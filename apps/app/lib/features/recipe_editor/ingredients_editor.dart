import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_editor/edit_models.dart';

/// The quantity rule, stated once. The row's validator reads it, and so does
/// the screen when it decides which collapsed rows a refused save has to open
/// (UX-039) — one predicate, so the two can never disagree about what is
/// wrong.
///
/// `ingredients_quantity_positive` (32a2) is the real guard; this is the same
/// rule stated where the cook can see it. Empty stays valid — a "to taste"
/// ingredient has no quantity, which is not the same as zero (B076: a zero
/// counts toward coverage while contributing nothing, and a negative one
/// *subtracts* from an estimated label). A fraction is a quantity (UX-052):
/// `1/2`, `1 1/2` and `½` all parse, and only what cannot be read at all is
/// refused — never silently saved as "no quantity".
String? ingredientQuantityError(EditIngredient ingredient) {
  if (ingredient.hasInvalidQuantity) {
    // `parseQuantity` reads no sign, so `-2` is unreadable to it — but the
    // cook's mistake there is the sign, and naming that is the useful answer.
    final text = ingredient.quantity.text.trim();
    if (text.startsWith('-') && parseQuantity(text.substring(1)) != null) {
      return 'Must be > 0';
    }
    return 'Try 1/2 or 0.5';
  }
  final value = ingredient.parsedQuantity;
  if (value != null && value <= 0) return 'Must be > 0';
  return null;
}

/// Whether a row holds anything a cook typed — what makes removing its group
/// worth a question.
bool _hasContent(EditIngredient i) =>
    [i.quantity, i.unit, i.name, i.note].any((c) => c.text.trim().isNotEmpty);

/// The ingredients half of the editor — groups, their rows, and the buttons
/// that add, remove and reorder both. One of the two natural seams in what was
/// an 880-line screen (OPT-A8).
///
/// Stateless on purpose: the draft lives in `_RecipeEditorScreenState`, and
/// every mutation here calls [onChanged] so the one `setState` that owns the
/// form runs. The only state below this widget is presentational — whether a
/// row is open on a phone, whether its note line is revealed — and changing it
/// is deliberately **not** an edit: it rebuilds the row without reporting
/// through [onChanged], so opening a row and closing it again does not make
/// the editor ask "Discard changes?" on the way out (B085).
class IngredientsEditor extends StatelessWidget {
  const IngredientsEditor({
    super.key,
    required this.groups,
    required this.onChanged,
  });

  final List<EditIngredientGroup> groups;
  final VoidCallback onChanged;

  /// Removes [group], asking first when it holds anything (UX-052): a whole
  /// group of typed ingredients went with one tap and no undo.
  ///
  /// Remove, rebuild, *then* dispose (32c4). Disposing first leaves
  /// controllers that a still-mounted `TextField` is attached to; the
  /// post-frame callback is what makes that an ordering rather than a
  /// tolerance — by the time it runs the rows' elements are gone. Keyed on the
  /// group object, not its index: the dialog is an `await`, and an index is
  /// only a promise about the list as it was before it.
  Future<void> _removeGroup(
    BuildContext context,
    EditIngredientGroup group,
  ) async {
    final filled = group.ingredients.where(_hasContent).length;
    if (filled > 0) {
      final remove = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Remove this group?'),
              content: Text(
                'Its ${countOf(filled, 'ingredients')} will be removed too.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Keep'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Remove'),
                ),
              ],
            ),
      );
      // A disposed editor has already disposed this group with the rest.
      if (remove != true || !context.mounted) return;
    }
    if (!groups.remove(group)) return;
    onChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) => group.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ingredients', style: Theme.of(context).textTheme.titleLarge),
        for (final group in groups)
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
                          controller: group.name,
                          decoration: const InputDecoration(
                            labelText: 'Group name (optional)',
                            hintText: 'e.g. For the sauce',
                          ),
                        ),
                      ),
                      if (groups.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          // UX-047: without it this is an unnamed button.
                          tooltip: 'Remove group',
                          onPressed: () => _removeGroup(context, group),
                        ),
                    ],
                  ),
                  _IngredientList(group: group, onChanged: onChanged),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        // Starts open: a new row has nothing to summarise.
                        group.ingredients.add(EditIngredient());
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

/// One group's rows, reorderable two ways: a drag handle for a pointer, and a
/// per-row **Move up / Move down** menu for a keyboard or a screen reader — a
/// drag is not something either can perform, so the handle must never be the
/// only way (UX-035).
///
/// The order *is* the data: `EditIngredientGroup.toModel()` writes each row's
/// list index as its `sort_order`, ascending (B022), so moving a row here is
/// all a save needs to persist the new order.
class _IngredientList extends StatelessWidget {
  const _IngredientList({required this.group, required this.onChanged});

