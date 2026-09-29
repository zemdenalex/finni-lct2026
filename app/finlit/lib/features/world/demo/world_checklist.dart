/// Чек-лист эксперта по Приложению А ТЗ — на новом мире (S16).
///
/// Порт `features/demo/expert_checklist.dart` со старого `Game` на [World].
/// 🟡 Контракт не отдаёт журнал: отметки выводятся из снимка и, если он
/// есть, из списка видов записей ([kinds]) — имена видов из журнала
/// `WorldGame`. Без [kinds] часть шагов доказывается косвенно по снимку, и
/// это написано в `evidence`.
library;

import '../../../domain/world/contract.dart';
import '../review/week_review_screen.dart';
import '../world_routes.dart';

/// Откуда отметка: приложение доказывает шаг само или смотрит эксперт.
enum WorldCheckSource { ledger, snapshot, expert }

class WorldCheckPart {
  const WorldCheckPart(this.title, {required this.done});

  final String title;
  final bool done;
}

class WorldCheckStep {
  const WorldCheckStep({
    required this.no,
    required this.title,
    required this.source,
    required this.evidence,
    required this.done,
    this.route,
    this.parts = const <WorldCheckPart>[],
  });

  final int no;
  final String title;
  final WorldCheckSource source;
  final String evidence;
  final bool done;
  final String? route;
  final List<WorldCheckPart> parts;

  String get statusLabel => done ? 'Выполнено' : 'Ещё не выполнено';

  String get sourceLabel => switch (source) {
        WorldCheckSource.ledger => 'по журналу',
        WorldCheckSource.snapshot => 'по ресурсам',
        WorldCheckSource.expert => 'подтверждает эксперт',
      };
}

/// Что экран знает о сеансе сверх мира: сброс и заход во «Взрослым»
/// в журнал не попадают (сброс его очищает).
class WorldDemoSession {
  WorldDemoSession._();

  /// Игру начинали заново в этом сеансе (прогресс стёрт).
  static bool resetDone = false;

  /// Раздел взрослого открывался (барьер пройден) в этом сеансе.
  static bool adultOpened = false;

  static void clear() {
    resetDone = false;
    adultOpened = false;
  }
}

