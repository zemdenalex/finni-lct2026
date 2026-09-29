import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../domain/world/contract.dart';
import '../home/world_hud.dart';
import '../world_help.dart';
import '../world_layout.dart';
import '../world_routes.dart';
import '../world_state.dart';
import '../shop/shop_kit.dart' show billPartsText;
import 'plan_fact_view.dart';
import '../../../core/world_theme.dart';
import '../pic_text.dart';

/// S11 · Итоги недели (`docs/game/screens-other.md`, `week-loop.md`).
///
/// Шаги: почему неделя кончилась → счета недели и «Оплатить» (при нехватке —
/// выбор: взять из копилки или как есть, тогда поможет семья) → было / стало
/// план против факта по конвертам (`World.weekHistory`, ТЗ 2.5.5.3) с
/// выводом недели, очки роста, стадия → «Новая неделя».
///
/// Счета уже оплачены (итоги открыты второй раз) — экран сразу показывает
/// итог: флаг берётся из [WeekPlanFact.billsPaid].
///
/// 🟡 Дыра контракта, которую экран обходит: нет причин по каждому очку
/// роста — показана фраза `payBills().reason` целиком (в ней мир
/// перечисляет причины).
class WeekReviewScreen extends StatefulWidget {
  const WeekReviewScreen({super.key});

  /// Очки, с которых начинается следующая стадия, или null — последняя.
  /// 🟡 Пороги 4 / 9 (open-questions T2) — те же, что в `FakeWorld`.
  static int? nextThreshold(WorldStage s) => switch (s) {
        WorldStage.village => 4,
        WorldStage.town => 9,
        WorldStage.moscow => null,
      };

  /// Строка «до переезда» в итогах и в истории. Очков уже хватает, а
  /// ребёнок не переехал — не «ещё −2» (ревью df2164a), а «можно
  /// переезжать» и хватает ли денег на залог. null — дальше некуда.
  static String? moveLine(
      ResourceSnapshot now, List<WorldCatalogItem> catalog) {
    final int? next = nextThreshold(now.stage);
    if (next == null) return null;
    final int left = next - now.growthPoints;
    if (left > 0) return '➡️ До переезда: ещё $left (нужно $next)';
    WorldCatalogItem? home;
    for (final WorldCatalogItem i in catalog) {
      if (i.category != WorldCatalogCategory.home || now.owned.contains(i.id)) {
        continue;
      }
      if (home == null || i.price < home.price) home = i;
    }
    if (home == null) return '➡️ Очков хватает — можно переезжать';
    return '➡️ Очков хватает — можно переезжать: ${home.title}, залог '
        '${home.price}. '
        '${now.goal >= home.price ? 'В копилке хватает.' : 'В копилке ${now.goal} из ${home.price}.'}';
  }

  /// Названия стадий — решение Дениса 28.09 (`economy.json →
  /// growth.stages[].name`). 🟡 Контракт их не отдаёт, поэтому копия здесь;
  /// меняются в файле — меняются и тут.
  static String stageName(WorldStage s) => switch (s) {
        WorldStage.village => 'В деревне',
        WorldStage.town => 'В городе',
        WorldStage.moscow => 'В Москве',
      };

  /// Своих денег на счета: НУЖНО + ХОЧУ + заработок (копилка — нет).
  static int money(ResourceSnapshot s) => s.need + s.want + s.free;

  @override
  State<WeekReviewScreen> createState() => _WeekReviewScreenState();
}

class _WeekReviewScreenState extends State<WeekReviewScreen> {
  late final ResourceSnapshot _before;

  /// Части счёта — в тот же миг, что [_before]: после оплаты мир уже
  /// считает счёт следующей недели.
  late final WeekBillParts _billParts;
  WorldResult? _bills;
  bool _paid = false;

  /// Итоги открыты, когда счета уже были оплачены: [_before] — снимок после
  /// счетов, «было → стало» и «не хватает» по нему не считаются.
  bool _paidOnOpen = false;
  WorldResult? _startRefused;

  @override
  void initState() {
    super.initState();
    final WorldState ws = context.read<WorldState>();
    _before = ws.snapshot;
    _billParts = ws.world.weeklyBillParts;
    _paidOnOpen =
        ws.phase == WeekPhase.review && (_week(ws.world)?.billsPaid ?? false);
    _paid = _paidOnOpen;
  }

