import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/world_theme.dart';
import 'pic_text.dart';
import 'world_routes.dart';

/// Шапка окна мира в её раскладке (спека §2.7 «Окно», шаг 6): заголовок
/// слева, крестик 48 dp справа (у неё 32 — меньше пальца). Заголовок —
/// `header` для TalkBack, крестик — «Закрыть».
class WorldDialogTitle extends StatelessWidget {
  const WorldDialogTitle(this.title, {super.key});

  final Widget title;

  /// Поле шапки: крестик прижат к правому краю окна.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(22, 14, 8, 0);

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(header: true, child: title),
            ),
          ),
          IconButton(
            key: const ValueKey<String>('dialog:close'),
            tooltip: 'Закрыть',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, color: WorldColors.textSoft),
          ),
        ],
      );
}

/// Подсказка «Что здесь?» (ТЗ 2.5.1.3) — одна на все экраны мира.
///
/// Внизу — «Словарик» (ТЗ 2.5.11.2): из любой подсказки один тап до
/// объяснения слов «бюджет», «конверт», «подушка безопасности».
void showHelp(BuildContext context, String title, String text) {
  showDialog<void>(
    context: context,
    builder: (BuildContext c) => AlertDialog(
      titlePadding: WorldDialogTitle.padding,
      title: WorldDialogTitle(Text(title)),
      // Значки в тексте подсказки — те же векторные, что на экране.
      content: SingleChildScrollView(
        child: PicText(text,
            style: const TextStyle(
                fontSize: 18, height: 1.3, color: WorldColors.text)),
      ),
      actions: <Widget>[
        TextButton.icon(
          key: const ValueKey<String>('help:glossary'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () {
            Navigator.of(c).pop();
            Navigator.of(context).pushNamed(WorldRoutes.glossary);
          },
          icon: const Pictogram(Pic.dictionary,
              size: 22, color: WorldColors.gold),
          label: const Text('Словарик'),
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(c).pop(),
          child: const Text('Понятно'),
        ),
      ],
    ),
  );
}

/// Кнопка «?» в шапке экрана мира. Ключ — `<id>:help`. [tooltip] — подпись
/// для TalkBack и долгого нажатия: у «?» рядом с числом — о чём подсказка.
class HelpButton extends StatelessWidget {
  const HelpButton(
      {super.key, required this.onPressed, this.tooltip = 'Что здесь?'});

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: const Text('?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      );
}
