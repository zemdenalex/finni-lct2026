import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/core/widgets.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/features/plan/plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget wrap(AppState app, Widget child, {double textScale = 1.0}) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      theme: buildAppTheme(),
      home: child,
      builder: (BuildContext ctx, Widget? c) => MediaQuery(
        data: MediaQuery.of(ctx)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
    ),
  );
}

/// Состояние «пришли карманные, план ещё не подтверждён».
Future<AppState> freshWeek() async {
  final AppState app = AppState(MemoryStorage());
  await app.boot();
  await app.act((Game g) => g.startPeriod());
  return app;
}

/// Тест с включённой семантикой.
///
/// Подписи для чтения с экрана — требование §3.6, и проверять их нужно теми же
/// тестами. Дескриптор семантики приходится закрывать внутри тела теста:
/// flutter_test проверяет его до того, как отработают addTearDown.
void semanticTest(String name, Future<void> Function(WidgetTester t) body) {
  testWidgets(name, (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await body(tester);
    handle.dispose();
  });
}

/// Общая подготовка экрана.
///
/// Окно высокое: ListView строит детей лениво, а проверять нужно все три
/// конверта. Семантика включается явно — иначе подписи для чтения с экрана
/// в тестовом окружении не собираются, и проверять §3.6 было бы нечем.
Future<void> pumpPlan(
  WidgetTester tester,
  AppState app, {
  Size size = const Size(400, 2400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(wrap(app, const PlanScreen(), textScale: textScale));
  await tester.pumpAndSettle();
}

Finder plus(Envelope e) =>
    find.bySemanticsLabel('Положить монетку в конверт «${e.title}»');

Finder minus(Envelope e) =>
    find.bySemanticsLabel('Убрать монетку из конверта «${e.title}»');

Future<void> tapTimes(WidgetTester tester, Finder f, int times) async {
  for (int i = 0; i < times; i++) {
    await tester.tap(f);
    await tester.pump();
  }
}

bool doneEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Готово'))
        .onPressed !=
    null;

/// Каждый тест читает контент заново.
///
/// rootBundle кэширует не строку, а Future, созданный внутри предыдущего теста.
/// Второй AppState.boot() в том же файле дожидался бы этого Future в уже
/// завершённой зоне flutter_test и висел бы вечно — сброс кэша убирает
/// зависимость между тестами.
void main() {
  setUp(rootBundle.clear);
  semanticTest('§2.5.5.1 экран строится и предлагает три направления', (
    WidgetTester tester,
  ) async {
    final AppState app = await freshWeek();
    final int money = app.game.snapshot.wallet.unallocated;

    await pumpPlan(tester, app);

    expect(find.text('Разложи $money монеток'), findsOneWidget);
    for (final Envelope e in Envelope.values) {
      expect(plus(e), findsOneWidget,
          reason: '§2.5.5.1: направлений должно быть не меньше трёх');
      expect(minus(e), findsOneWidget);
    }
  });

  semanticTest('§2.5.5.2 остаток считается и не уходит ниже нуля', (
    WidgetTester tester,
  ) async {
    final AppState app = await freshWeek();
    final int money = app.game.snapshot.wallet.unallocated;

    await pumpPlan(tester, app);

    expect(find.bySemanticsLabel('Осталось разложить: $money монеток'),
        findsOneWidget);

    await tapTimes(tester, plus(Envelope.needs), 4);
    expect(
      find.bySemanticsLabel('Осталось разложить: ${money - 4} монеток'),
      findsOneWidget,
    );

    await tapTimes(tester, minus(Envelope.needs), 1);
    expect(
      find.bySemanticsLabel('Осталось разложить: ${money - 3} монеток'),
      findsOneWidget,
    );

    // §2.5.5.2: сумма распределения не может превысить доступный бюджет —
    // лишние нажатия «+1» просто ничего не делают.
    await tapTimes(tester, plus(Envelope.wants), money + 5);
    expect(
        find.bySemanticsLabel('Осталось разложить: 0 монеток'), findsOneWidget);
    expect(app.game.currentPlan, isNull,
        reason: 'до нажатия «Готово» план в журнал не попадает');
  });

  semanticTest('подтверждение недоступно, пока остаток не разложен', (
    WidgetTester tester,
  ) async {
    final AppState app = await freshWeek();
    final int money = app.game.snapshot.wallet.unallocated;

    await pumpPlan(tester, app);

    expect(doneEnabled(tester), isFalse);
    expect(find.text('Положи монетки в конверты.'), findsOneWidget,
        reason: '§2.2: рядом с недоступной кнопкой сказано, что сделать');

    await tapTimes(tester, plus(Envelope.needs), money - 2);
    expect(doneEnabled(tester), isFalse);

    await tapTimes(tester, plus(Envelope.savings), 2);
    expect(doneEnabled(tester), isTrue);

    await tester.tap(find.widgetWithText(FilledButton, 'Готово'));
    await tester.pumpAndSettle();

    expect(app.game.currentPlan,
        Allocation(needs: money - 2, wants: 0, savings: 2));
    expect(find.text('План на неделю готов'), findsOneWidget,
        reason: '§2.5.9: после действия показывается карточка последствия');
  });

  semanticTest('§2.5.5.3 после подтверждения видно план и факт', (
    WidgetTester tester,
  ) async {
    final AppState app = await freshWeek();
    await app.act((Game g) =>
        g.confirmPlan(const Allocation(needs: 5, wants: 3, savings: 2)));
    await app.act((Game g) => g.buy(app.content.item('porridge')));

    await pumpPlan(tester, app);

    expect(find.text('План и что получается'), findsOneWidget);
    expect(find.text('По плану'), findsNWidgets(3));
    expect(find.text('Потрачено'), findsNWidgets(2));
    expect(find.text('Отложено'), findsOneWidget);
    expect(find.text('пока по плану'), findsNWidgets(3),
        reason: '🔴 недорасход по «Хочу» нарушением не считается — '
            'норма в PeriodRules асимметрична');
  });

  semanticTest('мягкая подсказка про еду не блокирует подтверждение', (
    WidgetTester tester,
  ) async {
    final AppState app = await freshWeek();
    final int money = app.game.snapshot.wallet.unallocated;

    await pumpPlan(tester, app);

    // Всё в «Хочу»: на еду не осталось ничего.
    await tapTimes(tester, plus(Envelope.wants), money);

    expect(find.textContaining('На еду и воду нужно хотя бы'), findsOneWidget);
    expect(doneEnabled(tester), isTrue,
        reason: '§2.2 «безопасная ошибка»: подсказка не запрещает');
  });

  semanticTest('не переполняется на 360 dp при крупном шрифте', (
    WidgetTester tester,
  ) async {
    final AppState app = await freshWeek();
    await pumpPlan(tester, app, size: const Size(360, 640), textScale: 1.3);
    expect(tester.takeException(), isNull);

    // Конверты должны быть достижимы: на узком экране с крупным шрифтом
    // список прокручивается, но нижняя полоса не имеет права занять его весь.
    // 🔴 Ищем по подписи для чтения с экрана, а не по значку: значков
    // Material в приложении больше нет, пиктограммы рисуются вектором и
    // `find.byIcon` про них ничего не знает.
    await tester.dragUntilVisible(
      plus(Envelope.needs),
      find.byType(ListView),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    await tester.tap(plus(Envelope.needs));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('прошлый план повторяется одним касанием и не выходит за бюджет',
      (WidgetTester tester) async {
    final AppState app = await freshWeek();
    await app.act((Game g) =>
        g.confirmPlan(const Allocation(needs: 4, wants: 3, savings: 3)));
    await app.closePeriod();
    await app.act((Game g) => g.startPeriod());
    final int available = app.game.snapshot.wallet.unallocated;

    await pumpPlan(tester, app);
    final Finder repeat = find.text('Разложить как на прошлой неделе');
    expect(repeat, findsOneWidget,
        reason: 'на второй неделе прошлый план можно повторить');

    await tester.tap(repeat);
    await tester.pumpAndSettle();

    // Кнопка исчезла — черновик уже не пустой, дальше он правится «+» и «−».
    expect(repeat, findsNothing);
    final int placed = available < 10 ? available : 10;
    final int left = available - placed;
    expect(
        find.bySemanticsLabel(
            'Осталось разложить: $left ${Coins.word(left)}'),
        findsOneWidget,
        reason: 'лишнего не кладётся: остаток не уходит в минус');
  });

  testWidgets('на первой неделе повторять нечего', (WidgetTester tester) async {
    final AppState app = await freshWeek();
    await pumpPlan(tester, app);
    expect(find.text('Разложить как на прошлой неделе'), findsNothing);
  });
}
