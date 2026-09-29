import 'package:finlit/app_state.dart';
import 'package:finlit/core/speaker.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/core/widgets.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:finlit/features/onboarding/onboarding_screen.dart';
import 'package:finlit/features/shop/shop_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// §3.6.7 «звуки и анимации можно отключить» — проверка поведением.
///
/// 🔴 Записи `soundOn: false` в JSON недостаточно: профиль хранил оба флага
/// с первого дня, и оба не читал никто. Поэтому здесь нет ни одной проверки
/// сериализации. Каждый тест смотрит наружу: ушёл ли щелчок на платформу,
/// сдвинулась ли страница за один кадр, есть ли кнопка «Прослушать».

/// Всё, что приложение сказало платформенному каналу.
final List<MethodCall> _platform = <MethodCall>[];

/// Только то, что относится к отклику: щелчок и вибрация.
List<MethodCall> get _feel => _platform
    .where((MethodCall c) =>
        c.method == 'SystemSound.play' || c.method == 'HapticFeedback.vibrate')
    .toList();

bool get _vibrated =>
    _feel.any((MethodCall c) => c.method == 'HapticFeedback.vibrate');
bool get _clicked =>
    _feel.any((MethodCall c) => c.method == 'SystemSound.play');

Widget wrap(AppState app, Widget child, {bool systemReducedMotion = false}) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: child,
        builder: (BuildContext ctx, Widget? c) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(disableAnimations: systemReducedMotion),
          child: c!,
        ),
      ),
    );

/// Экран-подставка: одна кнопка, которая показывает карточку последствия.
/// Через неё проходит каждое игровое событие, поэтому она и есть «поведение».
Widget feedbackHost(AppState app) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showFeedback(
                  ctx,
                  const ActionResult(
                    title: 'Куплено: Вода для умывания',
                    text: 'Монетка ушла из конверта «Нужное».',
                    nextStep: 'Посмотри, сколько осталось',
                  ),
                ),
                child: const Text('показать'),
              ),
            ),
          ),
        ),
      ),
    );

Future<AppState> bootWith(GameSettings s) async {
  final AppState app = AppState(MemoryStorage());
  await app.boot();
  await app.updateProfile(app.game.profile.copyWith(settings: s));
  return app;
}

Future<void> pumpShop(WidgetTester tester, AppState app) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(wrap(app, const ShopScreen()));
  await tester.pumpAndSettle();
}

/// Неделя с подтверждённым планом: в конверте «Нужное» есть на что купить.
Future<AppState> weekWithMoney(GameSettings s) async {
  final AppState app = await bootWith(s);
  await app.act((Game g) => g.startPeriod());
  await app.act((Game g) =>
      g.confirmPlan(const Allocation(needs: 5, wants: 3, savings: 2)));
  return app;
}

