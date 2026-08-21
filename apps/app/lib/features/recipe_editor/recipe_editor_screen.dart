import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:app/features/recipe_editor/edit_models.dart';
import 'package:app/routing/app_router.dart';

/// Create or edit a recipe. When [recipeId] is null, creates a new recipe;
/// otherwise loads and edits the existing one. Saving an edit appends a new
/// version via the repository.
class RecipeEditorScreen extends ConsumerStatefulWidget {
  const RecipeEditorScreen({super.key, this.recipeId});

  final String? recipeId;

  bool get isEditing => recipeId != null;

  @override
  ConsumerState<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends ConsumerState<RecipeEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _cuisine = TextEditingController();
  final _attribution = TextEditingController();
  final _prep = TextEditingController(text: '0');
  final _cook = TextEditingController(text: '0');
  final _servings = TextEditingController(text: '1');

  Difficulty _difficulty = Difficulty.easy;
  RecipeVisibility _visibility = RecipeVisibility.private;
  String? _coverUrl;
  Uint8List? _pendingCoverBytes;

  final List<EditIngredientGroup> _ingredientGroups = [EditIngredientGroup()];
  final List<EditStepGroup> _stepGroups = [EditStepGroup()];

  bool _loading = false;
  bool _saving = false;

  /// Why the existing recipe could not be loaded, or null. Non-null puts the
  /// screen into its error state instead of the form (B052).
  String? _loadError;

  /// Whether the draft actually reflects a recipe that came back from the
  /// server. False while editing means the fields are the empty defaults, and
  /// saving them would delete every ingredient and step group the recipe has
  /// (`update()` replaces content wholesale) — so Save stays blocked.
  /// Always true when creating: there is nothing to load.
  bool _loaded = false;

