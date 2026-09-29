import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/feel.dart';
import '../../../../core/theme.dart';
import '../../world_layout.dart';
import '../job_games.dart';
import '../mini_games.dart';
import '../../../../core/world_theme.dart';

/// Программист: собрать программу из блоков для городского устройства,
/// запустить, найти шаг с ошибкой, исправить (`docs/game/job-programmer.md`).
///
/// Задачи — `content/jobs.json → jobs.programmer.tasks` ([ProgrammerContent]):
/// устройство, цель, палитра блоков, решение, подсказка. Уровень берётся из
/// `variant` (easy / medium / hard).
///
/// Проверка — симуляция: устройство выполняет программу ребёнка и программу
/// из `solution` по шагу; первый шаг, где состояния разошлись, подсвечивается
/// и объясняется. Строки ответа не сравниваются.
///
/// 🟡 Как устройство исполняет блоки (светофор, двор робота, полив) — код,
/// по id задачи ([programmerDevices]). Новые тексты, палитра и решение для
/// этих устройств — правка файла; новое устройство — правка кода.
@immutable
class ProgCommand {
  const ProgCommand(this.id, this.label, this.icon);

  factory ProgCommand.fromData(JobData d) {
    final String id = dStr(d, 'id');
    return ProgCommand(
        id, dStr(d, 'label'), _commandIcons[id] ?? Icons.widgets_rounded);
  }

  final String id;
  final String label;
  final IconData icon;
}

/// Картинка блока по id; блок без своей — общая.
const Map<String, IconData> _commandIcons = <String, IconData>{
  'red': Icons.circle,
  'yellow': Icons.circle,
  'green': Icons.circle,
  'fwd': Icons.arrow_upward_rounded,
  'left': Icons.turn_left_rounded,
  'right': Icons.turn_right_rounded,
  'drop': Icons.inventory_2_rounded,
  'open': Icons.water_rounded,
  'water1': Icons.water_drop_rounded,
  'turn': Icons.rotate_right_rounded,
  'water2': Icons.water_drop_outlined,
  'close': Icons.block_rounded,
  'pump_off': Icons.power_settings_new,
  'extra_music': Icons.music_note_rounded,
};

@immutable
class ProgTask {
  const ProgTask({
    required this.id,
    required this.tier,
    required this.device,
    required this.goal,
    required this.palette,
    required this.solution,
    required this.hint,
  });

  factory ProgTask.fromData(JobData d) => ProgTask(
        id: dStr(d, 'id'),
        tier: dStr(d, 'tier'),
        device: dStr(d, 'device'),
        goal: dStr(d, 'goal'),
        palette: dObjs(d, 'blocks').map(ProgCommand.fromData).toList(),
        solution: dStrs(d, 'solution'),
        hint: dStr(d, 'hint_on_error'),
      );

  final String id;
  final String tier;
  final String device;
  final String goal;
  final List<ProgCommand> palette;
  final List<String> solution;
  final String hint;

  ProgCommand command(String id) =>
      palette.firstWhere((ProgCommand c) => c.id == id);
}

/// `jobs.json → jobs.programmer`.
@immutable
class ProgrammerContent {
  const ProgrammerContent({required this.tasks});

  factory ProgrammerContent.fromData(JobData d) => ProgrammerContent(
      tasks: dObjs(d, 'tasks').map(ProgTask.fromData).toList());

  final List<ProgTask> tasks;

  /// Задача по уровню; неизвестный или null — первая (лёгкая).
  ProgTask taskFor(String? variant) => tasks
      .firstWhere((ProgTask t) => t.tier == variant, orElse: () => tasks.first);
}

/// Устройства, которые умеет исполнять симуляция: id задачи в `jobs.json`
/// обязан быть одним из них.
const Set<String> programmerDevices = <String>{
  'traffic_light',
  'robot_delivery',
  'garden_watering',
};

const String programmerHelp = 'Прочитай, что должно сделать устройство. '
    'Нажимай блоки команд — они встают в программу по порядку. Лишний блок '
    'можно убрать, нажав на него в программе. Нажми «Запуск»: устройство '
    'выполнит команды по одной. Если что-то пошло не так, увидишь, на каком '
    'шаге и почему, — исправь и запусти снова. Таймера нет, оплата от ошибок '
    'не уменьшается.';

