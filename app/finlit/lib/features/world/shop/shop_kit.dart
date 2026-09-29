import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../domain/world/contract.dart';
import '../home/world_hud.dart';
import '../world_layout.dart';
import '../pic_text.dart';
import '../world_help.dart';
import '../world_routes.dart';
import '../../../core/world_theme.dart';

export '../world_help.dart' show showHelp;

/// Общее для S4 магазина, S5 зоомагазина и S9 копилки: каркас экрана,
/// конверт оплаты, превью счёта недели, подтверждение и карточка итога.

const TextStyle kitText =
    TextStyle(fontSize: 18, height: 1.3, color: WorldColors.text);
const TextStyle kitSoft =
    TextStyle(fontSize: 16, height: 1.3, color: WorldColors.textSoft);

/// Текст карточек в альбомной сетке: мельче [kitText], но не меньше 16 sp.
const TextStyle kitTextCompact =
    TextStyle(fontSize: 16, height: 1.3, color: WorldColors.text);

/// [kitText] в портрете, [kitTextCompact] в альбомной.
TextStyle kitBody(BuildContext context) =>
    WorldLayout.isLandscape(context) ? kitTextCompact : kitText;
const TextStyle kitTitle = TextStyle(
    fontSize: 20, fontWeight: FontWeight.w800, color: WorldColors.text);

/// Минимальная кнопка (ТЗ: ≥ 48 dp).
const Size kitButton = Size(48, 48);

// ─────────────────────────────── каталог мира ───────────────────────────────

/// Позиции раздела в порядке каталога мира.
///
/// 🔴 Каталог живой (⚡ досуга зависит от 😊): читать в `build` из
/// `WorldState.world`, не кешировать.
List<WorldCatalogItem> catalogOf(World w, WorldCatalogCategory c) =>
    <WorldCatalogItem>[
      for (final WorldCatalogItem i in w.catalog)
        if (i.category == c) i
    ];

/// Выполнено ли условие открытия [WorldCatalogItem.requires]: `any_pet`,
/// `transport` или id вещи. Правило открытия проверяет мир (`canDo`); здесь
/// — только чтобы показать [WorldCatalogItem.requiresText] вместо позиции.
bool requirementMet(World w, WorldCatalogItem i) {
  final String? r = i.requires;
  if (r == null) return true;
  final Set<String> owned = w.snapshot.owned;
  final WorldCatalogCategory? any = switch (r) {
    'any_pet' => WorldCatalogCategory.pet,
    'transport' => WorldCatalogCategory.transport,
    _ => null,
  };
  if (any == null) return owned.contains(r);
  return owned.any((String id) => w.catalogItem(id)?.category == any);
}

/// Отказ из-за этапа недели (`phase.*`): его показывают один раз над
/// списком, а не на каждой карточке.
bool isPhaseBlock(BlockReason? b) => b != null && b.code.startsWith('phase.');

// ─────────────────────────────── счёт недели ───────────────────────────────

/// Уровень еды, выбранный в этом мире.
///
/// Запасной путь для мира, который не отдаёт [ResourceSnapshot.foodId]:
/// помним выбор экрана, привязанный к объекту мира; до выбора — самая
/// дешёвая еда каталога (с неё начинается игра).
final Expando<String> _foodOf = Expando<String>('food');

/// Еда недели: из снимка мира ([ResourceSnapshot.foodId], этап 4), иначе
/// выбранная на экране, иначе самая дешёвая в каталоге. Снимок — первым:
/// после перезапуска память экрана пуста, а журнал помнит выбор.
WorldCatalogItem? chosenFood(World w) {
  final String? id = w.snapshot.foodId ?? _foodOf[w];
  final WorldCatalogItem? picked = id == null ? null : w.catalogItem(id);
  if (picked != null) return picked;
  WorldCatalogItem? cheapest;
  for (final WorldCatalogItem f in catalogOf(w, WorldCatalogCategory.food)) {
    if (cheapest == null || f.price < cheapest.price) cheapest = f;
  }
  return cheapest;
}

/// Запомнить еду, которую мир принял ([World.chooseFood] вернул ok).
void rememberFood(World w, String foodId) => _foodOf[w] = foodId;

