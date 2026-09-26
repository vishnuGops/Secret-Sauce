import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:app/features/recipe_editor/edit_models.dart';

/// The steps half of the editor — the other seam (OPT-A8). Same contract as
/// `IngredientsEditor`: it renders the draft it is handed and reports every
/// mutation through [onChanged].
///
/// The one exception is the photo picker: choosing a file needs a platform
/// channel, a size guard and a snackbar, all of which live on the screen, so
/// this asks for it through [onPickImage] instead. Removing a photo is a plain
/// draft mutation and goes through [onChanged] like everything else.
class StepsEditor extends StatelessWidget {
  const StepsEditor({
    super.key,
    required this.groups,
    required this.onChanged,
    required this.onPickImage,
  });

  final List<EditStepGroup> groups;
  final VoidCallback onChanged;

  /// Asks the screen to pick (and later upload) a photo for this step.
  final void Function(EditStep step) onPickImage;

  /// Removes [group] — at once when it holds no written step, otherwise only
  /// after the cook confirms (UX-052): a section is the one delete in this
  /// editor that can take a dozen steps with it in a single tap.
  ///
  /// The group is found again by identity after the dialog, not by the index
  /// it had when the button was pressed: the list is the screen's, and nothing
  /// stops it changing while the dialog is up.
  Future<void> _removeGroup(BuildContext context, EditStepGroup group) async {
    final written = group.steps.where((s) => s.text.text.trim().isNotEmpty);
    if (written.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        // The editor is pushed on the root navigator already; saying so keeps
        // the dialog above any chrome if that ever changes (Gotcha 23).
        useRootNavigator: true,
        builder:
            (context) => AlertDialog(
              title: const Text('Remove this section?'),
              content: Text(
                'Its ${countOf(written.length, 'steps')} will be removed too.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Keep'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Remove'),
                ),
              ],
            ),
      );
      if (confirmed != true) return;
    }
    final index = groups.indexOf(group);
    if (index < 0) return;
    // Remove, rebuild, then dispose — same order as `IngredientsEditor` and
    // for the same reason (32c4): the controllers are still attached to the
    // fields of the frame being torn down.
    final removed = groups.removeAt(index);
    onChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Instructions', style: Theme.of(context).textTheme.titleLarge),
        for (final group in groups)
          Card(
            // Keyed by the draft object so a removed section's fields are not
            // handed to the section that slides into its slot.
            key: ObjectKey(group),
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
                            labelText: 'Section name (optional)',
                            hintText: 'e.g. Prepare the dough',
                          ),
                        ),
                      ),
                      if (groups.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          // UX-047: without it this is an unnamed button.
                          tooltip: 'Remove section',
                          onPressed: () => _removeGroup(context, group),
                        ),
                    ],
                  ),
                  _StepList(
                    group: group,
                    onChanged: onChanged,
                    onPickImage: onPickImage,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        group.steps.add(EditStep());
                        onChanged();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add step'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () {
            groups.add(EditStepGroup());
            onChanged();
          },
          icon: const Icon(Icons.add),
          label: const Text('Add section'),
        ),
      ],
    );
  }
}

/// One section's steps, reorderable two ways (UX-035): by the drag handle,
/// and by each row's **Move up / Move down** menu — the handle is a pointer
/// gesture, so the menu is what a keyboard or a screen reader reaches.
///
/// Reordering moves the draft objects themselves, and `EditStepGroup.toModel`
/// numbers them by list index, so the new order is what saves — ascending, as
/// every nested read expects (B022). Rows are keyed by their draft, so the
/// text fields travel with the step rather than staying in their slot.
class _StepList extends StatelessWidget {
  const _StepList({
    required this.group,
    required this.onChanged,
    required this.onPickImage,
  });

  final EditStepGroup group;
  final VoidCallback onChanged;
  final void Function(EditStep step) onPickImage;

