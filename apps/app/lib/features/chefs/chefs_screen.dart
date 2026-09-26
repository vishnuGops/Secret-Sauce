import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/chefs/chef_detail_common.dart';
import 'package:app/features/chefs/chefs_hero.dart';
import 'package:app/features/chefs/chefs_providers.dart';
import 'package:app/features/chefs/chefs_rails.dart';
import 'package:app/routing/app_router.dart';

/// Chefs leaderboard — ranked by chef score over each chef's public recipes, or
/// (Phase 33) by what they earned this month or week, or by join date.
///
/// Two layouts, one screen. On a phone this is the board and nothing else. From
/// [Breakpoints.compact] up it is the page from the redraw: a hero stating the
/// population and the ranking rule, the board demoted to a panel on the left,
/// and rails of spotlight cards on the right.
///
/// **No `AppBar` from compact up** (the Phase 21 carry-over, for this screen):
/// the web shell already draws `TopNavBar` above every shell screen, so a
/// second bar under it was chrome stacked on chrome — and the hero's `Chefs`
/// display title is the page title there. A phone has no top bar, so the
/// compact board keeps its own. `chefs_screen_test.dart` pins both halves.
///
/// Signed-out safe, like Discover: every read behind it is `anon`-callable, so
/// this route is deliberately absent from the router's `needsAuth` list.
class ChefsScreen extends ConsumerWidget {
  const ChefsScreen({super.key});

  /// Width of the leaderboard panel beside the rails, from the draft.
  static const double panelWidth = 404;

  /// Above this text scale the two-column layout stops being a layout.
  ///
  /// The columns are fixed-height — a 404px panel beside the rails, under a
  /// hero that does not scroll — so all three have to fit the viewport at once.
  /// At 2.0× the hero alone is taller than a 1200px window, which is the
  /// overflow this bound exists to prevent. Past it the page becomes one
  /// scroll, which has no such constraint.
  static const double maxTwoColumnTextScale = 1.3;

  /// The board panel's header inset (top 14, bottom 10 — the draft's).
  static const EdgeInsets _panelHeaderPadding = EdgeInsets.fromLTRB(
    AppSpacing.md,
    14,
    AppSpacing.md,
    10,
  );

  /// The panel footer's left inset: lines the footnote up with a board row's
  /// text rather than with the panel edge.
  static const double _panelFooterStart = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (context.isCompact) return const _CompactBoard();

    final wide =
        context.isExpanded && context.textScale <= maxTwoColumnTextScale;
    final railHeight = spotlightCardHeight(context);

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          wide ? AppSpacing.xl : AppSpacing.md,
          AppSpacing.lg,
          wide ? AppSpacing.xl : AppSpacing.md,
          wide ? AppSpacing.xl : AppSpacing.md,
        ),
        child:
            wide
                ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ChefsHero(),
                    const SizedBox(height: AppSpacing.lg),
                    // Two independently scrolling columns under a fixed hero.
                    // The draft scrolls the page and pins the panel with
                    // `position: sticky`; the panel already owns a scroll
                    // container there, so this renders the same thing without a
                    // nested-scroll arrangement to get wrong.
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(
                            width: panelWidth,
                            child: _BoardPanel(scrollable: true),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(child: ChefsRails(height: railHeight)),
                        ],
                      ),
                    ),
                  ],
                )
                // Below 1000px — or above the text scale the columns can hold —
                // the page becomes one scroll, rails first: they are the part of
                // this redraw a narrow window can still show properly.
                : ListView(
                  children: [
                    const ChefsHero(),
                    const SizedBox(height: AppSpacing.lg),
                    ChefsRails(height: railHeight, shrinkWrap: true),
                    const SizedBox(height: AppSpacing.lg),
                    const _BoardPanel(scrollable: false),
                  ],
                ),
      ),
    );
  }
}