/// Каким станет счёт недели после покупки [e] — со следующей недели.
///
/// Питомец добавляет корм к нынешнему счёту. Жильё меняет плату: счёт
/// следующей недели = еда + корм всех питомцев + плата за самое дорогое
/// жильё. Остальное счёт не трогает. Все слагаемые — из каталога мира.
int weeklyBillAfter(World w, WorldCatalogItem e) {
  final ResourceSnapshot s = w.snapshot;
  switch (e.category) {
    case WorldCatalogCategory.pet:
      return s.weeklyBill + e.weeklyCost;
    case WorldCatalogCategory.home:
      int pets = 0;
      int rent = e.weeklyCost;
      for (final String id in s.owned) {
        final WorldCatalogItem? o = w.catalogItem(id);
        if (o == null) continue;
        if (o.category == WorldCatalogCategory.pet) pets += o.weeklyCost;
        if (o.category == WorldCatalogCategory.home) {
          rent = math.max(rent, o.weeklyCost);
        }
      }
      return (chosenFood(w)?.weeklyCost ?? 0) + pets + rent;
    default:
      return s.weeklyBill;
  }
}

/// Счёт недели по частям словами: «еда 60 · корм питомца 20 · жильё 30».
///
/// Корм — отдельной строкой, чтобы ребёнок видел его до конца недели
/// (фидбек дизайнера 28.09, п. 9). Нулевые части не называются, кроме еды.
String billPartsText(WeekBillParts p) => <String>[
      'еда ${p.food}',
      if (p.petFood > 0) 'корм питомца ${p.petFood}',
      if (p.rent > 0) 'жильё ${p.rent}',
      if (p.extra > 0) 'добавка ${p.extra}',
    ].join(' · ');

/// Откуда платим: конверт иконкой и словом (не только цветом).
enum PayFrom { need, want, goal }

(IconData, String, Color) payFromLook(PayFrom p) => switch (p) {
      PayFrom.need => (Icons.receipt_long_rounded, 'НУЖНО', WorldColors.needs),
      PayFrom.want => (Icons.favorite_rounded, 'ХОЧУ', WorldColors.wants),
      PayFrom.goal => (Icons.savings_rounded, 'ЦЕЛЬ', WorldColors.goal),
    };

PayFrom payFromOf(WorldCatalogItem e) => e.isGoal
    ? PayFrom.goal
    : e.category == WorldCatalogCategory.food
        ? PayFrom.need
        : PayFrom.want;

/// Метка конверта: иконка + слово.
class PayFromTag extends StatelessWidget {
  const PayFromTag(this.from, {super.key});

  final PayFrom from;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String word, Color color) = payFromLook(from);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 20, color: color),
        const SizedBox(width: Gap.xs),
        Text(word,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }
}

/// «Счёт недели: сейчас → потом» — до любой покупки (ключевое правило B4).
class BillPreview extends StatelessWidget {
  const BillPreview({
    super.key,
    required this.now,
    required this.after,
    required this.when,
  });

  final int now;
  final int after;

  /// «со следующей недели» / «с этой недели».
  final String when;

