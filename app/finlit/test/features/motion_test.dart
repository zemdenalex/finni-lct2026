import 'package:finlit/app_state.dart';
import 'package:finlit/core/finni_art.dart';
import 'package:finlit/core/icons.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/core/widgets.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/pet.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:finlit/features/pet/pet_create_screen.dart';
import 'package:finlit/features/plan/plan_screen.dart';
import 'package:finlit/features/progress/progress_screen.dart';
import 'package:finlit/features/savings/savings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Движение (§6 «Визуального направления») — проверка поведением.
///
/// 🔴 Каждая анимация здесь проверяется тремя вопросами, и третий важнее
/// первых двух:
///
///  1. с движением — оно есть и идёт не мгновенно;
///  2. без движения (флаг профиля **или** системная просьба) — конечное
///     состояние достигается за один кадр;
///  3. число на экране после анимации равно числу в модели, и ввод во время
///     анимации работает.
///
/// Третий вопрос — про настоящий риск: анимация, которая «теряет» монетку
/// или съедает касание, хуже отсутствия анимации.

Widget wrap(
  AppState app,
  Widget child, {
  bool systemReducedMotion = false,
}) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: child,
        builder: (BuildContext ctx, Widget? c) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(disableAnimations: systemReducedMotion),
          child: c!,
        ),
      ),
    );

Future<AppState> booted({bool animations = true}) async {
  final AppState app = AppState(MemoryStorage());
  await app.boot();
  if (!animations) {
    await app.updateProfile(app.game.profile
        .copyWith(settings: const GameSettings(animationsOn: false)));
  }
  return app;
}

/// Высокое окно: ListView строит детей лениво, а проверять нужно все три
/// конверта и всю карточку цели.
void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Кнопка «+1» у конверта: первая — «Нужное», вторая — «Хочу», третья —
/// «Копилка». По пиктограмме, а не по подписи: подпись живёт в семантике,
/// и включать её ради нажатия незачем.
Finder plus(int index) =>
    find.byWidgetPredicate((Widget w) => w is Pictogram && w.pic == Pic.plus)
        .at(index);

/// Сколько монеток **показано** в конверте.
int shownIn(WidgetTester tester, int index) =>
    tester.widgetList<EnvelopeCard>(find.byType(EnvelopeCard)).toList()[index]
        .amount;

/// Счётчик «осталось разложить»: единственные монетки кеглем 24 на экране.
int shownLeft(WidgetTester tester) => tester
    .widget<Coins>(
        find.byWidgetPredicate((Widget w) => w is Coins && w.size == 24))
    .amount;

Future<void> pumpPlan(
  WidgetTester tester,
  AppState app, {
  bool systemReducedMotion = false,
}) async {
  useTallScreen(tester);
  await tester.pumpWidget(
      wrap(app, const PlanScreen(), systemReducedMotion: systemReducedMotion));
  await tester.pumpAndSettle();
}

/// Взнос в одну монетку через нижний лист «Отложить монетки».
Future<void> depositOne(WidgetTester tester) async {
  await tester.tap(find.text('Отложить монетки'));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Отложить 1'));
  await tester.pumpAndSettle();
}

/// Анимация роста у Финни на карточке «научился».
Animation<double> grownFinni(WidgetTester tester) => tester
    .widget<FinniView>(
        find.byWidgetPredicate((Widget w) => w is FinniView && w.size == 96))
    .grow!;

/// Анимация кивка у крупного предпросмотра на экране создания питомца.
Animation<double> noddingFinni(WidgetTester tester) => tester
    .widget<FinniView>(
        find.byWidgetPredicate((Widget w) => w is FinniView && w.size == 168))
    .hop!;

/// Экран с одной шкалой показателя.
Widget meterHost(int value) =>
    Scaffold(body: MeterRow(meter: Meter.mood, value: value));

/// Неделя, в которой есть что раскладывать.
Future<AppState> freshWeek({bool animations = true}) async {
  final AppState app = await booted(animations: animations);
  await app.act((Game g) => g.startPeriod());
  return app;
}

