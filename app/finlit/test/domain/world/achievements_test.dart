import 'dart:convert';

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Награды и прогресс (D3): правила из `economy.json → achievements`.
///
/// Защищает: в контенте 12 наград; прогресс считается из журнала; награда
/// получается записью `achievementEarned` один раз и не засчитывается дважды;
/// после перезапуска полученное остаётся полученным, второй записи нет.
/// Уронит: награда пишется на каждое действие после цели, прогресс живёт в
/// памяти, или новая награда не появляется в снимке.
void main() {
  WorldGame living() {
    final WorldGame w = contentWorld();
    ok(w.startWeek());
    ok(w.plan(needs: 0, wants: 0, goal: 0));
    return w;
  }

  AchievementView view(World w, String id) =>
      w.snapshot.achievements.firstWhere((AchievementView v) => v.def.id == id);

  int earnedEntries(WorldGame w, String id) => w.journal
      .where((WorldEntry e) =>
          e.kind == WorldLedgerKind.achievementEarned && e.args['id'] == id)
      .length;

  test('в контенте 12 наград, у каждой метрика и цель', () {
    expect(contentConfig.achievements, hasLength(12));
    for (final AchievementDef d in contentConfig.achievements) {
      expect(d.target, greaterThan(0), reason: d.id);
      expect(d.hint, isNotEmpty, reason: d.id);
    }
    final WorldGame w = living();
    expect(w.snapshot.achievements, hasLength(12));
    expect(
        w.snapshot.achievements
            .every((AchievementView v) => v.status != AchievementStatus.earned),
        isTrue,
        reason: 'в начале ничего не получено');
  });

  test('первая смена: награда один раз, дальше не повторяется', () {
    final WorldGame w = living();
    expect(view(w, 'first_shift').status, AchievementStatus.locked);
    final JobOffer o = w.jobBoard.firstWhere((JobOffer j) => !j.blocked);
    ok(w.completeJob(o.jobId, variant: o.variant, score: 1));
    expect(view(w, 'first_shift').status, AchievementStatus.earned);
    expect(view(w, 'first_shift').earnedWeek, 1);
    expect(earnedEntries(w, 'first_shift'), 1);
    final JobOffer o2 = w.jobBoard.firstWhere((JobOffer j) => !j.blocked);
    ok(w.completeJob(o2.jobId, variant: o2.variant, score: 1));
    expect(earnedEntries(w, 'first_shift'), 1,
        reason: 'не засчитывается дважды');
    expect(view(w, 'good_shifts_5').status, AchievementStatus.inProgress);
    expect(view(w, 'good_shifts_5').progress, 2);
  });

  // Защищает «день N недели M» на экране наград (17.10): запись
  // хранит день; старая запись без `day` читается, день — null. Уронит: поле
  // не пишется, пишется в режиме «неделя» или старое сохранение не читается.
  test('день получения: в днях пишется, в «неделе» и старых записях — null',
      () {
    final WorldGame d = contentDayWorld();
    ok(d.startWeek());
    ok(d.plan(needs: 0, wants: 0, goal: 0));
    ok(d.sleep());
    expect(d.snapshot.dayInWeek, 2);
    final JobOffer o = d.jobBoard.firstWhere((JobOffer j) => !j.blocked);
    ok(d.completeJob(o.jobId, variant: o.variant, score: 1));
    expect(view(d, 'first_shift').earnedWeek, 1);
    expect(view(d, 'first_shift').earnedDay, 2);

    final WorldGame w = living();
    final JobOffer ow = w.jobBoard.firstWhere((JobOffer j) => !j.blocked);
    ok(w.completeJob(ow.jobId, variant: ow.variant, score: 1));
    expect(view(w, 'first_shift').earnedDay, isNull, reason: 'неделя');

    // Старое сохранение: та же запись без `day`.
    final List<Object?> json =
        jsonDecode(jsonEncode(d.toJson())) as List<Object?>;
    for (final Object? e in json) {
      final Object? args = (e! as Map<String, Object?>)['args'];
      if (args is Map<String, Object?>) args.remove('day');
    }
    final WorldGame old = WorldGame.fromJson(json, config: d.config);
    expect(old.unreadable, 0);
    expect(view(old, 'first_shift').status, AchievementStatus.earned);
    expect(view(old, 'first_shift').earnedDay, isNull);
  });

  test('перезапуск: полученное остаётся, второй записи нет', () {
    final WorldGame w = living();
    final JobOffer o = w.jobBoard.firstWhere((JobOffer j) => !j.blocked);
    ok(w.completeJob(o.jobId, variant: o.variant, score: 1));
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: w.config);
    expect(r.unreadable, 0);
    expect(view(r, 'first_shift').status, AchievementStatus.earned);
    ok(r.leisure('park'));
    expect(earnedEntries(r, 'first_shift'), 1);
  });
}
