import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';

/// Быстрая раскладка монет недели: удержание «−»/«+», ввод числа и совет
/// Финни — общие для сценки плана в знакомстве, листа плана из комнаты и
/// копилки.
///
/// Денис, чат 1898, 17.10: «нельзя зажать или ввести самому или сделать
/// рекомендованное, нажимать сейчас 74 раза просто чтобы распределить деньги
/// это ужас».

/// Удержание «−»/«+»: когда начинается повтор и как разгоняется.
///
/// Касание — один шаг. Удержание: через [delay] — шаг, дальше шаг каждые
/// [every]; с [x5After] от касания — по 5 шагов, с [x10After] — по 10.
/// 820 монет раскладываются удержанием за ~2,7 с (а не 82 касания).
abstract final class HoldRepeat {
  static const Duration delay = Duration(milliseconds: 400);
  static const Duration every = Duration(milliseconds: 120);
  static const Duration x5After = Duration(milliseconds: 1200);
  static const Duration x10After = Duration(milliseconds: 2500);

  /// Во сколько шагов повтор, когда палец держат [held] от касания.
  static int timesAt(Duration held) => held >= x10After
      ? 10
      : held >= x5After
          ? 5
          : 1;

  /// Сколько держат к повтору номер [tick] (0 — первый, на [delay]).
  /// Считаем по номеру тика, а не по часам: в тестах время ненастоящее.
  static Duration heldAt(int tick) => delay + every * tick;
}

/// Новая сумма строки: [value] + [delta], но не меньше нуля и не больше
/// [max] (в строке не может быть больше, чем в ней было, плюс остаток).
int stepAmount(int value, int delta, int max) =>
    (value + delta).clamp(0, max < 0 ? 0 : max);

/// Кнопка «−» или «+» строки плана: касание — шаг, удержание — повтор с
/// разгоном ([HoldRepeat]) до границы (0 или остаток).
///
/// Повтор останавливается, когда отпустили, палец ушёл с кнопки, сумма
/// дошла до границы или кнопку убрали с экрана. Для TalkBack — обычная
/// кнопка с подписью [label]: касание — один шаг, как раньше.
class HoldStepButton extends StatefulWidget {
  const HoldStepButton({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.max,
    required this.step,
    required this.up,
    required this.onChanged,
    this.onBlocked,
    this.outlined = true,
  });

  final IconData icon;
  final String label;
  final int value;

  /// Больше этого в строке быть не может: сколько в ней + остаток.
  final int max;
  final int step;

  /// «+» (true) или «−».
  final bool up;
  final ValueChanged<int> onChanged;

  /// «+» уже некуда: что сказать ребёнку (строка «На неделю» трясётся).
  /// null — кнопка на границе погашена.
  final VoidCallback? onBlocked;

  /// Контурная круглая (план) или плоская (лист плана).
  final bool outlined;

  @override
  State<HoldStepButton> createState() => _HoldStepButtonState();
}

class _HoldStepButtonState extends State<HoldStepButton> {
  Timer? _timer;
  int _tick = 0;

  /// Сумма во время удержания: родитель перестраивается не на каждый тик,
  /// поэтому шаг считается от неё, а не от [HoldStepButton.value].
  int _live = 0;

  bool get _canStep => widget.up ? widget.value < widget.max : widget.value > 0;

  int _next(int from, int times) =>
      stepAmount(from, (widget.up ? 1 : -1) * widget.step * times, widget.max);

  /// Шаг × [times]; false — сумма упёрлась в границу.
  bool _apply(int times) {
    final int next = _next(_live, times);
    if (next == _live) return false;
    _live = next;
    widget.onChanged(next);
    return next != 0 && next != widget.max;
  }

  void _start(LongPressStartDetails _) {
    _stop();
    if (!_canStep) {
      widget.onBlocked?.call();
      return;
    }
    _live = widget.value;
    _tick = 0;
    if (!_apply(1)) return;
    _timer = Timer.periodic(HoldRepeat.every, (Timer t) {
      _tick++;
      if (!mounted || !_apply(HoldRepeat.timesAt(HoldRepeat.heldAt(_tick)))) {
        _stop();
      }
    });
  }

