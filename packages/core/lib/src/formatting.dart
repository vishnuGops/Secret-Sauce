/// Small display helpers shared by the UI layers.
///
/// Deliberately hand-rolled rather than pulling in `intl`: the only thing
/// needed is thousands grouping, and the app has no localization story yet
/// (every label in the product is a fixed English string). If locale-aware
/// formatting ever lands, this is the one place to replace.
library;

import 'package:core/src/models/ingredient.dart';
import 'package:core/src/unit_forms.dart';

/// Groups a whole number with commas — `1980` becomes `1,980`.
///
/// Negative values keep their sign. Counts are never negative in this schema,
/// but the helper is also used for score gaps, which are clamped rather than
/// trusted.
String groupedCount(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}

/// The right noun for [count] — `1 recipe`, `2 recipes`.
///
/// Takes the **plural** and strips the trailing `s` at one, because every noun
/// this product counts (recipes, likes, saves, views, chefs) is a regular
/// plural. An irregular one would need its own singular passed in; there is no
/// such counter today, and inventing the machinery for a case that does not
/// exist is how a formatting helper turns into a localization library.
///
/// `1 recipes` shipped on the leaderboard's first render (B031), which is why
/// this is one shared helper rather than a closure inside whichever widget
/// happens to need it.
String pluralNoun(int count, String plural) =>
    count == 1 ? plural.substring(0, plural.length - 1) : plural;

/// [pluralNoun] with the grouped count in front — `1,980 likes`.
String countOf(int count, String plural) =>
    '${groupedCount(count)} ${pluralNoun(count, plural)}';

const _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `Mar 2025` — the resolution a "joined" or "member since" line wants.
///
/// English month abbreviations, like every other label in the product (see the
/// library note above): `intl` would buy locale-aware month names for an app
/// that has no other localized string in it.
String monthYear(DateTime date) => '${_kMonths[date.month - 1]} ${date.year}';

/// `2026-08-21` — ISO order, zero-padded.
///
/// Deliberately not `Mar 2025`'s cousin: a version history is a list of
/// **timestamps to compare**, and an ISO date sorts and scans by column. The two
/// formatters live together (OPT-A7) because they were hand-rolled one screen
/// apart, each private to its own widget.
String isoDate(DateTime date) =>
    '${date.year}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// `70` → `1 h 10 min`, `40` → `40 min`, `120` → `2 h`, `0`/negative → `—`.
///
/// **The** duration format (UX-043, DESIGN §2.1): the facts strip, the method
/// list's step chips and cook mode's "coming up" rail all read through here, so
/// one recipe no longer says `1 h 10 m`, `70 min` and `70 m` on three surfaces.
/// Hours are split out because durations are read side by side. A running
/// timer is the one exception — `formatClock` in cook mode is a countdown, not
/// a duration label.
///
/// [compact] — `1h 10m` — is the one exception, and it has exactly one caller,
/// `RecipeCard`'s time label. It is a **width** decision: the card is a fixed
/// tile whose metadata row caps the time label at its flex share, and at the
/// 288px floor that share is ~57px — `2 h 20 min` measures 57.1 and clips at
/// 1.0× text scale, `12 h 45 min` 62.1 (Manrope, measured in the Phase 37
/// review). Phase 37 tried the long form on the card and put this back.
/// Nothing else should pass it.
String formatMinutes(int minutes, {bool compact = false}) {
  if (minutes <= 0) return '—';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  if (compact) return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
  if (rest == 0) return '$hours h';
  return '$hours h $rest min';
}