/// Игра, доведённая до самого перехода на новую стадию.
///
/// Очки заботы начисляются только при закрытии недели, поэтому стадия
/// меняется тоже только там. Цикл идёт до смены — это два закрытия
/// при текущей экономике, но тест не завязан на это число.
Future<AppState> atStageUp() async {
  final AppState app = await booted();
  app.game.chooseGoal('zoo');
  for (int week = 0; week < 8; week++) {
    if (app.game.snapshot.stage != PetStage.novice) break;
    await app.act((Game g) => g.startPeriod());
    await app.act((Game g) => g.allocate(Envelope.savings, 5));
    await app.closePeriod();
  }
  return app;
}

/// Копилка, до цели которой не хватает ровно одной монетки, и монетка эта
/// лежит нераспределённой.
Future<AppState> oneCoinFromGoal({bool animations = true}) async {
  final AppState app = await booted(animations: animations);
  app.game.chooseGoal('zoo');
  const int price = 20;
  for (int week = 0; week < 8; week++) {
    await app.act((Game g) => g.startPeriod());
    final int savings = app.game.snapshot.wallet.savings;
    final int need = price - 1 - savings;
    final int free = app.game.snapshot.wallet.unallocated;
    if (need > 0) {
      final int take = need < free ? need : free;
      if (take > 0) await app.act((Game g) => g.allocate(Envelope.savings, take));
    }
    if (app.game.snapshot.wallet.savings == price - 1 &&
        app.game.snapshot.wallet.unallocated > 0) {
      return app;
    }
    await app.closePeriod();
  }
  return app;
}

