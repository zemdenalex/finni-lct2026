import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/features/home/home_screen.dart';
import 'package:finlit/features/pet/pet_create_screen.dart';
import 'package:finlit/features/plan/plan_screen.dart';
import 'package:finlit/features/savings/savings_screen.dart';
import 'package:finlit/features/shop/shop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fonts.dart';
import 'package:provider/provider.dart';

/// Черновые скриншоты для карточки RuStore и презентации.
///
/// Лежит в `tool/`, на CI не гоняется. Запуск:
///
///     flutter test tool/generate_screenshots_test.dart
///
/// 🔴 Это **черновики**, а не финальные скриншоты магазина. RuStore требует
/// пропорций 9:16 и запрещает показывать элементы интерфейса Android — снимок
/// с реального телефона всё равно придётся кадрировать. Но черновики нужны
/// сегодня: презентацию верстают 27–28.09, а до этого показывать нечего.
Future<void> _loadFonts() async {
  // Без системного шрифта flutter_test рисует прямоугольники вместо букв.
  for (final String path in <String>[
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
    '/System/Library/Fonts/SFNS.ttf',
  ]) {
    final File f = File(path);
    if (!f.existsSync()) continue;
    final FontLoader loader = FontLoader('Roboto')
      ..addFont(Future<ByteData>.value(
          ByteData.view(f.readAsBytesSync().buffer)));
    await loader.load();
    break;
  }

  // Шрифт иконок Material — без него на месте каждой иконки квадрат,
  // и черновой скриншот невозможно ни показать, ни оценить.
  final String root = Platform.environment['FLUTTER_ROOT'] ??
      Directory(Platform.resolvedExecutable).parent.parent.path;
  for (final String rel in <String>[
    'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    'packages/flutter/lib/src/material/MaterialIcons-Regular.otf',
  ]) {
    final File f = File('$root/$rel');
    if (!f.existsSync()) continue;
    final FontLoader icons = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(
          ByteData.view(f.readAsBytesSync().buffer)));
    await icons.load();
    return;
  }
  // ignore: avoid_print
  print('⚠ MaterialIcons не найден — иконки будут квадратами');
}

Future<AppState> _state() async {
  final AppState app = AppState(MemoryStorage());
  await app.boot();
  await app.act((Game g) => g.startPeriod());
  app.game.chooseGoal('scooter');
  return app;
}

Future<void> _shoot(
  WidgetTester tester,
  String name,
  Widget screen, {
  AppState? state,
  Future<void> Function(WidgetTester t)? interact,
}) async {
  // 🔴 physicalSize задаётся в ФИЗИЧЕСКИХ пикселях. 1080 × 1920 при плотности 3
  // даёт логические 360 × 640 — ту самую минимальную ширину, которую называет
  // §3.1.2 ТЗ. Если передать сюда 360 × 640, логический экран станет 120 dp,
  // и вёрстка поедет — в первой версии этого файла так и вышло.
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final AppState app = state ?? await _state();
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: screen,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  if (interact != null) {
    await interact(tester);
    await tester.pumpAndSettle();
  }

  await tester.runAsync(() async {
    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
    final File out = File('assets/store/screenshot-$name.png');
    await out.create(recursive: true);
    await out.writeAsBytes(png!.buffer.asUint8List());
    // ignore: avoid_print
    print('$name: ${image.width}×${image.height} → ${out.path}');
  });
}

void main() {
  setUp(rootBundle.clear);
  setUpAll(_loadFonts);

  testWidgets('главный экран', (WidgetTester tester) async {
    await loadAppFonts();
    // Для витрины — обжитая комната: первое, что видит человек в магазине,
    // должно показывать главную мысль — решения ребёнка меняют мир Финни.
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await app.updateProfile(
        app.game.profile.copyWith(palette: PetPalette.apricot));
    await app.act((Game g) => g.startPeriod());
    app.game.chooseGoal('house');
    await app.act((Game g) =>
        g.confirmPlan(const Allocation(needs: 3, wants: 3, savings: 4)));
    await app.act((Game g) => g.buy(app.content.item('porridge')));
    await app.act((Game g) => g.buy(app.content.item('ball')));
    await app.act((Game g) => g.buy(app.content.item('stickers')));
    await _shoot(tester, '1-home', const HomeScreen(), state: app);
  });

  testWidgets('план недели', (WidgetTester tester) async {
    await loadAppFonts();
    // План в процессе: монетки уже лежат в конвертах. На пустом плане
    // подсказка про еду уходила под нижнюю панель, и кадр выглядел
    // обрезанным.
    final SemanticsHandle sem = tester.ensureSemantics();
    await _shoot(tester, '2-plan', const PlanScreen(),
        interact: (WidgetTester t) async {
      for (final (String e, int n) in <(String, int)>[
        ('Нужное', 4),
        ('Хочу', 2),
      ]) {
        for (int i = 0; i < n; i++) {
          final Finder plus =
              find.bySemanticsLabel('Положить монетку в конверт «$e»');
          await t.ensureVisible(plus);
          await t.tap(plus);
          await t.pump(const Duration(milliseconds: 50));
        }
      }
      // Обратно к началу: в кадре — Финни с задачей и первый конверт.
      await t.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await t.pumpAndSettle();
    });
    sem.dispose();
  });

  testWidgets('покупки', (WidgetTester tester) async {
    await loadAppFonts();
    final AppState app = await _state();
    await app.act((Game g) =>
        g.confirmPlan(const Allocation(needs: 4, wants: 3, savings: 3)));
    await _shoot(tester, '3-shop', const ShopScreen(), state: app);
  });

  testWidgets('копилка и цель', (WidgetTester tester) async {
    await loadAppFonts();
    final AppState app = await _state();
    await app.act((Game g) =>
        g.confirmPlan(const Allocation(needs: 3, wants: 2, savings: 5)));
    await _shoot(tester, '4-savings', const SavingsScreen(), state: app);
  });

  testWidgets('создание питомца', (WidgetTester tester) async {
    await loadAppFonts();
    // §7.1.5: создание питомца — один из трёх обязательных ключевых экранов
    // промежуточной сдачи.
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await app.updateProfile(
        app.game.profile.copyWith(palette: PetPalette.apricot));
    await _shoot(tester, '5-pet', const PetCreateScreen(), state: app);
  });
}
