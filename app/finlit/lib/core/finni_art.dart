import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../domain/models/pet.dart';
import '../domain/models/profile.dart';
import 'icons.dart';
import 'theme.dart';

/// Финни рисуется кодом, а не картинками.
///
/// 🔴 Это ответ на §3.3 ТЗ: «все использованные изображения … должны иметь
/// право на использование». Векторный питомец из этого файла не имеет
/// правообладателя кроме команды, не весит ни килобайта в APK и
/// масштабируется без потерь.
///
/// Язык рисунка — **одна линия**: у каждой формы тот же чернильный контур,
/// что у текста и пиктограмм. Так Финни, вещи в его комнате и интерфейс
/// выглядят одной вещью, а не наклейкой поверх приложения.
///
/// Девять визуально различимых комбинаций (§2.6) — три вида × три расцветки;
/// стадии, настроение и шапочка добавляют ещё.
class FinniPalette {
  const FinniPalette(this.body, this.shade, this.belly);

  final Color body;
  final Color shade;
  final Color belly;

  static FinniPalette of(PetPalette p) => switch (p) {
        PetPalette.mint => const FinniPalette(
            Color(0xFF74CDA8), Color(0xFF34997A), Color(0xFFE6F7EF)),
        PetPalette.apricot => const FinniPalette(
            Color(0xFFF39A4C), Color(0xFFC4621F), Color(0xFFFFF1E0)),
        PetPalette.lilac => const FinniPalette(
            Color(0xFFB39AE6), Color(0xFF7657BD), Color(0xFFF2ECFC)),
      };
}

/// Поза Финни. Выбирает вызывающий экран, по событию — не по таймеру.
enum FinniPose {
  /// Стоит, лапки у груди.
  idle,

  /// Радуется: лапки вверх. Только в ответ на действие ребёнка —
  /// покупку, взнос, набранную цель.
  cheer,
}

class FinniView extends StatelessWidget {
  const FinniView({
    super.key,
    required this.species,
    required this.palette,
    required this.stage,
    required this.meters,
    this.accessories = const <String>{},
    this.size = 180,
    this.grow,
    this.hop,
    this.pose = FinniPose.idle,
    this.holding,
    this.holdingColor,
  });

  final PetSpecies species;
  final PetPalette palette;
  final PetStage stage;
  final PetMeters meters;
  final Set<String> accessories;
  final double size;

  /// Новая стадия: 0 — начало движения, 1 — покой.
  ///
  /// Не задан — Финни неподвижен: §6 разрешает движение исключительно
  /// в ответ на действие ребёнка.
  final Animation<double>? grow;

  /// Подскок в ответ на действие: 0 — начало, 1 — покой.
  final Animation<double>? hop;

  final FinniPose pose;

  /// Что Финни держит в лапках — например, только что купленную вещь.
  /// 🔴 Главный ход из анализа референсов: покупка не исчезает в списке,
  /// её видно у персонажа и потом в комнате.
  final Pic? holding;
  final Color? holdingColor;

  @override
  Widget build(BuildContext context) {
    final Widget art = CustomPaint(
      size: Size.square(size),
      painter: FinniPainter(
        look: FinniLook(
          species: species,
          palette: FinniPalette.of(palette),
          stage: stage,
          meters: meters,
          accessories: accessories,
          pose: pose,
          holds: holding != null,
        ),
        grow: grow,
        hop: hop,
      ),
    );
    // §3.6.5: настроение читается не только по мимике, но и подписью рядом —
    // подпись рисует вызывающий экран. Здесь — описание для TalkBack.
    return Semantics(
      label: '${species.title}, ${palette.title.toLowerCase()}. '
          '${stage.title}. ${Meter.mood.label(meters.mood)}',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: holding == null
            ? art
            : Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  art,
                  // Вещь — поверх лапок, у груди. Координаты — те же доли
                  // квадрата, что и у лапок в рисунке.
                  Positioned(
                    left: size * 0.33,
                    top: size * 0.53,
                    child: _HeldThing(
                      pic: holding!,
                      color: holdingColor ?? AppColors.wants,
                      size: size * 0.24,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Вещь в лапках: пиктограмма на белом кружке с чернильным контуром —
/// так она читается поверх любой расцветки Финни.
class _HeldThing extends StatelessWidget {
  const _HeldThing({required this.pic, required this.color, required this.size});

  final Pic pic;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.ink, width: size * 0.07),
      ),
      child: Pictogram(pic, size: size * 0.66, color: color),
    );
  }
}

/// Всё, что определяет рисунок, кроме движения.
@immutable
class FinniLook {
  const FinniLook({
    required this.species,
    required this.palette,
    required this.stage,
    required this.meters,
    this.accessories = const <String>{},
    this.pose = FinniPose.idle,
    this.holds = false,
  });

