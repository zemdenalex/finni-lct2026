import 'package:flutter/material.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';
import 'hud_chips.dart';
import 'world_hud.dart';

/// Верхняя плашка комнаты (Денис 29.09: «объединение 2 и 3, одна плашка, но с
/// полосками, монетки и молния — пиксель-артом»): одна полупрозрачная полоса
/// во всю ширину сцены. Ряд 1: монеты | ⚡ с полоской | 😊 с полоской | «?» ⋮
/// через тонкие разделители; ряд 2 — строка цели [goal].
///
/// Ключи и подписи TalkBack — те же, что у фишек ([HudChips]): `hud:coins`,
/// `hud:energy`, `hud:happiness`; касание числа — карточка-пояснение.
class HudStrip extends StatelessWidget {
  const HudStrip({
    super.key,
    required this.snapshot,
    this.registry,
    this.leading,
    this.tools = const <Widget>[],
    this.goal,
  });

  final ResourceSnapshot snapshot;

  /// Реестр арта — пиксельные значки (`hud_icons`); нет — значки-пиктограммы.
  final AssetRegistry? registry;

  /// Кнопка слева в первом ряду (в городе — «Назад»).
  final Widget? leading;

  /// Кнопки справа в первом ряду («?», ⋮).
  final List<Widget> tools;

  /// Второй ряд — строка цели.
  final Widget? goal;

  /// Подложка: тёмная, полупрозрачная. Альфа 0,6 (в макете ~0,42): только
  /// так белый текст даёт контраст ≥ 4,5 и на самом светлом потолке
  /// (#f1e6d8); проверка — hud_strip_test.
  static const Color backing = Color(0x99161834);
  static const Color border = Color(0x8CFFFFFF);
  static const Color divider = Color(0x66FFFFFF);
  static const List<Shadow> textShadow = <Shadow>[
    Shadow(color: Color(0x99000000), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// Высота ряда показателей (палец — 48 dp).
  static const double rowHeight = 48;

  @override
  Widget build(BuildContext context) {
    final ResourceSnapshot s = snapshot;
    final String energy = WorldHud.energyText(s.energy);
    Widget sep() => Container(
        width: 1,
        height: 28,
        color: divider,
        margin: const EdgeInsets.symmetric(horizontal: 2));
    return NoLargerText(
      child: DecoratedBox(
        key: const ValueKey<String>('hud:strip'),
        decoration: BoxDecoration(
          color: backing,
          borderRadius: BorderRadius.circular(WorldRadii.tile),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Padding(
          // Без строки цели снизу отступа нет: одна полоса в 48 dp.
          padding:
              EdgeInsets.fromLTRB(Gap.xs, 0, Gap.xs, goal == null ? 0 : Gap.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: rowHeight,
                child: Row(
                  children: <Widget>[
                    if (leading case final Widget l) ...<Widget>[l, sep()],
                    Expanded(
                      child: _StripValue(
                        key: const ValueKey<String>('hud:coins'),
                        icon: _icon('hud_coin', Pic.coin, WorldColors.gold),
                        value: '${s.available}',
                        semantic: 'Монет доступно: ${s.available}',
                        onTap: () =>
                            WorldHud.hintCoins(context, coins: s.available),
                      ),
                    ),
                    sep(),
                    Expanded(
                      child: _StripValue(
                        key: const ValueKey<String>('hud:energy'),
                        icon: _icon('hud_bolt', Pic.bolt, WorldColors.energy),
                        value: energy,
                        fill: s.energy / WorldHud.energyMax,
                        color: WorldColors.energy,
                        semantic: 'Энергия: $energy из 14',
                        onTap: () =>
                            WorldHud.hintEnergy(context, energy: s.energy),
                      ),
                    ),
                    sep(),
                    Expanded(
                      child: _StripValue(
                        key: const ValueKey<String>('hud:happiness'),
                        icon: _icon('hud_smile', Pic.smile, WorldColors.mood),
                        value: '${s.happiness}',
                        fill: s.happiness / 100,
                        color: WorldColors.mood,
                        semantic: 'Настроение: ${s.happiness} из 100',
                        onTap: () => WorldHud.hintMood(context,
                            mood: s.happiness, reason: s.moodReason.text),
                      ),
                    ),
                    if (tools.isNotEmpty) sep(),
                    ...tools,
                  ],
                ),
              ),
              if (goal case final Widget g) g,
            ],
          ),
        ),
      ),
    );
  }

  Widget _icon(String id, Pic fallback, Color color) {
    final String? path = registry?.hudIcon(id);
    if (path == null) return Pictogram(fallback, size: 20, color: color);
    // Пиксель-арт: 12 × 12 пикселей рисунка на 24 dp, без сглаживания.
    return Image.asset(path,
        key: ValueKey<String>('hud:icon:$id'),
        width: 24,
        height: 24,
        filterQuality: FilterQuality.none,
        isAntiAlias: false,
        excludeFromSemantics: true,
        errorBuilder: (_, __, ___) =>
            Pictogram(fallback, size: 20, color: color));
  }
}

/// Одно значение полосы: значок и число, под числом — тонкая полоска
/// ([fill]), если это шкала. Касание — пояснение.
class _StripValue extends StatelessWidget {
  const _StripValue({
    super.key,
    required this.icon,
    required this.value,
    required this.semantic,
    required this.onTap,
    this.fill,
    this.color = WorldColors.text,
  });

  final Widget icon;
  final String value;
  final String semantic;
  final VoidCallback onTap;
  final double? fill;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantic,
        excludeSemantics: true,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(WorldRadii.tag),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    icon,
                    const SizedBox(width: 4),
                    Text(value,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: HudStrip.textShadow)),
                  ],
                ),
              ),
              if (fill case final double f) ...<Widget>[
                const SizedBox(height: 3),
                FractionallySizedBox(
                  widthFactor: 0.7,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: f.clamp(0.0, 1.0),
                      minHeight: 5,
                      color: color,
                      backgroundColor: const Color(0x40FFFFFF),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}
