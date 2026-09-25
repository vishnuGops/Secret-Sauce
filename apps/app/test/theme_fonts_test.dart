import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app resolves the fonts `design_system` bundles (Phase 36b). A family a
/// dependency declares is registered as `packages/<package>/<family>` — the
/// exact string `AppFonts` builds — so a renamed family, a dropped `fonts:`
/// block or a wrong `package:` would fall back to the platform font silently
/// on every screen. This is the one place that notices.
void main() {
  testWidgets('the bundled families resolve under their package prefix', (
    tester,
  ) async {
    final manifest = await rootBundle.loadString('FontManifest.json');
    expect(manifest, contains('"${AppFonts.uiFamily}"'));
    expect(manifest, contains('"${AppFonts.displayFamily}"'));
    expect(
      AppTheme.light().textTheme.bodyMedium?.fontFamily,
      AppFonts.uiFamily,
    );
    expect(
      AppTheme.light().textTheme.titleLarge?.fontFamily,
      AppFonts.displayFamily,
    );
  });
}
