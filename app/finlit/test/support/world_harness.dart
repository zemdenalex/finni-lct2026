import 'dart:convert';
import 'dart:io';

import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'fake_world.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_scene.dart' show RoomScene;
import 'package:finlit/features/world/jobs/job_games.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/room_iso/iso_room_scene.dart'
    show IsoRoomScene;
import 'package:finlit/features/world/world_explain.dart';
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
///
/// 🔴 День по энергии (`day_cycle`) в сборке включён, но эти числа — **режим
/// «неделя»** (`days_per_week: 1`, запасной флаг): тесты экранов и правил
/// недели проверяют цикл «одна ночь — итоги», и он не менялся. Дни и
/// сытость проверяет `test/domain/world/day_cycle_test.dart` на настоящих
/// числах `day_cycle`.
final WorldContent shippedContent = WorldContent.parse(
  economy: weekMode(_readContent('economy.json')),
  jobs: _readContent('jobs.json'),
  events: _readContent('events.json'),
  roomItems: _readContent('room_items.json'),
);

final WorldConfig contentConfig = worldConfigFromContent(shippedContent);

/// Числа сборки **как есть**: день по энергии включён (`day_cycle`), как в
/// релизе. Для экранных тестов на дневном мире: `contentDayWorld()` или
/// `WorldKind.day` в `forEachDayWorld`.
final WorldContent shippedDayContent = WorldContent.parse(
  economy: _readContent('economy.json'),
  jobs: _readContent('jobs.json'),
  events: _readContent('events.json'),
  roomItems: _readContent('room_items.json'),
);

final WorldConfig contentDayConfig = worldConfigFromContent(shippedDayContent);

/// Настоящий движок на числах сборки с днями — как в релизе.
WorldGame contentDayWorld({
  OnboardingProgress onboarding = const OnboardingProgress(),
  OnboardingSave? saveOnboarding,
}) =>
    WorldGame(
        config: contentDayConfig,
        onboarding: onboarding,
        saveOnboarding: saveOnboarding);

/// Содержание мини-игр из того же `jobs.json`, что едет в сборку.
final JobGames contentJobGames = JobGames.fromData(shippedContent.jobData,
    university: shippedContent.university,
    shiftChoicesUi: shippedContent.economy.shiftChoicesUi,
    dogWalkGame: shippedContent.economy.dogWalkGame);

/// [contentJobGames] с выключенной прогулкой выгульщика
/// (`day_cycle.dog_walk_game = false`): смена — одной кнопкой «Сделать».
/// Для тестов урока и мини-решения, где сама игра не нужна.
final JobGames contentJobGamesDogStub = JobGames.fromData(
    shippedContent.jobData,
    university: shippedContent.university,
    shiftChoicesUi: shippedContent.economy.shiftChoicesUi,
    dogWalkGame: false);

/// Сценки знакомства из того же `onboarding.json`, что едет в сборку.
final OnboardingScript contentScript =
    OnboardingScript.parse(File(OnboardingScript.path).readAsStringSync());

/// `economy.json` с выключенными днями: `day_cycle.days_per_week = 1`.
String weekMode(String economyJson) {
  final Map<String, Object?> eco =
      jsonDecode(economyJson) as Map<String, Object?>;
  final Object? dc = eco['day_cycle'];
  if (dc is Map<String, Object?>) {
    eco['day_cycle'] = <String, Object?>{...dc, 'days_per_week': 1};
  }
  return jsonEncode(eco);
}

/// `economy.json` с включённой кастомизацией комнаты (`room.customize`):
/// в сборке она выключена, и покупка вещей комнаты без флага отклоняется.
String roomCustomizeOn(String economyJson) {
  final Map<String, Object?> eco =
      jsonDecode(economyJson) as Map<String, Object?>;
  eco['room'] = <String, Object?>{
    ...(eco['room'] as Map<String, Object?>? ?? const <String, Object?>{}),
    'customize': true,
  };
  return jsonEncode(eco);
}

/// Числа сборки (режим «неделя») с включённой кастомизацией комнаты.
final WorldConfig roomOnConfig = worldConfigFromContent(WorldContent.parse(
  economy: roomCustomizeOn(weekMode(_readContent('economy.json'))),
  jobs: _readContent('jobs.json'),
  events: _readContent('events.json'),
  roomItems: _readContent('room_items.json'),
));

