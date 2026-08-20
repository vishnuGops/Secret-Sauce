/// Small display helpers shared by the UI layers.
///
/// Deliberately hand-rolled rather than pulling in `intl`: the only thing
/// needed is thousands grouping, and the app has no localization story yet
/// (every label in the product is a fixed English string). If locale-aware
/// formatting ever lands, this is the one place to replace.
library;

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
