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

import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/core/widgets.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/features/home/home_screen.dart';
import 'package:finlit/routes.dart';
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

/// Приложение целиком, но со стартом сразу на главном экране.
///
/// Профиль — в памяти, а не на диске: замер не должен зависеть от того, что
/// осталось на устройстве от предыдущего прогона.
Widget _harness(AppState app) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        title: 'Финни',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const HomeScreen(),
        // 🔴 Не `routes: appRoutes` с `initialRoute`. В той сборке под главным
        // экраном оказывается ещё и BootScreen с маршрута «/», его
        // pushReplacementNamed срабатывает посреди замера и уводит тест на
        // онбординг. Здесь маршруты те же, но стартовый ровно один.
        onGenerateRoute: (RouteSettings settings) {
          final WidgetBuilder? builder = appRoutes[settings.name];
          if (builder == null) return null;
          return MaterialPageRoute<void>(builder: builder, settings: settings);
        },
      ),
    );

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 🔴 rootBundle кеширует Future из зоны предыдущего теста: без этой строки
  // второй boot() виснет навсегда и без вывода.
  setUp(rootBundle.clear);

  testWidgets('§3.4 отклик интерфейса: p90 кадра и время до отклика',
      (WidgetTester tester) async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await app.act((Game g) => g.startPeriod());
    app.game.chooseGoal('zoo');

    await tester.pumpWidget(_harness(app));
    await tester.pumpAndSettle();

    // Отклик на отдельные действия меряется вне трассировки: здесь важны
    // не кадры, а настенное время от касания до появления нового экрана.
    final Map<String, int> responses = <String, int>{};

    Future<void> measure(String name, Finder tap) async {
      final Stopwatch sw = Stopwatch()..start();
      await tester.tap(tap);
      await tester.pumpAndSettle();
      sw.stop();
      responses[name] = sw.elapsedMilliseconds;
    }

    // Переход на каждый раздел, доступный с главного (§2.5.3.2), и обратно.
    for (final String section in <String>[
      'План',
      'Покупки',
      'Задания',
      'Копилка',
      'Прогресс',
      'Словарик',
    ]) {
      await tester.scrollUntilVisible(
          find.widgetWithText(SectionTile, section), 200,
          scrollable: find.byType(Scrollable).first);
      await measure(
          'открыть «$section»', find.widgetWithText(SectionTile, section));
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    // Та же дорога ещё раз, но уже под трассировкой: прокрутка главного
    // экрана и переходы — это все кадры, которые ребёнок видит в цикле.
    //
    // 🔴 Порог по кадрам проверяет драйвер (test_driver/perf_driver.dart):
    // сводку считает flutter_driver, а он живёт на хосте, не на устройстве.
    await binding.traceAction(
      () async {
        for (int i = 0; i < 3; i++) {
          await tester.fling(
              find.byType(ListView).first, const Offset(0, -400), 2000);
          await tester.pumpAndSettle();
          await tester.fling(
              find.byType(ListView).first, const Offset(0, 400), 2000);
          await tester.pumpAndSettle();
        }
        for (final String section in <String>['План', 'Покупки', 'Прогресс']) {
          await tester.scrollUntilVisible(
              find.widgetWithText(SectionTile, section), 200,
              scrollable: find.byType(Scrollable).first);
          await tester.tap(find.widgetWithText(SectionTile, section));
          await tester.pumpAndSettle();
          await tester.pageBack();
          await tester.pumpAndSettle();
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
