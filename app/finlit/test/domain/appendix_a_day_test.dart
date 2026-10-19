import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_save.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/world_harness.dart' show ok, sleepWeek;

/// Приложение А ТЗ, 12 шагов, в режиме дней — как в релизе (`day_cycle`
/// включён), на настоящем сохранении (`openSavedWorld` над `FileStorage`).
/// Ручные кейсы тех же шагов — `docs/sdacha/10-testy-i-proverka.md` §2.
///
/// Защищает сквозной путь эксперта: после каждого шага мир в ожидаемом
/// состоянии, покупка при нехватке ничего не списывает, после серии недель
/// меняется стадия, закрытие посреди дня 2 и повторный запуск дают тот же
/// снимок (день, сытость, дела дня), сброс начинает с онбординга.
/// Уронит: сохранение теряет день/сытость, покупка списывает при нехватке,
/// стадия не растёт в днях, сброс оставляет старый прогресс.
Future<String> _read(String path) => File(path).readAsString();

Directory _dir() {
  final Directory d = Directory.systemTemp.createTempSync('finlit_appa_');
  addTearDown(() => d.deleteSync(recursive: true));
  return d;
}

Future<SavedWorld> _launch(Directory dir) =>
    openSavedWorld(read: _read, storage: FileStorage(dir));

int _pockets(ResourceSnapshot s) => s.need + s.want + s.free + s.unallocated;

/// Всё, что ребёнок видит в комнате и итогах, — одной строкой.
String _describe(WorldGame w) {
  final ResourceSnapshot s = w.snapshot;
  return <Object?>[
    w.phase,
    s.weekNo,
    s.dayInWeek,
    s.daysPerWeek,
    s.satiety,
    (s.doneToday.toList()..sort()).join(','),
    s.need,
    s.want,
    s.goal,
    s.free,
    s.unallocated,
    s.energy,
    s.happiness,
    s.growthPoints,
    s.stage,
    s.activeGoalId,
    (s.owned.toList()..sort()).join(','),
    s.experience,
    s.achievements
        .map((AchievementView a) => '${a.def.id}:${a.status.name}')
        .join(','),
    w.pendingEvent?.id,
    w.weekHistory.length,
  ].join(' | ');
}

