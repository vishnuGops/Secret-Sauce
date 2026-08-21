// `snapRating` is named in CLAUDE.md Gotcha 15 as untested, and it is the one
// piece of client code that has to agree with a SQL **check constraint**:
// `recipe_ratings.rating` must be between 0.5 and 5.0 in half-star steps. A
// value that slips past this function does not render wrong — it raises 23514
// from the database at the moment a user taps a star.
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snaps to the nearest half star', () {
    expect(snapRating(2.2), 2.0);
    expect(snapRating(2.3), 2.5);
    expect(snapRating(2.5), 2.5);
    expect(snapRating(4.9), 5.0);
  });

  test('exact halves are left alone', () {
    for (final v in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0]) {
      expect(snapRating(v), v, reason: '$v was moved');
    }
  });

  test('clamps to the range the check constraint allows', () {
    // Zero is the interesting one: a star widget that reports "no rating" as 0
    // must not send 0, which the constraint rejects.
    expect(snapRating(0), kMinRating);
    expect(snapRating(0.2), kMinRating);
    expect(snapRating(-3), kMinRating);
    expect(snapRating(5.4), kMaxRating);
    expect(snapRating(99), kMaxRating);
  });

  test('every input in range produces a value the database will accept', () {
    // The property, not a sample: 0..6 in hundredths, all of which a drag
    // gesture can produce.
    for (var i = 0; i <= 600; i++) {
      final snapped = snapRating(i / 100);
      expect(snapped, greaterThanOrEqualTo(kMinRating), reason: 'from ${i / 100}');
      expect(snapped, lessThanOrEqualTo(kMaxRating), reason: 'from ${i / 100}');
      // A half-star step, checked in tenths to keep it off binary fractions.
      expect((snapped * 10).round() % 5, 0, reason: '${i / 100} snapped to $snapped');
    }
  });
}
