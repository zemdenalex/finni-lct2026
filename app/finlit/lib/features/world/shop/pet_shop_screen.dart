import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/art/sprite_anim.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../domain/world/contract.dart';
import '../world_layout.dart';
import '../world_state.dart';
import '../pic_text.dart';
import 'shop_kit.dart';
import '../../../core/world_theme.dart';

/// S5 — зоомагазин: питомцы как цели накопления (`docs/game/pets.md`).
///
/// На карточке: спрайт, цена, корм в неделю, что даёт. Выбор — на кого
/// копить и когда покупать. 🔴 Перед покупкой — счёт недели «сейчас → со
/// следующей недели» с кормом.
class PetShopScreen extends StatefulWidget {
  const PetShopScreen({super.key});

  @override
  State<PetShopScreen> createState() => _PetShopScreenState();
}

class _PetShopScreenState extends State<PetShopScreen> {
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

  void _choose(WorldCatalogItem e) {
    final WorldResult r = _state.act((World w) => w.chooseGoal(e.id));
    setState(() => _last = r);
  }

  Future<void> _buy(WorldCatalogItem e) async {
    final WorldState st = _state;
    if (!await confirmBuy(context, st.world, e) || !mounted) return;
    final WorldResult r = st.act((World w) => w.buy(e.id));
    setState(() => _last = r);
  }

  @override
  Widget build(BuildContext context) {
    final WorldState st = context.watch<WorldState>();
    // Каталог и запреты читаются заново при каждой перерисовке: мир живой.
    final World w = st.world;
    final ResourceSnapshot s = st.snapshot;
    final List<WorldCatalogItem> pets = catalogOf(w, WorldCatalogCategory.pet);
    final BlockReason? phase =
        pets.isEmpty ? null : w.canDo(WorldAction.buy, id: pets.first.id);
    return WorldPage(
      id: 'pets',
      title: 'Зоомагазин',
      snapshot: s,
      helpTitle: 'Зоомагазин',
      result: _last,
      help: 'Питомец — цель: на него копят в копилке (конверт ЦЕЛЬ) и '
          'покупают целиком, когда накоплено хватает.\n\n'
          '«Копить» — сделать питомца целью. «Купить» — забрать домой.\n\n'
          'Питомец радует Финни каждую неделю, но и ест: корм добавится к '
          'счёту недели со следующей недели. Питомцы не болеют и не уходят.',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.lg),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                const PayFromTag(PayFrom.goal),
                const Text('копим в копилке', style: kitSoft),
                Text(
                    'В копилке ${s.goal}. Счёт недели сейчас: ${s.weeklyBill}.',
                    style: kitText),
              ],
            ),
          ),
          // Этап недели: покупка закрыта — одной строкой над карточками.
          if (isPhaseBlock(phase))
            Padding(
              key: const ValueKey<String>('pets:phase'),
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: BlockNote(phase!),
            ),
          // Две колонки: у питомца две кнопки, им нужна ширина рядом.
          CardGrid(minCard: 240, maxColumns: 2, children: <Widget>[
            for (final WorldCatalogItem p in pets)
              _PetCard(
                key: ValueKey<String>('card:${p.id}'),
                pet: p,
                snapshot: s,
                buyBlock: w.canDo(WorldAction.buy, id: p.id),
                goalBlock: w.canDo(WorldAction.chooseGoal, id: p.id),
                sprite: _reg?.pet(p.id),
                onChoose: () => _choose(p),
                onBuy: () => _buy(p),
              ),
          ]),
        ],
      ),
    );
  }
}

class _PetCard extends StatelessWidget {
  const _PetCard({
    super.key,
    required this.pet,
    required this.snapshot,
    required this.buyBlock,
    required this.goalBlock,
    required this.sprite,
    required this.onChoose,
    required this.onBuy,
  });

  final WorldCatalogItem pet;
  final ResourceSnapshot snapshot;

  /// Почему «Купить» / «Копить» сейчас нельзя — ответ мира ([World.canDo]).
  final BlockReason? buyBlock;
  final BlockReason? goalBlock;
  final SpriteRef? sprite;
  final VoidCallback onChoose;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final ResourceSnapshot s = snapshot;
    final bool owned = s.owned.contains(pet.id);
    final bool active = s.activeGoalId == pet.id;
    // Отказ этапа недели показан над сеткой — на карточке только кнопка.
    final BlockReason? buy = buyBlock;
    final SpriteRef? ref = sprite;
    final bool land = WorldLayout.isLandscape(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Panel(
        padding: const EdgeInsets.all(Gap.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: land ? 56 : 72,
                      height: land ? 48 : 64,
                      child: Center(
                        child: ref == null
                            ? const Icon(Icons.pets_rounded,
                                size: 40, color: WorldColors.textSoft)
                            : SpriteAnim(
                                sprite: ref,
                                tag: 'sleep',
                                height: land ? 48 : 64,
                                semanticLabel: pet.title,
                              ),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(pet.title, style: kitTitle),
                          PriceLine(pet.price),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.xs),
                Text('Корм ${pet.weeklyCost} в неделю',
                    style: kitBody(context)),
                if (effectText(pet) case final String fx)
                  PicText(fx, style: kitBody(context)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: owned
                  ? const MarkLine(Icons.home_rounded, 'Уже дома у Финни')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (active)
                          const MarkLine(Icons.star_rounded, 'Копим на него',
                              color: WorldColors.goal),
                        if (buy == null)
                          const Text('Накоплено хватает — можно купить',
                              style: kitSoft)
                        else if (!isPhaseBlock(buy))
                          BlockNote(buy,
                              key: ValueKey<String>('block:${pet.id}')),
                        const SizedBox(height: Gap.xs),
                        Wrap(
                          spacing: Gap.sm,
                          runSpacing: Gap.xs,
                          children: <Widget>[
                            // Золото — у «Копить»: игра учит копить на
                            // питомца (макет Алины «Копить на него»), а
                            // «Купить» — тихая.
                            if (!active)
                              FilledButton.icon(
                                key: ValueKey<String>('goal:${pet.id}'),
                                style: FilledButton.styleFrom(
                                    minimumSize: kitButton),
                                onPressed: goalBlock == null ? onChoose : null,
                                icon: const Icon(Icons.star_outline_rounded),
                                label: const Text('Копить'),
                              ),
                            OutlinedButton.icon(
                              key: ValueKey<String>('buy:${pet.id}'),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: kitButton),
                              onPressed: buy == null ? onBuy : null,
                              icon: const Icon(Icons.shopping_bag_rounded),
                              label: const Text('Купить'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
