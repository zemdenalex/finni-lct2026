import 'package:finlit/app.dart';
import 'package:finlit/app_state.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/home/home_screen.dart';
import 'package:finlit/features/onboarding/onboarding_screen.dart';
import 'package:finlit/features/world/adult/world_adult_screen.dart';
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
  setUp(rootBundle.clear);

  testWidgets('знакомство не пройдено → заставка ведёт в S0 нового мира',
      (WidgetTester tester) async {
    await _launch(tester, const OnboardingProgress());
    expect(find.byType(BootScreen), findsNothing);
    expect(find.byType(WorldOnboardingScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
  });

  // Ловит ещё: раздел взрослого (ТЗ 2.5.12, а через него режим проверки
  // 2.5.13.2) недостижим из нового мира — раньше в него вела только
  // старая игра.
  testWidgets('знакомство пройдено → комната; 🔒 ведёт к барьеру взрослого',
      (WidgetTester tester) async {
    await _launch(
        tester,
        const OnboardingProgress(
            step: OnboardingProgress.stepDone, nickname: 'Кот'));
    expect(find.byType(BootScreen), findsNothing);
    expect(find.byType(RoomScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('room:adult')));
    await _step(tester);
    expect(find.byType(WorldAdultScreen), findsOneWidget);
    expect(find.byKey(WorldAdultScreen.questionKey), findsOneWidget,
        reason: 'раздел открывается барьером, а не сразу');
  });
}