/// The phone board: the ranked rows under the two controls the web hero and
/// panel carry — the ordering, and (on Momentum) the window.
///
/// One scroll holding the controls **and** whatever state the board is in, so
/// an empty Momentum week still shows the tabs that lead back out of it, and a
/// pull-to-refresh works from every state.
class _CompactBoard extends ConsumerWidget {
  const _CompactBoard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chefBoardProvider);
    final view = ref.watch(boardViewProvider);
    final page = async.valueOrNull;

    final Widget? state = switch (async) {
      _ when _showsSpinner(async) => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: LoadingView(),
      ),
      AsyncValue(:final error?) => ErrorView(
        message: friendlyError(error),
        onRetry: () => ref.invalidate(chefBoardProvider),
      ),
      _ when page != null && page.rows.isEmpty => _BoardEmpty(view: view),
      _ => null,
    };
    final rows = state == null ? page!.rows : const <ChefBoardRow>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Chefs')),
      body: RefreshIndicator(
        onRefresh: () async {
          // A failed refresh lands in the error state above; the indicator
          // only needs to know the attempt finished.
          try {
            ref.invalidate(chefBoardProvider);
            await ref.read(chefBoardProvider.future);
          } catch (_) {}
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.md),
          // Controls, then either the one state widget or every row, then the
          // footer.
          itemCount: 1 + (state == null ? rows.length : 1) + 1,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, i) {
            if (i == 0) return const _BoardControls(showWindow: true);
            if (state != null) {
              return i == 1 ? state : const SizedBox.shrink();
            }
            if (i <= rows.length) {
              return _BoardCard(row: rows[i - 1], view: view);
            }
            return page!.hasMore
                ? _LoadMoreButton(loading: page.loadingMore)
                : const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

/// Whether the board should show a spinner rather than rows: the first load,
/// and a **re-sort**. Riverpod keeps the previous value while a provider
/// rebuilds for a changed dependency (`isReloading`), which here would leave
/// the last ordering's rows on screen under the new tab — a Momentum week's
/// gains labelled as last month's. A pull-to-refresh (`isRefreshing`) keeps
/// its rows, because they are still the right ordering.
bool _showsSpinner(AsyncValue<ChefBoardPage> async) =>
    async.isLoading && (!async.hasValue || async.isReloading);

/// The ordering pill, and — on a phone, where there is no hero — the window
/// pill under it while Momentum is selected.
class _BoardControls extends ConsumerWidget {
  const _BoardControls({required this.showWindow});

  /// True on compact, where the hero (and its Month / Week) is absent.
  final bool showWindow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(boardViewProvider);
    final notifier = ref.read(boardViewProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChefPillTabs<BoardSort>(
          options: BoardSort.values,
          selected: view.sort,
          labelOf: (sort) => sort.label,
          onSelected: notifier.selectSort,
        ),
        if (showWindow && view.sort == BoardSort.momentum) ...[
          const SizedBox(height: AppSpacing.sm),
          ChefPillTabs<ChefsWindow>(
            // All time is not a Momentum window — it is the Score tab.
            options: const [ChefsWindow.month, ChefsWindow.week],
            selected: view.window,
            labelOf: (window) => window.label,
            onSelected: notifier.selectWindow,
          ),
        ],
      ],
    );
  }
}

/// One board row, in whichever shape the layout asks for, carrying the window
/// on Momentum and the join date on `New`.
class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.row, required this.view, this.variant});

  final ChefBoardRow row;
  final BoardView view;

  /// Null is the podium row, sized for the ambient width.
  final ChefCardVariant? variant;

  @override
  Widget build(BuildContext context) {
    final joined = row.standing.createdAt;
    return ChefStandingCard(
      standing: row.standing,
      variant: variant ?? ChefCardVariant.podium,
      window: row.window,
      windowLabel: view.window.span,
      note:
          view.sort == BoardSort.newest && joined != null
              ? 'joined ${monthYear(joined.toLocal())}'
              : null,
      onTap: () => context.push(Routes.chef(row.standing.id)),
    );
  }
}

/// A loaded board with no rows — two different sentences.
///
/// On Score or New it means nobody has published yet. On Momentum it means
/// nobody **moved** in the window, which is a statement about the data, not a
/// failure: a simulated database whose `sim.epoch_end()` anchor has gone stale
/// returns exactly this, correctly. Hence a real state with a way back to the
/// all-time board, never a spinner.
class _BoardEmpty extends ConsumerWidget {
  const _BoardEmpty({required this.view});

  final BoardView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (view.sort != BoardSort.momentum) {
      return const EmptyView(
        title: 'No chefs yet',
        message: 'Publish a recipe and you will show up here.',
        icon: Icons.emoji_events_outlined,
      );
    }
    return EmptyView(
      title: 'Nothing moved in the ${view.window.span}',
      message:
          'No public recipe earned a like, save or view in that time. '
          'The Score board still ranks every chef on all-time points.',
      icon: Icons.hourglass_empty,
      action: TextButton(
        onPressed:
            () => ref
                .read(boardViewProvider.notifier)
                .selectSort(BoardSort.score),
        child: const Text('Show all-time scores'),
      ),
    );
  }
}