  final PetSpecies species;
  final FinniPalette palette;
  final PetStage stage;
  final PetMeters meters;
  final Set<String> accessories;
  final FinniPose pose;
  final bool holds;

  @override
  bool operator ==(Object other) =>
      other is FinniLook &&
      other.species == species &&
      other.palette.body == palette.body &&
      other.stage == stage &&
      other.meters == meters &&
      other.pose == pose &&
      other.holds == holds &&
      setEquals(other.accessories, accessories);

  @override
  int get hashCode =>
      Object.hash(species, palette.body, stage, meters, pose, holds,
          Object.hashAllUnordered(accessories));
}

/// Художник Финни. Публичный, чтобы сцену и превью можно было рисовать
/// тем же кодом, что и экран, — без второго, «похожего» рисунка.
class FinniPainter extends CustomPainter {
  /// 🔴 `repaint` — единственный способ анимировать здесь: кадр движения
  /// не проходит ни build, ни layout, только перерисовку.
  FinniPainter({required this.look, this.grow, this.hop})
      : super(repaint: Listenable.merge(<Listenable?>[grow, hop]));

  final FinniLook look;
  final Animation<double>? grow;
  final Animation<double>? hop;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide;
    final double g = grow == null ? 1.0 : 0.86 + 0.14 * grow!.value;
    // Подскок — вверх по синусу; перелёт кривой даёт маленькое приседание
    // на приземлении, и прыжок читается как прыжок, а не как сдвиг.
    final double lift =
        hop == null ? 0.0 : -s * 0.07 * math.sin(math.pi * hop!.value);

    // Тень под ногами остаётся на месте, пока Финни в воздухе, — по ней
    // и видно, что он подпрыгнул.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(s * 0.47, s * 0.915), width: s * 0.5, height: s * 0.05),
      Paint()..color = AppColors.ink.withValues(alpha: 0.12),
    );

    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.9 + lift);
    canvas.scale(g);
    canvas.translate(-size.width / 2, -size.height * 0.9);
    _Pen(canvas, s, look).draw();
    canvas.restore();
  }

  @override
  bool shouldRepaint(FinniPainter old) =>
      old.look != look || old.grow != grow || old.hop != hop;
}

/// Рисование в долях квадрата: координаты ниже — от 0 до 1.
class _Pen {
  _Pen(this.c, this.s, this.look)
      : ink = Paint()..color = AppColors.ink,
        line = Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.017
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round;

  final Canvas c;
  final double s;
  final FinniLook look;
  final Paint ink;
  final Paint line;

  FinniPalette get pal => look.palette;
  PetSpecies get sp => look.species;

  /// Настроение как непрерывная величина, а не два состояния.
  double get joy => (look.meters.mood / PetMeters.max).clamp(0.0, 1.0);

  /// Голоден или заскучал — глаза прикрыты: «задумался», а не «страдает».
  bool get calm => look.meters.fullness <= 3 || look.meters.mood <= 3;

  Offset o(double x, double y) => Offset(x * s, y * s);

  Rect ov(double x, double y, double w, double h) =>
      Rect.fromCenter(center: o(x, y), width: w * s, height: h * s);

  void fill(Path p, Color color, {bool stroke = true}) {
    c.drawPath(p, Paint()..color = color);
    if (stroke) c.drawPath(p, line);
  }

  void oval(double x, double y, double w, double h, Color color,
      {bool stroke = true}) {
    c.drawOval(ov(x, y, w, h), Paint()..color = color);
    if (stroke) c.drawOval(ov(x, y, w, h), line);
  }