Widget buildProgrammerGame(BuildContext context, MiniGameArgs args) =>
    ProgrammerGame(
        content: args.games.programmer,
        variant: args.variant,
        onDone: args.onDone);

// ─────────────────────────── симуляция ───────────────────────────

/// Состояние устройства после шага. [key] сравнивается с эталоном,
/// [text] — что произошло, словами.
@immutable
class ProgFrame {
  const ProgFrame(this.key, this.text, this.state);

  final String key;
  final String text;
  final Object state;
}

/// Робот: клетка, куда смотрит (0 — вверх, 1 — вправо, 2 — вниз, 3 — влево),
/// отдал ли посылку.
typedef RobotState = ({int r, int c, int dir, bool dropped});

/// Двор робота: `#` стена, `D` подъезд, `S` старт (смотрит вверх).
const List<String> robotYard = <String>[
  '###',
  '.D#',
  '.##',
  'S..',
];

/// Полив: кран, куда смотрит шланг, политы ли грядки, насос, музыка.
typedef GardenState = ({
  bool tap,
  int hose,
  bool bed1,
  bool bed2,
  bool pump,
  bool music,
});

/// Прогон программы: кадр 0 — начальное состояние, дальше по кадру на шаг.
List<ProgFrame> programmerRun(ProgTask task, List<String> program) =>
    switch (task.id) {
      'traffic_light' => _runLight(program),
      'robot_delivery' => _runRobot(program),
      _ => _runGarden(program),
    };

const Map<String, String> _lightNames = <String, String>{
  'red': 'красный',
  'yellow': 'жёлтый',
  'green': 'зелёный',
};

List<ProgFrame> _runLight(List<String> program) => <ProgFrame>[
      const ProgFrame('off', 'светофор выключен', ''),
      for (final String id in program)
        ProgFrame(id, 'загорелся ${_lightNames[id]}', id),
    ];

bool _yardOpen(int r, int c) =>
    r >= 0 &&
    c >= 0 &&
    r < robotYard.length &&
    c < robotYard[r].length &&
    robotYard[r][c] != '#';

List<ProgFrame> _runRobot(List<String> program) {
  RobotState s = (r: 3, c: 0, dir: 0, dropped: false);
  String key(RobotState s) => '${s.r},${s.c},${s.dir},${s.dropped}';
  final List<ProgFrame> out = <ProgFrame>[
    ProgFrame(key(s), 'робот стоит на старте', s),
  ];
  const List<(int, int)> step = <(int, int)>[(-1, 0), (0, 1), (1, 0), (0, -1)];
  for (final String id in program) {
    String text;
    switch (id) {
      case 'fwd':
        final int r = s.r + step[s.dir].$1;
        final int c = s.c + step[s.dir].$2;
        if (_yardOpen(r, c)) {
          s = (r: r, c: c, dir: s.dir, dropped: s.dropped);
          text = 'робот проехал клетку вперёд';
        } else {
          text = 'робот упёрся в стену и остался на месте';
        }
      case 'left':
        s = (r: s.r, c: s.c, dir: (s.dir + 3) % 4, dropped: s.dropped);
        text = 'робот повернул налево';
      case 'right':
        s = (r: s.r, c: s.c, dir: (s.dir + 1) % 4, dropped: s.dropped);
        text = 'робот повернул направо';
      default:
        final bool door = robotYard[s.r][s.c] == 'D';
        s = (r: s.r, c: s.c, dir: s.dir, dropped: true);
        text = door
            ? 'робот отдал посылку у подъезда'
            : 'робот отдал посылку, но подъезда тут нет';
    }
    out.add(ProgFrame(key(s), text, s));
  }
  return out;
}

