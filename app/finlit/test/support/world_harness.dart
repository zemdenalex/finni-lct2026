import 'dart:io';

import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/fake_world.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/job_games.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Размеры, на которых проверяются экраны нового мира: альбомная —
/// основная, портрет от 360 dp обязан работать (`world_layout.dart`).
const Size landscape = Size(640, 360);
const Size portrait = Size(360, 640);
const Map<String, Size> bothOrientations = <String, Size>{
  'альбомная 640×360': landscape,
  'портрет 360×640': portrait,
};

/// Числа мира из `assets/content/world/*.json` — те же файлы, что едут в
/// сборку. Читаются синхронно и один раз: так конфиг доступен и в теле
/// `testWidgets`, где настоящий асинхронный ввод-вывод не завершается.
final WorldContent shippedContent = WorldContent.parse(
  economy: _readContent('economy.json'),
  jobs: _readContent('jobs.json'),
  events: _readContent('events.json'),
);

final WorldConfig contentConfig = worldConfigFromContent(shippedContent);

/// Содержание мини-игр из того же `jobs.json`, что едет в сборку.
final JobGames contentJobGames = JobGames.fromData(shippedContent.jobData,
    university: shippedContent.university);

/// Сценки знакомства из того же `onboarding.json`, что едет в сборку.
final OnboardingScript contentScript =
    OnboardingScript.parse(File(OnboardingScript.path).readAsStringSync());

String _readContent(String file) =>
    File('${WorldContentLoader.base}/$file').readAsStringSync();

/// Настоящий движок на числах из контента — как в приложении
/// (`openSavedWorld`), только без диска.
WorldGame contentWorld({
  OnboardingProgress onboarding = const OnboardingProgress(),
  OnboardingSave? saveOnboarding,
}) =>
    WorldGame(
        config: contentConfig,
        onboarding: onboarding,
        saveOnboarding: saveOnboarding);

/// На каком мире гоняется экран.
class WorldKind {
  const WorldKind._(this.name, this._make);

  final String name;
  final World Function(OnboardingProgress, OnboardingSave?) _make;

  World make({
    OnboardingProgress onboarding = const OnboardingProgress(),
    OnboardingSave? saveOnboarding,
  }) =>
      _make(onboarding, saveOnboarding);

  @override
  String toString() => name;
}

/// Фейк (`FakeWorld`) и настоящий движок (`WorldGame` из контента).
///
/// 🔴 Экран, который работает на фейке и ломается на движке, — это дыра в
/// контракте, а не повод убрать движок из теста.
final List<WorldKind> worldKinds = <WorldKind>[
  WorldKind._(
      'FakeWorld',
      (OnboardingProgress o, OnboardingSave? s) =>
          FakeWorld(onboarding: o, saveOnboarding: s)),
  WorldKind._(
      'WorldGame',
      (OnboardingProgress o, OnboardingSave? s) =>
          contentWorld(onboarding: o, saveOnboarding: s)),
];

/// Каждый тест из [body] — на обоих мирах, в группах `FakeWorld` и
/// `WorldGame`.
void forEachWorld(void Function(WorldKind kind) body) {
  for (final WorldKind k in worldKinds) {
    group(k.name, () => body(k));
  }
}

/// Действие настройки теста обязано пройти: отказ здесь — это дыра в
/// контракте, а не будущая загадочная ошибка ниже по тесту.
WorldResult ok(WorldResult r) {
  expect(r.ok, isTrue, reason: 'настройка теста: $r');
  return r;
}

/// Экран нового мира с [WorldState] над ним — без диска.
///
/// [world] по умолчанию — настоящий движок из контента ([contentWorld]).
/// Сброс собирает новый мир того же вида. Маршруты нового мира подключены,
/// так что переходы между экранами тоже проверяются.
///
/// [script] — сценки знакомства; по умолчанию — из сборки ([contentScript]).
///
/// [app] — профиль старой игры с настройками звука и движения
/// (`core/feel.dart`); без него действуют настройки по умолчанию.
Future<WorldState> pumpWorldScreen(
  WidgetTester tester,
  Widget screen, {
  World? world,
  WorldState? state,
  Size size = const Size(360, 640),
  double textScale = 1,
  AppState? app,
  OnboardingScript? script,
}) async {
  final World w = world ?? contentWorld();
  final WorldState ws = state ??
      WorldState.persistent(w,
          freshWorld: w is FakeWorld ? FakeWorld.new : contentWorld);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final Widget root = Provider<JobGames>.value(
    value: contentJobGames,
    child: Provider<OnboardingScript>.value(
      value: script ?? contentScript,
      child: ChangeNotifierProvider<WorldState>.value(
        value: ws,
        child: MaterialApp(
          theme: buildAppTheme(),
          routes: worldRoutes,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          // Экран в теме мира, как его строят маршруты `/w/…`: проверки
          // контраста и раскладки должны видеть то же, что ребёнок.
          home: WorldTheme(child: screen),
        ),
      ),
    ),
  );
  await tester.pumpWidget(app == null
      ? root
      : ChangeNotifierProvider<AppState>.value(value: app, child: root));
  await tester.pump();
  return ws;
}

/// Точка на экране, где палец попадает в предмет [key], а не в Финни или
/// питомца над ним.
Offset pointOn(WidgetTester tester, String key) {
  final Finder f = find.byKey(ValueKey<String>(key));
  final RenderObject target = tester.renderObject(f);
  final Rect r = tester.getRect(f).intersect(
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio);
  const List<double> steps = <double>[0.5, 0.3, 0.7, 0.15, 0.85];
  for (final double fy in steps) {
    for (final double fx in steps) {
      final Offset p = Offset(r.left + r.width * fx, r.top + r.height * fy);
      final HitTestResult hit = HitTestResult();
      tester.binding.hitTestInView(hit, p, tester.view.viewId);
      if (hit.path.any((HitTestEntry e) => identical(e.target, target))) {
        return p;
      }
    }
  }
  fail('$key: не попасть пальцем');
}

/// Город в портрете: список мест — в листе «Все места». Открывает лист,
/// если кнопка есть (в альбомной список и так столбцом справа).
Future<void> openCityPlaces(WidgetTester tester) async {
  final Finder chip = find.byKey(const ValueKey<String>('city:places'));
  if (chip.evaluate().isEmpty) return;
  await tester.tap(chip);
  await tester.pumpAndSettle();
}
