import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/chefs/chefs_providers.dart';
import 'package:app/routing/app_router.dart';

/// The three shelves beside the board (web/medium only).
///
/// **Popular** is the top of the all-time board. **Trending** and **Best of the
/// month** are the top of `chefs_leaderboard_windowed` over 7 and 30 days
/// (Phase 33 — they were placeholder cards until the windowed SQL existed), and
/// they list only chefs who actually gained points in the window.
///
/// Every shelf has four states: placeholders while loading, an error, **empty**,
/// and cards. Empty is a real, loaded answer — nobody has published yet, or
/// nobody moved in the window (the stale-sim-anchor case) — so it keeps its
/// heading and says *why* in one sentence, the way Discover's shelves do
/// (UX-045). It is never a card-sized bordered box: in the fixed-height
/// two-column layout a sentence centred in a spotlight-card-sized tile sat
/// below the fold, and what showed was an empty frame.
class ChefsRails extends ConsumerWidget {
  const ChefsRails({super.key, required this.height, this.shrinkWrap = false});

  final double height;
  final bool shrinkWrap;

  /// Why Popular is empty: the board has nobody on it.
  static const String popularEmptyReason =
      'No chef has a public recipe yet, so nobody holds a rank. A chef joins '
      'the board with their first public recipe.';

  /// Why a windowed shelf is empty: nobody earned a point in [window].
  static String windowEmptyReason(ChefsWindow window) =>
      'No chef earned a like, save or view in the ${window.span} yet.';

  /// The note after the last card when the whole board fits on one page of
  /// the shelf (UX-045).
  static const String popularEndNote =
      'That is every ranked chef so far. A chef joins the board with their '
      'first public recipe.';

  /// The note after the last card of a short windowed shelf.
  static String windowEndNote(ChefsWindow window) =>
      'Nobody else earned points in the ${window.span}.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(popularChefsProvider);
    final total = ref.watch(chefCountProvider).valueOrNull;

    final popular = async.valueOrNull ?? const <ChefStanding>[];
    // Three states, not two. A board that has loaded and is genuinely empty
    // must not render a shelf of placeholders — that reads as "loading
    // forever" and claims a population the empty state right beside it denies.
    final loading = async.isLoading && popular.isEmpty;
    const title = 'Popular chefs';
    const subtitle = 'Most decorated kitchens, all time';

    return ListView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.zero,
      children: [
        if (async.hasError)
          _RailHeading(
            icon: Icons.favorite,
            title: title,
            subtitle: subtitle,
            child: ErrorView(
              message: friendlyError(async.error),
              onRetry: () => ref.invalidate(popularChefsProvider),
            ),
          )
        else if (!loading && popular.isEmpty)
          const _RailHeading(
            icon: Icons.favorite,
            title: title,
            subtitle: subtitle,
            reason: popularEmptyReason,
          )
        else
          CardRail(
            icon: Icons.favorite,
            title: title,
            subtitle: subtitle,
            height: height,
            cardWidth: kSpotlightCardWidth,
            // Placeholders while the board is still loading, so the shelf keeps
            // its height instead of collapsing and shoving the rails below it.
            itemCount:
                loading
                    ? kChefRailLength
                    : popular.length.clamp(1, kChefRailLength),
            trailing:
                loading || !_isShort(popular.length)
                    ? null
                    : _RailEndNote(text: popularEndNote, height: height),
            itemBuilder:
                (context, i) =>
                    loading
                        ? SpotlightCardPlaceholder(
                          tier: ChefTier.values[i % ChefTier.values.length],
                        )
                        : ChefSpotlightCard(
                          standing: popular[i],
                          totalChefs: total,
                          onTap: () => context.push(Routes.chef(popular[i].id)),
                        ),
          ),
        const SizedBox(height: AppSpacing.lg),
        _WindowRail(
          window: ChefsWindow.week,
          icon: Icons.trending_up,
          title: 'Trending chefs',
          height: height,
        ),
        const SizedBox(height: AppSpacing.lg),
        _WindowRail(
          window: ChefsWindow.month,
          icon: Icons.calendar_month,
          title: 'Best chefs of the month',
          height: height,
        ),
      ],
    );
  }
}

/// How many cards a rail's arrow press moves — `CardRail.page`'s default,
/// which the chefs rails keep.
const int _kRailPage = 3;

