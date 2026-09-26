import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/explore/explore_providers.dart';
import 'package:app/features/legal/legal_document.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/routing/pop_or_go.dart';
import 'package:app/widgets/recipe_async_grid.dart';
import 'package:app/widgets/route_title.dart';

/// `/explore` — recipes captured from the public web (Phase 35c).
///
/// Deliberately its own page rather than a fourth sort on Discover. Two
/// reasons, and the second is the one that matters:
///
///  * **It cannot be ranked with the rest.** Imported recipes arrive with every
///    counter at zero, so mixing them into Popular or Trending would order
///    21,000 identical scores by whatever the tie-break happens to be and bury
///    the recipes people here actually wrote.
///  * **It has to introduce itself.** These are other people's recipes, shown
///    with the credit and a link back. A reader who cannot tell that from the
///    grid has been misled by the layout, whatever the individual cards say —
///    so the page states it above the first card and links to the Rights page.
///
/// Root navigator, signed-out safe, and **no nav destination** (Gotcha 18): a
/// fifth entry costs the web pill its labels, so this is reached from Discover.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pad = context.isCompact ? AppSpacing.md : AppSpacing.lg;

    return RouteTitle(
      // UX-051.
      page: 'Explore',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('From around the web'),
          leading: BackButton(
            onPressed: () => popOrGo(context, Routes.discover),
          ),
        ),
        // The page owns its scroll, so the grid has to be the SLIVER form
        // (Gotcha 24): `RecipeAsyncGrid` is a `CustomScrollView` and putting one
        // inside another is a scrollable inside a scrollable.
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, AppSpacing.md),
              sliver: const SliverToBoxAdapter(child: _Preamble()),
            ),
            RecipeAsyncSliverGrid<CorpusRecipesNotifier>(
              provider: corpusRecipesProvider,
              padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
              // UX-046: written for a reader. It used to explain that an import
              // had not been run "against this database" — true, and nothing a
              // cook can act on. It says what will be here, why it can be empty,
              // and where the recipes that do exist are.
              empty: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: EmptyView(
                  icon: Icons.travel_explore_outlined,
                  title: 'Nothing from the web yet',
                  message:
                      'This is where recipes published elsewhere will appear, '
                      'each credited to its cook with a link back to the '
                      'original. None have been added yet — in the meantime, '
                      'Discover has everything cooks here have shared.',
                  action: TextButton(
                    onPressed: () => popOrGo(context, Routes.discover),
                    child: const Text('Go to Discover'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What this collection is, said before the first card rather than after it.
class _Preamble extends ConsumerWidget {
  const _Preamble();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = ref.watch(corpusCountProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count.maybeWhen(
            data: (n) => '${_grouped(n)} recipes from cooks across the web',
            orElse: () => 'Recipes from cooks across the web',
          ),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Every recipe here was published somewhere else. We keep the '
          'ingredients and the method, credit the cook and the publisher, and '
          'link back to the original — we do not copy their photographs or '
          'their writing. They carry no ratings or scores here, so they are '
          'ordered by how complete the record is.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Wrap rather than Row: two buttons at 2.0x text scale do not share a
        // line on a 390px phone.
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            TextButton.icon(
              onPressed: () => context.push(Routes.legal(LegalDoc.rights.slug)),
              icon: const Icon(Icons.gavel_outlined, size: AppIconSize.button),
              label: const Text('How we credit these'),
            ),
          ],
        ),
      ],
    );
  }

  /// `21,334`. Restated here rather than reaching for a formatter that does not
  /// exist in `core` for plain integers — the counters on a card go through
  /// `compactCount`, which abbreviates, and an abbreviated corpus size reads as
  /// vagueness about how much of somebody else's work this holds.
  static String _grouped(int n) {
    final digits = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}
