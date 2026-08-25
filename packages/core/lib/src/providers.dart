import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/profile.dart';
import 'package:core/src/repositories/auth_repository.dart';
import 'package:core/src/repositories/chef_repository.dart';
import 'package:core/src/repositories/discover_repository.dart';
import 'package:core/src/repositories/food_repository.dart';
import 'package:core/src/repositories/profile_repository.dart';
import 'package:core/src/repositories/recipe_repository.dart';
import 'package:core/src/services/storage_service.dart';
import 'package:core/src/services/supabase_service.dart';

/// The shared Supabase client.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseService.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.watch(supabaseClientProvider));
});

final recipeRepositoryProvider = Provider<RecipeRepository>((ref) {
  return SupabaseRecipeRepository(ref.watch(supabaseClientProvider));
});

final discoverRepositoryProvider = Provider<DiscoverRepository>((ref) {
  return SupabaseDiscoverRepository(ref.watch(supabaseClientProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return SupabaseProfileRepository(ref.watch(supabaseClientProvider));
});

final chefRepositoryProvider = Provider<ChefRepository>((ref) {
  return SupabaseChefRepository(ref.watch(supabaseClientProvider));
});

final foodRepositoryProvider = Provider<FoodRepository>((ref) {
  return SupabaseFoodRepository(ref.watch(supabaseClientProvider));
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(ref.watch(supabaseClientProvider));
});

/// Streams Supabase auth state; drives routing/redirects.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Convenience: current user id (null when signed out).
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).currentUserId;
});

/// The signed-in user's own profile, or null when signed out.
///
/// Cross-cutting: the web top navigation's account avatar and the profile
/// screen both read it, and it re-resolves on every auth change because it
/// watches [currentUserIdProvider].
final myProfileProvider = FutureProvider.autoDispose<Profile?>((ref) {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return Future.value(null);
  return ref.watch(profileRepositoryProvider).getById(id);
});
