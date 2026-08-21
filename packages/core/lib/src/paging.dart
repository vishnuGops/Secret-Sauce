import 'package:flutter/foundation.dart' show protected;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:core/src/models/recipe.dart';

/// How many recipes one page of a browsing surface holds (OPT-P9).
///
/// Discover and My Recipes were capped at 20/30 rows or unbounded, so a vault
/// with 400 recipes either showed 20 of them forever or decoded all 400 on
/// every visit. One number for every surface on purpose: the page size is the
/// unit `loadMore` advances by, and a surface whose size differs from its
/// offsets is how a row gets skipped.
const int kRecipePageSize = 20;

/// One page-at-a-time recipe list: everything loaded so far, whether the server
/// looks like it has more, and whether the next page is in flight.
///
/// `loadingMore` lives in the data rather than in an [AsyncLoading] state so the
/// rows already on screen stay on screen while the next page loads — an
/// `AsyncLoading` would replace the whole grid with a spinner on every tap of
/// Load more.
class RecipePage {
  const RecipePage({
    this.recipes = const [],
    this.hasMore = false,
    this.loadingMore = false,
  });

  final List<Recipe> recipes;

  /// True when the last fetch came back **full**, which is the only evidence a
  /// `limit`/`offset` read gives that more rows exist. A total that happens to
  /// be an exact multiple of [kRecipePageSize] therefore costs one extra
  /// request that returns nothing and clears the flag — cheaper than a
  /// `count(*)` on every page.
  final bool hasMore;

  final bool loadingMore;

  RecipePage copyWith({
    List<Recipe>? recipes,
    bool? hasMore,
    bool? loadingMore,
  }) {
    return RecipePage(
      recipes: recipes ?? this.recipes,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
    );
  }
}

/// Base for every paged recipe surface (OPT-P9): Discover's four lists and My
/// Recipes' two tabs.
///
/// Subclasses implement [fetchPage] — one repository call taking `limit` and
/// `offset` — and get the first page, [loadMore], de-duplication, and the
/// in-flight flag for free. It lives in `core` rather than beside one of the
/// features because both features need it and neither owns it; it is provider
/// layer, not UI, so it takes a repository call and returns state.
abstract class PagedRecipesNotifier
    extends AutoDisposeAsyncNotifier<RecipePage> {
  /// Rows per request. Override only with a reason — see [kRecipePageSize].
  int get pageSize => kRecipePageSize;

  /// One page from the server. `offset` is always a multiple of [pageSize].
  Future<List<Recipe>> fetchPage({required int limit, required int offset});

  bool _disposed = false;

  /// Whether this build has been torn down. [loadMore] can outlive the screen
  /// that started it — leaving Discover mid-request disposes the provider
  /// (nothing is listening any more) long before the rows come back, and
  /// `state =` on a disposed notifier throws.
  @protected
  bool get isDisposed => _disposed;

  /// The first page. Overridden by surfaces that must gate the request — search
  /// waits out its debounce here. Anything reading `ref.watch` must do it
  /// **before the first `await`**, which is what keeps this a build-phase call.
  @protected
  Future<RecipePage> firstPage() async {
    final rows = await fetchPage(limit: pageSize, offset: 0);
    return RecipePage(recipes: rows, hasMore: rows.length == pageSize);
  }

  @override
  Future<RecipePage> build() {
    // Re-armed per build: `onDispose` also fires when the provider *rebuilds*
    // (a new search query, a new session) and the notifier instance survives
    // that, so a stale `true` here would freeze `loadMore` for good.
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    return firstPage();
  }

  /// Append the next page. Safe to call twice — the second call returns
  /// immediately while the first is in flight.
  ///
  /// On failure the list is left exactly as it was and the error is rethrown, so
  /// the caller can surface it without the page collapsing to an error screen:
  /// the rows already loaded are still valid.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final rows = await fetchPage(
        limit: pageSize,
        offset: current.recipes.length,
      );
      if (_disposed) return;

      // The offset is only as stable as the server's ordering. Every list this
      // backs has a total order (the Discover RPCs tie-break down to `id`), but
      // a recipe created, deleted, or made private between two pages still
      // shifts the window — so a row already on screen is dropped rather than
      // shown twice.
      final seen = {for (final r in current.recipes) r.id};
      final fresh = [
        for (final r in rows)
          if (seen.add(r.id)) r,
      ];

      state = AsyncData(
        RecipePage(
          recipes: [...current.recipes, ...fresh],
          // Judged on what the server returned, not on what survived the
          // de-dup: a full page that was entirely duplicates still means there
          // is more behind it.
          hasMore: rows.length == pageSize,
        ),
      );
    } catch (_) {
      if (!_disposed) state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }
}
