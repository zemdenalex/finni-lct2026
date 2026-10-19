import 'package:flutter/material.dart';

import '../../../core/build_info.dart';
import '../shop/shop_kit.dart';

/// Номер сборки — служебная строка для взрослого и команды (кэш веб-демо уже
/// выдавал старую сборку). Правило текстов 8 (Настя): ребёнку не показываем,
/// поэтому виджет живёт среди экранов взрослого. Ставится в раздел
/// «Взрослым», а при скрытом разделе (`adult.section` false, DEN-27) — в
/// блок «Игра заново и проверка» внизу настроек (finni 18.10: иначе номера
/// сборки не видно нигде).
class BuildLine extends StatelessWidget {
  const BuildLine({super.key});

  static const String text = 'Сборка $buildSha';

  @override
  Widget build(BuildContext context) => const Text(text, style: kitSoft);
}
