import 'package:flutter/material.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';
import 'day_energy_looks.dart';
import 'hud_chips.dart';
import 'hud_delta.dart';
import 'hud_strip.dart';
import 'world_hud.dart';

/// Цвета макета Алины «Комната · HUD · меню» (`ref/final/alina-ui-2026-10-18/
/// alina-01-komnata-hud-nav.jpg`), сняты пипеткой с макета.
abstract final class AlinaColors {
  /// «День N из 7», активный пункт меню — [WorldColors.goldText].
  static const Color gold = WorldColors.goldText;

  /// Дата в верхней строке — светлее [gold]: на стене под затемнением
  /// золото 29.09 давало 4,2–4,35 : 1 (нужно 4,5 для 16 sp), это — 5,1+.
  static const Color dayText = Color(0xFFFFE09E);

  /// Кнопка действия: заливка и текст — золото мира ([WorldColors.gold],
  /// [WorldColors.onGold]); три оттенка золота на всю игру (спека §2.1).
  static const Color buttonTop = WorldColors.gold;
  static const Color buttonBottom = WorldColors.goldEdge;
  static const Color buttonText = WorldColors.onGold;

  /// Точка «всё хорошо».
  static const Color okDot = WorldColors.fullness;

  /// Затемнение сцены под верхней строкой и под меню: текст макета лежит
  /// прямо на сцене, без плашки. Тёмно-коричневый пола макета (#603830).
  static const Color scrim = Color(0x99301C18);
  static const Color scrimClear = Color(0x00301C18);

  /// Полоса меню — тёмный пол макета (#5F3831): белый текст 8,7 : 1.
  static const Color navBack = Color(0xFF5F3831);
  static const Color navBackClear = Color(0x005F3831);
}

/// Верхняя строка комнаты по макету Алины: слева «Дома» и «День N из 7»,
/// справа показатели значок · число · слово под ним — монеты, силы,
/// настроение. Второй ряд: строка цели (или «Комната Финни»), сытость (с
/// моделью дней) и «?». Без плашки: под строкой сцена затемнена
/// ([AlinaColors.scrim]).
///
/// Ключи и подписи TalkBack — как у [HudStrip]: `hud:coins`, `hud:energy`,
/// `hud:happiness`, `hud:fed`; касание числа — то же пояснение.
class RoomHud extends StatelessWidget {
  const RoomHud({
    super.key,
    required this.snapshot,
    this.registry,
    this.tools = const <Widget>[],
    this.goal,
    this.compact = false,
  });

  final ResourceSnapshot snapshot;
  final AssetRegistry? registry;

  /// Кнопки во втором ряду справа («?»).
  final List<Widget> tools;

  /// Строка цели — во втором ряду на месте «Комнаты Финни».
  final Widget? goal;

  /// Только первый ряд («Расставить»: комнате нужна высота, клетки сетки
  /// не мельче 48 dp и не под касанием второго ряда).
  final bool compact;

  /// Высота ряда показателей (со сдвигом настроения над числом).
  static const double rowHeight = 56;

  /// Второй ряд: цель · сытость · «?» (палец — 48).
  static const double titleHeight = 48;

  static const List<Shadow> _shadow = HudStrip.textShadow;

