import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/profile.dart';
import 'package:core/src/repositories/auth_repository.dart';
import 'package:core/src/repositories/chef_repository.dart';
import 'package:core/src/repositories/discover_repository.dart';
import 'package:core/src/repositories/food_repository.dart';
import 'package:core/src/repositories/profile_id.dart';
import 'package:core/src/repositories/profile_repository.dart';
import 'package:core/src/repositories/recipe_repository.dart';
import 'package:core/src/services/storage_service.dart';
import 'package:core/src/services/supabase_service.dart';

/// The shared Supabase client.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseService.client;
});

/// Resolves the signed-in account to its `profiles.id`, once per session
/// (Phase 35b).
///
/// A `Provider`, so both repositories below share **one** cache. That is not a
/// micro-optimisation: an approved claim moves an account's link without
/// changing its auth uid, so a second resolver keyed on the auth uid would go
/// on returning the old profile id and every write it fed would be denied by
/// RLS — silently, on update and delete (Gotcha 2). One cache, one
/// [ProfileIdResolver.invalidate].
final profileIdResolverProvider = Provider<ProfileIdResolver>((ref) {
  return ProfileIdResolver(ref.watch(supabaseClientProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(
    ref.watch(supabaseClientProvider),
    profileIds: ref.watch(profileIdResolverProvider),
  );
});

final recipeRepositoryProvider = Provider<RecipeRepository>((ref) {
  return SupabaseRecipeRepository(
    ref.watch(supabaseClientProvider),
    profileIds: ref.watch(profileIdResolverProvider),
  );
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

/// The signed-in user's own `profiles.id`, or null when signed out.
///
/// **Not the same value as [currentUserIdProvider] in general.** They agree for
/// every member, because `handle_new_user` writes `id = new.id` — and they stop
/// agreeing the moment someone claims an imported chef page, which is the one
/// case Phase 35b exists for. Anything that reads or writes a row keyed on a
/// `profiles` id wants this one; `currentUserIdProvider` is for auth questions
/// ("is anyone signed in") and for the storage bucket, whose folders are still
/// namespaced by the auth uid.
///
/// It goes through [AuthRepository] rather than the client directly so the
/// whole graph stays swappable behind one override — the same reason every
/// other cross-cutting provider here names a repository.
final currentProfileIdProvider = FutureProvider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).currentProfileId();
});

/// The signed-in user's own profile, or null when signed out.
///
/// Cross-cutting: the web top navigation's account avatar and the profile
/// screen both read it, and it re-resolves on every auth change because it
/// watches [currentProfileIdProvider], which watches the auth stream.
final myProfileProvider = FutureProvider.autoDispose<Profile?>((ref) async {
  final id = await ref.watch(currentProfileIdProvider.future);
  if (id == null) return null;
  return ref.watch(profileRepositoryProvider).getById(id);
});
