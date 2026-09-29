import 'package:flutter/material.dart';

import '../../../../core/feel.dart';
import '../../../../core/theme.dart';
import '../../world_layout.dart';
import '../job_games.dart';
import '../mini_games.dart';
import '../../../../core/world_theme.dart';

/// Кассир: собрать сдачу монетами (`docs/game/job-cashier.md`).
///
/// Покупки, монеты и тексты — `content/jobs.json → jobs.cashier`
/// ([CashierContent]). Поле `change` из файла не берём: сдачу считает код
/// (`paid − price`).
@immutable
class CashierPurchase {
  const CashierPurchase(this.id, this.item, this.price, this.paidWith);

  factory CashierPurchase.fromData(JobData d) => CashierPurchase(
      dStr(d, 'id'), dStr(d, 'item'), dInt(d, 'price'), dInt(d, 'paid_with'));

  final String id;
  final String item;
  final int price;
  final int paidWith;

  /// Сдача считается кодом, а не берётся из файла.
  int get change => paidWith - price;
}

/// `jobs.json → jobs.cashier`.
@immutable
class CashierContent {
  const CashierContent({
    required this.coins,
    required this.purchases,
    required this.customersPerShift,
    required this.feedbackRight,
    required this.feedbackTooLittle,
    required this.feedbackTooMuch,
  });

  factory CashierContent.fromData(JobData d) {
    final JobData fb = dObj(d, 'feedback');
    return CashierContent(
      coins: dInts(d, 'coins'),
      purchases: dObjs(d, 'purchases').map(CashierPurchase.fromData).toList(),
      customersPerShift: dInt(d, 'customers_per_shift'),
      feedbackRight: dStr(fb, 'right'),
      feedbackTooLittle: dStr(fb, 'too_little'),
      feedbackTooMuch: dStr(fb, 'too_much'),
    );
  }

  /// Монеты в лотке.
  final List<int> coins;
  final List<CashierPurchase> purchases;

  /// Покупателей за смену.
  final int customersPerShift;
  final String feedbackRight;

  /// `{diff}` — на сколько ошибся.
  final String feedbackTooLittle;
  final String feedbackTooMuch;

  /// Покупки смены [round]: по кругу по списку.
  List<CashierPurchase> purchasesFor(int round) => <CashierPurchase>[
        for (int i = 0; i < customersPerShift; i++)
          purchases[(round * customersPerShift + i) % purchases.length],
      ];
}

const String cashierHelp = 'Покупатель платит купюрой. Посчитай сдачу: '
    'из того, что дали, вычти цену. Нажимай на монеты — они попадут в '
    'сдачу, сумма видна числом. Лишнюю монету можно убрать. Подходит '
    'любой набор монет с нужной суммой. Таймера нет — ошибка не уменьшает '
    'оплату.';

Widget buildCashierGame(BuildContext context, MiniGameArgs args) => CashierGame(
    content: args.games.cashier, round: args.round, onDone: args.onDone);

class CashierGame extends StatefulWidget {
  const CashierGame({
    super.key,
    required this.content,
    this.round = 0,
    required this.onDone,
  });

  final CashierContent content;
  final int round;
  final MiniGameDone onDone;

  @override
  State<CashierGame> createState() => _CashierGameState();
}

enum _Verdict { right, tooLittle, tooMuch }

class _CashierGameState extends State<CashierGame> {
  late final List<CashierPurchase> _queue =
      widget.content.purchasesFor(widget.round);
  int _index = 0;
  final List<int> _given = <int>[];
  _Verdict? _verdict;
  int _diff = 0;
  bool _missedThis = false;
  int _firstTry = 0;

  CashierPurchase get _p => _queue[_index];
  int get _sum => _given.fold(0, (int a, int b) => a + b);
  bool get _solved => _verdict == _Verdict.right;
  bool get _last => _index == _queue.length - 1;

  void _add(int coin) => setState(() {
        _given.add(coin);
        _verdict = null;
      });

  void _undo() => setState(() {
        if (_given.isNotEmpty) _given.removeLast();
        _verdict = null;
      });

  void _give() {
    final int change = _p.change;
    setState(() {
      if (_sum == change) {
        _verdict = _Verdict.right;
        if (!_missedThis) _firstTry++;
      } else {
        _missedThis = true;
        _verdict = _sum < change ? _Verdict.tooLittle : _Verdict.tooMuch;
        _diff = (_sum - change).abs();
      }
    });
    if (_sum == change) context.cue(Cue.done);
  }

  void _next() {
    if (_last) {
      widget.onDone(_firstTry / _queue.length);
      return;
    }
    setState(() {
      _index++;
      _given.clear();
      _verdict = null;
      _missedThis = false;
    });
  }

