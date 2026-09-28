// Phase 35a. The three legal documents, driven through the real router.
//
// Two properties matter more than the prose and neither is obvious from
// reading the screen:
//
//   * `/legal/*` must stay OUT of `needsAuth`. A Terms page you have to sign in
//     to read is not a Terms page, and the three routes nearest it in the
//     router (`/my`, `/profile`, `/recipe/new`) are all guarded — so adding it
//     to that list is an easy mistake that nothing else here would catch.
//   * the draft banner must appear while `LegalFacts` still holds placeholders.
//     A document missing its operating entity and its jurisdiction still reads
//     like a finished document, which is exactly how one gets published.
import 'dart:async';

import 'package:app/features/legal/legal_document.dart';
import 'package:app/features/legal/legal_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.uid);

  final String? uid;

  @override
  String? get currentUserId => uid;

  @override
  Future<String?> currentProfileId() async => uid;

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

Future<GoRouter> _pumpAt(
  WidgetTester tester,
  String location, {
  String? uid,
  Size size = const Size(1400, 2400),
}) async {
  // Tall on purpose: these documents are long, and a finder for a heading near
  // the bottom of a ListView fails on a short viewport for a reason that has
  // nothing to do with what is being tested.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(_FakeAuth(uid))],
  );
  addTearDown(container.dispose);

  final router = container.read(appRouterProvider);
  router.go(location);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Scroll to the footer at the end of the document.
