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

  // UX-043: one duration format everywhere — `1 h 10 min`, never `1 h 10 m`.
  test('formatMinutes splits hours out and dashes the empty case', () {
    expect(formatMinutes(40), '40 min');
    expect(formatMinutes(70), '1 h 10 min');
    expect(formatMinutes(90), '1 h 30 min');
    expect(formatMinutes(765), '12 h 45 min');
    expect(formatMinutes(120), '2 h');
    expect(formatMinutes(60), '1 h');
    expect(formatMinutes(0), '—');
    expect(formatMinutes(-5), '—');
  });

  // UX-043: one format everywhere except the fixed-width card, whose time
  // label clips at 288px in the long form (Phase 37 review).
  test('formatMinutes compact drops the spaces and nothing else', () {
    expect(formatMinutes(765), '12 h 45 min');
    expect(formatMinutes(70, compact: true), '1h 10m');
    expect(formatMinutes(120, compact: true), '2h');
    expect(formatMinutes(765, compact: true), '12h 45m');
    expect(formatMinutes(40, compact: true), '40 min');
    expect(formatMinutes(0, compact: true), '—');
  });

  // One trimmer for the two places a stored `numeric` reaches a label (32d2).
  test('trimDecimal keeps the shortest honest decimal', () {
    expect(trimDecimal(2), '2');
    expect(trimDecimal(2.0), '2');
    expect(trimDecimal(1.5), '1.5');
    expect(trimDecimal(1.25), '1.25');
    expect(trimDecimal(2.50), '2.5');
    // Two places is the ceiling — a scaled third of a cup rounds rather than
    // printing 0.3333333333333333.
    expect(trimDecimal(1 / 3), '0.33');
  });

  // UX-023: cooks read ⅓ and ¾, not 0.33 and 0.75. Fractions for US volume,
  // imperial weight, bare counts and word units; metric keeps its decimal.
  group('formatQuantity', () {
    const half = '½';
    const quarter = '¼';
    const threeQuarters = '¾';
    const slash = '⁄';

    test('halves and quarters are the precomposed glyphs', () {
      expect(formatQuantity(0.5, 'cup'), half);
      expect(formatQuantity(0.25, 'tsp'), quarter);
      expect(formatQuantity(0.75, 'tbsp'), threeQuarters);
      // No space before a glyph: `1¼`, `2¾`.
      expect(formatQuantity(1.25, 'cup'), '1$quarter');
      expect(formatQuantity(2.75, 'cups'), '2$threeQuarters');
      // Eighths reduce before choosing: 4/8 is a half, 6/8 three quarters.
      expect(formatQuantity(1.5, 'Tablespoons'), '1$half');
    });

    test('thirds and odd eighths are digits around the fraction slash', () {
      expect(formatQuantity(0.33, 'cup'), '1${slash}3');
      expect(formatQuantity(1 / 3, 'cup'), '1${slash}3');
      expect(formatQuantity(0.666, 'cup'), '2${slash}3');
      expect(formatQuantity(0.375, 'tsp'), '3${slash}8');
      // A space after a whole part, or `1 1⁄8` reads as eleven-eighths.
      expect(formatQuantity(1.125, 'tsp'), '1 1${slash}8');
      expect(formatQuantity(2.333, 'oz'), '2 1${slash}3');
      expect(formatQuantity(1.875, 'lb'), '1 7${slash}8');
    });

    test('bare counts and word units read as fractions', () {
      expect(formatQuantity(1.5, null), '1$half');
      expect(formatQuantity(0.5, ''), half);
      expect(formatQuantity(3, 'cloves'), '3');
      expect(formatQuantity(0.5, 'stick'), half);
      expect(formatQuantity(1.5, 'pinch'), '1$half');
    });

    test('metric units keep the shortest decimal', () {
      expect(formatQuantity(250, 'g'), '250');
      expect(formatQuantity(1.5, 'L'), '1.5');
      expect(formatQuantity(1.5, 'l'), '1.5');
      expect(formatQuantity(0.5, 'kg'), '0.5');
      expect(formatQuantity(0.25, 'ml'), '0.25');
      expect(formatQuantity(2.5, 'Grams'), '2.5');
      expect(formatQuantity(0.75, 'dl'), '0.75');
    });

    test('a value near no eighth or third keeps its decimal', () {
      // 0.4 is 0.025 from 3/8 — just outside the snap.
      expect(formatQuantity(2.4, 'cup'), '2.4');
      expect(formatQuantity(0.1, 'tsp'), '0.1');
    });

    test('whole numbers, zero and float residue', () {
      expect(formatQuantity(0, 'cup'), '0');
      expect(formatQuantity(2, 'cup'), '2');
      expect(formatQuantity(2.001, 'cup'), '2');
      expect(formatQuantity(1.999, 'tsp'), '2');
      expect(formatQuantity(0.99, null), '1');
      // Too small to snap to anything but zero: keep the honest decimal
      // rather than printing a quantity of nothing.
      expect(formatQuantity(0.01, 'tsp'), '0.01');
      // Phase 37 review: two decimals rounded a scaled pinch to `0 tsp`.
      expect(formatQuantity(0.004, 'tsp'), '0.004');
      expect(formatQuantity(0.004, 'g'), '0.004');
    });
  });

  test('formatNutritionValue is that trimmer, under its own name', () {
    expect(formatNutritionValue(10), trimDecimal(10));
    expect(formatNutritionValue(0.25), trimDecimal(0.25));
  });

  test('sentenceCase capitalises without touching the rest', () {
    expect(sentenceCase('plain yoghurt'), 'Plain yoghurt');
    // Not title case — "Gruyère, shredded" must not become "Gruyère, Shredded".
    expect(sentenceCase('gruyère, shredded'), 'Gruyère, shredded');
    expect(sentenceCase(''), '');
    expect(sentenceCase('A'), 'A');
  });

  // The quantity-gutter chain (B066). Both surfaces that draw a quantity column
  // — the reading page's ingredients rail and cook mode's step rail — read it
  // from here, because two copies of it is how the two sides of the 1000px
  // branch came to disagree in the first place.
  group('ingredientQuantityLabel', () {
    const base = Ingredient(id: 'i', groupId: 'g', name: 'yoghurt');

    test('quantity and unit together, as a cook reads them', () {
      expect(
        ingredientQuantityLabel(base.copyWith(quantity: 1.5, unit: 'cup')),
        '1½ cup',
      );
      expect(
        ingredientQuantityLabel(base.copyWith(quantity: 2, unit: 'cup')),
        '2 cup',
      );
      expect(
        ingredientQuantityLabel(base.copyWith(quantity: 1.25, unit: 'cup')),
        '1¼ cup',
      );
      // Metric keeps its decimal (UX-023).
      expect(
        ingredientQuantityLabel(base.copyWith(quantity: 1.5, unit: 'L')),
        '1.5 L',
      );
      expect(ingredientQuantityLabel(base.copyWith(quantity: 600)), '600');
    });

    test(
      'a unit with no quantity keeps the unit, it does not become a dash',
      () {
        // Reachable from the editor: the quantity field parses a decimal, so
        // typing `1/2` fails the parse and saves the unit alone.
        expect(ingredientQuantityLabel(base.copyWith(unit: 'cup')), 'cup');
      },
    );

    test('the unit outranks the note, and the note is not lost', () {
      final ing = base.copyWith(unit: 'tbsp', note: 'melted');
      expect(ingredientQuantityLabel(ing), 'tbsp');
      // Not the quantity, so it rides beside the name instead.
      expect(ingredientNoteIsQuantity(ing), isFalse);
    });

    test('the note is the quantity only when nothing else is', () {
      final ing = base.copyWith(note: 'to taste');
      expect(ingredientQuantityLabel(ing), 'to taste');
      expect(ingredientNoteIsQuantity(ing), isTrue);
      // With a number present the note is never the quantity.
      expect(ingredientNoteIsQuantity(ing.copyWith(quantity: 1)), isFalse);
    });

    test('nothing at all is a dash', () {
      expect(ingredientQuantityLabel(base), '—');
      expect(ingredientQuantityLabel(base.copyWith(unit: '', note: '')), '—');
    });

    test('the factor scales the number and never the unit', () {
      final ing = base.copyWith(quantity: 600, unit: 'g');
      expect(ingredientQuantityLabel(ing, factor: 1.25), '750 g');
      // The fraction is chosen AFTER scaling: ¾ cup doubled is 1½ cup.
      expect(
        ingredientQuantityLabel(
          base.copyWith(quantity: 0.75, unit: 'cup'),
          factor: 2,
        ),
        '1½ cup',
      );
      // A servings ratio's float residue never reaches the label.
      expect(
        ingredientQuantityLabel(
          base.copyWith(quantity: 3, unit: 'cloves'),
          factor: (0.1 + 0.2) / 0.3,
        ),
        '3 cloves',
      );
      // A unit-only row has no number to scale, so the factor cannot corrupt it.
      expect(
        ingredientQuantityLabel(base.copyWith(unit: 'cup'), factor: 3),
        'cup',
      );
    });
  });

  test('ingredientOneLine drops the dash rather than printing it', () {
    const base = Ingredient(id: 'i', groupId: 'g', name: 'yoghurt');
    expect(
      ingredientOneLine(base.copyWith(quantity: 1.5, unit: 'cup')),
      '1½ cup Yoghurt',
    );
    // No quantity, no unit, no note — the name alone, not "— Yoghurt".
    expect(ingredientOneLine(base), 'Yoghurt');
    expect(
      ingredientOneLine(base.copyWith(note: 'to taste')),
      'to taste Yoghurt',
    );
  });
}
