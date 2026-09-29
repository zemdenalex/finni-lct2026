import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/features/demo/demo_screen.dart';
import 'package:finlit/features/demo/expert_checklist.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget wrap(AppState app, Widget child) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildAppTheme(), home: child),
    );

void tallScreen(WidgetTester tester, {double width = 400}) {
  tester.view.physicalSize = Size(width, 12000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> flushSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

ExpertStep step(List<ExpertStep> steps, int no) =>
    steps.firstWhere((ExpertStep s) => s.no == no);

CatalogItem cheapest(Game g, Envelope e) => g.content.catalog
    .where((CatalogItem i) => i.envelope == e)
    .reduce((CatalogItem a, CatalogItem b) => a.price <= b.price ? a : b);

CatalogItem dearest(Game g) => g.content.catalog
    .reduce((CatalogItem a, CatalogItem b) => a.price >= b.price ? a : b);

void main() {
  // 🔴 rootBundle кеширует не строку, а Future, созданный в зоне того теста,
  // где ассет прочитали впервые. Второй AppState.boot() в том же файле ждёт
  // этот Future вечно — тест виснет без единого сообщения.
  setUp(rootBundle.clear);

  test('Приложение А: шаг 7 засчитывается только вместе с отклонённой покупкой',
      () async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    final Game g = app.game;

    g.startPeriod();
    g.confirmPlan(const Allocation(needs: 5, wants: 4, savings: 1));
    g.buy(cheapest(g, Envelope.needs));
    g.buy(cheapest(g, Envelope.wants));

    List<ExpertStep> steps = ExpertChecklist.of(g);
    expect(step(steps, 7).done, isFalse,
        reason: 'двух покупок мало: шаг требует ещё попытки при нехватке');

    g.declinePurchase(dearest(g));
    steps = ExpertChecklist.of(g);
    expect(step(steps, 7).done, isTrue);
    expect(
      step(steps, 7).parts.every((CheckPart p) => p.done),
      isTrue,
    );
  });

  test('шаги выводятся из журнала, а не отмечаются вручную', () async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    final Game g = app.game;

    List<ExpertStep> steps = ExpertChecklist.of(g);
    expect(step(steps, 4).done, isFalse);
    expect(step(steps, 5).done, isFalse);
    expect(step(steps, 8).done, isFalse);
    expect(step(steps, 10).done, isFalse);
    expect(step(steps, 2).done, isTrue,
        reason: '§3.5.1 выполняется устройством данных: полей для имени, '
            'телефона и e-mail в профиле нет');

    g.startPeriod();
    g.chooseGoal(g.content.goals.first.id);
    g.confirmPlan(const Allocation(needs: 4, wants: 3, savings: 3));
    g.completeTask(g.availableTasks.first, best: true);
    g.closePeriod();

    steps = ExpertChecklist.of(g);
    expect(step(steps, 4).done, isTrue, reason: 'карманные начислены');
    expect(step(steps, 5).done, isTrue, reason: 'план подтверждён');
    expect(step(steps, 6).done, isTrue, reason: 'задание выполнено');
    expect(step(steps, 8).done, isTrue, reason: 'цель выбрана, копилка полна');
    expect(step(steps, 9).done, isTrue, reason: 'неделя закрыта');
    expect(step(steps, 10).done, isTrue, reason: 'идёт вторая неделя');
    expect(step(steps, 11).done, isTrue,
        reason: 'в журнале записи двух недель');
  });

  test('шаг 12 отмечается после захода в раздел для взрослого', () async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    final Game g = app.game;

    expect(step(ExpertChecklist.of(g), 12).done, isFalse);
    expect(
        step(ExpertChecklist.of(g, demoResetWasDone: true), 12).done, isTrue);

    g.parentUnlockTask();
    expect(step(ExpertChecklist.of(g), 12).done, isTrue);
  });

  test('каждый шаг честно подписан, откуда взялась отметка', () async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    final List<ExpertStep> steps = ExpertChecklist.of(app.game);

    expect(steps.length, 12, reason: 'в Приложении А ровно 12 шагов');
    for (final ExpertStep s in steps) {
      expect(s.evidence, isNotEmpty);
      expect(s.statusLabel, s.done ? 'Выполнено' : 'Ещё не выполнено');
    }
    // Шаги, которые приложение доказать о себе не может.
    expect(step(steps, 1).source, CheckSource.expert);
    expect(step(steps, 11).source, CheckSource.expert);
  });

  testWidgets('§2.5.13 чеклист отмечает шаг 7 после отклонённой покупки', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    final Game g = app.game;
    g.startPeriod();
    g.confirmPlan(const Allocation(needs: 5, wants: 4, savings: 1));
    g.buy(cheapest(g, Envelope.needs));
    g.buy(cheapest(g, Envelope.wants));

    await tester.pumpWidget(wrap(app, const DemoScreen()));
    await tester.pumpAndSettle();
    expect(
        find.text('Попытка при нехватке монеток — пока нет'), findsOneWidget);

    await app.act((Game game) => game.declinePurchase(dearest(game)));
    await tester.pumpAndSettle();
    expect(find.text('Попытка при нехватке монеток — есть'), findsOneWidget);
  });

  testWidgets('§2.5.13 панель управления и сброс тестового профиля', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    final MemoryStorage storage = MemoryStorage();
    final AppState app = AppState(storage);
    await app.boot();
    await app.setDemoMode(true);
    await app.act((Game g) => g.startPeriod());
    expect(app.game.ledger, isNotEmpty);

    await tester.pumpWidget(wrap(app, const DemoScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Демонстрационный режим'), findsOneWidget);
    expect(find.text('Завершить неделю'), findsOneWidget);
    expect(find.text('Начислить карманные'), findsOneWidget);
    expect(find.text('Вызвать непредвиденный расход'), findsOneWidget);

    // Экран «Проверка» открывается и показывает все 12 шагов Приложения А.
    expect(find.textContaining('из 12 шагов'), findsOneWidget);
    for (int no = 1; no <= 12; no++) {
      expect(find.text('Шаг $no'), findsOneWidget);
    }

    // §3.6: сброс — через подтверждение.
    await tester.tap(find.text('Сбросить тестовый профиль'));
    await tester.pumpAndSettle();
    expect(find.text('Сбросить тестовый профиль?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Сбросить'));
    await tester.pumpAndSettle();

    expect(app.game.ledger, isEmpty,
        reason: '§2.5.13.2: тестовый профиль сбрасывается к исходному '
            'состоянию');
    await flushSnack(tester);
  });

  testWidgets('§2.5.13.2 непредвиденный расход воспроизводится без ожидания', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await app.setDemoMode(true);

    await tester.pumpWidget(wrap(app, const DemoScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Вызвать непредвиденный расход'));
    await tester.pumpAndSettle();

    expect(app.game.periodNo, app.content.economy.unexpectedPeriod);
    expect(app.game.unexpectedPending, isTrue);
  });

  testWidgets('§3.1.2 чеклист не переполняется на 360 dp', (
    WidgetTester tester,
  ) async {
    tallScreen(tester, width: 360);
    final AppState app = AppState(MemoryStorage());
    await app.boot();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DemoScreen(),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
