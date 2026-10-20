import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/city/city_guide.dart' show cityLabelScale;
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/event/event_screen.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/jobs/shift_choice_view.dart';
import 'package:finlit/features/world/onboarding/world_onboarding_screen.dart';
import 'package:finlit/features/world/screen_flags.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:finlit/features/world/tutorial/tutorial_steps.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';

/// Путь ребёнка первым заходом — одним приложением, как на телефоне:
/// знакомство → комната (обучалка, утреннее событие, нижнее меню, золотая
/// кнопка) → доска работ → смена → урок → домой → еда → сон → утро дня 2.
///
/// Защищает: первый заход доходит до второго дня на 360×640 и 640×360 при
/// шрифте 1,0 и 1,3 — без переполнения раскладки и необработанных
/// исключений, и каждое нажатое действие меняет мир (запись в журнале,
/// день, экран), а не только подсветку.
///
/// Уронит: кнопка без действия (onPressed не зовёт движок), кнопка под
/// краем экрана или под меню (не попасть пальцем — `pointOn`), RenderFlex
/// overflow на любом экране пути, урок без доступного варианта, сон без
/// нового утра.
///
/// Почему не ловят другие тесты: каждый экран проверяется своим тестом на
/// заранее собранном мире; здесь — один мир, прошедший знакомство на
/// экране, и экраны в том порядке, в каком их видит ребёнок (обучалка
/// поверх комнаты есть только на маршруте `/w/room`).
void main() {
  setUpAll(loadAppFonts);

  late TutorialLook savedLook;
  late bool savedLabels;
  setUp(() {
    // rootBundle кеширует Future из зоны первого теста: без сброса арт
    // комнаты во втором тесте файла не грузится (нет кровати, двери).
    rootBundle.clear();
    savedLook = tutorialLook;
    savedLabels = cityLabelScale;
    // Флаги экранов — как в сборке (`main.dart`): обучалка включена.
    applyContentScreenFlags(shippedDayContent.economy);
  });
  tearDown(() {
    tutorialLook = savedLook;
    cityLabelScale = savedLabels;
  });

  for (final MapEntry<String, Size> size in <String, Size>{
    '360×640': portrait,
    '640×360': landscape,
  }.entries) {
    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets('путь ребёнка до дня 2: ${size.key}, шрифт $scale',
          (WidgetTester tester) async {
        await _childPath(tester, size.value, scale);
      });
    }
  }
}

