import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:app/features/recipe_editor/edit_models.dart';

/// The steps half of the editor — the other seam (OPT-A8). Same contract as
/// `IngredientsEditor`: it renders the draft it is handed and reports every
/// mutation through [onChanged].
class StepsEditor extends StatelessWidget {
  const StepsEditor({
    super.key,required this.groups, required this.onChanged});

  final List<EditStepGroup> groups;
  final VoidCallback onChanged;

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
                          onPressed: () {
                            groups[gi].dispose();
                            groups.removeAt(gi);
                            onChanged();
                          },
                        ),
                    ],
                  ),
                  for (var si = 0; si < groups[gi].steps.length; si++)
                    _StepRow(
                      step: groups[gi].steps[si],
                      number: si + 1,
                      onChanged: onChanged,
                      onRemove: () {
                        groups[gi].steps[si].dispose();
                        groups[gi].steps.removeAt(si);
                        onChanged();
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

/// One numbered instruction, plus the time / temperature / tip block that the
/// recipe detail screen renders as chips. Those three are collapsed by default
/// and revealed by the tune button; a step that already carries any of them
/// opens expanded, so an edit can never hide (and then drop) them (B035).
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.number,
    required this.onChanged,
    required this.onRemove,
  });

  final EditStep step;
  final int number;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 12, child: Text('$number')),
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
                icon: const Icon(Icons.tune, size: 18),
                color: step.hasDetails ? scheme.primary : null,
                tooltip: 'Time, temperature & tip',
                onPressed: () {
                  step.showDetails = !step.showDetails;
                  onChanged();
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove step',
                onPressed: onRemove,
              ),
            ],
          ),
          if (step.showDetails)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.lg + AppSpacing.sm,
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
