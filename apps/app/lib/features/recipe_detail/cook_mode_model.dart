/// Pure derivations behind cook mode — no widgets, no providers, no clock.
///
/// Cook mode walks a recipe one step at a time, but a recipe's steps are stored
/// **grouped** (`step_groups` → `steps`, both ordered ascending — B022), and the
/// grouping is not decoration: the progress bar is segmented by group and
/// weighted by step count, and the header says `Filling · step 1 of 3` rather
/// than `step 5 of 9`. So the walk needs a flat list that still remembers where
/// each step came from, which is what [CookStep] is.
///
/// Everything here is a function of the recipe and the current index, so it is
/// all directly testable — `apps/app/test/cook_mode_test.dart` is where the
/// interesting cases live.
library;

import 'package:core/core.dart';

/// One step, positioned twice: inside its group (what the cook is told) and
/// across the whole recipe (what the progress bar and the finish screen count).
class CookStep {
  const CookStep({
    required this.step,
    required this.groupName,
    required this.groupIndex,
    required this.indexInGroup,
    required this.groupStepCount,
    required this.overallIndex,
  });

  final RecipeStep step;

  /// The step group's name, already defaulted — never empty, so the header has
  /// something to print for a recipe whose single group is unnamed.
  final String groupName;

  final int groupIndex;

  /// 0-based position within the group; the UI prints `indexInGroup + 1`,
  /// because numbering restarts at 1 per group (that is how recipes are
  /// authored, and flattening it to 1..N loses the grouping).
  final int indexInGroup;

  final int groupStepCount;

  /// 0-based position across every group, in reading order.
  final int overallIndex;

  /// `Filling · step 1 of 3`, or just `Step 1 of 3` when the recipe has one
  /// unnamed group and the group label would be noise.
  String headerLabel({required bool showGroup}) =>
      showGroup
          ? '$groupName · step ${indexInGroup + 1} of $groupStepCount'
          : 'Step ${indexInGroup + 1} of $groupStepCount';
}

/// Flattens [recipe]'s grouped steps into the order they are cooked in.
///
/// Groups with no steps are skipped entirely — they would otherwise contribute
/// a zero-width progress segment and a group heading for nothing.
List<CookStep> flattenCookSteps(Recipe recipe) {
  final out = <CookStep>[];
  var groupIndex = 0;
  for (final group in recipe.stepGroups) {
    if (group.steps.isEmpty) continue;
    final name = group.name.isEmpty ? 'Steps' : group.name;
    for (var i = 0; i < group.steps.length; i++) {
      out.add(
        CookStep(
          step: group.steps[i],
          groupName: name,
          groupIndex: groupIndex,
          indexInGroup: i,
          groupStepCount: group.steps.length,
          overallIndex: out.length,
        ),
      );
    }
    groupIndex++;
  }
  return out;
}

/// One bar of the segmented progress indicator: a group, weighted by how many
/// steps it holds.
class CookSegment {
  const CookSegment({
    required this.name,
    required this.stepCount,
    required this.fill,
  });

  final String name;
  final int stepCount;

  /// 0..1 — the fraction of this group's steps that are **behind** the cook.
  final double fill;
}

/// The progress segments for [steps] with the cook standing on [currentIndex].
///
/// `fill` counts steps *completed*, so the group you are standing in is
/// `indexInGroup / stepCount` — landing on the first step of a group fills
/// nothing, and the bar only completes when you leave the group's last step.
/// (The canvas draws both readings across two frames; this is the one that
/// does not claim credit for a step still in front of you.)
List<CookSegment> cookSegments(List<CookStep> steps, int currentIndex) {
  if (steps.isEmpty) return const [];
  final byGroup = <int, List<CookStep>>{};
  for (final s in steps) {
    byGroup.putIfAbsent(s.groupIndex, () => []).add(s);
  }
  final keys = byGroup.keys.toList()..sort();
  return [
    for (final k in keys)
      CookSegment(
        name: byGroup[k]!.first.groupName,
        stepCount: byGroup[k]!.length,
        fill:
            byGroup[k]!.where((s) => s.overallIndex < currentIndex).length /
            byGroup[k]!.length,
      ),
  ];
}

/// Words that appear in ingredient names but say nothing about *which*
/// ingredient, so matching on them would attach half the list to every step.
const _kIngredientStopWords = <String>{
  'and',
  'for',
  'the',
  'with',
  'plain',
  'fresh',
  'large',
  'small',
  'whole',
  'ground',
  'chopped',
  'sliced',
  'minced',
  'grated',
  'shredded',
  'trimmed',
  'cold',
  'warm',
  'room',
  'temperature',
  'optional',
  'taste',
  'thinly',
  'finely',
  'extra',
  'unbleached',
};

final _kWordSplit = RegExp(r'[^a-z0-9]+');

/// The ingredients [step] appears to call for, out of [all].
///
/// **There is no schema link between a step and an ingredient** — no
/// `step_ingredients` table, nothing on `steps` pointing at a row. The canvas
/// asks for "you'll need" chips on the step anyway, and the honest way to get
/// them without inventing a column is to read the step's own prose: an
/// ingredient matches when a distinctive word of its name appears in the step
/// text as a whole word.
///
/// Whole-word matching is what makes it safe rather than clever — `\bbutter\b`
/// does not fire on "buttermilk" and `\begg\b` does not fire on "eggplant" —
/// and [_kIngredientStopWords] drops the words ("chopped", "fresh") that would
/// otherwise attach an ingredient to every step that mentions chopping. Names
/// are matched word-by-word because the stored name is rarely the phrase the
/// step uses: "boneless chicken thigh" appears in prose as "the chicken".
///
/// Consequences worth knowing before relying on it: a step that names nothing
/// ("Serve with rice") returns empty and the panel is hidden, and a step that
/// says "add the remaining spices" gets nothing. It is a hint, never a
/// checklist — which is why cook mode also keeps a link to the full list.
List<Ingredient> stepIngredients(RecipeStep step, List<Ingredient> all) {
  final haystack = step.text.toLowerCase();
  if (haystack.isEmpty) return const [];
  final out = <Ingredient>[];
  for (final ing in all) {
    final words = ing.name
        .toLowerCase()
        .split(_kWordSplit)
        .where((w) => w.length >= 3 && !_kIngredientStopWords.contains(w));
    for (final w in words) {
      if (RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(haystack)) {
        out.add(ing);
        break;
      }
    }
  }
  return out;
}

/// `1:05` / `12:00` / `0:09` — a countdown, not a duration label.
///
/// Deliberately not [formatMinutes]: that reads `1 h 10 m` for a *fact* about a
/// recipe, and a running clock has to be scannable at a glance from across a
/// kitchen, which means fixed-width minutes and seconds. Negative clamps to
/// zero so an overshoot never renders `-0:01`.
String formatClock(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
