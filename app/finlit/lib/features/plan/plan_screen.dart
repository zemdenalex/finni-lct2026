import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/feel.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/world_art.dart';
import '../../domain/economy/finni_habits.dart';
import '../../domain/economy/period_rules.dart';
import '../../domain/game.dart';
import '../../domain/ledger/ledger_fold.dart';
import '../../domain/models/envelope.dart';
import '../../domain/models/pet.dart';
import '../tasks/task_kit.dart';
import 'plan_hints.dart';

/// План бюджета (§2.5.5).
///
/// Экран живёт в двух состояниях, и переключает их не вкладка, а сама игра:
/// пока план не подтверждён — раскладка монеток (§2.5.5.1–2), после
/// подтверждения — сравнение плана с фактом (§2.5.5.3).
class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    if (!app.ready) {
      return const Scaffold(body: Center(child: Text('Финни')));
    }

    final Game g = app.game;
    final Allocation? plan = g.currentPlan;

    return Scaffold(
      appBar: AppBar(title: Text('План на неделю ${g.periodNo}')),
      body: SafeArea(
        child: plan == null
            ? _Editor(
                available: g.snapshot.wallet.unallocated,
                previous: g.profile.plans[g.periodNo - 1],
                // Обещание стадии «Хранитель копилки»: Финни раскладывает
                // сам — так, как обычно раскладывает ребёнок.
                proposal: g.snapshot.stage == PetStage.planner
                    ? FinniHabits.propose(
                        plans: g.profile.plans,
                        periodNo: g.periodNo,
                        available: g.snapshot.wallet.unallocated,
                      )
                    : null,
                minNeeds: cheapestNeedsBasket(app.content),
                onConfirm: (Allocation draft) => _confirm(context, app, draft),
              )
            : _PlanVsFact(
                plan: plan,
                fact: LedgerFold.factOfPeriod(g.ledger, g.periodNo),
                tolerance: app.content.economy.planTolerance,
              ),
      ),
    );
  }

  /// §2.5.5.3: подтверждение плана.
  ///
  /// Действие принадлежит экрану, а не редактору: сразу после подтверждения
  /// редактор исчезает (на его месте — сравнение с фактом), и его контекст
  /// становится непригодным для показа карточки последствия.
  Future<void> _confirm(
    BuildContext context,
    AppState app,
    Allocation draft,
  ) async {
    final NavigatorState nav = Navigator.of(context);
    await app.act((Game game) => game.confirmPlan(draft));
    if (!context.mounted) return;
    final ActionResult? f = app.lastFeedback;
    if (f != null) await showFeedback(context, f);
    if (!context.mounted) return;
    if (nav.canPop()) nav.pop();
  }
}

// ─────────────────────────── раскладка монеток ───────────────────────────

class _Editor extends StatefulWidget {
  const _Editor({
    required this.available,
    required this.minNeeds,
    required this.onConfirm,
    this.previous,
    this.proposal,
  });

  final int available;

  /// План прошлой недели — его можно повторить одним касанием.
  final Allocation? previous;

  /// Раскладка, которую предлагает Финни на стадии «Хранитель копилки».
  final FinniProposal? proposal;

  /// Цена самого дешёвого набора еды и воды — только для мягкой подсказки.
  final int minNeeds;

