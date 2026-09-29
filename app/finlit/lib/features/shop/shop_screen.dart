import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/world_art.dart';
import '../../domain/economy/purchase_rules.dart';
import '../../domain/economy/savings_rules.dart';
import '../../domain/game.dart';
import '../../domain/ledger/ledger_fold.dart';
import '../../domain/models/catalog_item.dart';
import '../../domain/models/envelope.dart';
import '../../domain/models/goal.dart';
import '../../routes.dart';

/// Покупки (§2.5.6).
///
/// Каталог делится на два раздела по конверту: «Нужное» — обязательные
/// расходы, «Хочу» — необязательные (§2.5.6.1). Ни один расчёт здесь не
/// живёт: можно ли купить, чего не хватает и какие есть варианты — решает
/// [PurchaseRules] через [Game.canBuy].
class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    if (!app.ready) {
      return const Scaffold(body: Center(child: Text('Финни')));
    }

    final Game g = app.game;
    final Wallet w = g.snapshot.wallet;

    return Scaffold(
      appBar: AppBar(title: const Text('Покупки')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.xl),
          children: <Widget>[
            SceneHeader(
              say: w.unallocated > 0
                  ? '${w.unallocated} ${Coins.word(w.unallocated)} ещё не '
                      'разложены. Покупки берутся из конвертов — сначала план.'
                  : 'В «Нужном» ${w.envelopes.needs}, в «Хочу» '
                      '${w.envelopes.wants}. Что возьмём?',
            ),
            const SizedBox(height: Gap.lg),
            // Вопрос про отложенное стоит выше витрины намеренно: если
            // спросить после того, как ребёнок уже разглядывает новое,
            // ответ будет про новое, а не про старое желание.
            for (final CatalogItem item in g.ripeWishes) ...<Widget>[
              _WishQuestion(
                item: item,
                onKeep: () => _answerWish(context, app, item, keep: true),
                onDrop: () => _answerWish(context, app, item, keep: false),
              ),
              const SizedBox(height: Gap.sm),
            ],
            if (g.freshWishes.isNotEmpty) ...<Widget>[
              _WaitingNote(items: g.freshWishes),
              const SizedBox(height: Gap.md),
            ],
            for (final Envelope e in <Envelope>[
              Envelope.needs,
              Envelope.wants
            ]) ...<Widget>[
              _SectionHeader(
                  envelope: e, inEnvelope: w.envelopes.byEnvelope(e)),
              const SizedBox(height: Gap.sm),
              if (e == Envelope.needs)
                for (final CatalogItem item in app.content.catalog
                    .where((CatalogItem i) => i.envelope == e)) ...<Widget>[
                  _ItemCard(
                    item: item,
                    decision: g.canBuy(item),
                    onTap: () => _openItem(context, app, item),
                  ),
                  const SizedBox(height: Gap.sm),
                ]
              else
                // «Хочу» — витрина вещей, а не список расходников: вещь
                // видно крупно, как на полке, ещё до покупки.
                _Shelf(
                  items: app.content.catalog
                      .where((CatalogItem i) => i.envelope == e)
                      .toList(),
                  decide: g.canBuy,
                  owned: (CatalogItem i) {
                    for (final (CatalogItem k, int n) in g.keepsakes) {
                      if (k.id == i.id) return n;
                    }
                    return 0;
                  },
                  onTap: (CatalogItem i) => _openItem(context, app, i),
                ),
              const SizedBox(height: Gap.md),
            ],
          ],
        ),
      ),
    );
  }

  /// §2.5.6.3: покупка требует подтверждения. §2.5.6.4: при нехватке — не
  /// запрет, а объяснение и список вариантов.
  Future<void> _openItem(
    BuildContext context,
    AppState app,
    CatalogItem item,
  ) async {
    final PurchaseDecision d = app.game.canBuy(item);
    if (d.allowed) {
      final _BuyChoice choice =
          await _askToBuy(context, app, item, d) ?? _BuyChoice.no;
      if (!context.mounted) return;
      switch (choice) {
        case _BuyChoice.buy:
          await app.act((Game g) => g.buy(item));
        case _BuyChoice.wait:
          await app.act((Game g) => g.addToWishList(item));
        case _BuyChoice.no:
          return;
      }
      if (!context.mounted) return;
      await _showResult(context, app,
          bought: choice == _BuyChoice.buy ? item : null);
      return;
    }

    final _Choice? choice = await _askWhatInstead(context, app, item, d);
    if (!context.mounted) return;

    final Envelope? from = switch (choice?.option) {
      ShortfallOption.moveFromSavings => Envelope.savings,
      ShortfallOption.moveFromNeeds => Envelope.needs,
      ShortfallOption.moveFromWants => Envelope.wants,
      ShortfallOption.doTask || ShortfallOption.waitForNextWeek || null => null,
    };

    if (from != null) {
      // Сначала переложить, потом купить — одним действием, чтобы состояние
      // не осталось на половине, если что-то пойдёт не так.
      await app.act((Game g) {
        g.move(from: from, to: item.envelope, amount: d.shortfall);
        return g.buy(item);
      });
      if (!context.mounted) return;
      await _showResult(context, app, bought: item);
      return;
    }

    // 🔴 Покупки не будет — ни когда ребёнок выбрал «подождать» или
    // «заработать», ни когда он просто закрыл лист. Попытка всё равно
    // попадает в журнал: на записи об отказе держится шаг 7 обязательного
    // сценария Приложения А и история недели (§2.5.6.3).
    await app.act((Game g) => g.declinePurchase(item));
    if (!context.mounted) return;

    if (choice?.goToPlan ?? false) {
      await Navigator.pushNamed(context, AppRoutes.plan);
      return;
    }
    if (choice?.option == ShortfallOption.doTask) {
      await Navigator.pushNamed(context, AppRoutes.tasks);
      return;
    }
    // Закрыл лист молча — не показываем ничего: это его право, а не событие,
    // которое нужно комментировать.
    if (choice != null) await _showResult(context, app);
  }

  Future<void> _answerWish(
    BuildContext context,
    AppState app,
    CatalogItem item, {
    required bool keep,
  }) async {
    await app.act((Game g) => keep ? g.keepWish(item) : g.dropWish(item));
    if (!context.mounted) return;
    await _showResult(context, app);
  }

  /// Карточка последствия. После покупки Финни держит купленное в лапках:
  /// 🔴 покупка не исчезает в списке, она появляется у персонажа — а то,
  /// что остаётся, потом и в комнате на главном.
  Future<void> _showResult(BuildContext context, AppState app,
      {CatalogItem? bought}) async {
    if (!context.mounted) return;
    final ActionResult? f = app.lastFeedback;
    if (f == null) return;
    final Game g = app.game;
    final bool stays = bought != null && bought.keeps;
    await showFeedback(
      context,
      f,
      holding: bought == null || stays ? null : shopPic(bought.icon),
      holdingColor: bought == null ? null : AppColors.of(bought.envelope),
      room: stays
          ? RoomScene(
              stage: g.snapshot.stage,
              keepsakes: g.keepsakes,
              goal: g.goal,
              saved: g.snapshot.wallet.savings,
              fresh: bought.icon,
              fulfilled: g.fulfilledGoals,
            )
          : null,
    );
  }
}

