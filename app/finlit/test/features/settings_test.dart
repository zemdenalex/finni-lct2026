import 'package:finlit/app_state.dart';
import 'package:finlit/core/speaker.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget wrap(AppState app, Widget child) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildAppTheme(), home: child),
    );

void tallScreen(WidgetTester tester, {double width = 400}) {
  tester.view.physicalSize = Size(width, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  // 🔴 rootBundle кеширует не строку, а Future, созданный в зоне того теста,
  // где ассет прочитали впервые. Второй AppState.boot() в том же файле ждёт
  // этот Future вечно — тест виснет без единого сообщения.
  setUp(rootBundle.clear);

  // §3.6.7: «Читать вслух» показывается только если голос на устройстве есть.
  // В виджет-тестах платформенного канала нет, поэтому состояние задаётся явно.
  setUp(() => Speaker.instance.debugSetAvailable(value: true));

  // 🔴 Здесь проверяется только то, что переключатель записывает флаг и флаг
  // переживает перезапуск. Что флаг на что-то влияет — отдельный файл,
  // test/features/sound_and_motion_test.dart: раньше этот тест назывался
  // «звуки и анимации выключаются» и был единственным, а выключалось при
  // этом ровно ничего.
  testWidgets('§3.6.7 переключатели пишут флаги в профиль и на диск', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    final MemoryStorage storage = MemoryStorage();
    final AppState app = AppState(storage);
    await app.boot();

    await tester.pumpWidget(wrap(app, const SettingsScreen()));
    await tester.pumpAndSettle();

    expect(app.game.profile.settings.soundOn, isTrue);
    await tester.tap(find.text('Звуки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Анимации'));
    await tester.pumpAndSettle();

    expect(app.game.profile.settings.soundOn, isFalse);
    expect(app.game.profile.settings.animationsOn, isFalse);

    // «Сохраняются» — значит, переживают перезапуск, а не только setState.
    final AppState again = AppState(storage);
    await again.boot();
    expect(again.game.profile.settings.soundOn, isFalse);
    expect(again.game.profile.settings.animationsOn, isFalse);
  });

  testWidgets('«Читать вслух» переключается и подписан честно', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    final AppState app = AppState(MemoryStorage());
    await app.boot();

    await tester.pumpWidget(wrap(app, const SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Читать вслух'));
    await tester.pumpAndSettle();
    expect(app.game.profile.settings.readAloud, isTrue);

    expect(
      find.textContaining('Ключевые объяснения можно прослушать'),
      findsOneWidget,
      reason: 'подпись не должна обещать озвучку всего текста',
    );
    expect(find.text('Проверить голос'), findsOneWidget,
        reason: 'взрослому нужно услышать звук до того, как отдать телефон');
  });

  testWidgets('§3.6.7 без русского голоса переключателя нет вовсе', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    Speaker.instance.debugSetAvailable(value: false);
    final AppState app = AppState(MemoryStorage());
    await app.boot();

    await tester.pumpWidget(wrap(app, const SettingsScreen()));
    await tester.pumpAndSettle();

    // Остаются ровно три переключателя: звуки, анимации, крупные числа.
    expect(find.byType(SwitchListTile), findsNWidgets(3),
        reason: 'мёртвый тумблер хуже отсутствующего');
    expect(find.textContaining('Озвучка недоступна'), findsOneWidget);
    expect(find.text('Проверить голос'), findsNothing);
  });

  testWidgets('§3.6 «Числа покрупнее» предупреждают диалогом', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    final int pocketBefore = app.content.economy.pocketMoney;

    await tester.pumpWidget(wrap(app, const SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Числа покрупнее'));
    await tester.pumpAndSettle();
    expect(find.text('Включить крупные числа?'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(app.game.profile.settings.bigNumbers, isFalse,
        reason: 'отмена не меняет масштаб экономики');

    await tester.tap(find.text('Числа покрупнее'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
    await tester.pumpAndSettle();

    expect(app.game.profile.settings.bigNumbers, isTrue);
    expect(app.content.economy.pocketMoney, greaterThan(pocketBefore),
        reason: 'переключатель меняет scale и перезагружает игровые числа');
    // 🔴 И экран, и движок — иначе проверяется ровно та половина, которая
    // работала: контент умножался, а игра продолжала считать по старому.
    // Весь режим целиком — test/features/big_numbers_test.dart.
    expect(app.game.content.economy.pocketMoney,
        app.content.economy.pocketMoney);
  });

  testWidgets('§3.5 возрастная маркировка и данные только на устройстве', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    final AppState app = AppState(MemoryStorage());
    await app.boot();

    await tester.pumpWidget(wrap(app, const SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Возрастная маркировка 0+'), findsOneWidget);
    expect(find.text('Данные только на устройстве'), findsOneWidget);
    expect(
        find.text('Финни, версия ${SettingsScreen.version}'), findsOneWidget);
    // §2.5.13: путь в демонстрационный режим должен существовать с первого
    // запуска, иначе эксперт до экрана «Проверка» не доберётся.
    expect(find.text('Демонстрационный режим (для проверки)'), findsOneWidget);
  });

  testWidgets('§3.6.4 не переполняется при 360 dp и увеличенном шрифте', (
    WidgetTester tester,
  ) async {
    tallScreen(tester, width: 360);
    final AppState app = AppState(MemoryStorage());
    await app.boot();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const SettingsScreen(),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