  Path path(void Function(Path p) build) {
    final Path p = Path();
    build(p);
    return p;
  }

  void moveTo(Path p, double x, double y) => p.moveTo(x * s, y * s);
  void quad(Path p, double x1, double y1, double x, double y) =>
      p.quadraticBezierTo(x1 * s, y1 * s, x * s, y * s);
  void cubic(Path p, double x1, double y1, double x2, double y2, double x,
          double y) =>
      p.cubicTo(x1 * s, y1 * s, x2 * s, y2 * s, x * s, y * s);
  void lineTo(Path p, double x, double y) => p.lineTo(x * s, y * s);

  void draw() {
    switch (sp) {
      case PetSpecies.squirrel:
        _squirrel();
      case PetSpecies.fox:
        _fox();
      case PetSpecies.owl:
        _owl();
    }
  }

  // ─────────────────────────────── белка ───────────────────────────────

  /// 🔴 Белка, а не кот с новым именем. Узнаётся по трём вещам сразу:
  /// хвост-опахало выше головы, кисточки на ушах и щёки. Хвост закручен
  /// над спиной — это и силуэт, и характер: белка «держит запасы при себе».
  void _squirrel() {
    // Хвост — за всем остальным. Плавный плюмаж по S-образной оси: низ
    // лежит у бедра, середина прижата к спине, кончик загибается **наружу**.
    // 🔴 Не объединение кругов: «бугристый» край читался как гусеница или
    // кактус. Здесь край гладкий, а пушистость дают четыре пряди-зубца
    // на внешней стороне.
    const List<(double, double, double)> spine = <(double, double, double)>[
      (0.56, 0.84, 0.065), (0.67, 0.81, 0.09), (0.76, 0.72, 0.105),
      (0.79, 0.60, 0.11), (0.77, 0.48, 0.105), (0.745, 0.37, 0.10),
      (0.75, 0.27, 0.09), (0.80, 0.19, 0.08), (0.865, 0.16, 0.062),
      (0.905, 0.19, 0.045), (0.905, 0.24, 0.03),
    ];
    _plume(spine, pal.shade);
    // Светлая «опушка» на загнутом кончике — как у настоящей белки, и по ней
    // видно, что кончик завит наружу.
    c.drawCircle(o(0.895, 0.175), s * 0.035,
        Paint()..color = pal.body.withValues(alpha: 0.9));

    // Туловище и бедро: белка сидит, и крупное заднее бедро — половина
    // её силуэта.
    oval(0.46, 0.71, 0.33, 0.31, pal.body);
    oval(0.57, 0.78, 0.17, 0.17, pal.body);
    oval(0.45, 0.73, 0.18, 0.21, pal.belly, stroke: false);
    _feet(0.36, 0.555, 0.885);

    // Уши с кисточками — позади головы. Короткие: длинное ухо
    // превращает белку в зайца. Кисточка — крупная, из трёх прядей:
    // главная примета белки, и видно её должно быть даже на иконке.
    for (final double sgn in <double>[-1, 1]) {
      double x(double dx) => 0.44 + sgn * dx;
      final Path ear = path((Path p) {
        moveTo(p, x(0.155), 0.33);
        quad(p, x(0.175), 0.26, x(0.155), 0.215);
        quad(p, x(0.085), 0.235, x(0.055), 0.295);
        p.close();
      });
      fill(ear, pal.body);
      fill(
          path((Path p) {
            moveTo(p, x(0.13), 0.30);
            quad(p, x(0.15), 0.255, x(0.14), 0.235);
            quad(p, x(0.095), 0.25, x(0.08), 0.29);
            p.close();
          }),
          pal.belly,
          stroke: false);
      // Кисточка — «кисть»: узкая у кончика уха и широкая, с двумя
      // вырезами, вверху. Продолжение уха той же ширины читалось как
      // длинное заячье ухо.
      fill(
          path((Path p) {
            moveTo(p, x(0.13), 0.235);
            quad(p, x(0.115), 0.17, x(0.15), 0.115);
            lineTo(p, x(0.165), 0.15);
            lineTo(p, x(0.195), 0.12);
            quad(p, x(0.20), 0.19, x(0.175), 0.235);
            p.close();
          }),
          pal.shade);
    }

    // Голова чуть шире, чем высока: щёки.
    final Path head = path((Path p) {
      p.addOval(ov(0.44, 0.42, 0.40, 0.35));
    });
    fill(head, pal.body);
    // Щёки и мордочка светлым, без контура.
    oval(0.35, 0.48, 0.13, 0.10, pal.belly, stroke: false);
    oval(0.53, 0.48, 0.13, 0.10, pal.belly, stroke: false);
    oval(0.44, 0.495, 0.13, 0.09, pal.belly, stroke: false);

    _eyes(0.37, 0.51, 0.405, 0.040);
    _blush(0.315, 0.565, 0.475);
    _nose(0.44, 0.458, 0.042, 0.03);
    _mouth(0.44, 0.49, 0.055, teeth: true);
    _gear(chestX: 0.445, chestY: 0.64, hipX: 0.60, hipY: 0.80,
        shoulderX: 0.33, shoulderY: 0.60, neckY: 0.59, neckW: 0.22);
    _hat(0.44, 0.255, 0.30);
  }

