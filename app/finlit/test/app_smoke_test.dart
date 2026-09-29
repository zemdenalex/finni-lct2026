import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget wrap(AppState app, Widget child) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildAppTheme(), home: child),
    );

void main() {
  // 🔴 rootBundle кеширует не строку, а Future, созданный в зоне предыдущего теста.
  // Второй AppState.boot() в том же файле висит навсегда, и без этой строки
  // отладка выглядит как «тест зависает без причины».
  setUp(rootBundle.clear);

  testWidgets('§2.5.13 профиль переживает перезапуск приложения', (
    WidgetTester tester,
  ) async {
    final MemoryStorage storage = MemoryStorage();

    final AppState first = AppState(storage);
    await first.boot();
    await first.act((Game g) => g.startPeriod());
    final int saved = first.game.snapshot.wallet.unallocated;
    expect(saved, greaterThan(0));

    // «Перезапуск»: новое состояние поверх того же хранилища.
    final AppState second = AppState(storage);
    await second.boot();
    expect(second.game.snapshot.wallet.unallocated, saved,
        reason: 'ТЗ §2.5.13: профиль, баланс и покупки сохраняются после '
            'закрытия и повторного запуска');
  });

  testWidgets('§2.5.3 главный экран показывает всё одновременно', (
    WidgetTester tester,
  ) async {
    // Высокое окно: ListView строит детей лениво, и «одновременно видны»
    // проверяется на всём содержимом экрана, а не на первом экране прокрутки.
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await app.act((Game g) => g.startPeriod());
    app.game.chooseGoal('zoo');

    await tester.pumpWidget(wrap(app, const HomeScreen()));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('У тебя есть'), findsOneWidget);
    expect(find.text('Финни'), findsOneWidget);
    expect(find.text('Поход в зоопарк с Финни'), findsOneWidget);
    for (final String section in <String>[
      'План',
      'Покупки',
      'Задания',
      'Копилка',
      'Прогресс',
      'Взрослым',
    ]) {
      // findsAtLeastNWidgets, а не findsOneWidget: «Копилка» на главном
      // экране появляется дважды и оба раза законно — как конверт кошелька
      // (§2.5.3.1, сумма накоплений видна сразу) и как плитка раздела
      // (§2.5.3.2, накопления доступны с главного).
      expect(find.text(section), findsAtLeastNWidgets(1),
          reason: '§2.5.3.2: раздел «$section» должен быть доступен с главного');
    }
  });

  testWidgets('главный экран не переполняется на экране шириной 360 dp', (
    WidgetTester tester,
  ) async {
    // §3.1.2: «корректная работа в портретной ориентации на экранах
    // от 360 dp по ширине».
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await app.act((Game g) => g.startPeriod());

    await tester.pumpWidget(wrap(app, const HomeScreen()));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
