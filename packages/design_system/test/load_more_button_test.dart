import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// UX-032: the one `Load more` control, shared by every paged recipe grid and
/// the chefs leaderboard.
Widget _host(Widget button, {double width = 390, double textScale = 1.0}) =>
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Center(
            child: SizedBox(width: width, child: Center(child: button)),
          ),
        ),
      ),
    );

Future<void> _noop() async {}

void main() {
  for (final dense in [false, true]) {
    final kind = dense ? 'dense' : 'outlined';

    group(kind, () {
      testWidgets('a tap fetches the next page', (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          _host(
            LoadMoreButton(
              loading: false,
              dense: dense,
              onPressed: () async => calls++,
            ),
          ),
        );
        await tester.tap(find.byType(LoadMoreButton));
        await tester.pump();
        expect(calls, 1);
      });

      testWidgets('loading disables it and shows a spinner', (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          _host(
            LoadMoreButton(
              loading: true,
              dense: dense,
              onPressed: () async => calls++,
            ),
          ),
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final button = tester.widget<ButtonStyleButton>(
          find.byWidgetPredicate((w) => w is ButtonStyleButton),
        );
        expect(button.onPressed, isNull);

        await tester.tap(find.byType(LoadMoreButton), warnIfMissed: false);
        await tester.pump();
        expect(calls, 0);
      });

      testWidgets('is the same size loading and idle', (tester) async {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            _host(
              LoadMoreButton(loading: false, dense: dense, onPressed: _noop),
              textScale: scale,
            ),
          );
          final idle = tester.getSize(find.byType(LoadMoreButton));
          expect(find.byType(CircularProgressIndicator), findsNothing);

          await tester.pumpWidget(
            _host(
              LoadMoreButton(loading: true, dense: dense, onPressed: _noop),
              textScale: scale,
            ),
          );
          expect(
            tester.getSize(find.byType(LoadMoreButton)),
            idle,
            reason: 'the button changed size at ${scale}x',
          );
        }
      });

      testWidgets('says "Load more" in both states', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(LoadMoreButton(loading: false, dense: dense, onPressed: _noop)),
        );
        expect(find.bySemanticsLabel('Load more'), findsOneWidget);

        await tester.pumpWidget(
          _host(LoadMoreButton(loading: true, dense: dense, onPressed: _noop)),
        );
        final data =
            tester
                .getSemantics(find.bySemanticsLabel('Load more'))
                .getSemanticsData();
        expect(data.value, 'Loading more');
        handle.dispose();
      });

      // 288: a recipe grid's narrowest column, where the paged footer sits.
      for (final width in [288.0, 390.0, 600.0, 1000.0, 1440.0]) {
        for (final scale in [1.0, 2.0]) {
          for (final loading in [false, true]) {
            testWidgets('fits at ${width.toInt()} × ${scale}x'
                '${loading ? ', loading' : ''}', (tester) async {
              await tester.pumpWidget(
                _host(
                  LoadMoreButton(
                    loading: loading,
                    dense: dense,
                    onPressed: _noop,
                  ),
                  width: width,
                  textScale: scale,
                ),
              );
              expect(tester.takeException(), isNull);
            });
          }
        }
      }
    });
  }

  testWidgets('a failed page is a friendly snackbar, not a crash', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LoadMoreButton(
          loading: false,
          onPressed: () async => throw Exception('socket closed'),
        ),
      ),
    );
    await tester.tap(find.byType(LoadMoreButton));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  // The dense form sits as a non-flex child of the chefs panel's footer row,
  // where it is laid out with an unbounded width.
  testWidgets('dense survives an unbounded row at 2.0x', (tester) async {
    await tester.pumpWidget(
      _host(
        const Row(
          children: [
            Expanded(child: Text('Ties share a rank.')),
            LoadMoreButton(loading: true, dense: true, onPressed: _noop),
          ],
        ),
        textScale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
