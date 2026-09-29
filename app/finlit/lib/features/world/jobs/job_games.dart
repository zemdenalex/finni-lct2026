import 'package:flutter/foundation.dart';

import '../../../data/world_content.dart' show UniversityContent;

import 'games/cashier_game.dart';
import 'games/consultant_game.dart';
import 'games/courier_game.dart';
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
    this.university = UniversityContent.empty,
  });

  /// [jobs] — `jobs.json → jobs` по id профессии; [university] —
  /// `jobs.json → university` (карточки вуза на доске).
  factory JobGames.fromData(Map<String, Map<String, Object?>> jobs,
      {UniversityContent university = UniversityContent.empty}) {
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
      university: university,
    );
  }

  /// Вуз Финни: почему открыты финансовые работы и советы с источниками.
  final UniversityContent university;

  final CashierContent cashier;
  final ConsultantContent consultant;

  /// Помощник бухгалтера — игра консультанта со своим содержанием.
  final ConsultantContent accountant;
  final GardenerContent gardener;
  final CourierContent courier;
  final ProgrammerContent programmer;
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
