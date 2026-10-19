import 'package:finlit/app.dart';
import 'package:finlit/app_state.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/adult/world_adult_screen.dart';
import 'package:finlit/features/world/demo/world_checklist.dart';
import 'package:finlit/features/world/demo/world_demo_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/onboarding/world_onboarding_screen.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/world_harness.dart';

/// Спрайты анимируются бесконечно — pumpAndSettle не дождётся покоя.
Future<void> _step(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Верный ответ на пример барьера «для взрослого».
Future<void> _solve(WidgetTester tester) async {
  final String q =
      tester.widget<Text>(find.byKey(WorldAdultScreen.questionKey)).data!;
  await tester.enterText(find.byKey(WorldAdultScreen.answerKey),
      '${WorldAdultScreen.answerOf(q)}');
  final Finder enter = find.byKey(const ValueKey<String>('adult:enter'));
  await tester.ensureVisible(enter);
  await tester.pump();
  await tester.tap(enter);
  await _step(tester);
  await _step(tester);
}

/// Приложение целиком, как его собирает `main.dart`, — с заставки.
/// Заставка читает старый профиль из бандла, поэтому ждём по-настоящему.
Future<void> _launch(WidgetTester tester, OnboardingProgress onboarding) async {
  tester.view.physicalSize = portrait;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final AppState app = AppState(MemoryStorage());
  await tester.pumpWidget(MultiProvider(
    providers: <ChangeNotifierProvider<ChangeNotifier>>[
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider<WorldState>(
          create: (_) => WorldState(contentWorld(onboarding: onboarding))),
    ],
    child: const FinniApp(),
  ));
  // Чтение бандла — настоящий ввод-вывод: даём ему время вне фейковых
  // часов, а продолжение крутим кадрами.
  for (int i = 0; i < 40; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
  expect(app.ready, isTrue, reason: 'заставка не дочитала старый профиль');
  // Переход со сменой маршрута — анимация, дальше арт экрана из бандла.
  for (int i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Ловит: заставка ведёт в старую игру (конкурсная сдача — новый мир), или
/// ребёнок, прошедший знакомство, после перезапуска снова попадает в него.
void main() {
  // rootBundle кеширует Future из зоны прошлого теста — второй boot() висел
  // бы (см. app_smoke_test).
  setUp(() {
    rootBundle.clear();
    WorldDemoSession.clear();
  });

  testWidgets('знакомство не пройдено → заставка ведёт в S0 нового мира',
      (WidgetTester tester) async {
    await _launch(tester, const OnboardingProgress());
    expect(find.byType(BootScreen), findsNothing);
    expect(find.byType(WorldOnboardingScreen), findsOneWidget);
  });

  // Ловит ещё: режим проверки (ТЗ 2.5.13.2) недостижим из нового мира —
  // раньше в него вела только старая игра. С 18.10 (DEN-27, `adult.section`
  // false) путь — ⋮ → «Настройки» → «Режим проверки», за тем же барьером.
  testWidgets('знакомство пройдено → комната; режим проверки — за барьером',
      (WidgetTester tester) async {
    await _launch(
        tester,
        const OnboardingProgress(
            step: OnboardingProgress.stepDone, nickname: 'Кот'));
    expect(find.byType(BootScreen), findsNothing);
    expect(find.byType(RoomScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('room:menu')));
    await _step(tester);
    expect(find.byKey(const ValueKey<String>('room:adult')), findsNothing,
        reason: 'раздела «Взрослым» в сборке нет (DEN-27)');
    await tester.tap(find.byKey(const ValueKey<String>('room:settings')));
    await _step(tester);
    await _step(tester);
    final Finder demo = find.byKey(const ValueKey<String>('settings:demo'));
    await tester.scrollUntilVisible(demo, 200,
        scrollable: find.byType(Scrollable).last);
    // scrollUntilVisible сдвигает список (ensureVisible), но кадр не
    // перестраивает: без pump касание идёт в старую точку — с нижним меню
    // она под меню, а не на кнопке.
    await tester.pump();
    await tester.tap(demo);
    await _step(tester);
    await _step(tester);
    expect(find.byType(WorldAdultScreen), findsOneWidget);
    expect(find.byKey(WorldAdultScreen.questionKey), findsOneWidget,
        reason: 'раздел открывается барьером, а не сразу');
  });

  // Ловит: S14 «Взрослым» в сборке без раздела (DEN-27) стал недостижим —
  // путь «Ещё → Настройки → Режим проверки → Экраны → S14» не проходил ни
  // один тест; или чек-лист «Проверки» отмечает «Раздел взрослого открыт»
  // уже за барьером режима проверки, а после настоящего S14 — не обновляется.
  testWidgets(
      'путь до S14: ⋮ → Настройки → Режим проверки → Экраны → S14 · '
      'Взрослым; чек-лист отмечает раздел только после S14',
      (WidgetTester tester) async {
    await _launch(
        tester,
        const OnboardingProgress(
            step: OnboardingProgress.stepDone, nickname: 'Кот'));
    expect(find.byType(RoomScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('room:menu')));
    await _step(tester);
    await tester.tap(find.byKey(const ValueKey<String>('room:settings')));
    await _step(tester);
    await _step(tester);
    final Finder demo = find.byKey(const ValueKey<String>('settings:demo'));
    await tester.scrollUntilVisible(demo, 200,
        scrollable: find.byType(Scrollable).last);
    // scrollUntilVisible сдвигает список (ensureVisible), но кадр не
    // перестраивает: без pump касание идёт в старую точку — с нижним меню
    // она под меню, а не на кнопке.
    await tester.pump();
    await tester.tap(demo);
    await _step(tester);
    await _step(tester);
    await _solve(tester);
    expect(find.byType(WorldDemoScreen), findsOneWidget);

    final Finder list = find.descendant(
        of: find.byKey(const ValueKey<String>('demo:list')),
        matching: find.byType(Scrollable));
    final Finder notYet = find.text('– Раздел взрослого открыт');
    final Finder done = find.text('✓ Раздел взрослого открыт');
    await tester.scrollUntilVisible(notYet, 300, scrollable: list.first);
    expect(notYet, findsOneWidget,
        reason: 'пройден барьер режима проверки, S14 ещё не открывали');
    expect(WorldDemoSession.adultOpened, isFalse);

    // «Экраны» → «S14 · Взрослым»: свой пример на входе, затем раздел.
    final Finder s14 = find.byKey(const ValueKey<String>('demo:go:/w/adult'));
    await tester.scrollUntilVisible(s14, -300, scrollable: list.first);
    await tester.tap(s14);
    await _step(tester);
    await _step(tester);
    expect(find.byType(WorldAdultScreen), findsOneWidget);
    expect(find.text('Взрослым'), findsOneWidget);
    expect(find.byKey(WorldAdultScreen.questionKey), findsOneWidget);
    await _solve(tester);
    expect(find.byKey(const ValueKey<String>('adult:list')), findsOneWidget,
        reason: 'открыт сам раздел S14');
    expect(WorldDemoSession.adultOpened, isTrue);

    // Назад — в «Проверку»: пункт отмечен.
    await tester.tap(find.byKey(const ValueKey<String>('adult:back')));
    await _step(tester);
    await _step(tester);
    expect(find.byType(WorldDemoScreen), findsOneWidget);
    await tester.scrollUntilVisible(done, 300, scrollable: list.first);
    expect(done, findsOneWidget);
  });
}