  void _move(LongPressMoveUpdateDetails d) {
    final Size? size = context.size;
    if (size != null && !(Offset.zero & size).contains(d.localPosition)) {
      _stop();
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VoidCallback? tap = _canStep
        ? () => widget.onChanged(_next(widget.value, 1))
        : widget.onBlocked;
    final Widget button = widget.outlined
        ? IconButton.outlined(
            tooltip: widget.label,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            iconSize: 24,
            icon: Icon(widget.icon),
            onPressed: tap,
          )
        : IconButton(
            tooltip: widget.label,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(widget.icon),
            onPressed: tap,
          );
    if (tap == null) return button;
    return RawGestureDetector(
      // Удержание берёт касание раньше, чем подсказка (0,5 с) и чем
      // отпускание: лишнего шага при отпускании нет.
      gestures: <Type, GestureRecognizerFactory>{
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(
              duration: HoldRepeat.delay, debugOwner: this),
          (LongPressGestureRecognizer r) => r
            ..onLongPressStart = _start
            ..onLongPressMoveUpdate = _move
            ..onLongPressEnd = ((_) => _stop())
            ..onLongPressCancel = _stop,
        ),
      },
      // TalkBack видит только кнопку: касание — один шаг.
      excludeFromSemantics: true,
      child: button,
    );
  }
}

/// Число в строке плана — касание открывает ввод с цифровой клавиатуры.
class AmountTap extends StatelessWidget {
  const AmountTap({
    super.key,
    required this.title,
    required this.value,
    required this.max,
    required this.onChanged,
    required this.child,
    this.semantic = true,
    this.alignment = Alignment.center,
  });

  /// false — касание только для пальца, TalkBack его не видит: узкое число
  /// в альбомной (34 dp) — рядом есть цель ввода 48 dp (заголовок строки).
  final bool semantic;
  final AlignmentGeometry alignment;

  /// Название строки: «Нужное», «Хочу», «Копилка».
  final String title;
  final int value;

  /// Больше нельзя: сколько в строке + остаток.
  final int max;
  final ValueChanged<int> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Widget tap = InkWell(
      borderRadius: BorderRadius.circular(WorldRadii.button),
      onTap: () => _open(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Align(alignment: alignment, widthFactor: 1, child: child),
      ),
    );
    if (!semantic) return ExcludeSemantics(child: tap);
    return Semantics(
      button: true,
      // Не «Нужное: …»: эта подпись у строки с её суммой.
      label: 'Ввести число, $title — $value',
      excludeSemantics: true,
      onTap: () => _open(context),
      child: tap,
    );
  }

  Future<void> _open(BuildContext context) async {
    final int? v =
        await showAmountInput(context, title: title, value: value, max: max);
    if (v != null && v != value) onChanged(v);
  }
}

/// Ввод суммы строки с цифровой клавиатуры: от 0 до [max]. Ввели больше —
/// в поле сразу встаёт [max] и подсказка «Столько нет». null — отмена.
Future<int?> showAmountInput(
  BuildContext context, {
  required String title,
  required int value,
  required int max,
}) =>
    showDialog<int>(
      context: context,
      builder: (BuildContext c) =>
          _AmountDialog(title: title, value: value, max: max),
    );

class _AmountDialog extends StatefulWidget {
  const _AmountDialog(
      {required this.title, required this.value, required this.max});

  final String title;
  final int value;
  final int max;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  // Сумма уже выделена: первая же цифра её заменяет.
  late final TextEditingController _c = () {
    final String t = widget.value > 0 ? '${widget.value}' : '';
    return TextEditingController.fromValue(TextEditingValue(
        text: t,
        selection: TextSelection(baseOffset: 0, extentOffset: t.length)));
  }();
  bool _capped = false;

  int get _amount => int.tryParse(_c.text) ?? 0;

