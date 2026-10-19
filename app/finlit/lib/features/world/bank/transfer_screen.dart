import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../core/world_theme.dart';
import '../../../domain/phrases.dart';
import '../../../domain/world/contract.dart';
import '../../../domain/world/world_game.dart';
import '../home/plan_amount.dart';
import '../shop/shop_kit.dart';
import '../world_state.dart';
import '../world_dock.dart';

/// Банк с переводами включён (`economy.json → bank.transfer`, ТЗ Насти
/// «Начальное обучение» 18.10, экраны 10–11). Фейк-мир — выключен: экраны на
/// фейке выглядят как сборка. Решение о включении — DEN-41.
bool bankTransferOn(World w) => w is WorldGame && w.config.bankTransfer;

/// Ключ «уже показано» карточки «Что такое банк?» в профиле ([World.seen]).
const String bankIntroSeen = 'bank.intro';

/// Тексты банка — ТЗ Насти, экраны 10–11, переписанные по её правилам Т1 Б
/// и Т5 Б (решение pm 19.10): «конверт» только в сценке знакомства, здесь —
/// «часть»; к ребёнку без рода («хочется», «мы перевели»), без «мечты».
abstract final class BankTexts {
  /// Экран 10 — «Что такое банк?» (точный текст утверждён).
  static const String introTitle = 'Что такое банк?';
  static const String intro = 'В банке люди хранят деньги, переводят их и '
      'копят на большие покупки. А иногда берут деньги в долг. Пока мы '
      'научимся самому простому — переводить монеты из одной части в другую!';
  static const String introButton = 'Попробовать перевод';

  // Экран 11 — «Перевод между частями».
  static const String title = 'Перевод монет';
  static const String subtitle = 'Из одной части в другую';
  static const String hello = 'Иногда планы меняются! Например, хочется '
      'отложить больше на цель. В банке монеты можно переводить из части в '
      'часть. Давай попробуем!';
  static const String from = 'Откуда';
  static const String to = 'Куда';
  static const String howMuch = 'Сколько монет перевести?';
  static const String after = 'После перевода';
  static const String afterDone =
      'Видишь? Мы ничего не потратили! Просто переложили монеты в другую часть.';
  static const String understood = 'Понятно';

  static String go(int n) => 'Перевести $n ${Phrases.coinsAcc(n)}';
  static String total(int n) => 'Всего монет: $n';
}

/// Открыть «Перевод монет» поверх текущего экрана.
Future<void> openTransfer(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const WorldTheme(child: TransferScreen()),
    ));