  // ─────────────────────────────── лиса ───────────────────────────────

  void _fox() {
    // Хвост с белым кончиком обнимает лапы справа.
    final Path tail = path((Path p) {
      moveTo(p, 0.56, 0.87);
      cubic(p, 0.86, 0.92, 1.00, 0.70, 0.93, 0.50);
      cubic(p, 0.89, 0.38, 0.79, 0.34, 0.74, 0.41);
      cubic(p, 0.79, 0.56, 0.74, 0.72, 0.57, 0.76);
      p.close();
    });
    fill(tail, pal.body);
    c.save();
    c.clipPath(tail);
    c.drawCircle(o(0.90, 0.43), s * 0.10, Paint()..color = pal.belly);
    c.restore();
    c.drawPath(tail, line);

    oval(0.45, 0.72, 0.30, 0.30, pal.body);
    oval(0.45, 0.68, 0.16, 0.17, pal.belly, stroke: false);
    // Тёмные «носочки» — примета лисы.
    _feet(0.38, 0.52, 0.885, color: pal.shade);

    // Уши — большие треугольники с тёмной серединой.
    for (final double sgn in <double>[-1, 1]) {
      double x(double dx) => 0.44 + sgn * dx;
      fill(
          path((Path p) {
            moveTo(p, x(0.19), 0.36);
            quad(p, x(0.215), 0.18, x(0.20), 0.10);
            quad(p, x(0.08), 0.16, x(0.02), 0.27);
            p.close();
          }),
          pal.body);
      fill(
          path((Path p) {
            moveTo(p, x(0.165), 0.31);
            quad(p, x(0.18), 0.20, x(0.185), 0.15);
            quad(p, x(0.10), 0.19, x(0.065), 0.26);
            p.close();
          }),
          pal.shade,
          stroke: false);
    }

    // Голова — с острыми пучками на щеках.
    final Path head = path((Path p) {
      moveTo(p, 0.44, 0.24);
      cubic(p, 0.57, 0.24, 0.65, 0.33, 0.66, 0.43);
      lineTo(p, 0.71, 0.50);
      cubic(p, 0.62, 0.54, 0.53, 0.59, 0.44, 0.60);
      cubic(p, 0.35, 0.59, 0.26, 0.54, 0.17, 0.50);
      lineTo(p, 0.22, 0.43);
      cubic(p, 0.23, 0.33, 0.31, 0.24, 0.44, 0.24);
      p.close();
    });
    fill(head, pal.body);
    c.save();
    c.clipPath(head);
    // Светлая «маска» нижней половины морды.
    c.drawPath(
        path((Path p) {
          moveTo(p, 0.15, 0.49);
          cubic(p, 0.28, 0.43, 0.38, 0.45, 0.44, 0.50);
          cubic(p, 0.50, 0.45, 0.60, 0.43, 0.73, 0.49);
          lineTo(p, 0.73, 0.65);
          lineTo(p, 0.15, 0.65);
          p.close();
        }),
        Paint()..color = pal.belly);
    c.restore();
    c.drawPath(head, line);

    _eyes(0.365, 0.515, 0.415, 0.037);
    _blush(0.30, 0.58, 0.48);
    _nose(0.44, 0.51, 0.05, 0.034);
    _mouth(0.44, 0.535, 0.05);
    _gear(chestX: 0.45, chestY: 0.67, hipX: 0.59, hipY: 0.80,
        shoulderX: 0.34, shoulderY: 0.62, neckY: 0.605, neckW: 0.20);
    _hat(0.44, 0.27, 0.28);
  }

