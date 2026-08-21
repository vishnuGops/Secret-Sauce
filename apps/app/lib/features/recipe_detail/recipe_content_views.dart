import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:app/features/recipe_detail/detail_chips.dart';

/// The two read-only renderings of a recipe's content: an ingredient group
/// scaled to the chosen servings, and a numbered step group with its
/// time/temperature/tip chips. Split out of `recipe_detail_screen.dart`
/// (OPT-A8) — they are the largest block in it and depend on nothing but the
/// models.

class IngredientGroupView extends StatelessWidget {
  const IngredientGroupView({
    super.key,required this.group, required this.factor});

  final IngredientGroup group;
  final double factor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.name.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 4),
            child: Text(group.name,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
        for (final ing in group.ingredients)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6, right: 8),
                  child: Icon(Icons.circle, size: 6),
                ),
                Expanded(
                  child: Text(
                    _format(ing),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _format(Ingredient ing) {
    final parts = <String>[];
    if (ing.quantity != null) {
      final scaled = ing.quantity! * factor;
      parts.add(_trim(scaled));
    }
    if (ing.unit != null && ing.unit!.isNotEmpty) parts.add(ing.unit!);
    parts.add(ing.name);
    var text = parts.join(' ');
    if (ing.note != null && ing.note!.isNotEmpty) text += ' (${ing.note})';
    if (ing.isOptional) text += ' — optional';
    return text;
  }

  String _trim(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}

class StepGroupView extends StatelessWidget {
  const StepGroupView({
    super.key,required this.group});

  final StepGroup group;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.name.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 4),
            child: Text(group.name,
                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
        for (var i = 0; i < group.steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 14, child: Text('${i + 1}')),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.steps[i].text, style: textTheme.bodyLarge),
                      _StepMeta(step: group.steps[i]),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepMeta extends StatelessWidget {
  const _StepMeta({required this.step});
  final RecipeStep step;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (step.durationMinutes != null)
        MetaChip(icon: Icons.timer, label: '${step.durationMinutes} min'),
      if (step.temperature != null && step.temperature!.isNotEmpty)
        MetaChip(icon: Icons.thermostat, label: step.temperature!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: AppSpacing.sm, children: chips),
          ),
        if (step.tip != null && step.tip!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Tip: ${step.tip}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
      ],
    );
  }
}