Future<void> _childPath(WidgetTester tester, Size size, double scale) async {
  final WorldGame w = contentDayWorld();
  final WorldState ws = await pumpWorldScreen(
      tester, const WorldOnboardingScreen(),
      world: w, size: size, textScale: scale, games: contentJobGamesDogStub);

  // 1. Знакомство: ник, облик, сценки, план, цель → комната.
  await _register(tester);
  _clean(tester, 'регистрация');
  expect(w.phase, WeekPhase.planning);
  await _talkToPlan(tester);
  await _fillNeeds(tester);
  await _confirmPlan(tester);
  expect(w.phase, WeekPhase.living, reason: 'план принят — неделя идёт');
  final Finder goal = find.byKey(const ValueKey<String>('goal:pet_fish'));
  await _tapReal(tester, goal);
  await _settle(tester);
  expect(w.snapshot.activeGoalId, 'pet_fish');
  for (int i = 0;
      i < 10 && find.byType(WorldOnboardingScreen).evaluate().isNotEmpty;
      i++) {
    await _tapReal(tester, _next);
    await _settle(tester);
  }
  await _loadRoom(tester);
  expect(find.byType(RoomScreen), findsOneWidget,
      reason: 'после знакомства — комната');
  _clean(tester, 'знакомство → комната');
  expect(w.snapshot.dayInWeek, 1);

  // 2. Второго знакомства в комнате нет (Денис 20.10: «надо старый
  // убрать», флаг сборки tutorial_ui выключен) — сразу игра.
  expect(find.byKey(const ValueKey<String>('tutorial:next')), findsNothing,
      reason: 'одно знакомство: обучалка в комнате не повторяет его');

  // 3. Утреннее событие дня 1: доступный вариант → итог → «Дальше».
  final Finder badge = find.byKey(const ValueKey<String>('room:event'));
  expect(badge, findsOneWidget, reason: 'утро дня 1 — событие ждёт');
  {
    await _tapReal(tester, badge);
    await _frames(tester);
    expect(find.byType(EventScreen), findsOneWidget);
    _clean(tester, 'событие');
    final int before = w.journal.length;
    await _tapReal(tester, _firstEnabled(tester, 'event:choice:', 'событие'));
    await _frames(tester);
    expect(w.journal.length, greaterThan(before),
        reason: 'выбор в событии записан в журнал');
    _clean(tester, 'итог события');
    await _tapReal(tester, find.byKey(const ValueKey<String>('event:done')));
    await _frames(tester);
    expect(find.byType(EventScreen), findsNothing);
    _clean(tester, 'событие → комната');
  }

  // 3а. Первый выход в город — подсказки облачком Финни (Денис 20.10):
  // каждое «Дальше» меняет подсказку, «Понятно» закрывает, второй раз их
  // нет.
  {
    await _tapReal(tester, find.byKey(const ValueKey<String>('room:nav:city')));
    await _frames(tester);
    expect(find.byType(CityScreen), findsOneWidget);
    final Finder introNext =
        find.byKey(const ValueKey<String>('city:intro:next'));
    expect(introNext, findsOneWidget, reason: 'подсказки первого выхода');
    int beats = 0;
    for (; beats < 6 && introNext.evaluate().isNotEmpty; beats++) {
      await _tapReal(tester, introNext);
      await _frames(tester);
      _clean(tester, 'подсказка города ${beats + 1}');
    }
    expect(introNext, findsNothing, reason: '«Понятно» закрыло подсказки');
    expect(beats, contentScript.cityIntro.length);
    expect(w.seen('city.intro'), isTrue);
    _navigator(tester).pop();
    await _frames(tester);
  }

  // 4. Нижнее меню и золотая кнопка: каждая открывает свой экран.
  await _opens(tester, 'room:nav:city', find.byType(CityScreen));
  await _opens(tester, 'room:nav:progress', find.byType(HistoryScreen));
  await _opens(tester, 'room:nav:week',
      find.byKey(const ValueKey<String>('room:week:plan')));
  await _opens(tester, 'room:nav:more',
      find.byKey(const ValueKey<String>('room:settings')));
  final Finder now = find.byKey(const ValueKey<String>('room:now'));
  // Денег на счета хватает — главный шаг «В город».
  await _opens(tester, 'room:now', find.byType(CityScreen));
  expect(now, findsOneWidget);

  // 5. Первая смена: доска → «Взяться» → смена → итог → урок → домой.
  // Выгульщик без собаки (демо «Открыть все профессии») — смена одной
  // кнопкой; мини-игры работ дня 1 играют job_games_b7_test и
  // job_play_screen_test, здесь они не пройдены.
  ok(w.demoUnlockAllJobs());
  await _tapRoomObject(tester, 'room:desk'); // стол — доска работ
  expect(find.byType(JobBoardScreen), findsOneWidget);
  _clean(tester, 'доска работ');
  await _tapReal(
      tester, find.byKey(const ValueKey<String>('jobs:take:dog_walker')));
  await _frames(tester);
  expect(find.byType(JobPlayScreen), findsOneWidget);
  _clean(tester, 'карточка смены');
  // Флаг сборки shift_choices_ui: смена начинается ответом на вопрос.
  expect(find.byType(ShiftChoiceButton), findsWidgets,
      reason: 'вопрос перед сменой');
  await _tapReal(tester, _firstEnabled(tester, 'job:choice:', 'вопрос смены'));
  await _frames(tester);
  _clean(tester, 'смена началась');
  final int beforeShift = w.journal.length;
  final int coins = _coins(w);
  await _tapReal(
      tester, find.byKey(const ValueKey<String>('game:placeholder:do')));
  await _frames(tester);
  final WorldEntry pay = w.journal.skip(beforeShift).lastWhere(
      (WorldEntry e) => e.kind == WorldLedgerKind.jobPayout,
      orElse: () => fail('после «Сделать» нет jobPayout в журнале'));
  expect(_coins(w), greaterThan(coins), reason: 'оплата смены пришла: $pay');
  expect(find.byKey(const ValueKey<String>('job:result')), findsOneWidget);
  _clean(tester, 'итог смены');
  expect(w.pendingLesson, isNotNull, reason: 'после смены — урок');
  {
    final int beforeLesson = w.journal.length;
    await _tapReal(tester, _firstEnabled(tester, 'lesson:', 'урок'));
    await _frames(tester);
    expect(w.pendingLesson, isNull, reason: 'урок решён');
    expect(w.journal.length, greaterThan(beforeLesson));
    expect(find.byKey(const ValueKey<String>('lesson:result')), findsOneWidget);
    _clean(tester, 'урок');
  }
  await _tapReal(tester, find.byKey(const ValueKey<String>('job:toRoom')));
  await _frames(tester);
  expect(find.byType(JobPlayScreen), findsNothing);
  expect(find.byType(RoomScreen), findsOneWidget);
  _clean(tester, 'смена → комната');

  // 6. Еда: магазин, вкладка «Еда» → «Съесть» → «Да».
  await _tapRoomObject(tester, 'room:fridge'); // холодильник — магазин
  expect(find.byType(WorldShopScreen), findsOneWidget);
  _clean(tester, 'магазин');
  final int beforeMeal = w.journal.length;
  await _tapReal(tester, _firstEnabled(tester, 'eat:', 'еда'));
  await _frames(tester);
  final Finder yes = find.byKey(const ValueKey<String>('confirm:yes'));
  expect(yes, findsOneWidget, reason: '«Съесть» спрашивает подтверждение');
  expect(w.journal.length, beforeMeal, reason: 'до «Да» ничего не съедено');
  _clean(tester, 'диалог еды');
  await _tapReal(tester, yes);
  await _frames(tester);
  expect(
      w.journal
          .skip(beforeMeal)
          .any((WorldEntry e) => e.kind == WorldLedgerKind.mealEaten),
      isTrue,
      reason: '«Съесть» записало mealEaten');
  _clean(tester, 'после еды');
  await _tapReal(tester, find.byKey(const ValueKey<String>('shop:back')));
  await _frames(tester);
  expect(find.byType(WorldShopScreen), findsNothing);

  // 7. Сон: кровать в комнате → «Лечь спать?» → «Спать» → утро дня 2.
  await _tapRoomObject(tester, 'room:bed');
  final Finder sleep = find.byKey(const ValueKey<String>('sleep:confirm'));
  expect(sleep, findsOneWidget, reason: 'кровать спрашивает «Лечь спать?»');
  _clean(tester, 'диалог сна');
  await _tapReal(tester, sleep);
  await _frames(tester);
  await _frames(tester);
  expect(w.phase, WeekPhase.living);
  expect(w.snapshot.dayInWeek, 2, reason: 'наступило утро дня 2');
  expect(find.byType(RoomScreen), findsOneWidget);
  _clean(tester, 'утро дня 2');
  expect(ws.snapshot.dayInWeek, 2);
}

