import 'dart:convert';
import 'dart:io';

import 'package:finlit/core/art/asset_registry.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/world_game_loader.dart';

/// ТЗ §2.6 — минимум демонстрационного контента на том мире, который едет в
/// сборке: файлы `assets/content/world/` как есть (7 дней, профиль mid).
/// Защищает: 9 обликов · 5 периодов подряд · 6 заданий по 3 темам ·
/// 8 покупок двух типов · 3 цели · 3 стадии. Уронит: контент урезали, облик
/// без файла, урок потерял тему, позиция выпала из каталога, автопилот в
/// режиме дней не закрывает пять недель. Почему не ловят прежние: минимум в
/// `content_valid_test.dart` считается по контенту первой игры
/// (`assets/content/*.json`), а не по миру; автопилот A8 в режиме дней не
/// проверяет, что пять недель закрыты по семь дней.
Future<WorldGame> _shipped() => openWorldGame(
    read: (String p) => File(p).readAsString(), storage: MemoryStorage());

void main() {
  test('§2.6: облики Финни — не меньше 9, у каждого есть файл', () {
    final AssetRegistry reg = AssetRegistry.parse(
        File('assets/art/registry.json').readAsStringSync());
    final List<String> looks = <String>[
      for (final String s in reg.ids('finni')) ...reg.finniLooks(s),
    ];
    for (final String p in looks) {
      expect(File(p).existsSync(), isTrue, reason: 'нет файла $p');
    }
    // ignore: avoid_print
    print('§2.6 облики: ${reg.ids('finni').length} вида × … = ${looks.length}');
    expect(looks.length, greaterThanOrEqualTo(9));
  });

  test('§2.6: покупки двух типов ≥ 8, цели ≥ 3, стадии ≥ 3', () async {
    final WorldGame w = await _shipped();
    final List<WorldCatalogItem> c = w.catalog;
    const Set<WorldCatalogCategory> required = <WorldCatalogCategory>{
      WorldCatalogCategory.food,
    };
    final int need =
        c.where((WorldCatalogItem i) => required.contains(i.category)).length;
    // Декор не считаем: минимум держится и без него.
    final int want = c
        .where((WorldCatalogItem i) =>
            !required.contains(i.category) &&
            !i.isGoal &&
            i.category != WorldCatalogCategory.decor)
        .length;
    final int decor = c
        .where((WorldCatalogItem i) => i.category == WorldCatalogCategory.decor)
        .length;
    final int goals = c.where((WorldCatalogItem i) => i.isGoal).length;
    // ignore: avoid_print
    print('§2.6 покупки: обязательные $need (еда; плюс жильё и корм в счёте '
        'недели), необязательные без декора $want (декор ещё $decor), '
        'цели $goals, стадии ${w.config.stageMinPoints.length}');
    expect(need, greaterThanOrEqualTo(1), reason: 'обязательные');
    expect(want, greaterThanOrEqualTo(1), reason: 'необязательные');
    expect(need + want, greaterThanOrEqualTo(8));
    expect(goals, greaterThanOrEqualTo(3));
    expect(w.config.stageMinPoints.length, greaterThanOrEqualTo(3));
  });

  test('§2.6: задания — 6 смен с мини-игрой и уроком, 3 темы', () async {
    final WorldGame w = await _shipped();
    final Map<String, Object?> file = jsonDecode(
            File('${WorldContentLoader.base}/jobs.json').readAsStringSync())
        as Map<String, Object?>;
    final Set<String> games = (file['jobs']! as Map<String, Object?>)
        .keys
        .where((String k) => !k.startsWith('_'))
        .toSet();
    final Set<String> withLesson = <String>{
      for (final WorldJob j in w.config.jobs)
        if (games.contains(j.id) && w.config.lesson(j.id) != null) j.id,
    };
    final Set<String> topics = <String>{
      for (final String id in withLesson) w.config.lesson(id)!.topic,
    };
    // ignore: avoid_print
    print('§2.6 задания: ${withLesson.length} ${withLesson.toList()..sort()}, '
        'темы ${topics.toList()..sort()}');
    expect(withLesson.length, greaterThanOrEqualTo(6));
    expect(topics.length, greaterThanOrEqualTo(3));
  });

  test('§2.6: 5 периодов подряд в демо — 5 недель по 7 дней без отказов',
      () async {
    final WorldGame w = await _shipped();
    expect(w.config.dayCycle.daysPerWeek, 7, reason: 'сборка — 7 дней');
    final List<AutopilotStep> steps = WorldAutopilot(w).playWeeks(5);
    for (final AutopilotStep s in steps) {
      expect(s.result.ok, isTrue, reason: '$s');
    }
    int count(WorldLedgerKind k) =>
        w.journal.where((WorldEntry e) => e.kind == k).length;
    // ignore: avoid_print
    print('§2.6 периоды: дней закрыто ${count(WorldLedgerKind.dayEnded)}, '
        'неделя сейчас ${w.snapshot.weekNo}');
    expect(count(WorldLedgerKind.dayEnded), greaterThanOrEqualTo(5 * 6),
        reason: '«Спать» в днях 1–6 каждой недели');
    expect(w.snapshot.weekNo, greaterThanOrEqualTo(6));
  });
}
