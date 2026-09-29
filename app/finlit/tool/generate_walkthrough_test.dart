import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/custom_goal.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:finlit/features/adult/adult_screen.dart';
import 'package:finlit/features/demo/demo_screen.dart';
import 'package:finlit/features/glossary/glossary_screen.dart';
import 'package:finlit/features/home/home_screen.dart';
import 'package:finlit/features/onboarding/onboarding_screen.dart';
import 'package:finlit/features/pet/pet_create_screen.dart';
import 'package:finlit/features/plan/plan_screen.dart';
import 'package:finlit/features/progress/progress_screen.dart';
import 'package:finlit/features/savings/savings_screen.dart';
import 'package:finlit/features/settings/settings_screen.dart';
import 'package:finlit/features/shop/shop_screen.dart';
import 'package:finlit/features/tasks/tasks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fonts.dart';
import 'package:provider/provider.dart';

/// Покадровый проход по приложению для видео.
///
/// Лежит в `tool/`, на CI не гоняется. Запуск:
///
///     flutter test tool/generate_walkthrough_test.dart
///
/// Кадры складываются в `build/walkthrough/`, дальше их склеивает ffmpeg —
/// см. `tool/make_walkthrough.sh`.
///
/// 🔴 Зачем так, а не записью экрана. Ни устройства, ни эмулятора под рукой нет,
/// а показать команде работающее приложение надо сегодня. Здесь снимаются
/// **настоящие экраны с настоящим состоянием**: сценарий прогоняется через
/// игровое ядро, а не рисуется макетом. Когда появится телефон, запись экрана
/// заменит это — но не отменит: по кадрам удобнее сверяться с Приложением А.

int _frame = 0;
final List<String> _index = <String>[];

Future<void> _loadFonts() async {
  for (final String path in <String>[
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
  ]) {
    final File f = File(path);
    if (!f.existsSync()) continue;
    final FontLoader loader = FontLoader('Roboto')
      ..addFont(Future<ByteData>.value(
          ByteData.view(f.readAsBytesSync().buffer)));
    await loader.load();
    break;
  }
  final String root = Platform.environment['FLUTTER_ROOT'] ??
      Directory(Platform.resolvedExecutable).parent.parent.path;
  final File icons =
      File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final FontLoader l = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(
          ByteData.view(icons.readAsBytesSync().buffer)));
    await l.load();
  }
}

/// Тап по подписи с прокруткой до неё.
///
/// 🔴 `ListView` не строит то, что за пределами экрана, поэтому `find.text`
/// по элементу ниже видимой области возвращает пустоту, а `ensureVisible`
/// нечего показывать. Нужен `scrollUntilVisible`, который прокручивает список,
/// пока элемент не появится в дереве.
///
/// Симптом, если этого не сделать: кадр получается «до нажатия», тест зелёный,
/// и понять это можно только посмотрев на картинку.
Future<void> _tap(WidgetTester t, String label) async {
  final Finder target = find.text(label);
  if (target.evaluate().isEmpty) {
    final Finder list = find.byType(Scrollable).first;
    try {
      await t.scrollUntilVisible(target, 300, scrollable: list, maxScrolls: 40);
      await t.pumpAndSettle();
    } on Object {
      return;
    }
  }
  if (target.evaluate().isEmpty) return;
  await t.ensureVisible(target.first);
  await t.pumpAndSettle();
  await t.tap(target.first, warnIfMissed: false);
  await t.pumpAndSettle();
}

Future<AppState> _fresh({bool demo = false}) async {
  final AppState app = AppState(MemoryStorage());
  await app.boot();
  if (demo) await app.setDemoMode(true);
  return app;
}

/// Один кадр: подпись сверху, экран снизу.
Future<void> _shoot(
  WidgetTester tester,
  AppState app,
  String step,
  String caption,
  Widget screen, {
  Future<void> Function(WidgetTester t)? interact,
}) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 3.0;

  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
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
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  if (interact != null) {
    await interact(tester);
    await tester.pump(const Duration(milliseconds: 500));
  }

  await tester.runAsync(() async {
    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image screenImage = await boundary.toImage(pixelRatio: 3.0);

    // Полоса с подписью рисуется поверх снимка: так кадр остаётся ровно
    // того размера, что и экран телефона, и видео не «прыгает».
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas canvas = Canvas(rec);
    canvas.drawImage(screenImage, Offset.zero, Paint());

    const double bandH = 230;
    final double top = screenImage.height - bandH;
    canvas.drawRect(
      Rect.fromLTWH(0, top, screenImage.width.toDouble(), bandH),
      Paint()..color = const Color(0xFF1F2430),
    );

    void text(String s, double dy, double size, FontWeight w, Color c) {
      final ui.ParagraphBuilder pb = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontFamily: 'Roboto',
        fontSize: size,
        fontWeight: w,
      ))
        ..pushStyle(ui.TextStyle(color: c, fontSize: size, fontWeight: w))
        ..addText(s);
      final ui.Paragraph p = pb.build()
        ..layout(ui.ParagraphConstraints(
            width: screenImage.width.toDouble() - 96));
      canvas.drawParagraph(p, Offset(48, top + dy));
    }

    text(step, 34, 30, FontWeight.w700, const Color(0xFF8FD7B4));
    text(caption, 80, 40, FontWeight.w600, Colors.white);

    final ui.Image framed = await rec.endRecording().toImage(
        screenImage.width, screenImage.height);
    final ByteData? png =
        await framed.toByteData(format: ui.ImageByteFormat.png);

    _frame++;
    final String name = _frame.toString().padLeft(3, '0');
    final File out = File('build/walkthrough/frame-$name.png');
    await out.create(recursive: true);
    await out.writeAsBytes(png!.buffer.asUint8List());
    _index.add('$name  $step — $caption');
    // ignore: avoid_print
    print('кадр $name: $step — $caption');
  });
}

