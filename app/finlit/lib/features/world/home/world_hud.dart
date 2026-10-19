import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../pic_text.dart';
import '../world_help.dart' show WorldDialogTitle;

import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';
import '../../../domain/world/world_game.dart';
import 'day_energy_looks.dart' show DayView;
import 'hud_chips.dart' show NoLargerText;
import 'hud_delta.dart';
import 'hud_strip.dart' show HudStrip;
import '../world_state.dart';

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

  /// Верх шкалы ⚡, если мир его не знает (фейк в тестах экранов): 0..14.
  static const double energyMax = 14;

  /// Верх шкалы ⚡ этого мира: в неделе из 7 дней — 20 (economy.json,
  /// `day_cycle.energy_max`), в недельном режиме — 14.
  static double energyMaxOf(World? w) =>
      w is WorldGame ? w.energyMaxNow : energyMax;

  /// То же по миру над экраном (без мира — [energyMax]).
  static double energyMaxIn(BuildContext context) =>
      energyMaxOf(Provider.of<WorldState?>(context, listen: false)?.world);

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
      String? extra,
      required String fallbackTitle}) async {
    // Имя героя (BG-01): `{name}` в тексте карточки и в причине настроения.
    final String hero =
        Provider.of<WorldState?>(context, listen: false)?.finniName ??
            OnboardingProgress.defaultFinniName;
    Map<String, Object?> e = const <String, Object?>{};
    try {
      final Object? root = jsonDecode(await rootBundle.loadString(textsAsset));
      if (root is Map<String, Object?> && root[id] is Map<String, Object?>) {
        e = root[id]! as Map<String, Object?>;
      }
    } on Object {
      // без файла — только заголовок и значение
    }
    String fill_(Object? t) => heroText(
        (t is String ? t : '')
            .replaceAll('{value}', value)
            .replaceAll('{max}', max),
        hero);
    final String title =
        e['title'] is String ? e['title']! as String : fallbackTitle;
    final String line = e['value'] is String ? fill_(e['value']) : value;
    final String text = <String>[
      if (reason != null && reason.isNotEmpty) heroText(reason, hero),
      fill_(e['text']),
      if (extra != null && extra.isNotEmpty) heroText(extra, hero),
    ].where((String t) => t.isNotEmpty).join('\n\n');
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        key: ValueKey<String>('hud:explain:$id'),
        titlePadding: WorldDialogTitle.padding,
        title: WorldDialogTitle(PicText(title)),
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

  /// [satiety] — сытость 0–100, когда она в HUD второй полоской под силами
  /// (вариант B HUD дня): подсказка говорит, что это за полоска.
  static void hintEnergy(BuildContext context,
          {double? energy, int? satiety}) =>
      explain(context, 'energy',
          extra: satiety == null
              ? null
              : 'Нижняя полоска — сытость: $satiety из 100. Еда её наполняет; '
                  'голодному Финни утром сил меньше.',
          value: energy == null ? '' : energyText(energy),
          max: energyText(energyMaxIn(context)),
          fill: energy == null ? null : energy / energyMaxIn(context),
          color: WorldColors.energy,
          fallbackTitle: 'Силы');

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
    final double top = energyMaxIn(context);
    final DayView day = DayView.of(s);
    final Widget coins = _Pill(
      key: const ValueKey<String>('hud:coins'),
      icon: Pic.coin,
      iconColor: WorldColors.gold,
      value: '${s.available}',
      word: 'монеты',
      semantic: 'Монет можно тратить: ${s.available}',
      onTap: () => hintCoins(context, coins: s.available),
    );
    // Копилки в HUD нет (Денис 29.09): её сумма — над копилкой в комнате и
    // в плане недели.
    final Widget energyPill = _Pill(
      key: const ValueKey<String>('hud:energy'),
      icon: Pic.bolt,
      iconColor: WorldColors.energy,
      fill: (s.energy / top).clamp(0.0, 1.0),
      color: WorldColors.energy,
      value: energy,
      word: 'силы',
      semantic: 'Сил: $energy из ${energyText(top)}',
      onTap: () => hintEnergy(context, energy: s.energy),
    );
    // Сдвиг настроения «+2 / −3» на 3 с — виден на итоге смены (7 дней).
    final Widget mood = HudDelta(
      value: s.happiness,
      deltaKey: 'hud:happiness:delta',
      child: _Pill(
        key: const ValueKey<String>('hud:happiness'),
        icon: Pic.smile,
        iconColor: WorldColors.mood,
        fill: (s.happiness / 100).clamp(0.0, 1.0),
        color: WorldColors.mood,
        value: '${s.happiness}',
        word: 'настроение',
        semantic: 'Настроение: ${s.happiness} из 100',
        onTap: () => hintMood(context, mood: s.happiness),
      ),
    );
    // Стиль Алины (спека §2.7, шаг 5): одна строка без плашки поверх
    // затемнённого фона — монеты · силы · настроение · день. У показателей
    // свои тела r10 (её «пилюли-счётчики», радиус из шкалы, не полный
    // круг), у сил и настроения — доля полосой по низу тела. Как строка
    // комнаты (alina-01): кегль HUD не растёт со шрифтом системы, иначе на
    // 360 dp при ×1,3 слово «настроение» ужималось бы ниже 14; TalkBack
    // читает подписи целиком. Портрет и альбомная — одна раскладка высотой
    // [landscapeHeight]: прежний портрет в две строки занимал 104 dp.
    return NoLargerText(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: landscapeHeight - 4),
          child: Row(
            children: <Widget>[
              Expanded(flex: 4, child: coins),
              const SizedBox(width: Gap.xs),
              Expanded(flex: 4, child: energyPill),
              const SizedBox(width: Gap.xs),
              Expanded(flex: 5, child: mood),
              if (day.on) ...<Widget>[
                const SizedBox(width: Gap.sm),
                Semantics(
                  label: 'День ${day.day} из ${day.days}',
                  excludeSemantics: true,
                  child: Text(
                    'День ${day.day}\nиз ${day.days}',
                    key: const ValueKey<String>('hud:day'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: WorldColors.goldText,
                      shadows: HudStrip.textShadow,
                    ),
                  ),
                ),
              ],
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Показатель HUD в её форме: тело r10 (`.meter-body`), значок и число в
/// строку, слово под ними (≥ 14 sp, разбор финала 15.10 — не одни значки
/// и числа); [fill] — доля полосой по низу тела. Касание — всё тело
/// (≥ 48 dp); при нехватке ширины содержимое ужимается, а не режется.
class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.word,
    required this.semantic,
    required this.onTap,
    this.fill,
    this.color = WorldColors.gold,
  });

  final Pic icon;
  final Color iconColor;
  final String value;
  final String word;
  final String semantic;
  final VoidCallback onTap;

  /// Доля 0..1 для полосы по низу; null — без полосы (монеты).
  final double? fill;
  final Color color;

  static const double _bar = 4;

  @override
  Widget build(BuildContext context) {
    // Слово — первым в дереве, число — последним (его читают тесты экранов
    // как текст показателя); на экране число сверху: столбец снизу вверх.
    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      verticalDirection: VerticalDirection.up,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(word,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
                fontSize: 14,
                height: 1.1,
                fontWeight: FontWeight.w600,
                color: WorldColors.textSoft,
                shadows: HudStrip.textShadow)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Pictogram(icon, size: 18, color: iconColor),
            const SizedBox(width: Gap.xs),
            Text(value,
                maxLines: 1,
                softWrap: false,
                style: AppType.number(18, color: WorldColors.text)),
          ],
        ),
      ],
    );
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      onTap:
          onTap, // иначе excludeSemantics отсекает касание: TalkBack не нажмёт
      child: Material(
        color: WorldColors.surface,
        borderRadius: BorderRadius.circular(WorldRadii.tile),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Gap.sm, Gap.xs, Gap.xs, Gap.xs + _bar),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: content,
                    ),
                  ),
                ),
                if (fill case final double f)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: _bar,
                    child: ColoredBox(
                      color: WorldColors.raised,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: f,
                        child: ColoredBox(color: color),
                      ),
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