  // ─────────────────────────────── сова ───────────────────────────────

  void _owl() {
    // Крылья — за туловищем.
    for (final double sgn in <double>[-1, 1]) {
      c.save();
      c.translate(o(0.45 + sgn * 0.22, 0.64).dx, o(0, 0.64).dy);
      c.rotate(sgn * 0.18);
      final Rect r = Rect.fromCenter(
          center: Offset.zero, width: s * 0.13, height: s * 0.30);
      c.drawOval(r, Paint()..color = pal.shade);
      c.drawOval(r, line);
      c.restore();
    }

    // Пёрышки на макушке — короткие и отогнутые наружу, как у настоящей
    // совы. Высокие треугольники прошлой версии читались кошачьими ушами.
    for (final double sgn in <double>[-1, 1]) {
      double x(double dx) => 0.45 + sgn * dx;
      fill(
          path((Path p) {
            moveTo(p, x(0.20), 0.335);
            quad(p, x(0.245), 0.28, x(0.255), 0.235);
            quad(p, x(0.20), 0.255, x(0.14), 0.30);
            quad(p, x(0.17), 0.31, x(0.20), 0.335);
            p.close();
          }),
          pal.shade);
    }

    // Голова и туловище — одно яйцо: так сова и выглядит.
    oval(0.45, 0.585, 0.50, 0.62, pal.body);
    oval(0.45, 0.72, 0.30, 0.28, pal.belly, stroke: false);
    // «Галочки» на груди — перья.
    final Paint mark = Paint()
      ..color = pal.shade
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.012
      ..strokeCap = StrokeCap.round;
    for (final (double x, double y) in <(double, double)>[
      (0.40, 0.68), (0.50, 0.68), (0.45, 0.75), (0.38, 0.78), (0.52, 0.78),
    ]) {
      c.drawPath(
          path((Path p) {
            moveTo(p, x - 0.022, y);
            quad(p, x, y + 0.025, x + 0.022, y);
          }),
          mark);
    }
    // Лицевой диск — два светлых круга.
    oval(0.37, 0.45, 0.19, 0.19, pal.belly, stroke: false);
    oval(0.53, 0.45, 0.19, 0.19, pal.belly, stroke: false);

    // Лапки — оранжевые коготки.
    for (final double x in <double>[0.39, 0.51]) {
      oval(x, 0.895, 0.09, 0.045, const Color(0xFFF0A13A));
    }

    _eyes(0.37, 0.53, 0.45, 0.052);
    _blush(0.30, 0.60, 0.52);
    // Клюв.
    fill(
        path((Path p) {
          moveTo(p, 0.42, 0.50);
          lineTo(p, 0.48, 0.50);
          quad(p, 0.465, 0.545, 0.45, 0.56);
          quad(p, 0.435, 0.545, 0.42, 0.50);
          p.close();
        }),
        const Color(0xFFF0A13A));
    _gear(chestX: 0.45, chestY: 0.68, hipX: 0.62, hipY: 0.80,
        shoulderX: 0.31, shoulderY: 0.62, neckY: 0.575, neckW: 0.28);
    _hat(0.45, 0.29, 0.30);
  }

  // ─────────────────────────────── общее ───────────────────────────────