  @override
  Widget build(BuildContext context) {
    final int d = after - now;
    final String change = d == 0
        ? 'не меняется'
        : d > 0
            ? '+$d $when'
            : '−${-d} $when';
    return Semantics(
      label: 'Счёт недели: сейчас $now, станет $after, $change',
      excludeSemantics: true,
      child: Container(
        key: const ValueKey<String>('bill:preview'),
        padding: const EdgeInsets.all(Gap.sm),
        decoration: BoxDecoration(
          color: WorldColors.needsBg,
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.receipt_long_rounded,
                color: WorldColors.needs, size: 22),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                d == 0
                    ? 'Счёт недели: $now — не меняется'
                    : 'Счёт недели: $now → $after ($change)',
                style: kitText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────── диалоги ───────────────────────────────

/// Подтверждение действия: заголовок, строки, превью счёта. true — «да».
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required List<String> lines,
  Widget? preview,
  required String yes,
  String no = 'Не сейчас',
}) async {
  final bool? r = await showDialog<bool>(
    context: context,
    builder: (BuildContext c) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final String l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: PicText(l, style: kitText),
              ),
            if (preview != null) preview,
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('confirm:no'),
          style: TextButton.styleFrom(minimumSize: kitButton),
          onPressed: () => Navigator.of(c).pop(false),
          child: Text(no),
        ),
        FilledButton(
          key: const ValueKey<String>('confirm:yes'),
          style: FilledButton.styleFrom(minimumSize: kitButton),
          onPressed: () => Navigator.of(c).pop(true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return r == true;
}

/// Подтверждение покупки из каталога: цена, конверт, что даёт, счёт недели.
Future<bool> confirmBuy(BuildContext context, World w, WorldCatalogItem e) {
  final ResourceSnapshot s = w.snapshot;
  final PayFrom from = payFromOf(e);
  final String pay = switch (from) {
    PayFrom.goal => 'Платим из копилки: там ${s.goal}.',
    PayFrom.want => 'Платим из ХОЧУ (${s.want}), потом из заработка '
        '(${s.free}).',
    PayFrom.need => 'Это счёт недели.',
  };
  return confirmAction(
    context,
    title: 'Купить: ${e.title}?',
    lines: <String>[
      'Цена: ${e.price}. $pay',
      if (effectText(e) case final String fx) fx,
      if (e.category == WorldCatalogCategory.pet)
        'Корм ${e.weeklyCost} в неделю — ест со следующей недели.',
      if (e.category == WorldCatalogCategory.home)
        'Плата за жильё ${e.weeklyCost} в неделю — со следующей недели.',
    ],
    preview: BillPreview(
      now: s.weeklyBill,
      after: weeklyBillAfter(w, e),
      when: 'со следующей недели',
    ),
    yes: 'Купить',
  );
}

/// ⚡ без знака: 1 → «1», 1.5 → «1,5».
String energyAbs(double v) {
  final double a = v.abs();
  return a == a.roundToDouble()
      ? a.toInt().toString()
      : a.toString().replaceAll('.', ',');
}

/// Что даёт позиция — словами, с иконками ⚡ / 😊. null — ничего.
String? effectText(WorldCatalogItem e) {
  String plus(int v) => v < 0 ? '−${-v}' : '+$v';
  final String en = energyAbs(e.energy);
  return switch (e.category) {
    WorldCatalogCategory.pet => '😊 ${plus(e.happiness)} в неделю'
        '${e.perk == null ? '' : '. ${e.perk}'}',
    WorldCatalogCategory.transport || WorldCatalogCategory.tech => e.perk,
    WorldCatalogCategory.home =>
      '😊 ${plus(e.happiness)} и ⚡ +$en каждую неделю',
    WorldCatalogCategory.clothes => e.happinessByWeek.length > 1
        ? '😊 ${plus(e.happinessByWeek.first)} в первую неделю, потом '
            '${e.happinessByWeek.skip(1).map(plus).join(', ')}'
        : '😊 ${plus(e.happiness)} на неделю, потом радость угасает',
    WorldCatalogCategory.decor => '😊 ${plus(e.happiness)} один раз',
    WorldCatalogCategory.snack => '⚡ +$en сразу'
        '${e.weeklyLimit == null ? '' : ', не больше ${e.weeklyLimit} в неделю'}',
    WorldCatalogCategory.food => '⚡ +$en сразу, 😊 ${plus(e.happiness)}',
    WorldCatalogCategory.leisure => '⚡ −$en, 😊 ${plus(e.happiness)}',
  };
}

/// Почему сейчас нельзя: текст мира и что можно сделать (значок + слова,
/// не только цвет).
class BlockNote extends StatelessWidget {
  const BlockNote(this.block, {super.key, this.showNext = true});

  final BlockReason block;

  /// Показать и [BlockReason.nextStep].
  final bool showNext;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded,
              size: 20, color: WorldColors.wants),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(block.text, style: kitBody(context)),
                if (showNext && block.nextStep != null)
                  Text('Что можно: ${block.nextStep}', style: kitSoft),
              ],
            ),
          ),
        ],
      );
}

// ─────────────────────────────── каркас ───────────────────────────────

/// Экран потока B: «назад» слева, заголовок, «?» справа, HUD под ним.
class WorldPage extends StatelessWidget {
  const WorldPage({
    super.key,
    required this.id,
    required this.title,
    required this.snapshot,
    required this.helpTitle,
    required this.help,
    required this.body,
    this.header,
    this.result,
  });

  /// Префикс ключей: `shop`, `pets`, `piggy`.
  final String id;
  final String title;
  final ResourceSnapshot snapshot;
  final String helpTitle;
  final String help;
  final Widget body;

  /// Что поставить между HUD и телом (вкладки). В альбомной — в шапку
  /// рядом с заголовком: высота там дороже ширины.
  final Widget? header;

  /// Итог последнего действия — над списком, чтобы не уехал с прокруткой.
  final WorldResult? result;