/// Вопрос о том, что ребёнок отложил неделю назад.
///
/// 🔴 Оба ответа равноправны: одинаковые кнопки, одинаковый вес, никакого
/// «правильного». «Уже не хочу» — не отмена и не проигрыш: именно ради
/// возможности передумать пауза и существует.
class _WishQuestion extends StatelessWidget {
  const _WishQuestion({
    required this.item,
    required this.onKeep,
    required this.onDrop,
  });

  final CatalogItem item;
  final VoidCallback onKeep;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.envelope),
        border: Border.all(color: AppColors.wants, width: 2),
        boxShadow: Paper.cut(AppColors.wantsBg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Pictogram(Pic.hand, size: 26, color: AppColors.wants),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  'Неделю назад «${item.title}» отправилось ждать',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text('Всё ещё хочешь?',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: Gap.md),
          // 🔴 Обе кнопки одного вида. Сначала «Да, хочу» была залитой,
          // а «Уже не хочу» — контурной, и это молча подталкивало к покупке:
          // ровно к тому, от чего пауза должна защищать. На экране перекос
          // был очевиден, в коде — нет.
          OutlinedButton(onPressed: onKeep, child: const Text('Да, хочу')),
          const SizedBox(height: Gap.sm),
          OutlinedButton(onPressed: onDrop, child: const Text('Уже не хочу')),
        ],
      ),
    );
  }
}

/// То, что отложено на этой же неделе. Спрашивать про это рано — пауза
/// должна быть паузой, — но ребёнок должен видеть, что список не потерялся.
class _WaitingNote extends StatelessWidget {
  const _WaitingNote({required this.items});

  final List<CatalogItem> items;