  /// Плюмаж по оси: точки (x, y, радиус) → гладкий контур с округлым
  /// кончиком и прядями-зубцами на внешней стороне в точках [tufts].
  /// Готовые контуры хвоста по размеру рисунка.
  ///
  /// 🔴 Хвост — объединение полусотни кругов (`Path.combine`), а Финни
  /// перерисовывается каждый кадр подскока. На API 26–28 это заметная
  /// работа процессора в кадре; контур от кадра к кадру не меняется, и
  /// считать его заново незачем. Размеров в игре — единицы.
  static final Map<int, Path> _plumeCache = <int, Path>{};

  void _plume(List<(double, double, double)> spine, Color color) {
    final int key = (s * 10).round();
    final Path? cached = _plumeCache[key];
    if (cached != null) {
      fill(cached, color);
      return;
    }
    // Плотное объединение кругов: между опорными точками — по пять
    // промежуточных. Край получается мягким, почти гладким: редкие круги
    // давали «бугры», и хвост читался гусеницей.
    Path tail = Path();
    for (int i = 0; i < spine.length - 1; i++) {
      final (double x0, double y0, double r0) = spine[i];
      final (double x1, double y1, double r1) = spine[i + 1];
      for (int k = 0; k < 5; k++) {
        final double t = k / 5;
        tail = Path.combine(
            PathOperation.union,
            tail,
            Path()
              ..addOval(Rect.fromCircle(
                  center: o(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t),
                  radius: (r0 + (r1 - r0) * t) * s)));
      }
    }
    final (double lx, double ly, double lr) = spine.last;
    tail = Path.combine(PathOperation.union, tail,
        Path()..addOval(Rect.fromCircle(center: o(lx, ly), radius: lr * s)));
    // Пушистость — три мягких бугра только по внешнему краю: хвост
    // гладкий у спины и «лохматый» снаружи, как настоящий.
    for (final int i in <int>[1, 3, 5, 7]) {
      final (double x, double y, double r) = spine[i];
      tail = Path.combine(
          PathOperation.union,
          tail,
          Path()
            ..addOval(Rect.fromCircle(
                center: o(x + r * 0.72, y + r * 0.1), radius: r * 0.55 * s)));
    }
    if (_plumeCache.length > 24) _plumeCache.clear();
    _plumeCache[key] = tail;
    fill(tail, color);
  }

  /// Шарф — знак Копилкина и Хранителя: виден с первого взгляда, даже на
  /// маленьком портрете, в отличие от монетки в лапках.
  void _scarf(double x, double y, double w) {
    const Color knit = Color(0xFF4B3BB5);
    const Color light = Color(0xFF8E80E6);
    // Два конца шарфа развеваются вбок, за край силуэта: по ним стадию
    // видно даже на портрете в 48 dp. Свисающий вниз конец на груди
    // читался предметом в лапах.
    for (final double k in <double>[0.0, 1.0]) {
      final Path end = path((Path p) {
        moveTo(p, x + w * 0.38, y - 0.012 + k * 0.02);
        quad(p, x + w * 0.62, y - 0.03 + k * 0.045, x + w * 0.86,
            y + 0.012 + k * 0.05);
        lineTo(p, x + w * 0.82, y + 0.045 + k * 0.05);
        quad(p, x + w * 0.60, y + 0.02 + k * 0.035, x + w * 0.36,
            y + 0.03 + k * 0.02);
        p.close();
      });
      fill(end, k == 0 ? knit : light);
    }
    final RRect band = RRect.fromRectAndRadius(
        ov(x, y, w, 0.07), Radius.circular(s * 0.035));
    c.drawRRect(band, Paint()..color = knit);
    final Paint stripe = Paint()
      ..color = light
      ..strokeWidth = s * 0.014;
    for (final double k in <double>[-0.25, 0.0, 0.25]) {
      c.drawLine(o(x + w * k, y - 0.024), o(x + w * k, y + 0.024), stripe);
    }
    c.drawRRect(band, line);
  }

  void _feet(double left, double right, double y, {Color? color}) {
    oval(left, y, 0.14, 0.055, color ?? pal.shade);
    oval(right, y, 0.14, 0.055, color ?? pal.shade);
  }