  final EditIngredientGroup group;
  final VoidCallback onChanged;

  void _move(int from, int to) {
    final rows = group.ingredients;
    if (from == to || to < 0 || to >= rows.length) return;
    rows.insert(to, rows.removeAt(from));
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final rows = group.ingredients;
    // The page scrolls, not this list: it lays out at its full height inside
    // the editor's one scroll view.
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      buildDefaultDragHandles: false,
      // `onReorderItem` hands over the index the row lands at *after* its
      // removal, so it is a plain remove-then-insert.
      onReorderItem: _move,
      children: [
        for (var ii = 0; ii < rows.length; ii++)
          _IngredientRow(
            key: ObjectKey(rows[ii]),
            ingredient: rows[ii],
            index: ii,
            count: rows.length,
            onChanged: onChanged,
            onMove: (delta) => _move(ii, ii + delta),
            // Same remove-rebuild-dispose order as a group (32c4).
            onRemove: () {
              final removed = rows.removeAt(ii);
              onChanged();
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => removed.dispose(),
              );
            },
          ),
      ],
    );
  }
}

class _IngredientRow extends ConsumerStatefulWidget {
  const _IngredientRow({
    super.key,
    required this.ingredient,
    required this.index,
    required this.count,
    required this.onChanged,
    required this.onMove,
    required this.onRemove,
  });

  final EditIngredient ingredient;

  /// This row's place in its group, and the group's size — for the drag
  /// listener and for which of Move up / Move down is available.
  final int index;
  final int count;

  final VoidCallback onChanged;

  /// Moves the row by one place: -1 up, +1 down.
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;

  @override
  ConsumerState<_IngredientRow> createState() => _IngredientRowState();
}

class _IngredientRowState extends ConsumerState<_IngredientRow> {
  /// Fixed widths of the quantity and unit fields.
  static const double _quantityWidth = 64;
  static const double _unitWidth = 72;

  /// The typeahead dropdown: its lift and its largest extent.
  static const double _suggestionsElevation = 4;
  static const double _suggestionsMaxHeight = 240;
  static const double _suggestionsMaxWidth = 320;

  /// The room a Name field needs before it is worth sharing a line with the
  /// quantity and unit, at 1.0× text — scaled with the text below.
  static const double _nameMinWidth = 120;

  EditIngredient get _ingredient => widget.ingredient;

  /// Reordering needs somewhere to move to.
  bool get _reorderable => widget.count > 1;

  /// Below this the quantity/unit/name row cannot hold a usable Name field:
  /// its fixed children (two sized fields, the icon buttons, the handle and
  /// two gaps) do not shrink with the text scale while the space a name needs
  /// grows with it. Narrower than this the row splits in two so the name gets
  /// the full width instead of eight pixels of it.
  double _wideThreshold(BuildContext context, int actionCount) {
    final fixed =
        (_reorderable ? kMinInteractiveDimension : 0) +
        _quantityWidth +
        AppSpacing.sm +
        _unitWidth +
        AppSpacing.sm +
        actionCount * kMinInteractiveDimension;
    return fixed +
        _nameMinWidth * (MediaQuery.textScalerOf(context).scale(16) / 16);
  }

