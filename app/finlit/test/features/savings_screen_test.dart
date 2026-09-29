import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/goal.dart';
import 'package:finlit/features/savings/savings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget wrap(AppState app) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildAppTheme(), home: const SavingsScreen()),
    );

Future<AppState> booted() async {
  final AppState app = AppState(MemoryStorage());
  await app.boot();
  return app;
}

/// Высокое окно: ListView строит детей лениво, а проверяем мы то, что
/// ребёнок видит целиком.
void useTallScreen(WidgetTester tester, {double width = 400}) {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  // 🔴 rootBundle кеширует не строку, а Future, созданный в зоне предыдущего
  // теста: без сброса второй AppState.boot() в этом файле виснет навсегда.
  setUp(rootBundle.clear);


  testWidgets(
      '§2.5.7.1–2 цель выбирается, видны стоимость, накопленное '
      'и остаток', (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();
    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    expect(find.text('На что копим?'), findsOneWidget);
    // §2.6: цель-впечатление подписана как цель, а не как вещь.
    expect(
        find.textContaining('Копить можно не только на вещи'), findsOneWidget);

    await tester.tap(find.text('Поход в зоопарк с Финни'));
    await tester.pumpAndSettle();

    expect(app.game.profile.goalId, 'zoo');
    expect(find.text('Накоплено 0 из 20'), findsOneWidget);
    expect(find.textContaining('Осталось 20'), findsOneWidget);
  });

  testWidgets('§2.5.7.4 срок не выдумывается, пока не было ни одного взноса',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();
    app.game.chooseGoal('zoo');
    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    expect(
      find.text('Срок появится, когда ты первый раз отложишь монетки '
          'в копилку.'),
      findsOneWidget,
      reason: '§2.5.7.4: расчёт должен быть понятным — придуманного числа '
          'недель на экране быть не может',
    );
  });

  testWidgets('§2.5.7.3 монетки переводятся в накопления',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();
    app.game.chooseGoal('zoo');
    await app.act((Game g) => g.startPeriod());

    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Отложить монетки'));
    await tester.pumpAndSettle();
    // Сумма набирается кнопками, а не клавиатурой. Между нажатиями нужен
    // кадр: без него второе нажатие попадает в ещё не перестроенный виджет.
    for (int i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Отложить: больше на одну'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Отложить 3'));
    await tester.pumpAndSettle();

    expect(app.game.snapshot.wallet.savings, 3);
  });

  testWidgets('§2.5.7.5 снятие показывает предпросмотр ДО подтверждения',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();
    app.game.chooseGoal('zoo');
    await app.act((Game g) => g.startPeriod());
    await app.act((Game g) =>
        g.confirmPlan(const Allocation(needs: 3, wants: 2, savings: 5)));
    expect(app.game.snapshot.wallet.savings, 5);

    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Взять из копилки'));
    await tester.pumpAndSettle();

    // Предпросмотр: сумма и срок — оба до подтверждения.
    expect(find.text('В копилке было 5, станет 4.'), findsOneWidget);
    expect(
        find.text('До цели было 3 недели, станет 4 недели.'), findsOneWidget);
    expect(app.game.snapshot.wallet.savings, 5,
        reason: '§2.5.7.5: до отдельного подтверждения копилка не меняется');

    await tester.tap(find.textContaining('Да, взять'));
    await tester.pumpAndSettle();

    expect(app.game.snapshot.wallet.savings, 4);
  });

  testWidgets('непредвиденный расход: четыре варианта, включая перенос',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();
    app.game.chooseGoal('zoo');
    // Доходим до недели непредвиденного расхода (economy.json: неделя 3).
    for (int i = 0; i < 3; i++) {
      await app.act((Game g) => g.startPeriod());
      // План — из того, что реально пришло: с 19.09 бюджет от родителей
      // зависит от стадии Финни (10 → 8 → 6), и фиксированные 10 на третьей
      // неделе могли не поместиться.
      await app.act((Game g) => g.confirmPlan(Allocation(
          needs: 3, wants: 2, savings: g.snapshot.wallet.unallocated - 5)));
      if (i < 2) await app.closePeriod();
    }
    expect(app.game.unexpectedPending, isTrue);

    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    expect(find.text('Финни промочил лапы'), findsOneWidget);
    expect(find.textContaining('тёплый плед и чай — 3'), findsOneWidget);
    expect(find.text('Взять 3 из копилки'), findsOneWidget);
    expect(find.text('Взять 3 из конверта «Хочу»'), findsOneWidget);
    expect(find.text('Выполнить задание и заработать'), findsOneWidget);

    // 🔴 Четвёртый вариант обязателен: без него это не выбор, а налог
    // с тремя способами оплаты.
    final Finder defer =
        find.text('Обойтись домашним пледом и перенести на следующую неделю');
    expect(defer, findsOneWidget);

    // Сравниваем до и после, а не с готовым числом: сумма в копилке
    // зависит от того, сколько доверили родители на каждой стадии, а
    // проверяется здесь ровно одно — что перенос ничего не списывает.
    final int savingsBefore = app.game.snapshot.wallet.savings;
    await tester.tap(defer);
    await tester.pumpAndSettle();

    expect(app.game.unexpectedPending, isFalse);
    expect(app.game.snapshot.wallet.savings, savingsBefore,
        reason: 'перенос ничего не списывает');
  });

  testWidgets('когда подработка кончилась, «заработать» не предлагается',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    app.game.chooseGoal('zoo');
    for (int i = 0; i < 3; i++) {
      await app.act((Game g) => g.startPeriod());
      await app.act((Game g) => g.confirmPlan(Allocation(
          needs: 3, wants: 2, savings: g.snapshot.wallet.unallocated - 5)));
      if (i < 2) await app.closePeriod();
    }
    int guard = 0;
    while (!app.game.earnCapReached && guard++ < 20) {
      await app.act((Game g) =>
          g.completeTask(g.availableTasks.first, best: true));
    }
    expect(app.game.earnCapReached, isTrue);

    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();
    expect(app.game.unexpectedPending, isTrue);
    expect(find.text('Выполнить задание и заработать'), findsNothing,
        reason: 'задание уже не принесёт монеток — обещать их нечестно');
    expect(find.textContaining('перенести на следующую неделю'), findsOneWidget);
  });

  testWidgets('экран не переполняется на 360 dp при крупном шрифте',
      (WidgetTester tester) async {
    // §3.1.2 (360 dp) и §3.6.4 (системное увеличение шрифта).
    useTallScreen(tester, width: 360);
    final AppState app = await booted();
    app.game.chooseGoal('scooter');
    await app.act((Game g) => g.startPeriod());

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const SavingsScreen(),
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

  testWidgets(
      'мечта исполняется с подтверждением: названы суммы, мечта остаётся '
      'в мире, дальше — выбор следующей', (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();
    await app.act((Game g) => g.startPeriod());
    app.game.chooseGoal('zoo');
    final int money = app.game.snapshot.wallet.unallocated;
    await app.act((Game g) => g.allocate(Envelope.savings, money));
    // Добрать до цены через следующие недели, если одной не хватает.
    while (!app.game.goalReached) {
      await app.closePeriod();
      await app.act((Game g) => g.startPeriod());
      await app.act((Game g) =>
          g.allocate(Envelope.savings, g.snapshot.wallet.unallocated));
    }
    final int before = app.game.snapshot.wallet.savings;
    final int price = app.game.goal!.price;

    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Исполнить мечту'));
    await tester.pumpAndSettle();

    // §3.6.8: последствие названо числами до подтверждения.
    expect(find.textContaining('останется ${before - price}'), findsOneWidget);
    await tester.tap(find.text('Пока подожду'));
    await tester.pumpAndSettle();
    expect(app.game.goal, isNotNull, reason: 'отказ ничего не меняет');

    await tester.tap(find.text('Исполнить мечту'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Исполнить'));
    await tester.pumpAndSettle();

    expect(find.text('Мечта теперь стоит во дворе — насовсем.'), findsOneWidget);
    expect(app.game.snapshot.wallet.savings, before - price);
    expect(app.game.fulfilledGoals.map((Goal g) => g.id), contains('zoo'));

    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(find.text('На что копим?'), findsOneWidget,
        reason: 'после исполнения — выбор следующей мечты');
  });
}