  /// Глаза. Зрачок крупнее у довольного — разница небольшая, но именно она
  /// отличает «рад» от «терпит». Прикрытые глаза — дуга-«улыбка»: так
  /// выглядит спокойствие, а не грусть.
  ///
  /// 🔴 Бровей нет. У прошлой версии любая наклонная бровь читалась то как
  /// злость, то как обида, и довольный лис на превью выглядел рассерженным.
  void _eyes(double lx, double rx, double y, double r) {
    for (final double x in <double>[lx, rx]) {
      if (calm) {
        c.drawPath(
            path((Path p) {
              moveTo(p, x - r, y);
              quad(p, x, y + r * 1.1, x + r, y);
            }),
            line);
        continue;
      }
      final double k = 0.9 + 0.2 * joy;
      c.drawOval(ov(x, y, r * 2 * k, r * 2.3 * k), ink);
      // Два блика: крупный сверху и маленький снизу — живой глаз.
      c.drawCircle(o(x + r * 0.35, y - r * 0.45), s * r * 0.42,
          Paint()..color = Colors.white);
      c.drawCircle(o(x - r * 0.35, y + r * 0.5), s * r * 0.18,
          Paint()..color = Colors.white.withValues(alpha: 0.8));
    }
  }

  /// Румянец — только на верхнем краю настроения: награда, а не деталь.
  void _blush(double lx, double rx, double y) {
    if (joy < 0.6) return;
    final Paint blush = Paint()
      ..color = const Color(0xFFF07C98).withValues(alpha: 0.45);
    for (final double x in <double>[lx, rx]) {
      c.drawOval(ov(x, y, 0.075, 0.045), blush);
    }
  }

  void _nose(double x, double y, double w, double h) {
    c.drawRRect(
        RRect.fromRectAndRadius(ov(x, y, w, h), Radius.circular(s * h * 0.5)),
        ink);
  }

  /// Рот. 🔴 Вниз не загибается ни при каком настроении: грустный питомец —
  /// это механика вины, а §3.5 её запрещает. Нижний край — прямая линия
  /// «задумался».
  void _mouth(double x, double y, double w, {bool teeth = false}) {
    if (joy >= 0.75 && !calm) {
      // Открытая улыбка.
      final Path open = path((Path p) {
        moveTo(p, x - w * 0.8, y);
        quad(p, x, y + w * 1.5, x + w * 0.8, y);
        p.close();
      });
      c.drawPath(open, ink);
      c.save();
      c.clipPath(open);
      c.drawOval(ov(x, y + w * 0.95, w * 1.0, w * 0.7),
          Paint()..color = const Color(0xFFF07C98));
      c.restore();
      if (teeth) _teeth(x, y);
      return;
    }
    final double curve = w * (0.1 + 0.7 * joy);
    c.drawPath(
        path((Path p) {
          moveTo(p, x - w * 0.7, y);
          quad(p, x, y + curve, x + w * 0.7, y);
        }),
        line);
  }

