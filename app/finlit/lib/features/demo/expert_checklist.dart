import '../../domain/game.dart';
import '../../domain/ledger/ledger_entry.dart';
import '../../domain/models/envelope.dart';
import '../../routes.dart';

/// Откуда берётся отметка о выполнении шага.
///
/// 🔴 Различие подписано в интерфейсе. Чеклист, который сам себе ставит
/// галочки без объяснения, — это не проверка, а декорация: эксперт обязан
/// видеть, что именно доказывает отметку.
enum CheckSource {
  /// Выведено из журнала или профиля — приложение доказывает шаг само.
  ledger,

  /// Приложение показывает признак, но подтверждает шаг эксперт глазами.
  expert,
}

/// Подшаг составного шага — например, три вида покупок в шаге 7.
class CheckPart {
  const CheckPart(this.title, {required this.done});

  final String title;
  final bool done;
}

/// Один шаг Приложения А ТЗ.
class ExpertStep {
  const ExpertStep({
    required this.no,
    required this.title,
    required this.source,
    required this.evidence,
    required this.done,
    this.route,
    this.parts = const <CheckPart>[],
  });

  /// Номер шага в Приложении А.
  final int no;

  /// Формулировка шага — из Приложения А, дословно.
  final String title;

  final CheckSource source;

  /// Чем именно доказан (или не доказан) шаг. Текст для эксперта.
  final String evidence;

  final bool done;

  /// Маршрут, на котором шаг воспроизводится. null — шаг без экрана
  /// (например, перезапуск приложения).
  final String? route;

  final List<CheckPart> parts;

  /// Подпись словами. §3.6.5: цвет и иконка не единственные носители смысла.
  String get statusLabel => done ? 'Выполнено' : 'Ещё не выполнено';
}

