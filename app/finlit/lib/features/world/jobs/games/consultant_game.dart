import 'package:flutter/material.dart';

import '../../../../core/feel.dart';
import '../../../../core/theme.dart';
import '../../pic_text.dart';
import '../../world_layout.dart';
import '../job_games.dart';
import '../mini_games.dart';
import '../../../../core/world_theme.dart';

/// Продавец-консультант: цены по полкам, затем товар под покупателя
/// (`docs/game/job-consultant.md`).
///
/// Наборы и подписи полок — `content/jobs.json → jobs.consultant`
/// ([ConsultantContent]). Порядок полок — по `price`.
@immutable
class ConsultantItem {
  const ConsultantItem(this.id, this.name, this.traits, this.price, this.why);

  factory ConsultantItem.fromData(JobData d) => ConsultantItem(
        dStr(d, 'id'),
        dStr(d, 'name'),
        dStrs(d, 'traits'),
        dInt(d, 'price'),
        dStr(d, 'why'),
      );

  final String id;
  final String name;
  final List<String> traits;
  final int price;
  final String why;
}

@immutable
class ConsultantCustomer {
  const ConsultantCustomer({
    required this.line,
    required this.budget,
    required this.bestFit,
    required this.feedbackFit,
    required this.feedbackCheaper,
    required this.feedbackPricier,
  });

  factory ConsultantCustomer.fromData(JobData d) => ConsultantCustomer(
        line: dStr(d, 'line'),
        budget: dInt(d, 'budget'),
        bestFit: dStr(d, 'best_fit'),
        feedbackFit: dStr(d, 'feedback_fit'),
        feedbackCheaper: dStr(d, 'feedback_cheaper'),
        feedbackPricier: dStr(d, 'feedback_pricier'),
      );

  final String line;
  final int budget;
  final String bestFit;
  final String feedbackFit;
  final String feedbackCheaper;
  final String feedbackPricier;
}

@immutable
class ConsultantSet {
  const ConsultantSet(this.id, this.category, this.items, this.customer);

  factory ConsultantSet.fromData(JobData d) => ConsultantSet(
        dStr(d, 'id'),
        dStr(d, 'category'),
        dObjs(d, 'items').map(ConsultantItem.fromData).toList(),
        ConsultantCustomer.fromData(dObj(d, 'customer')),
      );

  final String id;
  final String category;
  final List<ConsultantItem> items;
  final ConsultantCustomer customer;

  /// Полка товара: место по цене (0 — дешевле всех).
  int tierOf(ConsultantItem item) =>
      items.where((ConsultantItem o) => o.price < item.price).length;

  ConsultantItem get best =>
      items.firstWhere((ConsultantItem i) => i.id == customer.bestFit);
}

/// Подписи экрана игры «сравни три и выбери под бюджет». У консультанта —
/// магазин и сканер; у помощника бухгалтера (`jobs.accountant.texts`) —
/// предложения и смета. `{category}` в [sortIntro] — название набора.
@immutable
class ConsultantTexts {
  const ConsultantTexts({
    this.sortIntro = '{category}: ценники перепутались. Разложи по полкам — '
        'от дешёвого к дорогому.',
    this.check = 'Проверить сканером',
    this.checkWait = 'Разложи все товары, потом сканер',
    this.allOk = 'Все ценники на месте!',
    this.pick = 'Что посоветуешь? Нажми на товар.',
  });

  /// Поля файла, которых нет, — подписи консультанта.
  factory ConsultantTexts.fromData(JobData? d) {
    const ConsultantTexts base = ConsultantTexts();
    if (d == null) return base;
    return ConsultantTexts(
      sortIntro: dStrOrNull(d, 'sort_intro') ?? base.sortIntro,
      check: dStrOrNull(d, 'check') ?? base.check,
      checkWait: dStrOrNull(d, 'check_wait') ?? base.checkWait,
      allOk: dStrOrNull(d, 'all_ok') ?? base.allOk,
      pick: dStrOrNull(d, 'pick') ?? base.pick,
    );
  }

  final String sortIntro;
  final String check;
  final String checkWait;
  final String allOk;
  final String pick;

