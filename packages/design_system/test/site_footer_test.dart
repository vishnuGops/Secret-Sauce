// Phase 35a. The legal bar lives in `Scaffold.bottomNavigationBar` on web, so
// it is a fixed-height page region in the sense Gotcha 22 means: whatever it
// takes comes out of the viewport, and it has to stay sane at 2.0x text scale
// at the narrow end of the wide breakpoint.
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {required double width, double scale = 1.0}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 800),
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(body: SizedBox(width: width, child: child)),
    ),
  );
}

List<SiteFooterLink> _links({String? current, VoidCallback? onTap}) => [
  for (final label in ['Privacy', 'Terms', 'Rights'])
    SiteFooterLink(
      label: label,
      isCurrent: label == current,
      onTap: onTap ?? () {},
    ),
];

void main() {
  group('SiteFooter', () {
    testWidgets('renders every link', (tester) async {
      await tester.pumpWidget(_wrap(SiteFooter(links: _links()), width: 1000));

      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Terms'), findsOneWidget);
      expect(find.text('Rights'), findsOneWidget);
    });

    testWidgets('links are set in the brown footer ink (36c)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SiteFooter(links: _links(current: 'Terms'), dense: true),
          width: 1000,
        ),
      );
      final scheme = AppTheme.light().colorScheme;

      expect(
        tester.widget<Text>(find.text('Privacy')).style?.color,
        scheme.secondary,
      );
      // The current page is text, not a link, so it stays muted.
      expect(
        tester.widget<Text>(find.text('Terms')).style?.color,
        scheme.onSurfaceVariant,
      );
    });

    testWidgets('a link calls back; the current page does not', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          SiteFooter(links: _links(current: 'Terms', onTap: () => taps++)),
          width: 1000,
        ),
      );

      await tester.tap(find.text('Privacy'));
      expect(taps, 1);

      // The page you are already on is plain text, so there is nothing to tap.
      // Asserted as "no InkWell under it" rather than as a missing tap, because
      // a dead InkWell looks identical until someone presses it.
      expect(
        find.ancestor(of: find.text('Terms'), matching: find.byType(InkWell)),
        findsNothing,
      );
    });

    testWidgets('drops the copyright above the scale cap', (tester) async {
      await tester.pumpWidget(
        _wrap(SiteFooter(links: _links(), copyright: '© Someone'), width: 1000),
      );
      expect(find.text('© Someone'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(
          SiteFooter(links: _links(), copyright: '© Someone'),
          width: 1000,
          scale: kSiteFooterCopyrightMaxScale,
        ),
      );
      // The links are the part a reader might need; the copyright is not.
      expect(find.text('© Someone'), findsNothing);
      expect(find.text('Privacy'), findsOneWidget);
    });

    testWidgets('survives its envelope', (tester) async {
      // The same two-axis matrix the card and the nav pill are held to
      // (Gotchas 13/18): one width or one scale proves nothing.
      for (final width in <double>[360, 600, 1000, 1440]) {
        for (final scale in <double>[1.0, 1.5, 2.0]) {
          await tester.pumpWidget(
            _wrap(
              SiteFooter(
                links: _links(),
                copyright: '© A Fairly Long Operating Entity Name Ltd',
                dense: true,
              ),
              width: width,
              scale: scale,
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
}
