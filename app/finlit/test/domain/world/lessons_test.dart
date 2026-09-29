import 'dart:convert';
import 'dart:io';

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/fake_world.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Урок после смены (Денис 29.09, 938; критерии ночи §4): после каждой
/// мини-игры — ситуация, связанная с работой, и 2–3 решения с последствием в
/// мире. Тексты и числа — `jobs.json → lessons`.
void main() {
  // Защищает: у каждой работы есть урок; темы покрывают три темы ТЗ; слово
  // урока есть в Словарике. Уронит: новая работа без урока, урок-тест с одним
  // вариантом, слово, которого нет в glossary.json.
  test('контент: урок у каждой работы, 3 темы ТЗ, слово в Словарике', () {
    final List<Object?> glossary =
        (jsonDecode(File('assets/content/glossary.json').readAsStringSync())
            as Map<String, Object?>)['terms']! as List<Object?>;
    final Set<Object?> words = <Object?>{
      for (final Object? t in glossary) (t! as Map<String, Object?>)['id'],
    };
    final Set<String> jobs = <String>{
      for (final WorldJob j in contentConfig.jobs) j.id,
    };
    expect(<String>{for (final WorldLesson l in contentConfig.lessons) l.jobId},
        jobs);
    expect(<String>{for (final WorldLesson l in contentConfig.lessons) l.topic},
        <String>{'budget', 'savings', 'payments'});
    for (final WorldLesson l in contentConfig.lessons) {
      expect(words, contains(l.word), reason: l.jobId);
      expect(l.choices.length, inInclusiveRange(2, 3), reason: l.jobId);
      // Ревью 2b58bdb §4.2: нет пустых вариантов и нет «правильной кнопки» —
      // варианта, который при тех же долях в конверты тратит не больше и
      // радует не меньше другого (старый кассир: +1 😊 против −10 монет).
      for (final WorldLessonChoice a in l.choices) {
        expect(
            a.goalShare != 0 ||
                a.needShare != 0 ||
                a.spend != 0 ||
                a.happiness != 0,
            isTrue,
            reason: '${l.jobId}.${a.id}: вариант без последствия');
        for (final WorldLessonChoice b in l.choices) {
          if (identical(a, b) ||
              a.goalShare != b.goalShare ||
              a.needShare != b.needShare) {
            continue;
          }
          final bool dominates = a.spend <= b.spend &&
              a.happiness >= b.happiness &&
              (a.spend < b.spend || a.happiness > b.happiness);
          expect(dominates, isFalse,
              reason: '${l.jobId}: «${a.id}» строго лучше «${b.id}»');
        }
      }
    }
  });

  for (final (String name, World Function() make)
      in <(String, World Function())>[
    ('FakeWorld', () => FakeWorld(config: contentConfig)),
    ('WorldGame', contentWorld),
  ]) {
    group(name, () {
      World afterShift(String job) {
        final World w = make();
        ok(w.startWeek());
        ok(w.plan(needs: 400, wants: 0, goal: 0));
        ok(w.completeJob(job, score: 0.5));
        return w;
      }

      // Защищает: решение меняет мир по правилу (доля оплаты смены до
      // десятков — в конверт), итог начинается с «Что мы поняли», слово —
      // в следующем шаге, урок решается один раз. Уронит: доля от кошелька, а
      // не от оплаты; урок можно решить дважды; итог без вывода.
      test('решение урока двигает монеты и решается один раз', () {
        final World w = afterShift('accountant');
        final int pay = w.offer('accountant')!.pay;
        final LessonOffer l = w.pendingLesson!;
        expect(l.jobId, 'accountant');
        expect(l.choices.map((LessonChoiceView c) => c.id),
            containsAll(<String>['needs', 'goal', 'keep']));
        final ResourceSnapshot before = w.snapshot;
        final WorldResult r = ok(w.resolveLesson('goal'));
        final int half = ((pay * 0.5) / 10).round() * 10;
        expect(w.snapshot.goal - before.goal, half);
        expect(w.snapshot.free - before.free, -half);
        expect(r.reason, startsWith('Что мы поняли:'));
        expect(r.nextStep, contains('Смета'));
        expect(w.pendingLesson, isNull);
        expect(w.resolveLesson('goal').reasonCode, 'lesson.none');
      });

      // Защищает: ТЗ 2.5.6.4 — вариант с тратой, на которую не хватает,
      // недоступен и ничего не списывает. Уронит: баланс в минус.
      test('трата дороже, чем есть, — вариант недоступен', () {
        final World w = afterShift('consultant');
        final int spare = w.snapshot.free;
        ok(w.depositToGoal(spare));
        final LessonChoiceView buy = w.pendingLesson!.choices
            .firstWhere((LessonChoiceView c) => c.id == 'buy');
        expect(buy.blockReason?.code, 'lesson.short');
        final ResourceSnapshot before = w.snapshot;
        expect(w.resolveLesson('buy').ok, isFalse);
        expect(w.snapshot.available, before.available);
        expect(w.snapshot.need, before.need, reason: 'НУЖНО не трогаем');
      });

      // Защищает: к уроку можно вернуться в истории недели (§4 п. 7).
      test('решённый урок виден в истории недели', () {
        final World w = afterShift('gardener');
        ok(w.resolveLesson('tenth'));
        expect(w.weekHistory.last.events, contains(startsWith('Урок: ')));
      });
    });
  }

  // Защищает: каждое решение — запись журнала с причиной, урок переживает
  // перезапуск (ТЗ 2.5.4.3, 2.5.13.1). Уронит: вид записи не читается,
  // ожидающий урок пропадает после перезапуска.
  test('урок — запись журнала; ждущий урок переживает перезапуск', () {
    final WorldGame w = contentWorld()..startWeek();
    ok(w.plan(needs: 400, wants: 0, goal: 0));
    ok(w.completeJob('cashier', score: 0.5));
    final WorldGame r = WorldGame.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as List<Object?>,
        config: contentConfig);
    expect(r.pendingLesson?.jobId, 'cashier');
    final int len = r.journal.length;
    ok(r.resolveLesson('trust'));
    final List<WorldEntry> added = r.journal.sublist(len);
    expect(added.single.kind, WorldLedgerKind.lessonChoice);
    expect(added.single.reasonCode, 'lesson.choice');
    expect(added.single.args['choiceId'], 'trust');
    expect(added.single.free + added.single.want, -10,
        reason: 'сдачу не пересчитали — десятка потерялась');
  });

  // Защищает: смена из события — без урока (урок только после мини-игры).
  test('урок не появляется без смены', () {
    final WorldGame w = contentWorld()..startWeek();
    ok(w.plan(needs: 400, wants: 0, goal: 0));
    expect(w.pendingLesson, isNull);
  });

  // Ловит (критерии ночи §8 п. 4): темы ТЗ и слова не собираются из
  // решений — прогресс «чему учит» пустой, хотя уроки пройдены.
  for (final (String name, World Function() make)
      in <(String, World Function())>[
    ('FakeWorld', () => FakeWorld(config: contentConfig)),
    ('WorldGame', contentWorld),
  ]) {
    test('$name: чему научились — темы и слова из уроков', () {
      final World w = make();
      ok(w.startWeek());
      ok(w.plan(needs: 400, wants: 0, goal: 0));
      expect(w.learning.topics, isEmpty);
      ok(w.completeJob('accountant', score: 0.5));
      ok(w.resolveLesson('keep'));
      ok(w.completeJob('cashier', score: 0.5));
      ok(w.resolveLesson('recount'));
      final LearningSummary l = w.learning;
      expect(l.topics, <String, int>{'budget': 1, 'payments': 1});
      expect(l.words.map((({String id, String term}) x) => x.term),
          <String>['Смета', 'Чек']);
    });
  }
}
