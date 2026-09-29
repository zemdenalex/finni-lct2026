import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/world_theme.dart';

/// Строка мира, в которой значки ресурсов (💰 ⚡ 😊 🐷 ⭐ 📈 📅 …) и значки
/// строк итогов и прогресса (🏠 ➡️ 🏁 🎉 🙂 💬 ✅ ⏳ ⚠️) нарисованы вектором,
/// а не эмодзи.
///
/// Мир отдаёт короткие строки вида «−2 ⚡ · +5 😊» (`EffectPreview.text`) —
/// их удобно сравнивать в тестах и читать в логах. На экране эмодзи
/// рисуется системным шрифтом: на Android 8 и в браузере по-разному, на
/// скриншотах бывает пустым (`docs/design-system.md` §5). [text] хранит
/// исходную строку; значки подставляются только при отрисовке.
class PicText extends StatelessWidget {
  const PicText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  /// Значок и необязательный за ним U+FE0F («➡️», «⚠️»): селектор
  /// эмодзи-варианта уходит вместе со значком, а не остаётся в тексте.
  static final RegExp _marks =
      RegExp('(💰|⚡|😊|🐷|⭐|📈|📅|📊|🧾|🛍|❗|💼|🏠|➡|🏁|🎉|🙂|💬|✅|⏳|⚠)️?');

  /// Значок, его цвет и слово для TalkBack. Пустое слово — рядом со значком
  /// в тексте и так стоит его слово («📊 Потом сверяем план…»).
  static (Pic, Color, String) _of(String mark) => switch (mark) {
        '💰' => (Pic.coin, WorldColors.gold, 'монет'),
        '⚡' => (Pic.spark, WorldColors.energy, 'энергии'),
        '😊' => (Pic.smile, WorldColors.mood, 'настроения'),
        '🐷' => (Pic.jar, WorldColors.needs, 'копилка'),
        '📈' => (Pic.chart, WorldColors.textSoft, 'опыт'),
        '📅' => (Pic.week, WorldColors.textSoft, 'смен на неделе'),
        '📊' => (Pic.chart, WorldColors.textSoft, ''),
        '🧾' => (Pic.list, WorldColors.textSoft, ''),
        '🛍' => (Pic.shop, WorldColors.textSoft, ''),
        '❗' => (Pic.info, WorldColors.danger, ''),
        '💼' => (Pic.task, WorldColors.textSoft, ''),
        '🏠' => (Pic.house, WorldColors.textSoft, ''),
        '➡' => (Pic.arrowRight, WorldColors.textSoft, ''),
        '🏁' => (Pic.flag, WorldColors.gold, ''),
        '🎉' => (Pic.trophy, WorldColors.gold, ''),
        '🙂' => (Pic.smile, WorldColors.mood, ''),
        '💬' => (Pic.speech, WorldColors.textSoft, ''),
        '✅' => (Pic.check, WorldColors.needs, ''),
        '⏳' => (Pic.clock, WorldColors.textSoft, ''),
        '⚠' => (Pic.info, WorldColors.danger, ''),
        _ => (Pic.star, WorldColors.gold, 'звёзд'),
      };

  /// Та же строка словами — для TalkBack.
  String get spoken =>
      text.replaceAllMapped(_marks, (Match m) => _of(m.group(1)!).$3).trim();

  @override
  Widget build(BuildContext context) {
    final TextStyle base = DefaultTextStyle.of(context).style.merge(style);
    final double size = (base.fontSize ?? 16) * 1.1;
    final List<InlineSpan> spans = <InlineSpan>[];
    int at = 0;
    for (final Match m in _marks.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      final (Pic pic, Color color, String _) = _of(m.group(1)!);
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Pictogram(pic, size: size, color: color),
      ));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Text.rich(TextSpan(children: spans), style: style),
    );
  }
}
