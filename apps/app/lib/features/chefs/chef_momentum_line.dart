import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/chefs/chef_detail_common.dart';
import 'package:app/features/chefs/chefs_providers.dart';

/// What this chef earned in the last [kChefMomentumDays] days, on `/chef/:id`
/// (Phase 33): `+312 points · 40 likes · 12 saves · 60 views · 2 new recipes`.
///
/// Read from `chef_window_stats` with `p_chef` — the same function the Momentum
/// board ranks — so this line and the board can never disagree about a chef.
/// Rendered only for a ranked chef (the page decides), and secondary to the
/// page: a failure here costs this line, not the page, which is why it is a
/// separate provider rather than a fourth read inside `chefPageProvider`.
///
/// A `Wrap` of short clauses, so a phone at 2.0× text scale costs it lines
/// rather than overflowing it.
class ChefMomentumLine extends ConsumerWidget {
  const ChefMomentumLine({super.key, required this.chefId});

  final String chefId;

  static const _span = 'last $kChefMomentumDays days';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final async = ref.watch(chefMomentumProvider(chefId));

    return async.when(
      // Nothing while in flight: the line is one row under a panel that has
      // already rendered, and a spinner there would draw the eye to the one
      // part of the page that matters least.
      loading: () => const SizedBox.shrink(),
      error: (e, _) => ChefNote(text: friendlyError(e)),
      data: (w) {
        if (w == null) return const SizedBox.shrink();

        // Tabular: every clause but the quiet one is a count (UX-049).
        final muted = theme.textTheme.bodySmall?.tabular.copyWith(
          color: scheme.onSurfaceVariant,
        );
        final facts = <Widget>[
          if (w.moved)
            Text(
              '${w.gainLabel} points',
              style: context.appText.quantity.copyWith(color: scheme.primary),
            )
          else
            // A quiet window is an answer, not an absence: say it, the way the
            // board's empty state does.
            Text('No likes, saves or views on public recipes', style: muted),
          if (w.moved) ...[
            Text(countOf(w.likes, 'likes'), style: muted),
            Text(countOf(w.saves, 'saves'), style: muted),
            // Distinct signed-in viewers **per recipe**, summed — one person who
            // reads five of this chef's recipes counts five. That is exactly
            // what the all-time `views` figure counts (B012, Gotcha 10), so it
            // takes the same word; "readers" promised distinct people.
            Text(countOf(w.viewers, 'views'), style: muted),
          ],
          if (w.newRecipes > 0)
            Text(countOf(w.newRecipes, 'new recipes'), style: muted),
          if (w.ratings > 0) Text(countOf(w.ratings, 'ratings'), style: muted),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChefKicker(text: _span),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: facts,
            ),
          ],
        );
      },
    );
  }
}
