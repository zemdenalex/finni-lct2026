import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';

import 'world_harness.dart';

String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

/// Конфиг сборки (7 дней) с флагом `bank.transfer`: [on] null — как в файле.
WorldConfig bankConfig({bool? on}) {
  final Map<String, Object?> e =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  if (on != null) {
    e['bank'] = <String, Object?>{
      ...?(e['bank'] as Map<String, Object?>?),
      'transfer': on,
    };
  }
  return worldConfigFromContent(WorldContent.parse(
    economy: jsonEncode(e),
    jobs: _read('jobs.json'),
    events: _read('events.json'),
    roomItems: _read('room_items.json'),
  ));
}

/// Мир сборки после знакомства: неделя 1 идёт, во всех трёх частях есть
/// монеты. План: в «Нужное» ровно счёт недели (семья не нужна), остаток — в
/// «Хочу» (80 на числах сборки); подарок 200 уже в копилке. [on] — флаг
/// `bank.transfer`.
WorldGame bankWorld({
  bool? on = true,
  OnboardingProgress onboarding =
      const OnboardingProgress(step: OnboardingProgress.stepDone),
  OnboardingSave? saveOnboarding,
}) {
  final WorldGame w = WorldGame(
      config: bankConfig(on: on),
      onboarding: onboarding,
      saveOnboarding: saveOnboarding);
  ok(w.startWeek());
  final int u = w.snapshot.unallocated;
  final int bill = w.snapshot.weeklyBill;
  ok(w.plan(needs: bill, wants: u - bill, goal: 0));
  return w;
}
