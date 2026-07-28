import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/auth/auth_controller.dart';
import 'package:app/routing/app_router.dart';

final _myProfileProvider = FutureProvider.autoDispose<Profile?>((ref) {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return Future.value(null);
  return ref.watch(profileRepositoryProvider).getById(id);
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (profile) {
          if (profile == null) {
            return EmptyView(
              title: 'Not signed in',
              action: FilledButton(
                onPressed: () => context.go(Routes.auth),
                child: const Text('Sign in'),
              ),
            );
          }
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 44,
                  backgroundColor: scheme.primaryContainer,
                  backgroundImage: (profile.avatarUrl?.isNotEmpty ?? false)
                      ? NetworkImage(profile.avatarUrl!)
                      : null,
                  child: (profile.avatarUrl?.isEmpty ?? true)
                      ? Text(
                          profile.displayName.isEmpty
                              ? '?'
                              : profile.displayName[0].toUpperCase(),
                          style: Theme.of(context).textTheme.headlineMedium,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Text(
                  profile.displayName.isEmpty ? 'Unnamed cook' : profile.displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Center(child: Text(profile.bio!)),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton.tonalIcon(
                onPressed: () => context.go(Routes.newRecipe),
                icon: const Icon(Icons.add),
                label: const Text('New recipe'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(authControllerProvider.notifier).signOut();
                  if (context.mounted) context.go(Routes.home);
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          );
        },
      ),
    );
  }
}