  bool get _canSave => !widget.isEditing || _loaded;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) _load();
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _description,
      _cuisine,
      _attribution,
      _prep,
      _cook,
      _servings,
    ]) {
      c.dispose();
    }
    for (final g in _ingredientGroups) {
      g.dispose();
    }
    for (final g in _stepGroups) {
      g.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final recipe =
          await ref.read(recipeRepositoryProvider).getById(widget.recipeId!);
      _title.text = recipe.title;
      _description.text = recipe.description;
      _cuisine.text = recipe.cuisine ?? '';
      _attribution.text = recipe.attribution ?? '';
      _prep.text = recipe.prepMinutes.toString();
      _cook.text = recipe.cookMinutes.toString();
      _servings.text = recipe.servings.toString();
      _difficulty = recipe.difficulty;
      _visibility = recipe.visibility;
      _coverUrl = recipe.coverImageUrl;
      _ingredientGroups
        ..clear()
        ..addAll(recipe.ingredientGroups.map(EditIngredientGroup.fromModel));
      _stepGroups
        ..clear()
        ..addAll(recipe.stepGroups.map(EditStepGroup.fromModel));
      if (_ingredientGroups.isEmpty) {
        _ingredientGroups.add(EditIngredientGroup());
      }
      if (_stepGroups.isEmpty) {
        _stepGroups.add(EditStepGroup());
      }
      _loaded = true;
    } catch (e) {
      // Without this catch the exception escaped as an unhandled future and the
      // form rendered its empty defaults over a recipe that still exists —
      // pressing Save then wiped its content (B052). `getById` is awaited before
      // any field is touched, so a failure leaves the draft untouched, not half
      // filled.
      _loadError = friendlyError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCover() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1600);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _pendingCoverBytes = bytes);
  }

  int _parseInt(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  /// Navigate back to a sensible location, confirming first so in-progress
  /// edits aren't lost by accident. The editor is reached via `go`, so there is
  /// no back stack to pop.
  Future<void> _cancel() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Any unsaved changes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    _leave();
  }

  /// Where the editor exits to. Reached via `go`, so there is usually no back
  /// stack to pop.
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else if (widget.isEditing) {
      context.go('/recipe/${widget.recipeId}');
    } else {
      context.go(Routes.myRecipes);
    }
  }

  Future<void> _save() async {
    // Belt and braces behind the build-time guard: an unloaded edit draft holds
    // the empty defaults, and `update()` replaces content wholesale, so saving
    // it would delete the recipe's ingredients and steps (B052).
    if (!_canSave) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(recipeRepositoryProvider);
    try {
      // Upload cover if a new image was picked.
      var coverUrl = _coverUrl;
      if (_pendingCoverBytes != null) {
        coverUrl = await ref.read(storageServiceProvider).uploadRecipeImage(
              fileName: 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg',
              bytes: _pendingCoverBytes!,
            );
      }

      final base = Recipe(
        id: widget.recipeId ?? '',
        ownerId: ref.read(currentUserIdProvider) ?? '',
        title: _title.text.trim(),
        description: _description.text.trim(),
        coverImageUrl: coverUrl,
        cuisine: _cuisine.text.trim().isEmpty ? null : _cuisine.text.trim(),
        attribution:
            _attribution.text.trim().isEmpty ? null : _attribution.text.trim(),
        difficulty: _difficulty,
        prepMinutes: _parseInt(_prep),
        cookMinutes: _parseInt(_cook),
        servings: int.tryParse(_servings.text.trim()) ?? 1,
        visibility: _visibility,
        ingredientGroups: _ingredientGroups.map((g) => g.toModel()).toList(),
        stepGroups: _stepGroups.map((g) => g.toModel()).toList(),
      );

      final saved = widget.isEditing
          ? await repo.update(base, changeSummary: 'Edited recipe')
          : await repo.create(base);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recipe saved')),
        );
        context.go('/recipe/${saved.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed — ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: LoadingView());
    }
    // A failed load must never fall through to the form: the fields are still
    // the empty defaults, and `update()` replaces content wholesale, so one Save
    // would delete every ingredient and step group (B052). Offer retry or exit
    // instead — and leave via `_leave()`, not `_cancel()`, since there are no
    // changes to confirm discarding.
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: _leave,
          ),
          title: const Text('Edit recipe'),
        ),
        body: ErrorView(
          message: 'Could not open this recipe for editing.\n$_loadError',
          onRetry: _load,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: _saving ? null : _cancel,
        ),
        title: Text(widget.isEditing ? 'Edit recipe' : 'New recipe'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilledButton.icon(
              onPressed: (_saving || !_canSave) ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _CoverPicker(
                  url: _coverUrl,
                  bytes: _pendingCoverBytes,
                  onPick: _pickCover,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Short description'),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _prep,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Prep (min)'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _cook,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Cook (min)'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _servings,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Servings'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<Difficulty>(
                        initialValue: _difficulty,
                        // `isExpanded` + an ellipsising label: without it the
                        // dropdown's internal [label, arrow] row is intrinsic,
                        // and half of a 360px phone at 2.0x text scale is not
                        // enough for "Medium" + the arrow (B036).
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Difficulty'),
                        items: [
                          for (final d in Difficulty.values)
                            DropdownMenuItem(
                              value: d,
                              child: Text(
                                d.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => _difficulty = v ?? Difficulty.easy),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _cuisine,
                        decoration: const InputDecoration(labelText: 'Cuisine'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SwitchListTile(
                  value: _visibility.isPublic,
                  onChanged: (v) => setState(() => _visibility =
                      v ? RecipeVisibility.public : RecipeVisibility.private),
                  title: const Text('Public'),
                  subtitle: const Text('Anyone can find this on Discover'),
                  contentPadding: EdgeInsets.zero,
                ),
                TextFormField(
                  controller: _attribution,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Attribution / story (optional)',
                    hintText: "e.g. Grandma Rosa's Sunday sauce",
                  ),
                ),
                const Divider(height: AppSpacing.xl),
                _IngredientsEditor(
                  groups: _ingredientGroups,
                  onChanged: () => setState(() {}),
                ),
                const Divider(height: AppSpacing.xl),
                _StepsEditor(
                  groups: _stepGroups,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverPicker extends StatelessWidget {
  const _CoverPicker({this.url, this.bytes, required this.onPick});

  final String? url;
  final Uint8List? bytes;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadii.card),
            image: bytes != null
                ? DecorationImage(image: MemoryImage(bytes!), fit: BoxFit.cover)
                : (url != null && url!.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(url!), fit: BoxFit.cover)
                    : null),
          ),
          child: (bytes == null && (url == null || url!.isEmpty))
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo, color: scheme.onSurfaceVariant),
                    const SizedBox(height: AppSpacing.sm),
                    const Text('Add cover photo'),
                  ],
                )
              : null,
        ),
      ),
    );
  }
}

class _IngredientsEditor extends StatelessWidget {
  const _IngredientsEditor({required this.groups, required this.onChanged});

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

class _StepsEditor extends StatelessWidget {
  const _StepsEditor({required this.groups, required this.onChanged});

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
