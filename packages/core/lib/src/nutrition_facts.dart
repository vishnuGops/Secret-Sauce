/// The arithmetic behind a nutrition-facts label: FDA reference daily values,
/// the `% Daily Value` column, and the value formatter.
///
/// Pure, and in `core` rather than in the widget that needed it first (the
/// OPT-A7 rule): the label is drawn by `NutritionFactsLabel` in `design_system`
/// today, and an editor preview or an export would compute the same numbers.
library;

/// FDA reference daily values for a 2,000-calorie diet — the same basis the
/// footnote on a real label states.
///
/// There is deliberately no entry for **calories** (a label prints no %DV for
/// them), **trans fat** (no established daily value), or **total sugars** (only
/// *added* sugars carry one). A caller asking for a percentage of something not
/// listed here is asking for a column the real label leaves blank.
const double kDvTotalFatG = 78;
const double kDvSaturatedFatG = 20;
const double kDvCholesterolMg = 300;
const double kDvSodiumMg = 2300;
const double kDvTotalCarbsG = 275;
const double kDvDietaryFiberG = 28;
const double kDvAddedSugarsG = 50;
const double kDvProteinG = 50;

/// [value] as a whole-percent share of [dailyValue], or `null` when there is
/// nothing to print.
///
/// Null in, null out — the label omits a row it has no value for rather than
/// printing a zero, so the absent case has to survive the arithmetic. A
/// non-positive [dailyValue] also returns null instead of dividing by zero;
/// that cannot happen with the constants above, but the guard is what keeps a
/// future caller from turning a bad constant into an `Infinity%`.
///
/// Rounded to the nearest whole percent, as printed labels are.
int? percentDailyValue(double? value, double dailyValue) {
  if (value == null || dailyValue <= 0) return null;
  return (value / dailyValue * 100).round();
}

/// A nutrient amount as the shortest honest decimal — `10`, `1.5`, `0.25`.
///
/// The same trimming `ingredientQuantityLabel` applies to a scaled quantity,
/// and for the same reason: a stored `numeric` round-trips as `10.0`, and
/// `10.0 g` on a label reads like a measurement precision nobody entered.
/// Two decimal places is the ceiling; nutrition data is never finer.
String formatNutritionValue(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