  String introFor(String category) =>
      sortIntro.replaceAll('{category}', category);
}

/// `jobs.json → jobs.consultant` (и `jobs.accountant` — та же игра).
@immutable
class ConsultantContent {
  const ConsultantContent({
    required this.tierLabels,
    required this.sets,
    this.texts = const ConsultantTexts(),
  });

  factory ConsultantContent.fromData(JobData d) => ConsultantContent(
        tierLabels: dStrs(d, 'tier_labels'),
        sets: dObjs(d, 'sets').map(ConsultantSet.fromData).toList(),
        texts: ConsultantTexts.fromData(d['texts'] as JobData?),
      );

  /// Подписи полок: дешевле → дороже.
  final List<String> tierLabels;
  final List<ConsultantSet> sets;

  /// Подписи экрана.
  final ConsultantTexts texts;

  /// Набор смены [round] — по кругу.
  ConsultantSet setFor(int round) => sets[round % sets.length];
}

const String consultantHelp = 'В магазине перепутались ценники. Сначала '
    'разложи товары по полкам: «Дешевле», «Средняя цена», «Дороже» — и '
    'проверь сканером. Потом покупатель скажет, что ему нужно и сколько у '
    'него денег: выбери подходящий товар. Дороже — не значит лучше. '
    'Ошибка не уменьшает оплату.';

/// Порядок показа товаров: не по цене, иначе полки угадываются сами.
const List<List<int>> _orders = <List<int>>[
  <int>[1, 2, 0],
  <int>[2, 0, 1],
  <int>[0, 2, 1],
  <int>[2, 1, 0],
];

Widget buildConsultantGame(BuildContext context, MiniGameArgs args) =>
    ConsultantGame(
        content: args.games.consultant, round: args.round, onDone: args.onDone);

/// Помощник бухгалтера студсовета (Денис 29.09, 941 п. 5): та же игра, что у
/// консультанта, — сравнить три предложения по цене и выбрать под смету.
/// Содержание — `jobs.json → jobs.accountant`.
const String accountantHelp = 'Студсовету нужно выбрать одно из трёх '
    'предложений. Сначала разложи их от дешёвого к дорогому и проверь по '
    'смете. Потом староста скажет, что нужно и сколько денег в смете: выбери '
    'подходящее. Дороже — не значит лучше, дешевле — тоже не всегда. '
    'Ошибка не уменьшает оплату.';

Widget buildAccountantGame(BuildContext context, MiniGameArgs args) =>
    ConsultantGame(
        content: args.games.accountant, round: args.round, onDone: args.onDone);

class ConsultantGame extends StatefulWidget {
  const ConsultantGame({
    super.key,
    required this.content,
    this.round = 0,
    required this.onDone,
  });

  final ConsultantContent content;
  final int round;
  final MiniGameDone onDone;

  @override
  State<ConsultantGame> createState() => _ConsultantGameState();
}

class _ConsultantGameState extends State<ConsultantGame> {
  late final ConsultantSet _set = widget.content.setFor(widget.round);
  late final List<ConsultantItem> _shown = <ConsultantItem>[
    for (final int i in _orders[widget.round % _orders.length]) _set.items[i],
  ];

  final Map<String, int> _shelf = <String, int>{};

  /// Товары, которые сканер нашёл не на своей полке.
  final Set<String> _wrong = <String>{};
  bool _scanned = false;
  bool _sorted = false;
  String? _picked;
  int _mistakes = 0;

  bool get _pickedRight => _picked == _set.customer.bestFit;

  void _put(ConsultantItem item, int tier) => setState(() {
        _shelf[item.id] = tier;
        _wrong.remove(item.id);
      });

  void _scan() {
    setState(() {
      _scanned = true;
      _wrong
        ..clear()
        ..addAll(<String>[
          for (final ConsultantItem i in _set.items)
            if (_shelf[i.id] != _set.tierOf(i)) i.id,
        ]);
      _mistakes += _wrong.length;
      if (_wrong.isEmpty) _sorted = true;
    });
    if (_wrong.isEmpty) context.cue(Cue.done);
  }

