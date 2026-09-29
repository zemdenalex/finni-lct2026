import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pic_text.dart';

import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';
import '../world_layout.dart';

/// Верхняя строка ресурсов нового мира: 💰 доступно · 🐷 накоплено ·
/// ⚡ полоса + число · 😊 полоса + число + лицо.
///
/// 🔴 Цвет не единственный сигнал (ТЗ 3.6.5): у каждого ресурса иконка,
/// число и подпись для озвучки. Иконки векторные (`Pic`), не эмодзи: эмодзи
/// на Android 8 и в браузере рисуются системным шрифтом по-разному
/// (`docs/design-system.md` §5). Шрифт HUD — обычный, не пиксельный
/// (`docs/game/screen-home-room.md`, «Не делать»).
///
/// Переиспользуется экранами потока B: `WorldHud(snapshot: …)`.
/// Тап по ресурсу — короткая подсказка, что это такое.
class WorldHud extends StatelessWidget {
  const WorldHud({super.key, required this.snapshot, this.trailing});

  final ResourceSnapshot snapshot;

  /// Что поставить справа от денег (например, кнопку «?»).
  final Widget? trailing;

  /// Высота HUD в альбомной — как прежние 48 dp ячеек с полями по 4.
  static const double landscapeHeight = 56;

  /// Верх шкалы ⚡ (контракт: 0..14).
  static const double energyMax = 14;

  /// ⚡ дробная с шагом 0,5 — «7» или «7,5».
  static String energyText(double e) => energyShown(e);

  /// Тексты карточек — `content/hud.json` (копия в сборке).
  static const String textsAsset = 'assets/content/world/hud.json';

