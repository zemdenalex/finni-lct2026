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
import '../home/room_skins.dart';
import '../world_routes.dart';
import '../../../core/world_theme.dart';
import '../world_dock.dart';

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

  /// Открытая вкладка: 0 — продукты, 1 — уют и декор, 2 — одежда,
  /// 3 — мебель, 4 — техника и транспорт, 5 — зоомагазин.
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
    // Одно правило «сколько ещё можно поесть» (дни учтены), как в справке.
    final int leftAfter = s.mealsAvailable - 1;
    final bool full =
        s.energy + food.energy > WorldHud.energyMaxOf(st.world) + 1e-9;
    final bool yes = await confirmAction(
      context,
      title: '${food.title} — съесть сейчас?',
      lines: <String>[
        'Цена: ${food.price} — обязательная трата, из части «Нужно» '
            '(не хватит — из заработка).',
        s.need >= food.price
            ? 'В части «Нужно» сейчас ${s.need}, останется ${s.need - food.price}.'
            : 'В части «Нужно» сейчас ${s.need}: ещё ${food.price - s.need} возьмём из '
                'заработка.',
        if (effectText(food) case final String fx) fx,
        if (full) 'Силы почти полные: лишнего Финни не запасёт.',
        leftAfter > 0
            ? 'Потом на этой неделе можно поесть ещё $leftAfter '
                '${Phrases.timesWord(leftAfter)}.'
            : 'Это последний раз поесть на этой неделе.',
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
    // Купленный вариант предмета сразу становится его видом в комнате.
    if (r.ok) st.chooseSkin(e.id);
    setState(() => _last = r);
  }

  /// Вещь комнаты — покупка из «Хочу», как прочие вещи; поставить её
  /// можно в комнате (режим «Расставить»).
  Future<void> _buyRoom(WorldCatalogItem e) async {
    final WorldState st = _state;
    if (!await confirmBuy(context, st.world, e) || !mounted) return;
    final WorldResult r = st.act((World w) => w.buyRoomItem(e.id));
    setState(() => _last = r);
  }

  /// Вещь комнаты карточкой каталога: цена и 😊 — как у декора.
  static WorldCatalogItem roomEntry(RoomCatalog room, RoomItemSpec it) =>
      WorldCatalogItem(
        id: it.id,
        title: it.name,
        category: WorldCatalogCategory.decor,
        price: it.price,
        happiness: room.happinessOnce,
      );

  /// Вкладка «Комната» (флаг room.customize): вещи для сетки комнаты.
  Widget _roomTab(World w) {
    final ResourceSnapshot s = w.snapshot;
    final List<RoomItemSpec> items = w.room.items;
    final Widget? phase = items.isEmpty
        ? null
        : _phaseNote(w.canDo(WorldAction.buyRoomItem, id: items.first.id));
    return _list(<Widget>[
      _intro(PayFrom.want,
          'необязательно: вещи, которые можно поставить в комнате', null),
      _spendable(s),
      if (phase != null) phase,
      CardGrid(children: <Widget>[
        for (final RoomItemSpec it in items) _roomCard(w, it),
      ]),
    ]);
  }

  Widget _roomCard(World w, RoomItemSpec it) {
    final bool owned = w.snapshot.roomOwned.contains(it.id);
    final BlockReason? block =
        owned ? null : w.canDo(WorldAction.buyRoomItem, id: it.id);
    final WorldCatalogItem e = roomEntry(w.room, it);
    return Builder(
      key: ValueKey<String>('card:${it.id}'),
      builder: (BuildContext context) => _Card(
        entry: e,
        picture: it.sprite,
        scales: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (w.room.happinessOnce != 0)
              if (effectText(e) case final String fx)
                PicText(fx, style: kitBody(context)),
            Text('Ставится ${it.slot.where}, клеток: ${it.w * it.h}.',
                key: ValueKey<String>('where:${it.id}'),
                style: kitBody(context)),
          ],
        ),
        block: isPhaseBlock(block) ? null : block,
        mark: owned ? const MarkLine(Icons.home_rounded, 'Уже куплено') : null,
        action: owned
            ? null
            : OutlinedButton(
                key: ValueKey<String>('buy:${it.id}'),
                style: OutlinedButton.styleFrom(minimumSize: kitButton),
                onPressed: block == null ? () => _buyRoom(e) : null,
                child: const Text('Купить'),
              ),
      ),
    );
  }

  /// Какой цвет открыт на карточке варианта: код → id плитки.
  final Map<String, String> _pick = <String, String>{};

  /// Позиции каталога одной карточкой на код: цвета одного кода — точки.
  List<List<WorldCatalogItem>> _families(List<WorldCatalogItem> items) {
    final Map<String, List<WorldCatalogItem>> by =
        <String, List<WorldCatalogItem>>{};
    for (final WorldCatalogItem i in items) {
      (by[skinFamily(i.id)] ??= <WorldCatalogItem>[]).add(i);
    }
    return by.values.toList();
  }

  /// Карточка варианта: открытый цвет, точки цветов, «Купить» / «Выбрать».
  Widget _familyCard(World w, List<WorldCatalogItem> fam) {
    if (fam.length == 1 && skinObject(fam.first.id) == null) {
      return _itemCard(w, fam.first);
    }
    final WorldState st = _state;
    final String key = skinFamily(fam.first.id);
    final Set<String> owned = w.snapshot.owned;
    // Открыт выбранный ребёнком цвет, иначе купленный, иначе первый.
    final WorldCatalogItem e = fam.firstWhere(
        (WorldCatalogItem i) => i.id == _pick[key],
        orElse: () => fam.firstWhere(
            (WorldCatalogItem i) => owned.contains(i.id),
            orElse: () => fam.first));
    final bool have = owned.contains(e.id);
    final String? object = skinObject(e.id);
    final bool worn =
        object != null && equippedSkins(owned, st.chosenSkins)[object] == e.id;
    final BlockReason? block = have ? null : w.canDo(WorldAction.buy, id: e.id);
    // Цель касания 48 dp (ТЗ, androidTapTargetGuideline; ревью
    // 17.10: было 40), точка та же — 26 dp; отступ между целями не нужен.
    final Widget dots = Wrap(
      children: <Widget>[
        for (final WorldCatalogItem v in fam)
          Semantics(
            button: true,
            selected: v.id == e.id,
            label: 'Цвет ${fam.indexOf(v) + 1}',
            child: InkWell(
              key: ValueKey<String>('color:${v.id}'),
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _pick[key] = v.id),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Color(_reg?.swatch(v.id) ?? 0xFF9E9E9E),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: v.id == e.id
                              ? WorldColors.text
                              : WorldColors.textSoft,
                          width: v.id == e.id ? 3 : 1),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return _Card(
      key: ValueKey<String>('card:$key'),
      entry: e,
      picture: _reg?.item(e.id),
      scales: fam.length > 1 ? dots : null,
      block: isPhaseBlock(block) ? null : block,
      mark: worn
          ? const MarkLine(Icons.home_rounded, 'Сейчас в комнате')
          : have
              ? const MarkLine(Icons.check_rounded, 'Куплено')
              : null,
      action: worn
          ? null
          : have
              ? OutlinedButton(
                  key: ValueKey<String>('choose:${e.id}'),
                  style: OutlinedButton.styleFrom(minimumSize: kitButton),
                  onPressed: () => setState(() => st.chooseSkin(e.id)),
                  child: const Text('Выбрать'),
                )
              : OutlinedButton(
                  key: ValueKey<String>('buy:${e.id}'),
                  style: OutlinedButton.styleFrom(minimumSize: kitButton),
                  onPressed: block == null ? () => _buy(e) : null,
                  child: const Text('Купить'),
                ),
    );
  }

  /// Зоомагазин — свой экран с питомцами; вкладка ведёт туда.
  Widget _petsTab() => _list(<Widget>[
        const Text(
            'Питомцы живут в зоомагазине: там видно, сколько стоит корм и '
            'что питомец даёт.',
            style: kitText),
        const SizedBox(height: Gap.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const ValueKey<String>('shop:pets'),
            style: FilledButton.styleFrom(minimumSize: kitButton),
            onPressed: () =>
                Navigator.of(context).pushNamed(WorldRoutes.petShop),
            child: const Text('В зоомагазин'),
          ),
        ),
      ]);

  Widget _list(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.lg),
        children: children,
      );

  /// Строка над карточками: конверт, пояснение и сколько сейчас.
  Widget _intro(PayFrom from, String what, String? now) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            PayFromTag(from),
            Text(what, style: kitSoft),
            if (now != null) Text(now, style: kitText),
          ],
        ),
      );

  /// Сколько можно потратить на покупки — крупно, и куда делись остальные
  /// монеты из шапки. Было (путь ребёнка rc-7d, D1): в шапке «760 монет»,
  /// плакат за 200 — «Не хватает 180»: покупки идут только из «Хочу» и
  /// заработка, а 740 лежат в «Нужном» на еду и счета, и экран этого не
  /// говорил. Что считается тратой, не меняется — только объяснение.
  Widget _spendable(ResourceSnapshot s) {
    final int can = s.want + s.free;
    final int rest = s.available - can;
    return Padding(
      key: const ValueKey<String>('shop:spendable'),
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Можно потратить: $can', style: kitTitle),
            Text('Это «Хочу» ${s.want} и заработок со смен ${s.free}.',
                style: kitText),
            if (rest > 0)
              Text(
                  s.unallocated > 0
                      ? 'Остальные $rest из ${s.available} ещё не разложены '
                          'по плану — сначала план недели.'
                      : 'Остальные $rest из ${s.available} лежат в части «Нужно» — '
                          'на еду и счета. На покупки их не тратят.',
                  key: const ValueKey<String>('shop:spendable:rest'),
                  style: kitSoft),
          ],
        ),
      ),
    );
  }

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
    final int left = s.mealsAvailable;
    final String hero = w.onboarding.finniName;
    final String full = heroGendered(w.onboarding.finniGender,
        neutral: 'На этой неделе больше поесть нельзя.',
        boy: 'На этой неделе $hero наелся.',
        girl: 'На этой неделе $hero наелась.');
    // n5 (кадр D5): в режиме дней — про сегодня. Над карточкой «на сегодня
    // еда кончилась» стояло «поесть на этой неделе можно ещё 6 раз».
    final bool days = s.daysPerWeek > 1;
    final bool ateToday = days &&
        foods.isNotEmpty &&
        w.canDo(WorldAction.eat, id: foods.first.id)?.code == 'eat.day_limit';
    final String homeTail = 'Что не выберешь, Финни съест '
        'дома (${home?.title.toLowerCase() ?? 'простая еда'}) — это '
        'уже в счёте недели: ${s.weeklyBill}.';
    return _list(<Widget>[
      _intro(
          PayFrom.need,
          'обязательная трата',
          left > 0
              ? days
                  ? '${ateToday ? 'Сегодня уже поели — следующий приём '
                      'завтра.' : 'Сегодня ещё можно поесть.'} $homeTail'
                  : 'Поесть на этой неделе можно ещё $left '
                      '${Phrases.timesWord(left)}. $homeTail'
              : '$full Счёт недели: ${s.weeklyBill}.'),
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
    final ResourceSnapshot s = w.snapshot;
    // Сколько блюда в холодильнике: куплено на дни вперёд (дела дня), иначе
    // у домашнего блюда — приёмы недели, которые Финни съест дома.
    final int stock =
        s.fridge[f.id] ?? (home && s.fridge.isEmpty ? s.mealsLeft : 0);
    return _Card(
      key: ValueKey<String>('card:${f.id}'),
      entry: f,
      picture: _reg?.item(f.id),
      priceSuffix: 'за раз',
      scales: scales,
      block: isPhaseBlock(block) ? null : block,
      // Эксперт 16.10: «Едим дома» (состояние) и «Есть дома» (кнопка)
      // читались одинаково. Теперь у выбранного блюда — отметка с галочкой и
      // сколько его в холодильнике, у остальных — кнопка с другим глаголом.
      mark: home || stock > 0
          ? Column(
              key: ValueKey<String>('food:home:${f.id}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (home)
                  const MarkLine(Icons.check_circle_rounded, 'Дома едим это',
                      color: WorldColors.needs),
                if (stock > 0)
                  Text('В холодильнике: $stock ${_portionWord(stock)}',
                      key: ValueKey<String>('food:fridge:${f.id}'),
                      style: kitSoft),
              ],
            )
          : null,
      // Одна кнопка «Купить и съесть» на каждом продукте (Настя 20.10 16:50
      // и 23:33, Денис 23:36): «Съесть» и «Готовить дома» путали.
      action: OutlinedButton(
        key: ValueKey<String>('eat:${f.id}'),
        // Контур цвета НУЖНО: видно, что это кнопка, но не золото —
        // золотая на экране одна (docs/design-system.md, принцип 6).
        style: OutlinedButton.styleFrom(
            minimumSize: kitButton,
            side: const BorderSide(color: WorldColors.needs, width: 2)),
        onPressed: block == null ? () => _eat(f) : null,
        child: const Text('Купить и съесть'),
      ),
    );
  }

  static String _portionWord(int n) {
    final int m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'порция';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'порции';
    return 'порций';
  }

  Widget _itemsTab(World w, List<WorldCatalogItem> items, String intro,
      {PayFrom from = PayFrom.want}) {
    final ResourceSnapshot s = w.snapshot;
    final Widget? phase = items.isEmpty
        ? null
        : _phaseNote(w.canDo(WorldAction.buy, id: items.first.id));
    return _list(<Widget>[
      _intro(from, intro, from == PayFrom.goal ? 'В копилке ${s.goal}.' : null),
      if (from != PayFrom.goal) _spendable(s),
      if (phase != null) phase,
      CardGrid(children: <Widget>[
        for (final List<WorldCatalogItem> f in _families(items))
          _familyCard(w, f),
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
    // Вкладка «Комната» — только с флагом room.customize.
    final bool roomTab = w.room.enabled;
    final List<WorldCatalogItem> decor =
        catalogOf(w, WorldCatalogCategory.decor);
    bool furniture(WorldCatalogItem i) =>
        skinObject(i.id)?.startsWith('skin_') ?? false;
    // Родовые формы (5Б) — отдельной строкой: линт и konvert_1b_test видят
    // литералы только вне `${…}`.
    final String homeMealByDay = heroGendered(st.profile.gender,
        neutral: 'не выберешь днём — вечером ${st.finniName} поест дома.',
        boy: 'не поел днём — вечером ${st.finniName} поест дома.',
        girl: 'не поела днём — вечером ${st.finniName} поест дома.');
    return DefaultTabController(
      length: roomTab ? 7 : 6,
      initialIndex: widget.initialTab,
      child: WorldPage(
        id: 'shop',
        dock: DockSection.city,
        title: 'Магазин',
        snapshot: s,
        helpTitle: 'Магазин',
        result: _last,
        // Режим дней: домашняя еда — вечером каждого дня; «неделя» — в конце
        // недели, и её польза переходит на следующую (day_help_texts_test).
        help: 'Еду оплачивает «Нужно», у каждого блюда есть цена, польза (⚡) '
            'и вкус (😊); ${s.daysPerWeek > 1 ? homeMealByDay : 'не выберешь — Финни поест дома, а польза перейдёт на следующую неделю.'} '
            'Вещи и одежда — по желанию: платим из «Хочу», потом из '
            'заработка. Если монет не хватает, ничего не спишется.',
        header: Material(
          color: WorldLayout.isLandscape(context)
              ? Colors.transparent
              : WorldColors.panel,
          // n5: вкладки за правым краем без признака, что есть ещё.
          child: _TabsMoreHint(
            fade: WorldLayout.isLandscape(context)
                ? WorldColors.night
                : WorldColors.panel,
            child: TabBar(
              // Шесть отделов не встают в 360 dp — лента прокручивается.
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: WorldLayout.isLandscape(context)
                  ? const EdgeInsets.symmetric(horizontal: Gap.xs)
                  : null,
              labelStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              tabs: <Widget>[
                kitTab(context,
                    key: const ValueKey<String>('tab:food'),
                    icon: Icons.restaurant_rounded,
                    text: 'Продукты'),
                kitTab(context,
                    key: const ValueKey<String>('tab:want'),
                    icon: Icons.favorite_rounded,
                    text: 'Уют и декор'),
                kitTab(context,
                    key: const ValueKey<String>('tab:clothes'),
                    icon: Icons.checkroom_rounded,
                    text: 'Одежда'),
                kitTab(context,
                    key: const ValueKey<String>('tab:furniture'),
                    icon: Icons.bed_rounded,
                    text: 'Мебель'),
                kitTab(context,
                    key: const ValueKey<String>('tab:tech'),
                    icon: Icons.pedal_bike_rounded,
                    text: 'Техника и транспорт'),
                kitTab(context,
                    key: const ValueKey<String>('tab:pets'),
                    icon: Icons.pets_rounded,
                    text: 'Зоомагазин'),
                if (roomTab)
                  kitTab(context,
                      key: const ValueKey<String>('tab:room'),
                      icon: Icons.chair_rounded,
                      text: 'Комната'),
              ],
            ),
          ),
        ),
        body: _OnTabChange(
          // Итог покупки — про отдел, где купили: на другой вкладке он
          // закрывал список (проход RC 17.10, находка 8).
          onChange: () {
            if (_last != null) setState(() => _last = null);
          },
          child: TabBarView(
            children: <Widget>[
              _foodTab(w),
              _itemsTab(
                w,
                <WorldCatalogItem>[
                  ...catalogOf(w, WorldCatalogCategory.snack),
                  ...decor.where((WorldCatalogItem i) => !furniture(i)),
                ],
                'необязательно: перекус и вещи для комнаты',
              ),
              _itemsTab(w, catalogOf(w, WorldCatalogCategory.clothes),
                  'необязательно: радость от новой вещи со временем проходит'),
              _itemsTab(w, decor.where(furniture).toList(),
                  'необязательно: купленный вид сразу встаёт в комнату'),
              _itemsTab(
                  w,
                  <WorldCatalogItem>[
                    ...catalogOf(w, WorldCatalogCategory.tech),
                    ...catalogOf(w, WorldCatalogCategory.transport),
                  ],
                  'цель накопления: открывает новую работу',
                  from: PayFrom.goal),
              _petsTab(),
              if (roomTab) _roomTab(w),
            ],
          ),
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
        // Своя ветка TalkBack у каждой карточки: без неё тексты всех
        // карточек отдела сливались в одну подпись в 1000+ знаков
        // (проход RC 17.10, находка 9) — блюдо нельзя было пройти по одному.
        child: Semantics(
          container: true,
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
        ),
      );
}

/// Зовёт [onChange], когда в [DefaultTabController] над ним меняется вкладка
/// (нажатием на ярлык или смахиванием).
class _OnTabChange extends StatefulWidget {
  const _OnTabChange({required this.onChange, required this.child});

  final VoidCallback onChange;
  final Widget child;

  @override
  State<_OnTabChange> createState() => _OnTabChangeState();
}

class _OnTabChangeState extends State<_OnTabChange> {
  TabController? _tabs;
  int? _index;

  void _changed() {
    final TabController? t = _tabs;
    if (t == null || t.index == _index) return;
    _index = t.index;
    widget.onChange();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final TabController t = DefaultTabController.of(context);
    if (t == _tabs) return;
    _tabs?.removeListener(_changed);
    _tabs = t..addListener(_changed);
    _index = t.index;
  }

  @override
  void dispose() {
    _tabs?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Признак «вкладок ещё больше» у правого края прокручиваемой ленты: тень в
/// цвет шапки и стрелка, пока справа есть невидимые вкладки. Касания не
/// ловит — лента под ним листается и нажимается как раньше.
class _TabsMoreHint extends StatefulWidget {
  const _TabsMoreHint({required this.fade, required this.child});

  final Color fade;
  final Widget child;

  @override
  State<_TabsMoreHint> createState() => _TabsMoreHintState();
}

class _TabsMoreHintState extends State<_TabsMoreHint> {
  bool _more = false;

  bool _update(ScrollMetrics m) {
    if (m.axis != Axis.horizontal) return false;
    final bool more = m.extentAfter > 1;
    if (more != _more) setState(() => _more = more);
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (ScrollMetricsNotification n) =>
            n.depth == 0 && _update(n.metrics),
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification n) =>
              n.depth == 0 && _update(n.metrics),
          child: Stack(
            children: <Widget>[
              widget.child,
              if (_more)
                Positioned(
                  key: const ValueKey<String>('shop:tabs:more'),
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: 40,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              widget.fade.withValues(alpha: 0),
                              widget.fade,
                            ],
                          ),
                        ),
                        child: const Align(
                          alignment: Alignment.centerRight,
                          child: Icon(Icons.chevron_right_rounded,
                              color: WorldColors.textSoft),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}