  final Future<void> Function(Allocation draft) onConfirm;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> with TickerProviderStateMixin {
  /// Черновик плана. Живёт в состоянии экрана, потому что §2.5.5.3 разрешает
  /// менять план сколько угодно **до** подтверждения: в журнал попадает
  /// только подтверждённый.
  Allocation _draft = const Allocation();
  bool _busy = false;

  /// Монетки, которые сейчас летят. Пока монетка в воздухе, её уже нет
  /// в счётчике «осталось разложить», но ещё нет и в конверте — ровно так,
  /// как если бы ребёнок держал её в руке.
  final List<_Flight> _flights = <_Flight>[];

  /// Сколько монеток летит в каждый конверт: на столько число в конверте
  /// отстаёт от черновика.
  final Map<Envelope, int> _inFlight = <Envelope, int>{};

  /// Откуда и куда лететь. Координаты берутся с настоящих виджетов, а не
  /// задаются числами: конверты переезжают от длины подсказки и масштаба
  /// шрифта, и захардкоженная точка прилёта разъехалась бы с карточкой.
  final GlobalKey _field = GlobalKey();
  final GlobalKey _purse = GlobalKey();
  final Map<Envelope, GlobalKey> _cards = <Envelope, GlobalKey>{
    for (final Envelope e in Envelope.values) e: GlobalKey(),
  };

  int get _left => widget.available - _draft.total;

  /// Сколько монеток показывать в конверте прямо сейчас.
  int _shown(Envelope e) =>
      (_draft.byEnvelope(e) - (_inFlight[e] ?? 0)).clamp(0, widget.available);

  @override
  void dispose() {
    for (final _Flight f in _flights) {
      f.kill();
    }
    super.dispose();
  }

  /// Прошлый план, урезанный под то, что есть сейчас: сначала «Нужное»,
  /// потом «Копилка», потом «Хочу». Лишнего не кладёт никогда.
  Allocation _fitPrevious(Allocation prev) {
    int left = widget.available;
    int take(int want) {
      final int t = want < left ? want : left;
      left -= t;
      return t;
    }

    final int needs = take(prev.needs);
    final int savings = take(prev.savings);
    final int wants = take(prev.wants);
    return Allocation(needs: needs, wants: wants, savings: savings);
  }

  /// 🔴 Повторить свой прошлый план — это и есть самостоятельность, которую
  /// показывают стадии: ребёнок уже знает, как раскладывает, и не жмёт «+»
  /// по одной монетке десять раз. Дальше план правится как обычно.
  void _repeatPrevious() {
    final Allocation next = _fitPrevious(widget.previous!);
    setState(() => _draft = next);
    for (final Envelope e in Envelope.values) {
      if (next.byEnvelope(e) > 0) _launch(e);
    }
  }

  void _takeProposal() {
    final Allocation next = widget.proposal!.plan;
    setState(() => _draft = next);
    for (final Envelope e in Envelope.values) {
      if (next.byEnvelope(e) > 0) _launch(e);
    }
  }

  void _change(Envelope e, int delta) {
    if (delta > 0 && _left <= 0) return;
    if (delta < 0 && _draft.byEnvelope(e) <= 0) return;
    setState(() => _draft = _draft.plus(e, delta));
    // 🔴 Модель меняется сразу, а не по прилёту: ребёнок бьёт по «+1»
    // быстрее, чем летит монетка, и если ждать посадки, счётчик «осталось»
    // разрешит разложить больше, чем есть. Анимация показывает изменение,
    // а не выполняет его.
    if (delta > 0) _launch(e);
  }

  /// Запускает монетку от счётчика к конверту.
  void _launch(Envelope e) {
    if (!context.motionOn) return;
    final RenderBox? field = _box(_field);
    final RenderBox? purse = _box(_purse);
    final RenderBox? card = _box(_cards[e]!);
    if (field == null || purse == null || card == null) return;

    Offset centre(RenderBox b) =>
        field.globalToLocal(b.localToGlobal(b.size.center(Offset.zero)));

    final _Flight f = _Flight(
      envelope: e,
      from: centre(purse),
      to: centre(card),
      controller: AnimationController(
        vsync: this,
        duration: context.motion(Motion.flight),
      ),
    );
    f.controller.addStatusListener((AnimationStatus s) {
      if (s == AnimationStatus.completed) _land(f);
    });
    setState(() {
      _flights.add(f);
      _inFlight.update(e, (int n) => n + 1, ifAbsent: () => 1);
    });
    f.controller.forward();
  }

  /// Монетка долетела — теперь число в конверте растёт.
  void _land(_Flight f) {
    if (!mounted) {
      f.kill();
      return;
    }
    setState(() {
      _flights.remove(f);
      final int n = (_inFlight[f.envelope] ?? 1) - 1;
      if (n <= 0) {
        _inFlight.remove(f.envelope);
      } else {
        _inFlight[f.envelope] = n;
      }
    });
    // 🔴 Контроллер нельзя освобождать изнутри его же слушателя статуса:
    // тикер в этот момент ещё договаривает кадр. Отдельной микрозадачей —
    // можно, и к концу тика от него не остаётся ничего.
    scheduleMicrotask(f.kill);
  }

  RenderBox? _box(GlobalKey key) =>
      key.currentContext?.findRenderObject() as RenderBox?;

  /// Подсказка про еду и воду. Возвращает null, когда показывать нечего:
  /// это именно подсказка, а не проверка — подтверждение она не блокирует.
  String? get _needsHint {
    if (widget.minNeeds <= 0) return null;
    if (_draft.needs >= widget.minNeeds) return null;
    return 'На еду и воду нужно хотя бы ${widget.minNeeds} '
        '${Coins.word(widget.minNeeds)}.';
  }

  @override
  Widget build(BuildContext context) {

    if (widget.available <= 0) {
      return _EmptyWallet();
    }

    return Stack(
      key: _field,
      children: <Widget>[
        Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.lg),
                children: <Widget>[
                  SceneHeader(
                    title: 'Разложи ${widget.available} '
                        '${Coins.word(widget.available)}',
                    say: 'Сначала — «Нужное». Остальное — как решишь.',
                  ),
                  if (widget.proposal != null && _draft.total == 0) ...<Widget>[
                    const SizedBox(height: Gap.md),
                    FinniSays(text: widget.proposal!.says),
                    const SizedBox(height: Gap.sm),
                    OutlinedButton.icon(
                      icon: const Pictogram(Pic.paw, color: AppColors.primary),
                      label: const Text('Взять раскладку Финни'),
                      onPressed: _takeProposal,
                    ),
                  ] else if (widget.previous != null &&
                      widget.previous!.total > 0 &&
                      _draft.total == 0) ...<Widget>[
                    const SizedBox(height: Gap.md),
                    OutlinedButton.icon(
                      icon: const Pictogram(Pic.history,
                          color: AppColors.primary),
                      label: const Text('Разложить как на прошлой неделе'),
                      onPressed: _repeatPrevious,
                    ),
                  ],
                  const SizedBox(height: Gap.md),
                  for (final Envelope e in Envelope.values) ...<Widget>[
                    _EnvelopeRow(
                      cardKey: _cards[e]!,
                      envelope: e,
                      amount: _shown(e),
                      canAdd: _left > 0,
                      canRemove: _draft.byEnvelope(e) > 0,
                      onAdd: () => _change(e, 1),
                      onRemove: () => _change(e, -1),
                    ),
                    const SizedBox(height: Gap.xs),
                    Text(e.hint,
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.inkSoft)),
                    if (e == Envelope.needs && _needsHint != null) ...<Widget>[
                      const SizedBox(height: Gap.sm),
                      _SoftHint(text: _needsHint!),
                    ],
                    const SizedBox(height: Gap.lg),
                  ],
                ],
              ),
            ),
            _Footer(
              purseKey: _purse,
              left: _left,
              busy: _busy,
              onConfirm: () async {
                setState(() => _busy = true);
                await widget.onConfirm(_draft);
                if (mounted) setState(() => _busy = false);
              },
            ),
          ],
        ),
        // 🔴 IgnorePointer — обязателен: пока монетка летит, ребёнок уже
        // тычет в «+1» снова, и слой с анимацией не имеет права перехватить
        // это касание. Анимация показывает, а не распоряжается.
        if (_flights.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _CoinsInFlight(_flights)),
            ),
          ),
      ],
    );
  }
}