  /// Карточка числа HUD (Денис 29.09: «после нажатия на число написано, что
  /// это такое»): что это, текущее значение и полоса, где она есть. Тексты
  /// из [textsAsset]; файла нет — запасной текст.
  static Future<void> explain(BuildContext context, String id,
      {required String value,
      String max = '',
      double? fill,
      Color color = WorldColors.gold,
      String? reason,
      required String fallbackTitle}) async {
    Map<String, Object?> e = const <String, Object?>{};
    try {
      final Object? root = jsonDecode(await rootBundle.loadString(textsAsset));
      if (root is Map<String, Object?> && root[id] is Map<String, Object?>) {
        e = root[id]! as Map<String, Object?>;
      }
    } on Object {
      // без файла — только заголовок и значение
    }
    String fill_(Object? t) => (t is String ? t : '')
        .replaceAll('{value}', value)
        .replaceAll('{max}', max);
    final String title =
        e['title'] is String ? e['title']! as String : fallbackTitle;
    final String line = e['value'] is String ? fill_(e['value']) : value;
    final String text = <String>[
      if (reason != null && reason.isNotEmpty) reason,
      fill_(e['text']),
    ].where((String t) => t.isNotEmpty).join('\n\n');
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        key: ValueKey<String>('hud:explain:$id'),
        title: PicText(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(line,
                key: ValueKey<String>('hud:explain:$id:value'),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            if (fill != null) ...<Widget>[
              const SizedBox(height: Gap.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    key: const ValueKey<String>('hud:hint:bar'),
                    value: fill.clamp(0.0, 1.0),
                    minHeight: 12,
                    color: color,
                    backgroundColor: WorldColors.night),
              ),
            ],
            if (text.isNotEmpty) ...<Widget>[
              const SizedBox(height: Gap.sm),
              Text(text, style: const TextStyle(fontSize: 16)),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('Понятно')),
        ],
      ),
    );
  }

  /// Подсказки по показателям — одни у полосы HUD и у фишек поверх сцены
  /// ([HudChips]): карточка [explain] с текущим значением.
  static void hintCoins(BuildContext context, {int? coins}) =>
      explain(context, 'coins',
          value: coins == null ? '' : '$coins', fallbackTitle: 'Монеты');

  static void hintSaved(BuildContext context, {int? saved}) =>
      explain(context, 'saved',
          value: saved == null ? '' : '$saved', fallbackTitle: 'Копилка');

  static void hintEnergy(BuildContext context, {double? energy}) =>
      explain(context, 'energy',
          value: energy == null ? '' : energyText(energy),
          max: energyText(energyMax),
          fill: energy == null ? null : energy / energyMax,
          color: WorldColors.energy,
          fallbackTitle: 'Энергия');

  static void hintMood(BuildContext context, {int? mood, String? reason}) =>
      explain(context, 'happiness',
          value: mood == null ? '' : '$mood',
          max: '100',
          fill: mood == null ? null : mood / 100,
          color: WorldColors.mood,
          reason: reason,
          fallbackTitle: 'Настроение');

  @override
  Widget build(BuildContext context) {
    final ResourceSnapshot s = snapshot;
    final String energy = energyText(s.energy);
    final Widget coins = _Cell(
      key: const ValueKey<String>('hud:coins'),
      icon: Pic.coin,
      iconColor: WorldColors.gold,
      value: '${s.available}',
      caption: 'есть',
      semantic: 'Монет доступно: ${s.available}',
      onTap: () => hintCoins(context, coins: s.available),
    );
    // Копилки в HUD нет (Денис 29.09): её сумма — над копилкой в комнате и
    // в плане недели.
    final Widget energyMeter = _Meter(
      key: const ValueKey<String>('hud:energy'),
      icon: Pic.bolt,
      iconColor: WorldColors.energy,
      fill: (s.energy / energyMax).clamp(0.0, 1.0),
      color: WorldColors.energy,
      value: energy,
      semantic: 'Энергия: $energy из 14',
      onTap: () => hintEnergy(context, energy: s.energy),
    );
    final Widget happinessMeter = _Meter(
      key: const ValueKey<String>('hud:happiness'),
      icon: Pic.smile,
      iconColor: WorldColors.mood,
      fill: (s.happiness / 100).clamp(0.0, 1.0),
      color: WorldColors.mood,
      value: '${s.happiness}',
      semantic: 'Настроение: ${s.happiness} из 100',
      onTap: () => hintMood(context, mood: s.happiness),
    );
    // Альбомная — основная (world_layout.dart): одна строка, чтобы сцене
    // осталась высота. Портрет — две строки, как раньше.
    final Widget content = WorldLayout.isLandscape(context)
        ? Row(
            children: <Widget>[
              // Ячейкам монет — больше места, чем полосам: полоса
              // тянется, а число и подпись — нет (подпись «в копилке»
              // при 3 : 4 ужималась до 12 sp).
              Expanded(flex: 4, child: coins),
              Expanded(flex: 3, child: energyMeter),
              const SizedBox(width: Gap.sm),
              Expanded(flex: 3, child: happinessMeter),
              if (trailing != null) trailing!,
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: coins),
                  if (trailing != null) trailing!,
                ],
              ),
              Row(
                children: <Widget>[
                  Expanded(child: energyMeter),
                  const SizedBox(width: Gap.sm),
                  Expanded(child: happinessMeter),
                ],
              ),
            ],
          );
    // Альбомная: высота строки — ровно 56 dp с любым [trailing] (кнопка ⚙
    // в комнате — 56 dp), без вертикальных полей: иначе HUD растёт, и
    // комнате под ним не хватает высоты на масштаб ×2.
    return Material(
      color: WorldColors.panel,
      child: Padding(
        padding: WorldLayout.isLandscape(context)
            ? const EdgeInsets.symmetric(horizontal: Gap.sm)
            : const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.sm, Gap.xs),
        child: WorldLayout.isLandscape(context)
            ? ConstrainedBox(
                constraints: const BoxConstraints(minHeight: landscapeHeight),
                child: content)
            : content,
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.caption,
    required this.semantic,
    required this.onTap,
  });

  final Pic icon;
  final Color iconColor;
  final String value;
  final String caption;
  final String semantic;
  final VoidCallback onTap;

  static const double _iconSize = 20;
  static TextStyle get _valueStyle =>
      AppType.number(18, color: WorldColors.text);
  static const TextStyle _captionStyle =
      TextStyle(fontSize: 15, height: 1.2, color: WorldColors.textSoft);

  double _width(BuildContext context, String text, TextStyle style) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
          text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final double w = tp.width;
    tp.dispose();
    return w;
  }

  /// Число не ужимается — ужимается подпись (`docs/design-system.md` §1
  /// п. 4), но не мельче 14 sp: подпись встаёт в строку за числом, если
  /// влезает; иначе — под число; иначе её нет (значок и число остаются,
  /// TalkBack читает [semantic] целиком).
  Widget _content(BuildContext context, double room) {
    final double value = _width(context, this.value, _valueStyle);
    final double caption = _width(context, this.caption, _captionStyle);
    const double lead = _iconSize + Gap.xs;
    final Widget number = Text(this.value, style: _valueStyle);
    final Widget word =
        Text(this.caption, maxLines: 1, softWrap: false, style: _captionStyle);
    final Widget pic = Pictogram(icon, size: _iconSize, color: iconColor);
    if (lead + value + Gap.xs + caption <= room) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          pic,
          const SizedBox(width: Gap.xs),
          number,
          const SizedBox(width: Gap.xs),
          word
        ],
      );
    }
    final bool stacked = lead + (caption > value ? caption : value) <= room;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        pic,
        const SizedBox(width: Gap.xs),
        if (stacked)
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[number, word],
          )
        else
          number,
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantic,
        excludeSemantics: true,
        onTap:
            onTap, // иначе excludeSemantics отсекает касание: TalkBack не нажмёт
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.chip),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Container(
              alignment: Alignment.centerLeft,
              // Зазор до соседней ячейки: подпись «есть» не упирается
              // в значок копилки.
              padding: const EdgeInsets.only(right: Gap.sm),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) =>
                    // Последняя страховка — если не влезает даже число
                    // (крупный шрифт на самом узком экране).
                    FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _content(context, c.maxWidth),
                ),
              ),
            ),
          ),
        ),
      );
}

class _Meter extends StatelessWidget {
  const _Meter({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.fill,
    required this.color,
    required this.value,
    required this.semantic,
    required this.onTap,
  });

  final Pic icon;
  final Color iconColor;
  final double fill;
  final Color color;
  final String value;
  final String semantic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantic,
        excludeSemantics: true,
        onTap:
            onTap, // иначе excludeSemantics отсекает касание: TalkBack не нажмёт
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.chip),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            // Число сжимается, а не вылезает: в узкой ячейке альбомной HUD
            // «12,5» ⚡ (обеды дома дают дробную ⚡ на неделю) шире места.
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) => Row(
                children: <Widget>[
                  Pictogram(icon, size: 18, color: iconColor),
                  const SizedBox(width: Gap.xs),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fill,
                        minHeight: 8,
                        color: color,
                        backgroundColor: WorldColors.raised,
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.xs),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: (c.maxWidth - 18 - Gap.xs * 2 - 8)
                            .clamp(0.0, 76.0)),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(value,
                          style: AppType.number(15, color: WorldColors.text)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
