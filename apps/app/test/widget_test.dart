import 'package:app/features/home/home_screen.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home landing shows app name and sign-in actions',
      (tester) async {
    // The landing page targets real browser sizes; give the test a roomy view.
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        // Signed-out state; avoids touching the (uninitialized) Supabase client.
        overrides: [currentUserIdProvider.overrideWithValue(null)],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    expect(find.text('Secret-Sauce'), findsOneWidget);
    expect(find.text('Sign up'), findsWidgets);
  });
}