  void _move(int from, int to) {
    final steps = group.steps;
    if (from == to || to < 0 || to >= steps.length) return;
    steps.insert(to, steps.removeAt(from));
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final steps = group.steps;
    return ReorderableListView(
      // The page is the scroll: this list only lays its rows out.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      // `onReorderItem` hands over the index the item lands at once it has
      // been removed — exactly what `_move` wants.
      onReorderItem: _move,
      children: [
        for (var si = 0; si < steps.length; si++)
          _StepRow(
            key: ObjectKey(steps[si]),
            step: steps[si],
            index: si,
            count: steps.length,
            onChanged: onChanged,
            onPickImage: onPickImage,
            onMove: (to) => _move(si, to),
            onRemove: () {
              final removed = steps.removeAt(si);
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

/// The step-number bubble's radius (24 wide).
const double _kBubbleRadius = 12;

/// The drag handle's column: the 24px icon plus a hair of breathing room, so
/// the bubble beside it does not read as part of the grip.
const double _kHandleWidth = AppIconSize.lg + AppSpacing.xs;

/// Where the step field starts: past the handle, the bubble and the gap
/// beside it. Everything under the step text (time, details, photo) indents
/// to this so the row reads as one step.
const double _kStepIndent = _kHandleWidth + 2 * _kBubbleRadius + AppSpacing.sm;

/// The per-row menu's two entries.
enum _StepMove { up, down }

/// One numbered instruction, its step timer, the temperature / tip block, and
/// its optional photo.
///
/// The **Time** field is always shown (UX-035): it was hidden behind the tune
/// button, which is where a cook never looked for the one field that turns a
/// step into a timer in cook mode. It reads `90`, `1h`, `1h 30m`,
/// `1 h 30 min`; anything else fails the form instead of saving no timer.
/// Temperature and tip stay behind the disclosure — a step that already
/// carries either opens with them shown, so an edit can never hide (and then
/// drop) them (B035).
///
/// The photo is not behind that disclosure: it is the one piece of step content
/// that has to be visible to be judged, so a step that has one always shows it.
class _StepRow extends StatelessWidget {
  const _StepRow({
    super.key,
    required this.step,
    required this.index,
    required this.count,
    required this.onChanged,
    required this.onPickImage,
    required this.onMove,
    required this.onRemove,
  });

  final EditStep step;

  /// Position in the section, 0-based; the bubble prints `index + 1`.
  final int index;

  /// Steps in the section — where Move down stops.
  final int count;
  final VoidCallback onChanged;
  final void Function(EditStep step) onPickImage;
  final void Function(int to) onMove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasExtras =
        step.temperature.text.trim().isNotEmpty ||
        step.tip.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  // The menu beside the field is the accessible way to move a
                  // step; the grip is a pointer affordance only.
                  child: ExcludeSemantics(
                    child: SizedBox(
                      width: _kHandleWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        child: Icon(
                          Icons.drag_indicator,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              CircleAvatar(radius: _kBubbleRadius, child: Text('${index + 1}')),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: step.text,
                  maxLines: null,
                  decoration: const InputDecoration(
                    labelText: 'Step',
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.add_a_photo_outlined,
                  size: AppIconSize.button,
                ),
                color: step.hasImage ? scheme.primary : null,
                tooltip: 'Step photo',
                onPressed: () => onPickImage(step),
              ),
              PopupMenuButton<_StepMove>(
                tooltip: 'Move step',
                icon: const Icon(Icons.swap_vert, size: AppIconSize.button),
                onSelected:
                    (move) =>
                        onMove(move == _StepMove.up ? index - 1 : index + 1),
                itemBuilder:
                    (context) => [
                      PopupMenuItem(
                        value: _StepMove.up,
                        enabled: index > 0,
                        child: ListTile(
                          enabled: index > 0,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.arrow_upward),
                          title: const Text('Move up'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _StepMove.down,
                        enabled: index < count - 1,
                        child: ListTile(
                          enabled: index < count - 1,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.arrow_downward),
                          title: const Text('Move down'),
                        ),
                      ),
                    ],
              ),
              IconButton(
                icon: const Icon(Icons.close, size: AppIconSize.button),
                tooltip: 'Remove step',
                onPressed: onRemove,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: _kStepIndent,
              top: AppSpacing.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: step.duration,
                    decoration: const InputDecoration(
                      labelText: 'Time',
                      hintText: 'e.g. 1h 30m',
                      isDense: true,
                      // The message is a sentence; at 2.0× on a phone it
                      // needs a second line rather than an ellipsis.
                      errorMaxLines: 3,
                    ),
                    // On leaving the field, not per keystroke: `1h 3` on the
                    // way to `1h 30m` is not a mistake yet.
                    autovalidateMode: AutovalidateMode.onUnfocus,
                    validator:
                        (_) =>
                            step.hasInvalidDuration
                                ? 'Try 90, 1h or 1h 30m'
                                : null,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.tune, size: AppIconSize.button),
                  color: hasExtras ? scheme.primary : null,
                  tooltip: 'Temperature & tip',
                  onPressed: () {
                    step.showDetails = !step.showDetails;
                    onChanged();
                  },
                ),
              ],
            ),
          ),
          // Collapsing hides the fields, never their text: `toModel` reads
          // the controllers either way, and the tinted button says so.
          if (step.showDetails)
            Padding(
              padding: const EdgeInsets.only(
                left: _kStepIndent,
                top: AppSpacing.sm,
              ),
              child: Column(
                children: [
                  TextField(
                    controller: step.temperature,
                    decoration: const InputDecoration(
                      labelText: 'Temperature',
                      hintText: 'e.g. 180°C',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: step.tip,
                    decoration: const InputDecoration(
                      labelText: 'Tip',
                      hintText: "e.g. don't overmix",
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          if (step.hasImage)
            Padding(
              padding: const EdgeInsets.only(
                left: _kStepIndent,
                top: AppSpacing.sm,
                bottom: AppSpacing.xs,
              ),
              child: _StepImage(
                step: step,
                onReplace: () => onPickImage(step),
                onRemove: () {
                  step.clearImage();
                  onChanged();
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The step's photo: the pending pick if there is one, otherwise the stored
/// URL. Tapping it picks a replacement; the corner button drops it.
///
/// Sized by aspect ratio rather than by a width, so it cannot overflow at any
/// text scale — the row it replaced in earlier drafts could. On anything wider
/// than a phone it takes a fraction of the step column instead of all of it: a
/// 720px editor with a full-bleed photo under every step reads as a gallery,
/// not a method.
class _StepImage extends StatelessWidget {
  const _StepImage({
    required this.step,
    required this.onReplace,
    required this.onRemove,
  });

  final EditStep step;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = step.pendingImageBytes;
    final url = step.imageUrl;

    final Widget image;
    if (bytes != null) {
      image = Image.memory(bytes, fit: BoxFit.cover);
    } else if (url != null && url.isNotEmpty) {
      image = Image.network(
        url,
        fit: BoxFit.cover,
        // A stored photo whose object has gone (or whose network is down) is a
        // placeholder, not a thrown error: without this the failure is reported
        // as a framework exception under a form the cook is still editing.
        errorBuilder:
            (context, error, stack) => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
      );
    } else {
      image = const SizedBox.shrink();
    }

    final tile = Stack(
      children: [
        InkWell(
          onTap: onReplace,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: AspectRatio(aspectRatio: 16 / 9, child: image),
          ),
        ),
        Positioned(
          top: AppSpacing.xs,
          right: AppSpacing.xs,
          child: IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: AppIconSize.button),
            tooltip: 'Remove photo',
            onPressed: onRemove,
          ),
        ),
      ],
    );

    return Align(
      alignment: Alignment.centerLeft,
      child:
          context.isCompact
              ? tile
              : FractionallySizedBox(widthFactor: 0.6, child: tile),
    );
  }
}
