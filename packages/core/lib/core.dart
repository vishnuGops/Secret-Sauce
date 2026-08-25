/// Secret-Sauce shared platform core: models, repositories, services, providers.
library core;

// Models
export 'src/models/enums.dart';
export 'src/models/profile.dart';
export 'src/models/ingredient.dart';
export 'src/models/ingredient_group.dart';
export 'src/models/recipe_step.dart';
export 'src/models/step_group.dart';
export 'src/models/recipe_version.dart';
export 'src/models/recipe_nutrition.dart';
export 'src/models/recipe.dart';
export 'src/models/chef_standing.dart';
export 'src/models/food_hit.dart';

// Domain helpers
export 'src/chef_scoring.dart';
export 'src/formatting.dart';
export 'src/nutrition_facts.dart';
export 'src/friendly_error.dart';
export 'src/paging.dart';

// Services
export 'src/services/supabase_service.dart';
export 'src/services/storage_service.dart';

// Repositories
export 'src/repositories/write_denied_exception.dart';
export 'src/repositories/auth_repository.dart';
export 'src/repositories/recipe_repository.dart';
export 'src/repositories/discover_repository.dart';
export 'src/repositories/profile_repository.dart';
export 'src/repositories/chef_repository.dart';
export 'src/repositories/food_repository.dart';

// Providers
export 'src/providers.dart';

// Re-export Supabase types commonly used by the UI layer.
export 'package:supabase_flutter/supabase_flutter.dart'
    show AuthState, AuthChangeEvent;