///
/// `ListView(children: …)` still builds lazily, so the sibling links are not in
/// the tree at all until the reader gets there — a plain `find.text` on them
/// fails for a reason that has nothing to do with the links.
Future<void> _scrollToFooter(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text(LegalDoc.rights.shortLabel),
    600,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

SemanticsData _a11y(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData();

/// The titles every `Title` in the tree carries (UX-051).
Iterable<String> _titles(WidgetTester tester) =>
    tester.widgetList<Title>(find.byType(Title)).map((t) => t.title);

void main() {
  group('routing', () {
    testWidgets('every document opens signed OUT', (tester) async {
      for (final doc in LegalDoc.values) {
        final router = await _pumpAt(tester, Routes.legal(doc.slug));

        expect(
          router.state.matchedLocation,
          Routes.legal(doc.slug),
          reason: '${doc.slug} was redirected — is it in needsAuth?',
        );
        expect(find.byType(LegalScreen), findsOneWidget);
      }
    });

    testWidgets('an unknown slug falls back to Privacy', (tester) async {
      // Deliberately not a 404: the worst outcome of a mistyped legal URL is a
      // reader who cannot find the policy, so a wrong one lands on one.
      await _pumpAt(tester, Routes.legal('nonsense'));

      expect(find.text(LegalDoc.privacy.title), findsNWidgets(2));
    });

    testWidgets('opens signed IN too', (tester) async {
      final router = await _pumpAt(tester, Routes.legal('terms'), uid: 'u1');
      expect(router.state.matchedLocation, Routes.legal('terms'));
    });
  });

  group('content', () {
    testWidgets('each document prints its title and the update date', (
      tester,
    ) async {
      for (final doc in LegalDoc.values) {
        await _pumpAt(tester, Routes.legal(doc.slug));

        // Title twice: the AppBar and the page heading.
        expect(find.text(doc.title), findsNWidgets(2));
        expect(find.text('Last updated $kLegalLastUpdated'), findsOneWidget);
      }
    });

    // DESIGN §2.2: the Kitchen's covers are generated, and the Rights page is
    // where the site says so in words, not just in the `AI` tag.
    test("Rights discloses that the Kitchen's pictures are AI-generated", () {
      final text = kRightsBlocks
          .whereType<LegalBullets>()
          .expand((b) => b.items)
          .join(' ');
      expect(text, contains('AI-generated images, not photographs'));
    });

    testWidgets('the draft banner tracks LegalFacts', (tester) async {
      await _pumpAt(tester, Routes.legal('privacy'));

      final banner = find.textContaining('Draft — not in force');
      if (LegalFacts.isComplete) {
        expect(banner, findsNothing);
      } else {
        expect(
          banner,
          findsOneWidget,
          reason: 'placeholders are still present, so the banner must show',
        );
      }
    });

    testWidgets('Terms says publishing means forkable', (tester) async {
      // The one term specific to this product, and the reason the page exists
      // at all rather than being a generic template. If this heading is ever
      // softened or removed, the app is granting a fork right it never stated.
      await _pumpAt(tester, Routes.legal('terms'));

      expect(
        find.text('Publishing a recipe publicly means it can be forked'),
        findsOneWidget,
      );
    });

    testWidgets('Privacy names the view log and what deletion leaves', (
      tester,
    ) async {
      await _pumpAt(tester, Routes.legal('privacy'));

      expect(find.text('Deleting your account'), findsOneWidget);
      expect(
        find.textContaining('the account reference removed'),
        findsOneWidget,
      );
    });

    testWidgets('Rights states the photograph position', (tester) async {
      await _pumpAt(tester, Routes.legal('rights'));

      expect(find.textContaining('never re-host a photograph'), findsOneWidget);
    });
  });

  group('navigation between documents', () {
    testWidgets('each page links to its two siblings, not to itself', (
      tester,
    ) async {
      await _pumpAt(tester, Routes.legal('terms'));
      await _scrollToFooter(tester);

      // All three labels are present; the current one is plain text.
      for (final doc in LegalDoc.values) {
        expect(find.text(doc.shortLabel), findsOneWidget);
      }
      expect(
        find.ancestor(
          of: find.text(LegalDoc.terms.shortLabel),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });

    testWidgets('tapping a sibling navigates', (tester) async {
      final router = await _pumpAt(tester, Routes.legal('terms'));
      await _scrollToFooter(tester);

      await tester.tap(find.text(LegalDoc.rights.shortLabel));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, Routes.legal('rights'));
    });
  });

  group('envelope', () {
    testWidgets('renders without overflow across widths and scales', (
      tester,
    ) async {
      for (final width in <double>[390, 600, 1000, 1440]) {
        for (final scale in <double>[1.0, 2.0]) {
          tester.view.physicalSize = Size(width, 3000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final container = ProviderContainer(
            overrides: [
              authRepositoryProvider.overrideWithValue(_FakeAuth(null)),
            ],
          );
          addTearDown(container.dispose);
          final router = container.read(appRouterProvider);
          router.go(Routes.legal('rights'));

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 3000),
                  textScaler: TextScaler.linear(scale),
                ),
                child: MaterialApp.router(
                  theme: AppTheme.light(),
                  routerConfig: router,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: 'overflowed at ${width}px x $scale',
          );
        }
      }
    });
  });

  // UX-048: every control on the page is at least 48 × 48 (WCAG 2.5.8 via
  // Flutter's Android guideline, the stricter of the two it ships) — the back
  // arrow at the top, then the sibling links at the end of the document.
  for (final width in [390.0, 1440.0]) {
    testWidgets('every tap target meets the 48dp guideline at ${width}px', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpAt(tester, Routes.legal('privacy'), size: Size(width, 1600));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      // To the very end rather than `_scrollToFooter`, which stops as soon as
      // the links touch the viewport — and a node touching the edge is one
      // the guideline skips.
      await _scrollToFooter(tester);
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text(LegalDoc.terms.shortLabel), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  }

  // Phase 37 wave C (UX-014 / UX-047 / UX-051).
  group('accessibility', () {
    testWidgets('the title and every section heading are headings', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpAt(tester, Routes.legal('privacy'));

      final title = find.descendant(
        of: find.byType(ListView),
        matching: find.text(LegalDoc.privacy.title),
      );
      expect(_a11y(tester, title).flagsCollection.isHeader, isTrue);

      final heading =
          LegalDoc.privacy.blocks.whereType<LegalHeading>().first.text;
      expect(
        _a11y(tester, find.text(heading)).flagsCollection.isHeader,
        isTrue,
      );
      final paragraph =
          LegalDoc.privacy.blocks.whereType<LegalParagraph>().first.text;
      expect(
        _a11y(tester, find.text(paragraph)).flagsCollection.isHeader,
        isFalse,
      );
      handle.dispose();
    });

    testWidgets('the back arrow has a name', (tester) async {
      await _pumpAt(tester, Routes.legal('terms'));
      expect(find.byTooltip('Back'), findsOneWidget);
    });

    testWidgets('the document titles the tab', (tester) async {
      for (final doc in LegalDoc.values) {
        await _pumpAt(tester, Routes.legal(doc.slug));
        expect(_titles(tester), contains('${doc.title} · Secret Sauce'));
      }
    });
  });
}