  /// Typeahead matches for the name field (Phase 29b) — a hint surface, never
  /// a gate. Anything that stops a lookup (query too short, the registry
  /// unreachable, signed-out `42501`) resolves to no suggestions and the cook
  /// keeps typing free text; that is why the failure path is silent rather
  /// than routed through `friendlyError` — there is no error state to show,
  /// the feature simply is not adding hints right now.
  Future<Iterable<FoodHit>> _search(String raw) async {
    final query = raw.trim();
    if (query.length < 2) return const Iterable<FoodHit>.empty();
    // Debounce: wait, then only fire if the cook has stopped on this query.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (query != _ingredient.name.text.trim()) {
      return const Iterable<FoodHit>.empty();
    }
    try {
      return await ref.read(foodRepositoryProvider).search(query);
    } catch (_) {
      return const Iterable<FoodHit>.empty();
    }
  }

  /// Opening or closing a row is layout, not an edit — a local rebuild, never
  /// the editor's `onChanged` (see [IngredientsEditor]).
  void _setEditing(bool editing) =>
      setState(() => _ingredient.editing = editing);

  /// `Done` closes the row only when what it would hide is valid: collapsing
  /// an unreadable quantity into a summary would hide the one thing wrong.
  void _done(FormFieldState<String> field) {
    if (field.validate()) _setEditing(false);
  }

  /// The pointer's way to reorder. Not a button — a screen reader or a
  /// keyboard cannot drag — so it stays out of the semantics tree and the
  /// row's menu carries the same moves.
  Widget _dragHandle(ColorScheme scheme) => ReorderableDragStartListener(
    index: widget.index,
    child: Tooltip(
      message: 'Drag to reorder',
      excludeFromSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: SizedBox.square(
          dimension: kMinInteractiveDimension,
          child: Icon(Icons.drag_indicator, color: scheme.onSurfaceVariant),
        ),
      ),
    ),
  );

  /// The keyboard and screen-reader way to reorder (the drag handle's twin).
  Widget _reorderMenu() => PopupMenuButton<int>(
    tooltip: 'Move ingredient',
    icon: const Icon(Icons.swap_vert, size: AppIconSize.button),
    useRootNavigator: true,
    onSelected: widget.onMove,
    itemBuilder:
        (_) => [
          PopupMenuItem(
            value: -1,
            enabled: widget.index > 0,
            child: const Text('Move up'),
          ),
          PopupMenuItem(
            value: 1,
            enabled: widget.index < widget.count - 1,
            child: const Text('Move down'),
          ),
        ],
  );

  @override
  Widget build(BuildContext context) {
    // Read here, not inside the FormField's builder: the dependency belongs to
    // this row, which is what has to rebuild when the window crosses 600.
    final compact = context.isCompact;
    return FormField<String>(
      // Registered with the Form whether the row is open or collapsed, so a
      // collapsed row with an unreadable quantity still refuses the save — the
      // screen then opens it to show why (UX-039).
      validator: (_) => ingredientQuantityError(_ingredient),
      builder: (field) {
        final collapsed = compact && !_ingredient.editing;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (collapsed) _summary(context) else _fields(context, field),
              if (field.hasError) _error(context, field.errorText!),
              if (!collapsed) ..._extras(context),
              if (!collapsed && compact)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _done(field),
                    child: const Text('Done'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The quantity's message on its own line under the row, not inside the
  /// 64px field — there it clipped to a letter or two at 2.0× (UX-052). The
  /// field itself still turns red.
  Widget _error(BuildContext context, String message) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        top: AppSpacing.xs,
        left: _reorderable ? kMinInteractiveDimension : 0,
      ),
      // Heard with the field it belongs to; seen under the red field.
      child: Semantics(
        liveRegion: true,
        label: 'Quantity: $message',
        excludeSemantics: true,
        child: Text(
          message,
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    );
  }

  /// A saved row on a phone, as one line (UX-039: one ingredient took ~4 rows,
  /// so ten were several screens). Printed through core's one ingredient
  /// chain — `ingredientOneLine`, the same words the recipe page prints — and
  /// read aloud through its spoken twin, so a fraction is not announced as
  /// "fraction slash" (B066's rule: never a second formatter).
  Widget _summary(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final model = _ingredient.toModel(0);
    final line = ingredientOneLine(model);
    final note = model.note ?? '';
    final markers = [
      // A note that stands in for the quantity ("to taste") is already in
      // `line`; printing it twice is the duplication B066 removed.
      if (note.isNotEmpty && !ingredientNoteIsQuantity(model)) note,
      if (model.isOptional) 'optional',
    ];
    final details = markers.join(' · ');
    final spoken = [
      line.isEmpty ? 'unnamed ingredient' : ingredientOneLineSpoken(model),
      ...markers,
      if (model.foodId != null) 'linked to a food',
    ].join(', ');

    return Row(
      children: [
        if (_reorderable) _dragHandle(scheme),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Edit $spoken',
            onTap: () => _setEditing(true),
            excludeSemantics: true,
            child: InkWell(
              onTap: () => _setEditing(true),
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: kMinInteractiveDimension,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              line.isEmpty ? 'Unnamed ingredient' : line,
                              style: textTheme.bodyLarge,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (details.isNotEmpty)
                              Text(
                                details,
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      if (model.foodId != null)
                        Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.xs),
                          child: Icon(
                            Icons.link,
                            size: AppIconSize.sm,
                            color: scheme.primary,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xs),
                        child: Icon(
                          Icons.edit_outlined,
                          size: AppIconSize.sm,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_reorderable) _reorderMenu(),
      ],
    );
  }

  /// The open row: quantity, unit, name and the row's actions.
  Widget _fields(BuildContext context, FormFieldState<String> field) {
    final scheme = Theme.of(context).colorScheme;
    final marked =
        _ingredient.note.text.trim().isNotEmpty || _ingredient.isOptional;

    final quantity = SizedBox(
      width: _quantityWidth,
      child: TextField(
        controller: _ingredient.quantity,
        // A full keyboard, not a numeric one: the numeric keypads have no `/`,
        // and `1/2` is how most cooks write half (UX-052).
        keyboardType: TextInputType.text,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: 'Qty',
          isDense: true,
          // Red, but wordless: the message is a line of its own under the
          // row (see [_error]). A zero-height error adds no subtext band, so
          // the field stays level with Unit and Name.
          error: field.hasError ? const SizedBox.shrink() : null,
        ),
        // Once the field has complained, clear the complaint as soon as the
        // entry reads — not only on the next Save.
        onChanged: (_) {
          if (field.hasError) field.validate();
        },
      ),
    );
    final unit = SizedBox(
      width: _unitWidth,
      child: TextField(
        controller: _ingredient.unit,
        decoration: const InputDecoration(labelText: 'Unit', isDense: true),
      ),
    );
    // The name is free text with a registry typeahead over it: picking a
    // suggestion writes the display name AND the invisible food link; typing
    // past the dropdown is never blocked. The overlay attaches at this
    // widget's position, so the field itself is what RawAutocomplete wraps.
    final name = RawAutocomplete<FoodHit>(
      textEditingController: _ingredient.name,
      focusNode: _ingredient.nameFocus,
      displayStringForOption: (hit) => hit.displayName,
      optionsBuilder: (value) => _search(value.text),
      onSelected: (hit) {
        _ingredient.foodId = hit.id;
        _ingredient.foodLabel = hit.displayName;
        widget.onChanged();
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
              elevation: _suggestionsElevation,
              borderRadius: BorderRadius.circular(AppRadii.md),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: _suggestionsMaxHeight,
                  maxWidth: _suggestionsMaxWidth,
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
        icon: const Icon(Icons.notes, size: AppIconSize.button),
        color: marked ? scheme.primary : null,
        tooltip: 'Note & optional',
        // Revealing a line is layout, not an edit (see [IngredientsEditor]).
        onPressed:
            () => setState(
              () => _ingredient.showDetails = !_ingredient.showDetails,
            ),
      ),
      if (_reorderable) _reorderMenu(),
      IconButton(
        icon: const Icon(Icons.close, size: AppIconSize.button),
        tooltip: 'Remove ingredient',
        onPressed: widget.onRemove,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideThreshold(context, actions.length)) {
          return Row(
            children: [
              if (_reorderable) _dragHandle(scheme),
              quantity,
              const SizedBox(width: AppSpacing.sm),
              unit,
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: name),
              ...actions,
            ],
          );
        }
        // Handle, quantity and unit keep their sized boxes on their own line;
        // the actions ride with the name, which is the only child that can
        // give ground.
        return Column(
          children: [
            Row(
              children: [
                if (_reorderable) _dragHandle(scheme),
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
    );
  }

  /// What an open row carries below its fields: the food link and the
  /// note/optional line.
  List<Widget> _extras(BuildContext context) => [
    // The link chip sits on its own line rather than inside the row above —
    // that row is already at its width budget (Gotcha 26 is the receipt), and
    // a chip whose label is a food name cannot share a line with three fields
    // at 320px x 2.0x. Flexible + ellipsis so a long display name shrinks
    // instead of overflowing.
    if (_ingredient.foodId != null)
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(
          children: [
            Flexible(
              child: InputChip(
                avatar: const Icon(Icons.link, size: AppIconSize.sm),
                label: Text(
                  _ingredient.foodLabel ?? 'Linked',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                visualDensity: VisualDensity.compact,
                deleteButtonTooltipMessage: 'Remove link',
                onDeleted: () {
                  _ingredient.foodId = null;
                  _ingredient.foodLabel = null;
                  widget.onChanged();
                },
              ),
            ),
          ],
        ),
      ),
    if (_ingredient.showDetails)
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
              controller: _ingredient.note,
              decoration: const InputDecoration(
                labelText: 'Note',
                hintText: 'e.g. finely chopped',
                isDense: true,
              ),
            ),
            // A checkbox rather than a chip: a chip sizes to its label, and
            // "Optional" at 2.0x text scale is wider than a 320px phone leaves
            // here. This row's label can ellipsise.
            InkWell(
              onTap: () {
                _ingredient.isOptional = !_ingredient.isOptional;
                widget.onChanged();
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _ingredient.isOptional,
                    onChanged: (v) {
                      _ingredient.isOptional = v ?? false;
                      widget.onChanged();
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
  ];
}