// ───────────────────────────── помощники ─────────────────────────────

final Finder _next = find.byKey(const ValueKey<String>('onboarding-next'));
final Finder _planPlus = find.byKey(const ValueKey<String>('plus:need'));

/// Ни переполнения раскладки, ни необработанного исключения после шага.
void _clean(WidgetTester tester, String step) {
  expect(tester.takeException(), isNull, reason: 'исключение на шаге «$step»');
}

/// Касание туда, где палец попадает именно в [f] — не в меню, HUD или
/// затемнение над ним. Не попасть — красный (`pointOn`).
Future<void> _tapReal(WidgetTester tester, Finder f) async {
  expect(f, findsOneWidget, reason: '$f');
  await tester.ensureVisible(f);
  await tester.pump();
  final Key? k = tester.widget(f).key;
  if (k is ValueKey<String>) {
    await tester.tapAt(pointOn(tester, k.value));
  } else {
    await tester.tap(f);
  }
  await tester.pump();
}

/// Первая доступная кнопка с ключом на [prefix]; ни одной — красный.
Finder _firstEnabled(WidgetTester tester, String prefix, String what) {
  final List<Element> all = find
      .byWidgetPredicate((Widget x) =>
          (x is ButtonStyleButton || x is ShiftChoiceButton) &&
          x.key is ValueKey<String> &&
          (x.key! as ValueKey<String>).value.startsWith(prefix))
      .evaluate()
      .toList();
  expect(all, isNotEmpty, reason: '$what: кнопок «$prefix…» нет');
  for (final Element e in all) {
    final Widget b = e.widget;
    final VoidCallback? press = b is ButtonStyleButton
        ? b.onPressed
        : (b as ShiftChoiceButton).onPressed;
    if (press != null) return find.byKey(b.key!);
  }
  fail('$what: все варианты погашены '
      '(${all.map((Element e) => (e.widget.key! as ValueKey<String>).value).join(', ')})');
}

