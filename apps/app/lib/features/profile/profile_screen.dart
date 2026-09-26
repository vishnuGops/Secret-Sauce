import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/profile/edit_profile_dialog.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/routing/auth_return.dart';
import 'package:app/widgets/legal_footer.dart';

/// The profile's avatar (88 wide).
const double _kAvatarRadius = 44;

/// The page's reading measure (UX-038). At 1440 the buttons used to stretch
/// the full 1392px; the page is a short column of identity and actions, so it
/// is centred at a width a form would have.
const double kProfileMaxWidth = AppMeasure.column;

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _edit(BuildContext context, Profile profile) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showEditProfileDialog(context, profile);
    if (saved == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Profile updated')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Shared with the top navigation's account avatar — one read, one cache.
    final async = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: friendlyError(e)),
        data: (profile) {
          if (profile == null) {
            return EmptyView(
              title: 'Not signed in',
              action: FilledButton(
                // UX-017: remember `/profile`, so signing in comes back here.
                onPressed: () => goToSignIn(context),
                child: const Text('Sign in'),
              ),
            );
          }
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kProfileMaxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        // ChefAvatar, not a bare CircleAvatar: it falls back
                        // to an icon when the photo URL is broken (UX-053)
                        // and is the one avatar the rest of the app draws
                        // (UX-032).
                        child: ChefAvatar(
                          name: profile.displayName,
                          avatarUrl: profile.avatarUrl,
                          radius: _kAvatarRadius,
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        profile.displayName.isEmpty
                            ? 'Unnamed cook'
                            : profile.displayName,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Center(child: TierChip(tier: profile.chefTier)),
                      if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(profile.bio!, textAlign: TextAlign.center),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      FilledButton.icon(
                        onPressed: () => _edit(context, profile),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit profile'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // `profile.id` is `profiles.id` — the key `/chef/:id`
                      // takes — not the auth uid (Phase 35b).
                      OutlinedButton.icon(
                        onPressed: () => context.push(Routes.chef(profile.id)),
                        icon: const Icon(Icons.storefront_outlined),
                        label: const Text('View my chef page'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton.tonalIcon(
                        onPressed: () => context.go(Routes.newRecipe),
                        icon: const Icon(Icons.add),
                        label: const Text('New recipe'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: () async {
                          // The repository directly (OPT-A3) — see the same
                          // call in `top_nav_bar.dart`.
                          await ref.read(authRepositoryProvider).signOut();
                          // Signing out here would otherwise leave the visitor
                          // on `/profile`, which the redirect then bounces to
                          // `/auth`.
                          if (context.mounted) context.go(Routes.discover);
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out'),
                      ),
                      // Phase 35a. On compact this is the only screen a
                      // signed-in reader can reach the legal documents from —
                      // the phone's bottom slot belongs to the NavigationBar.
                      // Wider, the web shell already carries them in its own
                      // bar, and a second copy here was UX-038's "legal x2".
                      // A signed-out phone reader gets them from the sign-up
                      // form instead.
                      if (context.isCompact) ...[
                        const SizedBox(height: AppSpacing.xl),
                        const LegalFooter(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