void main() {
  setUp(rootBundle.clear);
  setUpAll(() async {
    await _loadFonts();
    final Directory d = Directory('build/walkthrough');
    if (d.existsSync()) d.deleteSync(recursive: true);
  });

  tearDownAll(() {
    File('build/walkthrough/index.txt')
        .writeAsStringSync(_index.join('\n'));
  });

  testWidgets('шаги 1–3: знакомство и создание питомца',
      (WidgetTester tester) async {
    await loadAppFonts();
    final AppState app = await _fresh();

    await _shoot(tester, app, 'Шаг 1', 'Знакомство: Финни и комната, которая меняется от решений',
        const OnboardingScreen());

    const List<String> pages = <String>[
      '',
      'Три конверта и три решения: нужное, желаемое, отложить',
      'Мечта встаёт в комнате и проявляется, пока копишь',
      'Откуда монетки: доверие родителей и задания',
    ];
    for (int i = 1; i <= 3; i++) {
      await _shoot(
        tester,
        app,
        'Шаг 1',
        pages[i],
        const OnboardingScreen(),
        interact: (WidgetTester t) async {
          for (int k = 0; k < i; k++) {
            await t.drag(find.byType(PageView), const Offset(-400, 0));
            await t.pumpAndSettle();
          }
        },
      );
    }

    await _shoot(tester, app, 'Шаги 2–3',
        'Питомец: 3 вида × 3 расцветки — девять комбинаций',
        const PetCreateScreen());

    await app.updateProfile(app.game.profile.copyWith(
        species: PetSpecies.fox, palette: PetPalette.apricot));
    await _shoot(tester, app, 'Шаги 2–3',
        'Имя уже готово — печатать необязательно',
        const PetCreateScreen());
  });

  testWidgets('шаги 4–5: карманные и план недели',
      (WidgetTester tester) async {
    await loadAppFonts();
    final AppState app = await _fresh();
    await app.act((Game g) => g.startPeriod());

    await _shoot(tester, app, 'Шаг 4',
        'Главный: комната, мечта, кошелёк — всё сразу, без вкладок', const HomeScreen());

    await _shoot(tester, app, 'Шаг 5',
        'План недели: «−» конверт «+», монетка летит в конверт',
        const PlanScreen());

    await app.act((Game g) =>
        g.confirmPlan(const Allocation(needs: 4, wants: 3, savings: 3)));
    await _shoot(tester, app, 'Шаг 5',
        'План подтверждён — дальше сравнение с фактом', const PlanScreen());
  });

  testWidgets('шаг 6: задания', (WidgetTester tester) async {
    await loadAppFonts();
    final AppState app = await _fresh(demo: true);
    await app.act((Game g) => g.startPeriod());
    await app.act((Game g) =>
        g.confirmPlan(const Allocation(needs: 4, wants: 3, savings: 3)));

    await _shoot(tester, app, 'Шаг 6',
        'Задания: лимит подработки виден заранее',
        const TasksScreen());

    await _shoot(
      tester,
      app,
      'Шаг 6',
      'Финни ошибается — ребёнок его исправляет',
      const TasksScreen(),
      interact: (WidgetTester t) async {
        await _tap(t, 'Финни ошибается');
      },
    );
  });

  testWidgets('шаг 7: покупки и нехватка монеток',
      (WidgetTester tester) async {
    await loadAppFonts();
    final AppState app = await _fresh();
    await app.act((Game g) => g.startPeriod());
    await app.act((Game g) =>
        g.confirmPlan(const Allocation(needs: 4, wants: 1, savings: 5)));

    await _shoot(tester, app, 'Шаг 7',
        'Покупки: цена, конверт и что изменится — у Финни и в комнате',
        const ShopScreen());

    await _shoot(
      tester,
      app,
      'Шаг 7',
      'Покупка требует подтверждения',
      const ShopScreen(),
      interact: (WidgetTester t) async {
        await _tap(t, 'Миска каши');
      },
    );

    await _shoot(
      tester,
      app,
      'Шаг 7',
      'Купленная вещь остаётся — и сразу стоит в комнате',
      const ShopScreen(),
      interact: (WidgetTester t) async {
        await _tap(t, 'Наклейки');
        await _tap(t, 'Купить');
      },
    );

    await _shoot(
      tester,
      app,
      'Шаг 7',
      'Не хватило монеток — не запрет, а четыре выхода',
      const ShopScreen(),
      interact: (WidgetTester t) async {
        await _tap(t, 'Мячик');
      },
    );
  });

  testWidgets('шаг 8: цель и копилка', (WidgetTester tester) async {
    await loadAppFonts();
    final AppState app = await _fresh();
    await app.act((Game g) => g.startPeriod());

    await _shoot(tester, app, 'Шаг 8',
        'Цели: среди них есть впечатление, а не только вещь',
        const SavingsScreen());

    app.game.chooseGoal('scooter');
    CustomGoals.restore(app.content, 'scooter');
    await app.act((Game g) =>
        g.confirmPlan(const Allocation(needs: 3, wants: 2, savings: 5)));
    await _shoot(tester, app, 'Шаг 8',
        'Срок считается по средней сумме пополнения',
        const SavingsScreen());
  });

  testWidgets('шаг 8: мечта исполнена', (WidgetTester tester) async {
    await loadAppFonts();
    final AppState app = await _fresh();
    await app.act((Game g) => g.startPeriod());
    app.game.chooseGoal('zoo');
    await app.act((Game g) =>
        g.allocate(Envelope.savings, g.snapshot.wallet.unallocated));
    while (!app.game.goalReached) {
      await app.closePeriod();
      await app.act((Game g) => g.startPeriod());
      await app.act((Game g) =>
          g.allocate(Envelope.savings, g.snapshot.wallet.unallocated));
    }
    await _shoot(tester, app, 'Шаг 8',
        'Мечта набрана — золотая кнопка «Исполнить мечту»',
        const SavingsScreen());
    await _shoot(
      tester,
      app,
      'Шаг 8',
      'Исполнение: мечта встаёт во дворе у дерева насовсем',
      const SavingsScreen(),
      interact: (WidgetTester t) async {
        await _tap(t, 'Исполнить мечту');
        await _tap(t, 'Исполнить');
      },
    );
    await _shoot(tester, app, 'Шаг 8',
        'Мир вырос: мечта во дворе, копилка ждёт следующую',
        const HomeScreen());
  });

  testWidgets('шаги 9–10: итоги недели и рост Финни',
      (WidgetTester tester) async {
    await loadAppFonts();
    final AppState app = await _fresh(demo: true);
    for (int week = 1; week <= 3; week++) {
      await app.act((Game g) => g.startPeriod());
      if (week == 1) app.game.chooseGoal('zoo');
      await app.act((Game g) =>
          g.confirmPlan(const Allocation(needs: 4, wants: 2, savings: 4)));
      await app.act((Game g) => g.buy(app.content.item('veggies')));
      await app.act((Game g) => g.buy(app.content.item('bath')));
      if (app.game.unexpectedPending) {
        await app.act((Game g) => g.deferUnexpected());
      }
      await app.closePeriod();
    }

    await app.act((Game g) => g.startPeriod());
    await _shoot(tester, app, 'Шаг 10',
        'Через три недели: у Финни коврик, шарф и своя монетка',
        const HomeScreen());

    await _shoot(tester, app, 'Шаг 9',
        'Итоги недели: план против факта и три очка заботы',
        const ProgressScreen());

    await _shoot(
      tester,
      app,
      'Шаг 10',
      'Стадии: растёт самостоятельность, а не возраст',
      const ProgressScreen(),
      interact: (WidgetTester t) async {
        await t.drag(find.byType(Scrollable).first, const Offset(0, -900));
        await t.pumpAndSettle();
      },
    );

    await _shoot(
      tester,
      app,
      'Объяснимость',
      'Любое число разворачивается в историю с причинами',
      const ProgressScreen(),
      interact: (WidgetTester t) async {
        await t.drag(find.byType(Scrollable).first, const Offset(0, -2600));
        await t.pumpAndSettle();
      },
    );

    await _shoot(tester, app, 'Словарик',
        'Термины открываются по мере встречи в игре',
        const GlossaryScreen());
  });

  testWidgets('шаг 12: взрослый, настройки, проверка',
      (WidgetTester tester) async {
    await loadAppFonts();
    final AppState app = await _fresh(demo: true);
    await app.act((Game g) => g.startPeriod());
    await app.act((Game g) =>
        g.confirmPlan(const Allocation(needs: 4, wants: 2, savings: 4)));
    await app.act((Game g) => g.buy(app.content.item('porridge')));
    await app.closePeriod();

    await _shoot(tester, app, 'Шаг 12',
        'Вход для взрослого — арифметический барьер',
        const AdultScreen());

    await _shoot(tester, app, 'Настройки',
        'Звук, анимации и озвучка отключаются',
        const SettingsScreen());

    await _shoot(tester, app, 'Для эксперта',
        'Экран «Проверка»: 12 шагов со статусом из журнала',
        const DemoScreen());
  });
}
