// The two date helpers OPT-A7 pulled out of two widgets. They are pure and one
// of them (`isoDate`) is what a version history is read by, so a padding slip
// would be invisible in review and obvious on screen.
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('monthYear is the abbreviated month and the year', () {
    expect(monthYear(DateTime(2025, 3, 14)), 'Mar 2025');
    expect(monthYear(DateTime(2026, 12, 1)), 'Dec 2026');
    // January is index 0 in the table — the classic off-by-one here.
    expect(monthYear(DateTime(2026, 1, 31)), 'Jan 2026');
  });

  test('isoDate zero-pads both fields', () {
    expect(isoDate(DateTime(2026, 8, 21)), '2026-08-21');
    expect(isoDate(DateTime(2026, 12, 9)), '2026-12-09');
    expect(isoDate(DateTime(2026, 1, 1)), '2026-01-01');
  });

  test('formatMinutes splits hours out and dashes the empty case', () {
    expect(formatMinutes(40), '40 min');
    expect(formatMinutes(70), '1 h 10 m');
    expect(formatMinutes(120), '2 h');
    expect(formatMinutes(60), '1 h');
    expect(formatMinutes(0), '—');
    expect(formatMinutes(-5), '—');
  });
}
