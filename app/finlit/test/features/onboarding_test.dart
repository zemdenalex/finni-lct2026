import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/features/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget wrap(AppState app, Widget child) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildAppTheme(), home: child),
    );

/// Онбординг, открытый как подсказка с главного: под ним есть экран,
/// на который можно вернуться.
Widget wrapPushed(AppState app) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const OnboardingScreen()),
                ),
                child: const Text('подсказка'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> toLastPage(WidgetTester tester) async {
  while (find.text('Дальше').evaluate().isNotEmpty) {
    await tester.tap(find.text('Дальше'));
    await tester.pumpAndSettle();
  }
}

void main() {
  // 🔴 rootBundle кеширует не строку, а Future, созданный в зоне предыдущего
  // теста. Второй AppState.boot() в том же файле висит навсегда, и без этой
  // строки отладка выглядит как «тест зависает без причины».
  setUp(rootBundle.clear);

  testWidgets('§2.5.1.1 знакомство называет три типа решений', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await tester.pumpWidget(wrap(app, const OnboardingScreen()));
    await tester.pumpAndSettle();

    // Три решения — на второй странице, рядом с конвертами.
    await tester.tap(find.text('Дальше'));
    await tester.pumpAndSettle();

    expect(find.text('Потратить на нужное'), findsOneWidget);
    expect(find.text('Потратить на то, что хочется'), findsOneWidget);
    expect(find.text('Отложить в копилку'), findsOneWidget);
  });

  testWidgets('§2.5.1.2 первый запуск: в конце «Поехали», «Закрыть» нет', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await tester.pumpWidget(wrap(app, const OnboardingScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Закрыть'), findsNothing);
    await toLastPage(tester);
    expect(find.text('Поехали'), findsOneWidget);
    expect(find.text('Закрыть'), findsNothing);
  });

  testWidgets('§2.5.1.3 тот же экран открывается как подсказка и закрывается', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await tester.pumpWidget(wrapPushed(app));
    await tester.tap(find.text('подсказка'));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    await toLastPage(tester);
    // Повторный вызов заканчивается возвратом, а не переходом к созданию
    // питомца: «Поехали» здесь не место.
    expect(find.text('Поехали'), findsNothing);
    expect(find.text('Закрыть'), findsOneWidget);

    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('подсказка'), findsOneWidget);
  });

  testWidgets('§3.1.2 не переполняется на 360 dp при увеличенном шрифте', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildAppTheme(),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await toLastPage(tester);
    expect(tester.takeException(), isNull);
  });
}
