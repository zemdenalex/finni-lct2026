import 'package:flutter/material.dart';

import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';
import 'world_hud.dart';

/// Показатели поверх сцены (комнаты, города): 💰 · ⚡ · 😊 — фишками на
/// сплошной подложке, а не отдельной полосой интерфейса. Денис, 29.09
/// (вариант В): «монеты, энергию и счастье лучше сделать поверх комнаты и
/// других фонов, просто более выделяющимися».
///
/// Те же ключи (`hud:coins` …), подписи для TalkBack и подсказки по тапу,
/// что у полосы [WorldHud]: у ребёнка один язык показателей на всех экранах.
/// Цвет не единственный сигнал (ТЗ 3.6.5): значок, число и подпись.
///
/// [trailing] — кнопки справа в первом ряду («?», ⋮); они тоже на подложке.
class HudChips extends StatelessWidget {
  const HudChips(
      {super.key,
      required this.snapshot,
      this.trailing,
      this.leading,
      this.dense = false});

  /// Узкий столбец (город в альбомной): два ряда — деньги, под ними силы,
  /// настроение и кнопки.
  final bool dense;

  /// Кнопка слева («Назад» в городе) — на той же подложке.
  final Widget? leading;

  final ResourceSnapshot snapshot;

  /// Кнопки справа («?», ⋮) — на той же подложке.
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final ResourceSnapshot s = snapshot;
    final String energy = WorldHud.energyText(s.energy);
    // Полос в фишках нет (ревью В2, 29.09: один ряд, ~12 % высоты) —
    // полоса и причина видны по касанию, в подсказке.
    final List<Widget> chips = <Widget>[
      HudChip(
        key: const ValueKey<String>('hud:coins'),
        icon: Pic.coin,
        iconColor: WorldColors.gold,
        value: '${s.available}',
        semantic: 'Монет доступно: ${s.available}',
        onTap: () => WorldHud.hintCoins(context, coins: s.available),
      ),
      // Копилки в ряду нет (Денис 29.09): её сумма — табличкой над копилкой
      // в комнате.
      HudChip(
        key: const ValueKey<String>('hud:energy'),
        icon: Pic.bolt,
        iconColor: WorldColors.energy,
        value: energy,
        semantic: 'Энергия: $energy из 14',
        onTap: () => WorldHud.hintEnergy(context, energy: s.energy),
      ),
      HudChip(
        key: const ValueKey<String>('hud:happiness'),
        icon: Pic.smile,
        iconColor: WorldColors.mood,
        value: '${s.happiness}',
        semantic: 'Настроение: ${s.happiness} из 100',
        onTap: () => WorldHud.hintMood(context,
            mood: s.happiness, reason: s.moodReason.text),
      ),
    ];
    const double gap = Gap.xs;
    final List<Widget> after = <Widget>[
      for (final Widget t in trailing ?? const <Widget>[]) HudBacking(child: t),
    ];
    final Widget content;
    if (dense) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(spacing: gap, runSpacing: gap, children: chips.sublist(0, 1)),
          const SizedBox(height: gap),
          Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[...chips.sublist(1), ...after]),
        ],
      );
    } else {
      // Один ряд: [Назад] 💰 ⚡ 😊 … [?] [⋮]. Ряд не переносится
      // никогда: фишки делят место по длине числа, а число, которому тесно
      // (4 знака денег на 360 dp), чуть ужимается внутри фишки — высота
      // фишки остаётся 48 dp.
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (leading case final Widget l) ...<Widget>[
            HudBacking(child: l),
            const SizedBox(width: gap),
          ],
          Expanded(
            child: Row(children: <Widget>[
              for (int i = 0; i < chips.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: gap),
                Flexible(
                    flex: 3 + (chips[i] as HudChip).value.length,
                    child: chips[i]),
              ],
            ]),
          ),
          for (final Widget t in after) ...<Widget>[
            const SizedBox(width: gap),
            t,
          ],
        ],
      );
    }
    // Числа фишек не растут с системным шрифтом выше ×1: иначе ряд
    // переносится во второй и съедает сцену (бюджет 20–30 %, Денис 29.09).
    // Кегль ≥ 16 sp, TalkBack читает подпись целиком.
    return NoLargerText(child: content);
  }
}

/// Текст внутри не крупнее ×1 при системном увеличении шрифта (фишки и
/// строка цели над сценой). Не `MediaQuery.withClampedTextScaling`: приложение
/// уже зажимает масштаб снизу единицей (`app.dart`), и повторный зажим до
/// [1, 1] падает на проверке `maxScale > minScale`.
class NoLargerText extends StatelessWidget {
  const NoLargerText({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    if (mq.textScaler.scale(16) <= 16) return child;
    return MediaQuery(
        data: mq.copyWith(textScaler: TextScaler.noScaling), child: child);
  }
}

/// Сплошная подложка фишки: непрозрачная панель с контрастной рамкой и
/// тенью — читается на любом фоне сцены. Радиус из шкалы мира
/// ([WorldRadii.tile]), не «пилюля» (`design-bans.md`).
class HudBacking extends StatelessWidget {
  const HudBacking({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: WorldColors.panel,
        elevation: 3,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorldRadii.tile),
          side: const BorderSide(color: WorldColors.line, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? child : InkWell(onTap: onTap, child: child),
      );
}

/// Одна фишка: значок и число на сплошной подложке. Не ниже 48 dp; число
/// не режется и не ужимается.
class HudChip extends StatelessWidget {
  const HudChip({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.semantic,
    required this.onTap,
  });

  final Pic icon;
  final Color iconColor;
  final String value;
  final String semantic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantic,
        excludeSemantics: true,
        onTap: onTap, // иначе excludeSemantics отсекает касание
        child: HudBacking(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Pictogram(icon, size: 18, color: iconColor),
                    const SizedBox(width: 3),
                    Text(value,
                        maxLines: 1,
                        softWrap: false,
                        // Шрифт игры, не широкий цифровой: четыре фишки и
                        // «?», ⋮ встают в один ряд на 360 dp.
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: WorldColors.text)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
