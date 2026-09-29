import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/world_theme.dart';
import 'pic_text.dart';
import 'world_routes.dart';

/// Подсказка «Что здесь?» (ТЗ 2.5.1.3) — одна на все экраны мира.
///
/// Внизу — «Словарик» (ТЗ 2.5.11.2): из любой подсказки один тап до
/// объяснения слов «бюджет», «конверт», «подушка безопасности».
void showHelp(BuildContext context, String title, String text) {
  showDialog<void>(
    context: context,
    builder: (BuildContext c) => AlertDialog(
      title: Text(title),
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

/// Кнопка «?» в шапке экрана мира. Ключ — `<id>:help`.
class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Что здесь?',
        onPressed: onPressed,
        icon: const Text('?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      );
}
