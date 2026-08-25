import 'package:core/src/models/ingredient_group.dart';
import 'package:core/src/models/step_group.dart';

/// The jsonb trees `save_recipe` and `estimate_nutrition` take — one encoder,
/// used by both call sites (Phase 29c), so the editor's preview estimates the
/// EXACT trees the save then persists. Array order is meaning: the server
/// turns the index into `sort_order`/`step_order` (Gotcha 11 / B022).
///
/// A new ingredient or step column must be added here — this is one of the
/// restatement sites the CLAUDE.md ingredient-column rule enumerates, and like
/// `save_recipe`'s copy it fails silently: an omitted key simply never saves.
List<Map<String, dynamic>> ingredientGroupsPayload(
  List<IngredientGroup> groups,
) => [
  for (final group in groups)
    {
      'name': group.name,
      'ingredients': [
        for (final i in group.ingredients)
          {
            'quantity': i.quantity,
            'unit': i.unit,
            'name': i.name,
            'note': i.note,
            'is_optional': i.isOptional,
            'food_id': i.foodId,
          },
      ],
    },
];

List<Map<String, dynamic>> stepGroupsPayload(List<StepGroup> groups) => [
  for (final group in groups)
    {
      'name': group.name,
      'steps': [
        for (final s in group.steps)
          {
            'text': s.text,
            'image_url': s.imageUrl,
            'duration_minutes': s.durationMinutes,
            'temperature': s.temperature,
            'tip': s.tip,
          },
      ],
    },
];
