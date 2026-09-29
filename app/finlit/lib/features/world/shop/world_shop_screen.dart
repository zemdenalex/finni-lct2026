import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../domain/phrases.dart';
import '../../../domain/world/contract.dart';
import '../home/world_hud.dart';
import '../world_layout.dart';
import '../world_state.dart';
import '../pic_text.dart';
import 'shop_kit.dart';
import '../../../core/world_theme.dart';

/// S4 — магазин: еда (НУЖНО), «Хочу» (перекус, вещи для комнаты), одежда
/// (`docs/game/shop-purchases.md`).
///
/// Еда (Денис 29.09, 938): блюда с тремя шкалами — цена, польза (⚡ сразу)
/// и вкус (😊). Ребёнок сам выбирает, что Финни съест сейчас; приёмов в
/// неделю немного, а невыбранные Финни ест дома в итогах недели.
///
/// 🔴 До каждой покупки ребёнок видит цену, конверт, что даёт и счёт недели
/// «сейчас → потом». Отказ мира — карточка с причиной и следующим шагом.
class WorldShopScreen extends StatefulWidget {
  const WorldShopScreen({super.key, this.initialTab = 0});

  /// Открытая вкладка: 0 — еда, 1 — «Хочу», 2 — одежда.
  final int initialTab;

  @override
  State<WorldShopScreen> createState() => _WorldShopScreenState();
}

class _WorldShopScreenState extends State<WorldShopScreen> {
  AssetRegistry? _reg;
  WorldResult? _last;

  WorldState get _state => context.read<WorldState>();

  @override
  void initState() {
    super.initState();
    AssetRegistry.load().then((AssetRegistry r) {
      if (mounted) setState(() => _reg = r);
    }, onError: (Object _) {});
  }

  Future<void> _eat(WorldCatalogItem food) async {
    final WorldState st = _state;
    final ResourceSnapshot s = st.snapshot;
    final WorldCatalogItem? home = chosenFood(st.world);
    final int now = s.weeklyBill;
    // Съеденный сейчас приём больше не войдёт в счёт недели по цене
    // домашнего меню.
    final int after = now - (s.mealsLeft > 0 ? home?.price ?? 0 : 0);
    final int leftAfter = s.mealsLeft - 1;
    final bool full = s.energy + food.energy > WorldHud.energyMax + 1e-9;
    final bool yes = await confirmAction(
      context,
      title: '${food.title} — съесть сейчас?',
      lines: <String>[
        'Цена: ${food.price} — обязательная трата, из конверта НУЖНО '
            '(не хватит — из заработка).',
        s.need >= food.price
            ? 'В НУЖНО сейчас ${s.need}, останется ${s.need - food.price}.'
            : 'В НУЖНО сейчас ${s.need}: ещё ${food.price - s.need} возьмём из '
                'заработка.',
        if (effectText(food) case final String fx) fx,
        if (full) '⚡ почти полная — лишняя польза не сохранится.',
        leftAfter > 0
            ? 'Потом на этой неделе можно поесть ещё $leftAfter '
                '${Phrases.timesWord(leftAfter)}.'
            : 'Это последний приём пищи на этой неделе.',
      ],
      preview: BillPreview(now: now, after: after, when: 'сразу'),
      yes: 'Съесть',
    );
    if (!yes || !mounted) return;
    final WorldResult r = st.act((World w) => w.eat(food.id));
    setState(() => _last = r);
  }

  Future<void> _buy(WorldCatalogItem e) async {
    final WorldState st = _state;
    if (!await confirmBuy(context, st.world, e) || !mounted) return;
    final WorldResult r = st.act((World w) => w.buy(e.id));
    setState(() => _last = r);
  }

