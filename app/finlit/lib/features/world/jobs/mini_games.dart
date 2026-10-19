import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../domain/world/contract.dart'
    show FinniGender, OnboardingProgress;
import '../world_layout.dart';
import 'games/cashier_game.dart';
import 'games/consultant_game.dart';
import 'games/courier_game.dart';
import 'games/dog_walker_game.dart';
import 'games/gardener_game.dart';
import 'games/programmer_game.dart';
import 'job_games.dart';
import '../../../core/world_theme.dart';

/// Основной текст смены: в портрете крупный (`bodyLarge`), в альбомной —
/// [gameTextCompact], чтобы поле и кнопки влезли в 360 dp высоты.
TextStyle gameText(BuildContext context) => WorldLayout.isLandscape(context)
    ? gameTextCompact
    : Theme.of(context).textTheme.bodyLarge!;

/// 16 sp (минимум ТЗ 3.6.4) в любой ориентации — кеглем кнопок-вариантов
/// под текстом. Вопрос смены и ситуация урока в портрете: с нижним меню
/// (−60 dp) на 360×640 при шрифте 1,3 при 20 sp второй вариант уходил под
/// меню, а первый вариант урока — под строку «Уже утро»
/// (job_day_end_visible_test, lesson_fits_test).
const TextStyle gameTextCompact =
    TextStyle(fontSize: 16, height: 1.3, color: WorldColors.text);

/// Подпись узкой кнопки в альбомной. 🔴 Семейство — явно: в стилях
/// компонентов ThemeData.fontFamily не подставляется.
const TextStyle gameButtonText = TextStyle(
    fontFamily: AppType.family,
    fontFamilyFallback: AppType.fallback,
    fontSize: 16,
    fontWeight: FontWeight.w700);

/// Высота главной кнопки смены: в альбомной 48 dp (минимум ТЗ), иначе 64.
double gameButtonHeight(BuildContext context) =>
    WorldLayout.isLandscape(context) ? 48 : TapSize.primary;

/// Панели смены в альбомной: слева поле или числа, справа действия
/// (и, если задана, средняя панель).
///
/// Высота ограничена (экран смены в альбомной) — каждая панель с
/// [GamePane.scroll] прокручивается сама, и поле не уезжает вместе с
/// кнопками; без [GamePane.scroll] панель получает всю высоту и сама решает,
/// как в неё уложиться. Высота не ограничена (игра внутри прокрутки) —
/// панели своей высоты, по верху.
class GameSplit extends StatelessWidget {
  const GameSplit({super.key, required this.panes});

  final List<GamePane> panes;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final bool bounded = box.hasBoundedHeight;
          return Row(
            crossAxisAlignment:
                bounded ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < panes.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: Gap.md),
                _pane(panes[i], bounded),
              ],
            ],
          );
        },
      );

  Widget _pane(GamePane p, bool bounded) {
    final Widget body =
        bounded && p.scroll ? SingleChildScrollView(child: p.child) : p.child;
    return p.width != null
        ? SizedBox(width: p.width, child: body)
        : Expanded(flex: p.flex, child: body);
  }
}

/// Одна панель [GameSplit]: доля ширины или точная ширина.
@immutable
class GamePane {
  const GamePane(this.child, {this.flex = 1, this.width, this.scroll = true});

  final Widget child;
  final int flex;
  final double? width;
  final bool scroll;
}

/// Игра кончилась: оценка эффективности 0..1.
///
/// 🔴 Оценка влияет только на бонус сверху — ставка с карточки не
/// уменьшается от ошибок (`docs/game/job-cashier.md`, P4).
typedef MiniGameDone = void Function(double score);

/// Что экран смены передаёт мини-игре.
@immutable
class MiniGameArgs {
  const MiniGameArgs({
    required this.jobId,
    required this.games,
    required this.onDone,
    this.variant,
    this.round = 0,
    this.heroName = OnboardingProgress.defaultFinniName,
    this.heroGender,
  });

  final String jobId;

  /// Имя и пол героя из знакомства — для итога смены в его роде
  /// (правило 5Б, [heroGendered]).
  final String heroName;
  final FinniGender? heroGender;

  /// Содержание всех мини-игр из `jobs.json` — игра берёт своё.
  final JobGames games;

  /// Уровень (курьер, программист) или null.
  final String? variant;

  /// Номер раунда для выбора контента «по кругу» (опыт = число смен).
  final int round;

  /// Вызвать один раз, когда ребёнок закончил смену.
  final MiniGameDone onDone;
}

typedef MiniGameBuilder = Widget Function(
    BuildContext context, MiniGameArgs args);

/// Запись реестра: подсказка «?» и сама игра.
@immutable
class MiniGame {
  const MiniGame({required this.help, required this.build});

  /// Текст «Как играть» для кнопки «?».
  final String help;

  final MiniGameBuilder build;
}

/// Реестр мини-игр по `jobId`. Новая работа — одна запись здесь и один файл
/// в `games/<job>_game.dart`. Нет записи — [placeholderGame].
const Map<String, MiniGame> miniGames = <String, MiniGame>{
  'cashier': MiniGame(help: cashierHelp, build: buildCashierGame),
  'consultant': MiniGame(help: consultantHelp, build: buildConsultantGame),
  'accountant': MiniGame(help: accountantHelp, build: buildAccountantGame),
  'gardener': MiniGame(help: gardenerHelp, build: buildGardenerGame),
  'courier': MiniGame(help: courierHelp, build: buildCourierGame),
  'programmer': MiniGame(help: programmerHelp, build: buildProgrammerGame),
  'dog_walker': MiniGame(help: dogWalkerHelp, build: buildDogWalkerGame),
};

/// Игра для работы без своей мини-игры: одна кнопка «Сделать» (оценка 1).
const MiniGame placeholderGame = MiniGame(
  help: 'Эта работа простая: нажми «Сделать» — и смена готова.',
  build: _buildPlaceholder,
);

/// Игра работы [jobId]. Выгульщик собак при выключенном флаге
/// `day_cycle.dog_walk_game` ([JobGames.dogWalkGame]) — снова заглушка.
MiniGame miniGameFor(String jobId, JobGames games) =>
    jobId == 'dog_walker' && !games.dogWalkGame
        ? placeholderGame
        : miniGames[jobId] ?? placeholderGame;

Widget _buildPlaceholder(BuildContext context, MiniGameArgs args) =>
    _PlaceholderGame(args: args);

class _PlaceholderGame extends StatelessWidget {
  const _PlaceholderGame({required this.args});

  final MiniGameArgs args;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Работа простая: нажми «Сделать» — и смена готова.',
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: Gap.md),
          FilledButton.icon(
            key: const ValueKey<String>('game:placeholder:do'),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(TapSize.primary)),
            onPressed: () => args.onDone(1),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Сделать'),
          ),
        ],
      );
}
