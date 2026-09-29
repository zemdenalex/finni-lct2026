import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/task.dart';
import 'package:finlit/features/progress/progress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget wrap(AppState app) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const ProgressScreen(),
      ),
    );

/// Одна прожитая неделя: карманные, план «всё в Нужное», одно задание,
/// закрытие. В копилку не ушло ничего — значит одно очко заботы
/// останется незаработанным, и его объяснение обязано быть на экране.
Future<GameTask> playOneWeek(AppState app) async {
  app.game.chooseGoal('zoo');
  await app.act((Game g) => g.startPeriod());
  final int money = app.game.snapshot.wallet.unallocated;
  await app.act((Game g) => g.confirmPlan(Allocation(needs: money)));
  final GameTask task = app.content.tasks.first;
  await app.act((Game g) => g.completeTask(task, best: true));
  await app.closePeriod();
  return task;
}

void main() {
  // 🔴 rootBundle кеширует не строку, а Future, созданный в зоне предыдущего
  // теста. Второй AppState.boot() в том же файле висит навсегда, и без этой
  // строки отладка выглядит как «тест зависает без причины».
  setUp(rootBundle.clear);

  testWidgets(
      '§2.5.11.1 итоги недели: объяснение есть и у незаработанного очка', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await playOneWeek(app);

    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    expect(find.text('Итоги недели 1'), findsOneWidget);
    expect(find.text('Отложено: в этот раз нет'), findsOneWidget);
    // 🔴 Незаработанное очко объясняется без обвинения (§2.2).
    expect(
      find.textContaining('Даже одна монетка приближает цель'),
      findsOneWidget,
    );
    // План и факт по каждому конверту (§2.5.5.3).
    expect(find.text('План и как вышло'), findsOneWidget);
    for (final Envelope e in Envelope.values) {
      expect(find.text(e.title), findsWidgets);
    }
  });

  testWidgets('§2.5.10.3 экран объясняет причину настроения словами', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await playOneWeek(app);

    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    expect(find.text('Почему у Финни такое настроение'), findsOneWidget);
    expect(find.textContaining('Прошла неделя'), findsWidgets);
    expect(
      find.text('Пройденные задания подняли Финни настроение.'),
      findsOneWidget,
    );
  });

  testWidgets('§2.5.10.1 видны все три стадии развития', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await playOneWeek(app);

    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    expect(find.text('Новичок'), findsOneWidget);
    expect(find.text('Копилкин'), findsOneWidget);
    expect(find.text('Хранитель копилки'), findsOneWidget);
    expect(find.text('сейчас'), findsOneWidget);
    expect(find.textContaining('откроется при'), findsWidgets);
  });

  testWidgets('§2.5.4.3 история недели разворачивает числа в причины', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    final GameTask task = await playOneWeek(app);

    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    // Тексты берутся из copy.json по reasonCode записи журнала.
    expect(find.textContaining('Родители доверили тебе на неделю'), findsOneWidget);
    expect(find.textContaining('За задание «${task.title}»'), findsOneWidget);
    expect(find.text('Неделя 1'), findsOneWidget);

    // Выполненные задания сгруппированы по темам (§2.5.11.1).
    expect(find.text(task.topic.title), findsOneWidget);
    expect(find.text(task.title), findsWidgets);

    // Переключатель недель показывает записи другой недели.
    await tester.tap(find.text('Неделя 2'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Пришли карманные на неделю'), findsNothing);
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
    await playOneWeek(app);

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
          home: const ProgressScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
