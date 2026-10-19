import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/world_theme.dart';

/// Строка мира, в которой значки ресурсов (💰 ⚡ 😊 🐷 ⭐ 📈 📅 …) и значки
/// строк итогов и прогресса (🏠 ➡️ 🏁 🎉 🙂 💬 ✅ ⏳ ⚠️), наград (🏆 🔒)
/// нарисованы вектором, а не эмодзи.
///
/// Мир отдаёт короткие строки вида «−2 ⚡ · +5 😊» (`EffectPreview.text`) —
/// их удобно сравнивать в тестах и читать в логах. На экране эмодзи
/// рисуется системным шрифтом: на Android 8 и в браузере по-разному, на
/// скриншотах бывает пустым (`docs/design-system.md` §5). [text] хранит
/// исходную строку; значки подставляются только при отрисовке.
class PicText extends StatelessWidget {
  const PicText(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// Значок и необязательный за ним U+FE0F («➡️», «⚠️»): селектор
  /// эмодзи-варианта уходит вместе со значком, а не остаётся в тексте.
  static final RegExp _marks =
      RegExp('(💰|⚡|😊|🐷|⭐|📈|📅|📊|🧾|🛍|❗|💼|🏠|➡|🏁|🎉|🙂|💬|✅|⏳|⚠|🏆|🔒)️?');

  /// Значок, его цвет и слово для TalkBack. Пустое слово — рядом со значком
  /// в тексте и так стоит его слово («📊 Потом сверяем план…»).
  static (Pic, Color, String) _of(String mark) => switch (mark) {
        '💰' => (Pic.coin, WorldColors.gold, 'монет'),
        '⚡' => (Pic.bolt, WorldColors.energy, 'сил'),
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
        // Награды: у полученной рядом строка «Получено…» — слово не нужно;
        // у закрытой только прогресс — TalkBack говорит, что она закрыта.
        '🏆' => (Pic.trophy, WorldColors.gold, ''),
        '🔒' => (Pic.lock, WorldColors.textSoft, 'не получено'),
        _ => (Pic.star, WorldColors.gold, 'звёзд'),
      };

  /// Та же строка словами — для TalkBack. Слово значка не звучит, если то
  /// же слово стоит в трёх словах от него («🐷 В копилке», «Своих монет
  /// было 420 💰»): иначе TalkBack читает «копилка В копилке».
  String get spoken => text
      .replaceAllMapped(_marks, (Match m) {
        final String word = _of(m.group(1)!).$3;
        if (word.isEmpty) return '';
        final String first = word.split(' ').first;
        final String stem = first.length > 6 ? first.substring(0, 6) : first;
        bool near(Iterable<String> words) =>
            words.take(3).any((String w) => w.toLowerCase().contains(stem));
        final List<String> before = _words(text.substring(0, m.start));
        return near(before.reversed) || near(_words(text.substring(m.end)))
            ? ''
            : word;
      })
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();

  static List<String> _words(String s) =>
      s.split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).toList();

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
      child: Text.rich(TextSpan(children: spans),
          style: style, textAlign: textAlign),
    );
  }
}
