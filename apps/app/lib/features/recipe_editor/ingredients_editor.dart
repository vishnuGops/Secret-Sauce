import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:app/features/recipe_editor/edit_models.dart';

/// The ingredients half of the editor — groups, their rows, and the buttons
/// that add and remove both. One of the two natural seams in what was an
/// 880-line screen (OPT-A8).
///
/// Stateless on purpose: the draft lives in `_RecipeEditorScreenState`, and
/// every mutation here calls [onChanged] so the one `setState` that owns the
/// form runs. Splitting the file did not change that ownership.
class IngredientsEditor extends StatelessWidget {
  const IngredientsEditor({
    super.key,required this.groups, required this.onChanged});

  final List<EditIngredientGroup> groups;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ingredients', style: Theme.of(context).textTheme.titleLarge),
        for (var gi = 0; gi < groups.length; gi++)
          Card(
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: groups[gi].name,
                          decoration: const InputDecoration(
                            labelText: 'Group name (optional)',
                            hintText: 'e.g. For the sauce',
                          ),
                        ),
                      ),
                      if (groups.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            groups[gi].dispose();
                            groups.removeAt(gi);
                            onChanged();
                          },
                        ),
                    ],
                  ),
                  for (var ii = 0; ii < groups[gi].ingredients.length; ii++)
                    _IngredientRow(
                      ingredient: groups[gi].ingredients[ii],
                      onChanged: onChanged,
                      onRemove: () {
                        groups[gi].ingredients[ii].dispose();
                        groups[gi].ingredients.removeAt(ii);
                        onChanged();
                      },
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        groups[gi].ingredients.add(EditIngredient());
                        onChanged();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add ingredient'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () {
            groups.add(EditIngredientGroup());
            onChanged();
          },
          icon: const Icon(Icons.add),
          label: const Text('Add ingredient group'),
        ),
      ],
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.ingredient,
    required this.onChanged,
    required this.onRemove,
  });

  final EditIngredient ingredient;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  /// Below this the quantity/unit/name row cannot hold a usable Name field:
  /// its fixed children (two sized fields, two icon buttons, two gaps) come to
  /// 248px, and the icon buttons do not shrink with the text scale while the
  /// space a name needs grows with it. Narrower than this the row splits in
  /// two so the name gets the full width instead of eight pixels of it.
  static double _wideThreshold(BuildContext context) =>
      248 + 120 * (MediaQuery.textScalerOf(context).scale(16) / 16);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final marked =
        ingredient.note.text.trim().isNotEmpty || ingredient.isOptional;

    final quantity = SizedBox(
      width: 64,
      child: TextField(
        controller: ingredient.quantity,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Qty', isDense: true),
      ),
    );
    final unit = SizedBox(
      width: 72,
      child: TextField(
        controller: ingredient.unit,
        decoration: const InputDecoration(labelText: 'Unit', isDense: true),
      ),
    );
    final name = TextField(
      controller: ingredient.name,
      decoration: const InputDecoration(labelText: 'Name', isDense: true),
    );
    final actions = [
      IconButton(
        icon: const Icon(Icons.notes, size: 18),
        color: marked ? scheme.primary : null,
        tooltip: 'Note & optional',
        onPressed: () {
          ingredient.showDetails = !ingredient.showDetails;
          onChanged();
        },
      ),
      IconButton(
        icon: const Icon(Icons.close, size: 18),
        tooltip: 'Remove ingredient',
        onPressed: onRemove,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= _wideThreshold(context)) {
                return Row(
                  children: [
                    quantity,
                    const SizedBox(width: AppSpacing.sm),
                    unit,
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: name),
                    ...actions,
                  ],
                );
              }
              // Quantity and unit keep their sized boxes on their own line;
              // the actions ride with the name, which is the only child that
              // can give ground.
              return Column(
                children: [
                  Row(
                    children: [
                      quantity,
                      const SizedBox(width: AppSpacing.sm),
                      unit,
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(child: name),
                      ...actions,
                    ],
                  ),
                ],
              );
            },
          ),
          if (ingredient.showDetails)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.sm,
                top: AppSpacing.xs,
                bottom: AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: ingredient.note,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      hintText: 'e.g. finely chopped',
                      isDense: true,
                    ),
                  ),
                  // A checkbox rather than a chip: a chip sizes to its label,
                  // and "Optional" at 2.0x text scale is wider than a 320px
                  // phone leaves here. This row's label can ellipsise.
                  InkWell(
                    onTap: () {
                      ingredient.isOptional = !ingredient.isOptional;
                      onChanged();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: ingredient.isOptional,
                          onChanged: (v) {
                            ingredient.isOptional = v ?? false;
                            onChanged();
                          },
                        ),
                        const Flexible(
                          child: Text(
                            'Optional',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