/// `economy.json` с фронтальной комнатой (`room.view: "front"`, как сдано
/// 29.09). В сборке с 20.10 — iso; фронтальная осталась откатом флагом, и
/// тесты сцены `RoomScene` (джойстик, ходьба, зоны предметов, сетка
/// «Расставить» фронтальной комнаты) гоняются на ней — так видно, что откат
/// работает.
String frontRoom(String economyJson) {
  final Map<String, Object?> eco =
      jsonDecode(economyJson) as Map<String, Object?>;
  eco['room'] = <String, Object?>{
    ...(eco['room'] as Map<String, Object?>? ?? const <String, Object?>{}),
    'view': 'front',
  };
  return jsonEncode(eco);
}

/// Комната фейка (`FakeWorld`) во фронтальном виде.
const RoomCatalog frontRoomCatalog = RoomCatalog(view: 'front');

/// Числа сборки (режим «неделя») с фронтальной комнатой.
final WorldConfig contentFrontConfig =
    worldConfigFromContent(WorldContent.parse(
  economy: frontRoom(weekMode(_readContent('economy.json'))),
  jobs: _readContent('jobs.json'),
  events: _readContent('events.json'),
  roomItems: _readContent('room_items.json'),
));

/// [contentWorld] с фронтальной комнатой.
WorldGame contentFrontWorld() => WorldGame(config: contentFrontConfig);

/// [worldKinds] с фронтальной комнатой.
final List<WorldKind> frontWorldKinds = <WorldKind>[
  WorldKind._(
      'FakeWorld',
      (OnboardingProgress o, OnboardingSave? s) => FakeWorld(
          config: const WorldConfig(room: frontRoomCatalog),
          onboarding: o,
          saveOnboarding: s)),
  WorldKind._(
      'WorldGame',
      (OnboardingProgress o, OnboardingSave? s) => WorldGame(
          config: contentFrontConfig, onboarding: o, saveOnboarding: s)),
];

/// Сцена комнаты на экране, в любом виде (`room.view`): фронтальная
/// [RoomScene] или iso [IsoRoomScene]. Для тестов раскладки экрана, которым
/// вид комнаты не важен.
final Finder roomSceneFinder = find.byWidgetPredicate(
    (Widget w) => w is RoomScene || w is IsoRoomScene,
    description: 'RoomScene | IsoRoomScene');

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

/// Настоящий движок с днями — как в релизе (`contentDayWorld`).
final WorldKind dayWorldKind = WorldKind._(
    'WorldGameDay',
    (OnboardingProgress o, OnboardingSave? s) =>
        contentDayWorld(onboarding: o, saveOnboarding: s));

/// `FINNI_DAY=1 flutter test …` — те же экранные тесты ещё и на мире с
/// днями (третья группа `WorldGameDay`). Обычный прогон — без неё: многие
/// тесты написаны под неделю («Спать» = итоги), и красное в дневном прогоне —
/// список работы, а не сломанный CI.
final bool dayRun = Platform.environment['FINNI_DAY'] == '1';

/// Каждый тест из [body] — на обоих мирах, в группах `FakeWorld` и
/// `WorldGame` (и `WorldGameDay` при [dayRun]).
void forEachWorld(void Function(WorldKind kind) body) {
  for (final WorldKind k in <WorldKind>[
    ...worldKinds,
    if (dayRun) dayWorldKind
  ]) {
    group(k.name, () => body(k));
  }
}

/// Тест из [body] только на мире с днями (группа `WorldGameDay`).
void forEachDayWorld(void Function(WorldKind kind) body) =>
    group(dayWorldKind.name, () => body(dayWorldKind));

/// «Спать» до итогов недели: в режиме дней сон до последнего дня даёт новое
/// утро (`day.next`), итоги — только после последнего. В режиме «неделя» —
/// один `sleep()`, как раньше. Возвращает последний результат (итоги недели).
WorldResult sleepWeek(World w) {
  WorldResult r = w.sleep();
  while (r.ok && r.reasonCode == 'day.next') {
    r = w.sleep();
  }
  return r;
}

/// Режим дней: проспать до последнего дня недели, чтобы следующий «Спать»
/// (из комнаты или `sleep()`) закрыл неделю и открыл итоги. В режиме
/// «неделя» ничего не делает: там один сон и есть конец недели.
void sleepToLastDay(World w) {
  while (w.snapshot.daysPerWeek > 1 &&
      w.snapshot.dayInWeek < w.snapshot.daysPerWeek) {
    final WorldResult r = w.sleep();
    expect(r.reasonCode, 'day.next', reason: 'настройка теста: $r');
  }
}