  /// План и факт текущей недели, или null до первой недели.
  static WeekPlanFact? _week(World w) {
    final List<WeekPlanFact> h = w.weekHistory;
    return h.isEmpty ? null : h.last;
  }

  void _back() {
    final NavigatorState nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed(WorldRoutes.room);
    }
  }

  void _help() {
    showHelp(
        context,
        'Что здесь?',
        'Итоги недели.\n\n'
            '🧾 Сначала платим обязательные счета: еда, корм питомцам, '
            'жильё. Если своих монет не хватает, можно взять из копилки — '
            'или семья поможет, но Финни станет грустнее.\n'
            '📊 Потом сверяем план с тем, что вышло на деле: сколько '
            'положили в каждый конверт и сколько потратили или отложили.\n'
            '⭐ Очки роста дают за счета своими деньгами, неделю без '
            'нехватки и отложенные монеты. Наберёшь больше — Финни '
            'переедет дальше.');
  }

  void _pay({required bool fromGoal}) {
    final WorldResult r = context
        .read<WorldState>()
        .act((World w) => w.payBills(takeFromGoal: fromGoal));
    setState(() {
      _bills = r;
      _paid = r.ok || r.reasonCode == 'bills.paid';
    });
  }

  Future<void> _payFromGoal(int short, int saved) async {
    final int take = short < saved ? short : saved;
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Взять из копилки?'),
        content: PicText('Из копилки уйдёт до $take 💰. Было $saved — станет '
            '${saved - take}. Цель отодвинется.'),
        actions: <Widget>[
          TextButton(
              key: const ValueKey<String>('review:goal:no'),
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Нет')),
          FilledButton(
              key: const ValueKey<String>('review:goal:yes'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Да, взять')),
        ],
      ),
    );
    if (yes == true && mounted) _pay(fromGoal: true);
  }

  void _newWeek() {
    final WorldResult r =
        context.read<WorldState>().act((World w) => w.startWeek());
    if (!r.ok) {
      setState(() => _startRefused = r);
      return;
    }
    Navigator.of(context)
        .pushNamedAndRemoveUntil(WorldRoutes.room, (Route<dynamic> _) => false);
  }

  @override
  Widget build(BuildContext context) {
    final WorldState ws = context.watch<WorldState>();
    final ResourceSnapshot now = ws.snapshot;
    final bool review = ws.phase == WeekPhase.review;

    final bool land = WorldLayout.isLandscape(context);
    final bool early = !review && !_paid;

    // Шаг 1–2: почему неделя кончилась, счета и оплата. В альбомной счёт
    // с кнопками — слева первым, «почему кончилась» до оплаты стоит
    // справа (там пока пусто), после оплаты — под счетами.
    final Widget ended = _endedBox(_before.endedBy);
    // После оплаты в альбомной план против факта — первым слева: это
    // главный вывод недели, он должен быть виден без прокрутки.
    final List<Widget> bills = land
        ? <Widget>[
            if (_paid) ...<Widget>[
              _factBox(now, ws.world),
              const SizedBox(height: Gap.md),
            ],
            ..._billsStep(now, compact: true),
          ]
        : <Widget>[
            // Портрет после оплаты: «чек» ▲/▼ и «Что мы поняли» — первыми,
            // без прокрутки на 360×640 и при шрифте 1,3 (review_fits_test);
            // почему неделя кончилась и счета — под ними.
            if (_paid) ...<Widget>[
              _factBox(now, ws.world),
              const SizedBox(height: Gap.md),
            ],
            ended,
            const SizedBox(height: Gap.md),
            ..._billsStep(now, compact: false),
          ];
    final List<Widget> payButtons =
        land ? _payButtons(compact: true) : const <Widget>[];
    // Шаг 3: было → стало и рост. До оплаты — что здесь появится.
    final List<Widget> outcome = <Widget>[
      // В альбомной справа рост и «почему кончилась»; план — слева.
      if (_paid) ...<Widget>[
        _growthBox(now, ws.world),
        if (land) ...<Widget>[
          const SizedBox(height: Gap.md),
          ended,
        ],
        if (_startRefused != null) ...<Widget>[
          const SizedBox(height: Gap.md),
          _Box(
              icon: Icons.block_rounded,
              tone: _Tone.warn,
              title: 'Пока нельзя',
              text: _startRefused!.reason),
        ],
      ] else if (land) ...<Widget>[
        ended,
        const SizedBox(height: Gap.md),
        const Row(
          key: ValueKey<String>('review:outcome_wait'),
          children: <Widget>[
            Icon(Icons.bar_chart_rounded, color: WorldColors.textSoft),
            SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                  'После счетов здесь будут план против факта и очки роста.',
                  style: TextStyle(fontSize: 16, color: WorldColors.textSoft)),
            ),
          ],
        ),
      ],
    ];
    // «Новая неделя» прибита под списком — не уезжает с прокруткой.
    final Widget? newWeek = _paid
        ? Padding(
            padding: EdgeInsets.fromLTRB(
                land ? Gap.sm : Gap.md, Gap.sm, Gap.md, Gap.sm),
            child: FilledButton.icon(
              key: const ValueKey<String>('review:new_week'),
              style: land
                  ? FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(TapSize.min))
                  : null,
              onPressed: _newWeek,
              icon: const Icon(Icons.wb_sunny_rounded),
              label: const Text('Новая неделя'),
            ),
          )
        : null;

    Widget scroll(Key key, List<Widget> children, EdgeInsets padding) =>
        SingleChildScrollView(
          key: key,
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );

    const Widget notYet = _Box(
      key: ValueKey<String>('review:not_yet'),
      icon: Icons.event_note_rounded,
      tone: _Tone.info,
      title: 'Итоги пока рано',
      text: 'Итоги будут, когда неделя кончится: нажми «Спать» дома или '
          'потрать все ⚡.',
    );

    final Widget content;
    if (early) {
      content = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: scroll(const ValueKey<String>('review:list'),
              const <Widget>[notYet], const EdgeInsets.all(Gap.md)),
        ),
      );
    } else if (land) {
      // Альбомная: слева счета (после оплаты — план против факта над
      // ними), справа «почему кончилась», рост и «Новая неделя».
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: scroll(
                      const ValueKey<String>('review:list'),
                      bills,
                      const EdgeInsets.fromLTRB(
                          Gap.md, Gap.sm, Gap.sm, Gap.sm)),
                ),
                // Кнопки оплаты рядом, а не столбиком: так счёт над ними
                // остаётся виден и при шрифте 1,3.
                if (payButtons.isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(Gap.md, 0, Gap.sm, Gap.sm),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (int i = 0;
                              i < payButtons.length;
                              i++) ...<Widget>[
                            if (i > 0) const SizedBox(width: Gap.sm),
                            Expanded(child: payButtons[i]),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: scroll(
                      const ValueKey<String>('review:outcome'),
                      outcome,
                      const EdgeInsets.fromLTRB(
                          Gap.sm, Gap.sm, Gap.md, Gap.sm)),
                ),
                if (newWeek != null) newWeek,
              ],
            ),
          ),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: scroll(
                const ValueKey<String>('review:list'),
                <Widget>[
                  ...bills,
                  if (outcome.isNotEmpty) const SizedBox(height: Gap.md),
                  ...outcome,
                ],
                const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md)),
          ),
          if (newWeek != null) newWeek,
        ],
      );
    }

    return Scaffold(
      backgroundColor: WorldColors.night,
      appBar: AppBar(
        // Альбомная — основная: низкая шапка, высота нужна итогам.
        toolbarHeight: land ? 48 : null,
        leading: IconButton(
          key: const ValueKey<String>('review:back'),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Назад',
          onPressed: _back,
        ),
        automaticallyImplyLeading: false,
        title: Text(
            now.weekNo > 0 ? 'Итоги недели ${now.weekNo}' : 'Итоги недели'),
        actions: <Widget>[
          // История всех недель (S12) — отсюда тоже, не только из комнаты.
          // В портрете шапка узкая: значок съел бы заголовок, а прогресс и
          // так в один тап из комнаты.
          if (land)
            IconButton(
              key: const ValueKey<String>('review:history'),
              tooltip: 'Прогресс по неделям',
              onPressed: () =>
                  Navigator.of(context).pushNamed(WorldRoutes.history),
              icon: const Icon(Icons.timeline_rounded),
            ),
          HelpButton(
            key: const ValueKey<String>('review:help'),
            onPressed: _help,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WorldHud(snapshot: now),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _endedBox(WeekEnd? by) => switch (by) {
        WeekEnd.energyOut => const _Box(
            key: ValueKey<String>('review:ended'),
            icon: Icons.battery_alert_rounded,
            tone: _Tone.info,
            title: 'Кончилась ⚡',
            text: 'Сил не осталось ни на одно дело — неделя кончилась сама. '
                'Это не штраф, просто без бонуса сна.'),
        WeekEnd.sleep => const _Box(
            key: ValueKey<String>('review:ended'),
            icon: Icons.bedtime_rounded,
            tone: _Tone.info,
            title: 'Финни лёг спать',
            text: 'Ты сам закрыл неделю. Если ⚡ осталось, Финни выспался.'),
        null => const _Box(
            key: ValueKey<String>('review:ended'),
            icon: Icons.bedtime_rounded,
            tone: _Tone.info,
            title: 'Неделя кончилась',
            text: 'Подведём итоги.'),
      };

  /// Нехватка на счета недели (≤ 0 — хватает).
  int get _short => _before.weeklyBill - WeekReviewScreen.money(_before);

  /// Кнопки оплаты. В альбомной они прибиты под счётом, а не в прокрутке.
  List<Widget> _payButtons({required bool compact}) {
    if (_paid) return const <Widget>[];
    // Альбомная: кнопки ниже (56 dp) и с узкими полями — стоят в ряд.
    const EdgeInsets tight = EdgeInsets.symmetric(horizontal: Gap.sm);
    final ButtonStyle? main = compact
        ? FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(TapSize.min), padding: tight)
        : null;
    final int short = _short;
    if (short <= 0) {
      return <Widget>[
        FilledButton.icon(
          key: const ValueKey<String>('review:pay'),
          style: main,
          onPressed: () => _pay(fromGoal: false),
          icon: const Icon(Icons.receipt_long_rounded),
          label: const Text('Оплатить счета'),
        ),
      ];
    }
    return <Widget>[
      if (_before.goal > 0) ...<Widget>[
        FilledButton.icon(
          key: const ValueKey<String>('review:pay_goal'),
          style: main,
          onPressed: () => _payFromGoal(short, _before.goal),
          icon: const Icon(Icons.savings_rounded),
          label: Text(compact ? 'Из копилки' : 'Взять из копилки'),
        ),
        if (!compact) const SizedBox(height: Gap.sm),
      ],
      OutlinedButton.icon(
        key: const ValueKey<String>('review:pay'),
        style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(TapSize.min),
            padding: compact ? tight : null),
        onPressed: () => _pay(fromGoal: false),
        icon: const Icon(Icons.family_restroom_rounded),
        label: Text(
            compact ? 'Семья поможет' : 'Оплатить как есть — семья поможет'),
      ),
    ];
  }

  /// Счёт недели, отказ или итог оплаты; в портрете — и кнопки.
  List<Widget> _billsStep(ResourceSnapshot now, {required bool compact}) {
    final int bill = _before.weeklyBill;
    final int money = WeekReviewScreen.money(_before);
    final int short = _short;
    final WorldResult? r = _bills;
    const Widget familyNote = Text(
        'Если семья поможет, Финни станет грустнее и без очка роста за '
        'счета.',
        style: TextStyle(fontSize: 16, color: WorldColors.textSoft));
    if (_paidOnOpen) {
      final WeekPlanFact? w = _week(context.read<WorldState>().world);
      return <Widget>[
        _Box(
          key: const ValueKey<String>('review:bills_result'),
          icon: Icons.check_circle_rounded,
          tone: _Tone.ok,
          title: 'Счета закрыты',
          text: 'Счета недели — ${w?.need.actual ?? bill} 💰.',
        ),
      ];
    }
    return <Widget>[
      _Box(
        key: const ValueKey<String>('review:bills'),
        icon: Icons.receipt_long_rounded,
        tone: short > 0 && !_paid ? _Tone.warn : _Tone.info,
        title: 'Счета недели: $bill 💰',
        text: 'Из них ${billPartsText(_billParts)}. Своих монет было $money 💰'
            '${short > 0 ? ' — не хватает $short.' : ' — хватает.'}',
      ),
      const SizedBox(height: Gap.sm),
      if (!_paid) ...<Widget>[
        if (r != null) ...<Widget>[
          _Box(
              icon: Icons.block_rounded,
              tone: _Tone.warn,
              title: 'Не получилось',
              text: r.reason),
          const SizedBox(height: Gap.sm),
        ],
        if (compact) ...<Widget>[
          if (short > 0) familyNote,
        ] else ...<Widget>[
          ..._payButtons(compact: false),
          if (short > 0) ...<Widget>[
            const SizedBox(height: Gap.xs),
            familyNote,
          ],
        ],
      ] else if (r != null)
        _Box(
          key: const ValueKey<String>('review:bills_result'),
          icon: Icons.check_circle_rounded,
          tone: _Tone.ok,
          title: 'Счета закрыты',
          text: r.reason,
        ),
    ];
  }

  /// План против факта по конвертам (ТЗ 2.5.5.3) + вывод недели, копилка
  /// и настроение с причиной (A.9).
  Widget _factBox(ResourceSnapshot now, World world) {
    final WeekPlanFact? w = _week(world);
    return _Box(
      key: const ValueKey<String>('review:fact'),
      icon: Icons.bar_chart_rounded,
      tone: _Tone.info,
      title: 'План и на деле',
      lines: <String>[
        _paidOnOpen
            ? '🐷 В копилке: ${now.goal}'
            : '🐷 Копилка: было ${_before.goal} → стало ${now.goal}',
        _paidOnOpen
            ? '😊 Настроение: ${now.happiness}'
            : '😊 Настроение: было ${_before.happiness} → '
                'стало ${now.happiness}',
        // Почему такое настроение — одной фразой от мира (ТЗ 2.5.10.3).
        '💬 ${now.moodReason.text}',
      ],
      child: w == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                PlanFactRows(week: w, keyPrefix: 'review:planfact'),
                const SizedBox(height: Gap.xs),
                PicText('🙂 Что мы поняли: ${_lowerFirst(planFactTakeaway(w))}',
                    key: const ValueKey<String>('review:takeaway'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                if (foodTakeaway(w) case final String food) ...<Widget>[
                  const SizedBox(height: Gap.xs),
                  PicText(food,
                      key: const ValueKey<String>('review:food'),
                      style: const TextStyle(fontSize: 16)),
                ],
              ],
            ),
    );
  }

  Widget _growthBox(ResourceSnapshot now, World world) {
    final int gained = now.growthPoints - _before.growthPoints;
    final String? move = WeekReviewScreen.moveLine(now, world.catalog);
    final bool moved = now.stage != _before.stage;
    return _Box(
      key: const ValueKey<String>('review:growth'),
      icon: Icons.star_rounded,
      tone: _Tone.ok,
      title: _paidOnOpen ? 'Очки роста' : 'Очки роста: +$gained за неделю',
      lines: <String>[
        '⭐ Всего: ${now.growthPoints}',
        '🏠 Финни живёт: ${WeekReviewScreen.stageName(now.stage)}'
            '${moved ? ' — переезд!' : ''}',
        move ?? '🏁 Это последняя стадия.',
      ],
    );
  }
}

enum _Tone { info, ok, warn }

/// Блок итогов: иконка + заголовок + текст — не только цвет (ТЗ 3.6.5).
class _Box extends StatelessWidget {
  const _Box({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    this.text,
    this.child,
    this.lines = const <String>[],
  });

  final IconData icon;
  final _Tone tone;
  final String title;
  final String? text;

  /// Свой блок под заголовком (план против факта).
  final Widget? child;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (tone) {
      _Tone.info => (WorldColors.goal, WorldColors.goalBg),
      _Tone.ok => (WorldColors.needs, WorldColors.needsBg),
      _Tone.warn => (WorldColors.wants, WorldColors.wantsBg),
    };
    return Container(
      padding: const EdgeInsets.all(Gap.sm + Gap.xs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(color: fg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: fg),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          if (text != null) ...<Widget>[
            const SizedBox(height: Gap.xs),
            PicText(text!, style: const TextStyle(fontSize: 16)),
          ],
          if (child != null) ...<Widget>[
            const SizedBox(height: Gap.sm),
            child!,
          ],
          for (final String l in lines)
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: PicText(l, style: const TextStyle(fontSize: 16)),
            ),
        ],
      ),
    );
  }
}

/// «Счета вышли…» → «счета вышли…»: после «Что мы поняли:».
String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
