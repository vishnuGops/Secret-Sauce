// UX-047 on the app side: the editor's two image controls were unnamed
// buttons once a photo was in place (a `DecorationImage` and a bare `Image`
// carry no label), and the recipe page's cover was an unnamed image.
import 'dart:typed_data';

import 'package:app/features/recipe_editor/cover_picker.dart';
import 'package:app/features/recipe_editor/edit_models.dart';
import 'package:app/features/recipe_editor/steps_editor.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

// A 1×1 transparent PNG.
final _png = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, //
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, //
  120, 156, 99, 0, 1, 0, 0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, //
  78, 68, 174, 66, 96, 130,
]);

void main() {
  testWidgets('the cover picker is a named button, empty or not', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(CoverPicker(onPick: () {})));
    expect(find.bySemanticsLabel('Add cover photo'), findsOneWidget);

    await tester.pumpWidget(_app(CoverPicker(bytes: _png, onPick: () {})));
    expect(
      tester.getSemantics(find.byType(CoverPicker)),
      isSemantics(
        label: 'Cover photo, tap to replace',
        isButton: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('a step photo in the editor is a named button', (tester) async {
    final handle = tester.ensureSemantics();
    final step = EditStep(text: 'Bake.')..pendingImageBytes = _png;
    // `StepsEditor` is a sliver since Phase 39 (the editor page's drag
    // auto-scroll), so it is hosted the way the page hosts it.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Form(
            child: CustomScrollView(
              slivers: [
                StepsEditor(
                  groups: [
                    EditStepGroup(steps: [step]),
                  ],
                  onChanged: () {},
                  onPickImage: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Step photo, tap to replace'), findsOneWidget);
    handle.dispose();
  });
}
