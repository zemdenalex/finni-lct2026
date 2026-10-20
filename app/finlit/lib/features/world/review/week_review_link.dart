import 'package:flutter/material.dart';

import '../world_routes.dart';

/// Кнопка «Посмотреть» на плашке «Неделя кончилась» (Настя 20.10): плашка
/// раньше только говорила «посмотри итоги дома», а дойти до них можно было
/// лишь через город и комнату. Касание открывает итоги недели (S11) сразу;
/// оттуда «Новая неделя» сама ведёт в комнату.
///
/// 48 dp по высоте — минимум ТЗ для касания.
class WeekReviewLink extends StatelessWidget {
  const WeekReviewLink({super.key});

  /// Слово на кнопке — одно, детское.
  static const String label = 'Посмотреть';

  @override
  Widget build(BuildContext context) => FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: () => Navigator.of(context).pushNamed(WorldRoutes.review),
        // TalkBack: «Посмотреть итоги недели», а не одно «Посмотреть».
        child: const Text(label, semanticsLabel: 'Посмотреть итоги недели'),
      );
}
