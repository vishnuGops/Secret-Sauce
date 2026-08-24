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

    test('quantity and unit together, trimmed to the shortest honest form', () {
      expect(
        ingredientQuantityLabel(base.copyWith(quantity: 1.5, unit: 'cup')),
        '1.5 cup',
      );
      expect(
        ingredientQuantityLabel(base.copyWith(quantity: 2, unit: 'cup')),
        '2 cup',
      );
      expect(
        ingredientQuantityLabel(base.copyWith(quantity: 1.25, unit: 'cup')),
        '1.25 cup',
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
      '1.5 cup Yoghurt',
    );
    // No quantity, no unit, no note — the name alone, not "— Yoghurt".
    expect(ingredientOneLine(base), 'Yoghurt');
    expect(
      ingredientOneLine(base.copyWith(note: 'to taste')),
      'to taste Yoghurt',
    );
  });
}
