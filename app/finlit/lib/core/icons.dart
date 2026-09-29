import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Пиктограммы приложения. Рисуются кодом, одним пером.
///
/// 🔴 Почему не системный набор Material. Иконки Material спроектированы
/// для рабочих приложений: шестерёнка настроек, корзина, «три точки». В детском
/// продукте они читаются как административная панель — это первое, по чему
/// дизайнер за секунду отличает сборку на значениях по умолчанию от сделанной
/// вещи. Собственный набор — самая заметная и самая дешёвая правка этого.
///
/// Заодно закрывается §3.3 ТЗ про права на изображения: рисовали сами.
///
/// Язык: поле 24 × 24, перо толщиной 9 % от размера, круглые концы и стыки.
/// Заливка применяется там, где форма должна читаться на мелком размере
/// (монетка, конверт), контур — там, где важен силуэт.
enum Pic {
  // Еда и уход
  bowl, drop, apple, bath,
  // Хочу
  sticker, ball, book, hat, cake,
  // Деньги
  coin, envelope, jar,
  // Цели
  paw, house, scooter, gift,
  // Навигация и состояния
  task, chart, dictionary, family, sliders, question,
  check, cross, plus, minus, clock, week, heart, spark,
  // Стрелки и раскрытие
  arrowRight, arrowDown, caretUp, caretDown,
  // Действия с деньгами и вещами
  swap, undo, history, basket, shop,
  // Доступ и правка
  lock, lockOpen, trash, pencil,
  // Звук и движение
  sound, soundOff, speak, speakOff, motion, play,
  // Разделы
  flask, school, speech,
  // Смыслы денег
  umbrella, leaf, trophy, star, smile, flag, wallet, calc, list,
  // Маркеры и пояснения
  circleEmpty, info, bulb, hand, external,
  // Мир: выход в город и сон
  city, moon,
}

class Pictogram extends StatelessWidget {
  const Pictogram(
    this.pic, {
    super.key,
    this.size = 24,
    required this.color,
    this.accent,
    this.semanticLabel,
  });

  final Pic pic;
  final double size;
  final Color color;

  /// Второй цвет для заливок. По умолчанию — основной с малой непрозрачностью.
  final Color? accent;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget art = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PicPainter(
          pic: pic,
          color: color,
          accent: accent ?? color.withValues(alpha: 0.18),
        ),
      ),
    );
    if (semanticLabel == null) {
      return ExcludeSemantics(child: art);
    }
    return Semantics(label: semanticLabel, excludeSemantics: true, child: art);
  }
}

class _PicPainter extends CustomPainter {
  _PicPainter({required this.pic, required this.color, required this.accent});

  final Pic pic;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide;
    final double u = s / 24; // единица поля
    final Paint line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint fill = Paint()..color = color;
    final Paint soft = Paint()..color = accent;
    // Волосяная линия для деталей внутри формы: рёбра корзины, прожилки
    // листа, пузырьки в колбе. Тем же пером они забивают силуэт на 20 px.
    final Paint thin = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Offset p(double x, double y) => Offset(x * u, y * u);
    Rect r(double x, double y, double w, double h) =>
        Rect.fromLTWH(x * u, y * u, w * u, h * u);

