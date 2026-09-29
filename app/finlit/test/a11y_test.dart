import 'package:finlit/app.dart';
import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/features/home/home_screen.dart';
import 'package:finlit/features/plan/plan_screen.dart';
import 'package:finlit/features/shop/shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../tool/test_fonts.dart';

/// Автоматизированные проверки доступности.
///
/// §3.6 ТЗ требует тач-таргетов от 48 dp, текста от 16 sp, читаемости при
/// системном увеличении шрифта и того, чтобы цвет не был единственным
/// носителем смысла. Три из четырёх проверяются машиной — и это самый дешёвый
/// способ получить проверяемое утверждение в документации вместо обещания.
///
/// Здесь — три экрана обязательного сценария. Остальные девять покрыты
/// в `a11y_all_screens_test.dart`, и там же проверка идёт на 360 dp при
/// увеличенном шрифте.
///
/// 🔴 Граница «только три экрана» держалась до 19.09 и оказалась дорогой:
/// как только проверки включили на остальных, они сразу нашли то, чего
/// не видел ни один из полутора сотен прочих тестов. `Text` переносит слова,
/// а не переполняется, поэтому дефекты вёрстки на узком экране не падают
/// сами — их надо спрашивать.
Future<AppState> _state() async {
  final AppState app = AppState(MemoryStorage());
  await app.boot();
  await app.act((Game g) => g.startPeriod());
  app.game.chooseGoal('zoo');
  return app;
}

Widget _wrap(AppState app, Widget child) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildAppTheme(), home: child),
    );

Future<void> _checkGuidelines(WidgetTester tester, Widget screen) async {
  final AppState app = await _state();
  final SemanticsHandle handle = tester.ensureSemantics();
  await tester.pumpWidget(_wrap(app, screen));
  await tester.pump(const Duration(milliseconds: 400));

  // Размер тач-таргета проверяется у семантического узла, а не у картинки:
  // IconButton с иконкой 24 dp проходит, GestureDetector вокруг мелкого
  // Container — нет.
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  // Иконочная кнопка без подписи — самый частый дефект детского интерфейса.
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

void main() {
  // Настоящие Onest и Unbounded, а не подстановочный Ahem: у Ahem каждая
  // буква — квадрат в кегль, и на увеличенном шрифте тест проверял вёрстку
  // строк в полтора раза длиннее тех, что увидит ребёнок.
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  testWidgets('§3.6 главный экран проходит проверки доступности',
      (WidgetTester tester) async {
    await _checkGuidelines(tester, const HomeScreen());
  });

  testWidgets('§3.6 экран плана проходит проверки доступности',
      (WidgetTester tester) async {
    await _checkGuidelines(tester, const PlanScreen());
  });

  testWidgets('§3.6 экран покупок проходит проверки доступности',
      (WidgetTester tester) async {
    final AppState app = await _state();
    await app.act(
      (Game g) => g.confirmPlan(const Allocation(needs: 4, wants: 3, savings: 3)),
    );
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(app, const ShopScreen()));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('§3.6.4 вёрстка переживает системное увеличение шрифта',
      (WidgetTester tester) async {
    // Масштаб в приложении ограничен FinniApp.maxTextScale (см. app.dart): не отключён, но и
    // не пропущен до 2.0, при котором детская вёрстка с крупными кнопками
    // начинает переполняться, и вместо читаемости получается обрезанный текст.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = await _state();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const HomeScreen(),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(FinniApp.maxTextScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