PageController pages(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!;

/// Прогон теста на iOS.
///
/// 🔴 Не из любви к платформе: на Android Material сам играет
/// SystemSound.click на каждое касание InkWell, и щелчок приложения
/// растворился бы среди щелчков нажатий — «тишина» перестала бы проверяться.
/// На iOS `Feedback.forTap` молчит, и в журнале канала остаётся ровно то,
/// что послало приложение. Возврат значения — в finally: иначе упавший
/// expect оставит флаг взведённым и уронит весь остаток файла.
Future<void> onIOS(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  // 🔴 rootBundle кеширует не строку, а Future, созданный в зоне того теста,
  // где ассет прочитали первым. Второй AppState.boot() в файле ждал бы его
  // вечно — тест висит без единого сообщения.
  setUp(rootBundle.clear);

  setUp(() {
    _platform.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform,
            (MethodCall call) async {
      _platform.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('§3.6.7 со звуками покупка щёлкает и отдаётся вибрацией', (
    WidgetTester tester,
  ) async {
    await onIOS(() async {
      final AppState app = await weekWithMoney(const GameSettings());
      await pumpShop(tester, app);

      await tester.tap(find.text('Вода для умывания'));
      await tester.pumpAndSettle();
      _platform.clear();

      await tester.tap(find.widgetWithText(FilledButton, 'Купить'));
      await tester.pumpAndSettle();

      expect(app.game.snapshot.wallet.envelopes.needs, 4,
          reason: 'покупка должна была состояться, иначе тест ни о чём');
      expect(_clicked, isTrue, reason: 'подпись обещает щелчок при покупке');
      expect(_vibrated, isTrue);
    });
  });

  testWidgets('§3.6.7 без звуков покупка проходит молча', (
    WidgetTester tester,
  ) async {
    await onIOS(() async {
      final AppState app =
          await weekWithMoney(const GameSettings(soundOn: false));
      await pumpShop(tester, app);

      await tester.tap(find.text('Вода для умывания'));
      await tester.pumpAndSettle();
      _platform.clear();

      await tester.tap(find.widgetWithText(FilledButton, 'Купить'));
      await tester.pumpAndSettle();

      expect(app.game.snapshot.wallet.envelopes.needs, 4,
          reason: 'выключённый звук не отменяет саму покупку');
      expect(_feel, isEmpty,
          reason: 'ни щелчка, ни вибрации: переключатель обязан выключать');
    });
  });

  testWidgets('§3.6.7 карточка последствия отзывается только со звуками', (
    WidgetTester tester,
  ) async {
    await onIOS(() async {
      final AppState app = await bootWith(const GameSettings());
      await tester.pumpWidget(feedbackHost(app));
      await tester.pumpAndSettle();

      await tester.tap(find.text('показать'));
      await tester.pumpAndSettle();
      expect(_feel, isNotEmpty);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await app.updateProfile(app.game.profile
          .copyWith(settings: const GameSettings(soundOn: false)));
      await tester.pumpAndSettle();
      _platform.clear();

      await tester.tap(find.text('показать'));
      await tester.pumpAndSettle();
      expect(find.text('Куплено: Вода для умывания'), findsOneWidget,
          reason: 'карточка показывается всегда: §3.6.7 запрещает передавать '
              'важное только звуком');
      expect(_feel, isEmpty);
    });
  });

  testWidgets('§3.6.7 «Звуки» выключают и чтение вслух', (
    WidgetTester tester,
  ) async {
    Speaker.instance.debugSetAvailable(value: true);
    addTearDown(() => Speaker.instance.debugSetAvailable(value: false));

    // Ребёнок попросил читать вслух — и отдельно выключил звуки.
    final AppState app = await bootWith(
        const GameSettings(readAloud: true, soundOn: false));
    await tester.pumpWidget(feedbackHost(app));
    await tester.pumpAndSettle();

    await tester.tap(find.text('показать'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Прослушать'), findsNothing,
        reason: '🔴 выключенные звуки обязаны выключать и голос');

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await app.updateProfile(app.game.profile.copyWith(
        settings: const GameSettings(readAloud: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('показать'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Прослушать'), findsOneWidget,
        reason: 'со звуками кнопка озвучки на месте');
  });

  testWidgets('§3.6.7 без анимаций знакомство листается мгновенно', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app =
        await bootWith(const GameSettings(animationsOn: false));
    await tester.pumpWidget(wrap(app, const OnboardingScreen()));
    await tester.pumpAndSettle();

    final PageController c = pages(tester);
    await tester.tap(find.text('Дальше'));
    // Ровно один кадр и ноль игрового времени: анимации некуда деться.
    await tester.pump();

    expect(c.page, closeTo(1.0, 0.001),
        reason: 'страница обязана смениться без промежуточных кадров');
    expect(find.textContaining('Монетки живут в трёх конвертах.'),
        findsOneWidget);
  });

  testWidgets('§3.6.7 с анимациями та же страница едет, а не прыгает', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = await bootWith(const GameSettings());
    await tester.pumpWidget(wrap(app, const OnboardingScreen()));
    await tester.pumpAndSettle();

    final PageController c = pages(tester);
    await tester.tap(find.text('Дальше'));
    await tester.pump();

    // Контрольный тест: без него предыдущий проходил бы и на коде, который
    // никогда не анимирует, — и «выключение» перестало бы что-либо значить.
    expect(c.page, lessThan(1.0),
        reason: 'включённая анимация не долистывает за один кадр');
    await tester.pumpAndSettle();
    expect(c.page, closeTo(1.0, 0.001));
  });

  testWidgets('§3.6.7 системное «уменьшить движение» сильнее переключателя', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Флаг в профиле включён — но телефон просит не двигать ничего.
    final AppState app = await bootWith(const GameSettings());
    await tester.pumpWidget(
        wrap(app, const OnboardingScreen(), systemReducedMotion: true));
    await tester.pumpAndSettle();

    final PageController c = pages(tester);
    await tester.tap(find.text('Дальше'));
    await tester.pump();

    expect(app.game.profile.settings.animationsOn, isTrue);
    expect(c.page, closeTo(1.0, 0.001),
        reason: '🔴 системную просьбу игра не переспрашивает');
  });

  testWidgets('§3.6.7 без анимаций карточка последствия не выезжает', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = await bootWith(const GameSettings());
    await tester.pumpWidget(feedbackHost(app));
    await tester.pumpAndSettle();

    await tester.tap(find.text('показать'));
    await tester.pump();
    final double sliding = tester.getTopLeft(find.text('Куплено: Вода для умывания')).dy;
    await tester.pumpAndSettle();
    final double settled = tester.getTopLeft(find.text('Куплено: Вода для умывания')).dy;
    expect(sliding, greaterThan(settled),
        reason: 'с анимациями карточка первый кадр ещё внизу экрана');

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await app.updateProfile(app.game.profile
        .copyWith(settings: const GameSettings(animationsOn: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('показать'));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Куплено: Вода для умывания')).dy,
        closeTo(settled, 0.5),
        reason: 'без анимаций карточка на месте с первого кадра');
  });
}
