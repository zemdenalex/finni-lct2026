import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';
import '../shop/shop_kit.dart';
import '../world_state.dart';
import 'daily_rules.dart';

/// Карточка «Сегодня» (вариант A страницы `docs/final/daily-activities/`):
/// дела дня с ценой в ⚡, сколько дел ещё хватит сил, что лежит в
/// холодильнике. Вечером (сил нет) дела гаснут, карточка говорит «пора спать».
class DailyCard extends StatelessWidget {
  const DailyCard({super.key, required this.rules});

  final DailyRules rules;

  static const TextStyle _soft = TextStyle(
      fontSize: 14, color: WorldColors.textSoft, fontFamily: AppType.family);

  @override
  Widget build(BuildContext context) {
    final WorldState ws = context.watch<WorldState>();
    final World w = ws.world;
    final ResourceSnapshot s = w.snapshot;
    final bool evening = isEvening(w);
    final int acts = actsLeftToday(w);
    final int portions = fridgePortions(s);
    // Можно ли сейчас — у мира (контракт §4): кнопка гаснет с причиной до
    // нажатия. Магазин проверяется на домашнем блюде, одна порция.
    final BlockReason? restBlock = w.canDo(WorldAction.restAtHome);
    final String? homeFood = s.foodId;
    final BlockReason? shopBlock = homeFood == null
        ? null
        : w.canDo(WorldAction.stockFridge, id: homeFood, variant: '1');
    final Set<String> done = s.doneToday;
    final BlockReason? why = evening ? null : (shopBlock ?? restBlock);
    // Силы кончились — домен сам кладёт Финни спать, и сразу утро (D7,
    // контракт §2): отдельного вечера нет, поэтому карточка называет
    // переход словами, пока ребёнок не сделает следующее дело.
    final bool morning = !evening && _newDay(ws.lastResult);
    final Widget title = Text(
      // День недели — в HUD («День 1 из 3»), здесь не повторяем:
      // на 360 dp строка с «сил на N дел» не помещалась.
      evening ? 'Вечер' : (morning ? 'Утро' : 'Сегодня'),
      key: const ValueKey<String>('daily:title'),
      style: AppType.title(15, color: WorldColors.gold),
    );
    final List<Widget> left = <Widget>[
      const Pictogram(Pic.bolt, size: 16, color: WorldColors.energy),
      const SizedBox(width: Gap.xs),
      Flexible(
        child: Text(
          evening ? 'сил нет — пора спать' : 'сил на $acts ${_actsWord(acts)}',
          key: const ValueKey<String>('daily:left'),
          style: _soft,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ];
    final Widget shop = _Act(
      key: const ValueKey<String>('daily:shop'),
      pic: Pic.basket,
      title: 'Магазин',
      done: done.contains('fridge'),
      energy: rules.shopEnergy,
      said: 'Магазин: наполнить холодильник. Силы: '
          'минус ${_num(rules.shopEnergy)}',
      onTap: evening || shopBlock != null ? null : () => _stock(context),
    );
    final Widget rest = _Act(
      key: const ValueKey<String>('daily:rest'),
      pic: Pic.house,
      title: 'Отдых',
      done: done.contains('rest'),
      energy: rules.restEnergy,
      extra: '+${rules.restHappiness}',
      said: 'Отдых дома. Силы: минус '
          '${_num(rules.restEnergy)}, настроение: плюс '
          '${rules.restHappiness}',
      onTap: evening || restBlock != null ? null : () => _rest(context),
    );
    return Material(
      key: const ValueKey<String>('daily:card'),
      color: WorldColors.panel.withValues(alpha: 0.95),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WorldRadii.tile),
        side: const BorderSide(color: WorldColors.line, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.sm),
        // В альбомной карточка стоит в узкой боковой «Сейчас» (~154 dp):
        // два дела в ряд и «сил на N дел» рядом с заголовком не помещаются
        // (переполнение 39 px, аудит 16.10) — тогда ставим друг под другом.
        child: LayoutBuilder(
          builder: (BuildContext _, BoxConstraints box) {
            final bool narrow = box.maxWidth < 300;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (narrow) ...<Widget>[
                  title,
                  Row(children: left),
                ] else
                  Row(children: <Widget>[title, const Spacer(), ...left]),
                const SizedBox(height: Gap.xs),
                if (narrow) ...<Widget>[
                  shop,
                  const SizedBox(height: Gap.xs),
                  rest,
                ] else
                  Row(
                    children: <Widget>[
                      Expanded(child: shop),
                      const SizedBox(width: Gap.xs),
                      Expanded(child: rest),
                    ],
                  ),
                if (why != null) ...<Widget>[
                  const SizedBox(height: Gap.xs),
                  Text(why.text,
                      key: const ValueKey<String>('daily:why'), style: _soft),
                ],
                if (done.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Gap.xs),
                  Text('Сегодня сделано: ${_doneText(done)}',
                      key: const ValueKey<String>('daily:done'), style: _soft),
                ],
                const SizedBox(height: Gap.xs),
                Text(
                  portions == 0
                      ? 'Холодильник пуст'
                      : 'В холодильнике: ${_fridgeText(w)} — '
                          'Финни поест сам утром',
                  key: const ValueKey<String>('daily:fridge'),
                  style: _soft,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Последнее действие закончило день: «Спать» не в последний день или
  /// дело, после которого сил не осталось.
  static bool _newDay(WorldResult? r) =>
      r != null &&
      r.ok &&
      (r.reasonCode == 'day.next' || r.reason.contains('наступил вечер'));

  /// Коды `snapshot.doneToday` словами, в порядке дня.
  static String _doneText(Set<String> done) => <(String, String)>[
        ('meal', 'поел'),
        ('pet', 'погладили'),
        ('job', 'смена'),
        ('fridge', 'магазин'),
        ('rest', 'отдых'),
      ]
          .where(((String, String) e) => done.contains(e.$1))
          .map(((String, String) e) => e.$2)
          .join(' · ');

  static String _actsWord(int n) {
    final int m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'дело';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дела';
    return 'дел';
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  static String _fridgeText(World w) => <String>[
        for (final MapEntry<String, int> e in w.snapshot.fridge.entries)
          '${w.catalogItem(e.key)?.title.toLowerCase() ?? e.key} × ${e.value}',
      ].join(', ');

  void _say(BuildContext context, WorldResult r) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(r.reason)));
  }

  void _rest(BuildContext context) {
    final WorldResult r =
        context.read<WorldState>().act((World w) => w.restAtHome());
    _say(context, r);
  }

  Future<void> _stock(BuildContext context) async {
    final WorldState ws = context.read<WorldState>();
    final (String, int)? pick = await showModalBottomSheet<(String, int)>(
      context: context,
      backgroundColor: WorldColors.panel,
      isScrollControlled: true,
      builder: (BuildContext c) => _FridgeSheet(world: ws.world, rules: rules),
    );
    if (pick == null || !context.mounted) return;
    final WorldResult r = ws.act((World w) => w.stockFridge(pick.$1, pick.$2));
    _say(context, r);
  }
}

/// Дело дня: значок, название, цена в ⚡. Вечером погашено.
class _Act extends StatelessWidget {
  const _Act({
    super.key,
    required this.pic,
    required this.title,
    required this.energy,
    required this.said,
    required this.onTap,
    this.extra,
    this.done = false,
  });

  final Pic pic;
  final String title;
  final double energy;
  final String? extra;
  final String said;
  final VoidCallback? onTap;

  /// Уже сделано сегодня (`snapshot.doneToday`): галочка вместо значка.
  final bool done;

  @override
  Widget build(BuildContext context) {
    final bool off = onTap == null;
    final Color c = off ? WorldColors.textMute : WorldColors.text;
    return Semantics(
      button: true,
      enabled: !off,
      label: done ? '$said. Сегодня уже сделано' : said,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: WorldColors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorldRadii.tag),
          side: const BorderSide(color: WorldColors.line, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(WorldRadii.tag),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // Сделано — галочка на месте значка: рядом со значком в узкой
                  // карточке (альбомная, шрифт 1,3) название сжималось до «О…».
                  if (done)
                    const Icon(Icons.check_rounded,
                        size: 18, color: WorldColors.needs)
                  else
                    Pictogram(pic, size: 18, color: c),
                  const SizedBox(width: Gap.xs),
                  Flexible(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            color: c,
                            fontFamily: AppType.family,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: Gap.xs),
                  Pictogram(Pic.bolt,
                      size: 14,
                      color: off ? WorldColors.textMute : WorldColors.energy),
                  Text(DailyCard._num(energy),
                      style: TextStyle(
                          fontSize: 14, color: c, fontFamily: AppType.family)),
                  if (extra != null) ...<Widget>[
                    const SizedBox(width: Gap.xs),
                    Pictogram(Pic.heart,
                        size: 14,
                        color: off ? WorldColors.textMute : WorldColors.mood),
                    Text(extra!,
                        style: TextStyle(
                            fontSize: 14,
                            color: c,
                            fontFamily: AppType.family)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Что и сколько положить в холодильник. Платится сразу, ест Финни сам —
/// по порции утром (контракт §4).
class _FridgeSheet extends StatefulWidget {
  const _FridgeSheet({required this.world, required this.rules});

  final World world;
  final DailyRules rules;

  @override
  State<_FridgeSheet> createState() => _FridgeSheetState();
}

class _FridgeSheetState extends State<_FridgeSheet> {
  /// Порций сразу — на оставшиеся дни, но не больше, чем по карману хоть
  /// одному блюду: в неделе из 7 дней 7 порций дороже кошелька, и все
  /// кнопки листа были серыми, пока ребёнок не нажмёт «−» несколько раз.
  /// Может ли — решает мир (`canDo`), не своя арифметика цен.
  late int _count = _startCount();

  int _startCount() {
    final World w = widget.world;
    final List<WorldCatalogItem> foods =
        catalogOf(w, WorldCatalogCategory.food);
    for (int n = daysLeftInWeek(w.snapshot); n > 1; n--) {
      if (foods.any((WorldCatalogItem f) =>
          w.canDo(WorldAction.stockFridge, id: f.id, variant: '$n') == null)) {
        return n;
      }
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final World w = widget.world;
    final ResourceSnapshot s = w.snapshot;
    final int maxCount = s.daysPerWeek;
    const TextStyle body = TextStyle(
        fontSize: 16, color: WorldColors.text, fontFamily: AppType.family);
    // Блюд больше десятка: лист прокручивается, а не вылезает за экран.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Наполнить холодильник',
                style: AppType.title(18, color: WorldColors.text)),
            const SizedBox(height: Gap.xs),
            Text(
                'Платишь сейчас, а Финни ест сам — по порции утром. '
                'Поход в магазин тратит силы: '
                '${DailyCard._num(widget.rules.shopEnergy)}.',
                style: body.copyWith(color: WorldColors.textSoft)),
            const SizedBox(height: Gap.sm),
            Row(
              children: <Widget>[
                const Expanded(child: Text('Порций', style: body)),
                IconButton(
                  key: const ValueKey<String>('daily:fridge:minus'),
                  tooltip: 'Меньше',
                  onPressed: _count > 1 ? () => setState(() => _count--) : null,
                  icon:
                      const Icon(Icons.remove_rounded, color: WorldColors.text),
                ),
                Text('$_count',
                    key: const ValueKey<String>('daily:fridge:count'),
                    style: AppType.title(18, color: WorldColors.text)),
                IconButton(
                  key: const ValueKey<String>('daily:fridge:plus'),
                  tooltip: 'Больше',
                  onPressed:
                      _count < maxCount ? () => setState(() => _count++) : null,
                  icon: const Icon(Icons.add_rounded, color: WorldColors.text),
                ),
              ],
            ),
            const SizedBox(height: Gap.xs),
            for (final WorldCatalogItem f
                in catalogOf(w, WorldCatalogCategory.food))
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.xs),
                // Контур, не золото: золотая кнопка на экране одна
                // (docs/design-system.md, принцип 6), а блюд в списке много.
                child: OutlinedButton(
                  key: ValueKey<String>('daily:fridge:${f.id}'),
                  onPressed: w.canDo(WorldAction.stockFridge,
                              id: f.id, variant: '$_count') ==
                          null
                      ? () => Navigator.of(context).pop((f.id, _count))
                      : null,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(TapSize.min),
                      side:
                          const BorderSide(color: WorldColors.needs, width: 2)),
                  child: Text('${f.title} × $_count — ${f.price * _count}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