  void _back(BuildContext context) {
    final NavigatorState nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed(WorldRoutes.room);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool land = WorldLayout.isLandscape(context);
    final Widget? resultCard = result == null ? null : ResultCard(result!);
    return Scaffold(
      backgroundColor: WorldColors.night,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        // Альбомная — основная: низкая шапка, высота нужна списку.
        toolbarHeight: land ? 48 : null,
        leading: IconButton(
          key: ValueKey<String>('$id:back'),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Назад',
          onPressed: () => _back(context),
        ),
        title: land && header != null
            ? Row(
                children: <Widget>[
                  Text(title),
                  const SizedBox(width: Gap.md),
                  Expanded(child: header!),
                ],
              )
            : Text(title),
        actions: <Widget>[
          HelpButton(
            key: ValueKey<String>('$id:help'),
            onPressed: () => showHelp(context, helpTitle, help),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WorldHud(snapshot: snapshot),
            if (header != null && !land) header!,
            if (land)
              // Итог — справа от списка, а не над ним: в альбомной высота
              // дороже ширины.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: body),
                    if (resultCard != null)
                      SizedBox(
                        width: 240,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(Gap.sm),
                          child: resultCard,
                        ),
                      ),
                  ],
                ),
              )
            else ...<Widget>[
              if (resultCard != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.sm, 0),
                  child: resultCard,
                ),
              Expanded(child: body),
            ],
          ],
        ),
      ),
    );
  }
}

/// Итог последнего действия: получилось или почему нет и что делать.
class ResultCard extends StatelessWidget {
  const ResultCard(this.result, {super.key});

  final WorldResult result;

  @override
  Widget build(BuildContext context) {
    final bool ok = result.ok;
    return Panel(
      key: const ValueKey<String>('result:card'),
      color: ok ? WorldColors.needsBg : WorldColors.wantsBg,
      padding: const EdgeInsets.all(Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(ok ? Icons.check_circle_rounded : Icons.info_rounded,
              color: ok ? WorldColors.needs : WorldColors.wants, size: 24),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(ok ? 'Готово' : 'Не вышло',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: WorldColors.text)),
                Text(result.reason,
                    key: const ValueKey<String>('result:reason'),
                    style: kitText),
                if (result.nextStep != null)
                  Text('Что можно: ${result.nextStep}',
                      key: const ValueKey<String>('result:next'),
                      style: kitSoft),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Строка «иконка + текст» для отметок (уже есть, копим, выбрано).
class MarkLine extends StatelessWidget {
  const MarkLine(this.icon, this.text, {super.key, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 20, color: color ?? WorldColors.text),
          const SizedBox(width: Gap.xs),
          Flexible(
            child: Text(text,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color ?? WorldColors.text)),
          ),
        ],
      );
}

// ─────────────────────────────── раскладка ───────────────────────────────

/// Сколько колонок карточек влезает в [width]: в портрете 360 dp — одна,
/// в альбомной 640 dp — три (две, если справа карточка итога).
int kitColumns(double width, {double minCard = 176, int max = 3}) =>
    ((width + Gap.sm) / (minCard + Gap.sm)).floor().clamp(1, max);

/// Ширина колонки [CardGrid] для карточки внутри неё. Карточке нельзя
/// мерить себя LayoutBuilder'ом (ряд меряет её высоту через
/// IntrinsicHeight), поэтому ширину сообщает сама сетка.
class CardWidth extends InheritedWidget {
  const CardWidth({super.key, required this.width, required super.child});

  final double width;

  /// Ширина колонки или null — карточка не в [CardGrid].
  static double? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardWidth>()?.width;

  @override
  bool updateShouldNotify(CardWidth old) => old.width != width;
}

/// Размер шрифта названия: самый крупный из [sizes], при котором [text]
/// целиком помещается в [lines] строк ширины [width] и самое длинное слово
/// не рвётся посреди («Котлета с карто|шкой»). Название из каталога не
/// обрезается многоточием (смоук 29.09: «Котлета с картошк…»): не влез ни
/// один размер — самый мелкий, а строк будет больше. 16 sp — нижняя граница
/// основного текста по ТЗ; 14 — только если на 16 название не встаёт в две
/// строки (как у подписи, `test/support/text_floor.dart`).
double fitWordsFontSize(
    BuildContext context, String text, TextStyle style, double width,
    {List<double> sizes = const <double>[20, 18, 16, 14], int lines = 2}) {
  final String longest = text
      .split(RegExp(r'\s+'))
      .fold('', (String a, String b) => b.length > a.length ? b : a);
  final TextStyle base = DefaultTextStyle.of(context).style.merge(style);
  final TextScaler scaler = MediaQuery.textScalerOf(context);
  bool fits(String t, double size, int maxLines) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: t, style: base.copyWith(fontSize: size)),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: maxLines,
    )..layout(maxWidth: width);
    final bool ok = !tp.didExceedMaxLines && tp.width <= width;
    tp.dispose();
    return ok;
  }

  for (final double size in sizes) {
    if (fits(longest, size, 1) && fits(text, size, lines)) return size;
  }
  return sizes.last;
}