/// Одна монетка в полёте: откуда, куда и сколько ей осталось.
class _Flight {
  _Flight({
    required this.envelope,
    required this.from,
    required this.to,
    required this.controller,
  });

  final Envelope envelope;
  final Offset from;
  final Offset to;
  final AnimationController controller;

  bool _dead = false;

  void kill() {
    if (_dead) return;
    _dead = true;
    controller.dispose();
  }
}

/// Слой с летящими монетками.
///
/// 🔴 Рисуется painter'ом по `repaint`, а не виджетами с `Positioned`:
/// иначе каждый кадр полёта проходил бы build и layout всего экрана плана —
/// трёх конвертов, подсказок и нижней полосы. Здесь кадр — это две
/// окружности.
class _CoinsInFlight extends CustomPainter {
  _CoinsInFlight(this.flights)
      : super(
          repaint: Listenable.merge(<Listenable>[
            for (final _Flight f in flights) f.controller,
          ]),
        );

  final List<_Flight> flights;

  final Paint _body = Paint()..color = AppColors.coin;
  final Paint _rim = Paint()
    ..color = AppColors.coinDeep
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    for (final _Flight f in flights) {
      final double t = Motion.travel.transform(f.controller.value);
      // Дуга, а не прямая: по прямой монетка читается как подсказка-стрелка,
      // по дуге — как брошенный предмет. Квадратичная Безье считается
      // тремя умножениями, Path в кадре для этого не нужен.
      final Offset lift = Offset(
        (f.from.dx + f.to.dx) / 2,
        math.min(f.from.dy, f.to.dy) - 48,
      );
      final double u = 1 - t;
      final Offset p = f.from * (u * u) + lift * (2 * u * t) + f.to * (t * t);
      // Монетка чуть уменьшается к концу — «уходит внутрь» конверта.
      final double r = 11 - 2 * t;
      canvas.drawCircle(p, r, _body);
      canvas.drawCircle(p, r, _rim);
    }
  }

  @override
  bool shouldRepaint(_CoinsInFlight old) => true;
}

