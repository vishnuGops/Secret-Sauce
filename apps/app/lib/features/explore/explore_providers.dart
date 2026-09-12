import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `/explore` — the corpus (Phase 35c).
///
/// One paged list, like every other browsing surface, and the same
/// [PagedRecipesNotifier] machinery. What differs is the ordering it inherits
/// from `recipes_corpus`: imported recipes carry no engagement, so the RPC
/// sorts on `quality_score` and ends in `id` — `offset` is only meaningful over
/// a total order, and a score out of 100 across 21,000 rows ties constantly
/// (Gotcha 24).
class CorpusRecipesNotifier extends PagedRecipesNotifier {
  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) {
    return ref
        .read(discoverRepositoryProvider)
        .corpus(limit: limit, offset: offset);
  }
}

final corpusRecipesProvider =
    AsyncNotifierProvider.autoDispose<CorpusRecipesNotifier, RecipePage>(
      CorpusRecipesNotifier.new,
    );

/// How many recipes the corpus holds.
///
/// Shown on the page because the honest way to describe a collection this size
/// is to say how big it is — and because the number is the reason the page
/// exists separately from Discover at all.
final corpusCountProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(discoverRepositoryProvider).corpusCount();
});
