import 'package:flutter/material.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';
import 'day_energy_looks.dart';
import 'hud_chips.dart';
import 'hud_delta.dart';
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
  // 29.09 (ratify: палитра 20.10).
  static const Color backing = Color(0x99161834);
  static const Color border = Color(0x8CFFFFFF);
  static const Color divider = Color(0x66FFFFFF);
  static const List<Shadow> textShadow = <Shadow>[
    Shadow(color: Color(0x99000000), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// Высота ряда показателей (палец — 48 dp).
  static const double rowHeight = 48;

  /// Ряд «День N из 7 · сытость» (вид E HUD дня).
  static const double dayRowHeight = 24;

  @override
  Widget build(BuildContext context) {
    final ResourceSnapshot s = snapshot;
    final DayView day = DayView.of(s);
    final double fed = day.fed ?? 0;
    final String energy = WorldHud.energyText(s.energy);
    final double top = WorldHud.energyMaxIn(context);
    Widget sep() => Container(
          width: 1,
          height: 28,
          color: divider,
          margin: const EdgeInsets.symmetric(horizontal: 2),
        );
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
          padding: EdgeInsets.fromLTRB(
            Gap.xs,
            0,
            Gap.xs,
            goal == null ? 0 : Gap.xs,
          ),
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
                      flex: 4,
                      child: _StripValue(
                        key: const ValueKey<String>('hud:coins'),
                        icon: _icon('hud_coin', Pic.coin, WorldColors.gold),
                        value: '${s.available}',
                        word: 'монеты',
                        semantic: 'Монет можно тратить: ${s.available}',
                        onTap: () =>
                            WorldHud.hintCoins(context, coins: s.available),
                      ),
                    ),
                    sep(),
                    Expanded(
                      flex: 4,
                      child: _StripValue(
                        key: const ValueKey<String>('hud:energy'),
                        icon: _icon('hud_bolt', Pic.bolt, WorldColors.energy),
                        value: energy,
                        word: 'силы',
                        fill: s.energy / top,
                        color: WorldColors.energy,
                        // Вариант B: под энергией вторая полоска — сытость.
                        fill2: day.look == HudLook.doubleBar ? fed : null,
                        semantic: day.look == HudLook.doubleBar
                            ? 'Сил: $energy из ${WorldHud.energyText(top)}. Сытость: '
                                '${(fed * 100).round()} из 100'
                            : 'Сил: $energy из ${WorldHud.energyText(top)}',
                        onTap: () => WorldHud.hintEnergy(context,
                            energy: s.energy,
                            satiety: day.look == HudLook.doubleBar
                                ? (fed * 100).round()
                                : null),
                      ),
                    ),
                    sep(),
                    // Вариант C: третья ячейка — сытость, настроение на Финни.
                    if (day.fedInHud)
                      Expanded(
                        flex: 5,
                        child: _StripValue(
                          key: const ValueKey<String>('hud:fed'),
                          icon: const Pictogram(
                            Pic.bowl,
                            size: 20,
                            color: fedColor,
                          ),
                          value: '${(fed * 100).round()}',
                          word: 'сытость',
                          fill: fed,
                          color: fedColor,
                          semantic: 'Сытость: '
                              '${(fed * 100).round()} из 100',
                          onTap: () {},
                        ),
                      )
                    else
                      Expanded(
                        // «настроение» — самое длинное слово полосы.
                        flex: 5,
                        // Сдвиг настроения «+2 / −3» на 3 с (модель 7 дней).
                        child: HudDelta(
                          value: s.happiness,
                          deltaKey: 'hud:happiness:delta',
                          child: _StripValue(
                            key: const ValueKey<String>('hud:happiness'),
                            icon:
                                _icon('hud_smile', Pic.smile, WorldColors.mood),
                            value: '${s.happiness}',
                            word: 'настроение',
                            fill: s.happiness / 100,
                            color: WorldColors.mood,
                            semantic: 'Настроение: ${s.happiness} из 100',
                            onTap: () => WorldHud.hintMood(
                              context,
                              mood: s.happiness,
                              reason: s.moodReason.text,
                            ),
                          ),
                        ),
                      ),
                    if (tools.isNotEmpty) sep(),
                    ...tools,
                  ],
                ),
              ),
              // Вид E: «День N из 7» и сытость — своим рядом, цель — под
              // ними (в один ряд на 360 dp цель резалась до «бе…»).
              if (day.look == HudLook.fedRow) ...<Widget>[
                SizedBox(
                  height: dayRowHeight,
                  child: Row(
                    children: <Widget>[
                      DayTimeChip(day),
                      const SizedBox(width: Gap.md),
                      // С настоящим шрифтом влезает целиком; узкое окно или
                      // другой шрифт — ужимается, а не вылезает за край.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: FedChip(fed),
                        ),
                      ),
                    ],
                  ),
                ),
                if (goal case final Widget g) g,
              ]
              // Варианты дня: метка времени перед строкой цели.
              else if (day.look != HudLook.asIs)
                Row(
                  children: <Widget>[
                    DayTimeChip(day),
                    if (goal case final Widget g) ...<Widget>[
                      const SizedBox(width: Gap.sm),
                      Expanded(child: g),
                    ],
                  ],
                )
              else if (goal case final Widget g)
                g,
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
    return Image.asset(
      path,
      key: ValueKey<String>('hud:icon:$id'),
      width: 24,
      height: 24,
      filterQuality: FilterQuality.none,
      isAntiAlias: false,
      excludeFromSemantics: true,
      errorBuilder: (_, __, ___) => Pictogram(fallback, size: 20, color: color),
    );
  }
}

/// Одно значение полосы: значок и число, под ним — слово ([word]: три
/// значения со словами, разбор финала 15.10) и тонкая полоска ([fill]),
/// если это шкала. Касание — пояснение.
class _StripValue extends StatelessWidget {
  const _StripValue({
    super.key,
    required this.icon,
    required this.value,
    required this.word,
    required this.semantic,
    required this.onTap,
    this.fill,
    this.fill2,
    this.color = WorldColors.text,
  });

  final Widget icon;
  final String value;
  final String word;
  final String semantic;
  final VoidCallback onTap;
  final double? fill;

  /// Вторая полоска (сытость, вариант B) — под первой.
  final double? fill2;
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
                            height: 1.1,
                            shadows: HudStrip.textShadow)),
                  ],
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(word,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                        fontSize: 14,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        color: Color(0xE6FFFFFF),
                        shadows: HudStrip.textShadow)),
              ),
              // Вариант B HUD дня: под силами вторая полоска — сытость. Обе
              // тоньше (3 dp, зазор 1), чтобы ячейка не вылезала из ряда
              // 48 dp с настоящими значками (Денис, чат 1900).
              if (fill case final double f) ...<Widget>[
                SizedBox(height: fill2 == null ? 2 : 1),
                FractionallySizedBox(
                  widthFactor: 0.7,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: f.clamp(0.0, 1.0),
                      minHeight: fill2 == null ? 4 : 3,
                      color: color,
                      backgroundColor: const Color(0x40FFFFFF),
                    ),
                  ),
                ),
              ],
              if (fill2 case final double f2) ...<Widget>[
                const SizedBox(height: 1),
                FractionallySizedBox(
                  widthFactor: 0.7,
                  child: ValueBar(f2, fedColor, height: 3),
                ),
              ],
            ],
          ),
        ),
      );
}