List<ProgFrame> _runGarden(List<String> program) {
  GardenState s = (
    tap: false,
    hose: 1,
    bed1: false,
    bed2: false,
    pump: true,
    music: false,
  );
  String key(GardenState s) =>
      '${s.tap},${s.hose},${s.bed1},${s.bed2},${s.pump},${s.music}';
  final List<ProgFrame> out = <ProgFrame>[
    ProgFrame(key(s), 'кран закрыт, насос работает', s),
  ];
  for (final String id in program) {
    String text;
    switch (id) {
      case 'open':
        s = (
          tap: true,
          hose: s.hose,
          bed1: s.bed1,
          bed2: s.bed2,
          pump: s.pump,
          music: s.music
        );
        text = 'кран открыт';
      case 'water1' || 'water2':
        final int bed = id == 'water1' ? 1 : 2;
        if (!s.tap) {
          text = 'вода не течёт — кран закрыт';
        } else if (!s.pump) {
          text = 'вода не течёт — насос выключен';
        } else if (s.hose != bed) {
          text = 'шланг смотрит на грядку ${s.hose}, а не на $bed';
        } else {
          s = (
            tap: s.tap,
            hose: s.hose,
            bed1: s.bed1 || bed == 1,
            bed2: s.bed2 || bed == 2,
            pump: s.pump,
            music: s.music
          );
          text = 'грядка $bed полита';
        }
      case 'turn':
        s = (
          tap: s.tap,
          hose: s.hose == 1 ? 2 : 1,
          bed1: s.bed1,
          bed2: s.bed2,
          pump: s.pump,
          music: s.music
        );
        text = 'шланг смотрит на грядку ${s.hose}';
      case 'close':
        s = (
          tap: false,
          hose: s.hose,
          bed1: s.bed1,
          bed2: s.bed2,
          pump: s.pump,
          music: s.music
        );
        text = 'кран закрыт';
      case 'pump_off':
        s = (
          tap: s.tap,
          hose: s.hose,
          bed1: s.bed1,
          bed2: s.bed2,
          pump: false,
          music: s.music
        );
        text = 'насос выключен';
      default:
        s = (
          tap: s.tap,
          hose: s.hose,
          bed1: s.bed1,
          bed2: s.bed2,
          pump: s.pump,
          music: true
        );
        text = 'заиграла музыка — поливу она не нужна';
    }
    out.add(ProgFrame(key(s), text, s));
  }
  return out;
}

/// Первый шаг (с 1), где программа разошлась с эталоном; null — совпала.
int? programmerFirstMismatch(ProgTask task, List<String> program) {
  final List<ProgFrame> got = programmerRun(task, program);
  final List<ProgFrame> want = programmerRun(task, task.solution);
  for (int i = 1; i < want.length; i++) {
    if (i >= got.length || got[i].key != want[i].key) return i;
  }
  return got.length > want.length ? want.length : null;
}

// ─────────────────────────── экран ───────────────────────────

class ProgrammerGame extends StatefulWidget {
  const ProgrammerGame({
    super.key,
    required this.content,
    this.variant,
    required this.onDone,
  });

  final ProgrammerContent content;
  final String? variant;
  final MiniGameDone onDone;

  @override
  State<ProgrammerGame> createState() => _ProgrammerGameState();
}

