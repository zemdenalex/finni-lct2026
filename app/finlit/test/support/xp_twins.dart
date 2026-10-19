import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'world_harness.dart';

/// Миры-близнецы для надбавки за опыт в монетах (решение Дениса 19.10).
///
/// Ожидание берётся из **начисления**, а не из формулы: два мира делают одни
/// и те же шаги, у второго опыт ничего не прибавляет
/// (`experience_mult_per_shift` 1). Разница начисленного за обычную смену —
/// и есть надбавка за опыт.

/// Мир сборки ([week] — режим «неделя»); опыт растёт с множителем [growth],
/// везения нет (его доплата считается от оплаты с опытом). Настроение как
/// в сборке (`mood_pay_live`): у близнецов оно одно и то же, а дробная
/// оплата без опыта нужна, чтобы округление вверх отличалось от обычного.
WorldGame xpWorld(double growth, {bool week = false}) {
  String read(String f) =>
      File('${WorldContentLoader.base}/$f').readAsStringSync();
  final Map<String, Object?> e =
      jsonDecode(read('economy.json')) as Map<String, Object?>;
  final Map<String, Object?> dc = e['day_cycle']! as Map<String, Object?>;
  e['day_cycle'] = <String, Object?>{
    ...dc,
    'shift_luck': <String, Object?>{
      ...(dc['shift_luck']! as Map<String, Object?>),
      'chance': 0,
    },
  };
  e['jobs_pay_growth'] = <String, Object?>{
    ...(e['jobs_pay_growth']! as Map<String, Object?>),
    'experience_mult_per_shift': growth,
  };
  final String eco = jsonEncode(e);
  return WorldGame(
      config: worldConfigFromContent(WorldContent.parse(
          economy: week ? weekMode(eco) : eco,
          jobs: read('jobs.json'),
          events: read('events.json'),
          roomItems: read('room_items.json'))),
      onboarding: const OnboardingProgress(step: OnboardingProgress.stepDone));
}

/// Одно и то же действие в обоих мирах.
void both(List<WorldGame> ws, WorldResult Function(WorldGame w) act) {
  for (final WorldGame w in ws) {
    ok(act(w));
  }
}

/// Мир [growth] и его близнец без прибавки, неделя начата и разложена.
(WorldGame, WorldGame) livingTwins(double growth, {bool week = false}) {
  final WorldGame a = xpWorld(growth, week: week);
  final WorldGame b = xpWorld(1, week: week);
  final List<WorldGame> ws = <WorldGame>[a, b];
  both(ws, (WorldGame w) => w.startWeek());
  both(ws,
      (WorldGame w) => w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  return (a, b);
}

/// Довести оба мира до момента, когда смену [jobId] можно взять: неделя
/// кончилась — счета и новая неделя; не хватает сил — сон. false — так и
/// не открылась (закрыта замком или лимитом).
bool readyFor(WorldGame a, WorldGame b, String jobId, {String? variant}) {
  final List<WorldGame> ws = <WorldGame>[a, b];
  for (int tries = 0; tries < 4; tries++) {
    if (a.phase == WeekPhase.review) {
      both(ws, (WorldGame w) => w.payBills());
      both(ws, (WorldGame w) => w.startWeek());
      both(ws, (WorldGame w) =>
          w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    }
    final BlockReason? block =
        a.canDo(WorldAction.job, id: jobId, variant: variant);
    if (block == null) return true;
    if (block.code == 'job.locked' || block.code == 'job.limit') return false;
    if (a.phase == WeekPhase.living) {
      both(ws, (WorldGame w) => w.sleep());
    }
  }
  return false;
}

/// Хорошая смена кассира в обоих мирах (+1 опыт).
void goodShift(WorldGame a, WorldGame b) {
  expect(readyFor(a, b, 'cashier'), isTrue);
  both(<WorldGame>[a, b], (WorldGame w) => w.completeJob('cashier', score: 1));
}

/// [livingTwins] и [goodShifts] хороших смен.
(WorldGame, WorldGame) twins(double growth, int goodShifts,
    {bool week = false}) {
  final (WorldGame a, WorldGame b) = livingTwins(growth, week: week);
  for (int i = 0; i < goodShifts; i++) {
    goodShift(a, b);
  }
  expect(a.snapshot.experience, goodShifts);
  expect(b.snapshot.experience, goodShifts);
  return (a, b);
}

/// Обычная смена [jobId] в обоих мирах: на сколько монет больше начислили
/// миру с прибавкой за опыт. Смена должна быть доступна (`canDo` == null).
int creditedXpCoins(WorldGame a, WorldGame b, String jobId,
    {String? variant}) {
  final WorldResult ra =
      ok(a.completeJob(jobId, variant: variant, score: 0));
  final WorldResult rb =
      ok(b.completeJob(jobId, variant: variant, score: 0));
  return ra.coins - rb.coins;
}

/// «1 монета / 2 монеты / 5 монет» — ожидание в тестах, своим кодом.
String coinsNom(int n) {
  final int m10 = n % 10, m100 = n % 100;
  if (m100 >= 11 && m100 <= 14) return 'монет';
  if (m10 == 1) return 'монета';
  if (m10 >= 2 && m10 <= 4) return 'монеты';
  return 'монет';
}
