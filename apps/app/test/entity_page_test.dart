// Phase 35b. `/entity/:id` — one publisher's page.
//
// Two properties are worth more than the layout and neither is obvious from
// reading the screen:
//
//   * **The page must stay out of `needsAuth`.** `entities`, `entity_members`
//     and `entity_signature_dishes` are all world-readable on purpose — a
//     directory that needs an account is not a directory — and the routes
//     nearest it in the router are guarded, so adding it to that list is an
//     easy mistake nothing else would catch.
//   * **An empty roster and an empty signature list are states, not errors.**
//     Only a missing entity is a 404, exactly as `/chef/:id` treats a missing
//     profile against a null standing.
import 'dart:async';

import 'package:app/features/entities/entity_page.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _entity = Entity(
  id: 'e1',
  slug: 'northern-bakehouse',
  name: 'Northern Bakehouse',
  kind: EntityKind.brand,
  country: 'GB',
  homepage: 'https://example.test/northern-bakehouse',
  description: 'A simulated brand used to exercise the entity directory.',
);

Profile _profile(String id, String name) => Profile(id: id, displayName: name);

Recipe _recipe(String id, String title) => Recipe(
  id: id,
  ownerId: 'p1',
  title: title,
  servings: 4,
  visibility: RecipeVisibility.public,
);

class _FakeAuth implements AuthRepository {
  @override
  String? get currentUserId => null;

