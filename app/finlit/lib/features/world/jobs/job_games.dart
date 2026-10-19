import 'package:flutter/foundation.dart';

import '../../../data/world_content.dart'
    show EconomyContent, UniversityContent, mergeJobStage;

import 'games/cashier_game.dart';
import 'games/consultant_game.dart';
import 'games/courier_game.dart';
import 'games/dog_walker_game.dart';
import 'games/gardener_game.dart';
import 'games/programmer_game.dart';

/// Содержание мини-игр из `content/jobs.json → jobs` (ТЗ 2.5.14.1, 3.2.3):
/// товары, цены, заказы, карты, задачи и тексты. В коде — только правила
/// игр; новый товар, покупка или заказ — правка файла, а не кода.
///
/// Схему проверяет `WorldContent.parse` (ошибка с путём до поля, до
/// первого кадра), поэтому здесь данные только переводятся в типы. Приходят
/// сюда уже без ключей-комментариев (`_…`).
///
/// В приложение — через `Provider<JobGames>` (`main.dart`), в мини-игру —
/// через `MiniGameArgs.games`.
@immutable
class JobGames {
  const JobGames({
    required this.cashier,
    required this.consultant,
    required this.accountant,
    required this.gardener,
    required this.courier,
    required this.programmer,
    required this.dogWalker,
    this.university = UniversityContent.empty,
    this.shiftChoicesUi = false,
    this.dogWalkGame = EconomyContent.dogWalkGameDefault,
    Map<String, Map<String, Object?>>? raw,
  }) : _raw = raw;

  /// [jobs] — `jobs.json → jobs` по id профессии; [university] —
  /// `jobs.json → university` (карточки вуза на доске).
  factory JobGames.fromData(Map<String, Map<String, Object?>> jobs,
      {UniversityContent university = UniversityContent.empty,
      bool shiftChoicesUi = false,
      bool dogWalkGame = EconomyContent.dogWalkGameDefault}) {
    Map<String, Object?> of(String id) {
      final Map<String, Object?>? d = jobs[id];
      if (d == null) throw StateError('jobs.json: нет мини-игры «$id»');
      return d;
    }

    return JobGames(
      cashier: CashierContent.fromData(of('cashier')),
      consultant: ConsultantContent.fromData(of('consultant')),
      accountant: ConsultantContent.fromData(of('accountant')),
      gardener: GardenerContent.fromData(of('gardener')),
      courier: CourierContent.fromData(of('courier')),
      programmer: ProgrammerContent.fromData(of('programmer')),
      dogWalker: DogWalkContent.fromData(of('dog_walker')),
      university: university,
      shiftChoicesUi: shiftChoicesUi,
      dogWalkGame: dogWalkGame,
      raw: jobs,
    );
  }

  /// Поля `jobs.json → jobs` как пришли — из них [forStage] собирает ступени.
  final Map<String, Map<String, Object?>>? _raw;

  /// Содержание игр на ступени [stage] (C2): у работ с `stages` поля
  /// `stages[stage − 1]` ложатся поверх базовых; ступень 1 и null — базовое
  /// содержание как есть. Ступеней в файле меньше — берётся последняя.
  JobGames forStage(int? stage) {
    final Map<String, Map<String, Object?>>? raw = _raw;
    if (stage == null || stage <= 1 || raw == null) return this;
    return JobGames.fromData(<String, Map<String, Object?>>{
      for (final MapEntry<String, Map<String, Object?>> e in raw.entries)
        e.key: switch (e.value['stages']) {
          final List<Object?> s when s.isNotEmpty => mergeJobStage(e.value,
              s[(stage - 1).clamp(0, s.length - 1)]! as Map<String, Object?>),
          _ => e.value,
        },
    },
        university: university,
        shiftChoicesUi: shiftChoicesUi,
        dogWalkGame: dogWalkGame);
  }

  /// Вуз Финни: почему открыты финансовые работы и советы с источниками.
  final UniversityContent university;

  /// Показывать ли на экране смены мини-решение (`economy.json →
  /// day_cycle.shift_choices_ui`; нет ключа — false, экран как раньше).
  final bool shiftChoicesUi;

  /// Мини-игра выгульщика собак (`economy.json → day_cycle.dog_walk_game`);
  /// false — прежняя заглушка «Сделать» ([miniGameFor]).
  final bool dogWalkGame;

  final CashierContent cashier;
  final ConsultantContent consultant;

  /// Помощник бухгалтера — игра консультанта со своим содержанием.
  final ConsultantContent accountant;
  final GardenerContent gardener;
  final CourierContent courier;
  final ProgrammerContent programmer;
  final DogWalkContent dogWalker;
}

// Перевод проверенного JSON в типы. Числа — через `num`: `5` и `5.0` в
// файле равноправны.

typedef JobData = Map<String, Object?>;

String dStr(JobData d, String k) => d[k]! as String;

String? dStrOrNull(JobData d, String k) => d[k] as String?;

int dInt(JobData d, String k) => (d[k]! as num).toInt();

double dNum(JobData d, String k) => (d[k]! as num).toDouble();

bool dBool(JobData d, String k) => d[k]! as bool;

JobData dObj(JobData d, String k) => d[k]! as JobData;

List<JobData> dObjs(JobData d, String k) =>
    (d[k]! as List<Object?>).cast<JobData>();

List<String> dStrs(JobData d, String k) =>
    (d[k]! as List<Object?>).cast<String>();

List<int> dInts(JobData d, String k) =>
    (d[k]! as List<Object?>).map((Object? v) => (v! as num).toInt()).toList();

List<double> dNums(JobData d, String k) => (d[k]! as List<Object?>)
    .map((Object? v) => (v! as num).toDouble())
    .toList();