/// Чеклист экспертной проверки (§2.5.13.2, Приложение А ТЗ).
///
/// Здесь нет игровой логики: только чтение журнала и профиля. Что означает
/// каждая запись, решил домен — см. [LedgerKind].
abstract final class ExpertChecklist {
  /// Собирает все 12 шагов по текущему состоянию игры.
  ///
  /// [demoResetWasDone] — эксперт нажимал «Сбросить тестовый профиль» в этом
  /// сеансе. Факт сброса в журнале не остаётся по определению (журнал
  /// очищается), поэтому его приносит экран.
  static List<ExpertStep> of(Game g, {bool demoResetWasDone = false}) {
    final List<LedgerEntry> led = g.ledger;

    bool has(LedgerKind k) =>
        led.any((LedgerEntry e) => e.kind == k);
    bool bought(Envelope envelope) => led.any((LedgerEntry e) =>
        e.kind == LedgerKind.purchase && e.envelope == envelope);

    final Set<int> periodsInLedger =
        led.map((LedgerEntry e) => e.periodNo).toSet();
    final bool started = led.isNotEmpty;
    final bool petReady = g.profile.petName.trim().isNotEmpty;

    final bool boughtNeed = bought(Envelope.needs);
    final bool boughtWant = bought(Envelope.wants);
    final bool triedWithoutMoney = has(LedgerKind.purchaseDeclined);

    return <ExpertStep>[
      ExpertStep(
        no: 1,
        title: 'Установка и первый запуск; знакомство с целью игры и тремя '
            'типами решений',
        source: CheckSource.expert,
        evidence: started
            ? 'Игра начата: в журнале есть записи. Знакомство с целью и '
                'тремя решениями — экран приветствия, оцените глазами.'
            : 'Журнал пуст: игра ещё не начиналась.',
        done: started,
        route: AppRoutes.onboarding,
      ),
      ExpertStep(
        no: 2,
        title: 'Создание локального профиля без реального имени, телефона '
            'и e-mail',
        source: CheckSource.ledger,
        // Не «мы их не спрашиваем», а «их негде хранить»: в GameProfile
        // физически нет таких полей, и §3.5.1 выполняется по устройству
        // данных, а не по дисциплине разработчика.
        evidence: 'В профиле нет полей для имени, телефона и e-mail — '
            'хранить их некуда. Профиль лежит в одном файле на устройстве.',
        done: true,
        route: AppRoutes.petCreate,
      ),
      ExpertStep(
        no: 3,
        title: 'Выбор внешнего вида питомца, настройка и игровое имя',
        source: CheckSource.ledger,
        evidence: petReady
            ? 'Питомец назван: «${g.profile.petName}», '
                '${g.profile.species.title.toLowerCase()}, '
                '${g.profile.palette.title.toLowerCase()}.'
            : 'Имя питомца пустое — экран создания не пройден.',
        done: petReady,
        route: AppRoutes.petCreate,
      ),
      ExpertStep(
        no: 4,
        title: 'Получение стартового бюджета; текущая цель и доступные задания',
        source: CheckSource.ledger,
        evidence: has(LedgerKind.pocketMoney)
            ? 'В журнале есть начисление карманных.'
            : 'Начисления карманных в журнале нет.',
        done: has(LedgerKind.pocketMoney),
        route: AppRoutes.home,
      ),
      ExpertStep(
        no: 5,
        title: 'Распределение средств на обязательные и необязательные '
            'расходы, накопления',
        source: CheckSource.ledger,
        evidence: has(LedgerKind.planConfirmed)
            ? 'План на неделю подтверждён: монетки разложены по трём '
                'конвертам.'
            : 'Подтверждённого плана в журнале нет.',
        done: has(LedgerKind.planConfirmed),
        route: AppRoutes.plan,
      ),
      ExpertStep(
        no: 6,
        title: 'Выполнение задания и получение игровой валюты',
        source: CheckSource.ledger,
        evidence: has(LedgerKind.taskReward)
            ? 'Есть награда за выполненное задание.'
            : 'Выполненных заданий в журнале нет.',
        done: has(LedgerKind.taskReward),
        route: AppRoutes.tasks,
      ),
      ExpertStep(
        no: 7,
        title: 'Обязательная и необязательная покупка — минимум по одной '
            'каждого типа, включая попытку покупки при нехватке средств',
        source: CheckSource.ledger,
        evidence: 'Попытка при нехватке монеток тоже записывается в журнал '
            'отдельным видом записи — поэтому засчитывается сама.',
        done: boughtNeed && boughtWant && triedWithoutMoney,
        parts: <CheckPart>[
          CheckPart('Покупка из «Нужного»', done: boughtNeed),
          CheckPart('Покупка из «Хочу»', done: boughtWant),
          CheckPart('Попытка при нехватке монеток', done: triedWithoutMoney),
        ],
        route: AppRoutes.shop,
      ),
      ExpertStep(
        no: 8,
        title: 'Выбор финансовой цели и пополнение накоплений',
        source: CheckSource.ledger,
        evidence: g.profile.goalId == null
            ? 'Цель не выбрана.'
            : has(LedgerKind.savingsDeposit)
                ? 'Цель выбрана, взносы в копилку есть.'
                : 'Цель выбрана, но взносов в копилку ещё не было.',
        done: g.profile.goalId != null && has(LedgerKind.savingsDeposit),
        parts: <CheckPart>[
          CheckPart('Цель выбрана', done: g.profile.goalId != null),
          CheckPart('Копилка пополнена',
              done: has(LedgerKind.savingsDeposit)),
        ],
        route: AppRoutes.savings,
      ),
      ExpertStep(
        no: 9,
        title: 'Обратная связь о балансе, выполнении плана и состоянии '
            'питомца',
        source: CheckSource.ledger,
        evidence: has(LedgerKind.periodClosed)
            ? 'Неделя закрывалась: экран итогов показывает очки заботы, '
                'план против факта и состояние Финни.'
            : 'Ни одна неделя ещё не закрывалась.',
        done: has(LedgerKind.periodClosed),
        route: AppRoutes.progress,
      ),
      ExpertStep(
        no: 10,
        title: 'Переход к следующему игровому периоду; изменение прогресса '
            'или стадии развития',
        source: CheckSource.ledger,
        evidence: has(LedgerKind.periodClosed) && g.periodNo > 1
            ? 'Идёт неделя № ${g.periodNo}. Стадия Финни: '
                '${g.snapshot.stage.title}, очков заботы '
                '${g.snapshot.carePoints}.'
            : 'Игра всё ещё на первой неделе.',
        done: has(LedgerKind.periodClosed) && g.periodNo > 1,
        route: AppRoutes.home,
      ),
      ExpertStep(
        no: 11,
        title: 'Закрытие и повторный запуск приложения',
        source: CheckSource.expert,
        // Признак косвенный и честно назван косвенным: записи более чем
        // одной недели означают, что профиль переживал сохранения. Сам факт
        // перезапуска приложение о себе знать не может — его подтверждает
        // эксперт, закрыв и открыв приложение.
        evidence: periodsInLedger.length > 1
            ? 'В журнале записи ${periodsInLedger.length} игровых недель — '
                'профиль сохраняется и восстанавливается. Закройте и '
                'откройте приложение, чтобы убедиться лично.'
            : 'Пока записи только одной недели. Закройте и откройте '
                'приложение: журнал и баланс должны остаться прежними.',
        done: periodsInLedger.length > 1,
      ),
      ExpertStep(
        no: 12,
        title: 'Переход в раздел для взрослого, удаление или сброс тестового '
            'профиля',
        source: CheckSource.ledger,
        evidence: g.profile.parentUnlockedTasks > 0
            ? 'Взрослый открывал дополнительное задание — значит, в разделе '
                'для взрослого он был.'
            : demoResetWasDone
                ? 'Тестовый профиль сбрасывался в этом сеансе.'
                : 'Раздел для взрослого ещё не использовался.',
        done: g.profile.parentUnlockedTasks > 0 || demoResetWasDone,
        route: AppRoutes.adult,
      ),
    ];
  }

  static int doneCount(List<ExpertStep> steps) =>
      steps.where((ExpertStep s) => s.done).length;
}
