import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `ChefAvatar.initialsFor` (UX-040): initials came from whatever character
/// opened each whitespace token, so the imported byline
/// `Kannamma @kannammacooks.com` drew "K@" on its recipe page.
void main() {
  group('initialsFor (UX-040)', () {
    for (final (name, expected, why) in <(String, String, String)>[
      (
        'Kannamma @kannammacooks.com',
        'K',
        'a token opening with @ is a handle, not a name word',
      ),
      ('Amara Baptiste', 'AB', 'first and last word'),
      ('Amara Nia Baptiste', 'AB', 'two initials at most: first and last'),
      ('amara', 'A', 'one word, one letter, upper-cased'),
      ('José Ñúñez', 'JÑ', 'any script, accents kept'),
      ("O'Brien", 'O', 'an apostrophe does not split a word'),
      ('(Kannamma)', 'K', 'punctuation before the first letter is skipped'),
      ('Chef 2Go', 'CG', 'a digit is not a letter; the letter after it is'),
      ('Amara 123', 'A', 'a token with no letter contributes nothing'),
      (
        'E\u0301lodie Roux',
        'E\u0301R',
        'a decomposed accent stays one grapheme',
      ),
      ('  ', '?', 'blank'),
      ('', '?', 'empty'),
      ('123 456', '?', 'no letter anywhere'),
      ('@handle', '?', 'nothing but a handle'),
    ]) {
      test('"$name" -> "$expected" ($why)', () {
        expect(ChefAvatar.initialsFor(name), expected);
      });
    }
  });

  testWidgets('the circle renders the letters-only initials', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(child: ChefAvatar(name: 'Kannamma @kannammacooks.com')),
        ),
      ),
    );

    expect(find.text('K'), findsOneWidget);
    expect(find.text('K@'), findsNothing);
  });
}