void main() {
  test('Приложение А, шаги 1–12 в режиме дней', () async {
    final Directory dir = _dir();

    // A.1 Первый запуск: онбординг, режим дней.
    SavedWorld app = await _launch(dir);
    WorldGame w = app.world;
    expect(app.restored, WorldRestore.empty);
    expect(w.phase, WeekPhase.onboarding);
    expect(w.config.daysPerWeek, greaterThan(1), reason: 'в релизе дни');

    // A.2 Ник — единственное, что спрашиваем о ребёнке.
    ok(await w.setNickname('Кузя'));
    // A.3 Имя Финни.
    ok(await w.setFinniName('Бублик'));
    expect(w.onboarding.finniName, 'Бублик');

    // A.4 Первые карманные и подарок в копилке; цель; на доске есть смены.
    ok(w.startWeek());
    expect(_pockets(w.snapshot), w.config.pocketMoney);
    expect(w.snapshot.goal, greaterThan(0), reason: 'подарок — в копилке');
    ok(w.chooseGoal('pet_fish'));
    expect(w.jobBoard, isNotEmpty);

    // A.5 План: больше доступного не разложить, остаток виден.
    expect(w.plan(needs: 10000, wants: 0, goal: 0).ok, isFalse);
    ok(w.plan(needs: 300, wants: 50, goal: 50));
    expect(w.phase, WeekPhase.living);
    expect(w.snapshot.dayInWeek, 1);

    // A.6 Смена (задание ТЗ) и урок после неё; оплата в кошельке.
    final int before6 = w.snapshot.free;
    ok(w.completeJob('consultant', score: 1));
    expect(w.snapshot.free, greaterThan(before6));
    final LessonOffer? lesson = w.pendingLesson;
    expect(lesson, isNotNull, reason: 'урок после смены');
    ok(w.resolveLesson(lesson!.choices.first.id));

    // A.7 Еда и «хочу»; покупка дороже, чем есть, — без списания, с причиной.
    ok(w.eat(w.config.foods.first.id));
    final WorldCatalogItem pricey = w.catalog
        .where((WorldCatalogItem i) =>
            i.category == WorldCatalogCategory.clothes ||
            i.category == WorldCatalogCategory.decor)
        .reduce((WorldCatalogItem a, WorldCatalogItem b) =>
            a.price >= b.price ? a : b);
    expect(pricey.price, greaterThan(w.snapshot.available));
    final ResourceSnapshot before7 = w.snapshot;
    final WorldResult refused = w.buy(pricey.id);
    expect(refused.ok, isFalse);
    expect(refused.reason, isNotEmpty, reason: '«не хватает N» и что можно');
    expect(_pockets(w.snapshot), _pockets(before7), reason: 'списания нет');
    expect(w.snapshot.goal, before7.goal);

    // A.8 Пополнить цель: накоплено растёт.
    final int goal8 = w.snapshot.goal;
    ok(w.depositToGoal(20));
    expect(w.snapshot.goal, goal8 + 20);

    // A.9 Конец недели (в днях — после последнего дня) и итоги.
    ok(sleepWeek(w));
    expect(w.phase, WeekPhase.review);
    expect(
        w.journal.where((WorldEntry e) => e.kind == WorldLedgerKind.dayEnded),
        hasLength(w.config.daysPerWeek - 1),
        reason: 'неделя прожита по дням');
    final int points9 = w.snapshot.growthPoints;
    ok(w.payBills());
    expect(w.snapshot.growthPoints, greaterThanOrEqualTo(points9));
    expect(w.weekHistory.last.planMade, isTrue, reason: 'план против факта');

    // A.10 Следующие недели: после серии решений — новая стадия.
    ok(w.startWeek());
    expect(w.snapshot.weekNo, 2);
    final WorldStage stage10 = w.snapshot.stage;
    WorldAutopilot(w).playToStage(WorldStage.town);
    expect(w.snapshot.stage.index, greaterThan(stage10.index));
    expect(
        w.journal.any((WorldEntry e) => e.kind == WorldLedgerKind.stageChanged),
        isTrue);

    // A.11 Закрыть посреди недели (день 2, с делом дня) и открыть снова.
    if (w.phase == WeekPhase.review) {
      if (w.canDo(WorldAction.payBills) == null) ok(w.payBills());
      ok(w.startWeek());
    }
    if (w.phase == WeekPhase.planning) ok(w.plan(needs: 0, wants: 0, goal: 0));
    while (w.snapshot.dayInWeek < 2) {
      ok(w.sleep());
    }
    ok(w.petFinni());
    expect(w.snapshot.dayInWeek, 2);
    expect(w.snapshot.doneToday, contains('pet'));
    expect(w.snapshot.satiety, isNotNull);
    await app.flush();
    expect(app.lastSaveError, isNull);
    final String saved = _describe(w);
    final String journal = jsonEncode(w.toJson());

    app = await _launch(dir);
    expect(app.restored, WorldRestore.restored);
    w = app.world;
    expect(_describe(w), saved, reason: 'тот же день, сытость, дела дня');
    expect(jsonEncode(w.toJson()), journal);
    expect(w.onboarding.nickname, 'Кузя');

    // A.12 Сброс профиля: после подтверждения — онбординг с нуля.
    app.freshWorld();
    await app.forget();
    await app.flush();
    app = await _launch(dir);
    expect(app.restored, WorldRestore.empty);
    expect(app.world.phase, WeekPhase.onboarding);
    expect(app.world.onboarding.nickname, isNot('Кузя'));
    expect(app.world.journal, isEmpty);
  });
}