  @override
  Future<String?> currentProfileId() async => null;

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _FakeEntities implements EntityRepository {
  _FakeEntities({
    this.entity = _entity,
    List<EntityMember> members = const [],
    this.dishes = const [],
    this.fail = false,
  }) : _members = members;

  final Entity? entity;

  /// Private because the interface's `members` is a METHOD of the same name —
  /// a field would collide with it.
  final List<EntityMember> _members;
  final List<Recipe> dishes;
  final bool fail;

  @override
  Future<Entity?> getById(String id) async {
    if (fail) throw Exception('boom');
    return entity;
  }

  @override
  Future<List<EntityMember>> members(String entityId) async => _members;

  @override
  Future<List<Recipe>> signatureDishes(
    String entityId, {
    int limit = 12,
  }) async => dishes;

  @override
  Future<List<Entity>> forProfile(String profileId) async => const [];

  @override
  Future<List<Entity>> list({int limit = 24, int offset = 0}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

void _size(WidgetTester tester, double width, [double height = 1600]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required _FakeEntities entities,
  double textScale = 1.0,

  /// False leaves a pending read pending: a spinner never settles.
  bool settle = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuth()),
      entityRepositoryProvider.overrideWithValue(entities),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(appRouterProvider);
  router.go(Routes.entity('e1'));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return router;
}

SemanticsData _a11y(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData();

/// [text] inside the page body — the app bar names the publisher too since
/// UX-042, so an unscoped finder would find it twice.
Finder _inBody(String text) => find.descendant(
  of: find.byType(CustomScrollView),
  matching: find.text(text),
);

/// The app bar's title.
String _barTitle(WidgetTester tester) =>
    tester
        .widget<Text>(
          find.descendant(of: find.byType(AppBar), matching: find.byType(Text)),
        )
        .data!;

/// The titles every `Title` in the tree carries (UX-051).
Iterable<String> _titles(WidgetTester tester) =>
    tester.widgetList<Title>(find.byType(Title)).map((t) => t.title);

void main() {
  testWidgets('opens signed out — no redirect to /auth', (tester) async {
    _size(tester, 1000);
    final router = await _pump(tester, entities: _FakeEntities());

    expect(router.state.matchedLocation, Routes.entity('e1'));
    expect(find.byType(EntityPage), findsOneWidget);
  });

  testWidgets('renders the publisher and its kind', (tester) async {
    _size(tester, 1000);
    await _pump(tester, entities: _FakeEntities());

    expect(_inBody('Northern Bakehouse'), findsOneWidget);
    expect(find.text('Brand'), findsOneWidget);
    expect(find.text('GB'), findsOneWidget);
  });

  testWidgets('says so when nobody here manages it', (tester) async {
    // `created_by` is null on every imported entity, which is the corpus case.
    _size(tester, 1000);
    await _pump(tester, entities: _FakeEntities());

    expect(
      find.textContaining('Nobody on Secret Sauce manages this page yet'),
      findsOneWidget,
    );
  });

  testWidgets('an empty signature list is a state, not an error', (
    tester,
  ) async {
    _size(tester, 1000);
    await _pump(tester, entities: _FakeEntities());

    expect(find.text('No signature dishes yet'), findsOneWidget);
    expect(find.byType(ErrorView), findsNothing);
  });

  testWidgets('a missing entity is the one genuine 404', (tester) async {
    _size(tester, 1000);
    await _pump(tester, entities: _FakeEntities(entity: null));

    expect(find.byType(ErrorView), findsOneWidget);
  });

  testWidgets('a failed read offers a retry', (tester) async {
    _size(tester, 1000);
    await _pump(tester, entities: _FakeEntities(fail: true));

    expect(find.byType(ErrorView), findsOneWidget);
  });

  group('the roster', () {
    final members = [
      EntityMember(
        entityId: 'e1',
        profileId: 'p1',
        role: EntityRole.owner,
        title: 'Head Chef',
        profile: _profile('p1', 'Marta Kovac'),
      ),
      EntityMember(
        entityId: 'e1',
        profileId: 'p2',
        profile: _profile('p2', 'Ines Duarte'),
      ),
    ];

    testWidgets('lists members with their title', (tester) async {
      _size(tester, 1000);
      await _pump(tester, entities: _FakeEntities(members: members));

      expect(find.text('Marta Kovac'), findsOneWidget);
      // The free-text title is the one role line that always adds something.
      expect(find.text('Head Chef'), findsOneWidget);
      expect(find.text('Ines Duarte'), findsOneWidget);
    });

    // UX-042: the page said "Chef" three times — the kind chip, the roster
    // heading, and the role under every name — meaning three things.
    testWidgets('says "Chef" nowhere as a bare word', (tester) async {
      _size(tester, 1000);
      await _pump(
        tester,
        entities: _FakeEntities(
          entity: const Entity(
            id: 'e1',
            slug: 'marta-kovac',
            name: 'Marta Kovac Cooks',
            kind: EntityKind.chefSite,
          ),
          members: [
            EntityMember(
              entityId: 'e1',
              profileId: 'p1',
              role: EntityRole.owner,
              profile: _profile('p1', 'Marta Kovac'),
            ),
            EntityMember(
              entityId: 'e1',
              profileId: 'p2',
              profile: _profile('p2', 'Ines Duarte'),
            ),
          ],
        ),
      );

      expect(find.text('Chef'), findsNothing);
      expect(find.text('Chefs'), findsNothing);
      // The chip names the kind of publisher…
      expect(find.text("Chef's own site"), findsOneWidget);
      // …the heading names whose roster it is…
      expect(find.text('Cooks at Marta Kovac Cooks'), findsOneWidget);
      // …and a role line appears only when it adds something: the owner
      // manages the page; a plain member's line would repeat the heading.
      expect(find.text('Manages this page'), findsOneWidget);
      final ines = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Ines Duarte'),
          matching: find.byType(ListTile),
        ),
      );
      expect(ines.subtitle, isNull);
    });

    testWidgets('a member row opens that chef page', (tester) async {
      _size(tester, 1000);
      final router = await _pump(
        tester,
        entities: _FakeEntities(members: members),
      );

      await tester.tap(find.text('Marta Kovac'));
      await tester.pumpAndSettle();

      // `matchedLocation`, not `currentConfiguration.uri`: this is an
      // imperative push, which layers a route without moving the base.
      expect(router.state.matchedLocation, Routes.chef('p1'));
    });
  });

  testWidgets('signature dishes render as cards', (tester) async {
    _size(tester, 1000);
    await _pump(
      tester,
      entities: _FakeEntities(dishes: [_recipe('r1', 'Seeded Rye Loaf')]),
    );

    expect(find.text('Seeded Rye Loaf'), findsOneWidget);
    expect(find.text('No signature dishes yet'), findsNothing);
  });

  // UX-048: every control on the page is at least 48 × 48 (WCAG 2.5.8 via
  // Flutter's Android guideline, the stricter of the two it ships) — the
  // homepage link, the roster rows and a signature dish.
  for (final width in [390.0, 1440.0]) {
    testWidgets('every tap target meets the 48dp guideline at ${width}px', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      _size(tester, width, 2400);
      await _pump(
        tester,
        entities: _FakeEntities(
          members: [
            EntityMember(
              entityId: 'e1',
              profileId: 'p1',
              role: EntityRole.owner,
              title: 'Head Chef',
              profile: _profile('p1', 'Marta Kovac'),
            ),
            EntityMember(
              entityId: 'e1',
              profileId: 'p2',
              profile: _profile('p2', 'Ines Duarte'),
            ),
          ],
          dishes: [_recipe('r1', 'Seeded Rye Loaf')],
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  }

  group('envelope', () {
    for (final width in <double>[390, 600, 1000, 1440]) {
      for (final scale in <double>[1.0, 2.0]) {
        testWidgets('fits at ${width}px @ ${scale}x', (tester) async {
          _size(tester, width, 2400);
          await _pump(
            tester,
            textScale: scale,
            entities: _FakeEntities(
              members: [
                EntityMember(
                  entityId: 'e1',
                  profileId: 'p1',
                  role: EntityRole.owner,
                  title: 'Executive Pastry Chef and Head of Development',
                  profile: _profile(
                    'p1',
                    'Bartholomew Featherstonehaugh-Wentworth',
                  ),
                ),
              ],
              dishes: [
                _recipe('r1', 'Slow-Braised Short Rib with Salsa Verde'),
              ],
            ),
          );

          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow at ${width}px @ ${scale}x',
          );
        });
      }
    }
  });

  // Phase 37 wave C (UX-014 / UX-051).
  group('accessibility', () {
    testWidgets('the name, the roster and the dishes are headings', (
      tester,
    ) async {
      _size(tester, 1000);
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        entities: _FakeEntities(
          members: [
            EntityMember(
              entityId: 'e1',
              profileId: 'p1',
              profile: _profile('p1', 'Marta Kovac'),
            ),
            EntityMember(
              entityId: 'e1',
              profileId: 'p2',
              profile: _profile('p2', 'Ines Duarte'),
            ),
          ],
        ),
      );

      for (final text in [
        'Northern Bakehouse',
        'Cooks at Northern Bakehouse',
        'Signature dishes',
      ]) {
        expect(
          _a11y(tester, _inBody(text)).flagsCollection.isHeader,
          isTrue,
          reason: text,
        );
      }
      expect(
        _a11y(tester, find.text('Marta Kovac')).flagsCollection.isHeader,
        isFalse,
      );
      handle.dispose();
    });

    testWidgets("the publisher's name titles the tab", (tester) async {
      _size(tester, 1000);
      await _pump(tester, entities: _FakeEntities());
      expect(_titles(tester), contains('Northern Bakehouse · Secret Sauce'));
    });
  });

  // UX-042: the app bar said "Publisher" over every publisher.
  group('the app bar', () {
    testWidgets("names the publisher once loaded, and the tab agrees", (
      tester,
    ) async {
      _size(tester, 1000);
      await _pump(tester, entities: _FakeEntities());

      expect(_barTitle(tester), 'Northern Bakehouse');
      expect(_titles(tester), isNot(contains('Publisher · Secret Sauce')));
    });

    testWidgets('keeps the generic word while loading', (tester) async {
      _size(tester, 1000);
      final pending = Completer<Entity?>();
      await _pump(
        tester,
        entities: _SlowEntities(pending.future),
        settle: false,
      );

      expect(find.byType(LoadingView), findsOneWidget);
      expect(_barTitle(tester), 'Publisher');
      pending.complete(_entity);
      await tester.pumpAndSettle();
      expect(_barTitle(tester), 'Northern Bakehouse');
    });

    testWidgets('keeps the generic word on an error', (tester) async {
      _size(tester, 1000);
      await _pump(tester, entities: _FakeEntities(fail: true));

      expect(find.byType(ErrorView), findsOneWidget);
      expect(_barTitle(tester), 'Publisher');
    });
  });
}

/// An entity read that answers when the test says so — the loading state.
class _SlowEntities extends _FakeEntities {
  _SlowEntities(this._entity);

  final Future<Entity?> _entity;

  @override
  Future<Entity?> getById(String id) => _entity;
}