  @override
  Widget build(BuildContext context) {
    final String what = items.map((CatalogItem i) => '«${i.title}»').join(', ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Pictogram(Pic.clock, size: 22, color: AppColors.inkSoft),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            'Ждёт до следующей недели: $what',
            style: const TextStyle(fontSize: 16, color: AppColors.inkSoft),
          ),
        ),
      ],
    );
  }
}

/// Заголовок раздела: иконка, цвет и подпись словами — три канала смысла
/// вместо цвета в одиночку (§3.6.5).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.envelope, required this.inEnvelope});

  final Envelope envelope;
  final int inEnvelope;

  @override
  Widget build(BuildContext context) {
    final Color c = AppColors.of(envelope);
    return Semantics(
      header: true,
      label: '${envelope.title}. В конверте $inEnvelope '
          '${Coins.word(inEnvelope)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Pictogram(AppColors.picOf(envelope), size: 28, color: c),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  envelope.title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: c),
                ),
              ),
              // «В конверте» — плашкой цвета конверта: голая монетка с
              // числом справа от заголовка читалась ценой, как у товаров.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(Gap.sm, 3, Gap.sm, 3),
                    decoration: BoxDecoration(
                      color: AppColors.bgOf(envelope),
                      borderRadius: BorderRadius.circular(Radii.chip),
                      border: Border.all(color: c, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text('в конверте ',
                            style:
                                TextStyle(fontSize: 16, color: AppColors.ink)),
                        Coins(inEnvelope, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text(envelope.hint,
              style: const TextStyle(fontSize: 16, color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}

/// Карточка товара. §2.5.6.2: цена, категория и предполагаемое влияние
/// на питомца видны **до** покупки — влияние словами, потому что «+3»
/// семилетке ничего не говорит.
class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.decision,
    required this.onTap,
  });

  final CatalogItem item;
  final PurchaseDecision decision;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color c = AppColors.of(item.envelope);
    final bool short = !decision.allowed;
    return Semantics(
      button: true,
      label: '${item.title}, ${item.price} ${Coins.word(item.price)}, '
          'конверт «${item.envelope.title}». ${item.hint}'
          '${short ? '. Не хватает ${decision.shortfall}' : ''}',
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: const LedgeBorder(
          radius: Radii.envelope,
          edge: Paper.edge,
          side: BorderSide(color: Paper.edge, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.envelope)),
          child: Container(
            constraints: const BoxConstraints(minHeight: TapSize.primary),
            padding:
                const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.md + 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.bgOf(item.envelope),
                    shape: BoxShape.circle,
                  ),
                  child: Pictogram(shopPic(item.icon), size: 26, color: c),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(item.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: Gap.sm),
                          _PriceTag(price: item.price, muted: short),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(item.hint,
                          style: const TextStyle(
                              fontSize: 16, color: AppColors.inkSoft)),
                      if (item.keeps || short) ...<Widget>[
                        const SizedBox(height: Gap.sm),
                        Wrap(
                          spacing: Gap.sm,
                          runSpacing: Gap.xs,
                          children: <Widget>[
                            // Вещь останется: её будет видно в комнате
                            // Финни. Это и есть «влияние на питомца» из
                            // §2.5.6.2 — не только сейчас, но и потом.
                            if (item.keeps)
                              const _Tag(
                                  pic: Pic.house,
                                  text: 'останется в комнате',
                                  color: AppColors.savings,
                                  bg: AppColors.savingsBg),
                            if (short)
                              _Tag(
                                  pic: Pic.info,
                                  text: 'не хватает ${decision.shortfall}',
                                  color: AppColors.ink,
                                  bg: AppColors.grid),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Витрина «Хочу»: вещи по две в ряд, в ряду одной высоты.
class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.items,
    required this.decide,
    required this.owned,
    required this.onTap,
  });

  /// Сколько таких вещей уже стоит в комнате.
  final int Function(CatalogItem) owned;

  final List<CatalogItem> items;
  final PurchaseDecision Function(CatalogItem) decide;
  final void Function(CatalogItem) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < items.length; i += 2) ...<Widget>[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int k = i; k < i + 2; k++) ...<Widget>[
                  Expanded(
                    child: k < items.length
                        ? _ShelfTile(
                            item: items[k],
                            owned: owned(items[k]),
                            decision: decide(items[k]),
                            onTap: () => onTap(items[k]),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (k == i) const SizedBox(width: Gap.sm),
                ],
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),
        ],
      ],
    );
  }
}