/// `Plain yoghurt` from `plain yoghurt`.
///
/// Ingredient names are stored lowercase and capitalised at render, because in a
/// quantity/name grid the capital is the left edge of the scanned column. Doing
/// it here rather than in the widget is what stops the two surfaces that draw
/// that grid — the reading page's rail and cook mode's rail — from disagreeing.
String sentenceCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// The shortest honest decimal for [v]: `2`, `1.5`, `1.25`.
///
/// One implementation for the two places a stored `numeric` reaches a label —
/// a nutrition value, and an ingredient quantity that [formatQuantity] does not
/// set as a fraction (a metric unit, or a value near no eighth or third) — 32d2,
/// where the two bodies were byte-identical in two files. Two decimal places is the ceiling
/// in both: quantities are scaled by a servings ratio, nutrition data is never
/// finer, and `10.0 g` reads like a precision nobody entered.
String trimDecimal(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// Units a cook reads as decimals: SI mass, volume and length, every spelling
/// `nutritionData/units.json` accepts plus the ones it does not register
/// (`mg`, `cl`, `dl`, `mm`). Matched case-insensitively, so the display form
/// `L` and the lookup key `l` are one unit. Everything else — cups, spoons,
/// ounces, pounds, a bare count, a word unit like `cloves` — is read as a
/// fraction (UX-023).
const _kDecimalUnits = <String>{
  'mg', 'milligram', 'milligrams', //
  'g', 'gram', 'grams', //
  'kg', 'kilogram', 'kilograms', //
  'ml', 'millilitre', 'millilitres', 'milliliter', 'milliliters', //
  'cl', 'centilitre', 'centilitres', 'centiliter', 'centiliters', //
  'dl', 'decilitre', 'decilitres', 'deciliter', 'deciliters', //
  'l', 'litre', 'litres', 'liter', 'liters', //
  'mm', 'cm',
};

/// How far a scaled value may sit from an eighth or a third and still print as
/// one. Wide enough to absorb a stored `0.33` / `0.666` and a servings ratio's
/// float residue, narrow enough that `2.4 cup` (0.025 from `3⁄8`) stays `2.4`.
const _kFractionSnap = 0.02;

/// The three fractions Manrope draws as one glyph. Thirds and eighths have no
/// precomposed glyph in the bundled face, so they are set **flat** as digits
/// around U+2044 FRACTION SLASH (`1 1⁄3`). Manrope's `frac` feature does not
/// help: its GSUB ligates only ASCII `1/2`, `1/4` and `3/4` (measured, Phase
/// 37). A display face with a fuller `frac` would stack them.
const _kPrecomposedFractions = <String, String>{
  '1/2': '½',
  '1/4': '¼',
  '3/4': '¾',
};

/// U+2044 FRACTION SLASH — not `/`, which reads as a date or a ratio.
const _kFractionSlash = '⁄';

/// A quantity as a cook reads it in [unit]: `½ cup`, `1¼ tsp`, `1 1⁄3 cups`,
/// `3 cloves`, but `250 g` and `1.5 L` (UX-023).
///
/// Cups, spoons, ounces, pounds, bare counts and word units snap to the
/// nearest eighth or third when [v] is within [_kFractionSnap] of one; a value
/// that does not snap, and every metric unit, keeps [trimDecimal]. Called on
/// the **scaled** value, so `0.75 cup` doubled is `1½ cup`, and a servings
/// ratio's `2.0000001` is `2`. A tiny positive value that would snap to zero
/// keeps its decimal rather than printing `0`.
///
/// No space before a precomposed glyph (`1½`), a space before a slashed one
/// (`1 1⁄3`) — without it the whole part and the numerator run together as
/// `11⁄3`.
String formatQuantity(double v, String? unit) {
  final u = (unit ?? '').trim().toLowerCase();
  if (v <= 0 || _kDecimalUnits.contains(u)) return _decimalQuantity(v);

  final whole = v.floor();
  final rest = v - whole;
  var numerator = 0;
  var den = 1;
  var best = double.infinity;
  for (final d in const [8, 3]) {
    for (var n = 0; n <= d; n++) {
      final diff = (rest - n / d).abs();
      if (diff < best) {
        best = diff;
        numerator = n;
        den = d;
      }
    }
  }
  if (best > _kFractionSnap) return _decimalQuantity(v);
  if (numerator == den) return '${whole + 1}';
  if (numerator == 0) return whole == 0 ? _decimalQuantity(v) : '$whole';

  final g = numerator.gcd(den);
  final key = '${numerator ~/ g}/${den ~/ g}';
  final glyph = _kPrecomposedFractions[key];
  if (glyph != null) return whole == 0 ? glyph : '$whole$glyph';
  final slashed = '${numerator ~/ g}$_kFractionSlash${den ~/ g}';
  return whole == 0 ? slashed : '$whole $slashed';
}

/// [trimDecimal], except that a positive amount never prints as `0`: two
/// decimal places round a heavily scaled pinch (⅛ tsp in a 32-serving recipe
/// scaled to 1 is 0.004) to nothing, and "0 tsp" tells the cook to leave it
/// out. One significant figure keeps it visible.
String _decimalQuantity(double v) {
  final t = trimDecimal(v);
  return v > 0 && t == '0' ? v.toStringAsPrecision(1) : t;
}

/// True when [ingredient] has nothing but its note to put in a quantity column,
/// so the note *is* the quantity ("to taste") and must not also be printed
/// beside the name.
bool ingredientNoteIsQuantity(Ingredient ingredient) =>
    ingredient.quantity == null &&
    (ingredient.unit ?? '').isEmpty &&
    (ingredient.note ?? '').isNotEmpty;

/// What belongs in a fixed quantity gutter for [ingredient], scaled by [factor].
///
/// The chain is `quantity + unit` → `unit` → `note` → `—`, and every link is
/// reachable: `ingredients.quantity` is nullable, and the editor's quantity
/// field parses a decimal, so typing `1/2` fails the parse and saves a row with
/// a unit and no number. The unit outranks the note because a unit with no
/// number is a data defect worth seeing; the note then rides beside the name
/// instead (see [ingredientNoteIsQuantity]), so no combination silently drops a
/// half. Printing `—` and losing the unit was B066.
///
/// [factor] scales the number, and a word unit follows the number it ends up
/// beside: `1 clove` doubled is `2 cloves`, `2 cups` quartered is `½ cup`
/// (BL-10, B119). The unit is never *converted*, and callers must never pass
/// [factor] to a duration or a temperature, which do not scale with servings.
String ingredientQuantityLabel(Ingredient ingredient, {double factor = 1}) {
  final unit = ingredient.unit;
  final hasUnit = (unit ?? '').isNotEmpty;
  final quantity = ingredient.quantity;
  if (quantity == null) {
    if (hasUnit) return unit!;
    final note = ingredient.note;
    return (note ?? '').isEmpty ? '—' : note!;
  }
  final scaled = quantity * factor;
  final amount = formatQuantity(scaled, unit);
  return hasUnit ? '$amount ${_unitForAmount(unit!, scaled, amount)}' : amount;
}

/// [unit] in the number that fits [amount] — the label [formatQuantity] printed
/// for [value]. Singular at `1` and between 0 and 1 (`½ cup`, `1 clove`),
/// plural above 1 and at zero (`1½ cups`, `2 cloves`, `0 cups`).
///
/// Decided on the **printed** amount as well as the value, because the two
/// can disagree across 1: a scaled `1.01` snaps to `1` and must read `1 cup`,
/// not `1 cups`. A unit that does not change with quantity (`tbsp`, `g`, `L`),
/// or a spelling units.json does not know, comes back verbatim — so this can
/// only ever correct a word unit's number, never re-spell anything else.
/// The forms are [kUnitNumberForms], generated from `nutritionData/units.json`.
String _unitForAmount(String unit, double value, String amount) {
  final forms = kUnitNumberForms[unit.trim().toLowerCase()];
  if (forms == null) return unit;
  return amount == '1' || (value > 0 && value < 1) ? forms.$1 : forms.$2;
}

/// `1.5 cup yoghurt` — the gutter label and the name on one line, for places
/// too narrow for a two-column grid (cook mode's chips). Drops the `—` rather
/// than printing a dash in front of a name.
String ingredientOneLine(Ingredient ingredient, {double factor = 1}) {
  final qty = ingredientQuantityLabel(ingredient, factor: factor);
  final name = sentenceCase(ingredient.name);
  return qty == '—' ? name : '$qty $name';
}

/// The precomposed glyphs [formatQuantity] emits, as (numerator, denominator).
const _kGlyphFractions = <String, (int, int)>{
  '½': (1, 2),
  '¼': (1, 4),
  '¾': (3, 4),
};

/// Singular and plural names of the denominators [formatQuantity] can produce.
const _kDenominatorWords = <int, (String, String)>{
  2: ('half', 'halves'),
  3: ('third', 'thirds'),
  4: ('quarter', 'quarters'),
  8: ('eighth', 'eighths'),
};

String _spokenFraction(int numerator, int denominator) {
  final words = _kDenominatorWords[denominator];
  if (words == null) return '$numerator over $denominator';
  return '$numerator ${numerator == 1 ? words.$1 : words.$2}';
}

/// Whole-and-glyph (`1½`, or `1 ½` as a cook types it into a note) or a bare
/// glyph (`½`).
final _glyphPattern = RegExp(r'(?:(\d+) ?)?([½¼¾])');

/// Whole-and-slashed (`1 1⁄3`) or a bare slashed fraction (`2⁄3`).
final _slashedPattern = RegExp(r'(?:(\d+) )?(\d+)⁄(\d+)');

/// [text] with every fraction [formatQuantity] can print spelled out for a
/// screen reader: `1 1⁄3 cup` → `1 and 1 third cup`, `½ tsp` → `1 half tsp`,
/// `2¾ cups` → `2 and 3 quarters cups`.
///
/// A reader announced U+2044 as "fraction slash" — `1 1⁄3 cup` was "one one
/// fraction slash three cup" — and a precomposed `½` is read differently by
/// every engine. This is a **transform of the printed label**, not a second
/// formatter: the only way in is through [ingredientQuantityLabel] /
/// [ingredientOneLine], so what is heard can never disagree with what is shown
/// (B066). Everything that is not one of those fractions — the unit, a note,
/// an ingredient name, an ASCII `1/2` a cook typed into a note — passes through
/// untouched.
String spokenQuantity(String text) {
  return text
      .replaceAllMapped(_slashedPattern, (m) {
        final fraction = _spokenFraction(
          int.parse(m.group(2)!),
          int.parse(m.group(3)!),
        );
        final whole = m.group(1);
        return whole == null ? fraction : '$whole and $fraction';
      })
      .replaceAllMapped(_glyphPattern, (m) {
        final (n, d) = _kGlyphFractions[m.group(2)!]!;
        final fraction = _spokenFraction(n, d);
        final whole = m.group(1);
        return whole == null ? fraction : '$whole and $fraction';
      });
}

/// [ingredientQuantityLabel] as a screen reader should say it — the quantity
/// gutter's `Semantics` label.
String ingredientQuantitySpoken(Ingredient ingredient, {double factor = 1}) =>
    spokenQuantity(ingredientQuantityLabel(ingredient, factor: factor));

/// [ingredientOneLine] as a screen reader should say it — cook mode's chips.
String ingredientOneLineSpoken(Ingredient ingredient, {double factor = 1}) =>
    spokenQuantity(ingredientOneLine(ingredient, factor: factor));

/// Groups a score, keeping the single decimal place a `numeric` score can carry
/// (views contribute 0.2 each) and dropping it when the value is whole.
String groupedScore(double value) {
  if (value == value.roundToDouble()) return groupedCount(value.round());
  // Round first, then group: doing the arithmetic on the fraction by hand
  // carries the float error (0.2 * 3 is 0.6000000000000001) into the label.
  final text = value.toStringAsFixed(1);
  final dot = text.indexOf('.');
  final whole = int.parse(text.substring(0, dot));
  return '${groupedCount(whole)}${text.substring(dot)}';
}
