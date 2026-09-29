import 'package:finlit/app.dart';
import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/features/adult/adult_screen.dart';
import 'package:finlit/features/demo/demo_screen.dart';
import 'package:finlit/features/glossary/glossary_screen.dart';
import 'package:finlit/features/onboarding/onboarding_screen.dart';
import 'package:finlit/features/pet/pet_create_screen.dart';
import 'package:finlit/features/progress/progress_screen.dart';
import 'package:finlit/features/savings/savings_screen.dart';
import 'package:finlit/features/settings/settings_screen.dart';
import 'package:finlit/features/tasks/tasks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../tool/test_fonts.dart';

/// Доступность на **остальных** экранах.
///
/// `test/a11y_test.dart` покрывает три экрана обязательного сценария и честно
/// пишет, что это осознанная граница. Здесь — всё прочее, потому что граница
/// стоила дорого: за один день машинные проверки на новых экранах дважды
/// поймали переполнение Row на 360 dp, которого не видел ни один из
/// полутора сотен остальных тестов. Text переносит слова, а не переполняется,
/// поэтому такие дефекты не падают сами.
Future<AppState> _state() async {
  final AppState app = AppState(MemoryStorage());
  await app.boot();
  await app.act((Game g) => g.startPeriod());
  app.game.chooseGoal('zoo');
  await app.act((Game g) => g.confirmPlan(
      Allocation(needs: 4, wants: 3, savings: g.snapshot.wallet.unallocated - 7)));
  // Немного истории, чтобы экраны не были пустыми: пустой экран проходит
  // любые проверки и ничего не доказывает.
  final CatalogItem need =
      app.content.catalog.firstWhere((CatalogItem i) => i.isNeed);
  await app.act((Game g) => g.buy(need));
  await app.act((Game g) => g.completeTask(app.content.tasks.first, best: true));
  await app.act((Game g) =>
      g.allocate(Envelope.savings, g.snapshot.wallet.unallocated));
  return app;
}

Widget _wrap(AppState app, Widget child) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: child,
        onGenerateRoute: (RouteSettings s) => MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

/// 🔴 Телефон шириной 360 dp — нижняя граница из §3.1.2, и именно на ней
/// вёрстка ломается. Проверять на ширине по умолчанию (800) бессмысленно:
/// там помещается всё.
Future<void> _check(WidgetTester tester, Widget screen,
    {double textScale = 1.0}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final AppState app = await _state();
  final SemanticsHandle handle = tester.ensureSemantics();
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: _wrap(app, screen),
  ));
  await tester.pump(const Duration(milliseconds: 400));

  // 🔴 Сначала — что экран вообще отрисовался. Пустой экран проходит все три
  // проверки ниже и не доказывает ничего: ровно так и выглядит ложная зелёная
  // отметка, которых аудит 17.09 нашёл в этом проекте четыре штуки.
  final Iterable<String> texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((Text t) => t.data ?? '')
      .where((String t) => t.trim().isNotEmpty);
  expect(texts.length, greaterThanOrEqualTo(3),
      reason: 'экран почти пуст — проверять на нём нечего');
  expect(tester.takeException(), isNull,
      reason: 'экран отрисовался с исключением');

  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

void main() {
  // Настоящие Onest и Unbounded, а не подстановочный Ahem: у Ahem каждая
  // буква — квадрат в кегль, и на увеличенном шрифте тест проверял вёрстку
  // строк в полтора раза длиннее тех, что увидит ребёнок.
  setUpAll(loadAppFonts);
  // 🔴 rootBundle кеширует Future из зоны предыдущего теста: без сброса
  // второй boot() в файле виснет навсегда и без вывода.
  setUp(rootBundle.clear);

  final Map<String, Widget Function()> screens = <String, Widget Function()>{
    'знакомство': () => const OnboardingScreen(),
    'создание питомца': () => const PetCreateScreen(),
    'копилка': () => const SavingsScreen(),
    'задания': () => const TasksScreen(),
    'прогресс': () => const ProgressScreen(),
    'словарик': () => const GlossaryScreen(),
    'настройки': () => const SettingsScreen(),
    'взрослым': () => const AdultScreen(),
    'проверка': () => const DemoScreen(),
  };

  screens.forEach((String name, Widget Function() build) {
    testWidgets('§3.6 доступность на 360 dp: $name',
        (WidgetTester tester) async {
      await _check(tester, build());
    });
  });

  // §3.6.4: «поддержка системного увеличения шрифта». Увеличенный шрифт —
  // самый дешёвый способ найти вёрстку, которая помещается только впритык.
  screens.forEach((String name, Widget Function() build) {
    testWidgets('§3.6.4 при увеличенном шрифте: $name',
        (WidgetTester tester) async {
      await _check(tester, build(), textScale: FinniApp.maxTextScale);
    });
  });
}
