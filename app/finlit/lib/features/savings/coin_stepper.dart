import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Выбор количества кнопками −1 / +1.
///
/// 🔴 Клавиатуры здесь нет намеренно. Семилетка вводит «10» как «1» и «0»
/// в разных полях, промахивается мимо цифр системной клавиатуры и не может
/// стереть ошибку; §3.6.3 требует крупных целей нажатия, а не мелкой цифровой
/// раскладки. Две кнопки по 64 dp дают то же число без единого способа
/// ввести недопустимое значение — диапазон ограничен [min]..[max].
///
/// Живёт в features/savings, потому что core/widgets.dart в этом спринте
/// пишет другой человек; по смыслу это общий элемент и его место там.
class CoinStepper extends StatelessWidget {
  const CoinStepper({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    this.min = 0,
    this.unit,
  });

  /// Чем управляет этот счётчик: подставляется в подсказки кнопок,
  /// чтобы на экране с тремя конвертами кнопки различались на слух.
  final String label;

  final int value;
  final int min;
  final int max;

  /// Единица измерения рядом с числом. По умолчанию — «монетки».
  final String? unit;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final String word = unit ?? Coins.word(value);
    return Row(
      children: <Widget>[
        _StepButton(
          icon: Pic.minus,
          tooltip: '$label: меньше на одну',
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Expanded(
          child: Semantics(
            label: '$label: $value $word',
            excludeSemantics: true,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text('$value',
                        style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink)),
                    const SizedBox(width: Gap.xs),
                    Text(word,
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.inkSoft)),
                  ],
                ),
              ),
            ),
          ),
        ),
        _StepButton(
          icon: Pic.plus,
          tooltip: '$label: больше на одну',
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Pic icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // §3.6.3 рекомендует 48 dp, проект держит 56 как минимум; у главных
    // игровых кнопок — 64, потому что по ним бьют десятки раз подряд.
    return SizedBox(
      width: TapSize.primary,
      height: TapSize.primary,
      // 🔴 Не `IconButton.filledTonal`. Он берёт заливку из тональной схемы
      // Material — у нашей палитры это насыщенный сине-фиолетовый, — а
      // `Pictogram` рисует знак своим пером и про эту заливку не знает.
      // На экране получался тёмный минус на тёмном круге: прочитать нельзя,
      // и ни на что не похоже на соседнем экране плана, где степперы —
      // светлые плашки с цветной рамкой. Здесь ровно такие же.
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 30,
        style: IconButton.styleFrom(
          backgroundColor:
              onPressed == null ? AppColors.surface : AppColors.savingsBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.button),
            side: BorderSide(
              color: onPressed == null ? AppColors.line : AppColors.savings,
              width: 2,
            ),
          ),
        ),
        // Перо тоже гаснет: недоступная кнопка не должна выглядеть рабочей.
        icon: Pictogram(
          icon,
          size: 30,
          color: onPressed == null ? AppColors.inkSoft : AppColors.savings,
        ),
      ),
    );
  }
}