  void _changed(String s) {
    final int v = int.tryParse(s) ?? 0;
    final bool over = v > widget.max;
    if (over) {
      final String m = '${widget.max}';
      _c.value = TextEditingValue(
          text: m, selection: TextSelection.collapsed(offset: m.length));
    }
    if (over != _capped) setState(() => _capped = over);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() => Navigator.of(context).pop(_amount.clamp(0, widget.max));

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Сколько положить в «${widget.title}»?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                key: const ValueKey<String>('amount:field'),
                controller: _c,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: AppType.number(24, color: WorldColors.text),
                decoration: InputDecoration(
                  hintText: '0',
                  helperText: 'Можно от 0 до ${widget.max}',
                ),
                onChanged: _changed,
                onSubmitted: (_) => _done(),
              ),
              if (_capped) ...<Widget>[
                const SizedBox(height: Gap.xs),
                Text(
                  'Столько нет — поставили всё, что осталось.',
                  key: const ValueKey<String>('amount:capped'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: WorldColors.wants),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey<String>('amount:ok'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _done,
            child: const Text('Готово'),
          ),
        ],
      );
}

/// Совет Финни по плану: счета недели — в «Нужное», остальное делится
/// долями ([wantPercent] в «Хочу», прочее — в «Копилку»).
///
/// 🟡 Доли — методическое допущение (по умолчанию 30 / 70), в
/// `onboarding.json → plan_advice`; проверяет Настя.
class PlanAdvice {
  const PlanAdvice({this.wantPercent = 30});

  /// Сколько процентов из того, что осталось после счетов, — в «Хочу».
  final int wantPercent;
}

/// Раскладка по совету: весь остаток ([pool] минус уже положенное)
/// раскладывается, уже положенное ребёнком не уменьшается.
///
/// «Нужное» добирается до счетов [bill], округлённых вверх до [step] (иначе
/// сразу после совета — «Нужное меньше счёта»). Из остального в «Хочу» —
/// [PlanAdvice.wantPercent] %, вниз до [step]; всё прочее — в «Копилку».
/// Сумма трёх строк всегда равна [pool].
({int need, int want, int goal}) advisePlan({
  required int pool,
  required int bill,
  required int step,
  required PlanAdvice advice,
  int need = 0,
  int want = 0,
  int goal = 0,
}) {
  int rest = pool - need - want - goal;
  if (rest <= 0) return (need: need, want: want, goal: goal);
  final int s = step > 0 ? step : 1;
  final int billUp = (bill + s - 1) ~/ s * s;
  final int addNeed = (billUp - need).clamp(0, rest);
  rest -= addNeed;
  final int addWant = (rest * advice.wantPercent ~/ 100) ~/ s * s;
  return (
    need: need + addNeed,
    want: want + addWant,
    goal: goal + rest - addWant,
  );
}

/// Кнопка «Как советует Финни» над строками плана: одно касание
/// раскладывает весь остаток ([advisePlan]).
class PlanAdviceButton extends StatelessWidget {
  const PlanAdviceButton(
      {super.key, required this.name, this.onPressed, this.compact = false});

  /// Имя Финни, которое дал ребёнок.
  final String name;

  /// null — раскладывать нечего (кнопка погашена).
  final VoidCallback? onPressed;

  /// Альбомная: делит строку с «Не разложено» — шрифт мельче.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color c = onPressed == null ? WorldColors.textSoft : WorldColors.gold;
    return OutlinedButton.icon(
      key: const ValueKey<String>('plan:advice'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
        foregroundColor: WorldColors.gold,
        // Погашена — без золотой рамки: не путать с живой кнопкой.
        side: BorderSide(
            color: onPressed == null ? WorldColors.line : WorldColors.gold,
            width: 1.5),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorldRadii.button)),
      ),
      onPressed: onPressed,
      icon: Pictogram(Pic.bulb, size: compact ? 18 : 20, color: c),
      label: Text('Как советует $name',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: compact ? 14 : 16, fontWeight: FontWeight.w700)),
    );
  }
}
