import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:app/features/recipe_editor/cover_picker.dart';
import 'package:app/features/recipe_editor/edit_models.dart';
import 'package:app/features/recipe_editor/ingredients_editor.dart';
import 'package:app/features/recipe_editor/nutrition_editor.dart';
import 'package:app/features/recipe_editor/steps_editor.dart';
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
  final EditNutrition _nutrition = EditNutrition();

  /// Whether the nutrition panel is open. Owned here rather than by the panel
  /// so a blocked save can force it open — its fields stay registered with the
  /// `Form` while collapsed, so an invalid entry hidden behind the header still
  /// stops the save, and an error nobody can see would otherwise be a dead end.
  bool _nutritionExpanded = false;

  /// The three-way nutrition choice (Phase 29c). What it saves: `auto` sends
  /// `{source: 'auto'}` and `save_recipe` recomputes the label server-side
  /// from the same trees it persists; `manual` sends the typed values; `none`
  /// sends null. On load, a stored `source: 'auto'` reopens as Automatic,
  /// any other label as Manual, null as None.
  EditNutritionMode _nutritionMode = EditNutritionMode.none;

  /// The Auto pane's preview state. The estimate is fetched on entering
  /// Automatic, after a suggestion links a row, and on the pane's refresh
  /// button — discrete events, not keystrokes (one RPC per match change is
  /// the design; there is no Dart mirror of the arithmetic).
  NutritionEstimate? _estimate;
  bool _estimateLoading = false;
  String? _estimateError;
  Map<String, List<FoodHit>> _matchSuggestions = const {};

  /// Coalesces estimate refreshes triggered by editing the ingredients or the
  /// servings while Automatic is selected. Those are not discrete events —
  /// `onChanged` fires per keystroke — so they debounce rather than firing an
  /// RPC per character, the same 250 ms shape the typeahead uses, doubled
  /// because this one is not a hint but a recompute.
  Timer? _estimateDebounce;

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
    _nutrition.dispose();
    _estimateDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final recipe = await ref
          .read(recipeRepositoryProvider)
          .getById(widget.recipeId!);
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
      _nutrition.load(recipe.nutrition);
      // Mode from provenance (29c): `source: 'auto'` reopens as Automatic,
      // any other stored label as Manual, null as None. The stored auto
      // values were loaded into the manual controllers above on purpose —
      // they are the seed if the cook switches to Manual.
      final nutrition = recipe.nutrition;
      _nutritionMode =
          nutrition == null || nutrition.isEmpty
              ? EditNutritionMode.none
              : nutrition.isEstimated
              ? EditNutritionMode.auto
              : EditNutritionMode.manual;
      // A recipe that already carries a label must not hide it behind a
      // collapsed header.
      _nutritionExpanded = _nutritionMode != EditNutritionMode.none;
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
      await _labelFoodLinks();
      _loaded = true;
      // The Auto pane needs its preview; fire-and-forget, it manages its own
      // loading/error state and the form is usable meanwhile.
      if (_nutritionMode == EditNutritionMode.auto) {
        unawaited(_refreshEstimate());
      }
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

  /// Fills each linked ingredient's chip label from the registry (Phase 29b).
  /// The database stores only `food_id`, so a loaded recipe knows *that* a row
  /// is linked but not what to call the link. Failure is deliberately silent —
  /// the chip falls back to its generic label and the link itself is intact,
  /// so there is no error state worth interrupting the load for.
  Future<void> _labelFoodLinks() async {
    final ids = <String>{
      for (final g in _ingredientGroups)
        for (final i in g.ingredients)
          if (i.foodId != null) i.foodId!,
    };
    if (ids.isEmpty) return;
    try {
      final names = await ref
          .read(foodRepositoryProvider)
          .displayNames(ids.toList());
      for (final g in _ingredientGroups) {
        for (final i in g.ingredients) {
          i.foodLabel = names[i.foodId];
        }
      }
    } catch (_) {
      // Chips render 'Linked'; nothing else depends on the lookup.
    }
  }

  /// Fetches the Auto pane's preview: the estimate over the CURRENT draft
  /// trees (the same encoder the save path uses), then `match_foods`
  /// candidates for whatever is unlinked. The suggestion lookup failing is
  /// not an estimate failure — it is a hint surface, so it degrades to no
  /// chips silently.
  Future<void> _refreshEstimate() async {
    final groups = _ingredientGroups.map((g) => g.toModel()).toList();
    final servings = int.tryParse(_servings.text.trim()) ?? 1;
    setState(() {
      _estimateLoading = true;
      _estimateError = null;
    });
    try {
      final repo = ref.read(foodRepositoryProvider);
      final estimate = await repo.estimate(
        ingredientGroups: groups,
        servings: servings,
      );
      final unlinked = <String>{
        for (final g in _ingredientGroups)
          for (final i in g.ingredients)
            if (i.foodId == null && i.name.text.trim().isNotEmpty)
              i.name.text.trim(),
      };
      var suggestions = const <String, List<FoodHit>>{};
      if (unlinked.isNotEmpty) {
        try {
          suggestions = await repo.matchFoods(unlinked.toList());
        } catch (_) {
          // No chips this round; the estimate stands without them.
        }
      }
      if (!mounted) return;
      setState(() {
        _estimate = estimate;
        _matchSuggestions = suggestions;
        _estimateLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _estimateLoading = false;
        _estimateError = friendlyError(e);
      });
    }
  }

  /// Re-estimates after an edit to the ingredients or the servings, debounced.
  ///
  /// Without this the Auto pane silently goes stale against the very workflow
  /// it prints: linking a food in the ingredient list below (or changing the
  /// servings the label is *per*) would leave the preview and the
  /// counted-of-total header describing the previous draft until the cook
  /// found the refresh button. A no-op outside Automatic, where nothing reads
  /// the estimate.
  void _scheduleEstimate() {
    if (_nutritionMode != EditNutritionMode.auto) return;
    _estimateDebounce?.cancel();
    _estimateDebounce = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_refreshEstimate()),
    );
  }

  /// A tapped `match_foods` candidate — the human confirmation that turns a
  /// proposal into a stored link. Same write the typeahead pick does.
  void _linkSuggestion(EditIngredient row, FoodHit hit) {
    setState(() {
      row.foodId = hit.id;
      row.foodLabel = hit.displayName;
    });
    unawaited(_refreshEstimate());
  }

  /// Mode transitions, with their two rules (Phase 29c): entering Automatic
  /// over typed manual values asks first — saving in Automatic discards
  /// those numbers server-side, and that must never happen silently; leaving
  /// Automatic for Manual seeds the fields with the computed values so the
  /// cook edits the estimate instead of eleven empty boxes.
  Future<void> _selectNutritionMode(EditNutritionMode mode) async {
    if (mode == _nutritionMode) return;
    if (mode == EditNutritionMode.auto &&
        _nutritionMode == EditNutritionMode.manual &&
        _nutrition.hasValues) {
      final replace = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Switch to automatic?'),
              content: const Text(
                'Saving in Automatic replaces your entered values with the '
                'estimate computed from the ingredient list.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Keep manual'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Use automatic'),
                ),
              ],
            ),
      );
      if (replace != true || !mounted) return;
    }
    setState(() {
      final previous = _nutritionMode;
      _nutritionMode = mode;
      if (mode == EditNutritionMode.manual &&
          previous == EditNutritionMode.auto &&
          _estimate?.label != null) {
        // `load` copies the 11 values and ignores `source`, so the seeded
        // manual label sheds the estimate stamp — it is the cook's now.
        _nutrition.load(_estimate!.label);
      }
    });
    if (mode == EditNutritionMode.auto) {
      unawaited(_refreshEstimate());
    }
  }

  Future<void> _pickCover() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
    );
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
      builder:
          (ctx) => AlertDialog(
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
      context.go(Routes.recipe(widget.recipeId!));
    } else {
      context.go(Routes.myRecipes);
    }
  }

  Future<void> _save() async {
    // Belt and braces behind the build-time guard: an unloaded edit draft holds
    // the empty defaults, and `update()` replaces content wholesale, so saving
    // it would delete the recipe's ingredients and steps (B052).
    if (!_canSave) return;
    if (!_formKey.currentState!.validate()) {
      // The nutrition fields stay registered with the Form while the panel is
      // collapsed, so one of them can be what blocked this save — open the
      // panel in that case rather than leaving Save doing nothing. Scoped to a
      // *nutrition* failure on purpose: a blank Title must not unfold eleven
      // boxes that have nothing to do with the error above them. Manual mode
      // only — in Automatic and None the fields are out of the tree and out
      // of the save, so their text cannot be what blocked it.
      if (_nutritionMode == EditNutritionMode.manual &&
          _nutrition.hasInvalidEntry) {
        setState(() => _nutritionExpanded = true);
      }
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(recipeRepositoryProvider);
    try {
      // Upload cover if a new image was picked.
      var coverUrl = _coverUrl;
      if (_pendingCoverBytes != null) {
        coverUrl = await ref
            .read(storageServiceProvider)
            .uploadRecipeImage(
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
        // The mode decides the payload (29c). Automatic sends only the
        // provenance claim — `save_recipe` recomputes the label from the
        // trees in this same call, so preview numbers are never trusted from
        // here, and an estimate with nothing counted stores null. Manual is
        // null when every box is empty, never `{}` — one representation of
        // "no nutrition info", all the way to the column.
        nutrition: switch (_nutritionMode) {
          EditNutritionMode.none => null,
          EditNutritionMode.manual => _nutrition.toModel(),
          EditNutritionMode.auto => const RecipeNutrition(source: 'auto'),
        },
        ingredientGroups: _ingredientGroups.map((g) => g.toModel()).toList(),
        stepGroups: _stepGroups.map((g) => g.toModel()).toList(),
      );

      final saved =
          widget.isEditing
              ? await repo.update(base, changeSummary: 'Edited recipe')
              : await repo.create(base);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Recipe saved')));
        context.go(Routes.recipe(saved.id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed — ${friendlyError(e)}')),
        );
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
              icon:
                  _saving
                      ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
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
                CoverPicker(
                  url: _coverUrl,
                  bytes: _pendingCoverBytes,
                  onPick: _pickCover,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator:
                      (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Short description',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _prep,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Prep (min)',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _cook,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Cook (min)',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _servings,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Servings',
                        ),
                        // The estimate is *per serving*, so this number is a
                        // divisor: 4 → 8 halves every row. Re-estimate, or the
                        // pane prints per-4 values under an "8 servings" line.
                        onChanged: (_) {
                          setState(() {});
                          _scheduleEstimate();
                        },
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
                        decoration: const InputDecoration(
                          labelText: 'Difficulty',
                        ),
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
                        onChanged:
                            (v) => setState(
                              () => _difficulty = v ?? Difficulty.easy,
                            ),
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
                  onChanged:
                      (v) => setState(
                        () =>
                            _visibility =
                                v
                                    ? RecipeVisibility.public
                                    : RecipeVisibility.private,
                      ),
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
                NutritionEditor(
                  mode: _nutritionMode,
                  onModeSelected:
                      (mode) => unawaited(_selectNutritionMode(mode)),
                  nutrition: _nutrition,
                  expanded: _nutritionExpanded,
                  onToggle:
                      () => setState(
                        () => _nutritionExpanded = !_nutritionExpanded,
                      ),
                  onChanged: () => setState(() {}),
                  groups: _ingredientGroups,
                  servings: int.tryParse(_servings.text.trim()) ?? 1,
                  estimate: _estimate,
                  estimateLoading: _estimateLoading,
                  estimateError: _estimateError,
                  suggestions: _matchSuggestions,
                  onRefreshEstimate: () => unawaited(_refreshEstimate()),
                  onPickSuggestion: _linkSuggestion,
                ),
                const Divider(height: AppSpacing.xl),
                IngredientsEditor(
                  groups: _ingredientGroups,
                  onChanged: () {
                    setState(() {});
                    // Linking a food down here is what the Auto pane's own
                    // copy tells the cook to do, so the estimate has to follow.
                    _scheduleEstimate();
                  },
                ),
                const Divider(height: AppSpacing.xl),
                StepsEditor(
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
