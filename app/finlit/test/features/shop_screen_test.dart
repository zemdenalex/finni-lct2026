import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/ledger/ledger_entry.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/features/shop/shop_screen.dart';
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

Future<AppState> freshWeek() async {
  final AppState app = AppState(MemoryStorage());
  await app.boot();
  await app.act((Game g) => g.startPeriod());
  return app;
}

/// Высокое окно: каталог длинный, а ListView строит детей лениво. Высота
/// с запасом: тестовый шрифт рисует каждую букву квадратом, и подписи
/// переносятся на больше строк, чем на телефоне.
Future<void> pumpShop(
  WidgetTester tester,
  AppState app, {
  Size size = const Size(400, 3600),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(wrap(app, const ShopScreen(), textScale: textScale));
  await tester.pumpAndSettle();
}

int declines(AppState app) => app.game.ledger
    .where((LedgerEntry e) => e.kind == LedgerKind.purchaseDeclined)
    .length;

/// Каждый тест читает контент заново.
///
/// rootBundle кэширует не строку, а Future, созданный внутри предыдущего теста.
/// Второй AppState.boot() в том же файле дожидался бы этого Future в уже
/// завершённой зоне flutter_test и висел бы вечно — сброс кэша убирает
/// зависимость между тестами.
void main() {
  setUp(rootBundle.clear);
  testWidgets('§2.5.6.1 два раздела и товары с ценой и подсказкой', (
    WidgetTester tester,
  ) async {
    final AppState app = await freshWeek();
    await pumpShop(tester, app);

    expect(find.text('Нужное'), findsOneWidget);
    expect(find.text('Хочу'), findsOneWidget);
    expect(find.text('Миска каши'), findsOneWidget);
    expect(find.text('Праздничный торт'), findsOneWidget);
    // §2.5.6.2: влияние на питомца словами, до покупки.
    expect(find.text('Финни поест. Хватит на эту неделю'), findsOneWidget);
  });

  testWidgets('§2.5.6.3 покупка требует подтверждения и списывает монетки', (
    WidgetTester tester,
  ) async {
    final AppState app = await freshWeek();
    await app.act((Game g) =>
        g.confirmPlan(const Allocation(needs: 5, wants: 3, savings: 2)));
    await pumpShop(tester, app);

    await tester.tap(find.text('Вода для умывания'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Купить'), findsOneWidget);
    expect(find.text('Не сейчас'), findsOneWidget);
    expect(app.game.snapshot.wallet.envelopes.needs, 5,
        reason: 'до подтверждения ничего не списывается');

    await tester.tap(find.widgetWithText(FilledButton, 'Купить'));
    await tester.pumpAndSettle();

    expect(app.game.snapshot.wallet.envelopes.needs, 4);
    expect(find.text('Куплено: Вода для умывания'), findsOneWidget);
  });

  testWidgets('§2.5.6.4 при нехватке показываются варианты, а не запрет', (
    WidgetTester tester,
  ) async {
    // План не подтверждён: в конвертах пусто, монетки ещё в руках.
    final AppState app = await freshWeek();
    await pumpShop(tester, app);

    await tester.tap(find.text('Праздничный торт'));
    await tester.pumpAndSettle();

    expect(find.text('Не хватает 5 монеток'), findsOneWidget);
    expect(find.text('Подождать до следующей недели'), findsOneWidget);
    expect(find.text('Выполнить задание'), findsOneWidget);
    expect(find.text('Разложить монетки по конвертам'), findsOneWidget);
    expect(find.textContaining('нельзя'), findsNothing,
        reason: '§2.5.6.4: вместо запрета — объяснение и варианты');

    // 🔴 «Подождать» стоит не последним «сдаться»: перенос покупки по
    // Терминам ТЗ не считается ошибкой пользователя.
    expect(
      tester.getTopLeft(find.text('Подождать до следующей недели')).dy,
      lessThan(tester.getTopLeft(find.text('Выполнить задание')).dy),
    );

    await tester.tap(find.text('Подождать до следующей недели'));
    await tester.pumpAndSettle();

    expect(declines(app), 1,
        reason: 'шаг 7 обязательного сценария опирается на запись об отказе');
    expect(find.text('Не хватает 5'), findsOneWidget);
    expect(app.game.snapshot.wallet.everything, 10,
        reason: '§2.5.6.4: отрицательного баланса и покупки в долг нет');
  });

  testWidgets('закрытый без выбора лист тоже попадает в журнал', (
    WidgetTester tester,
  ) async {
    final AppState app = await freshWeek();
    await pumpShop(tester, app);

    await tester.tap(find.text('Мячик'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не хватает'), findsWidgets);

    // Ребёнок просто закрыл лист, ничего не выбрав.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(declines(app), 1);
    expect(find.text('Не хватает 2'), findsNothing,
        reason: 'закрыл сам — комментировать это карточкой не нужно');
  });

  testWidgets('§2.5.6.4 «взять из Копилки» честно показывает цену выбора', (
    WidgetTester tester,
  ) async {
    final AppState app = await freshWeek();
    app.game.chooseGoal('zoo');
    await app.act((Game g) =>
        g.confirmPlan(const Allocation(needs: 3, wants: 0, savings: 7)));
    await pumpShop(tester, app);

    await tester.tap(find.text('Праздничный торт'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Взять 5 монеток из «Копилки»'), findsOneWidget);
    expect(find.textContaining('нед.'), findsWidgets,
        reason: '§2.5.7.5: последствие снятия видно до подтверждения');

    await tester.tap(find.textContaining('Взять 5 монеток из «Копилки»'));
    await tester.pumpAndSettle();

    expect(app.game.snapshot.wallet.savings, 2);
    expect(find.text('Куплено: Праздничный торт'), findsOneWidget);
    expect(declines(app), 0);
  });

  testWidgets('не переполняется на 360 dp при крупном шрифте', (
    WidgetTester tester,
  ) async {
    final AppState app = await freshWeek();
    await pumpShop(tester, app, size: const Size(360, 640), textScale: 1.3);
    expect(tester.takeException(), isNull);

    // Над каталогом — Финни с репликой: на низком экране первая позиция
    // ниже окна, а ListView невидимое не строит.
    await tester.scrollUntilVisible(find.text('Миска каши'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Миска каши'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