  void _pick(ConsultantItem item) {
    if (_pickedRight) return;
    setState(() {
      _picked = item.id;
      if (!_pickedRight) _mistakes++;
    });
    if (_pickedRight) context.cue(Cue.done);
  }

  double get _score => (1 - 0.25 * _mistakes).clamp(0.0, 1.0);

  String get _pickFeedback {
    final ConsultantCustomer c = _set.customer;
    if (_pickedRight) return c.feedbackFit;
    final ConsultantItem p =
        _set.items.firstWhere((ConsultantItem i) => i.id == _picked);
    return p.price < _set.best.price ? c.feedbackCheaper : c.feedbackPricier;
  }

  @override
  Widget build(BuildContext context) =>
      _sorted ? _buildPick(context) : _buildSort(context);

  Widget _buildSort(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool land = WorldLayout.isLandscape(context);
    final bool allPlaced = _shelf.length == _set.items.length;
    // Товар строкой (полки справа) — в альбомной при обычном шрифте; при
    // крупном полкам нужна вся ширина, и они встают под сведения.
    final bool row = land && MediaQuery.textScalerOf(context).scale(1) < 1.15;
    final Widget intro = Text(widget.content.texts.introFor(_set.category),
        style: gameText(context));
    Widget shelves(ConsultantItem item) => Wrap(
          spacing: Gap.xs,
          runSpacing: Gap.xs,
          children: <Widget>[
            for (int t = 0; t < widget.content.tierLabels.length; t++)
              ChoiceChip(
                key: ValueKey<String>('consultant:shelf:${item.id}:$t'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                labelStyle: const TextStyle(fontSize: 16),
                label: Text(widget.content.tierLabels[t]),
                selected: _shelf[item.id] == t,
                onSelected: (_) => _put(item, t),
              ),
          ],
        );
    Widget why(ConsultantItem item) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.info_rounded, color: WorldColors.wants),
            const SizedBox(width: Gap.xs),
            Expanded(
              child: Text(
                key: ValueKey<String>('consultant:why:${item.id}'),
                'Не та полка: здесь «${widget.content.tierLabels[_set.tierOf(item)]}». '
                '${item.why}',
                style: gameText(context),
              ),
            ),
          ],
        );
    final List<Widget> cards = <Widget>[
      for (final ConsultantItem item in _shown)
        Padding(
          padding: EdgeInsets.only(bottom: land ? Gap.xs : Gap.sm),
          child: _Card(
            color: _wrong.contains(item.id) ? WorldColors.wantsBg : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (row)
                  // Альбомная: товар строкой — сведения слева, полки справа.
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _ItemHead(
                            item: item, showPrice: _scanned, compact: true),
                      ),
                      const SizedBox(width: Gap.sm),
                      shelves(item),
                    ],
                  )
                else ...<Widget>[
                  _ItemHead(item: item, showPrice: _scanned, compact: land),
                  const SizedBox(height: Gap.xs),
                  shelves(item),
                ],
                if (_wrong.contains(item.id)) ...<Widget>[
                  const SizedBox(height: Gap.xs),
                  why(item),
                ],
              ],
            ),
          ),
        ),
    ];
    final Widget scan = FilledButton.icon(
      key: const ValueKey<String>('consultant:scan'),
      style: FilledButton.styleFrom(
          minimumSize: Size.fromHeight(gameButtonHeight(context))),
      onPressed: allPlaced ? _scan : null,
      icon: const Icon(Icons.qr_code_scanner_rounded),
      label: Text(allPlaced
          ? widget.content.texts.check
          : widget.content.texts.checkWait),
    );
    if (land) {
      // Товары прокручиваются, сканер всегда внизу на виду.
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final Widget list = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              intro,
              const SizedBox(height: Gap.xs),
              ...cards,
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (box.hasBoundedHeight)
                Expanded(child: SingleChildScrollView(child: list))
              else
                list,
              const SizedBox(height: Gap.xs),
              scan,
            ],
          );
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(widget.content.texts.introFor(_set.category),
            style: text.bodyLarge),
        const SizedBox(height: Gap.sm),
        ...cards,
        const SizedBox(height: Gap.sm),
        scan,
      ],
    );
  }

  Widget _buildPick(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool land = WorldLayout.isLandscape(context);
    final Widget sorted = _Card(
      color: WorldColors.needsBg,
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle_rounded, color: WorldColors.needs),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(widget.content.texts.allOk, style: gameText(context)),
          ),
        ],
      ),
    );
    final Widget customer = _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('🧑', style: TextStyle(fontSize: land ? 28 : 32)),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              key: const ValueKey<String>('consultant:customer'),
              '«${_set.customer.line}»',
              style: text.titleMedium,
            ),
          ),
        ],
      ),
    );
    final List<Widget> goods = <Widget>[
      Text(widget.content.texts.pick, style: gameText(context)),
      const SizedBox(height: Gap.xs),
      for (final ConsultantItem item in _shown)
        Padding(
          padding: EdgeInsets.only(bottom: land ? Gap.xs : Gap.sm),
          child: _Card(
            key: ValueKey<String>('consultant:pick:${item.id}'),
            color: item.id == _picked
                ? (_pickedRight ? WorldColors.needsBg : WorldColors.wantsBg)
                : null,
            onTap: _pickedRight ? null : () => _pick(item),
            semantic: '${item.name}, ${item.price} монет. Выбрать',
            child: _ItemHead(item: item, showPrice: true, compact: land),
          ),
        ),
    ];
    final List<Widget> outcome = <Widget>[
      if (_picked != null)
        _Card(
          key: const ValueKey<String>('consultant:feedback'),
          color: _pickedRight ? WorldColors.needsBg : WorldColors.wantsBg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                  _pickedRight
                      ? Icons.check_circle_rounded
                      : Icons.info_rounded,
                  color: _pickedRight ? WorldColors.needs : WorldColors.wants),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  _pickedRight
                      ? _pickFeedback
                      : '$_pickFeedback Выбери другой.',
                  style: gameText(context),
                ),
              ),
            ],
          ),
        ),
      if (_pickedRight) ...<Widget>[
        SizedBox(height: land ? Gap.sm : Gap.md),
        FilledButton.icon(
          key: const ValueKey<String>('consultant:done'),
          style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(gameButtonHeight(context))),
          onPressed: () => widget.onDone(_score),
          icon: const Icon(Icons.flag_rounded),
          label: const Text('Закончить смену'),
        ),
      ],
    ];
    if (land) {
      // Альбомная: покупатель и ответ слева, товары справа.
      return GameSplit(panes: <GamePane>[
        GamePane(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            sorted,
            const SizedBox(height: Gap.sm),
            customer,
            if (outcome.isNotEmpty) const SizedBox(height: Gap.sm),
            ...outcome,
          ],
        )),
        GamePane(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: goods,
        )),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        sorted,
        const SizedBox(height: Gap.sm),
        customer,
        const SizedBox(height: Gap.sm),
        ...goods,
        ...outcome,
      ],
    );
  }
}