/// Whether a shelf of [cards] ends in a note (UX-045).
///
/// A shelf of one or two chefs left the rest of its row blank — about 45% of a
/// 1440px page with the one-chef population a fresh database has. The row is
/// not too narrow or capped (it already takes everything beside the 404px
/// board panel); it simply has nothing more to hold, and the honest thing to
/// put in that space is the sentence saying so. Only below a page
/// ([_kRailPage]). The note is the rail's `trailing`, outside its item count,
/// so neither the pager nor a screen reader counts it as a chef.
bool _isShort(int cards) => cards < _kRailPage;

/// One windowed shelf: loading placeholders, an error, a quiet window, or the
/// chefs who moved, ranked by the points they earned in it.
class _WindowRail extends ConsumerWidget {
  const _WindowRail({
    required this.window,
    required this.icon,
    required this.title,
    required this.height,
  });

  final ChefsWindow window;
  final IconData icon;
  final String title;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(windowRailProvider(window));
    final subtitle = 'Most points earned in the ${window.span}';

    if (async.hasError && !async.isLoading) {
      return _RailHeading(
        icon: icon,
        title: title,
        subtitle: subtitle,
        child: ErrorView(
          message: friendlyError(async.error),
          onRetry: () => ref.invalidate(windowRailProvider(window)),
        ),
      );
    }

    final chefs = async.valueOrNull;
    if (chefs == null) {
      return CardRail(
        icon: icon,
        title: title,
        subtitle: subtitle,
        height: height,
        cardWidth: kSpotlightCardWidth,
        itemCount: 6,
        itemBuilder:
            (context, i) => SpotlightCardPlaceholder(
              tier: ChefTier.values[i % ChefTier.values.length],
            ),
      );
    }

    // Nobody moved. On a real deployment that is a quiet week; on a simulated
    // one whose `sim.epoch_end()` anchor has gone stale it is every week — old
    // data, not a broken query, which is why this names the window rather than
    // apologising for an error.
    if (chefs.isEmpty) {
      return _RailHeading(
        icon: icon,
        title: title,
        subtitle: subtitle,
        reason: ChefsRails.windowEmptyReason(window),
      );
    }

    return CardRail(
      icon: icon,
      title: title,
      subtitle: subtitle,
      height: height,
      cardWidth: kSpotlightCardWidth,
      itemCount: chefs.length,
      trailing:
          _isShort(chefs.length)
              ? _RailEndNote(
                text: ChefsRails.windowEndNote(window),
                height: height,
              )
              : null,
      itemBuilder:
          (context, i) => ChefSpotlightCard(
            standing: chefs[i].standing,
            window: chefs[i].window,
            windowLabel: window.span,
            // No denominator: the rank here is the rank *in the
            // window*, and "4 / 148" would read as the all-time board.
            onTap: () => context.push(Routes.chef(chefs[i].id)),
          ),
    );
  }
}

/// A shelf's heading over something that is not a row of cards — the reason
/// it is empty, or an error (UX-045).
///
/// The heading is the shelf's own: a [CardRail] with no cards and no height
/// draws exactly the badged header a populated shelf does (icon tile, a
/// `Semantics(header: true)` title, the subtitle), so an empty shelf still
/// reads as one of three and heading navigation still lands on it. The reason
/// is the rail's footnote — one plain sentence, no frame around it.
class _RailHeading extends StatelessWidget {
  const _RailHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.reason,
    this.child,
  }) : assert((reason == null) != (child == null), 'a reason or a child');

  final IconData icon;
  final String title;
  final String subtitle;

  /// Why the shelf is empty.
  final String? reason;

  /// Drawn under the heading instead of a reason — the error state.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final heading = CardRail(
      icon: icon,
      title: title,
      subtitle: subtitle,
      height: 0,
      cardWidth: kSpotlightCardWidth,
      itemCount: 0,
      itemBuilder: (_, __) => const SizedBox.shrink(),
      footnote: reason,
    );
    if (child == null) return heading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [heading, child!],
    );
  }
}

/// The sentence after the last card of a short shelf (UX-045): the space a
/// card would take, holding the reason there is no further card.
///
/// Plain text, no border and no fill — a framed tile at card size is what the
/// audit read as an empty box, and it would claim a slot the population does
/// not have.
class _RailEndNote extends StatelessWidget {
  const _RailEndNote({required this.text, required this.height});

  final String text;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: kSpotlightCardWidth,
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
