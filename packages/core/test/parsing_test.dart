// UX-035 / UX-052: the editor's quantity field rejected `1/2`, and its timer
// field read `1h` as nothing and saved a step with no timer. These are the
// parsers behind both, and the round trip that keeps them honest: whatever
// `formatting.dart` prints, these read back.
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseQuantity', () {
    test('decimals, including a decimal comma', () {
      expect(parseQuantity('2'), 2);
      expect(parseQuantity('1.5'), 1.5);
      expect(parseQuantity('.5'), 0.5);
      expect(parseQuantity('1,5'), 1.5);
      expect(parseQuantity('  3 '), 3);
    });

    test('typed fractions', () {
      expect(parseQuantity('1/2'), 0.5);
      expect(parseQuantity('1 1/2'), 1.5);
      expect(parseQuantity('1-1/2'), 1.5);
      expect(parseQuantity('2 3/4'), 2.75);
      expect(parseQuantity('1/3'), closeTo(1 / 3, 1e-9));
    });

    test('unicode fractions, precomposed and slashed', () {
      expect(parseQuantity('½'), 0.5);
      expect(parseQuantity('1½'), 1.5);
      expect(parseQuantity('1 ½'), 1.5);
      expect(parseQuantity('⅔'), closeTo(2 / 3, 1e-9));
      expect(parseQuantity('1 1⁄3'), closeTo(4 / 3, 1e-9));
    });

    test('empty and unreadable are null', () {
      expect(parseQuantity(''), isNull);
      expect(parseQuantity('   '), isNull);
      expect(parseQuantity('a pinch'), isNull);
      expect(parseQuantity('1/0'), isNull);
      expect(parseQuantity('1..2'), isNull);
      expect(parseQuantity('-1'), isNull);
    });

    // Phase 38 review: `1,000` read as `1.000` saved a kilo as a gram.
    test('a thousands comma is refused, not read as a decimal', () {
      expect(parseQuantity('1,000'), isNull);
      expect(parseQuantity('1,25'), 1.25);
    });

    // Phase 38 review: they are called from form validators, so they must
    // return null — never throw — for a pasted run of digits.
    test('overlong input is null, not an exception', () {
      final many = '9' * 25;
      expect(parseQuantity('$many/2'), isNull);
      expect(parseQuantity('1/$many'), isNull);
      expect(parseQuantity('$many ½'), isNull);
      expect(parseQuantity('9' * 400), isNull);
    });

    test('reads back everything formatQuantity prints', () {
      for (final unit in ['cup', 'tsp', 'g', null]) {
        for (final v in [0.25, 0.5, 0.75, 1 / 3, 2 / 3, 1.125, 2.5, 250.0]) {
          final printed = formatQuantity(v, unit);
          expect(
            parseQuantity(printed),
            closeTo(v, 0.01),
            reason: '"$printed" ($unit)',
          );
        }
      }
    });
  });

  group('parseDurationMinutes', () {
    test('bare minutes', () {
      expect(parseDurationMinutes('90'), 90);
      expect(parseDurationMinutes(' 5 '), 5);
    });

    test('hours and minutes, spelled every way a cook types them', () {
      expect(parseDurationMinutes('1h'), 60);
      expect(parseDurationMinutes('1h 30m'), 90);
      expect(parseDurationMinutes('1h30m'), 90);
      expect(parseDurationMinutes('1 h 30 min'), 90);
      expect(parseDurationMinutes('1.5 hours'), 90);
      expect(parseDurationMinutes('2 hours 15 minutes'), 135);
      expect(parseDurationMinutes('2 hours, 15 minutes'), 135);
      expect(parseDurationMinutes('1 hour and 5 mins'), 65);
      expect(parseDurationMinutes('45 min'), 45);
      expect(parseDurationMinutes('45m'), 45);
      expect(parseDurationMinutes('1H 30M'), 90);
      expect(parseDurationMinutes('1:30'), 90);
    });

    test('empty and unreadable are null, never a partial read', () {
      expect(parseDurationMinutes(''), isNull);
      expect(parseDurationMinutes('soon'), isNull);
      expect(parseDurationMinutes('1h 30x'), isNull);
      expect(parseDurationMinutes('about 1h'), isNull);
      expect(parseDurationMinutes('1:75'), isNull);
    });

    test('overlong or absurd durations are null, not an exception', () {
      expect(parseDurationMinutes('9' * 25), isNull);
      expect(parseDurationMinutes('${'9' * 400}h'), isNull);
      expect(parseDurationMinutes('3000000000'), isNull);
      // The ceiling: a week, and not a minute more.
      expect(parseDurationMinutes('$kMaxDurationMinutes'), kMaxDurationMinutes);
      expect(parseDurationMinutes('${kMaxDurationMinutes + 1}'), isNull);
    });

    test('reads back everything formatMinutes prints', () {
      for (final m in [5, 45, 60, 70, 120, 135, 765]) {
        expect(parseDurationMinutes(formatMinutes(m)), m);
        expect(parseDurationMinutes(formatMinutes(m, compact: true)), m);
      }
    });
  });
}
