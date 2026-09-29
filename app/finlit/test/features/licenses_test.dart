import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/features/settings/settings_screen.dart';
import 'package:finlit/main.dart' show fontLicenses;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// §3.3: права на шрифты должны быть «в составе прототипа», а OFL 1.1 требует
// поставлять текст лицензии вместе со шрифтом. До 23.09 оба текста лежали
// только в репозитории, и в установленной игре их не было.
void main() {
  setUp(rootBundle.clear);

  test('тексты OFL обоих шрифтов лежат в сборке', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final List<LicenseEntry> entries = await fontLicenses().toList();
    expect(entries.map((LicenseEntry e) => e.packages.single),
        <String>['Onest', 'Unbounded']);
    for (final LicenseEntry e in entries) {
      final String text =
          e.paragraphs.map((LicenseParagraph p) => p.text).join('\n');
      expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
    }
  });

  testWidgets('экран лицензий открывается из настроек', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildAppTheme(), home: const SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Лицензии'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
