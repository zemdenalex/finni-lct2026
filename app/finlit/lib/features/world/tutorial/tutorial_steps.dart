import 'package:flutter/foundation.dart';

import '../../../domain/phrases.dart';
import '../../../domain/world/contract.dart';

/// Предмет комнаты, о котором сейчас шаг обучалки (`door`, `piggy`…):
/// камера комнаты держит его целиком в кадре (на 360 dp дверь иначе
/// срезана краем экрана). null — шага нет или он не о предмете.
final ValueNotifier<String?> tutorialRoomFocus = ValueNotifier<String?>(null);

/// Предмет комнаты по ключу цели шага: `room:door` → `door`.
String? roomObjectOfTarget(String key) => switch (key) {
      'room:door' => 'door',
      'room:piggy' => 'piggy',
      'room:bed' => 'bed',
      'room:fridge' => 'fridge',
      'room:desk' => 'desk',
      _ => null,
    };

/// Как показывать обучалку первого захода (D6, страница
/// `docs/final/tutorial/`). Вид выбирает Денис.
enum TutorialLook {
  /// Обучалки нет — первый заход как сдано.
  off,

  /// T1: экран затемнён, светится то, о чём речь; карточка с Финни.
  spotlight,

  /// T2: панель-диалог снизу, цель обведена рамкой, без затемнения.
  dialog,

  /// T3: короткие подсказки на месте, игра не останавливается.
  hints,
}

/// 🔴 Флаг обучалки — ОДНА строка. `off` — первый заход как сдано.
/// Включить: `TutorialLook.spotlight` (T1, рекомендация), `dialog` (T2),
/// `hints` (T3). Не `const`: тесты переключают вид сами.
TutorialLook tutorialLook = TutorialLook.off;

/// Вид обучалки по флагу контента `day_cycle.tutorial_ui` (C4): включён —
/// T1 (затемнение и карточка с Финни, рекомендация DEN-4), выключен — нет
/// обучалки. `main.dart` ставит [tutorialLook] отсюда до первого кадра.
TutorialLook tutorialLookFor({required bool tutorialUi}) =>
    tutorialUi ? TutorialLook.spotlight : TutorialLook.off;

/// Слова, которые ещё не выбраны окончательно (решение «опыт или звёзды»,
/// `formulirovki-reshenija-nasti.md`, правило 2). Меняются здесь — и во всех
/// репликах обучалки сразу.
abstract final class TutorialWords {
  /// Что растёт за хорошо сделанные смены (сейчас в игре — «опыт»).
  static const String xp = 'опыт';

  /// То же в родительном падеже: «прибавка …».
  static const String xpOf = 'опыта';
}

/// Шаг обучалки: что подсветить и что сказать.
class TutorialStep {
  const TutorialStep({
    required this.id,
    required this.targets,
    required this.say,
    required this.short,
  });

  /// Устойчивое имя шага — для тестов и журнала.
  final String id;

  /// `ValueKey<String>` того, что светится: первый найденный на экране
  /// (разделы комнаты бывают в два набора — `RoomScreen.threeTabs`). Ни
  /// одного нет — карточка без подсветки.
  final List<String> targets;

  /// Реплика Финни (T1, T2).
  final String Function(World w) say;

  /// Короткая подсказка на месте (T3).
  final String Function(World w) short;
}

/// Сколько обычно уходит на еду за неделю: домашнее блюдо × приёмы недели —
/// та же сумма входит в счета, которые называет шаг про аренду.
int weeklyFoodCost(World w) {
  final ResourceSnapshot s = w.snapshot;
  final String? food = s.foodId;
  final int price = food == null ? 0 : (w.catalogItem(food)?.price ?? 0);
  return price * s.mealsPerWeek;
}

/// Деньги, которые можно тратить на счета: НУЖНО + ХОЧУ + кошелёк (как
/// подсказка «Сейчас» в комнате).
int _money(ResourceSnapshot s) => s.need + s.want + s.free;

/// Шаги первого захода. Созвон 15.10 (привет, аренда, магазин) + замечания
/// эксперта 16.10 (№ 4 «что такое опыт», № 5 «настроение влияет на оплату»).
final List<TutorialStep> tutorialSteps = <TutorialStep>[
  TutorialStep(
    id: 'hello',
    targets: <String>['room:finni'],
    // Без рода: Финни бывает мальчиком и девочкой (= D3, баг-прогон 18.10).
    say: (World w) => 'Привет! Я ${w.onboarding.finniName}. Это мой дом — '
        'теперь я тут живу. Поможешь?',
    short: (_) => 'Это я. Нажми на меня — я обрадуюсь',
  ),
  TutorialStep(
    id: 'rent',
    targets: <String>['room:door'],
    say: (World w) {
      final ResourceSnapshot s = w.snapshot;
      final int short = s.weeklyBill - _money(s);
      // Коротко: на 360 dp при шрифте ×1,3 карточка под дверью не влезала
      // (обучалка на макете Алины, 18.10). Два предложения, без рода.
      return 'Тук-тук, это хозяйка! За жильё и еду — ${s.weeklyBill} '
          '${Phrases.coinsNom(s.weeklyBill)} '
          'в конце недели. '
          '${short > 0 ? 'Не хватает $short — заработаем на смене.' : 'Отложим их первыми.'}';
    },
    short: (World w) => 'Счета недели — ${w.snapshot.weeklyBill}',
  ),
  TutorialStep(
    id: 'shop',
    targets: <String>['room:nav:shop', 'room:nav:city'],
    say: (World w) => 'Еда нужна каждый день. Обычно на неделю уходит '
        'около ${weeklyFoodCost(w)} монет. Магазин — в городе.',
    short: (World w) => 'Еда — около ${weeklyFoodCost(w)} в неделю',
  ),
  TutorialStep(
    id: 'xp',
    targets: <String>['room:nav:jobs', 'room:nav:city'],
    say: (_) => 'В городе — работа. За смену платят монеты. Сделаешь смену '
        'хорошо — растёт ${TutorialWords.xp}, и следующие смены платят '
        'чуть больше.',
    short: (_) => 'Хорошая смена — больше ${TutorialWords.xpOf}',
  ),
  TutorialStep(
    id: 'mood',
    targets: <String>['hud:happiness'],
    say: (_) => 'Это моё настроение. Когда оно хорошее, за смену платят '
        'больше, а когда плохое — меньше. Гладь меня, отдыхай и иногда балуй.',
    short: (_) => 'Хорошее настроение — больше монет',
  ),
  TutorialStep(
    id: 'done',
    targets: <String>['room:help'],
    say: (_) => 'Дальше — твой ход! Что непонятно, жми «?» наверху.',
    short: (_) => 'Подсказки — здесь',
  ),
];

/// Первый заход в комнату: знакомство пройдено, идёт первый день первой
/// недели, и ребёнок ещё ничего не сделал. Правило выводится из мира, а не
/// хранится: после сброса обучалка покажется снова, а после первой смены
/// или еды — больше никогда.
bool isFirstVisit(World w) {
  final ResourceSnapshot s = w.snapshot;
  return w.onboarding.done &&
      w.phase == WeekPhase.living &&
      s.weekNo == 1 &&
      s.dayInWeek <= 1 &&
      s.shiftsThisWeek == 0 &&
      s.mealsThisWeek == 0;
}