/// Режим дней: следующее утро той же недели (одна ночь). В режиме «неделя»
/// ничего не делает — следующего дня там нет.
void nextDay(World w) {
  if (w.snapshot.daysPerWeek <= 1) return;
  final WorldResult r = w.sleep();
  expect(r.reasonCode, 'day.next', reason: 'настройка теста: $r');
}

/// Смены в неделю без лимита (режим дней, DEN-18: ограничивают силы).
/// Бонус «+1 смена» тогда не нужен, и мир отказывает `parent.no_limit`.
bool noShiftLimit(World w) => w.jobBoard.any((JobOffer o) => o.shiftsUnlimited);

/// Действие настройки теста обязано пройти: отказ здесь — это дыра в
/// контракте, а не будущая загадочная ошибка ниже по тесту.
WorldResult ok(WorldResult r) {
  expect(r.ok, isTrue, reason: 'настройка теста: $r');
  return r;
}

/// Объяснения 7 дней из `explain.json` сборки для мира [w] — как в
/// `main.dart`: у движка — его `day_cycle`, у фейка (режим «неделя») — нет.
WorldExplain explainFor(World w) => w is WorldGame
    ? WorldExplain.parse(_readContent('explain.json'),
        dayCycle: w.config.dayCycle)
    : WorldExplain.off;

/// Экран нового мира с [WorldState] над ним — без диска.
///
/// [world] по умолчанию — настоящий движок из контента ([contentWorld]).
/// Сброс собирает новый мир того же вида. Маршруты нового мира подключены,
/// так что переходы между экранами тоже проверяются.
///
/// [script] — сценки знакомства; по умолчанию — из сборки ([contentScript]).
///
/// [games] — содержание мини-игр; по умолчанию — из сборки ([contentJobGames]).
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
  WorldExplain? explain,
  JobGames? games,
}) async {
  final World w = world ?? contentWorld();
  final WorldState ws = state ??
      WorldState.persistent(w,
          freshWorld: w is FakeWorld ? FakeWorld.new : contentWorld);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final Widget root = Provider<JobGames>.value(
    value: games ?? contentJobGames,
    child: Provider<OnboardingScript>.value(
      value: script ?? contentScript,
      child: Provider<WorldExplain>.value(
        value: explain ?? explainFor(w),
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
    ),
  );
  await tester.pumpWidget(app == null
      ? root
      : ChangeNotifierProvider<AppState>.value(value: app, child: root));
  await tester.pump();
  return ws;
}

/// Комната шире экрана (Денис 15.10: по высоте, камера за Финни):
/// предмет [key] за краем — кнопка у того края подводит к нему Финни, пока
/// предмет не окажется под пальцем. Уже под пальцем — ничего не делает.
/// true — Финни подводили (он уже у предмета или рядом).
Future<bool> bringIntoReach(WidgetTester tester, String key) async {
  bool walked = false;
  for (int i = 0; i < 3 && _pointOrNull(tester, key) == null; i++) {
    walked = true;
    final Rect screen =
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    final bool right = tester.getCenter(find.byKey(ValueKey<String>(key))).dx >
        screen.center.dx;
    final Finder edge =
        find.byKey(ValueKey<String>('room:edge:${right ? 'right' : 'left'}'));
    expect(edge, findsOneWidget, reason: '$key: за краем, кнопки у края нет');
    await tester.tap(edge);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }
  return walked;
}

/// Точка на экране, где палец попадает в предмет [key], а не в Финни или
/// питомца над ним.
Offset pointOn(WidgetTester tester, String key) =>
    _pointOrNull(tester, key) ?? fail('$key: не попасть пальцем');

Offset? _pointOrNull(WidgetTester tester, String key) {
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
  return null;
}

/// Город в портрете: список мест — в листе «Все места». Открывает лист,
/// если кнопка есть (в альбомной список и так столбцом справа).
Future<void> openCityPlaces(WidgetTester tester) async {
  final Finder chip = find.byKey(const ValueKey<String>('city:places'));
  if (chip.evaluate().isEmpty) return;
  await tester.tap(chip);
  await tester.pumpAndSettle();
}