class _EnvelopeRow extends StatelessWidget {
  const _EnvelopeRow({
    required this.cardKey,
    required this.envelope,
    required this.amount,
    required this.canAdd,
    required this.canRemove,
    required this.onAdd,
    required this.onRemove,
  });

  /// Точка прилёта монетки — сама карточка конверта.
  final GlobalKey cardKey;

  final Envelope envelope;
  final int amount;
  final bool canAdd;
  final bool canRemove;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // Счётчик: «−» слева, конверт посередине, «+» справа — как у любого
    // счётчика в игре. Раньше обе кнопки стояли справа рядом, и «−»
    // легко нажималась вместо «+».
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _StepButton(
          icon: Pic.minus,
          envelope: envelope,
          label: 'Убрать монетку из конверта «${envelope.title}»',
          onPressed: canRemove ? onRemove : null,
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: EnvelopeCard(
              key: cardKey,
              envelope: envelope,
              amount: amount,
              compact: true),
        ),
        const SizedBox(width: Gap.sm),
        _StepButton(
          icon: Pic.plus,
          envelope: envelope,
          label: 'Положить монетку в конверт «${envelope.title}»',
          onPressed: canAdd ? onAdd : null,
        ),
      ],
    );
  }
}

/// Кнопка −1/+1. Квадрат [TapSize.min] — §3.6.3 просит 48, детям мало.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.envelope,
    required this.label,
    required this.onPressed,
  });

  final Pic icon;
  final Envelope envelope;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool on = onPressed != null;
    final Color c = AppColors.of(envelope);
    return Semantics(
      button: true,
      enabled: on,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: on ? AppColors.surface : AppColors.grid,
        shape: LedgeBorder(
          radius: Radii.button,
          depth: on ? 4 : 0,
          edge: c,
          side: BorderSide(color: on ? c : AppColors.line, width: 2),
        ),
        child: InkWell(
          onTap: onPressed,
          customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.button)),
          child: Container(
            width: TapSize.min,
            height: TapSize.min + 8,
            alignment: Alignment.center,
            child: Pictogram(icon,
                size: 30, color: on ? c : AppColors.inkSoft),
          ),
        ),
      ),
    );
  }
}

/// Мягкая подсказка: объясняет, но не запрещает (§2.2 «безопасная ошибка»).
class _SoftHint extends StatelessWidget {
  const _SoftHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // Строкой с лампочкой, а не плашкой: плашка на 360 dp съедала место
    // второго конверта, а подсказка — не событие, а примечание.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Pictogram(Pic.bulb, size: 22, color: AppColors.needs),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            '$text Меньше — Финни проголодается, но это поправимо.',
            style: const TextStyle(fontSize: 16, color: AppColors.ink),
          ),
        ),
      ],
    );
  }
}