class _ProgrammerGameState extends State<ProgrammerGame>
    with SingleTickerProviderStateMixin {
  late final ProgTask _task = widget.content.taskFor(widget.variant);
  // 🔴 Создаётся в initState, а не лениво: иначе выход из игры без единого
  // действия создавал контроллер прямо в dispose (ассерт «deactivated»).
  late final AnimationController _play;
  final List<String> _program = <String>[];
  int _runs = 0;
  bool _sent = false;

  /// Кадры текущего запуска и показанный кадр.
  List<ProgFrame>? _frames;
  int _shown = 0;

  /// Итог запуска (после анимации): null — ещё не запускали.
  int? _mismatch;
  bool _checked = false;

  int get _slots => _task.solution.length;
  bool get _solved => _checked && _mismatch == null;

  @override
  void initState() {
    super.initState();
    _play = AnimationController(vsync: this)..addListener(_onPlay);
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  void _onPlay() {
    final List<ProgFrame>? f = _frames;
    if (f == null) return;
    final int i = (_play.value * (f.length - 1)).floor();
    if (i != _shown) setState(() => _shown = i);
  }

  void _edit(VoidCallback change) => setState(() {
        change();
        _checked = false;
        _mismatch = null;
        _frames = null;
        _shown = 0;
        _play.stop();
      });

  void _add(String id) {
    if (_program.length >= _slots) return;
    _edit(() => _program.add(id));
  }

  void _removeAt(int i) => _edit(() => _program.removeAt(i));

  Future<void> _run() async {
    final int? miss = programmerFirstMismatch(_task, _program);
    final List<ProgFrame> all = programmerRun(_task, _program);
    // Показываем шаги до первой ошибки включительно.
    final int last = miss == null
        ? all.length - 1
        : (miss < all.length ? miss : all.length - 1);
    final List<ProgFrame> frames = all.sublist(0, last + 1);
    setState(() {
      _runs++;
      _frames = frames;
      _shown = 0;
      _checked = false;
      _mismatch = null;
    });
    _play.duration =
        context.motion(Duration(milliseconds: 450 * (frames.length - 1)));
    await _play.forward(from: 0).orCancel.catchError((Object _) {});
    if (!mounted || _frames != frames) return;
    setState(() {
      _shown = frames.length - 1;
      _checked = true;
      _mismatch = miss;
    });
    if (miss == null) unawaited(context.cue(Cue.done));
  }

  void _done() {
    if (_sent) return;
    _sent = true;
    widget.onDone(1 / (_runs < 1 ? 1 : _runs));
  }

  String _feedback() {
    final int? miss = _mismatch;
    if (miss == null) {
      return 'Всё сработало! ${_task.device} работает как надо.';
    }
    final List<ProgFrame> want = programmerRun(_task, _task.solution);
    final List<ProgFrame> got = programmerRun(_task, _program);
    final String should = want[miss].text;
    if (miss >= got.length) {
      return 'Шаг $miss: команды нет, а нужно, чтобы $should. '
          'Добавь блок. ${_task.hint}';
    }
    return 'Шаг $miss: ${got[miss].text}. А нужно, чтобы $should. '
        'Нажми на этот блок, чтобы убрать его, и поставь другой. '
        '${_task.hint}';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool land = WorldLayout.isLandscape(context);
    final List<ProgFrame> preview =
        _frames ?? programmerRun(_task, const <String>[]);
    final ProgFrame frame = preview[_shown.clamp(0, preview.length - 1)];
    final bool running = _frames != null && !_checked;
    final Widget goal =
        Text(_task.goal, style: land ? gameText(context) : text.bodyMedium);
    final Widget device =
        _DeviceView(task: _task, frame: frame, cell: land ? 36 : 48);
    final Widget programTitle = Text('Программа: ${_program.length} из $_slots',
        style: text.titleSmall);
    final List<Widget> slots = <Widget>[
      for (int i = 0; i < _slots; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.xs),
          child: _Slot(
            key: ValueKey<String>('programmer:slot:$i'),
            index: i,
            command: i < _program.length ? _task.command(_program[i]) : null,
            wrong: _checked && _mismatch == i + 1,
            onTap: i < _program.length && !_solved && !running
                ? () => _removeAt(i)
                : null,
          ),
        ),
    ];
    final Widget? feedback = !_checked
        ? null
        : _Box(
            key: const ValueKey<String>('programmer:feedback'),
            color: _solved ? WorldColors.needsBg : WorldColors.wantsBg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(_solved ? Icons.check_circle_rounded : Icons.info_rounded,
                    color: _solved ? WorldColors.needs : WorldColors.wants),
                const SizedBox(width: Gap.sm),
                Expanded(child: Text(_feedback(), style: gameText(context))),
              ],
            ),
          );
    final double h = land ? 48 : TapSize.min;
    final Widget done = FilledButton.icon(
      key: const ValueKey<String>('programmer:done'),
      style: FilledButton.styleFrom(
          minimumSize: Size.fromHeight(gameButtonHeight(context))),
      onPressed: _done,
      icon: const Icon(Icons.flag_rounded),
      label: const Text('Закончить смену'),
    );
    final Widget clear = OutlinedButton.icon(
      key: const ValueKey<String>('programmer:clear'),
      style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(h)),
      onPressed:
          _program.isEmpty || running ? null : () => _edit(_program.clear),
      icon: const Icon(Icons.delete_sweep_rounded),
      label: const Text('Очистить'),
    );
    final Widget run = FilledButton.icon(
      key: const ValueKey<String>('programmer:run'),
      style: FilledButton.styleFrom(minimumSize: Size.fromHeight(h)),
      onPressed: _program.isEmpty || running ? null : _run,
      icon: const Icon(Icons.play_arrow_rounded),
      label: const Text('Запуск'),
    );
    Widget block(ProgCommand c) => OutlinedButton.icon(
          key: ValueKey<String>('programmer:cmd:${c.id}'),
          style: OutlinedButton.styleFrom(
            minimumSize: land
                ? const Size.fromHeight(48)
                : const Size(TapSize.min, TapSize.min),
            padding:
                land ? const EdgeInsets.symmetric(horizontal: Gap.sm) : null,
            alignment: land ? Alignment.centerLeft : null,
            textStyle: land ? gameButtonText : null,
          ),
          onPressed:
              _program.length < _slots && !running ? () => _add(c.id) : null,
          icon: Icon(c.icon, color: _commandColor(c.id)),
          label: Text(c.label),
        );
    final Widget blocksTitle = Text('Блоки команд', style: text.titleSmall);

    if (land) {
      // Альбомная, три панели: задание и устройство слева, программа
      // посередине, запуск и блоки справа. После запуска вместо задания —
      // что пошло не так: задание вернётся, как только программу поправят.
      return GameSplit(panes: <GamePane>[
        GamePane(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(_task.device, style: text.titleMedium),
              const SizedBox(height: Gap.xs),
              feedback ?? goal,
              const SizedBox(height: Gap.sm),
              device,
            ],
          ),
          flex: 7,
        ),
        GamePane(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              programTitle,
              const SizedBox(height: Gap.xs),
              ...slots,
            ],
          ),
          flex: 6,
        ),
        GamePane(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_solved)
                done
              else ...<Widget>[
                run,
                const SizedBox(height: Gap.xs),
                clear,
                const SizedBox(height: Gap.sm),
                blocksTitle,
                const SizedBox(height: Gap.xs),
                for (final ProgCommand c in _task.palette)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.xs),
                    child: block(c),
                  ),
              ],
            ],
          ),
          flex: 5,
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(_task.device, style: text.titleMedium),
              const SizedBox(height: Gap.xs),
              goal,
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        device,
        const SizedBox(height: Gap.sm),
        programTitle,
        const SizedBox(height: Gap.xs),
        ...slots,
        if (feedback != null) ...<Widget>[
          const SizedBox(height: Gap.xs),
          feedback,
        ],
        const SizedBox(height: Gap.sm),
        if (_solved)
          done
        else ...<Widget>[
          blocksTitle,
          const SizedBox(height: Gap.xs),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: <Widget>[
              for (final ProgCommand c in _task.palette) block(c),
            ],
          ),
          const SizedBox(height: Gap.md),
          Row(
            children: <Widget>[
              Expanded(child: clear),
              const SizedBox(width: Gap.sm),
              Expanded(child: run),
            ],
          ),
        ],
      ],
    );
  }
}