    switch (pic) {
      // ─────────────────────────── еда и уход ───────────────────────────
      case Pic.bowl:
        // Миска: чаша, ободок и две струйки пара.
        final Path bowl = Path()
          ..moveTo(3 * u, 12 * u)
          ..lineTo(21 * u, 12 * u)
          ..arcToPoint(p(3, 12),
              radius: Radius.circular(9 * u), clockwise: true);
        canvas.drawPath(bowl, soft);
        canvas.drawLine(p(2, 12), p(22, 12), line);
        canvas.drawArc(r(3, 3, 18, 18), 0, math.pi, false, line);
        for (final double dx in <double>[9, 15]) {
          final Path steam = Path()
            ..moveTo(dx * u, 8.5 * u)
            ..quadraticBezierTo(
                (dx + 1.6) * u, 6.5 * u, dx * u, 4.5 * u);
          canvas.drawPath(steam, line);
        }

      case Pic.drop:
        final Path drop = Path()
          ..moveTo(12 * u, 3 * u)
          ..quadraticBezierTo(20 * u, 12 * u, 18 * u, 16 * u)
          ..arcToPoint(p(6, 16), radius: Radius.circular(6.4 * u))
          ..quadraticBezierTo(4 * u, 12 * u, 12 * u, 3 * u)
          ..close();
        canvas.drawPath(drop, soft);
        canvas.drawPath(drop, line);
        canvas.drawArc(r(8, 12, 4, 5), math.pi * 0.7, math.pi * 0.7, false,
            line..strokeWidth = s * 0.06);

      case Pic.apple:
        final Paint l2 = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.09
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final Path body = Path()
          ..moveTo(12 * u, 8 * u)
          ..cubicTo(8 * u, 5 * u, 3 * u, 8 * u, 4 * u, 14 * u)
          ..cubicTo(5 * u, 19 * u, 9 * u, 21 * u, 12 * u, 19.2 * u)
          ..cubicTo(15 * u, 21 * u, 19 * u, 19 * u, 20 * u, 14 * u)
          ..cubicTo(21 * u, 8 * u, 16 * u, 5 * u, 12 * u, 8 * u)
          ..close();
        canvas.drawPath(body, soft);
        canvas.drawPath(body, l2);
        canvas.drawLine(p(12, 8), p(12, 4.5), l2);
        final Path leaf = Path()
          ..moveTo(12 * u, 5.5 * u)
          ..quadraticBezierTo(16.5 * u, 3 * u, 17.5 * u, 6 * u)
          ..quadraticBezierTo(14 * u, 8 * u, 12 * u, 5.5 * u)
          ..close();
        canvas.drawPath(leaf, fill);

      case Pic.bath:
        // Кран и ножки обязательны: без них ванна читается как миска.
        canvas.drawPath(
          Path()
            ..moveTo(4.2 * u, 11.5 * u)
            ..lineTo(4.2 * u, 6 * u)
            ..quadraticBezierTo(4.2 * u, 4.2 * u, 6 * u, 4.2 * u)
            ..lineTo(7.6 * u, 4.2 * u),
          line,
        );
        canvas.drawRRect(
          RRect.fromRectAndCorners(r(2.4, 11.5, 19.2, 6.4),
              bottomLeft: Radius.circular(3 * u),
              bottomRight: Radius.circular(3 * u)),
          soft,
        );
        canvas.drawPath(
          Path()
            ..moveTo(1.6 * u, 11.5 * u)
            ..lineTo(22.4 * u, 11.5 * u)
            ..lineTo(22.4 * u, 14.6 * u)
            ..quadraticBezierTo(22.4 * u, 17.9 * u, 19.1 * u, 17.9 * u)
            ..lineTo(4.9 * u, 17.9 * u)
            ..quadraticBezierTo(1.6 * u, 17.9 * u, 1.6 * u, 14.6 * u)
            ..close(),
          line,
        );
        canvas.drawLine(p(5.6, 17.9), p(5.6, 20.6), line);
        canvas.drawLine(p(18.4, 17.9), p(18.4, 20.6), line);
        canvas.drawCircle(p(10.5, 8), 1.7 * u, line);
        canvas.drawCircle(p(14.6, 6.2), 1.1 * u, line);

      // ──────────────────────────────  хочу  ──────────────────────────────
      case Pic.sticker:
        // Ободок по контуру — то, чем наклейка отличается от звезды-оценки:
        // высечка по краю. Без него две пиктограммы читаются одинаково.
        final Path star = _star(p(12, 11.5), 8.8 * u, 3.8 * u, 5);
        canvas.drawPath(star, soft);
        canvas.drawPath(star, line);
        canvas.drawPath(_star(p(12, 11.5), 6.2 * u, 2.7 * u, 5), thin);

      case Pic.ball:
        // 🔴 Простой шар с бликом и одним швом. Сложные узоры здесь уже
        // пробовались трижды и каждый раз давали чужой предмет: футбольный
        // пятиугольник со швами — автомобильный диск, меридианы с пояском —
        // глобус, тёмные дольки по краю — глаз. Объём читается бликом, а от
        // пустого кружка Pic.circleEmpty шар отличается заливкой.
        canvas.drawCircle(p(12, 12), 8.6 * u, soft);
        canvas.drawCircle(p(12, 12), 8.6 * u, line);
        // 🔴 Полоса поперёк — две прямые хорды, как у мячика в комнате
        // Финни. Дуга-шов с бликом над ней читалась грустным лицом:
        // «Хочу» было подписано хмурой мордочкой.
        canvas.drawLine(p(3.9, 10.2), p(20.1, 10.2), thin);
        canvas.drawLine(p(3.9, 13.8), p(20.1, 13.8), thin);

      case Pic.book:
        canvas.drawPath(
          Path()
            ..moveTo(12 * u, 6.5 * u)
            ..quadraticBezierTo(8 * u, 4 * u, 3.5 * u, 5.5 * u)
            ..lineTo(3.5 * u, 18 * u)
            ..quadraticBezierTo(8 * u, 16.5 * u, 12 * u, 19 * u)
            ..quadraticBezierTo(16 * u, 16.5 * u, 20.5 * u, 18 * u)
            ..lineTo(20.5 * u, 5.5 * u)
            ..quadraticBezierTo(16 * u, 4 * u, 12 * u, 6.5 * u)
            ..close(),
          soft,
        );
        canvas.drawPath(
          Path()
            ..moveTo(12 * u, 6.5 * u)
            ..quadraticBezierTo(8 * u, 4 * u, 3.5 * u, 5.5 * u)
            ..lineTo(3.5 * u, 18 * u)
            ..quadraticBezierTo(8 * u, 16.5 * u, 12 * u, 19 * u)
            ..quadraticBezierTo(16 * u, 16.5 * u, 20.5 * u, 18 * u)
            ..lineTo(20.5 * u, 5.5 * u)
            ..quadraticBezierTo(16 * u, 4 * u, 12 * u, 6.5 * u)
            ..close(),
          line,
        );
        canvas.drawLine(p(12, 6.5), p(12, 19), line);

      case Pic.hat:
        // Помпон отделён зазором, отворот с рёбрами — иначе колпак для блюд.
        canvas.drawCircle(p(12, 3.4), 2.1 * u, fill);
        canvas.drawLine(p(12, 5.5), p(12, 7.4), line);
        canvas.drawPath(
          Path()
            ..addArc(r(4.4, 7.2, 15.2, 15.2), math.pi, math.pi)
            ..close(),
          soft,
        );
        canvas.drawArc(r(4.4, 7.2, 15.2, 15.2), math.pi, math.pi, false, line);
        final RRect cuff = RRect.fromRectAndRadius(
            r(3, 14.4, 18, 4.6), Radius.circular(2.3 * u));
        canvas.drawRRect(cuff, Paint()..color = accent);
        canvas.drawRRect(cuff, line);
        for (int i = 0; i < 4; i++) {
          canvas.drawLine(p(6.6 + i * 3.6, 15.4), p(6.6 + i * 3.6, 18),
              Paint()
                ..color = color
                ..strokeWidth = s * 0.05
                ..strokeCap = StrokeCap.round);
        }

      case Pic.cake:
        // 🔴 Два яруса: широкий низ и узкий верх со свечой. Один ярус
        // с волной глазури читался лотком со стрелкой «скачать».
        final RRect low = RRect.fromRectAndRadius(
            r(3.4, 13.2, 17.2, 6.2), Radius.circular(1.6 * u));
        final RRect top = RRect.fromRectAndRadius(
            r(6.6, 8.4, 10.8, 4.8), Radius.circular(1.4 * u));
        for (final RRect tier in <RRect>[low, top]) {
          canvas.drawRRect(tier, soft);
          canvas.drawRRect(tier, line);
        }
        // Капли глазури по краю нижнего яруса.
        canvas.drawPath(
          Path()
            ..moveTo(3.6 * u, 15.6 * u)
            ..quadraticBezierTo(6.3 * u, 17.4 * u, 9 * u, 15.6 * u)
            ..quadraticBezierTo(12 * u, 17.4 * u, 15 * u, 15.6 * u)
            ..quadraticBezierTo(17.7 * u, 17.4 * u, 20.4 * u, 15.6 * u),
          thin,
        );
        canvas.drawLine(p(12, 4.8), p(12, 8.4), line);
        final Path flame = Path()
          ..moveTo(12 * u, 1.4 * u)
          ..quadraticBezierTo(14.2 * u, 3.4 * u, 12 * u, 4.8 * u)
          ..quadraticBezierTo(9.8 * u, 3.4 * u, 12 * u, 1.4 * u)
          ..close();
        canvas.drawPath(flame, fill);

      // ───────────────────────────── деньги ─────────────────────────────
      case Pic.coin:
        // 🔴 На монете должен быть знак рубля. Без него круг с ободком
        // читался как объектив или пуговица: «монетность» несёт не форма,
        // а номинал. На 20 px знак сливается в пятно, но силуэт с плотной
        // серединой всё равно отличается от пустого кружка Pic.circleEmpty.
        canvas.drawCircle(p(12, 12), 9 * u, soft);
        canvas.drawCircle(p(12, 12), 9 * u, line);

        final Paint mark = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.085
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        // Стойка знака ₽.
        canvas.drawLine(p(10.2, 7.4), p(10.2, 16.8), mark);
        // Чаша.
        canvas.drawPath(
          Path()
            ..moveTo(10.2 * u, 7.4 * u)
            ..lineTo(13.2 * u, 7.4 * u)
            ..cubicTo(15.6 * u, 7.4 * u, 15.6 * u, 12.2 * u, 13.2 * u, 12.2 * u)
            ..lineTo(10.2 * u, 12.2 * u),
          mark,
        );
        // Перечёркивание — то, что отличает ₽ от латинской P.
        canvas.drawLine(p(8.2, 14.4), p(13.4, 14.4), mark);

      case Pic.envelope:
        // Конверт с клапаном — буквальная форма, а не «карточка со скруглением».
        final RRect body = RRect.fromRectAndRadius(
            r(2.5, 6, 19, 13), Radius.circular(2 * u));
        canvas.drawRRect(body, soft);
        canvas.drawRRect(body, line);
        canvas.drawPath(
          Path()
            ..moveTo(2.5 * u, 7.6 * u)
            ..lineTo(12 * u, 14 * u)
            ..lineTo(21.5 * u, 7.6 * u),
          line,
        );

      case Pic.jar:
        // 🔴 Стеклянная банка, а не сундучок. Прошлая версия — скруглённый
        // прямоугольник с кружком сверху — на листе читалась как ЗАМОК, и
        // стояла в одном интерфейсе с настоящим Pic.lock. Конверт «Копилка»
        // при этом выглядел запертым. Теперь силуэт узнаётся по трём вещам:
        // крышка шире тулова, плечики сужаются, внутри видно монетки.
        final Path body = Path()
          ..moveTo(6.2 * u, 9.6 * u)
          ..cubicTo(6.2 * u, 8.2 * u, 8.0 * u, 7.8 * u, 8.0 * u, 6.6 * u)
          ..lineTo(16.0 * u, 6.6 * u)
          ..cubicTo(16.0 * u, 7.8 * u, 17.8 * u, 8.2 * u, 17.8 * u, 9.6 * u)
          ..lineTo(17.8 * u, 18.2 * u)
          ..quadraticBezierTo(17.8 * u, 20.4 * u, 15.6 * u, 20.4 * u)
          ..lineTo(8.4 * u, 20.4 * u)
          ..quadraticBezierTo(6.2 * u, 20.4 * u, 6.2 * u, 18.2 * u)
          ..close();
        canvas.drawPath(body, soft);
        canvas.drawPath(body, line);
        // Крышка — шире плечиков, поэтому банку ни с чем не спутать.
        canvas.drawRRect(
          RRect.fromRectAndRadius(r(6.6, 3.0, 10.8, 3.6), Radius.circular(1.2 * u)),
          fill,
        );
        // Прорезь для монетки.
        canvas.drawLine(
          p(10.0, 4.8),
          p(14.0, 4.8),
          Paint()
            ..color = soft.color
            ..strokeWidth = s * 0.075
            ..strokeCap = StrokeCap.round,
        );
        // Монетки внутри: копилка не пустая — это и есть смысл конверта.
        canvas.drawCircle(p(10.3, 16.4), 2.0 * u, fill);
        canvas.drawCircle(p(14.0, 17.4), 1.7 * u, fill);

      // ────────────────────────────── цели ──────────────────────────────
      case Pic.paw:
        canvas.drawOval(r(7.5, 10.5, 9, 8), soft);
        canvas.drawOval(r(7.5, 10.5, 9, 8), line);
        for (final List<double> t in <List<double>>[
          <double>[5.5, 7.5, 3, 4],
          <double>[9.8, 4.6, 3, 4.2],
          <double>[14.2, 4.6, 3, 4.2],
          <double>[18, 7.5, 3, 4],
        ]) {
          canvas.drawOval(r(t[0] - 1.5, t[1] - 2, t[2], t[3]), fill);
        }

      case Pic.house:
        canvas.drawPath(
          Path()
            ..moveTo(12 * u, 3.5 * u)
            ..lineTo(21 * u, 11 * u)
            ..lineTo(21 * u, 20 * u)
            ..lineTo(3 * u, 20 * u)
            ..lineTo(3 * u, 11 * u)
            ..close(),
          soft,
        );
        canvas.drawPath(
          Path()
            ..moveTo(2 * u, 11.6 * u)
            ..lineTo(12 * u, 3.4 * u)
            ..lineTo(22 * u, 11.6 * u),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(4.5 * u, 10.5 * u)
            ..lineTo(4.5 * u, 20 * u)
            ..lineTo(19.5 * u, 20 * u)
            ..lineTo(19.5 * u, 10.5 * u),
          line,
        );
        canvas.drawRRect(
          RRect.fromRectAndCorners(r(9.5, 14, 5, 6),
              topLeft: Radius.circular(2.5 * u),
              topRight: Radius.circular(2.5 * u)),
          line,
        );

      case Pic.scooter:
        canvas.drawCircle(p(6, 17.5), 3.2 * u, line);
        canvas.drawCircle(p(18.5, 17.5), 3.2 * u, line);
        canvas.drawPath(
          Path()
            ..moveTo(6 * u, 17.5 * u)
            ..lineTo(13 * u, 17.5 * u)
            ..lineTo(17 * u, 7 * u)
            ..lineTo(20 * u, 7 * u),
          line,
        );
        canvas.drawLine(p(17.6, 7), p(18.5, 14.3), line);

      case Pic.gift:
        canvas.drawRRect(
          RRect.fromRectAndRadius(r(3.5, 10, 17, 10), Radius.circular(2 * u)),
          soft,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(r(3.5, 10, 17, 10), Radius.circular(2 * u)),
          line,
        );
        canvas.drawLine(p(12, 10), p(12, 20), line);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r(2.5, 6.5, 19, 3.8), Radius.circular(1.5 * u)),
          line,
        );
        canvas.drawArc(r(6, 2.5, 6, 5.5), math.pi * 0.1, math.pi * 1.1, false, line);
        canvas.drawArc(r(12, 2.5, 6, 5.5), math.pi * 1.8, math.pi * 1.1, false, line);

      // ────────────────────── навигация и состояния ──────────────────────
      case Pic.task:
        canvas.drawRRect(
          RRect.fromRectAndRadius(r(4, 3, 16, 18), Radius.circular(2.4 * u)),
          soft,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(r(4, 3, 16, 18), Radius.circular(2.4 * u)),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(7.5 * u, 9.5 * u)
            ..lineTo(9.5 * u, 11.5 * u)
            ..lineTo(13 * u, 7.5 * u),
          line,
        );
        canvas.drawLine(p(7.5, 16), p(16.5, 16), line);

      case Pic.chart:
        canvas.drawLine(p(3.5, 20), p(20.5, 20), line);
        for (int i = 0; i < 3; i++) {
          final double h = 5.0 + i * 4.2;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                r(5.5 + i * 5.4, 20 - h, 3.8, h), Radius.circular(1.5 * u)),
            i == 2 ? fill : soft,
          );
          if (i != 2) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                  r(5.5 + i * 5.4, 20 - h, 3.8, h), Radius.circular(1.5 * u)),
              line,
            );
          }
        }

      case Pic.dictionary:
        canvas.drawRRect(
          RRect.fromRectAndRadius(r(3, 4, 18, 14), Radius.circular(4 * u)),
          soft,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(r(3, 4, 18, 14), Radius.circular(4 * u)),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(8.5 * u, 18 * u)
            ..lineTo(8.5 * u, 21.5 * u)
            ..lineTo(12.5 * u, 18 * u),
          line,
        );
        canvas.drawLine(p(7.5, 9), p(16.5, 9), line);
        canvas.drawLine(p(7.5, 13), p(13.5, 13), line);

      case Pic.family:
        canvas.drawCircle(p(8.5, 7.5), 3.2 * u, line);
        canvas.drawPath(
          Path()
            ..moveTo(3 * u, 20 * u)
            ..quadraticBezierTo(3 * u, 12.5 * u, 8.5 * u, 12.5 * u)
            ..quadraticBezierTo(14 * u, 12.5 * u, 14 * u, 20 * u),
          line,
        );
        canvas.drawCircle(p(17, 12), 2.3 * u, line);
        canvas.drawPath(
          Path()
            ..moveTo(13.2 * u, 20 * u)
            ..quadraticBezierTo(13.2 * u, 15.6 * u, 17 * u, 15.6 * u)
            ..quadraticBezierTo(20.8 * u, 15.6 * u, 20.8 * u, 20 * u),
          line,
        );

      case Pic.sliders:
        // Не шестерёнка: шестерёнка — знак офисного софта.
        for (int i = 0; i < 3; i++) {
          final double y = 6.5 + i * 5.5;
          canvas.drawLine(p(3.5, y), p(20.5, y), line);
          canvas.drawCircle(p(<double>[15, 8, 17][i], y), 2.6 * u,
              Paint()..color = accent);
          canvas.drawCircle(p(<double>[15, 8, 17][i], y), 2.6 * u, line);
        }

      case Pic.question:
        canvas.drawPath(
          Path()
            ..moveTo(4 * u, 4 * u)
            ..lineTo(20 * u, 4 * u)
            ..quadraticBezierTo(22 * u, 4 * u, 22 * u, 6 * u)
            ..lineTo(22 * u, 15 * u)
            ..quadraticBezierTo(22 * u, 17 * u, 20 * u, 17 * u)
            ..lineTo(11 * u, 17 * u)
            ..lineTo(6 * u, 21 * u)
            ..lineTo(6.6 * u, 17 * u)
            ..lineTo(4 * u, 17 * u)
            ..quadraticBezierTo(2 * u, 17 * u, 2 * u, 15 * u)
            ..lineTo(2 * u, 6 * u)
            ..quadraticBezierTo(2 * u, 4 * u, 4 * u, 4 * u)
            ..close(),
          line,
        );
        canvas.drawArc(r(9, 7, 6, 5.4), math.pi, math.pi * 1.5, false, line);
        canvas.drawLine(p(12, 11.4), p(12, 12.6), line);
        canvas.drawCircle(p(12, 14.4), s * 0.05, fill);

      case Pic.check:
        canvas.drawPath(
          Path()
            ..moveTo(4.5 * u, 12.5 * u)
            ..lineTo(9.8 * u, 17.6 * u)
            ..lineTo(19.5 * u, 6.8 * u),
          line..strokeWidth = s * 0.12,
        );

      case Pic.cross:
        canvas.drawLine(p(6, 6), p(18, 18), line..strokeWidth = s * 0.11);
        canvas.drawLine(p(18, 6), p(6, 18), line);

      case Pic.plus:
        canvas.drawLine(p(12, 5), p(12, 19), line..strokeWidth = s * 0.13);
        canvas.drawLine(p(5, 12), p(19, 12), line);

      case Pic.minus:
        canvas.drawLine(p(5, 12), p(19, 12), line..strokeWidth = s * 0.13);

      case Pic.clock:
        canvas.drawCircle(p(12, 12), 8.8 * u, soft);
        canvas.drawCircle(p(12, 12), 8.8 * u, line);
        canvas.drawPath(
          Path()
            ..moveTo(12 * u, 7 * u)
            ..lineTo(12 * u, 12.4 * u)
            ..lineTo(16 * u, 14.6 * u),
          line,
        );

      case Pic.week:
        canvas.drawRRect(
          RRect.fromRectAndRadius(r(3, 5, 18, 16), Radius.circular(2.6 * u)),
          soft,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(r(3, 5, 18, 16), Radius.circular(2.6 * u)),
          line,
        );
        canvas.drawLine(p(3, 10), p(21, 10), line);
        canvas.drawLine(p(8, 2.8), p(8, 6.4), line);
        canvas.drawLine(p(16, 2.8), p(16, 6.4), line);
        for (int i = 0; i < 3; i++) {
          canvas.drawCircle(p(7.5 + i * 4.5, 15), s * 0.055, fill);
        }

      case Pic.heart:
        final Path heart = Path()
          ..moveTo(12 * u, 20 * u)
          ..cubicTo(2 * u, 13.4 * u, 4 * u, 5 * u, 9 * u, 5 * u)
          ..cubicTo(11 * u, 5 * u, 12 * u, 6.6 * u, 12 * u, 7.6 * u)
          ..cubicTo(12 * u, 6.6 * u, 13 * u, 5 * u, 15 * u, 5 * u)
          ..cubicTo(20 * u, 5 * u, 22 * u, 13.4 * u, 12 * u, 20 * u)
          ..close();
        canvas.drawPath(heart, soft);
        canvas.drawPath(heart, line);

      case Pic.spark:
        for (final List<double> t in <List<double>>[
          <double>[12, 11, 6.4],
          <double>[19, 5.5, 2.8],
        ]) {
          canvas.drawPath(_spark(p(t[0], t[1]), t[2] * u), fill);
        }

      // ───────────────────── стрелки и раскрытие ─────────────────────
      case Pic.arrowRight:
        canvas.drawLine(p(4.2, 12), p(18, 12), line);
        canvas.drawPath(
          Path()
            ..moveTo(13.4 * u, 6.8 * u)
            ..lineTo(19.2 * u, 12 * u)
            ..lineTo(13.4 * u, 17.2 * u),
          line,
        );

      case Pic.arrowDown:
        // Нижняя черта — то место, куда кладут. Без неё стрелка означает
        // просто «вниз», а нужна «сюда».
        canvas.drawLine(p(12, 3.4), p(12, 14.4), line);
        canvas.drawPath(
          Path()
            ..moveTo(6.8 * u, 10.2 * u)
            ..lineTo(12 * u, 15.6 * u)
            ..lineTo(17.2 * u, 10.2 * u),
          line,
        );
        canvas.drawLine(p(5.6, 20.2), p(18.4, 20.2), line);

      case Pic.caretUp:
        canvas.drawPath(
          Path()
            ..moveTo(5.8 * u, 15.2 * u)
            ..lineTo(12 * u, 8.8 * u)
            ..lineTo(18.2 * u, 15.2 * u),
          line..strokeWidth = s * 0.11,
        );

      case Pic.caretDown:
        canvas.drawPath(
          Path()
            ..moveTo(5.8 * u, 8.8 * u)
            ..lineTo(12 * u, 15.2 * u)
            ..lineTo(18.2 * u, 8.8 * u),
          line..strokeWidth = s * 0.11,
        );

      // ────────────────── действия с деньгами и вещами ──────────────────
      case Pic.swap:
        // Две встречные стрелки: монетка ушла туда, монетка пришла сюда.
        canvas.drawLine(p(3.4, 8.6), p(18.2, 8.6), line);
        canvas.drawPath(
          Path()
            ..moveTo(14.6 * u, 5 * u)
            ..lineTo(19.4 * u, 8.6 * u)
            ..lineTo(14.6 * u, 12.2 * u),
          line,
        );
        canvas.drawLine(p(20.6, 15.4), p(5.8, 15.4), line);
        canvas.drawPath(
          Path()
            ..moveTo(9.4 * u, 11.8 * u)
            ..lineTo(4.6 * u, 15.4 * u)
            ..lineTo(9.4 * u, 19 * u),
          line,
        );

      case Pic.undo:
        // Дуга через верх и остриё, падающее влево-вниз: «вернуть как было».
        canvas.drawArc(
            r(4.6, 5.6, 14.8, 14.8), math.pi, math.pi * 1.24, false, line);
        canvas.drawPath(
          Path()
            ..moveTo(1.9 * u, 10.4 * u)
            ..lineTo(4.6 * u, 13.8 * u)
            ..lineTo(7.7 * u, 10.8 * u),
          line,
        );

      case Pic.history:
        // Чек с оторванным краем: лента причин, по которой читают неделю.
        // Часы сюда не годятся — они уже заняты сроком задания.
        // 🔴 Низ — мелкая пила во всю ширину. Две широкие волны, как было
        // сначала, дают вырез посередине, и чек читается закладкой.
        final Path tape = Path()
          ..moveTo(5.6 * u, 3.2 * u)
          ..lineTo(18.4 * u, 3.2 * u)
          ..lineTo(18.4 * u, 19 * u);
        for (int i = 0; i < 4; i++) {
          final double x0 = 18.4 - i * 3.2;
          tape
            ..lineTo((x0 - 1.6) * u, 21 * u)
            ..lineTo((x0 - 3.2) * u, 19 * u);
        }
        tape.close();
        canvas.drawPath(tape, soft);
        canvas.drawPath(tape, line);
        canvas.drawLine(p(8.2, 7.4), p(15.8, 7.4), line);
        canvas.drawLine(p(8.2, 11), p(14, 11), line);
        canvas.drawLine(p(8.2, 14.6), p(15.8, 14.6), line);

      case Pic.basket:
        canvas.drawArc(r(7.6, 4.2, 8.8, 9.8), math.pi, math.pi, false, line);
        final Path bskBody = Path()
          ..moveTo(2.8 * u, 9.2 * u)
          ..lineTo(21.2 * u, 9.2 * u)
          ..lineTo(18.6 * u, 17.6 * u)
          ..quadraticBezierTo(18 * u, 19.8 * u, 15.8 * u, 19.8 * u)
          ..lineTo(8.2 * u, 19.8 * u)
          ..quadraticBezierTo(6 * u, 19.8 * u, 5.4 * u, 17.6 * u)
          ..close();
        canvas.drawPath(bskBody, soft);
        canvas.drawPath(bskBody, line);
        canvas.drawLine(p(9.6, 12), p(10.2, 17), thin);
        canvas.drawLine(p(14.4, 12), p(13.8, 17), thin);

      case Pic.shop:
        final Path awning = Path()
          ..moveTo(2.4 * u, 9 * u)
          ..lineTo(4.4 * u, 4.2 * u)
          ..lineTo(19.6 * u, 4.2 * u)
          ..lineTo(21.6 * u, 9 * u);
        for (int i = 0; i < 6; i++) {
          final double x0 = 21.6 - i * 3.2;
          awning.quadraticBezierTo(
              (x0 - 1.6) * u, 11.4 * u, (x0 - 3.2) * u, 9 * u);
        }
        awning.close();
        canvas.drawPath(awning, soft);
        canvas.drawPath(awning, line);
        canvas.drawPath(
          Path()
            ..moveTo(4.8 * u, 11.6 * u)
            ..lineTo(4.8 * u, 20.4 * u)
            ..lineTo(19.2 * u, 20.4 * u)
            ..lineTo(19.2 * u, 11.6 * u),
          line,
        );
        canvas.drawLine(p(3.2, 20.4), p(20.8, 20.4), line);
        canvas.drawRRect(
          RRect.fromRectAndCorners(r(9.4, 13.8, 5.2, 6.6),
              topLeft: Radius.circular(2.6 * u),
              topRight: Radius.circular(2.6 * u)),
          line,
        );

      // ────────────────────────── доступ и правка ──────────────────────────
      case Pic.lock:
        canvas.drawArc(r(7.4, 3.6, 9.2, 10), math.pi, math.pi, false, line);
        canvas.drawLine(p(7.4, 8.6), p(7.4, 11.6), line);
        canvas.drawLine(p(16.6, 8.6), p(16.6, 11.6), line);
        final RRect lockBody = RRect.fromRectAndRadius(
            r(4, 11, 16, 9.6), Radius.circular(2.8 * u));
        canvas.drawRRect(lockBody, soft);
        canvas.drawRRect(lockBody, line);
        canvas.drawCircle(p(12, 14.8), 1.4 * u, line);
        canvas.drawLine(p(12, 16.2), p(12, 17.8), line);

      case Pic.lockOpen:
        // Та же форма, что и у закрытого: различие — дужка не достаёт до
        // корпуса. Так ребёнок видит именно «то же самое, но открыто».
        canvas.drawArc(
            r(7.4, 3.6, 9.2, 10), math.pi, math.pi * 0.84, false, line);
        canvas.drawLine(p(7.4, 8.6), p(7.4, 11.6), line);
        final RRect openBody = RRect.fromRectAndRadius(
            r(4, 11, 16, 9.6), Radius.circular(2.8 * u));
        canvas.drawRRect(openBody, soft);
        canvas.drawRRect(openBody, line);
        canvas.drawCircle(p(12, 14.8), 1.4 * u, line);
        canvas.drawLine(p(12, 16.2), p(12, 17.8), line);

      case Pic.trash:
        canvas.drawLine(p(3.4, 6.8), p(20.6, 6.8), line);
        canvas.drawPath(
          Path()
            ..moveTo(9.2 * u, 6.8 * u)
            ..lineTo(9.2 * u, 4.4 * u)
            ..lineTo(14.8 * u, 4.4 * u)
            ..lineTo(14.8 * u, 6.8 * u),
          line,
        );
        final Path bin = Path()
          ..moveTo(5.8 * u, 6.8 * u)
          ..lineTo(6.9 * u, 18.2 * u)
          ..quadraticBezierTo(7.1 * u, 20.4 * u, 9.3 * u, 20.4 * u)
          ..lineTo(14.7 * u, 20.4 * u)
          ..quadraticBezierTo(16.9 * u, 20.4 * u, 17.1 * u, 18.2 * u)
          ..lineTo(18.2 * u, 6.8 * u)
          ..close();
        canvas.drawPath(bin, soft);
        canvas.drawPath(bin, line);
        canvas.drawLine(p(10, 10.2), p(10.3, 17), thin);
        canvas.drawLine(p(14, 10.2), p(13.7, 17), thin);

      case Pic.pencil:
        // Корпус строится от оси: остриё внизу слева, обойма ближе к верху.
        final Path pen = Path()
          ..moveTo(4.2 * u, 19.8 * u)
          ..lineTo(7.66 * u, 18.74 * u)
          ..lineTo(19.54 * u, 6.86 * u)
          ..lineTo(17.14 * u, 4.46 * u)
          ..lineTo(5.26 * u, 16.34 * u)
          ..close();
        canvas.drawPath(pen, soft);
        canvas.drawPath(pen, line);
        canvas.drawPath(
          Path()
            ..moveTo(4.2 * u, 19.8 * u)
            ..lineTo(7.66 * u, 18.74 * u)
            ..lineTo(5.26 * u, 16.34 * u)
            ..close(),
          fill,
        );
        canvas.drawLine(p(16, 10.4), p(13.6, 8), line);

      // ───────────────────────── звук и движение ─────────────────────────
      case Pic.sound:
        final Path speaker = Path()
          ..moveTo(2.6 * u, 9.4 * u)
          ..lineTo(6.6 * u, 9.4 * u)
          ..lineTo(11.4 * u, 5 * u)
          ..lineTo(11.4 * u, 19 * u)
          ..lineTo(6.6 * u, 14.6 * u)
          ..lineTo(2.6 * u, 14.6 * u)
          ..close();
        canvas.drawPath(speaker, soft);
        canvas.drawPath(speaker, line);
        for (final double rad in <double>[4.2, 7.4]) {
          canvas.drawArc(
              Rect.fromCircle(center: p(11.4, 12), radius: rad * u),
              -math.pi / 3,
              math.pi * 2 / 3,
              false,
              line);
        }

      case Pic.soundOff:
        final Path muted = Path()
          ..moveTo(2.6 * u, 9.4 * u)
          ..lineTo(6.6 * u, 9.4 * u)
          ..lineTo(11.4 * u, 5 * u)
          ..lineTo(11.4 * u, 19 * u)
          ..lineTo(6.6 * u, 14.6 * u)
          ..lineTo(2.6 * u, 14.6 * u)
          ..close();
        canvas.drawPath(muted, soft);
        canvas.drawPath(muted, line);
        canvas.drawLine(p(15.4, 9.4), p(20.6, 14.6), line);
        canvas.drawLine(p(20.6, 9.4), p(15.4, 14.6), line);

      // ────────────────────────── чтение вслух ──────────────────────────
      case Pic.speak:
        canvas.drawCircle(p(8.2, 7.4), 3.3 * u, soft);
        canvas.drawCircle(p(8.2, 7.4), 3.3 * u, line);
        canvas.drawPath(
          Path()
            ..moveTo(2.6 * u, 20.2 * u)
            ..quadraticBezierTo(2.6 * u, 12.8 * u, 8.2 * u, 12.8 * u)
            ..quadraticBezierTo(13.8 * u, 12.8 * u, 13.8 * u, 20.2 * u),
          line,
        );
        for (final double rad in <double>[3.4, 6.2]) {
          canvas.drawArc(
              Rect.fromCircle(center: p(13.2, 9.4), radius: rad * u),
              -math.pi / 3.2,
              math.pi * 2 / 3.2,
              false,
              line);
        }

      case Pic.speakOff:
        canvas.drawCircle(p(8.2, 7.4), 3.3 * u, soft);
        canvas.drawCircle(p(8.2, 7.4), 3.3 * u, line);
        canvas.drawPath(
          Path()
            ..moveTo(2.6 * u, 20.2 * u)
            ..quadraticBezierTo(2.6 * u, 12.8 * u, 8.2 * u, 12.8 * u)
            ..quadraticBezierTo(13.8 * u, 12.8 * u, 13.8 * u, 20.2 * u),
          line,
        );
        canvas.drawLine(p(15.8, 6.6), p(21, 11.8), line);
        canvas.drawLine(p(21, 6.6), p(15.8, 11.8), line);

      case Pic.motion:
        // Мяч и след из затухающих точек — прыжок, а не скорость.
        // 🔴 Прямые линии скорости за мячом дают ровно силуэт ползунка
        // из «Настроек»; разница между `motion` и `sliders` пропадает.
        canvas.drawCircle(p(16.6, 7.8), 4 * u, soft);
        canvas.drawCircle(p(16.6, 7.8), 4 * u, line);
        for (final List<double> t in <List<double>>[
          <double>[12.2, 11.4, 1.15],
          <double>[8.9, 14.5, 0.9],
          <double>[6.1, 17.2, 0.68],
          <double>[3.8, 19.5, 0.5],
        ]) {
          canvas.drawCircle(p(t[0], t[1]), t[2] * u, fill);
        }

      case Pic.play:
        final Path tri = Path()
          ..moveTo(7.8 * u, 4.8 * u)
          ..lineTo(19 * u, 12 * u)
          ..lineTo(7.8 * u, 19.2 * u)
          ..close();
        canvas.drawPath(tri, soft);
        canvas.drawPath(tri, line);

      // ───────────────────────────── разделы ─────────────────────────────
      case Pic.flask:
        final Path flask = Path()
          ..moveTo(9.4 * u, 3.6 * u)
          ..lineTo(9.4 * u, 9.8 * u)
          ..lineTo(4.8 * u, 17.2 * u)
          ..quadraticBezierTo(3.4 * u, 19.8 * u, 6.4 * u, 19.8 * u)
          ..lineTo(17.6 * u, 19.8 * u)
          ..quadraticBezierTo(20.6 * u, 19.8 * u, 19.2 * u, 17.2 * u)
          ..lineTo(14.6 * u, 9.8 * u)
          ..lineTo(14.6 * u, 3.6 * u);
        canvas.drawPath(flask, soft);
        canvas.drawPath(flask, line);
        canvas.drawLine(p(8.2, 3.6), p(15.8, 3.6), line);
        canvas.drawCircle(p(10.4, 16.4), 1.1 * u, thin);
        canvas.drawCircle(p(13.8, 14.6), 0.8 * u, thin);

      case Pic.school:
        // Академическая шапочка, а не шапка-ушанка из «Хочу»: ромб плюс
        // кисточка — силуэт, который ни с чем не путается.
        final Path board = Path()
          ..moveTo(12 * u, 4.2 * u)
          ..lineTo(21.8 * u, 8.8 * u)
          ..lineTo(12 * u, 13.4 * u)
          ..lineTo(2.2 * u, 8.8 * u)
          ..close();
        canvas.drawPath(board, soft);
        canvas.drawPath(board, line);
        canvas.drawPath(
          Path()
            ..moveTo(6.6 * u, 11.2 * u)
            ..lineTo(6.6 * u, 15.8 * u)
            ..quadraticBezierTo(6.6 * u, 18.8 * u, 12 * u, 18.8 * u)
            ..quadraticBezierTo(17.4 * u, 18.8 * u, 17.4 * u, 15.8 * u)
            ..lineTo(17.4 * u, 11.2 * u),
          line,
        );
        canvas.drawLine(p(20.4, 10.2), p(20.4, 15), line);
        canvas.drawCircle(p(20.4, 16.4), 1.4 * u, fill);

      case Pic.speech:
        // Два пузыря: это разговор со взрослым, а не вопрос к приложению.
        final Path bubbleA = Path()
          ..moveTo(5.2 * u, 3.2 * u)
          ..lineTo(11.6 * u, 3.2 * u)
          ..quadraticBezierTo(14.4 * u, 3.2 * u, 14.4 * u, 6 * u)
          ..lineTo(14.4 * u, 9.4 * u)
          ..quadraticBezierTo(14.4 * u, 12.2 * u, 11.6 * u, 12.2 * u)
          ..lineTo(8.4 * u, 12.2 * u)
          ..lineTo(4.2 * u, 15.8 * u)
          ..lineTo(5 * u, 12.2 * u)
          ..quadraticBezierTo(2.4 * u, 12 * u, 2.4 * u, 9.4 * u)
          ..lineTo(2.4 * u, 6 * u)
          ..quadraticBezierTo(2.4 * u, 3.2 * u, 5.2 * u, 3.2 * u)
          ..close();
        canvas.drawPath(bubbleA, soft);
        canvas.drawPath(bubbleA, line);
        final Path bubbleB = Path()
          ..moveTo(15 * u, 12.8 * u)
          ..lineTo(19 * u, 12.8 * u)
          ..quadraticBezierTo(21.6 * u, 12.8 * u, 21.6 * u, 15.4 * u)
          ..lineTo(21.6 * u, 16.4 * u)
          ..quadraticBezierTo(21.6 * u, 19 * u, 19 * u, 19 * u)
          ..lineTo(19.8 * u, 22 * u)
          ..lineTo(16 * u, 19 * u)
          ..lineTo(15 * u, 19 * u)
          ..quadraticBezierTo(12.4 * u, 19 * u, 12.4 * u, 16.4 * u)
          ..lineTo(12.4 * u, 15.4 * u)
          ..quadraticBezierTo(12.4 * u, 12.8 * u, 15 * u, 12.8 * u)
          ..close();
        canvas.drawPath(bubbleB, Paint()..color = accent);
        canvas.drawPath(bubbleB, line);

      // ───────────────────────── смыслы денег ─────────────────────────
      case Pic.umbrella:
        final Path dome = Path()
          ..moveTo(2.4 * u, 12.2 * u)
          ..quadraticBezierTo(2.8 * u, 3.2 * u, 12 * u, 3.2 * u)
          ..quadraticBezierTo(21.2 * u, 3.2 * u, 21.6 * u, 12.2 * u)
          ..quadraticBezierTo(19.2 * u, 14.6 * u, 16.8 * u, 12.2 * u)
          ..quadraticBezierTo(14.4 * u, 14.6 * u, 12 * u, 12.2 * u)
          ..quadraticBezierTo(9.6 * u, 14.6 * u, 7.2 * u, 12.2 * u)
          ..quadraticBezierTo(4.8 * u, 14.6 * u, 2.4 * u, 12.2 * u)
          ..close();
        canvas.drawPath(dome, soft);
        canvas.drawPath(dome, line);
        canvas.drawPath(
          Path()
            ..moveTo(12 * u, 12.8 * u)
            ..lineTo(12 * u, 17.8 * u)
            ..arcToPoint(p(8.4, 17.8),
                radius: Radius.circular(1.8 * u), clockwise: true),
          line,
        );

      case Pic.leaf:
        final Path blade = Path()
          ..moveTo(4.4 * u, 19.6 * u)
          ..cubicTo(3.2 * u, 10.4 * u, 10 * u, 3.6 * u, 19.6 * u, 4.4 * u)
          ..cubicTo(20.4 * u, 14 * u, 13.6 * u, 20.8 * u, 4.4 * u, 19.6 * u)
          ..close();
        canvas.drawPath(blade, soft);
        canvas.drawPath(blade, line);
        canvas.drawLine(p(5.6, 18.4), p(16.6, 7.4), line);
        canvas.drawLine(p(8.8, 15.2), p(11.8, 17.6), thin);
        canvas.drawLine(p(12.6, 11.4), p(15.6, 13.8), thin);

      case Pic.trophy:
        final Path cup = Path()
          ..moveTo(6.8 * u, 4.6 * u)
          ..lineTo(17.2 * u, 4.6 * u)
          ..lineTo(17.2 * u, 9.2 * u)
          ..quadraticBezierTo(17.2 * u, 14.6 * u, 12 * u, 14.6 * u)
          ..quadraticBezierTo(6.8 * u, 14.6 * u, 6.8 * u, 9.2 * u)
          ..close();
        canvas.drawPath(cup, soft);
        canvas.drawPath(cup, line);
        canvas.drawPath(
          Path()
            ..moveTo(6.8 * u, 6 * u)
            ..quadraticBezierTo(2.6 * u, 6.6 * u, 4.2 * u, 9.8 * u)
            ..quadraticBezierTo(5.2 * u, 11.6 * u, 7.1 * u, 11.6 * u),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(17.2 * u, 6 * u)
            ..quadraticBezierTo(21.4 * u, 6.6 * u, 19.8 * u, 9.8 * u)
            ..quadraticBezierTo(18.8 * u, 11.6 * u, 16.9 * u, 11.6 * u),
          line,
        );
        canvas.drawLine(p(12, 14.6), p(12, 17.4), line);
        final RRect foot = RRect.fromRectAndRadius(
            r(7.4, 17.4, 9.2, 2.8), Radius.circular(1.2 * u));
        canvas.drawRRect(foot, soft);
        canvas.drawRRect(foot, line);

      case Pic.star:
        // Оценка заботы — сплошная звезда. Наклейка рядом остаётся контурной
        // с ободком, иначе эти две пиктограммы неразличимы.
        canvas.drawPath(_star(p(12, 12), 9.4 * u, 4.2 * u, 5), fill);

      case Pic.smile:
        canvas.drawCircle(p(12, 12), 8.8 * u, soft);
        canvas.drawCircle(p(12, 12), 8.8 * u, line);
        canvas.drawCircle(p(9, 10), s * 0.055, fill);
        canvas.drawCircle(p(15, 10), s * 0.055, fill);
        canvas.drawArc(r(7, 9.6, 10, 8), math.pi * 0.16, math.pi * 0.68, false,
            line);

      case Pic.flag:
        canvas.drawLine(p(5.4, 3.4), p(5.4, 20.6), line);
        final Path cloth = Path()
          ..moveTo(5.4 * u, 4.6 * u)
          ..lineTo(19.4 * u, 4.6 * u)
          ..lineTo(16.2 * u, 9.2 * u)
          ..lineTo(19.4 * u, 13.8 * u)
          ..lineTo(5.4 * u, 13.8 * u)
          ..close();
        canvas.drawPath(cloth, soft);
        canvas.drawPath(cloth, line);

      case Pic.wallet:
        final RRect purse = RRect.fromRectAndRadius(
            r(2.6, 5.4, 18.8, 13.2), Radius.circular(3 * u));
        canvas.drawRRect(purse, soft);
        canvas.drawRRect(purse, line);
        // Карман с кнопкой справа — то, чем кошелёк отличается от конверта.
        final RRect pocket = RRect.fromRectAndRadius(
            r(13.2, 9.4, 8.2, 4.8), Radius.circular(2.4 * u));
        canvas.drawRRect(pocket, Paint()..color = accent);
        canvas.drawRRect(pocket, line);
        canvas.drawCircle(p(16.6, 11.8), 1.2 * u, fill);

      case Pic.calc:
        final RRect box = RRect.fromRectAndRadius(
            r(4.6, 2.8, 14.8, 18.4), Radius.circular(2.6 * u));
        canvas.drawRRect(box, soft);
        canvas.drawRRect(box, line);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              r(7.2, 5.6, 9.6, 3.4), Radius.circular(1.2 * u)),
          line,
        );
        for (int row = 0; row < 2; row++) {
          for (int col = 0; col < 3; col++) {
            canvas.drawCircle(
                p(8.4 + col * 3.6, 12.8 + row * 4.2), s * 0.055, fill);
          }
        }

      case Pic.list:
        for (int i = 0; i < 3; i++) {
          final double y = 6.6 + i * 5.4;
          canvas.drawCircle(p(5, y), s * 0.055, fill);
          canvas.drawLine(p(9, y), p(20, y), line);
        }

      // ────────────────────── маркеры и пояснения ──────────────────────
      case Pic.circleEmpty:
        canvas.drawCircle(p(12, 12), 8.2 * u, line);

      case Pic.info:
        canvas.drawCircle(p(12, 12), 8.8 * u, soft);
        canvas.drawCircle(p(12, 12), 8.8 * u, line);
        canvas.drawCircle(p(12, 7.6), s * 0.055, fill);
        canvas.drawLine(p(12, 11), p(12, 16.4), line);

      case Pic.bulb:
        canvas.drawCircle(p(12, 9.4), 5.4 * u, soft);
        canvas.drawArc(Rect.fromCircle(center: p(12, 9.4), radius: 5.4 * u),
            math.pi * 0.8, math.pi * 1.4, false, line);
        canvas.drawLine(p(7.6, 12.6), p(9.6, 15.2), line);
        canvas.drawLine(p(16.4, 12.6), p(14.4, 15.2), line);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              r(9.4, 15.2, 5.2, 4.4), Radius.circular(1.3 * u)),
          line,
        );
        canvas.drawLine(p(9.8, 17.4), p(14.2, 17.4), thin);
        // Лучи: без них колба читается как лампочка, но не как «подсказка».
        canvas.drawLine(p(12, 2.9), p(12, 1.7), thin);
        canvas.drawLine(p(6.6, 4.6), p(5.7, 3.7), thin);
        canvas.drawLine(p(17.4, 4.6), p(18.3, 3.7), thin);

      case Pic.hand:
        // Раскрытая ладонь: «подожди, не спеши».
        // 🔴 Пальцы очерчены не щелями, а стыками-клиньями. Перо шириной
        // 2,16 единицы поля шире любого просвета, который поместился бы
        // между четырьмя пальцами: прорисованные щели слипаются, и ладонь
        // читается варежкой. Клин же перо сужает, но не закрывает.
        final Path palm = Path()
          ..moveTo(6.8 * u, 20.4 * u)
          ..lineTo(6.8 * u, 13.8 * u)
          ..quadraticBezierTo(3.4 * u, 12.2 * u, 4.6 * u, 10 * u)
          ..quadraticBezierTo(5.9 * u, 8.2 * u, 7.4 * u, 11.4 * u)
          ..lineTo(7.4 * u, 9 * u);
        for (final List<double> f in <List<double>>[
          <double>[7.4, 10, 5.8, 7.5],
          <double>[10, 12.6, 4.6, 6.3],
          <double>[12.6, 15.2, 4.8, 6.5],
          <double>[15.2, 17.8, 6.4, 9],
        ]) {
          palm
            ..quadraticBezierTo(
                f[0] * u, f[2] * u, (f[0] + f[1]) / 2 * u, f[2] * u)
            ..quadraticBezierTo(f[1] * u, f[2] * u, f[1] * u, f[3] * u);
        }
        palm
          ..lineTo(17.8 * u, 15.2 * u)
          ..quadraticBezierTo(17.8 * u, 20.4 * u, 12.3 * u, 20.4 * u)
          ..close();
        canvas.drawPath(palm, soft);
        canvas.drawPath(palm, line);
        for (final List<double> v in <List<double>>[
          <double>[10, 7.5],
          <double>[12.6, 6.3],
          <double>[15.2, 6.5],
        ]) {
          canvas.drawLine(p(v[0], v[1]), p(v[0], v[1] + 3.2), thin);
        }

      case Pic.external:
        canvas.drawPath(
          Path()
            ..moveTo(13 * u, 4.4 * u)
            ..lineTo(6.4 * u, 4.4 * u)
            ..quadraticBezierTo(3.6 * u, 4.4 * u, 3.6 * u, 7.2 * u)
            ..lineTo(3.6 * u, 17.6 * u)
            ..quadraticBezierTo(3.6 * u, 20.4 * u, 6.4 * u, 20.4 * u)
            ..lineTo(16.8 * u, 20.4 * u)
            ..quadraticBezierTo(19.6 * u, 20.4 * u, 19.6 * u, 17.6 * u)
            ..lineTo(19.6 * u, 11 * u),
          line,
        );
        canvas.drawLine(p(11.4, 12.6), p(20.2, 3.8), line);
        canvas.drawPath(
          Path()
            ..moveTo(14.6 * u, 3.6 * u)
            ..lineTo(20.4 * u, 3.6 * u)
            ..lineTo(20.4 * u, 9.4 * u),
          line,
        );

      // ───────────────────────────── мир ─────────────────────────────
      case Pic.city:
        // Три дома разной высоты на одной земле: «город», а не «дом».
        canvas.drawRRect(
            RRect.fromRectAndRadius(r(3, 10, 6, 10), Radius.circular(u)), soft);
        canvas.drawRRect(
            RRect.fromRectAndRadius(r(9, 4, 7, 16), Radius.circular(u)), soft);
        canvas.drawRRect(
            RRect.fromRectAndRadius(r(16, 12, 5, 8), Radius.circular(u)), soft);
        canvas.drawPath(
          Path()
            ..moveTo(3 * u, 20 * u)
            ..lineTo(3 * u, 10 * u)
            ..lineTo(9 * u, 10 * u)
            ..lineTo(9 * u, 4 * u)
            ..lineTo(16 * u, 4 * u)
            ..lineTo(16 * u, 12 * u)
            ..lineTo(21 * u, 12 * u)
            ..lineTo(21 * u, 20 * u),
          line,
        );
        canvas.drawLine(p(2, 20.4), p(22, 20.4), line);
        for (final double y in <double>[8, 12, 16]) {
          canvas.drawLine(p(11.6, y), p(13.4, y), thin);
        }
        canvas.drawLine(p(5.2, 14), p(6.8, 14), thin);
        canvas.drawLine(p(17.8, 16), p(19.2, 16), thin);

      case Pic.moon:
        // Полумесяц: круг минус смещённый круг.
        final Path moon = Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: p(11, 12.5), radius: 8 * u)),
          Path()..addOval(Rect.fromCircle(center: p(15.5, 9), radius: 7 * u)),
        );
        canvas.drawPath(moon, soft);
        canvas.drawPath(moon, line);
        canvas.drawPath(_star(p(18.6, 17), 2.2 * u, 0.9 * u, 4), fill);
    }
  }

  Path _star(Offset c, double outer, double inner, int points) {
    final Path path = Path();
    for (int i = 0; i < points * 2; i++) {
      final double rad = i.isEven ? outer : inner;
      final double a = -math.pi / 2 + i * math.pi / points;
      final Offset pt = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    return path..close();
  }

  /// Четырёхлучевая искра с вогнутыми сторонами — знак «получилось».
  Path _spark(Offset c, double rad) {
    final Path path = Path()..moveTo(c.dx, c.dy - rad);
    for (int i = 0; i < 4; i++) {
      final double a0 = -math.pi / 2 + i * math.pi / 2;
      final double a1 = a0 + math.pi / 2;
      path.quadraticBezierTo(
        c.dx + math.cos(a0 + math.pi / 4) * rad * 0.24,
        c.dy + math.sin(a0 + math.pi / 4) * rad * 0.24,
        c.dx + math.cos(a1) * rad,
        c.dy + math.sin(a1) * rad,
      );
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_PicPainter old) =>
      old.pic != pic || old.color != color || old.accent != accent;
}