/// The ranked board, as a panel: header, ordering tabs, rows, and a footer that
/// loads the next page.
class _BoardPanel extends ConsumerWidget {
  const _BoardPanel({required this.scrollable});

  /// True when the panel owns its own scroll (the two-column layout); false
  /// when it sits inside the page's scroll and must size to its content.
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final async = ref.watch(chefBoardProvider);
    final total = ref.watch(chefCountProvider).valueOrNull;
    final view = ref.watch(boardViewProvider);
    final page = async.valueOrNull;

    final Widget rows = switch (async) {
      _ when _showsSpinner(async) => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: LoadingView(),
      ),
      AsyncValue(:final error?) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: ErrorView(
          message: friendlyError(error),
          onRetry: () => ref.invalidate(chefBoardProvider),
        ),
      ),
      _ when page!.rows.isEmpty => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: _BoardEmpty(view: view),
      ),
      _ => ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.sm),
        shrinkWrap: !scrollable,
        physics: scrollable ? null : const NeverScrollableScrollPhysics(),
        itemCount: page.rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xsPlus),
        itemBuilder:
            (context, i) => _BoardCard(
              row: page.rows[i],
              view: view,
              variant: ChefCardVariant.board,
            ),
      ),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: ChefsScreen._panelHeaderPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.leaderboard,
                      size: AppIconSize.md,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      // The panel's section heading (UX-014).
                      child: Semantics(
                        container: true,
                        header: true,
                        child: Text(
                          'Leaderboard',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _shownLabel(page?.rows.length, total, view.sort),
                      // `TOP 25 / 148`: counts, so tabular (UX-049).
                      style: context.appText.overline.tabular.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                // The hero carries Month / Week on this layout.
                const _BoardControls(showWindow: false),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          if (scrollable)
            Expanded(
              // The list scrolls itself; the spinner, error and empty states
              // do not, and in the two-column layout this panel's height is
              // fixed by the page (Gotcha 22). The empty board — the real state
              // until real people use it (B113) — overflowed by 12px at 1000px
              // once the window filter grew its 48px targets (UX-048).
              child:
                  rows is ListView ? rows : SingleChildScrollView(child: rows),
            )
          else
            rows,
          Divider(height: 1, color: scheme.outlineVariant),
          // No footer button under a re-sort's spinner: `page` is still the
          // previous ordering's, and paging it would mix two orderings.
          _PanelFooter(page: _showsSpinner(async) ? null : page, view: view),
        ],
      ),
    );
  }

  /// `TOP 25 / 148` — or just the total until the rows land. Momentum has no
  /// denominator: it lists only the chefs who moved, and how many that is is
  /// not known until the last page.
  static String _shownLabel(int? loaded, int? total, BoardSort sort) {
    final prefix = sort == BoardSort.newest ? 'NEWEST' : 'TOP';
    if (loaded == null) return total == null ? '' : groupedCount(total);
    if (total == null || sort == BoardSort.momentum) {
      return '$prefix ${groupedCount(loaded)}';
    }
    return '$prefix ${groupedCount(loaded)} / ${groupedCount(total)}';
  }
}

class _PanelFooter extends StatelessWidget {
  const _PanelFooter({required this.page, required this.view});

  final ChefBoardPage? page;
  final BoardView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final more = page?.hasMore ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ChefsScreen._panelFooterStart,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xsPlus,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              switch (view.sort) {
                // The rank pill on a `New` row is still the all-time rank,
                // which reads as out of order unless it is said.
                BoardSort.newest => 'Newest first. Ranks are all-time.',
                BoardSort.momentum =>
                  'Points earned in the ${view.window.span}.',
                BoardSort.score => 'Ties share a rank.',
              },
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (more) _LoadMoreButton(loading: page!.loadingMore, dense: true),
        ],
      ),
    );
  }
}

/// `Load more` for the board, wired to [chefBoardProvider]. The control itself
/// — disabled spinner while in flight, the snackbar on a failed page — is the
/// shared [LoadMoreButton] every paged recipe grid uses too (UX-032).
class _LoadMoreButton extends ConsumerWidget {
  const _LoadMoreButton({required this.loading, this.dense = false});

  final bool loading;

  /// The panel footer's inline form, beside the footnote.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final button = LoadMoreButton(
      loading: loading,
      dense: dense,
      onPressed: () => ref.read(chefBoardProvider.notifier).loadMore(),
    );
    return dense ? button : Center(child: button);
  }
}
