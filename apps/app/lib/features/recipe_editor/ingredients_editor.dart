import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    super.key,
    required this.groups,
    required this.onChanged,
  });

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

class _IngredientRow extends ConsumerWidget {
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

  /// Typeahead matches for the name field (Phase 29b) — a hint surface, never
  /// a gate. Anything that stops a lookup (query too short, the registry
  /// unreachable, signed-out `42501`) resolves to no suggestions and the cook
  /// keeps typing free text; that is why the failure path is silent rather
  /// than routed through `friendlyError` — there is no error state to show,
  /// the feature simply is not adding hints right now.
  Future<Iterable<FoodHit>> _search(WidgetRef ref, String raw) async {
    final query = raw.trim();
    if (query.length < 2) return const Iterable<FoodHit>.empty();
    // Debounce: wait, then only fire if the cook has stopped on this query.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (query != ingredient.name.text.trim()) {
      return const Iterable<FoodHit>.empty();
    }
    try {
      return await ref.read(foodRepositoryProvider).search(query);
    } catch (_) {
      return const Iterable<FoodHit>.empty();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    // The name is free text with a registry typeahead over it: picking a
    // suggestion writes the display name AND the invisible food link; typing
    // past the dropdown is never blocked. The overlay attaches at this
    // widget's position, so the field itself is what RawAutocomplete wraps.
    final name = RawAutocomplete<FoodHit>(
      textEditingController: ingredient.name,
      focusNode: ingredient.nameFocus,
      displayStringForOption: (hit) => hit.displayName,
      optionsBuilder: (value) => _search(ref, value.text),
      onSelected: (hit) {
        ingredient.foodId = hit.id;
        ingredient.foodLabel = hit.displayName;
        onChanged();
      },
      fieldViewBuilder:
          (context, controller, focusNode, onFieldSubmitted) => TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: const InputDecoration(labelText: 'Name', isDense: true),
            onSubmitted: (_) => onFieldSubmitted(),
          ),
      optionsViewBuilder:
          (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(AppRadii.button),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 240,
                  maxWidth: 320,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final hit = options.elementAt(index);
                    return ListTile(
                      dense: true,
                      title: Text(
                        hit.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => onSelected(hit),
                    );
                  },
                ),
              ),
            ),
          ),
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
                  Row(children: [Expanded(child: name), ...actions]),
                ],
              );
            },
          ),
          // The link chip sits on its own line rather than inside the row
          // above — that row is already at its width budget (Gotcha 26 is the
          // receipt), and a chip whose label is a food name cannot share a line
          // with three fields at 320px x 2.0x. Flexible + ellipsis so a long
          // display name shrinks instead of overflowing.
          if (ingredient.foodId != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                children: [
                  Flexible(
                    child: InputChip(
                      avatar: const Icon(Icons.link, size: 16),
                      label: Text(
                        ingredient.foodLabel ?? 'Linked',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      visualDensity: VisualDensity.compact,
                      deleteButtonTooltipMessage: 'Remove link',
                      onDeleted: () {
                        ingredient.foodId = null;
                        ingredient.foodLabel = null;
                        onChanged();
                      },
                    ),
                  ),
                ],
              ),
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