/// Карточка «Что такое банк?» (ТЗ Насти, экран 10): один раз — при первом
/// входе в здание «Банк». Отмечается показанной сразу, ещё до ответа: закрыл
/// без перевода — второй раз не покажется. «Попробовать перевод» открывает
/// [TransferScreen].
Future<void> showBankIntro(BuildContext context) async {
  final WorldState st = context.read<WorldState>();
  if (!bankTransferOn(st.world) || st.world.seen(bankIntroSeen)) return;
  await st.markSeen(bankIntroSeen);
  if (!context.mounted) return;
  final bool? go = await showDialog<bool>(
    context: context,
    builder: (BuildContext c) => AlertDialog(
      key: const ValueKey<String>('bank:intro'),
      title: const Text(BankTexts.introTitle),
      content: const SingleChildScrollView(
        child: Text(BankTexts.intro, style: kitText),
      ),
      actions: <Widget>[
        FilledButton(
          key: const ValueKey<String>('bank:intro:go'),
          style: FilledButton.styleFrom(minimumSize: kitButton),
          onPressed: () => Navigator.of(c).pop(true),
          child: const Text(BankTexts.introButton),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) await openTransfer(context);
}

/// «Перевод монет» (ТЗ Насти, экран 11): Откуда → Куда → Сколько → После
/// перевода → подтверждение кнопкой «Перевести N монет». Части — «Нужное ·
/// Хочу · Копилка»; заработок не участвует (вопрос В3 к Насте).
///
/// «Всего монет» — сумма трёх частей: в HUD копилки нет, и после «Хочу →
/// Копилка» число HUD уменьшится, хотя монет столько же (В3).
class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  /// Шаг суммы — как в копилке.
  static const int step = 10;

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  MoneyPart _from = MoneyPart.want;
  MoneyPart _to = MoneyPart.goal;
  int _amount = 0;

  /// Перевод идёт: второе касание до перерисовки ничего не делает.
  bool _busy = false;

  /// «+» упёрся в остаток: показать ошибку ТЗ.
  bool _blocked = false;

  /// Отказ мира, если экран его не предвидел.
  String? _refused;

  /// Ключ этой операции: одна форма — один перевод. Новый — после успеха.
  late String _opId = _newOpId();
  static int _ops = 0;
  static String _newOpId() =>
      'tr-${DateTime.now().microsecondsSinceEpoch}-${_ops++}';

  void _set(void Function() f) => setState(() {
        f();
        _blocked = false;
        _refused = null;
      });

  /// Ошибка ТЗ для текущего выбора, или null.
  String? _error(World w, ResourceSnapshot s) {
    // Неделя не идёт (план, итоги) — причина мира сразу, а не после касания.
    final BlockReason? block = w.canDo(WorldAction.transfer);
    if (block != null) return block.text;
    if (_from == _to) return transferSame.text;
    if (_blocked || _amount > _from.of(s)) return transferTooMuch.text;
    return _refused;
  }

  Future<void> _go() async {
    if (_busy) return;
    _busy = true;
    final WorldState st = context.read<WorldState>();
    final WorldResult r = st.act((World w) =>
        w.transfer(from: _from, to: _to, amount: _amount, opId: _opId));
    if (!r.ok) {
      setState(() {
        _refused = r.reason;
        _busy = false;
      });
      return;
    }
    setState(() {
      _amount = 0;
      _opId = _newOpId();
    });
    await showDialog<void>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        key: const ValueKey<String>('transfer:done'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(r.reason,
                  key: const ValueKey<String>('transfer:done:text'),
                  style: kitTitle),
              const SizedBox(height: Gap.sm),
              const Text(BankTexts.afterDone, style: kitText),
            ],
          ),
        ),
        actions: <Widget>[
          FilledButton(
            key: const ValueKey<String>('transfer:done:ok'),
            style: FilledButton.styleFrom(minimumSize: kitButton),
            onPressed: () => Navigator.of(c).pop(),
            child: const Text(BankTexts.understood),
          ),
        ],
      ),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final WorldState st = context.watch<WorldState>();
    final ResourceSnapshot s = st.snapshot;
    final int fromHas = _from.of(s);
    final String? error = _error(st.world, s);
    final bool first =
        st.world.weekHistory.every((WeekPlanFact w) => w.transfers.isEmpty);
    final bool can = error == null && _amount > 0 && !_busy;

    Widget parts(String id, MoneyPart chosen, ValueChanged<MoneyPart> pick) =>
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: <Widget>[
            for (final MoneyPart p in MoneyPart.values)
              _PartTile(
                key: ValueKey<String>('transfer:$id:${p.name}'),
                part: p,
                balance: p.of(s),
                selected: p == chosen,
                onTap: () => pick(p),
              ),
          ],
        );

    return WorldPage(
      id: 'transfer',
      dock: DockSection.plan,
      title: BankTexts.title,
      snapshot: s,
      helpTitle: BankTexts.title,
      help: 'Перевод перекладывает монеты из одной части в другую: «Нужно», '
          '«Хочу», «Копилка». Это не трата: монет всего столько же.',
      // Не ListView: экран короткий, а «Перевести» внизу должен строиться
      // сразу (прокрутка к нему, проверки целей касания).
      body: SingleChildScrollView(
        key: const ValueKey<String>('transfer:list'),
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(BankTexts.subtitle, style: kitSoft),
            if (first) ...<Widget>[
              const SizedBox(height: Gap.sm),
              const Panel(
                key: ValueKey<String>('transfer:hello'),
                color: WorldColors.raised,
                padding: EdgeInsets.all(Gap.sm),
                child: Text(BankTexts.hello, style: kitText),
              ),
            ],
            const SizedBox(height: Gap.md),
            const Text(BankTexts.from, style: kitTitle),
            const SizedBox(height: Gap.xs),
            parts('from', _from, (MoneyPart p) => _set(() => _from = p)),
            const SizedBox(height: Gap.md),
            const Text(BankTexts.to, style: kitTitle),
            const SizedBox(height: Gap.xs),
            parts('to', _to, (MoneyPart p) => _set(() => _to = p)),
            const SizedBox(height: Gap.md),
            const Text(BankTexts.howMuch, style: kitTitle),
            Row(
              children: <Widget>[
                HoldStepButton(
                  key: const ValueKey<String>('transfer:minus'),
                  label: 'Меньше на ${TransferScreen.step}',
                  icon: Icons.remove_rounded,
                  value: _amount,
                  max: fromHas,
                  step: TransferScreen.step,
                  up: false,
                  onChanged: (int v) => _set(() => _amount = v),
                ),
                Expanded(
                  child: Text(
                    '$_amount',
                    key: const ValueKey<String>('transfer:amount'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: WorldColors.text),
                  ),
                ),
                HoldStepButton(
                  key: const ValueKey<String>('transfer:plus'),
                  label: 'Больше на ${TransferScreen.step}',
                  icon: Icons.add_rounded,
                  value: _amount,
                  max: fromHas,
                  step: TransferScreen.step,
                  up: true,
                  onChanged: (int v) => _set(() => _amount = v),
                  onBlocked: () => setState(() => _blocked = true),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Panel(
              key: const ValueKey<String>('transfer:after'),
              color: WorldColors.panel,
              padding: const EdgeInsets.all(Gap.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(BankTexts.after, style: kitTitle),
                  const SizedBox(height: Gap.xs),
                  if (_from != _to) ...<Widget>[
                    Text(
                        '${_from.title}: $fromHas → '
                        '${fromHas - (_amount > fromHas ? 0 : _amount)}',
                        key: const ValueKey<String>('transfer:after:from'),
                        style: kitText),
                    Text(
                        '${_to.title}: ${_to.of(s)} → '
                        '${_to.of(s) + (_amount > fromHas ? 0 : _amount)}',
                        key: const ValueKey<String>('transfer:after:to'),
                        style: kitText),
                  ],
                  Text(BankTexts.total(s.need + s.want + s.goal),
                      key: const ValueKey<String>('transfer:total'),
                      style: kitText),
                ],
              ),
            ),
            if (error != null) ...<Widget>[
              const SizedBox(height: Gap.sm),
              Text(error,
                  key: const ValueKey<String>('transfer:error'),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: WorldColors.danger)),
            ],
            const SizedBox(height: Gap.sm),
            FilledButton(
              key: const ValueKey<String>('transfer:go'),
              style: FilledButton.styleFrom(minimumSize: kitButton),
              onPressed: can ? _go : null,
              child: Text(BankTexts.go(_amount)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Одна часть с остатком: касание выбирает её.
class _PartTile extends StatelessWidget {
  const _PartTile({
    super.key,
    required this.part,
    required this.balance,
    required this.selected,
    required this.onTap,
  });

  final MoneyPart part;
  final int balance;
  final bool selected;
  final VoidCallback onTap;

  Color get _accent => switch (part) {
        MoneyPart.need => WorldColors.needs,
        MoneyPart.want => WorldColors.wants,
        MoneyPart.goal => WorldColors.goal,
      };

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: '${part.title}: $balance',
        excludeSemantics: true,
        child: Material(
          color: selected ? WorldColors.raised : WorldColors.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorldRadii.tile),
            side: BorderSide(
                color: selected ? _accent : WorldColors.line,
                width: selected ? 3 : 1.5),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(WorldRadii.tile),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96, minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: Gap.sm, vertical: Gap.xs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(part.title,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _accent)),
                    Text('$balance', style: kitText),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
