// OPT-P8: Discover's search field writes `searchQueryProvider` on every
// keystroke, which invalidates `searchResultsProvider`. Without a debounce,
// typing "chicken" fired seven `recipes_search` RPCs and used one.
//
// `recipes_search` is the most expensive read in the app even after OPT-P1, and
// it is reachable signed-out, so per-keystroke calls are both slow and free to
// anyone. These tests drive the provider directly through a ProviderContainer —
// no widget needed, and `async` timers advance under `fakeAsync` via
// `FakeAsync`-backed `pump`-less control.
import 'package:app/features/discover/discover_providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingDiscoverRepository implements DiscoverRepository {
  final List<String> searches = [];

  @override
  Future<List<Recipe>> search(
    String query, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    searches.add(query);
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

ProviderContainer _container(_RecordingDiscoverRepository repo) {
  final c = ProviderContainer(
    overrides: [discoverRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('an empty query never reaches the repository', () async {
    final repo = _RecordingDiscoverRepository();
    final c = _container(repo);

    c.listen(searchResultsProvider, (_, __) {});
    await Future<void>.delayed(kSearchDebounce * 2);

    expect(repo.searches, isEmpty);
  });

  test('one settled query issues exactly one search', () async {
    final repo = _RecordingDiscoverRepository();
    final c = _container(repo);

    c.read(searchQueryProvider.notifier).state = 'chicken';
    c.listen(searchResultsProvider, (_, __) {});
    await Future<void>.delayed(kSearchDebounce * 2);

    expect(repo.searches, ['chicken']);
  });

  test('typing does not search until the pause (the P8 fix)', () async {
    final repo = _RecordingDiscoverRepository();
    final c = _container(repo);
    c.listen(searchResultsProvider, (_, __) {});

    // Seven keystrokes in quick succession, each well inside the debounce.
    for (final q in ['c', 'ch', 'chi', 'chic', 'chick', 'chicke', 'chicken']) {
      c.read(searchQueryProvider.notifier).state = q;
      c.listen(searchResultsProvider, (_, __) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // Nothing should have gone out yet.
    expect(
      repo.searches,
      isEmpty,
      reason: 'a search fired mid-typing — the debounce is not holding',
    );

    await Future<void>.delayed(kSearchDebounce * 2);
    expect(
      repo.searches,
      ['chicken'],
      reason: 'only the settled query should reach the server',
    );
  });

  test('a superseded query is dropped, not sent late', () async {
    final repo = _RecordingDiscoverRepository();
    final c = _container(repo);

    c.read(searchQueryProvider.notifier).state = 'lamb';
    c.listen(searchResultsProvider, (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));

    c.read(searchQueryProvider.notifier).state = 'lamb tagine';
    c.listen(searchResultsProvider, (_, __) {});
    await Future<void>.delayed(kSearchDebounce * 2);

    expect(repo.searches, ['lamb tagine']);
  });
}