  Widget _list(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.lg),
        children: children,
      );

  /// Строка над карточками: конверт, пояснение и сколько сейчас.
  Widget _intro(PayFrom from, String what, String now) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            PayFromTag(from),
            Text(what, style: kitSoft),
            Text(now, style: kitText),
          ],
        ),
      );

  /// Отказ этапа недели — один раз над карточками.
  Widget? _phaseNote(BlockReason? b) => isPhaseBlock(b)
      ? Padding(
          key: const ValueKey<String>('shop:phase'),
          padding: const EdgeInsets.only(bottom: Gap.sm),
          child: BlockNote(b!),
        )
      : null;

  Widget _foodTab(World w) {
    final ResourceSnapshot s = w.snapshot;
    final WorldCatalogItem? home = chosenFood(w);
    final List<WorldCatalogItem> foods =
        catalogOf(w, WorldCatalogCategory.food);
    final Widget? phase = foods.isEmpty
        ? null
        : _phaseNote(w.canDo(WorldAction.eat, id: foods.first.id));
    final int left = s.mealsLeft;
    return _list(<Widget>[
      _intro(
          PayFrom.need,
          'обязательная трата',
          left > 0
              ? 'Поесть на этой неделе можно ещё $left '
                  '${Phrases.timesWord(left)}. Что не выберешь, Финни съест '
                  'дома (${home?.title.toLowerCase() ?? 'простая еда'}) — это '
                  'уже в счёте недели: ${s.weeklyBill}.'
              : 'На этой неделе Финни наелся. Счёт недели: ${s.weeklyBill}.'),
      if (phase != null) phase,
      CardGrid(children: <Widget>[
        for (final WorldCatalogItem f in foods)
          _foodCard(w, f,
              home: f.id == home?.id,
              scales: FoodScales(f,
                  maxEnergy: foods.fold<double>(0,
                      (double m, WorldCatalogItem x) => math.max(m, x.energy)),
                  maxHappiness: foods.fold<int>(
                      0,
                      (int m, WorldCatalogItem x) =>
                          math.max(m, x.happiness)))),
      ]),
    ]);
  }

  Widget _foodCard(World w, WorldCatalogItem f,
      {required bool home, required Widget scales}) {
    final BlockReason? block = w.canDo(WorldAction.eat, id: f.id);
    final BlockReason? homeBlock =
        home ? null : w.canDo(WorldAction.chooseFood, id: f.id);
    return _Card(
      key: ValueKey<String>('card:${f.id}'),
      entry: f,
      picture: _reg?.item(f.id),
      priceSuffix: 'за раз',
      scales: scales,
      block: isPhaseBlock(block) ? null : block,
      mark: home ? const MarkLine(Icons.home_rounded, 'Едим дома') : null,
      action: Wrap(
        spacing: Gap.sm,
        runSpacing: Gap.xs,
        children: <Widget>[
          // Ревью 174d885: тонкий контур на карточке читался как текст.
          OutlinedButton(
            key: ValueKey<String>('eat:${f.id}'),
            // Контур цвета НУЖНО: видно, что это кнопка, но не золото —
            // золотая на экране одна (docs/design-system.md, принцип 6).
            style: OutlinedButton.styleFrom(
                minimumSize: kitButton,
                side: const BorderSide(color: WorldColors.needs, width: 2)),
            onPressed: block == null ? () => _eat(f) : null,
            child: const Text('Съесть'),
          ),
          if (!home)
            TextButton(
              key: ValueKey<String>('home:${f.id}'),
              style: TextButton.styleFrom(minimumSize: kitButton),
              onPressed: homeBlock == null ? () => _chooseHome(f) : null,
              child: const Text('Есть дома'),
            ),
        ],
      ),
    );
  }

  /// Домашнее меню: что Финни ест в итогах за приёмы, которые не выбрали
  /// посреди недели. Меняет счёт недели — показываем «было → станет».
  Future<void> _chooseHome(WorldCatalogItem food) async {
    final WorldState st = _state;
    final ResourceSnapshot s = st.snapshot;
    final WorldCatalogItem? cur = chosenFood(st.world);
    final int now = s.weeklyBill;
    final int after = now + (food.price - (cur?.price ?? 0)) * s.mealsLeft;
    final bool yes = await confirmAction(
      context,
      title: '${food.title} — есть дома?',
      lines: <String>[
        'Приёмы, которые ты не выберешь сам, Финни съест дома: '
            '${food.price} за раз, из конверта НУЖНО в конце недели.',
        if (effectText(food) case final String fx) fx,
        'Польза дома придёт на следующую неделю.',
      ],
      preview: BillPreview(now: now, after: after, when: 'с этой недели'),
      yes: 'Есть дома',
    );
    if (!yes || !mounted) return;
    final WorldResult r = st.act((World w) => w.chooseFood(food.id));
    if (r.ok) rememberFood(st.world, food.id);
    setState(() => _last = r);
  }

  Widget _itemsTab(World w, List<WorldCatalogItem> items, String intro) {
    final ResourceSnapshot s = w.snapshot;
    final Widget? phase = items.isEmpty
        ? null
        : _phaseNote(w.canDo(WorldAction.buy, id: items.first.id));
    return _list(<Widget>[
      _intro(PayFrom.want, intro, 'В ХОЧУ ${s.want}, в заработке ${s.free}.'),
      if (phase != null) phase,
      CardGrid(children: <Widget>[
        for (final WorldCatalogItem e in items) _itemCard(w, e),
      ]),
    ]);
  }

  Widget _itemCard(World w, WorldCatalogItem e) {
    final bool owned = w.snapshot.owned.contains(e.id);
    final BlockReason? block =
        owned ? null : w.canDo(WorldAction.buy, id: e.id);
    return _Card(
      key: ValueKey<String>('card:${e.id}'),
      entry: e,
      picture: _reg?.item(e.id),
      block: isPhaseBlock(block) ? null : block,
      locked: requirementMet(w, e) ? null : e.requiresText,
      mark:
          owned ? const MarkLine(Icons.home_rounded, 'Уже есть у Финни') : null,
      action: owned
          ? null
          // Тихая кнопка: у каждой карточки своя «Купить», а золото на экране
          // одно — главное действие (docs/design-system.md, принцип 6).
          : OutlinedButton(
              key: ValueKey<String>('buy:${e.id}'),
              style: OutlinedButton.styleFrom(minimumSize: kitButton),
              onPressed: block == null ? () => _buy(e) : null,
              child: const Text('Купить'),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final WorldState st = context.watch<WorldState>();
    // Каталог и запреты читаются заново при каждой перерисовке: мир живой.
    final World w = st.world;
    final ResourceSnapshot s = st.snapshot;
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: WorldPage(
        id: 'shop',
        title: 'Магазин',
        snapshot: s,
        helpTitle: 'Магазин',
        result: _last,
        help: 'Еда — обязательная трата: её оплачивает конверт НУЖНО. Финни '
            'ест несколько раз в неделю, и что съесть — выбираешь ты. У '
            'каждого блюда три стороны: цена, польза (⚡ сразу) и вкус (😊). '
            'Вкусное бывает дорогим и не очень полезным, дешёвое — не очень '
            'вкусным. Лучшего блюда нет — есть то, что нужно сейчас.\n\n'
            'Не выберешь — Финни поест дома простой едой в конце недели: она '
            'уже в счёте недели, а её ⚡ перейдёт на следующую неделю.\n\n'
            '«Хочу» и одежда — необязательные покупки: платим из ХОЧУ, потом '
            'из заработка. Перед покупкой видно цену, что она даёт и каким '
            'будет счёт недели.\n\n'
            'Не хватает монет — ничего не спишется, Финни подскажет, что '
            'можно сделать.',
        header: Material(
          color: WorldLayout.isLandscape(context)
              ? Colors.transparent
              : WorldColors.panel,
          child: TabBar(
            labelPadding: WorldLayout.isLandscape(context)
                ? const EdgeInsets.symmetric(horizontal: Gap.xs)
                : null,
            labelStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            tabs: <Widget>[
              kitTab(context,
                  key: const ValueKey<String>('tab:food'),
                  icon: Icons.restaurant_rounded,
                  text: 'Еда'),
              kitTab(context,
                  key: const ValueKey<String>('tab:want'),
                  icon: Icons.favorite_rounded,
                  text: 'Хочу'),
              kitTab(context,
                  key: const ValueKey<String>('tab:clothes'),
                  icon: Icons.checkroom_rounded,
                  text: 'Одежда'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _foodTab(w),
            _itemsTab(
              w,
              <WorldCatalogItem>[
                ...catalogOf(w, WorldCatalogCategory.snack),
                ...catalogOf(w, WorldCatalogCategory.decor),
              ],
              'необязательно: перекус и вещи для комнаты',
            ),
            _itemsTab(w, catalogOf(w, WorldCatalogCategory.clothes),
                'необязательно: радость от обновки со временем угасает'),
          ],
        ),
      ),
    );
  }
}

/// Карточка позиции: картинка, название, цена, что даёт, отметка или кнопка.
class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.entry,
    this.picture,
    this.priceSuffix,
    this.scales,
    this.block,
    this.locked,
    this.mark,
    this.action,
  });

  final WorldCatalogItem entry;

  /// Шкалы блюда (польза и вкус) — под названием, вместо строки эффекта.
  final Widget? scales;

  /// Картинка из реестра; нет арта — карточка без неё, как раньше.
  final String? picture;
  final String? priceSuffix;

  /// Почему кнопка погашена — текст мира ([World.canDo]).
  final BlockReason? block;

  /// Чего не хватает, чтобы открылось ([WorldCatalogItem.requiresText]).
  final String? locked;
  final Widget? mark;
  final Widget? action;

  /// Название и цена. В портрете картинка слева от них; в альбомной — в
  /// ряду кнопки ([_picture]): узкая колонка сетки не переносит название,
  /// и карточка не растёт в высоту, которой на экране 360 dp мало.
  Widget _head(BuildContext context) {
    final bool side = picture != null && !WorldLayout.isLandscape(context);
    // Место под название: колонка сетки минус поля карточки и картинка
    // слева (в портрете). Название — в две строки целиком, слова не
    // рвутся; не встаёт — шрифт мельче (20 → 18 → 16 → 14).
    final double? card = CardWidth.of(context);
    final double size = card == null
        ? kitTitle.fontSize!
        : fitWordsFontSize(
            context,
            entry.title,
            kitTitle,
            card -
                2 * Gap.sm -
                (side ? itemPictureBox(context).width + Gap.sm : 0) -
                2);
    final Widget text = Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(entry.title,
            key: ValueKey<String>('title:${entry.id}'),
            style: kitTitle.copyWith(fontSize: size),
            // Название из каталога не режется: размер подобран так, чтобы
            // оно встало в две строки (fitWordsFontSize).
            softWrap: true),
        PriceLine(entry.price, suffix: priceSuffix),
      ],
    );
    if (!side) return text;
    return Row(
      children: <Widget>[
        _picture(context)!,
        const SizedBox(width: Gap.sm),
        Expanded(child: text),
      ],
    );
  }

  Widget? _picture(BuildContext context) {
    final String? p = picture;
    if (p == null) return null;
    final Size box = itemPictureBox(context);
    return ItemPicture(p,
        key: ValueKey<String>('picture:${entry.id}'),
        width: box.width,
        height: box.height);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: Panel(
          padding: const EdgeInsets.all(Gap.sm),
          // В сетке карточки ряда одной высоты: описание сверху, кнопка —
          // по низу карточки.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _head(context),
                  if (scales != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.xs),
                      child: scales,
                    )
                  else if (effectText(entry) case final String fx)
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.xs),
                      child: PicText(fx, style: kitBody(context)),
                    ),
                  if (locked != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.xs),
                      child: MarkLine(Icons.lock_rounded, locked!,
                          color: WorldColors.textSoft),
                    ),
                  if (block != null)
                    Padding(
                      key: ValueKey<String>('block:${entry.id}'),
                      padding: const EdgeInsets.only(top: Gap.xs),
                      child: BlockNote(block!),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: Gap.xs),
                child: Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.xs,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    if (mark != null) mark!,
                    if (action != null) action!,
                    if (WorldLayout.isLandscape(context))
                      if (_picture(context) case final Widget pic) pic,
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