/// Кнопка комнаты [key] открывает [target]; затем назад в комнату.
Future<void> _opens(WidgetTester tester, String key, Finder target) async {
  expect(target, findsNothing, reason: '$key: экран ещё не открыт');
  await _tapReal(tester, find.byKey(ValueKey<String>(key)));
  await _frames(tester);
  expect(target, findsWidgets, reason: '$key: касание ничего не открыло');
  _clean(tester, key);
  _navigator(tester).pop();
  await _frames(tester);
  expect(target, findsNothing, reason: '$key: назад в комнату');
  _clean(tester, '$key → назад');
}

/// Предмет комнаты: камера подводит к нему, касание по нему, Финни идёт
/// к предмету (`_walkThen`), затем — действие предмета.
Future<void> _tapRoomObject(WidgetTester tester, String key) async {
  await bringIntoReach(tester, key);
  await tester.tapAt(pointOn(tester, key));
  await _frames(tester);
  await tester.pump(const Duration(seconds: 2)); // Финни идёт к предмету
  await _frames(tester);
}

NavigatorState _navigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator).first);

int _coins(World w) => w.snapshot.need + w.snapshot.want + w.snapshot.free;

/// Комната грузит картинки и реестр ассетов настоящим вводом-выводом.
Future<void> _loadRoom(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await _frames(tester);
}

/// Кадры перехода (Финни дышит без конца — не pumpAndSettle).
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _register(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const ValueKey<String>('onboarding-nick')), 'Звёздочка');
  await tester.pump();
  // Облик — на первом экране, рядом с ником (Денис 20.10 13:46).
  await _tapReal(tester, find.byKey(const ValueKey<String>('look:finni-a2:3')));
  await _tapReal(tester, _next);
  await _settle(tester);
  await _tapReal(tester, find.byKey(const ValueKey<String>('gender:girl')));
  await tester.enterText(
      find.byKey(const ValueKey<String>('onboarding-finni-name')), 'Бублик');
  await tester.pump();
  await _tapReal(tester, _next);
  await _settle(tester);
}

Future<void> _talkToPlan(WidgetTester tester) async {
  for (int i = 0; i < 40 && _planPlus.evaluate().isEmpty; i++) {
    await _tapReal(tester, _next);
    await _settle(tester);
    _clean(tester, 'сценка ${i + 1}');
  }
  expect(_planPlus, findsOneWidget, reason: 'сценки дошли до плана');
}

Future<void> _fillNeeds(WidgetTester tester) async {
  await tester.ensureVisible(_planPlus);
  for (int i = 0;
      i < 200 &&
          find.byKey(const ValueKey<String>('plan:full')).evaluate().isEmpty;
      i++) {
    await tester.tap(_planPlus);
    await tester.pump();
  }
  await _settle(tester);
  _clean(tester, 'план');
}

Future<void> _confirmPlan(WidgetTester tester) async {
  await _tapReal(tester, _next);
  await _settle(tester);
  final Finder keep = find.byKey(const ValueKey<String>('confirm:yes'));
  if (keep.evaluate().isNotEmpty) {
    await _tapReal(tester, keep);
    await _settle(tester);
  }
}