abstract final class WorldChecklist {
  static List<WorldCheckStep> of({
    required ResourceSnapshot snapshot,
    required WeekPhase phase,
    required String finniName,
    Set<String>? kinds,
    bool resetDone = false,
    bool adultOpened = false,
  }) {
    final ResourceSnapshot s = snapshot;
    final bool started = s.weekNo > 0;
    final bool hasLog = kinds != null;
    bool has(Enum k) => kinds?.contains(k.name) ?? false;
    WorldCheckSource src(WorldCheckSource ifLog) =>
        hasLog ? ifLog : WorldCheckSource.snapshot;

    final bool planned = kinds != null
        ? kinds.contains('planConfirmed')
        : phase == WeekPhase.living ||
            phase == WeekPhase.review ||
            s.weekNo > 1;
    final bool earned = s.experience > 0 || has(WorldLedgerKind.jobPayout);
    final bool billPaid = has(WorldLedgerKind.billPaid) || s.weekNo > 1;
    final bool boughtWant = has(WorldLedgerKind.itemOwned) ||
        has(WorldLedgerKind.leisure) ||
        s.owned.any((String id) => !_goalPrefixes.any(id.startsWith));
    final bool goalChosen = s.activeGoalId != null ||
        s.owned.any((String id) => _goalPrefixes.any(id.startsWith));
    final bool deposited = kinds != null
        ? has(WorldLedgerKind.goalSliderDeposit) ||
            (kinds.contains('planConfirmed') && s.goal > 0)
        : s.goal > 0;
    final bool reviewed = phase == WeekPhase.review || s.weekNo > 1;
    final bool nextWeek = s.weekNo > 1;

    return <WorldCheckStep>[
      WorldCheckStep(
        no: 1,
        title: 'Установка и первый запуск; знакомство с целью игры и тремя '
            'типами решений',
        source: WorldCheckSource.expert,
        evidence: started
            ? 'Первая неделя началась. Цель игры и три конверта Финни '
                'объясняет в сценках в комнате после ника и облика, '
                'оцените глазами.'
            : 'Игра ещё не начиналась: онбординг не пройден.',
        done: started,
        route: WorldRoutes.onboarding,
      ),
      const WorldCheckStep(
        no: 2,
        title: 'Создание локального профиля без реального имени, телефона '
            'и e-mail',
        source: WorldCheckSource.snapshot,
        evidence: 'В профиле нового мира только ник, вид и облик Финни — '
            'полей для имени, телефона и e-mail нет.',
        done: true,
        route: WorldRoutes.onboarding,
      ),
      WorldCheckStep(
        no: 3,
        title: 'Выбор внешнего вида питомца, настройка и игровое имя',
        source: WorldCheckSource.expert,
        evidence: started
            ? 'Облик выбран, имя героя — «$finniName».'
            : 'Онбординг ещё не пройден.',
        done: started && finniName.trim().isNotEmpty,
        route: WorldRoutes.onboarding,
      ),
      WorldCheckStep(
        no: 4,
        title: 'Получение стартового бюджета; текущая цель и доступные задания',
        source: src(WorldCheckSource.ledger),
        evidence: started
            ? 'Карманные первой недели и подарок в копилку начислены.'
            : 'Карманных ещё не было.',
        done: started || has(WorldLedgerKind.weekStarted),
        route: WorldRoutes.jobs,
      ),
      WorldCheckStep(
        no: 5,
        title: 'Распределение средств на обязательные и необязательные '
            'расходы, накопления',
        source: src(WorldCheckSource.ledger),
        evidence: planned
            ? 'План недели подтверждён: карманные разложены по НУЖНО / ХОЧУ / '
                'ЦЕЛЬ.'
            : 'Плана недели ещё не было.',
        done: planned,
        route: WorldRoutes.room,
      ),
      WorldCheckStep(
        no: 6,
        title: 'Выполнение задания и получение игровой валюты',
        source: src(WorldCheckSource.ledger),
        evidence: earned
            ? 'Смен сделано: ${s.experience}. Оплата пришла в кошелёк.'
            : 'Смен ещё не было.',
        done: earned,
        route: WorldRoutes.jobs,
      ),
      WorldCheckStep(
        no: 7,
        title: 'Обязательная и необязательная покупка — минимум по одной '
            'каждого типа, включая попытку покупки при нехватке средств',
        source: WorldCheckSource.expert,
        evidence: 'Попытка при нехватке — отказ «Не хватает N»: мир ничего '
            'не записывает при отказе, поэтому этот подшаг подтверждает '
            'эксперт на экране магазина. Отметка ставится по двум покупкам.',
        done: billPaid && boughtWant,
        parts: <WorldCheckPart>[
          WorldCheckPart('Обязательное: счета недели оплачены', done: billPaid),
          WorldCheckPart('Необязательное: вещь, декор или досуг',
              done: boughtWant),
          const WorldCheckPart('Попытка при нехватке — смотрит эксперт',
              done: false),
        ],
        route: WorldRoutes.shop,
      ),
      WorldCheckStep(
        no: 8,
        title: 'Выбор финансовой цели и пополнение накоплений',
        source: src(WorldCheckSource.ledger),
        evidence: goalChosen
            ? 'Цель выбрана. В копилке ${s.goal}.'
            : 'Цель ещё не выбрана.',
        done: goalChosen && deposited,
        parts: <WorldCheckPart>[
          WorldCheckPart('Цель выбрана', done: goalChosen),
          WorldCheckPart('Копилка пополнена', done: deposited),
        ],
        route: WorldRoutes.piggy,
      ),
      WorldCheckStep(
        no: 9,
        title: 'Обратная связь о балансе, выполнении плана и состоянии '
            'питомца',
        source: src(WorldCheckSource.ledger),
        evidence: reviewed
            ? 'Неделя закрывалась: экран итогов показывает счета, очки роста '
                'и настроение.'
            : 'Ни одна неделя ещё не закрывалась.',
        done: reviewed,
        route: WorldRoutes.review,
      ),
      WorldCheckStep(
        no: 10,
        title: 'Переход к следующему игровому периоду; изменение прогресса '
            'или стадии развития',
        source: WorldCheckSource.snapshot,
        evidence: nextWeek
            ? 'Идёт неделя № ${s.weekNo}. Очков роста ${s.growthPoints}, '
                'стадия: ${stageTitle(s.stage)}.'
            : 'Игра всё ещё на первой неделе.',
        done: nextWeek,
        route: WorldRoutes.room,
      ),
      const WorldCheckStep(
        no: 11,
        title: 'Закрытие и повторный запуск приложения',
        source: WorldCheckSource.expert,
        evidence: 'Мир сохраняется на устройстве после каждого действия — '
            'журнал и знакомство. Закройте приложение и откройте снова: '
            'неделя, монеты, копилка и покупки на месте.',
        done: false,
      ),
      // Заголовок — формулировка пункта 12 Приложения А ТЗ. У нового мира
      // отдельного тестового профиля нет: «сброс» — это «Начать игру
      // заново», он стирает единственное сохранение.
      WorldCheckStep(
        no: 12,
        title: 'Переход в раздел для взрослого, удаление или сброс тестового '
            'профиля',
        source: WorldCheckSource.snapshot,
        evidence: resetDone
            ? 'Игра начиналась заново в этом сеансе (прогресс стёрт).'
            : adultOpened
                ? 'Раздел для взрослого открывался; заново игру ещё не начинали.'
                : 'Раздел для взрослого ещё не открывался.',
        done: resetDone,
        parts: <WorldCheckPart>[
          WorldCheckPart('Раздел взрослого открыт', done: adultOpened),
          WorldCheckPart('Игра начата заново', done: resetDone),
        ],
        route: WorldRoutes.adult,
      ),
    ];
  }

  static int doneCount(List<WorldCheckStep> steps) =>
      steps.where((WorldCheckStep s) => s.done).length;

  /// Цели (питомцы, транспорт, жильё) отличаются от вещей по префиксу id.
  static const List<String> _goalPrefixes = <String>[
    'pet_',
    'transport_',
    'home_',
  ];
}

/// Название стадии — решение Дениса 28.09 (`economy.json →
/// growth.stages[].name`), как на итогах недели.
String stageTitle(WorldStage s) => WeekReviewScreen.stageName(s);
