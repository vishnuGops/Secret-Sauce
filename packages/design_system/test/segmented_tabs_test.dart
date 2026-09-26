// SegmentedTabs — the one pill segmented control (UX-032), carrying the 48px
// targets (UX-048), the selected semantics (UX-014) and the one-weight labels
// (UX-049) of the four controls it replaced.
import 'dart:ui' show Tristate;

import 'package:design_system/design_system.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Win { allTime, month, week }

String _short(_Win w) => switch (w) {
  _Win.allTime => 'All time',
  _Win.month => 'Month',
  _Win.week => 'Week',
};

// The longest a real caller could plausibly pass, and then some.
String _long(_Win w) => switch (w) {
  _Win.allTime => 'All time, every public recipe',
  _Win.month => 'The last thirty days',
  _Win.week => 'This week only',
};

void _size(WidgetTester tester, double width, [double height = 800]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(
  WidgetTester tester, {
  _Win selected = _Win.allTime,
  ValueChanged<_Win>? onSelected,
  String Function(_Win) labelOf = _short,
  SegmentedTabsTone tone = SegmentedTabsTone.surface,
  bool expand = false,
  bool Function(_Win)? enabledOf,
  double width = 800,
  double scale = 1.0,
  bool reduceMotion = false,
  ThemeData? theme,
}) async {
  _size(tester, width);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Builder(
        builder:
            (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: reduceMotion,
              ),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  // A Column, as on every real page: the pill is handed a
                  // bounded width and an unbounded height.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SegmentedTabs<_Win>(
                        values: _Win.values,
                        selected: selected,
                        onSelected: onSelected ?? (_) {},
                        labelOf: labelOf,
                        tone: tone,
                        expand: expand,
                        enabledOf: enabledOf,
                        semanticLabel: 'Window',
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ),
    ),
  );
}

SemanticsData _sem(WidgetTester tester, String label) =>
    tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();

AnimatedContainer _chip(WidgetTester tester, String label) =>
    tester.widget<AnimatedContainer>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(AnimatedContainer),
      ),
    );

Color? _fill(WidgetTester tester, String label) =>
    (_chip(tester, label).decoration as BoxDecoration?)?.color;

