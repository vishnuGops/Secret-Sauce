/// Parsers for what a cook types into the recipe editor — the inverse of
/// `formatting.dart`, and kept beside it in core so the two are tested as a
/// pair: whatever [formatQuantity] or [formatMinutes] prints, these read back.
///
/// Both return **null for anything they cannot read**, and for empty input;
/// the caller decides whether empty is allowed (a "to taste" ingredient has no
/// quantity, a step with no timer has no duration) and turns a null from a
/// non-empty field into a message. Neither ever guesses: `int.tryParse` quietly
/// dropped `1h`, which saved a step with no timer and said nothing (UX-035).
library;

/// Unicode vulgar fractions a keyboard, a paste from a web recipe or our own
/// [formatQuantity] can put in a field.
const _kVulgarFractions = <String, double>{
  '½': 1 / 2,
  '⅓': 1 / 3,
  '⅔': 2 / 3,
  '¼': 1 / 4,
  '¾': 3 / 4,
  '⅕': 1 / 5,
  '⅖': 2 / 5,
  '⅗': 3 / 5,
  '⅘': 4 / 5,
  '⅙': 1 / 6,
  '⅚': 5 / 6,
  '⅛': 1 / 8,
  '⅜': 3 / 8,
  '⅝': 5 / 8,
  '⅞': 7 / 8,
};

final _decimal = RegExp(r'^(\d+(?:\.\d*)?|\.\d+)$');

/// `1 1/2`, `1-1/2`, `1/2`, and the same with U+2044 FRACTION SLASH, which is
/// what [formatQuantity] prints for thirds and eighths.
final _slashed = RegExp(r'^(?:(\d+)[\s-]+)?(\d+)\s*[/⁄]\s*(\d+)$');

/// `1½`, `1 ½`, `½`.
final _glyph = RegExp(r'^(\d+)?\s*([½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])$');

/// A quantity as a cook types it: `1.5`, `1,5`, `1/2`, `1 1/2`, `1-1/2`, `½`,
/// `1½`, `1 1⁄3`. Null for empty or unreadable input, and for a zero
/// denominator.
///
/// The result is what the column stores — a decimal (Gotcha 16: the servings
/// scaler multiplies a `numeric`, so `"1 1/4"` can never be the stored value).
double? parseQuantity(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  // A decimal comma, but only when it is the only separator: `1,5` is one and
  // a half; `1,500.5` is not a quantity anyone types into a 64px box.
  if (text.contains(',') && !text.contains('.')) {
    text = text.replaceFirst(',', '.');
  }
  if (_decimal.hasMatch(text)) return double.parse(text);

  final slashed = _slashed.firstMatch(text);
  if (slashed != null) {
    final whole = int.parse(slashed.group(1) ?? '0');
    final numerator = int.parse(slashed.group(2)!);
    final denominator = int.parse(slashed.group(3)!);
    if (denominator == 0) return null;
    return whole + numerator / denominator;
  }

  final glyph = _glyph.firstMatch(text);
  if (glyph != null) {
    final whole = int.parse(glyph.group(1) ?? '0');
    return whole + _kVulgarFractions[glyph.group(2)!]!;
  }
  return null;
}

final _clock = RegExp(r'^(\d+):([0-5]\d)$');

/// One `<number><unit>` term of a duration: `1h`, `1.5 hours`, `30 min`.
final _durationTerm = RegExp(
  r'(\d+(?:\.\d+)?)\s*(hours|hour|hrs|hr|h|minutes|minute|mins|min|m)(?![a-z])',
);

/// A step time as a cook types it, in whole minutes: `90`, `1h`, `1h 30m`,
/// `1 h 30 min`, `1.5 hours`, `2 hours 15 minutes`, `1:30`. Reads back every
/// form [formatMinutes] prints. Null for empty or unreadable input — including
/// a string with anything left over after its terms, so `1h 30x` is refused
/// rather than read as an hour.
int? parseDurationMinutes(String raw) {
  final text = raw.trim().toLowerCase();
  if (text.isEmpty) return null;
  if (RegExp(r'^\d+$').hasMatch(text)) return int.parse(text);

  final clock = _clock.firstMatch(text);
  if (clock != null) {
    return int.parse(clock.group(1)!) * 60 + int.parse(clock.group(2)!);
  }

  var minutes = 0.0;
  var consumed = 0;
  var terms = 0;
  for (final m in _durationTerm.allMatches(text)) {
    // Only spaces, commas or "and" may sit between two terms.
    final gap = text.substring(consumed, m.start).trim();
    if (gap.isNotEmpty && gap != ',' && gap != 'and') return null;
    final value = double.parse(m.group(1)!);
    minutes += m.group(2)!.startsWith('h') ? value * 60 : value;
    consumed = m.end;
    terms++;
  }
  if (terms == 0 || text.substring(consumed).trim().isNotEmpty) return null;
  return minutes.round();
}