/// Остаток и подтверждение.
///
/// §2.5.5.2: остаток виден всегда, а сумма распределения не может превысить
/// доступный бюджет — «+1» просто перестаёт работать, когда монеток в руках
/// не осталось.
///
/// Полоса намеренно низкая: на экране 360×640 с крупным шрифтом (§3.1.2,
/// §3.6.4) каждая лишняя строка здесь отнимается у конвертов, а конверты —
/// это и есть экран.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.purseKey,
    required this.left,
    required this.busy,
    required this.onConfirm,
  });

  /// Точка вылета монетки — счётчик «осталось разложить».
  final GlobalKey purseKey;

  final int left;
  final bool busy;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final bool ready = left == 0;
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            label: 'Осталось разложить: $left ${Coins.word(left)}',
            excludeSemantics: true,
            child: Row(
              children: <Widget>[
                // §3.6.5: состояние помечено иконкой и словом, цвет — третий
                // канал, а не единственный.
                // 🔴 Кошелёк, а не ладонь. Ладонь в этом наборе означает
                // «подожди, не спеши» и стоит на предложении отложить
                // покупку; здесь же речь о том, что монетки ещё в кошельке
                // и ждут решения. Один знак — одно значение.
                Pictogram(ready ? Pic.check : Pic.wallet,
                    size: 24,
                    color: ready ? AppColors.needs : AppColors.inkSoft),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text('Осталось разложить', style: t.titleMedium),
                ),
                Coins(left, key: purseKey, size: 24),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),
          // Короткая подпись, почему кнопка пока не работает (§2.2: сказать,
          // что произошло и что можно сделать, а не «нельзя»).
          Text(
            ready ? 'Можно подтверждать.' : 'Положи монетки в конверты.',
            style: const TextStyle(fontSize: 16, color: AppColors.inkSoft),
          ),
          const SizedBox(height: Gap.sm),
          FilledButton.icon(
            icon: const Pictogram(Pic.check, color: AppColors.onAction),
            label: const Text('Готово'),
            onPressed: ready && !busy
                ? () async {
                    await onConfirm();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _EmptyWallet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Pictogram(Pic.wallet, size: 56, color: AppColors.inkSoft),
          const SizedBox(height: Gap.md),
          Text('Раскладывать пока нечего',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center),
          const SizedBox(height: Gap.sm),
          const Text(
            'Монетки приходят в начале недели. Начни новую неделю '
            'на главном экране.',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── план против факта ───────────────────────────

/// §2.5.5.3: «после подтверждения отображается сравнение плана
/// с фактическими расходами».
class _PlanVsFact extends StatelessWidget {
  const _PlanVsFact({
    required this.plan,
    required this.fact,
    required this.tolerance,
  });

  final Allocation plan;
  final Allocation fact;
  final int tolerance;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.xl),
      children: <Widget>[
        Semantics(
          header: true,
          child: Text('План и что получается', style: t.headlineSmall),
        ),
        const SizedBox(height: Gap.sm),
        Text(
          'Здесь план недели и сколько уже ушло. Итог подведём, '
          'когда неделя закончится.',
          style: t.bodyMedium,
        ),
        const SizedBox(height: Gap.xs),
        Text(
          'Если разница не больше $tolerance, это всё ещё по плану.',
          style: const TextStyle(fontSize: 16, color: AppColors.inkSoft),
        ),
        const SizedBox(height: Gap.md),
        for (final Envelope e in Envelope.values) ...<Widget>[
          _FactCard(
            envelope: e,
            planned: plan.byEnvelope(e),
            actual: fact.byEnvelope(e),
            tolerance: tolerance,
          ),
          const SizedBox(height: Gap.md),
        ],
      ],
    );
  }
}

class _FactCard extends StatelessWidget {
  const _FactCard({
    required this.envelope,
    required this.planned,
    required this.actual,
    required this.tolerance,
  });

  final Envelope envelope;
  final int planned;
  final int actual;
  final int tolerance;

  @override
  Widget build(BuildContext context) {
    // 🔴 Норма считается доменом и она асимметрична: недорасход по «Хочу»
    // нарушением не считается — Термины ТЗ прямо называют отказ от
    // необязательной покупки и её перенос не ошибкой пользователя.
    final bool ok = PeriodRules.withinNorm(
      envelope: envelope,
      planned: planned,
      actual: actual,
      tolerance: tolerance,
    );
    final bool isSavings = envelope == Envelope.savings;
    final Color c = AppColors.of(envelope);
    final String status = ok
        // «Пока»: посреди недели это сравнение, а не оценка — итог
        // подводится, когда неделя закончится.
        ? 'пока по плану'
        : isSavings
            ? 'отложено меньше плана'
            : 'ушло больше плана';
    final String? note = ok
        ? (!isSavings && actual < planned
            ? (envelope == Envelope.needs
                ? 'Часть монеток на нужное осталась — они пригодятся.'
                : 'Часть монеток на «Хочу» осталась. Перенести покупку — '
                    'не ошибка.')
            : null)
        : isSavings
            ? 'В копилку ушло меньше, чем задумано. Даже одна монетка '
                'приближает цель.'
            : 'Так бывает. В следующем плане можно положить сюда побольше.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Pictogram(AppColors.picOf(envelope), size: 26, color: c),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(envelope.title,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: c)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            _Line(label: 'По плану', amount: planned),
            const SizedBox(height: Gap.xs),
            _Line(label: isSavings ? 'Отложено' : 'Потрачено', amount: actual),
            const SizedBox(height: Gap.sm),
            // §3.6.5: статус подписан словом и помечен иконкой, цвет — третий
            // канал, а не единственный.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Pictogram(ok ? Pic.check : Pic.info,
                    size: 22, color: ok ? AppColors.needs : AppColors.wants),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(status,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (note != null) ...<Widget>[
              const SizedBox(height: Gap.xs),
              Text(note,
                  style:
                      const TextStyle(fontSize: 16, color: AppColors.inkSoft)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $amount ${Coins.word(amount)}',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 16)),
          ),
          Coins(amount),
        ],
      ),
    );
  }
}
