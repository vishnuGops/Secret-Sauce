/// Small display helpers shared by the UI layers.
///
/// Deliberately hand-rolled rather than pulling in `intl`: the only thing
/// needed is thousands grouping, and the app has no localization story yet
/// (every label in the product is a fixed English string). If locale-aware
/// formatting ever lands, this is the one place to replace.
library;

import 'package:core/src/models/ingredient.dart';

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

/// `70` → `1 h 10 m`, `40` → `40 min`, `120` → `2 h`, `0`/negative → `—`.
///
/// The recipe-detail facts strip reads durations side by side, so hours are
/// split out instead of showing `70 min`. Chips inside a step keep the raw
/// `N min` form — a step long enough to need hours is a data problem, not a
/// formatting one.
String formatMinutes(int minutes) {
  if (minutes <= 0) return '—';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  if (rest == 0) return '$hours h';
  return '$hours h $rest m';
}

/// `Plain yoghurt` from `plain yoghurt`.
///
/// Ingredient names are stored lowercase and capitalised at render, because in a
/// quantity/name grid the capital is the left edge of the scanned column. Doing
/// it here rather than in the widget is what stops the two surfaces that draw
/// that grid — the reading page's rail and cook mode's rail — from disagreeing.
String sentenceCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Trims a scaled quantity to the shortest honest decimal: `2`, `1.5`, `1.25`.
String _trimQuantity(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
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
/// [factor] scales the number only — never the unit, and callers must never pass
/// it to a duration or a temperature, which do not scale with servings.
String ingredientQuantityLabel(Ingredient ingredient, {double factor = 1}) {
  final unit = ingredient.unit;
  final hasUnit = (unit ?? '').isNotEmpty;
  final quantity = ingredient.quantity;
  if (quantity == null) {
    if (hasUnit) return unit!;
    final note = ingredient.note;
    return (note ?? '').isEmpty ? '—' : note!;
  }
  final amount = _trimQuantity(quantity * factor);
  return hasUnit ? '$amount $unit' : amount;
}

/// `1.5 cup yoghurt` — the gutter label and the name on one line, for places
/// too narrow for a two-column grid (cook mode's chips). Drops the `—` rather
/// than printing a dash in front of a name.
String ingredientOneLine(Ingredient ingredient, {double factor = 1}) {
  final qty = ingredientQuantityLabel(ingredient, factor: factor);
  final name = sentenceCase(ingredient.name);
  return qty == '—' ? name : '$qty $name';
}

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
