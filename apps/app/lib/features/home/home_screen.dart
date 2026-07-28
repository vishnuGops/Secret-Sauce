import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/routing/app_router.dart';

/// Landing page: intro, feature highlights, and sign in / sign up.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _features = [
    _Feature(Icons.menu_book, 'Structured recipes',
        'Grouped ingredients and clear, step-by-step instructions anyone can follow.'),
    _Feature(Icons.call_split, 'Fork & improve',
        'Fork any recipe like code, tweak it to your taste, and keep the lineage intact.'),
    _Feature(Icons.history, 'Version history',
        'Every edit is saved as a version so legacy recipes are never lost.'),
    _Feature(Icons.lock_outline, 'Private or public',
        'Keep recipes private, share with specific people, or publish to Discover.'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.restaurant, color: scheme.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Text('Secret-Sauce',
                            style: textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        if (signedIn)
                          FilledButton(
                            onPressed: () => context.go(Routes.discover),
                            child: const Text('Open app'),
                          )
                        else ...[
                          TextButton(
                            onPressed: () => context.go(Routes.auth),
                            child: const Text('Sign in'),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          FilledButton(
                            onPressed: () => context.go(Routes.auth),
                            child: const Text('Sign up'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Text('Your family recipe vault.',
                        style: textTheme.displaySmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Document, preserve, and share cooking recipes the way they '
                      'deserve — beautifully structured and easy to follow. Fork '
                      'and improve recipes while keeping every generation’s version alive.',
                      style: textTheme.titleMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: [
                        FilledButton.icon(
                          onPressed: () => context
                              .go(signedIn ? Routes.discover : Routes.auth),
                          icon: const Icon(Icons.explore),
                          label: const Text('Explore recipes'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context
                              .go(signedIn ? Routes.newRecipe : Routes.auth),
                          icon: const Icon(Icons.add),
                          label: const Text('Add a recipe'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Text('Why Secret-Sauce',
                        style: textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.lg),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cols = constraints.maxWidth > 640 ? 2 : 1;
                        return GridView.count(
                          crossAxisCount: cols,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: AppSpacing.md,
                          crossAxisSpacing: AppSpacing.md,
                          childAspectRatio: 3.4,
                          children: [
                            for (final f in _features) _FeatureCard(feature: f),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature {
  const _Feature(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature});
  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(feature.icon, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(feature.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(feature.body,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
