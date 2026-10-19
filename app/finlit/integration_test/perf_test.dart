// Замер отклика интерфейса на устройстве (§3.4, пятый пункт: «локальные
// действия пользователя получают визуальный отклик не более чем за 1 секунду»).
//
// Почему именно integration_test, а не виджет-тест: виджет-тест считает кадры
// на хостовой машине без растеризации — там не бывает ни джанка, ни работы
// GPU. Требование ТЗ про отклик выполняется или нарушается на устройстве,
// значит и мерить нужно там.
//
// 🔴 Гейт стоит на p90, а не на среднем. Среднее прячет ровно те рывки, ради
// которых замер и делается: экран, где 89 кадров по 2 мс и 11 кадров по 40 мс,
// имеет среднее 6 мс и выглядит дёргано.
//
// Запуск (эмулятор или телефон должен быть подключён):
//   cd app/finlit
//   flutter drive \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/perf_test.dart \
//     --profile
//
// 🔴 Только `--profile`. В debug каждый кадр идёт через JIT и цифры завышены
// в несколько раз — такой замер в документацию ставить нельзя.

import 'package:finlit/app.dart';
import 'package:finlit/app_state.dart';
import 'package:finlit/data/onboarding_store.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_save.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/adult/world_adult_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/jobs/job_games.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/settings/world_settings_screen.dart';
import 'package:finlit/features/world/world_explain.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

/// Порог для p90 времени сборки и растеризации кадра, мс.
///
/// 16.7 мс — это граница «кадр не пропущен» при 60 Гц. Половина этого бюджета
/// берётся как рабочий порог: при 8 мс остаётся запас на устройство слабее
/// тестового, а ТЗ проверяют на телефоне жюри, а не на нашем.
const double kFrameBudgetMs = 8.0;

/// Порог отклика на локальное действие, мс (§3.4: «не более чем за 1 секунду»).
const int kResponseBudgetMs = 1000;

/// Приложение целиком, как его собирает `main.dart`: контент из бандла,
/// знакомство уже пройдено — старт в комнате (S1).
///
/// Хранилище — в памяти, а не на диске: замер не должен зависеть от того, что
/// осталось на устройстве от предыдущего прогона.
Future<Widget> _app() async {
  final MemoryStorage storage = MemoryStorage();
  await storage.write(
      onboardingStorageKey,
      const OnboardingProgress(
              step: OnboardingProgress.stepDone, nickname: 'Замер')
          .toJson());
  final SavedWorld saved =
      await openSavedWorld(read: rootBundle.loadString, storage: storage);
  final OnboardingScript script =
      await OnboardingScript.load(rootBundle.loadString);
  final WorldExplain explain = await WorldExplain.load(rootBundle.loadString,
      dayCycle: saved.content.economy.dayCycle);
  return Provider<JobGames>.value(
    value: JobGames.fromData(saved.content.jobData,
        university: saved.content.university),
    child: Provider<OnboardingScript>.value(
      value: script,
      child: Provider<WorldExplain>.value(
        value: explain,
        child: MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<AppState>(
                create: (_) => AppState(MemoryStorage())),
            ChangeNotifierProvider<WorldState>(
                create: (_) => WorldState(saved.world)),
          ],
          child: const FinniApp(),
        ),
      ),
    ),
  );
}

/// Спрайты комнаты анимируются бесконечно — `pumpAndSettle` не дождётся
/// покоя. Ждём кадрами, пока не сбудется [done], но не дольше [limit].
Future<void> _until(WidgetTester tester, bool Function() done,
    {Duration limit = const Duration(seconds: 3)}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (!done() && sw.elapsed < limit) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 🔴 rootBundle кеширует Future из зоны предыдущего теста: без этой строки
  // второй запуск виснет навсегда и без вывода.
  setUp(rootBundle.clear);

  testWidgets('§3.4 отклик интерфейса: p90 кадра и время до отклика',
      (WidgetTester tester) async {
    await tester.pumpWidget(await _app());
    await _until(tester, () => find.byType(RoomScreen).evaluate().isNotEmpty,
        limit: const Duration(seconds: 10));
    expect(find.byType(RoomScreen), findsOneWidget,
        reason: 'старт не дошёл до комнаты');

    // Отклик меряется вне трассировки: здесь важны не кадры, а настенное
    // время от касания до появления нового маршрута поверх комнаты.
    /// Открыть [key] (если задан [via] — сначала меню [via], не в счёт),
    /// дождаться, пока появится [shows], и закрыть всё до комнаты. Возвращает
    /// мс от касания до появления.
    Future<int> open(String key, Finder shows, {String? via}) async {
      if (via != null) {
        await tester.tap(find.byKey(ValueKey<String>(via)));
        await _until(tester,
            () => find.byKey(ValueKey<String>(key)).evaluate().isNotEmpty);
        await _until(tester, () => false,
            limit: const Duration(milliseconds: 400)); // меню доехало
      }
      final Stopwatch sw = Stopwatch()..start();
      await tester.tap(find.byKey(ValueKey<String>(key)));
      await _until(tester, () => shows.evaluate().isNotEmpty);
      sw.stop();
      expect(shows, findsWidgets, reason: '«$key» ничего не открыл');
      // Закрыть открытое (лист меню или страницу) и дождаться комнаты.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await _until(tester, () => shows.evaluate().isEmpty);
      await _until(tester, () => false,
          limit: const Duration(milliseconds: 300));
      return sw.elapsedMilliseconds;
    }

    final Finder menu = find.byKey(const ValueKey<String>('room:settings'));
    final Finder settings = find.byType(WorldSettingsScreen);
    final Finder adult = find.byType(WorldAdultScreen);

    // Меню комнаты и два раздела за ним (настройки, барьер взрослого) —
    // те же пути, что проверяет app_boot_test.
    final Map<String, int> responses = <String, int>{
      'меню': await open('room:menu', menu),
      'настройки': await open('room:settings', settings, via: 'room:menu'),
      'взрослым': await open('room:adult', adult, via: 'room:menu'),
    };

    // Те же касания ещё раз, но уже под трассировкой: это кадры, которые
    // ребёнок видит в цикле недели.
    //
    // 🔴 Порог по кадрам проверяет драйвер (test_driver/perf_driver.dart):
    // сводку считает flutter_driver, а он живёт на хосте, не на устройстве.
    await binding.traceAction(
      () async {
        for (int i = 0; i < 3; i++) {
          await open('room:menu', menu);
          await open('room:settings', settings, via: 'room:menu');
          await open('room:adult', adult, via: 'room:menu');
        }
      },
      reportKey: 'perf_timeline',
    );

    binding.reportData = <String, dynamic>{
      ...?binding.reportData,
      'response_ms': responses,
      'budget': <String, num>{
        'frame_p90_ms': kFrameBudgetMs,
        'response_ms': kResponseBudgetMs,
      },
    };

    // Время отклика проверяется прямо здесь: это настенные миллисекунды,
    // для них не нужна ни трассировка, ни хост.
    final int worstResponse =
        responses.values.reduce((int a, int b) => a > b ? a : b);
    debugPrint('PERF отклик, мс: $responses');
    expect(worstResponse, lessThanOrEqualTo(kResponseBudgetMs),
        reason: '§3.4: визуальный отклик на локальное действие — до 1 секунды');
  });
}