  @override
  Widget build(BuildContext context) {
    final ResourceSnapshot s = snapshot;
    final DayView day = DayView.of(s);
    final double top = WorldHud.energyMaxIn(context);
    final String energy = WorldHud.energyText(s.energy);
    final int? fed = day.on ? ((day.fed ?? 0) * 100).round() : null;
    return NoLargerText(
      child: Column(
        key: const ValueKey<String>('hud:strip'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: rowHeight,
            child: Row(
              children: <Widget>[
                // «Дома» и «День N из 7» — по своей ширине; остальное —
                // показателям.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'Дома',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Colors.white,
                        shadows: _shadow,
                      ),
                    ),
                    if (day.on)
                      Semantics(
                        label: day.dateSpoken,
                        excludeSemantics: true,
                        child: Text(
                          // Игровой календарь «Вт, 6 окт» (Настя 20.10).
                          day.dateShort,
                          key: const ValueKey<String>('hud:daytime'),
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: AlinaColors.dayText,
                            shadows: _shadow,
                          ),
                        ),
                      ),
                    // Сытость — третьей строкой под днём: в ряду показателей
                    // четвёртый на 360 dp ужимал подписи до ~10 sp, а во
                    // втором ряду она теснила название цели.
                    if (day.fed case final double f) FedChip(f, bar: false),
                  ],
                ),
                const SizedBox(width: Gap.xs),
                // Ячейки по весу ширины содержимого («настроение» — самое
                // длинное слово); касание — вся ячейка, не меньше пальца.
                _Value(
                  key: const ValueKey<String>('hud:coins'),
                  flex: 4,
                  icon: _icon('hud_coin', Pic.coin, WorldColors.gold),
                  value: '${s.available}',
                  word: 'монеты',
                  semantic: 'Монет можно тратить: ${s.available}',
                  onTap: () => WorldHud.hintCoins(context, coins: s.available),
                ),
                _Value(
                  key: const ValueKey<String>('hud:energy'),
                  flex: 4,
                  icon: _icon('hud_bolt', Pic.bolt, WorldColors.energy),
                  value: energy,
                  word: 'силы',
                  semantic: 'Сил: $energy из ${WorldHud.energyText(top)}',
                  onTap: () => WorldHud.hintEnergy(
                    context,
                    energy: s.energy,
                    satiety: fed,
                  ),
                ),
                _Value(
                  key: const ValueKey<String>('hud:happiness'),
                  flex: 5,
                  delta: s.happiness,
                  icon: _icon('hud_smile', Pic.smile, WorldColors.mood),
                  value: '${s.happiness}',
                  word: 'настроение',
                  semantic: 'Настроение: ${s.happiness} из 100',
                  onTap: () => WorldHud.hintMood(
                    context,
                    mood: s.happiness,
                    reason: s.moodReason.text,
                  ),
                ),
              ],
            ),
          ),
          // Второй ряд. В макете здесь «Комната Финни» и статус; четвёртый
          // показатель в первом ряду на 360 dp ужимал подписи до ~10 sp
          // (правило — ≥ 14), а третий ряд опускал дверь — обучалка не
          // помещалась. Цель (портрет) — на месте «Комнаты Финни»; без
          // цели в ряду (альбомная: цель в боковом столбце) — «Комната
          // Финни», как в макете.
          if (!compact)
            SizedBox(
              height: titleHeight,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: goal ??
                        const Text(
                          'Комната Финни',
                          key: ValueKey<String>('hud:place'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: _shadow,
                          ),
                        ),
                  ),
                  ...tools,
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _icon(String id, Pic fallback, Color color) {
    final String? path = registry?.hudIcon(id);
    if (path == null) return Pictogram(fallback, size: 20, color: color);
    return Image.asset(
      path,
      key: ValueKey<String>('hud:icon:$id'),
      width: 22,
      height: 22,
      filterQuality: FilterQuality.none,
      isAntiAlias: false,
      excludeFromSemantics: true,
      errorBuilder: (_, __, ___) => Pictogram(fallback, size: 20, color: color),
    );
  }
}

/// Показатель макета: значок и крупное число, под ними — слово. Ячейка —
/// доля ряда ([flex]); касание — вся ячейка (≥ 48 dp), содержимое при
/// нехватке места ужимается внутри неё, а не режется.
class _Value extends StatelessWidget {
  const _Value({
    super.key,
    required this.flex,
    required this.icon,
    required this.value,
    required this.word,
    required this.semantic,
    required this.onTap,
    this.delta,
  });

  final int flex;

  /// Настроение: сдвиг «+2 / −3» над числом ([HudDelta]).
  final int? delta;

  final Widget icon;
  final String value;
  final String word;
  final String semantic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget cell = Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WorldRadii.tag),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: TapSize.min,
            minWidth: TapSize.min,
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        icon,
                        const SizedBox(width: 4),
                        Text(
                          value,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 22,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: RoomHud._shadow,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      word,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        shadows: RoomHud._shadow,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Expanded(
      flex: flex,
      child: delta == null
          ? cell
          : HudDelta(
              value: delta!,
              deltaKey: 'hud:happiness:delta',
              child: cell,
            ),
    );
  }
}