void main() {
  // 🔴 rootBundle кеширует не строку, а Future, созданный в зоне того теста,
  // где ассет прочитали первым: без сброса второй AppState.boot() в файле
  // виснет навсегда и без единого сообщения.
  setUp(rootBundle.clear);

  // ───────────────────── монетка летит в конверт ─────────────────────

  testWidgets('§6 монетка долетает до конверта — и только тогда число растёт',
      (WidgetTester tester) async {
    final AppState app = await freshWeek();
    await pumpPlan(tester, app);
    final int available = app.game.snapshot.wallet.unallocated;

    await tester.tap(plus(0));
    await tester.pump();

    // Из рук монетка ушла сразу: ребёнок взял её и бросил.
    expect(shownLeft(tester), available - 1,
        reason: 'счётчик «осталось разложить» ждать прилёта не должен');
    // А в конверте её ещё нет — она в воздухе.
    expect(shownIn(tester, 0), 0,
        reason: '🔴 весь смысл перелёта в том, что число растёт в конце');

    await tester.pump(const Duration(milliseconds: 250));
    expect(shownIn(tester, 0), 0, reason: 'монетка ещё летит');

    await tester.pumpAndSettle();
    expect(shownIn(tester, 0), 1, reason: 'монетка долетела');
  });

  testWidgets('§6 монетка в воздухе не съедает следующее нажатие',
      (WidgetTester tester) async {
    final AppState app = await freshWeek();
    await pumpPlan(tester, app);
    final int available = app.game.snapshot.wallet.unallocated;

    // Ребёнок бьёт по «+1» три раза подряд, не дожидаясь ничего.
    await tester.tap(plus(0));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(plus(0));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(plus(1));
    await tester.pump(const Duration(milliseconds: 60));

    expect(shownLeft(tester), available - 3,
        reason: '🔴 слой с анимацией обязан пропускать касания насквозь');

    await tester.pumpAndSettle();
    expect(shownIn(tester, 0), 2);
    expect(shownIn(tester, 1), 1);
  });

  testWidgets('§6 после перелётов на экране ровно то, что в плане',
      (WidgetTester tester) async {
    final AppState app = await freshWeek();
    await pumpPlan(tester, app);
    final int available = app.game.snapshot.wallet.unallocated;

    for (int i = 0; i < available; i++) {
      await tester.tap(plus(i.isEven ? 0 : 2));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();

    // Разложено всё: ни одна монетка не потерялась в полёте и ни одна
    // не удвоилась.
    expect(shownLeft(tester), 0);
    expect(shownIn(tester, 0) + shownIn(tester, 1) + shownIn(tester, 2),
        available,
        reason: '🔴 сумма по конвертам обязана сойтись с бюджетом недели');
    expect(find.text('Можно подтверждать.'), findsOneWidget);
  });

  testWidgets('§6 план можно подтвердить, пока монетка ещё в воздухе',
      (WidgetTester tester) async {
    final AppState app = await freshWeek();
    await pumpPlan(tester, app);
    final int available = app.game.snapshot.wallet.unallocated;

    for (int i = 0; i < available; i++) {
      await tester.tap(plus(0));
      await tester.pump(const Duration(milliseconds: 20));
    }
    // 🔴 Подтверждение ровно в тот момент, когда монетки ещё летят:
    // редактор с ними и уезжает. Непогашённый контроллер здесь роняет
    // приложение проверкой самого Flutter — «тикер пережил свой экран».
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();

    expect(app.game.currentPlan?.needs, available,
        reason: 'план ушёл в журнал целиком');
  });

  testWidgets('§3.6.7 без анимаций монетка не летит: число сразу в конверте',
      (WidgetTester tester) async {
    final AppState app = await freshWeek(animations: false);
    await pumpPlan(tester, app);

    await tester.tap(plus(0));
    // Ровно один кадр и ноль игрового времени.
    await tester.pump();

    // 🔴 Это и есть «конечное состояние за один кадр»: с движением на этом
    // же кадре в конверте ноль — монетка ещё в воздухе. Общий признак
    // «что-то движется» здесь не годится: у кнопки Material свой всплеск,
    // и он идёт при любых настройках анимаций.
    expect(shownIn(tester, 0), 1,
        reason: 'без анимаций монетка оказывается в конверте сразу');
    expect(shownLeft(tester), app.game.snapshot.wallet.unallocated - 1,
        reason: 'и счётчик «осталось разложить» сходится с конвертами');
  });

  testWidgets('§3.6.7 системное «уменьшить движение» отменяет и перелёт',
      (WidgetTester tester) async {
    // Флаг в профиле включён — но телефон просит не двигать ничего.
    final AppState app = await freshWeek();
    await pumpPlan(tester, app, systemReducedMotion: true);

    await tester.tap(plus(0));
    await tester.pump();

    expect(app.game.profile.settings.animationsOn, isTrue);
    expect(shownIn(tester, 0), 1,
        reason: '🔴 системную просьбу игра не переспрашивает');
  });

  // ───────────────────── точки показателя ─────────────────────

  testWidgets('§6 точки показателя загораются, а не перерисовываются',
      (WidgetTester tester) async {
    final AppState app = await booted();
    // 🔴 Показатель меняется перестроением, а не нажатием на кнопку:
    // у любой кнопки Material есть собственный всплеск, и он один держал бы
    // `hasRunningAnimations` истинным независимо от нашей анимации.
    await tester.pumpWidget(wrap(app, meterHost(4)));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse,
        reason: '🔴 §6: сама по себе шкала не шевелится');

    await tester.pumpWidget(wrap(app, meterHost(8)));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue,
        reason: 'две новые точки загораются по очереди, а не разом');

    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse,
        reason: '🔴 один проход, а не цикл');
    expect(find.text(Meter.mood.label(8)), findsOneWidget);
  });

  testWidgets('§6 упавший показатель показывается сразу, без затухания',
      (WidgetTester tester) async {
    final AppState app = await booted();
    await tester.pumpWidget(wrap(app, meterHost(8)));
    await tester.pumpAndSettle();

    await tester.pumpWidget(wrap(app, meterHost(2)));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse,
        reason: 'растягивать «стало хуже» на секунду незачем');
  });

  testWidgets('§3.6.7 без анимаций точки показателя на местах сразу',
      (WidgetTester tester) async {
    final AppState app = await booted(animations: false);
    await tester.pumpWidget(wrap(app, meterHost(4)));
    await tester.pumpAndSettle();

    await tester.pumpWidget(wrap(app, meterHost(10)));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse,
        reason: 'без анимаций все точки горят с первого же кадра');
    expect(find.text(Meter.mood.label(10)), findsOneWidget);
  });

  // ───────────────────── Финни подрос ─────────────────────

  testWidgets('§2.5.10 новая стадия — карточка «научился» и рост питомца',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await atStageUp();
    expect(app.game.snapshot.stage, isNot(PetStage.novice),
        reason: 'подготовка теста должна была довести Финни до новой стадии');

    await tester.pumpWidget(wrap(app, const ProgressScreen()));
    await tester.pump();

    expect(find.text('Финни научился!'), findsOneWidget);
    // 🔴 Проба — само значение анимации, а не `hasRunningAnimations`:
    // у кнопок Material есть собственные всплески, и общий признак
    // «что-то движется» проверял бы их, а не рост питомца.
    final Animation<double> grow = grownFinni(tester);
    expect(grow.value, lessThan(1.0), reason: 'Финни начинает меньше себя');

    await tester.pumpAndSettle();
    expect(grow.value, 1.0, reason: 'и приходит ровно к своему размеру');
    expect(find.text('Финни научился!'), findsOneWidget,
        reason: 'карточка остаётся на экране и после движения');
  });

  testWidgets('§2.5.10 стадия забирается один раз: на второй заход роста нет',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await atStageUp();

    await tester.pumpWidget(wrap(app, const ProgressScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Финни научился!'), findsOneWidget);

    // Экран открыли заново — новость уже прочитана, повторять нечего.
    await tester.pumpWidget(wrap(app, const SizedBox.shrink()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(wrap(app, const ProgressScreen()));
    await tester.pump();

    expect(find.text('Финни научился!'), findsNothing);
    expect(tester.hasRunningAnimations, isFalse,
        reason: '🔴 §6: на экране, открытом просто так, не движется ничего');
  });

  testWidgets('§3.6.7 без анимаций Финни сразу нового размера',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await atStageUp();
    await app.updateProfile(app.game.profile
        .copyWith(settings: const GameSettings(animationsOn: false)));

    await tester.pumpWidget(wrap(app, const ProgressScreen()));
    await tester.pump();

    expect(find.text('Финни научился!'), findsOneWidget,
        reason: 'выключённые анимации не отменяют саму новость');
    expect(grownFinni(tester).value, 1.0,
        reason: 'конечный размер — с первого же кадра');
    expect(tester.hasRunningAnimations, isFalse);
  });

  // ───────────────────── цель набрана ─────────────────────

  testWidgets('§2.5.7 последняя монетка: монетки разлетаются один раз',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await oneCoinFromGoal();
    expect(app.game.snapshot.wallet.savings, 19,
        reason: 'подготовка: до цели должна оставаться ровно одна монетка');

    await tester.pumpWidget(wrap(app, const SavingsScreen()));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse,
        reason: '🔴 §6: экран, на который просто пришли, неподвижен');

    await depositOne(tester);

    // Карточка последствия — модальный лист поверх экрана; праздник ждёт,
    // пока её закроют, иначе ребёнок увидит его сквозь затемнение.
    await tester.tap(find.text('Понятно'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.hasRunningAnimations, isTrue,
        reason: 'монетки разлетаются от копилки после закрытия карточки');

    // 🔴 pumpAndSettle сам по себе — проверка «не цикл»: у бесконечной
    // анимации он не дождался бы конца и упал по таймауту.
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('Накоплено 20 из 20'), findsOneWidget,
        reason: 'число на экране равно копилке в модели');
    expect(app.game.snapshot.wallet.savings, 20);
  });

  testWidgets('§6 разлёт монеток не мешает нажать «выбрать другую цель»',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await oneCoinFromGoal();
    await tester.pumpWidget(wrap(app, const SavingsScreen()));
    await tester.pumpAndSettle();

    await depositOne(tester);
    await tester.tap(find.text('Понятно'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Монетки ещё в воздухе — а ребёнок уже жмёт.
    expect(tester.hasRunningAnimations, isTrue);
    await tester.tap(find.text('Выбрать другую цель'));
    await tester.pumpAndSettle();
    expect(find.text('На что копим?'), findsOneWidget,
        reason: '🔴 слой с монетками обязан пропускать касания насквозь');
  });

  testWidgets('§3.6.7 без анимаций цель набирается молча и сразу',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await oneCoinFromGoal(animations: false);

    await tester.pumpWidget(wrap(app, const SavingsScreen()));
    await tester.pumpAndSettle();

    await depositOne(tester);
    await tester.tap(find.text('Понятно'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.hasRunningAnimations, isFalse,
        reason: 'ни разлёта монеток, ни досчёта суммы');
    expect(find.text('Накоплено 20 из 20'), findsOneWidget);
    expect(find.text('Мечта набрана! Её можно исполнить.'), findsOneWidget);
  });

  testWidgets('§6 счётчик копилки досчитывает, но приходит ровно к модели',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();
    app.game.chooseGoal('zoo');
    await app.act((Game g) => g.startPeriod());

    await tester.pumpWidget(wrap(app, const SavingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Накоплено 0 из 20'), findsOneWidget);

    await tester.tap(find.text('Отложить монетки'));
    await tester.pumpAndSettle();
    for (int i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Отложить: больше на одну'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Отложить 5'));
    await tester.pump();

    // Первый кадр после взноса: в копилке уже пять, а число ещё в пути.
    expect(app.game.snapshot.wallet.savings, 5);
    expect(find.text('Накоплено 5 из 20'), findsNothing,
        reason: 'сумма не прыгает, а досчитывает');

    await tester.pumpAndSettle();
    expect(find.text('Накоплено 5 из 20'), findsOneWidget,
        reason: '🔴 досчитав, число обязано совпасть с моделью');
  });

  testWidgets('§3.6.7 без анимаций сумма меняется одним кадром',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted(animations: false);
    app.game.chooseGoal('zoo');
    await app.act((Game g) => g.startPeriod());

    await tester.pumpWidget(wrap(app, const SavingsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Отложить монетки'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Отложить 1'));
    await tester.pump();

    expect(find.text('Накоплено 1 из 20'), findsOneWidget,
        reason: 'без анимаций число на месте с первого кадра');
  });

  // ───────────────────── Финни отвечает ─────────────────────

  testWidgets('§6 Финни кивает в ответ на выбор',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();

    await tester.pumpWidget(wrap(app, const PetCreateScreen()));
    await tester.pumpAndSettle();
    expect(noddingFinni(tester).value, 1.0,
        reason: '🔴 §6: сам по себе питомец неподвижен');

    await tester.tap(find.text('Лисёнок'));
    await tester.pump();
    final Animation<double> nod = noddingFinni(tester);
    expect(nod.value, lessThan(1.0),
        reason: 'выбор — это действие ребёнка, и Финни на него отвечает');

    // Кивок не мешает выбирать дальше: ребёнок тычет, не дожидаясь.
    await tester.tap(find.text('Совёнок'));
    await tester.pumpAndSettle();
    expect(noddingFinni(tester).value, 1.0);
    expect(find.textContaining('Совёнок'), findsWidgets,
        reason: 'второй выбор состоялся');
  });

  testWidgets('§3.6.7 без анимаций Финни не кивает, но меняется',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted(animations: false);

    await tester.pumpWidget(wrap(app, const PetCreateScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Лисёнок'));
    await tester.pump();

    expect(noddingFinni(tester).value, 1.0,
        reason: 'без анимаций питомец сразу в покое');
    expect(find.textContaining('Лисёнок'), findsWidgets,
        reason: 'выбор состоялся: экран остался рабочим');
  });
}
