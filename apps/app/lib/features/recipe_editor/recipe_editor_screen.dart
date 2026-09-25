import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/recipe_editor/cover_picker.dart';
import 'package:app/features/recipe_editor/edit_models.dart';
import 'package:app/features/recipe_editor/ingredients_editor.dart';
import 'package:app/features/recipe_editor/nutrition_editor.dart';
import 'package:app/features/recipe_editor/recipe_editor_providers.dart';
import 'package:app/features/recipe_editor/steps_editor.dart';
import 'package:app/routing/app_router.dart';

/// The form's measure on a wide window.
const double _kFormMaxWidth = 720;

/// Stroke of the Save button's in-flight spinner.
const double _kSpinnerStroke = 2;

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
  /// `recipes_minutes_nonneg` (32a2), stated where the cook can see it. Shared
  /// by Prep and Cook because one rule with two call sites is how the two stay
  /// the same rule. Unparseable is not rejected — `_parseInt` reads it as 0.
  static String? _nonNegativeMinutes(String? v) {
    final n = int.tryParse((v ?? '').trim());
    return (n != null && n < 0) ? 'Cannot be negative' : null;
  }

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _cuisine = TextEditingController();
  final _category = TextEditingController();
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

  /// Whether anything in the draft has been touched since it was loaded.
  ///
  /// The whole point of the confirm dialog is to protect *work*, and without
  /// this it could not tell work from an untouched form: opening a recipe and
  /// backing straight out asked "Discard changes?" over nothing (B085's inverse
  /// half). A flag rather than a deep comparison of two drafts because every
  /// mutation already reports itself — the editors call `onChanged`, the fields
  /// have listeners — so the cheap answer is also the complete one.
  bool _dirty = false;

  /// What each of [_textFields] held when the draft was last known clean.
  ///
  /// The listener cannot simply treat a notification as an edit: a
  /// `TextEditingController` is a `ValueNotifier<TextEditingValue>` and that
  /// value carries the **selection**, so merely tapping into Title moves the
  /// caret and notifies — which would make "opened the editor and looked at a
  /// field" indistinguishable from "wrote something", and re-arm exactly the
  /// nag this change removes. Comparing text against this baseline is what makes
  /// focus not an edit, and it also lets a character typed and deleted again
  /// come back clean.
  late List<String> _baselineText = [for (final c in _textFields) c.text];

  /// The single-line fields, in one place: `initState` listens to all of them
  /// and `dispose` disposes all of them, and a field that appears in one list
  /// but not the other is exactly how a leak or a missed edit gets in.
  late final List<TextEditingController> _textFields = [
    _title,
    _description,
    _cuisine,
    _category,
    _attribution,
    _prep,
    _cook,
    _servings,
  ];

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
    for (final c in _textFields) {
      c.addListener(_onFieldChanged);
    }
    if (widget.isEditing) _load();
  }

  @override
  void dispose() {
    for (final c in _textFields) {
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

  /// Records that the draft now differs from what was loaded.
  ///
  /// `setState` because [_dirty] decides `PopScope.canPop`, which is read at
  /// build time: without the rebuild the first edit would leave the route still
  /// freely poppable.
  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  /// A text field notified. Dirty only if its **text** actually differs from
  /// [_baselineText] — see that field for why a notification is not enough.
  void _onFieldChanged() {
    if (_dirty) return;
    for (var i = 0; i < _textFields.length; i++) {
      if (_textFields[i].text != _baselineText[i]) {
        _markDirty();
        return;
      }
    }
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
      _category.text = recipe.category ?? '';
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
      // The loaded recipe is the new clean state: re-baseline first, then drop
      // the flag. Without this the fields would read as edits against the empty
      // defaults they were created with, and a freshly opened recipe would nag
      // on the way out over nothing the cook did.
      if (mounted) {
        _baselineText = [for (final c in _textFields) c.text];
        setState(() {
          _loading = false;
          _dirty = false;
        });
      }
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
    _markDirty();
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
    _markDirty();
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

  /// The one pick every image control in this editor goes through — the cover
  /// tile and each step's photo button. Returns null when the reader backed
  /// out, when the platform refused, or when the file is too big to store; the
  /// last two have already been explained on screen by the time it returns.
  ///
  /// Shared rather than copied: the size guard below is the only thing between
  /// a 12 MP phone photo and a save that fails with a sentence naming no size,
  /// and a second copy of it is a second thing to forget.
  Future<Uint8List?> _pickImageBytes() async {
    final Uint8List? bytes;
    try {
      bytes = await ref.read(imagePickerProvider)();
    } catch (e) {
      // A platform-channel failure (a denied permission, a missing entitlement)
      // is a message, not an unhandled async error thrown past the widget.
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
      return null;
    }
    if (bytes == null) return null;
    // `file_size_limit` on the bucket is 5 MB (32a4) and the picker's own
    // `maxWidth` does not reliably keep us under it: the Windows/Linux pickers
    // ignore their options outright, web skips the resize for gifs, and Android
    // re-encodes an alpha-bearing pick as lossless PNG. Without this the
    // refusal surfaces from inside `_save` as a `StorageException`, so the
    // whole save appears to fail and the message names no size. Checked here,
    // where the file was chosen.
    if (bytes.length > kMaxUploadBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That image is over 5 MB. Please pick a smaller one.',
            ),
          ),
        );
      }
      return null;
    }
    return bytes;
  }

  Future<void> _pickCover() async {
    final bytes = await _pickImageBytes();
    if (bytes == null || !mounted) return;
    setState(() => _pendingCoverBytes = bytes);
    _markDirty();
  }

  /// The per-step twin. Holds the bytes on the draft exactly as the cover does
  /// — nothing is uploaded until Save, so an abandoned edit leaves no orphan
  /// object in the bucket, and nothing reaches the recipe outside the one
  /// `save_recipe` call (Gotcha 11).
  Future<void> _pickStepImage(EditStep step) async {
    final bytes = await _pickImageBytes();
    if (bytes == null || !mounted) return;
    setState(() => step.pendingImageBytes = bytes);
    _markDirty();
  }

  /// Uploads every step photo picked since the last save and writes the
  /// resulting URL onto the draft, so the `toModel()` calls below carry it into
  /// the same `save_recipe` call as the rest of the recipe.
  ///
  /// The pending bytes are dropped as each upload lands: a recipe write that
  /// fails afterwards must not re-upload the same file on the retry, and the
  /// URL is already valid whether or not that write succeeded.
  ///
  /// The filename carries an index as well as a timestamp — several steps
  /// uploaded in one save land in the same millisecond, and `upsert: true`
  /// would quietly overwrite one photo with another.
  /// The empty case returns before touching [storageServiceProvider] on
  /// purpose — the same guard the cover upload gets from its `!= null` check.
  /// Reading it builds a `StorageService` over the live Supabase client, so a
  /// save with no new photo would otherwise need a Storage stub to run at all.
  Future<void> _uploadStepImages() async {
    final pending = [
      for (final group in _stepGroups)
        for (final step in group.steps)
          if (step.pendingImageBytes != null) step,
    ];
    if (pending.isEmpty) return;

    final storage = ref.read(storageServiceProvider);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < pending.length; i++) {
      final step = pending[i];
      step.imageUrl = await storage.uploadRecipeImage(
        fileName: 'step_${stamp}_$i.jpg',
        bytes: step.pendingImageBytes!,
      );
      step.pendingImageBytes = null;
    }
  }

  int _parseInt(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  /// Navigate back to a sensible location, confirming first when there is
  /// something to lose. An untouched editor leaves without a word.
  Future<void> _cancel() async {
    if (!_dirty) {
      _leave();
      return;
    }
    if (await _confirmDiscard() && mounted) _leave();
  }

  /// The one discard prompt. Both ways out of a dirty editor — the Cancel
  /// button and a system back gesture — ask through here, so the two can never
  /// answer the question differently (32c2).
  Future<bool> _confirmDiscard() async {
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
    return discard == true;
  }

  /// Where the editor exits to. Reached via `go`, so there is usually no back
  /// stack to pop — and the `go` fallback differs by mode, which is why this is
  /// not a bare `popOrGo` call.
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(
        widget.isEditing ? Routes.recipe(widget.recipeId!) : Routes.myRecipes,
      );
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
      // The same, per step. Has to run before the `toModel()` calls below read
      // `imageUrl` off the draft.
      await _uploadStepImages();

      final base = Recipe(
        id: widget.recipeId ?? '',
        ownerId: ref.read(currentUserIdProvider) ?? '',
        title: _title.text.trim(),
        description: _description.text.trim(),
        coverImageUrl: coverUrl,
        cuisine: _cuisine.text.trim().isEmpty ? null : _cuisine.text.trim(),
        category: _category.text.trim().isEmpty ? null : _category.text.trim(),
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
    final form = Scaffold(
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
                        height: AppIconSize.sm,
                        width: AppIconSize.sm,
                        child: CircularProgressIndicator(
                          strokeWidth: _kSpinnerStroke,
                        ),
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
            constraints: const BoxConstraints(maxWidth: _kFormMaxWidth),
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
                  // `recipes_text_lengths` (32a2) caps these in the database, so
                  // the field enforces the same numbers here — a save refused by
                  // a check constraint reads as "something went wrong", while a
                  // field that stops accepting characters explains itself.
                  maxLength: 200,
                  // `counterText: ''` keeps the enforcement and drops the
                  // `0/200` counter: nobody writing a recipe title is budgeting
                  // characters, and the counter is a new band of text under two
                  // fields the editor's envelope suite measures at 2.0×.
                  // Approximate on purpose: `maxLength` counts grapheme
                  // clusters and `char_length()` counts code points, so a title
                  // of composed emoji can satisfy this and still trip the
                  // constraint. SQL is authoritative; this is the courtesy.
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    counterText: '',
                  ),
                  validator:
                      (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  maxLength: 10000,
                  decoration: const InputDecoration(
                    labelText: 'Short description',
                    counterText: '',
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
                        validator: _nonNegativeMinutes,
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
                        validator: _nonNegativeMinutes,
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
                        // `recipes_servings_positive` (32a2). Unparseable text
                        // stays valid because `_save` reads it as `?? 1`, which
                        // the constraint accepts — it is only a *parsed*
                        // non-positive number that would reach the RPC and come
                        // back as an unattributed `23514`.
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          return (n != null && n < 1) ? 'At least 1' : null;
                        },
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
                        onChanged: (v) {
                          setState(() => _difficulty = v ?? Difficulty.easy);
                          _markDirty();
                        },
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
                TextFormField(
                  controller: _category,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SwitchListTile(
                  value: _visibility.isPublic,
                  onChanged: (v) {
                    setState(
                      () =>
                          _visibility =
                              v
                                  ? RecipeVisibility.public
                                  : RecipeVisibility.private,
                    );
                    _markDirty();
                  },
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
                  onChanged: () {
                    setState(() {});
                    _markDirty();
                  },
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
                    _markDirty();
                    // Linking a food down here is what the Auto pane's own
                    // copy tells the cook to do, so the estimate has to follow.
                    _scheduleEstimate();
                  },
                ),
                const Divider(height: AppSpacing.xl),
                StepsEditor(
                  groups: _stepGroups,
                  onChanged: () {
                    setState(() {});
                    _markDirty();
                  },
                  onPickImage: _pickStepImage,
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );

    // B085: the discard confirm used to hang off the close button alone, so an
    // Android back gesture or an iOS edge swipe threw a half-written recipe away
    // without a word. `canPop` is the dirty flag, so an untouched editor still
    // closes on the first gesture, and both routes out ask through
    // `_confirmDiscard`.
    //
    // What this does **not** cover is the web browser's Back button: that
    // arrives as new route information for the `Router`, not as a pop, and
    // nothing consults `PopScope` on the way through. The honest scope of this
    // guard is the platform back gesture and any `maybePop`.
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) _leave();
      },
      child: form,
    );
  }
}