/// Карточки сеткой: в альбомной 2–3 колонки, чтобы экран высотой 360 dp
/// показывал сразу несколько позиций; в портрете — столбик, как раньше.
///
/// Карточки одного ряда тянутся до общей высоты (кнопки — по низу).
/// Внутри карточек не должно быть LayoutBuilder: ряд меряет их высоту.
class CardGrid extends StatelessWidget {
  const CardGrid({
    super.key,
    required this.children,
    this.minCard = 176,
    this.maxColumns = 3,
  });

  final List<Widget> children;
  final double minCard;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final int cols =
              kitColumns(box.maxWidth, minCard: minCard, max: maxColumns);
          final double colWidth = (box.maxWidth - Gap.sm * (cols - 1)) / cols;
          if (cols == 1) {
            return CardWidth(
              width: colWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < children.length; i += cols)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int c = 0; c < cols; c++) ...<Widget>[
                        if (c > 0) const SizedBox(width: Gap.sm),
                        Expanded(
                          child: i + c < children.length
                              ? CardWidth(
                                  width: colWidth, child: children[i + c])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      );
}

/// Вкладка: в альбомной — низкая, значок рядом со словом (48 dp вместо 72).
Tab kitTab(BuildContext context,
    {required Key key, required IconData icon, required String text}) {
  if (!WorldLayout.isLandscape(context)) {
    return Tab(key: key, icon: Icon(icon), text: text);
  }
  return Tab(
    key: key,
    height: 48,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 22),
        const SizedBox(width: Gap.sm),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

/// Картинка вещи в карточке: вписана в коробку [width] × [height], hi-res
/// арт уменьшается сглаженно. Размер коробки фиксирован — ряд [CardGrid]
/// меряет высоту до загрузки файла. Подпись несёт название рядом, поэтому
/// картинка для TalkBack скрыта.
class ItemPicture extends StatelessWidget {
  const ItemPicture(this.path,
      {super.key, required this.width, required this.height});

  final String path;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: Image.asset(
          path,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
}

/// Коробка картинки в карточке: в альбомной — рядом с кнопкой 48 dp.
Size itemPictureBox(BuildContext context) =>
    WorldLayout.isLandscape(context) ? const Size(48, 48) : const Size(72, 64);

/// Цена с монеткой и подписью.
class PriceLine extends StatelessWidget {
  const PriceLine(this.price, {super.key, this.suffix});

  final int price;
  final String? suffix;

  @override
  Widget build(BuildContext context) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Gap.xs,
        children: <Widget>[
          Coins(price, size: 20),
          if (suffix != null) Text(suffix!, style: kitSoft),
        ],
      );
}

/// Три шкалы блюда (Денис 29.09, 938; разведка §4): польза ⚡ и вкус 😊
/// делениями — ряд блюд сравнивается взглядом, без чтения. Цена — в
/// строке названия. Лучшего блюда не помечаем: выбор — компромисс.
///
/// Деления: ⚡ — по 0,5, 😊 — по 1; сколько делений всего — по самому
/// полезному и самому вкусному блюду каталога, чисел в коде нет.
class FoodScales extends StatelessWidget {
  const FoodScales(this.food,
      {super.key, required this.maxEnergy, required this.maxHappiness});

  final WorldCatalogItem food;
  final double maxEnergy;
  final int maxHappiness;

  @override
  Widget build(BuildContext context) {
    final int e = (food.energy * 2).round();
    final int eMax = (maxEnergy * 2).round();
    final String label = 'Польза: ⚡ +${energyAbs(food.energy)} сразу. '
        'Вкус: 😊 ${food.happiness < 0 ? food.happiness : '+${food.happiness}'}.';
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Wrap(
        spacing: Gap.md,
        runSpacing: Gap.xs,
        children: <Widget>[
          _Scale(
              key: ValueKey<String>('scale:energy:${food.id}'),
              word: 'Польза',
              icon: '⚡',
              filled: e,
              total: eMax,
              color: WorldColors.energy),
          _Scale(
              key: ValueKey<String>('scale:taste:${food.id}'),
              word: 'Вкус',
              icon: '😊',
              filled: food.happiness,
              total: maxHappiness,
              color: WorldColors.mood),
        ],
      ),
    );
  }
}

class _Scale extends StatelessWidget {
  const _Scale({
    super.key,
    required this.word,
    required this.icon,
    required this.filled,
    required this.total,
    required this.color,
  });

  final String word;
  final String icon;
  final int filled;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 0,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: Gap.xs),
            child: Text('$word $icon', style: kitSoft),
          ),
          for (int i = 0; i < total; i++)
            Container(
              width: 10,
              height: 14,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: i < filled ? color : Colors.transparent,
                border: Border.all(color: color, width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      );
}
