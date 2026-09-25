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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Instructions', style: Theme.of(context).textTheme.titleLarge),
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
                            labelText: 'Section name (optional)',
                            hintText: 'e.g. Prepare the dough',
                          ),
                        ),
                      ),
                      if (groups.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          // Remove, rebuild, then dispose — same order as
                          // `IngredientsEditor` and for the same reason (32c4).
                          onPressed: () {
                            final removed = groups.removeAt(gi);
                            onChanged();
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => removed.dispose(),
                            );
                          },
                        ),
                    ],
                  ),
                  for (var si = 0; si < groups[gi].steps.length; si++)
                    _StepRow(
                      step: groups[gi].steps[si],
                      number: si + 1,
                      onChanged: onChanged,
                      onPickImage: onPickImage,
                      onRemove: () {
                        final removed = groups[gi].steps.removeAt(si);
                        onChanged();
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => removed.dispose(),
                        );
                      },
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        groups[gi].steps.add(EditStep());
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

/// The step-number bubble's radius (24 wide).
const double _kBubbleRadius = 12;

/// Where the step field starts: past the bubble and the gap beside it.
const double _kStepIndent = 2 * _kBubbleRadius + AppSpacing.sm;

/// One numbered instruction, its optional photo, plus the time / temperature /
/// tip block that the recipe detail screen renders as chips. Those three are
/// collapsed by default and revealed by the tune button; a step that already
/// carries any of them opens expanded, so an edit can never hide (and then
/// drop) them (B035).
///
/// The photo is not behind that disclosure: it is the one piece of step content
/// that has to be visible to be judged, so a step that has one always shows it.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.number,
    required this.onChanged,
    required this.onPickImage,
    required this.onRemove,
  });

  final EditStep step;
  final int number;
  final VoidCallback onChanged;
  final void Function(EditStep step) onPickImage;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: _kBubbleRadius, child: Text('$number')),
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
              IconButton(
                icon: const Icon(Icons.tune, size: AppIconSize.button),
                color: step.hasDetails ? scheme.primary : null,
                tooltip: 'Time, temperature & tip',
                onPressed: () {
                  step.showDetails = !step.showDetails;
                  onChanged();
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, size: AppIconSize.button),
                tooltip: 'Remove step',
                onPressed: onRemove,
              ),
            ],
          ),
          if (step.hasImage)
            Padding(
              // Indented to the step field: the number bubble is 24 wide and
              // the gap beside it is `sm`, the same sum the detail block below
              // uses.
              padding: const EdgeInsets.only(
                left: _kStepIndent,
                top: AppSpacing.xs,
                bottom: AppSpacing.sm,
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
          if (step.showDetails)
            Padding(
              padding: const EdgeInsets.only(
                left: _kStepIndent,
                top: AppSpacing.xs,
                bottom: AppSpacing.sm,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: step.duration,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Time (min)',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: step.temperature,
                          decoration: const InputDecoration(
                            labelText: 'Temperature',
                            hintText: 'e.g. 180°C',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
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