  /// Два передних зуба — белка.
  void _teeth(double x, double y) {
    final Rect r = Rect.fromLTWH(
        (x - 0.018) * s, y * s + s * 0.002, s * 0.036, s * 0.026);
    c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(s * 0.006)),
        Paint()..color = Colors.white);
    c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(s * 0.006)),
        Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.008);
    c.drawLine(Offset(x * s, r.top), Offset(x * s, r.bottom),
        Paint()
          ..color = AppColors.ink
          ..strokeWidth = s * 0.006);
  }

  /// Снаряжение по стадии — и лапки.
  ///
  /// 🔴 Стадия показывает **самостоятельность**, а не возраст. Финни не
  /// вырастает во взрослого зверя: пропорции у всех стадий одни. Меняется
  /// то, что он умеет и носит сам — своя монетка у Копилкина, своя сумка
  /// через плечо у Хранителя. Часть детей раздражает маленький беспомощный
  /// персонаж; здесь персонаж растёт в умениях вместе с ребёнком.
  void _gear({
    required double chestX,
    required double chestY,
    required double hipX,
    required double hipY,
    required double shoulderX,
    required double shoulderY,
    required double neckY,
    required double neckW,
  }) {
    if (look.stage == PetStage.planner) {
      // Ремень через грудь и сумка на боку с монеткой-застёжкой.
      final Paint strap = Paint()
        ..color = const Color(0xFF8A5530)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.03
        ..strokeCap = StrokeCap.round;
      final Path band = path((Path p) {
        moveTo(p, shoulderX, shoulderY);
        quad(p, (shoulderX + hipX) / 2 - 0.02, (shoulderY + hipY) / 2 + 0.04,
            hipX, hipY - 0.03);
      });
      c.drawPath(band, Paint()
        ..color = AppColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.03 + s * 0.017 * 2
        ..strokeCap = StrokeCap.round);
      c.drawPath(band, strap);
      final RRect bag = RRect.fromRectAndRadius(
          ov(hipX, hipY, 0.21, 0.16), Radius.circular(s * 0.03));
      c.drawRRect(bag, Paint()..color = const Color(0xFFA8683A));
      c.drawRRect(bag, line);
      c.drawLine(o(hipX - 0.105, hipY - 0.02), o(hipX + 0.105, hipY - 0.02),
          line);
      c.drawCircle(o(hipX, hipY + 0.01), s * 0.03, Paint()..color = AppColors.coin);
      c.drawCircle(o(hipX, hipY + 0.01), s * 0.03, line);
    }

    void arm(Offset from, Offset to) {
      c.drawLine(from, to, Paint()
        ..color = AppColors.ink
        ..strokeWidth = s * (0.055 + 0.034)
        ..strokeCap = StrokeCap.round);
      c.drawLine(from, to, Paint()
        ..color = sp == PetSpecies.owl ? pal.shade : pal.body
        ..strokeWidth = s * 0.055
        ..strokeCap = StrokeCap.round);
    }

    if (look.pose == FinniPose.cheer) {
      // Лапки вверх и в стороны — мимо морды, а не поверх неё.
      for (final double sgn in <double>[-1, 1]) {
        arm(o(chestX + sgn * 0.11, chestY - 0.01),
            o(chestX + sgn * 0.25, chestY - 0.12));
      }
      if (look.stage != PetStage.novice) _scarf(chestX, neckY, neckW);
      return;
    }

    final bool coin = look.stage != PetStage.novice && !look.holds;
    if (look.stage != PetStage.novice) _scarf(chestX, neckY, neckW);
    if (coin) {
      // Своя монетка в лапках.
      c.drawCircle(o(chestX, chestY), s * 0.058, Paint()..color = AppColors.coin);
      c.drawCircle(
          o(chestX, chestY),
          s * 0.038,
          Paint()
            ..color = AppColors.coinDeep
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.01);
      c.drawCircle(o(chestX, chestY), s * 0.058, line);
    }
    // У совы вместо лапок — кончики крыльев, и без монетки их не видно.
    if (sp == PetSpecies.owl && !coin && !look.holds) return;
    // Лапки — короткие ручки от боков к груди. Два кружка у груди
    // читались как пуговицы, сомкнутые — как бант.
    final double reach = coin || look.holds ? 0.075 : 0.045;
    for (final double sgn in <double>[-1, 1]) {
      arm(o(chestX + sgn * 0.13, chestY - 0.035),
          o(chestX + sgn * reach, chestY + 0.012));
    }
  }

  /// Шапочка — вязаная, с помпоном. Появляется, только если её купили.
  void _hat(double x, double top, double w) {
    if (!look.accessories.contains('hat')) return;
    const Color knit = Color(0xFFD8335F);
    final Path dome = path((Path p) {
      moveTo(p, x - w / 2, top + 0.06);
      cubic(p, x - w / 2, top - 0.08, x + w / 2, top - 0.08, x + w / 2,
          top + 0.06);
      p.close();
    });
    fill(dome, knit);
    final RRect band = RRect.fromRectAndRadius(
        ov(x, top + 0.065, w * 1.05, 0.055), Radius.circular(s * 0.025));
    c.drawRRect(band, Paint()..color = const Color(0xFFF2F2F2));
    c.drawRRect(band, line);
    c.drawCircle(o(x, top - 0.065), s * 0.035, Paint()..color = Colors.white);
    c.drawCircle(o(x, top - 0.065), s * 0.035, line);
  }
}