class _ShelfTile extends StatelessWidget {
  const _ShelfTile({
    required this.item,
    required this.decision,
    required this.onTap,
    this.owned = 0,
  });

  /// Сколько таких уже в комнате: вещь можно купить ещё раз, но ребёнок
  /// должен видеть, что одна у Финни уже есть.
  final int owned;

  final CatalogItem item;
  final PurchaseDecision decision;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool short = !decision.allowed;
    final Color c = AppColors.of(item.envelope);
    return Semantics(
      button: true,
      label: '${item.title}, ${item.price} ${Coins.word(item.price)}, '
          'конверт «${item.envelope.title}». ${item.hint}'
          '${item.keeps ? (owned > 0 ? '. В комнате уже $owned' : '. Останется в комнате') : ''}'
          '${short ? '. Не хватает ${decision.shortfall}' : ''}',
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: const LedgeBorder(
          radius: Radii.envelope,
          edge: Paper.edge,
          side: BorderSide(color: Paper.edge, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.envelope)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                Gap.sm + 4, Gap.md, Gap.sm + 4, Gap.md + 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 60,
                      height: 60,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.bgOf(item.envelope),
                        shape: BoxShape.circle,
                        border: Border.all(color: c, width: 2),
                      ),
                      child: Pictogram(shopPic(item.icon), size: 36, color: c),
                    ),
                    const SizedBox(width: Gap.xs),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _PriceTag(price: item.price, muted: short),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Text(item.title,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(item.hint,
                    style: const TextStyle(
                        fontSize: 16, color: AppColors.inkSoft)),
                const Spacer(),
                if (item.keeps || short) const SizedBox(height: Gap.sm),
                if (item.keeps)
                  _Tag(
                      pic: Pic.house,
                      text: owned > 0 ? 'в комнате: $owned' : 'в комнату',
                      color: AppColors.savings,
                      bg: AppColors.savingsBg),
                if (item.keeps && short) const SizedBox(height: Gap.xs),
                if (short)
                  _Tag(
                      pic: Pic.info,
                      text: 'не хватает ${decision.shortfall}',
                      color: AppColors.ink,
                      bg: AppColors.grid),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ценник — золотой, с уступом, как игровая кнопка покупки: сразу видно,
/// что вещь можно взять, и сколько она стоит.
class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.price, this.muted = false});

  final int price;

  /// Монеток не хватает — ценник спокойный, серый, без уступа: вещь
  /// открывается и объясняет варианты, но не выглядит «купи меня».
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.sm, 3, Gap.sm + 2, 6),
      decoration: ShapeDecoration(
        color: muted ? AppColors.grid : AppColors.action,
        shape: LedgeBorder(
          radius: Radii.chip,
          depth: muted ? 0 : 3,
          side: BorderSide(
              color: muted ? AppColors.line : AppColors.actionEdge, width: 1.5),
        ),
      ),
      child: Coins(price, size: 18),
    );
  }
}

/// Метка под товаром: пиктограмма и два-три слова на плашке.
class _Tag extends StatelessWidget {
  const _Tag({
    required this.pic,
    required this.text,
    required this.color,
    required this.bg,
  });

  final Pic pic;
  final String text;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.sm, 3, Gap.sm + 2, 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Pictogram(pic, size: 18, color: color),
          const SizedBox(width: Gap.xs),
          // Метка не рвётся на строки: «не хватает / 2» по отдельности
          // теряли смысл. Узкая плитка — метка чуть мельче, но целая.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(text,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Пиктограмма по строковому ключу из каталога. Рисуется вектором, без
/// картинок: растровые ассеты пришлось бы готовить в трёх плотностях, а ключ
/// в JSON позволяет добавить позицию каталога без единой правки кода
/// (§2.5.14).
Pic shopPic(String key) => switch (key) {
      'bowl' => Pic.bowl,
      'drop' => Pic.drop,
      'apple' => Pic.apple,
      'bath' => Pic.bath,
      'star' => Pic.sticker,
      'ball' => Pic.ball,
      'book' => Pic.book,
      'hat' => Pic.hat,
      'cake' => Pic.cake,
      _ => Pic.basket,
    };

// ─────────────────────────────── листы ───────────────────────────────

/// Что выбрал ребёнок в листе «не хватает». Кроме вариантов из домена есть
/// дорога к плану: если монетки ещё не разложены, «не хватает» — это не
/// про бедность, а про неразложенный кошелёк.
class _Choice {
  const _Choice.option(this.option) : goToPlan = false;
  const _Choice.plan()
      : option = null,
        goToPlan = true;

