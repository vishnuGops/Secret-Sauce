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
  // A decimal comma — `1,5` — but only with one or two digits after it. `1,000`
  // is a thousands separator, and reading it as `1.000` saved a kilo of flour
  // as one gram (Phase 38 review); it is refused instead.
  if (_decimalComma.hasMatch(text)) text = text.replaceFirst(',', '.');
  if (_decimal.hasMatch(text)) return _finite(double.tryParse(text));

  final slashed = _slashed.firstMatch(text);
  if (slashed != null) {
    final whole = int.tryParse(slashed.group(1) ?? '0');
    final numerator = int.tryParse(slashed.group(2)!);
    final denominator = int.tryParse(slashed.group(3)!);
    if (whole == null || numerator == null || denominator == null) return null;
    if (denominator == 0) return null;
    return _finite(whole + numerator / denominator);
  }

  final glyph = _glyph.firstMatch(text);
  if (glyph != null) {
    final whole = int.tryParse(glyph.group(1) ?? '0');
    if (whole == null) return null;
    return _finite(whole + _kVulgarFractions[glyph.group(2)!]!);
  }
  return null;
}

final _decimalComma = RegExp(r'^\d+,\d{1,2}$');

/// Null for a value too large to be a quantity: the parsers return null for
/// anything they cannot read, and a pasted run of digits must not throw from
/// inside a form validator (Phase 38 review).
double? _finite(double? v) => v == null || !v.isFinite ? null : v;

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
  if (RegExp(r'^\d+$').hasMatch(text)) {
    return _minutesOrNull(int.tryParse(text));
  }

  final clock = _clock.firstMatch(text);
  if (clock != null) {
    final hours = int.tryParse(clock.group(1)!);
    if (hours == null) return null;
    return _minutesOrNull(hours * 60 + int.parse(clock.group(2)!));
  }

  var minutes = 0.0;
  var consumed = 0;
  var terms = 0;
  for (final m in _durationTerm.allMatches(text)) {
    // Only spaces, commas or "and" may sit between two terms.
    final gap = text.substring(consumed, m.start).trim();
    if (gap.isNotEmpty && gap != ',' && gap != 'and') return null;
    final value = double.tryParse(m.group(1)!);
    if (value == null) return null;
    minutes += m.group(2)!.startsWith('h') ? value * 60 : value;
    consumed = m.end;
    terms++;
  }
  if (terms == 0 || text.substring(consumed).trim().isNotEmpty) return null;
  if (!minutes.isFinite) return null;
  return _minutesOrNull(minutes.round());
}

/// The longest duration a step, Prep or Cook may claim: a week. The columns
/// are `int`, so without a ceiling a pasted `3000000000` passed the form and
/// failed the save with a generic overflow; a week is longer than any
/// fermentation or cure a recipe here times, and past it the number is a typo.
const int kMaxDurationMinutes = 7 * 24 * 60;

int? _minutesOrNull(int? m) =>
    m == null || m < 0 || m > kMaxDurationMinutes ? null : m;