Color? _commandColor(String id) => switch (id) {
      'red' => const Color(0xFFD83A3A),
      'yellow' => WorldColors.gold,
      'green' => WorldColors.needs,
      _ => null,
    };

class _Slot extends StatelessWidget {
  const _Slot({
    super.key,
    required this.index,
    required this.command,
    required this.wrong,
    this.onTap,
  });

  final int index;
  final ProgCommand? command;
  final bool wrong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ProgCommand? c = command;
    return Material(
      color: wrong
          ? WorldColors.wantsBg
          : (c == null ? WorldColors.raised : WorldColors.panel),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
        side: BorderSide(
            color: wrong ? WorldColors.wants : WorldColors.line,
            width: wrong ? 3 : 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.chip),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minHeight: WorldLayout.isLandscape(context) ? 48 : TapSize.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
            child: Row(
              children: <Widget>[
                Text('${index + 1}.',
                    style: AppType.number(18, color: WorldColors.text)),
                const SizedBox(width: Gap.sm),
                if (c != null) ...<Widget>[
                  Icon(c.icon, color: _commandColor(c.id)),
                  const SizedBox(width: Gap.xs),
                ],
                Expanded(
                  child: Text(
                    c?.label ?? 'пусто',
                    style: WorldLayout.isLandscape(context)
                        ? gameText(context)
                        : Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (wrong)
                  const Icon(Icons.error_rounded, color: WorldColors.wants)
                else if (c != null && onTap != null)
                  const Icon(Icons.close_rounded, color: WorldColors.textSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Устройство в кадре: светофор, двор с роботом или полив.
class _DeviceView extends StatelessWidget {
  const _DeviceView({required this.task, required this.frame, this.cell = 48});

  final ProgTask task;
  final ProgFrame frame;

  /// Клетка двора робота: 48 dp, в альбомной меньше (поле — не кнопки).
  final double cell;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Widget body = switch (frame.state) {
      final RobotState s => _yard(s),
      final GardenState s => _garden(s),
      final String lit => _light(lit),
      _ => const SizedBox.shrink(),
    };
    return _Box(
      key: const ValueKey<String>('programmer:device'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(child: body),
          const SizedBox(height: Gap.xs),
          Text(
            key: const ValueKey<String>('programmer:now'),
            'Сейчас: ${frame.text}',
            style: WorldLayout.isLandscape(context)
                ? gameText(context)
                : text.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _light(String lit) => Wrap(
        alignment: WrapAlignment.center,
        children: <Widget>[
          for (final String id in const <String>['red', 'yellow', 'green'])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
              child: Column(
                children: <Widget>[
                  Icon(
                    lit == id ? Icons.circle : Icons.circle_outlined,
                    size: 40,
                    color: lit == id ? _commandColor(id) : WorldColors.textSoft,
                  ),
                  Text(
                    lit == id ? 'горит' : _lightNames[id]!,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
        ],
      );

  static const List<IconData> _arrows = <IconData>[
    Icons.arrow_upward_rounded,
    Icons.arrow_forward_rounded,
    Icons.arrow_downward_rounded,
    Icons.arrow_back_rounded,
  ];

  Widget _yard(RobotState s) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int r = 0; r < robotYard.length; r++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int c = 0; c < robotYard[r].length; c++)
                  Container(
                    width: cell,
                    height: cell,
                    decoration: BoxDecoration(
                      color: robotYard[r][c] == '#'
                          ? SceneColors.wall
                          : (robotYard[r][c] == 'D'
                              ? WorldColors.goalBg
                              : WorldColors.panel),
                      border: Border.all(color: WorldColors.line),
                    ),
                    child: s.r == r && s.c == c
                        ? Icon(
                            s.dropped
                                ? Icons.check_circle_rounded
                                : _arrows[s.dir],
                            color: WorldColors.text,
                            size: cell * 2 / 3,
                          )
                        : robotYard[r][c] == '#'
                            ? const Icon(Icons.house_rounded,
                                color: SceneColors.barkDark)
                            : robotYard[r][c] == 'D'
                                ? const Icon(Icons.door_front_door_rounded,
                                    color: WorldColors.goal)
                                : null,
                  ),
              ],
            ),
        ],
      );

  Widget _garden(GardenState s) {
    Widget chip(IconData icon, String label, bool on) => Padding(
          padding: const EdgeInsets.all(2),
          child: Chip(
            // Сведения, не кнопка: в альбомной — без поля под палец.
            materialTapTargetSize:
                cell < 48 ? MaterialTapTargetSize.shrinkWrap : null,
            visualDensity: cell < 48 ? VisualDensity.compact : null,
            avatar: Icon(icon,
                color: on ? WorldColors.needs : WorldColors.textSoft, size: 20),
            label: Text(label, style: const TextStyle(fontSize: 16)),
          ),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      children: <Widget>[
        chip(Icons.water_rounded, s.tap ? 'кран открыт' : 'кран закрыт', s.tap),
        chip(Icons.rotate_right_rounded, 'шланг → грядка ${s.hose}', true),
        chip(Icons.water_drop_rounded,
            s.bed1 ? 'грядка 1 полита' : 'грядка 1 сухая', s.bed1),
        chip(Icons.water_drop_rounded,
            s.bed2 ? 'грядка 2 полита' : 'грядка 2 сухая', s.bed2),
        chip(Icons.power_settings_new,
            s.pump ? 'насос работает' : 'насос выключен', !s.pump),
        if (s.music) chip(Icons.music_note_rounded, 'музыка', false),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({super.key, required this.child, this.color = WorldColors.panel});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: WorldColors.line, width: 1.5),
        ),
        child: Padding(padding: const EdgeInsets.all(Gap.sm), child: child),
      );
}