  final ShortfallOption? option;
  final bool goToPlan;
}

/// §2.5.6.3: покупка требует подтверждения.
/// Три ответа на лист покупки. Ожидание — полноценный третий вариант,
/// а не отказ: у него своя кнопка и свой текст.
enum _BuyChoice { buy, wait, no }

Future<_BuyChoice?> _askToBuy(
  BuildContext context,
  AppState app,
  CatalogItem item,
  PurchaseDecision d,
) {
  return showModalBottomSheet<_BuyChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext ctx) {
      final int inEnvelope =
          app.game.snapshot.wallet.envelopes.byEnvelope(item.envelope);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SheetTitle(item: item),
              const SizedBox(height: Gap.md),
              _SheetLine(
                icon: Pic.coin,
                text: 'Цена: ${item.price} ${Coins.word(item.price)}',
              ),
              _SheetLine(
                icon: AppColors.picOf(item.envelope),
                text: 'Спишется из конверта «${item.envelope.title}». '
                    'Сейчас там $inEnvelope ${Coins.word(inEnvelope)}',
              ),
              // Подсказка о предмете идёт без значка: сердечко рядом с ней
              // не обозначало ничего, кроме «тут тоже строчка».
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Text(item.hint, style: const TextStyle(fontSize: 16)),
              ),
              if (d.wastedWarning != null) ...<Widget>[
                const SizedBox(height: Gap.sm),
                _Warning(text: d.wastedWarning!),
              ],
              const SizedBox(height: Gap.lg),
              FilledButton.icon(
                icon: const Pictogram(Pic.basket, color: AppColors.onAction),
                label: const Text('Купить'),
                onPressed: () => Navigator.of(ctx).pop(_BuyChoice.buy),
              ),
              // 🔴 Ожидание предлагается только на дорогих необязательных
              // вещах. Предлагать подождать ради самой дешёвой наклейки —
              // ровно тот перегиб, из-за которого правило паузы бросают
              // в настоящих семьях.
              if (app.game.canWait(item)) ...<Widget>[
                const SizedBox(height: Gap.sm),
                OutlinedButton.icon(
                  icon: const Pictogram(Pic.hand, color: AppColors.ink),
                  label: const Text('Подождать неделю'),
                  onPressed: () => Navigator.of(ctx).pop(_BuyChoice.wait),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: Gap.xs),
                  child: Text(
                    'Монетки останутся у тебя. Через неделю спрошу, '
                    'хочешь ли ты это до сих пор.',
                    style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
                  ),
                ),
              ],
              const SizedBox(height: Gap.sm),
              OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(_BuyChoice.no),
                child: const Text('Не сейчас'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// §2.5.6.4: «приложение объясняет, чего не хватает и какие есть варианты».
///
/// Кнопки «нельзя» здесь нет ни в каком виде — только варианты, все одного
/// вида и веса.
Future<_Choice?> _askWhatInstead(
  BuildContext context,
  AppState app,
  CatalogItem item,
  PurchaseDecision d,
) {
  return showModalBottomSheet<_Choice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext ctx) {
      final Game g = app.game;
      final Wallet w = g.snapshot.wallet;
      final int inEnvelope = w.envelopes.byEnvelope(item.envelope);

      // 🔴 «Подождать» стоит первым, а не последним. Термины ТЗ: перенос
      // покупки на следующий период «допустим и не считается ошибкой
      // пользователя», а последний пункт в списке читается как «сдаться».
      final List<ShortfallOption> options = <ShortfallOption>[
        if (d.options.contains(ShortfallOption.waitForNextWeek))
          ShortfallOption.waitForNextWeek,
        ...d.options
            .where((ShortfallOption o) => o != ShortfallOption.waitForNextWeek),
      ];

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  'Не хватает ${d.shortfall} ${Coins.word(d.shortfall)}',
                  style: Theme.of(ctx).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: Gap.sm),
              Text(
                '«${item.title}» стоит ${item.price} '
                '${Coins.word(item.price)}, а в конверте '
                '«${item.envelope.title}» сейчас $inEnvelope.',
                style: Theme.of(ctx).textTheme.bodyLarge,
              ),
              const SizedBox(height: Gap.md),
              const Text('Вот что можно сделать:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: Gap.sm),
              for (final ShortfallOption o in options) ...<Widget>[
                _OptionTile(
                  icon: _optionPic(o),
                  title: _optionTitle(o, d.shortfall),
                  subtitle: _optionSubtitle(o, g, d.shortfall),
                  onTap: () => Navigator.of(ctx).pop(_Choice.option(o)),
                ),
                const SizedBox(height: Gap.sm),
              ],
              if (w.unallocated > 0) ...<Widget>[
                _OptionTile(
                  icon: Pic.wallet,
                  title: 'Разложить монетки по конвертам',
                  subtitle: '${w.unallocated} ${Coins.word(w.unallocated)} '
                      'ещё ждут своего конверта.',
                  onTap: () => Navigator.of(ctx).pop(const _Choice.plan()),
                ),
                const SizedBox(height: Gap.sm),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Pic _optionPic(ShortfallOption o) => switch (o) {
      ShortfallOption.waitForNextWeek => Pic.clock,
      ShortfallOption.moveFromSavings => Pic.jar,
      ShortfallOption.moveFromNeeds => Pic.bowl,
      ShortfallOption.moveFromWants => Pic.ball,
      ShortfallOption.doTask => Pic.task,
    };

String _optionTitle(ShortfallOption o, int shortfall) => switch (o) {
      ShortfallOption.waitForNextWeek => 'Подождать до следующей недели',
      ShortfallOption.moveFromSavings =>
        'Взять $shortfall ${Coins.wordAccusative(shortfall)} из «Копилки»',
      ShortfallOption.moveFromNeeds =>
        'Взять $shortfall ${Coins.wordAccusative(shortfall)} из «Нужного»',
      ShortfallOption.moveFromWants =>
        'Взять $shortfall ${Coins.wordAccusative(shortfall)} из «Хочу»',
      ShortfallOption.doTask => 'Выполнить задание',
    };

String _optionSubtitle(ShortfallOption o, Game g, int shortfall) => switch (o) {
      ShortfallOption.waitForNextWeek =>
        'Покупку можно перенести — это не ошибка. В начале недели придут '
            'новые монетки.',
      ShortfallOption.moveFromSavings => _savingsCost(g, shortfall),
      ShortfallOption.moveFromNeeds =>
        'Тогда на еду и чистоту для Финни останется меньше.',
      ShortfallOption.moveFromWants =>
        'Тогда на другие игрушки останется меньше.',
      ShortfallOption.doTask => 'За выполненное задание приходят монетки.',
    };

/// Честная цена снятия из копилки: на сколько отодвинется цель.
/// §2.5.7.5 требует показать последствие **до** подтверждения, а не после.
String _savingsCost(Game g, int amount) {
  final Goal? goal = g.goal;
  final int savings = g.snapshot.wallet.savings;
  if (goal == null) {
    return 'В копилке останется ${savings - amount}. '
        'Цель пока не выбрана, поэтому срок не считается.';
  }
  final WithdrawPreview p = SavingsRules.previewWithdraw(
    goal: goal,
    savings: savings,
    amount: amount,
    depositHistory: g.depositHistory,
  );
  final int? before = p.before.weeks;
  final int? after = p.after.weeks;
  if (before == null || after == null) {
    return 'В копилке останется ${p.savingsAfter} — до цели «${goal.title}» '
        'станет дальше.';
  }
  if (before == after) {
    return 'В копилке останется ${p.savingsAfter}. До цели «${goal.title}» '
        'по-прежнему примерно $after нед.';
  }
  return 'Цель «${goal.title}» отодвинется: было примерно $before нед., '
      'станет $after нед.';
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Pic icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: TapSize.primary),
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line, width: 2),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Pictogram(icon, size: 26, color: AppColors.primary),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 16, color: AppColors.inkSoft)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final Color c = AppColors.of(item.envelope);
    return Row(
      children: <Widget>[
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.bgOf(item.envelope),
            shape: BoxShape.circle,
          ),
          child: Pictogram(shopPic(item.icon), size: 28, color: c),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(item.title,
                style: Theme.of(context).textTheme.headlineSmall),
          ),
        ),
      ],
    );
  }
}

class _SheetLine extends StatelessWidget {
  const _SheetLine({required this.icon, required this.text});

  final Pic icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Pictogram(icon, size: 22, color: AppColors.inkSoft),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

/// Что произойдёт с питомцем после покупки (§2.5.6.2). Это не запрет и не
/// оценка: урок «не покупай лишнее» работает только тогда, когда лишнее
/// купить всё-таки можно, а слово о последствии — не то же самое, что
/// приговор трате до того, как ребёнок её совершил.
class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.wantsBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.wants.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Pictogram(Pic.info, size: 22, color: AppColors.wants),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