class _ItemHead extends StatelessWidget {
  const _ItemHead(
      {required this.item, required this.showPrice, this.compact = false});

  final ConsultantItem item;
  final bool showPrice;

  /// Альбомная: свойства одной строкой через «·».
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: Text(item.name, style: text.titleMedium)),
            const SizedBox(width: Gap.sm),
            PicText(showPrice ? '💰 ${item.price}' : '💰 ?',
                style: AppType.number(18, color: WorldColors.text)),
          ],
        ),
        if (compact)
          Text(item.traits.join(' · '), style: gameText(context))
        else
          for (final String t in item.traits)
            Text('• $t', style: text.bodyLarge),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.child,
    this.color,
    this.onTap,
    this.semantic,
  });

  final Widget child;
  final Color? color;
  final VoidCallback? onTap;
  final String? semantic;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(Radii.chip);
    Widget body = Padding(padding: const EdgeInsets.all(Gap.sm), child: child);
    if (onTap != null) {
      body = InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: TapSize.min),
          child: body,
        ),
      );
    }
    final Widget card = Material(
      color: color ?? WorldColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
            color: onTap != null ? WorldColors.text : WorldColors.line,
            width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
    if (semantic == null) return card;
    return Semantics(button: onTap != null, label: semantic, child: card);
  }
}