  String get _feedback => switch (_verdict!) {
        _Verdict.right => widget.content.feedbackRight,
        _Verdict.tooLittle =>
          widget.content.feedbackTooLittle.replaceAll('{diff}', '$_diff'),
        _Verdict.tooMuch =>
          widget.content.feedbackTooMuch.replaceAll('{diff}', '$_diff'),
      };

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final CashierPurchase p = _p;
    final bool land = WorldLayout.isLandscape(context);
    final Widget counter = Text('Покупатель ${_index + 1} из ${_queue.length}',
        style: text.bodyMedium);
    final Widget purchase = _Box(
      child: Row(
        children: <Widget>[
          Text('🧑', style: TextStyle(fontSize: land ? 28 : 36)),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              key: const ValueKey<String>('cashier:purchase'),
              '${p.item} стоит ${p.price}. Покупатель даёт ${p.paidWith}.',
              style: text.titleMedium,
            ),
          ),
        ],
      ),
    );
    final Widget trayTitle = Text('Лоток с монетами', style: text.titleSmall);
    final Widget tray = Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      children: <Widget>[
        for (final int c in widget.content.coins)
          _CoinButton(
            key: ValueKey<String>('cashier:coin:$c'),
            value: c,
            onTap: _solved ? null : () => _add(c),
          ),
      ],
    );
    final Widget sum = _Box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            key: const ValueKey<String>('cashier:sum'),
            'Сдача: $_sum',
            style: AppType.number(22, color: WorldColors.text),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            _given.isEmpty ? 'Пока пусто' : _given.join(' + '),
            style: gameText(context),
          ),
        ],
      ),
    );
    final List<Widget> feedback = <Widget>[
      if (_verdict != null) ...<Widget>[
        const SizedBox(height: Gap.sm),
        _Box(
          key: const ValueKey<String>('cashier:feedback'),
          color: _solved ? WorldColors.needsBg : WorldColors.wantsBg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(_solved ? Icons.check_circle_rounded : Icons.info_rounded,
                  color: _solved ? WorldColors.needs : WorldColors.wants),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  '$_feedback\n'
                  '${p.paidWith} − ${p.price} = ${p.change}'
                  '${_solved ? '' : ', а в сдаче $_sum.'}',
                  style: gameText(context),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
    final double h = land ? 48 : TapSize.min;
    final Widget actions = _solved
        ? FilledButton.icon(
            key: const ValueKey<String>('cashier:next'),
            style: FilledButton.styleFrom(
                minimumSize: Size.fromHeight(gameButtonHeight(context))),
            onPressed: _next,
            icon:
                Icon(_last ? Icons.flag_rounded : Icons.arrow_forward_rounded),
            label: Text(_last ? 'Закончить смену' : 'Следующий покупатель'),
          )
        : Flex(
            // Альбомная: панель узкая — «Отдать» над «Убрать», во всю ширину.
            direction: land ? Axis.vertical : Axis.horizontal,
            verticalDirection:
                land ? VerticalDirection.up : VerticalDirection.down,
            crossAxisAlignment:
                land ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
            children: <Widget>[
              _flexible(
                land,
                OutlinedButton.icon(
                  key: const ValueKey<String>('cashier:undo'),
                  style:
                      OutlinedButton.styleFrom(minimumSize: Size.fromHeight(h)),
                  onPressed: _given.isEmpty ? null : _undo,
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Убрать'),
                ),
              ),
              const SizedBox(width: Gap.sm, height: Gap.sm),
              _flexible(
                land,
                FilledButton.icon(
                  key: const ValueKey<String>('cashier:give'),
                  style:
                      FilledButton.styleFrom(minimumSize: Size.fromHeight(h)),
                  onPressed: _give,
                  icon: const Icon(Icons.payments_rounded),
                  label: const Text('Отдать сдачу'),
                ),
              ),
            ],
          );

    if (land) {
      // Альбомная: покупатель и сдача слева, лоток и кнопки справа.
      return GameSplit(panes: <GamePane>[
        GamePane(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            counter,
            const SizedBox(height: Gap.xs),
            purchase,
            const SizedBox(height: Gap.sm),
            sum,
            ...feedback,
          ],
        )),
        GamePane(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            trayTitle,
            const SizedBox(height: Gap.xs),
            tray,
            const SizedBox(height: Gap.md),
            actions,
          ],
        )),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        counter,
        const SizedBox(height: Gap.xs),
        purchase,
        const SizedBox(height: Gap.md),
        trayTitle,
        const SizedBox(height: Gap.xs),
        tray,
        const SizedBox(height: Gap.md),
        sum,
        ...feedback,
        const SizedBox(height: Gap.md),
        actions,
      ],
    );
  }
}

/// В ряду кнопки делят ширину, в столбике — каждая своей высоты.
Widget _flexible(bool column, Widget child) =>
    column ? child : Expanded(child: child);

class _CoinButton extends StatelessWidget {
  const _CoinButton({super.key, required this.value, required this.onTap});

  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Монета $value',
        excludeSemantics: true,
        onTap:
            onTap, // иначе excludeSemantics отсекает касание: TalkBack не нажмёт
        child: Material(
          color: onTap == null ? WorldColors.raised : WorldColors.gold,
          shape: const CircleBorder(
              side: BorderSide(color: WorldColors.gold, width: 2)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: TapSize.min + 8,
              child: Center(
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.xs),
                    child: Text('$value',
                        style: AppType.number(22, color: WorldColors.text)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Плашка-сведения (не кнопка).
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