void main() {
  group('selection', () {
    for (final expand in [false, true]) {
      testWidgets('a tap reports its value (expand: $expand)', (tester) async {
        final taps = <_Win>[];
        await _pump(tester, onSelected: taps.add, expand: expand);

        await tester.tap(find.text('Week'));
        await tester.tap(find.text('Month'));
        expect(taps, [_Win.week, _Win.month]);
      });
    }

    // Phase 37: the consolidated control carries the Discover sort and the
    // rail switch, both 14px before; it must not shrink them to 11px.
    testWidgets('labels read at labelLarge, not labelSmall', (tester) async {
      await _pump(tester, onSelected: (_) {});
      final label = tester.widget<Text>(find.text('Week'));
      final context = tester.element(find.text('Week'));
      expect(
        label.style?.fontSize ?? DefaultTextStyle.of(context).style.fontSize,
        Theme.of(context).textTheme.labelLarge!.fontSize,
      );
    });

    testWidgets('a disabled segment reports nothing', (tester) async {
      final taps = <_Win>[];
      await _pump(
        tester,
        onSelected: taps.add,
        enabledOf: (w) => w != _Win.week,
      );
      await tester.tap(find.text('Week'), warnIfMissed: false);
      expect(taps, isEmpty);
    });

    testWidgets('exactly one segment is announced selected, as a button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, selected: _Win.month);

      final selected = [
        for (final w in _Win.values)
          if (_sem(tester, _short(w)).flagsCollection.isSelected ==
              Tristate.isTrue)
            w,
      ];
      expect(selected, [_Win.month]);
      for (final w in _Win.values) {
        final data = _sem(tester, _short(w));
        expect(data.flagsCollection.isButton, isTrue, reason: _short(w));
        // Announced once: the painted label is not a second node.
        expect(find.bySemanticsLabel(_short(w)), findsOneWidget);
      }
      // The group carries its own name.
      expect(find.bySemanticsLabel('Window'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the selected segment is the one filled', (tester) async {
      await _pump(tester, selected: _Win.week);
      final scheme = AppTheme.light().colorScheme;
      expect(_fill(tester, 'Week'), scheme.surfaceContainerLowest);
      expect(_fill(tester, 'All time'), isNull);
      expect(_fill(tester, 'Month'), isNull);
    });
  });

  group('targets (UX-048)', () {
    for (final expand in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('every segment is 48 x 48 (expand: $expand, ${scale}x)', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          await _pump(tester, expand: expand, scale: scale);
          for (final w in _Win.values) {
            final rect = tester.getSemantics(find.bySemanticsLabel(_short(w)));
            expect(
              rect.rect.height,
              greaterThanOrEqualTo(kMinInteractiveDimension),
              reason: _short(w),
            );
            expect(
              rect.rect.width,
              greaterThanOrEqualTo(kMinInteractiveDimension),
              reason: _short(w),
            );
          }
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          handle.dispose();
        });
      }
    }

    testWidgets('a tap in the margin above the paint still selects', (
      tester,
    ) async {
      final taps = <_Win>[];
      await _pump(tester, onSelected: taps.add);

      final pill = tester.getRect(find.byType(SegmentedTabs<_Win>));
      final chip = tester.getRect(
        find.ancestor(
          of: find.text('Week'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      // The paint is still the slim pill — the target grew, the look did not.
      expect(chip.height, lessThan(pill.height * 0.75));
      expect(pill.height, greaterThanOrEqualTo(kMinInteractiveDimension));

      await tester.tapAt(Offset(chip.center.dx, pill.top + 2));
      await tester.tapAt(Offset(chip.center.dx, pill.bottom - 2));
      expect(taps, [_Win.week, _Win.week]);
    });
  });

  group('keyboard', () {
    testWidgets('Tab shows a focus ring, Enter and Space select', (
      tester,
    ) async {
      final taps = <_Win>[];
      await _pump(tester, onSelected: taps.add);
      expect(find.byKey(SegmentedTabs.focusRingKey), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final ring = find.byKey(SegmentedTabs.focusRingKey);
      expect(ring, findsOneWidget, reason: 'keyboard focus is invisible');
      // On the first segment's paint, not the whole 48px column.
      final chip = tester.getRect(
        find.ancestor(
          of: find.text('All time'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(tester.getRect(ring), chip);
      final border =
          (tester.widget<DecoratedBox>(ring).decoration as BoxDecoration)
                  .border!
              as Border;
      expect(border.top.color, AppTheme.light().colorScheme.primary);
      expect(border.top.width, SegmentedTabs.focusRingWidth);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(taps, [_Win.allTime, _Win.month]);
    });

    testWidgets('on the hero, the ring still reads over the selected fill', (
      tester,
    ) async {
      // The hero's selected fill is `onHero`, so an `onHero` ring on it would
      // be white on white.
      await _pump(tester, tone: SegmentedTabsTone.onHero);
      final palette = AppTheme.light().extension<AppPalette>()!;
      Color ringColor() =>
          ((tester
                              .widget<DecoratedBox>(
                                find.byKey(SegmentedTabs.focusRingKey),
                              )
                              .decoration
                          as BoxDecoration)
                      .border!
                  as Border)
              .top
              .color;

      await tester.sendKeyEvent(LogicalKeyboardKey.tab); // All time, selected
      await tester.pump();
      expect(ringColor(), palette.heroSelectedInk);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Month, unselected
      await tester.pump();
      expect(ringColor(), palette.onHero);
    });

    testWidgets('a focus that did not come from the keyboard shows no ring', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
        () =>
            FocusManager.instance.highlightStrategy =
                FocusHighlightStrategy.automatic,
      );
      await _pump(tester);
      Focus.of(tester.element(find.text('Month'))).requestFocus();
      await tester.pump();
      expect(find.byKey(SegmentedTabs.focusRingKey), findsNothing);
    });

    testWidgets('hover washes an unselected segment', (tester) async {
      await _pump(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Month')));
      await tester.pumpAndSettle();
      expect(_fill(tester, 'Month'), isNotNull);
      expect(_fill(tester, 'Week'), isNull);
    });
  });

  group('tones', () {
    testWidgets('surface: the scheme track, lifted selection', (tester) async {
      await _pump(tester, selected: _Win.month);
      final scheme = AppTheme.light().colorScheme;
      expect(_track(tester), scheme.surfaceContainerHigh);
      expect(_fill(tester, 'Month'), scheme.surfaceContainerLowest);
      expect(_ink(tester, 'Month'), scheme.onSurface);
      expect(_ink(tester, 'Week'), scheme.onSurfaceVariant);
    });

    for (final (name, theme) in [
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets('onHero keeps the hero colours ($name theme)', (
        tester,
      ) async {
        await _pump(
          tester,
          selected: _Win.month,
          tone: SegmentedTabsTone.onHero,
          theme: theme,
        );
        final palette = theme.extension<AppPalette>()!;
        expect(_track(tester), palette.heroFill);
        expect(_fill(tester, 'Month'), palette.onHero);
        expect(_ink(tester, 'Month'), palette.heroSelectedInk);
        expect(_ink(tester, 'Week'), palette.onHeroMuted);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('labels (UX-049)', () {
    testWidgets('one weight in both states, and selecting moves nobody', (
      tester,
    ) async {
      await _pump(tester);
      final weights = {
        for (final w in _Win.values)
          tester.widget<Text>(find.text(_short(w))).style?.fontWeight,
      };
      expect(weights, hasLength(1));
      final before = [
        for (final w in _Win.values) tester.getRect(find.text(_short(w))),
      ];

      await _pump(tester, selected: _Win.week);
      final after = [
        for (final w in _Win.values) tester.getRect(find.text(_short(w))),
      ];
      expect(after, before);
    });
  });

  group('motion', () {
    testWidgets('reduced motion collapses the fill animation', (tester) async {
      await _pump(tester, reduceMotion: true);
      expect(_chip(tester, 'Month').duration, Duration.zero);
      await _pump(tester);
      expect(_chip(tester, 'Month').duration, AppMotion.fast);
    });
  });

  group('envelope', () {
    for (final expand in [false, true]) {
      for (final width in <double>[288, 390, 600, 1000, 1440]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            'long labels fit at ${width}px x $scale (expand: $expand)',
            (tester) async {
              await _pump(
                tester,
                labelOf: _long,
                expand: expand,
                width: width,
                scale: scale,
              );
              expect(tester.takeException(), isNull);
              // Inside the box it was given, never past it.
              final pill = tester.getRect(find.byType(SegmentedTabs<_Win>));
              expect(pill.right, lessThanOrEqualTo(width - AppSpacing.md));
            },
          );
        }
      }
    }

    testWidgets('unbounded (a non-flex Row child) it sizes to its labels', (
      tester,
    ) async {
      _size(tester, 1440);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Row(
              children: [
                const Expanded(child: SizedBox()),
                SegmentedTabs<_Win>(
                  values: _Win.values,
                  selected: _Win.allTime,
                  onSelected: (_) {},
                  labelOf: _short,
                  tone: SegmentedTabsTone.onHero,
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(SegmentedTabs<_Win>),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      expect(
        tester.getSize(find.byType(SegmentedTabs<_Win>)).width,
        lessThan(400),
      );
    });
  });
}

Color? _track(WidgetTester tester) {
  final boxes = tester.widgetList<DecoratedBox>(
    find.descendant(
      of: find.byType(SegmentedTabs<_Win>),
      matching: find.byType(DecoratedBox),
    ),
  );
  // The first DecoratedBox in the control is the track band.
  return (boxes.first.decoration as BoxDecoration).color;
}

Color? _ink(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color;
