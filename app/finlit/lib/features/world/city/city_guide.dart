import 'package:flutter/foundation.dart';

import '../../../data/world_content.dart' show EconomyContent;
import '../../../domain/world/contract.dart';
import '../leisure/leisure_screen.dart';
import '../../../core/world_theme.dart';

/// Подсказки города: «Куда идти», зачем здание и почему оно сейчас закрыто
/// (`docs/final/gorod-audit.md`). Выключается
/// `--dart-define=city.guide=false` — город становится как на 145a127.
const bool cityGuideOn = bool.fromEnvironment('city.guide', defaultValue: true);

/// DEN-30, вариант A: подписи зданий — радиус шкалы [WorldRadii.tag], не
/// «пилюля». Флаг `economy.json → city.label_scale` (Денис 18.10 — включён):
/// `main.dart` ставит его из файла (`applyContentScreenFlags`). Не `const`:
/// тесты переключают его сами.
bool cityLabelScale = EconomyContent.cityLabelScaleDefault;

/// Куда идти сейчас: здание и короткая причина.
@immutable
class CityGuide {
  const CityGuide(this.buildingId, this.text, {this.event = false});

  /// Id здания из `cityBuildings`.
  final String buildingId;

  /// Причина со строчной буквы — идёт после названия здания: «Дом работы:
  /// не хватает 460 на счета». До двух строк в портрете.
  final String text;

  /// Там ждёт событие недели: касание ведёт в событие, а не в здание.
  final bool event;
}

/// Куда идти — тем же порядком, что «Сейчас: …» в комнате
/// (`room_screen.dart`, `_nextStep`): город продолжает комнату, а не спорит
/// с ней. Читает только фазу, снимок и отказы мира — правил не держит.
/// null — особой цели нет, город говорит обычную подсказку.
CityGuide? cityGuide(World w) {
  final ResourceSnapshot s = w.snapshot;
  switch (w.phase) {
    case WeekPhase.onboarding:
      return const CityGuide('home', 'сначала знакомство');
    case WeekPhase.weekStart:
      return const CityGuide('home', 'стипендия недели ждёт');
    case WeekPhase.planning:
      return const CityGuide('home', 'сначала план недели');
    case WeekPhase.review:
      return const CityGuide('home', 'неделя кончилась, итоги');
    case WeekPhase.living:
      break;
  }
  if (s.energy + 1e-9 < w.cheapestActionEnergy) {
    return const CityGuide('home', 'сил нет, пора спать');
  }
  final int money = s.need + s.want + s.free;
  // Как в комнате: не хватает на счета — на смену, даже если смены сейчас
  // закрыты (доска сама скажет почему).
  if (money < s.weeklyBill) {
    return CityGuide(
        'job-centre', 'не хватает ${s.weeklyBill - money} на счета');
  }
  final String? ev = w.eventBuildingId;
  if (ev != null) return CityGuide(ev, 'там что-то ждёт!', event: true);
  return null;
}

/// Зачем идти в здание — одной строкой, со строчной буквы: в TalkBack она
/// идёт после названия («Дом работы: смены и монеты»).
String cityPurpose(String id) => switch (id) {
      'home' => 'комната Финни',
      'grocery' => 'еда, уют и одежда',
      'job-centre' => 'смены и монеты',
      'pet-shop' => 'питомцы',
      'park' || 'cinema' => 'отдых, настроение лучше',
      'piggy-bank' => 'копилка и цель',
      _ => '',
    };

/// Почему главное дело здания сейчас нельзя сделать, или null — можно.
/// Вход в здание не запрещается: его экран объяснит подробнее.
///
/// Причины смен и отдыха — из мира ([JobOffer.blockReason], [World.canDo]),
/// фазовые — свои слова (у мира там «конверты», правило 1А).
String? cityClosedReason(World w, String id) {
  if (id == 'home' || id == 'piggy-bank') return null;
  switch (w.phase) {
    case WeekPhase.onboarding:
      return 'Откроется после знакомства.';
    case WeekPhase.weekStart || WeekPhase.planning:
      return 'Откроется после плана недели.';
    case WeekPhase.review:
      return 'Неделя кончилась — откроется в новую.';
    case WeekPhase.living:
      break;
  }
  switch (id) {
    case 'job-centre':
      final List<JobOffer> board = w.jobBoard;
      if (board.isEmpty || board.any((JobOffer o) => !o.blocked)) return null;
      // Постоянный замок («нужен транспорт») — не главная причина: сперва
      // то, что можно поправить (силы, смены).
      final JobOffer o = board.firstWhere((JobOffer o) => !o.locked,
          orElse: () => board.first);
      return o.blockReason?.text;
    case 'park' || 'cinema':
      final List<String> kinds = LeisureScreen.orderFor(id);
      final List<BlockReason?> why = <BlockReason?>[
        for (final String k in kinds) w.canDo(WorldAction.leisure, id: k),
      ];
      if (why.any((BlockReason? r) => r == null)) return null;
      return why.first?.text;
    default:
      return null;
  }
}
