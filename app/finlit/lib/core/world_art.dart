import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../domain/game.dart';

import '../domain/models/catalog_item.dart';
import '../domain/models/goal.dart';
import '../domain/models/pet.dart';
import '../domain/models/profile.dart';
import 'feel.dart';
import 'finni_art.dart';
import 'icons.dart';
import 'theme.dart';

/// Мир Финни: комната в разрезе дерева.
///
/// 🔴 Главная мысль из анализа игровых референсов команды: «ребёнок должен
/// копить не ради денег, а ради изменения своего мира». Поэтому здесь три
/// слоя, и каждый отвечает на решение ребёнка:
///
/// 1. **Вещи, которые остаются** (`Game.keepsakes`): купленный мячик лежит
///    на полу, книжки стоят на полке, наклейки — на стене. Покупка появляется
///    в пространстве, а не исчезает в списке (Animal Crossing).
/// 2. **Мечта** — выбранная цель стоит в комнате чертежом: пунктирный контур,
///    который закрашивается снизу вверх по мере накопления. Желанное видно
///    заранее (SimCity), и прогресс — это не полоска, а сама вещь.
/// 3. **Стадия** — обстановка, которую Финни завёл сам: у Копилкина коврик и
///    лампа, у Хранителя — доска с планом на стене. Рост показан умениями
///    и самостоятельностью, а не возрастом.
///
/// Ничего здесь не двигается само: сцена статична, пока ребёнок ничего не
/// сделал (§6 направления, §3.6.7).
class RoomScene {
  const RoomScene({
    required this.stage,
    required this.keepsakes,
    this.goal,
    this.saved = 0,
    this.fresh,
    this.fulfilled = const <Goal>[],
    this.freshDream = false,
  });

  /// Ключ иконки только что купленной вещи — её место в комнате
  /// подсвечено искрами. Только в карточке после покупки.
  final String? fresh;

  /// Исполненные мечты — в порядке исполнения (`Game.fulfilledGoals`).
  /// Стоят во дворе у корней дерева, в полном цвете, навсегда.
  final List<Goal> fulfilled;

  /// Последняя исполненная мечта только что появилась — искры вокруг неё.
  final bool freshDream;

  final PetStage stage;
  final List<(CatalogItem item, int count)> keepsakes;
  final Goal? goal;
  final int saved;

  /// Доля накопленного — от 0 до 1.
  double get ratio => goal == null || goal!.price <= 0
      ? 0
      : (saved / goal!.price).clamp(0.0, 1.0);

  bool get reached => goal != null && saved >= goal!.price;

  int countOf(String icon) {
    int n = 0;
    for (final (CatalogItem i, int c) in keepsakes) {
      if (i.icon == icon) n += c;
    }
    return n;
  }

  /// Вещи без своего места в комнате (новые позиции каталога).
  /// §2.5.14: новая позиция не должна требовать правки кода — она просто
  /// появится коробкой на полке.
  int get otherCount {
    int n = 0;
    for (final (CatalogItem i, int c) in keepsakes) {
      if (!_placed.contains(i.icon)) n += c;
    }
    return n;
  }

  static const Set<String> _placed = <String>{'star', 'ball', 'book', 'hat'};

  /// Описание для TalkBack — что стоит в комнате.
  String describe() {
    final List<String> things = <String>[
      for (final (CatalogItem i, int c) in keepsakes)
        c > 1 ? '${i.title} ×$c' : i.title,
    ];
    final String room = things.isEmpty
        ? 'Комната Финни. Пока здесь пусто — вещи, которые ты купишь, '
            'появятся тут.'
        : 'Комната Финни. Здесь: ${things.join(', ')}.';
    if (fulfilled.isEmpty) return room;
    return '$room Во дворе исполненные мечты: '
        '${fulfilled.map((Goal g) => g.title).join(', ')}.';
  }

  @override
  bool operator ==(Object other) =>
      other is RoomScene &&
      other.stage == stage &&
      other.goal?.id == goal?.id &&
      other.goal?.price == goal?.price &&
      other.saved == saved &&
      other.fresh == fresh &&
      other.freshDream == freshDream &&
      other.fulfilled.length == fulfilled.length &&
      _sameKeepsakes(other.keepsakes, keepsakes);

  @override
  int get hashCode => Object.hash(stage, goal?.id, saved, keepsakes.length);

  static bool _sameKeepsakes(
      List<(CatalogItem, int)> a, List<(CatalogItem, int)> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].$1.id != b[i].$1.id || a[i].$2 != b[i].$2) return false;
    }
    return true;
  }
}

/// Геометрия комнаты в долях сцены — общая для художника и для виджета,
/// который кладёт поверх Финни и подписи.
abstract final class RoomLayout {
  /// Отношение высоты сцены к ширине. Сцена — главное на главном экране,
  /// поэтому почти квадратная: в ней живут и Финни, и мечта, и три места,
  /// куда можно пойти.
  static const double aspect = 0.92;

  /// Пол комнаты (доля высоты).
  static const double floorY = 0.86;

  /// Где стоит Финни: центр по горизонтали и размер (доли ширины).
  static const double finniX = 0.48;
  static const double finniSize = 0.37;

  /// Где стоит мечта.
  static const Rect goalBox = Rect.fromLTRB(0.665, 0.58, 0.915, 0.86);

  /// Места, куда можно пойти из комнаты (доли ширины и высоты): дверь в
  /// лавку, доска заданий, банка-копилка на полке. Их же рисует художник.
  static const Rect door = Rect.fromLTRB(0.09, 0.47, 0.25, 0.86);
  static const Rect board = Rect.fromLTRB(0.36, 0.185, 0.60, 0.315);
  static const Rect jar = Rect.fromLTRB(0.725, 0.25, 0.825, 0.40);
  static const double shelfY = 0.40;

  /// Высота двора под комнатой (доля ширины) — когда есть исполненные мечты.
  static const double yardAspect = 0.38;
}

class RoomPainter extends CustomPainter {
  RoomPainter(this.scene);

  final RoomScene scene;

  @override
  void paint(Canvas canvas, Size size) => _Room(canvas, size, scene).draw();

  @override
  bool shouldRepaint(RoomPainter old) => old.scene != scene;
}

class _Room {
  _Room(this.c, this.size, this.scene, {double? lineScale})
      : w = size.width,
        h = size.height,
        line = Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = (lineScale ?? size.width) * 0.007
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round;

  final Canvas c;
  final Size size;
  final RoomScene scene;
  final double w;
  final double h;
  final Paint line;

  Offset p(double x, double y) => Offset(x * w, y * h);
  Rect r(double l, double t, double rr, double b) =>
      Rect.fromLTRB(l * w, t * h, rr * w, b * h);

  void fill(Path path, Color color, {bool stroke = true}) {
    c.drawPath(path, Paint()..color = color);
    if (stroke) c.drawPath(path, line);
  }

  late final RRect room = RRect.fromRectAndCorners(
    r(0.07, 0.16, 0.93, 0.96),
    topLeft: Radius.circular(w * 0.2),
    topRight: Radius.circular(w * 0.2),
    bottomLeft: Radius.circular(w * 0.04),
    bottomRight: Radius.circular(w * 0.04),
  );

  void draw() {
    // Крона выходит за верх ствола — но не за край сцены.
    c.clipRect(Offset.zero & size);
    _sky();
    _tree();
    c.save();
    c.clipRRect(room);
    _interior();
    _stageDecor();
    _keepsakes();
    _goal();
    c.restore();
    // Край дупла поверх всего, что внутри: так вещи не «вылезают» из ствола.
    c.drawRRect(
        room,
        Paint()
          ..color = SceneColors.barkDark
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.022);
    c.drawRRect(room.inflate(w * 0.011), line);
  }

  // ───────────────────────────── снаружи ─────────────────────────────

  void _sky() {
    final Rect all = Offset.zero & size;
    c.drawRect(
      all,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[SceneColors.skyTop, SceneColors.skyLow],
        ).createShader(all),
    );
    for (final (double x, double y, double k) in <(double, double, double)>[
      (0.10, 0.10, 1.0),
      (0.90, 0.16, 0.8),
    ]) {
      final Paint cloud = Paint()..color = SceneColors.cloud;
      c.drawCircle(p(x, y), w * 0.045 * k, cloud);
      c.drawCircle(p(x + 0.05 * k, y - 0.03), w * 0.055 * k, cloud);
      c.drawCircle(p(x + 0.1 * k, y), w * 0.04 * k, cloud);
    }
  }

  void _tree() {
    // Крона — пучки листвы над стволом.
    Path crown = Path();
    for (final (double x, double y, double rr) in <(double, double, double)>[
      (0.18, 0.08, 0.13), (0.34, 0.02, 0.15), (0.52, 0.00, 0.16),
      (0.70, 0.03, 0.15), (0.85, 0.09, 0.12), (0.06, 0.16, 0.08),
      (0.95, 0.18, 0.08),
    ]) {
      crown = Path.combine(PathOperation.union, crown,
          Path()..addOval(Rect.fromCircle(center: p(x, y), radius: w * rr)));
    }
    fill(crown, SceneColors.leaf);
    // Ствол.
    final RRect trunk = RRect.fromRectAndCorners(
      r(0.02, 0.12, 0.98, 1.2),
      topLeft: Radius.circular(w * 0.28),
      topRight: Radius.circular(w * 0.28),
    );
    c.drawRRect(trunk, Paint()..color = SceneColors.bark);
    c.drawRRect(trunk, line);
    // Кора — несколько тёмных штрихов по краям ствола.
    final Paint grain = Paint()
      ..color = SceneColors.barkDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.008
      ..strokeCap = StrokeCap.round;
    for (final (double x, double y, double len) in <(double, double, double)>[
      (0.045, 0.40, 0.14), (0.05, 0.70, 0.10), (0.955, 0.36, 0.12),
      (0.95, 0.66, 0.16),
    ]) {
      c.drawLine(p(x, y), p(x, y + len), grain);
    }
    // Листья, свисающие на ствол спереди.
    Path front = Path();
    for (final (double x, double y, double rr) in <(double, double, double)>[
      (0.08, 0.17, 0.07), (0.16, 0.13, 0.06), (0.88, 0.14, 0.065),
    ]) {
      front = Path.combine(PathOperation.union, front,
          Path()..addOval(Rect.fromCircle(center: p(x, y), radius: w * rr)));
    }
    fill(front, SceneColors.leafDark);
  }

  // ───────────────────────────── внутри ─────────────────────────────

  Rect rr(Rect f) => Rect.fromLTRB(f.left * w, f.top * h, f.right * w, f.bottom * h);

  void _interior() {
    c.drawRRect(room, Paint()..color = SceneColors.wall);
    final Paint plank = Paint()
      ..color = SceneColors.wallLine
      ..strokeWidth = w * 0.006;
    for (double x = 0.17; x < 0.93; x += 0.12) {
      c.drawLine(p(x, 0.14), p(x, RoomLayout.floorY), plank);
    }
    // Пол.
    final Rect floor = r(0.0, RoomLayout.floorY, 1.0, 1.0);
    c.drawRect(floor, Paint()..color = SceneColors.floor);
    c.drawLine(p(0, RoomLayout.floorY), p(1, RoomLayout.floorY), line);
    final Paint boards = Paint()
      ..color = SceneColors.floorLine
      ..strokeWidth = w * 0.005;
    c.drawLine(p(0, 0.91), p(1, 0.91), boards);

    // Круглое окно в небо.
    final Offset win = p(0.20, 0.30);
    final double wr = w * 0.065;
    c.drawCircle(win, wr, Paint()..color = SceneColors.skyTop);
    c.drawCircle(win.translate(wr * 0.35, wr * 0.35), wr * 0.45,
        Paint()..color = SceneColors.leaf);
    final Paint frame = Paint()
      ..color = SceneColors.barkDark
      ..strokeWidth = w * 0.01;
    c.drawLine(win.translate(-wr, 0), win.translate(wr, 0), frame);
    c.drawLine(win.translate(0, -wr), win.translate(0, wr), frame);
    c.drawCircle(
        win,
        wr,
        Paint()
          ..color = SceneColors.barkDark
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.016);
    c.drawCircle(win, wr + w * 0.008, line);

    _door();
    _board();

    // Полка на правой стене — на ней банка-копилка и книжки.
    final RRect shelf = RRect.fromRectAndRadius(
        r(0.64, RoomLayout.shelfY, 0.92, RoomLayout.shelfY + 0.022),
        Radius.circular(w * 0.006));
    c.drawRRect(shelf, Paint()..color = SceneColors.floor);
    c.drawRRect(shelf, line);
    _jar();
  }

  /// Дверь в лавку — «Покупки». Круглый верх, ручка и козырёк-навес
  /// в полоску: дверь ведёт наружу, к прилавку.
  void _door() {
    final Rect d = rr(RoomLayout.door);
    final RRect leaf = RRect.fromRectAndCorners(d,
        topLeft: Radius.circular(d.width / 2),
        topRight: Radius.circular(d.width / 2));
    c.drawRRect(leaf, Paint()..color = const Color(0xFFB7794A));
    final Paint grain = Paint()
      ..color = SceneColors.barkDark.withValues(alpha: 0.5)
      ..strokeWidth = w * 0.005;
    for (final double k in <double>[0.33, 0.66]) {
      c.drawLine(Offset(d.left + d.width * k, d.top + d.width * 0.4),
          Offset(d.left + d.width * k, d.bottom), grain);
    }
    c.drawRRect(leaf, line);
    c.drawCircle(Offset(d.right - d.width * 0.2, d.center.dy + d.height * 0.08),
        w * 0.011, Paint()..color = AppColors.coin);
    c.drawCircle(Offset(d.right - d.width * 0.2, d.center.dy + d.height * 0.08),
        w * 0.011, line);
  }

  /// Доска дел — «Задания»: пробковая доска с тремя приколотыми листками.
  void _board() {
    final Rect b = rr(RoomLayout.board);
    final RRect cork = RRect.fromRectAndRadius(b, Radius.circular(w * 0.012));
    c.drawRRect(cork, Paint()..color = const Color(0xFFD9A868));
    c.drawRRect(
        cork.deflate(w * 0.006),
        Paint()
          ..color = SceneColors.barkDark
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.012);
    c.drawRRect(cork, line);
    const List<Color> notes = <Color>[
      AppColors.needsBg,
      Colors.white,
      AppColors.wantsBg,
    ];
    for (int i = 0; i < 3; i++) {
      final double x = b.left + b.width * (0.12 + i * 0.28);
      final Rect n = Rect.fromLTWH(
          x, b.top + b.height * (i.isOdd ? 0.30 : 0.18), b.width * 0.22,
          b.height * 0.5);
      c.save();
      c.translate(n.center.dx, n.center.dy);
      c.rotate((i - 1) * 0.08);
      c.translate(-n.center.dx, -n.center.dy);
      c.drawRect(n, Paint()..color = notes[i]);
      c.drawRect(n, line);
      final Paint text = Paint()
        ..color = AppColors.inkSoft
        ..strokeWidth = w * 0.004;
      for (final double k in <double>[0.45, 0.65]) {
        c.drawLine(Offset(n.left + n.width * 0.18, n.top + n.height * k),
            Offset(n.right - n.width * 0.18, n.top + n.height * k), text);
      }
      c.restore();
      c.drawCircle(Offset(n.center.dx, n.top + b.height * 0.06), w * 0.008,
          Paint()..color = AppColors.wants);
    }
  }

  /// Банка-копилка на полке — «Копилка». В ней столько монеток, сколько
  /// отложено (до пяти рядов): банка наполняется вместе с мечтой.
  void _jar() {
    final Rect j = rr(RoomLayout.jar);
    final RRect glass = RRect.fromRectAndCorners(
      Rect.fromLTRB(j.left, j.top + j.height * 0.18, j.right, j.bottom),
      topLeft: Radius.circular(j.width * 0.3),
      topRight: Radius.circular(j.width * 0.3),
      bottomLeft: Radius.circular(j.width * 0.18),
      bottomRight: Radius.circular(j.width * 0.18),
    );
    c.drawRRect(glass, Paint()..color = const Color(0xFFD9ECF7));
    final int coins = scene.goal == null
        ? math.min(scene.saved, 5)
        : (scene.ratio * 5).ceil().clamp(0, 5);
    c.save();
    c.clipRRect(glass);
    for (int i = 0; i < coins; i++) {
      final double cy = glass.bottom - j.height * (0.1 + i * 0.13);
      for (final double k in <double>[0.32, 0.68]) {
        final Offset ctr = Offset(j.left + j.width * k, cy);
        c.drawCircle(ctr, j.width * 0.17, Paint()..color = AppColors.coin);
        c.drawCircle(
            ctr,
            j.width * 0.17,
            Paint()
              ..color = AppColors.coinDeep
              ..style = PaintingStyle.stroke
              ..strokeWidth = w * 0.004);
      }
    }
    c.restore();
    c.drawRRect(glass, line);
    final RRect lid = RRect.fromRectAndRadius(
        Rect.fromLTRB(j.left + j.width * 0.1, j.top, j.right - j.width * 0.1,
            j.top + j.height * 0.2),
        Radius.circular(j.width * 0.08));
    c.drawRRect(lid, Paint()..color = AppColors.savings);
    c.drawRRect(lid, line);
    c.drawLine(Offset(j.center.dx - j.width * 0.18, j.top + j.height * 0.1),
        Offset(j.center.dx + j.width * 0.18, j.top + j.height * 0.1),
        Paint()
          ..color = AppColors.ink
          ..strokeWidth = w * 0.008
          ..strokeCap = StrokeCap.round);
  }

  void _stageDecor() {
    if (scene.stage == PetStage.novice) return;
    // Копилкин: коврик под Финни — «обжился».
    final Rect rug = Rect.fromCenter(
        center: p(RoomLayout.finniX + 0.02, RoomLayout.floorY + 0.035),
        width: w * 0.36,
        height: h * 0.065);
    c.drawOval(rug, Paint()..color = SceneColors.rug);
    c.drawOval(
        rug.deflate(w * 0.018),
        Paint()
          ..color = const Color(0xFF7D70D6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.008);
    c.drawOval(rug, line);

    if (scene.stage != PetStage.planner) return;
    // Хранитель: цветок в горшке — Финни сам заботится о доме.
    final Rect pot = r(0.125, RoomLayout.floorY - 0.07, 0.175, RoomLayout.floorY);
    final Path stem = Path()
      ..moveTo(pot.center.dx, pot.top)
      ..lineTo(pot.center.dx, pot.top - h * 0.07);
    c.drawPath(stem, line);
    for (final double sgn in <double>[-1, 1]) {
      final Rect leafR = Rect.fromCenter(
          center: Offset(pot.center.dx + sgn * w * 0.022, pot.top - h * 0.05),
          width: w * 0.04,
          height: h * 0.028);
      c.drawOval(leafR, Paint()..color = SceneColors.leaf);
      c.drawOval(leafR, line);
    }
    c.drawCircle(Offset(pot.center.dx, pot.top - h * 0.08), w * 0.014,
        Paint()..color = AppColors.wants);
    c.drawCircle(Offset(pot.center.dx, pot.top - h * 0.08), w * 0.014, line);
    final Path potShape = Path()
      ..moveTo(pot.left, pot.top)
      ..lineTo(pot.right, pot.top)
      ..lineTo(pot.right - pot.width * 0.15, pot.bottom)
      ..lineTo(pot.left + pot.width * 0.15, pot.bottom)
      ..close();
    fill(potShape, const Color(0xFFC96A3B));
  }

  // ───────────────────────────── вещи ─────────────────────────────

  void _keepsakes() {
    // 🔴 Вещи крупные и на заметных местах. На третьей критике наклейка
    // была звёздочкой в 8 dp у окна — покупка «появлялась в мире», но
    // увидеть это было нельзя. Теперь у каждой вещи своё место размером
    // с предмет, а не с точку.

    // Наклейки — прямо на двери: так делают все дети. До пяти.
    final int stars = math.min(scene.countOf('star'), 5);
    final Rect d = rr(RoomLayout.door);
    final List<Offset> starSpots = <Offset>[
      Offset(d.left + d.width * 0.45, d.top + d.height * 0.48),
      Offset(d.left + d.width * 0.30, d.top + d.height * 0.68),
      Offset(d.left + d.width * 0.62, d.top + d.height * 0.80),
      Offset(d.left + d.width * 0.28, d.top + d.height * 0.90),
      Offset(d.left + d.width * 0.70, d.top + d.height * 0.62),
    ];
    for (int i = 0; i < stars; i++) {
      _star(starSpots[i], w * 0.038);
    }
    if (scene.fresh == 'star' && stars > 0) {
      _sparkle(starSpots[stars - 1], w * 0.04);
    }

    // Книжки — стопкой корешков на полке слева от банки.
    final int books = math.min(scene.countOf('book'), 3);
    const List<Color> spines = <Color>[
      AppColors.savings,
      AppColors.needs,
      AppColors.wants,
    ];
    for (int i = 0; i < books; i++) {
      final double x = 0.648 + i * 0.026;
      final Rect b = r(x, 0.285 + (i.isOdd ? 0.02 : 0), x + 0.024,
          RoomLayout.shelfY);
      c.drawRect(b, Paint()..color = spines[i]);
      c.drawRect(b, line);
      c.drawLine(Offset(b.left, b.top + b.height * 0.2),
          Offset(b.right, b.top + b.height * 0.2), line);
      if (scene.fresh == 'book' && i == books - 1) {
        _sparkle(b.center, b.height * 0.55);
      }
    }

    // Прочие вещи — коробками с бантом на полке справа от банки.
    final int others = math.min(scene.otherCount, 2);
    for (int i = 0; i < others; i++) {
      final double x = 0.835 + i * 0.042;
      final Rect b = r(x, 0.33, x + 0.038, RoomLayout.shelfY);
      c.drawRect(b, Paint()..color = AppColors.coin);
      c.drawRect(b, line);
      c.drawLine(b.topCenter, b.bottomCenter, line);
      if (scene.fresh != null &&
          !RoomScene._placed.contains(scene.fresh) &&
          i == others - 1) {
        _sparkle(b.center, b.height * 0.6);
      }
    }

    // Мячики — на полу у двери, крупно.
    final int balls = math.min(scene.countOf('ball'), 3);
    for (int i = 0; i < balls; i++) {
      final double br = w * 0.045;
      final Offset ctr = p(0.30 - i * 0.075, 0) +
          Offset(0, RoomLayout.floorY * h - br + w * 0.004);
      c.drawCircle(ctr, br, Paint()..color = AppColors.wants);
      c.save();
      c.clipPath(Path()..addOval(Rect.fromCircle(center: ctr, radius: br)));
      c.drawRect(
          Rect.fromCenter(center: ctr, width: br * 2.2, height: br * 0.55),
          Paint()..color = Colors.white);
      c.restore();
      c.drawCircle(ctr, br, line);
      if (scene.fresh == 'ball' && i == balls - 1) _sparkle(ctr, br);
    }
  }

  /// Искры вокруг только что появившейся вещи: четыре коротких луча.
  void _sparkle(Offset ctr, double rr) {
    final Paint ray = Paint()
      ..color = AppColors.coinDeep
      ..strokeWidth = w * 0.009
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 8; i++) {
      final double a = i * math.pi / 4;
      final double r0 = rr * (i.isEven ? 1.25 : 1.3);
      final double r1 = rr * (i.isEven ? 1.75 : 1.5);
      c.drawLine(ctr + Offset(math.cos(a) * r0, math.sin(a) * r0),
          ctr + Offset(math.cos(a) * r1, math.sin(a) * r1), ray);
    }
  }

  void _star(Offset ctr, double rr) {
    final Path star = Path();
    for (int i = 0; i < 10; i++) {
      final double a = -math.pi / 2 + i * math.pi / 5;
      final double k = i.isEven ? rr : rr * 0.45;
      final Offset pt = ctr + Offset(math.cos(a) * k, math.sin(a) * k);
      if (i == 0) {
        star.moveTo(pt.dx, pt.dy);
      } else {
        star.lineTo(pt.dx, pt.dy);
      }
    }
    star.close();
    fill(star, AppColors.coin);
  }

  // ───────────────────────────── мечта ─────────────────────────────

  void _goal([Rect? at]) {
    final Rect box = at ??
        Rect.fromLTRB(
          RoomLayout.goalBox.left * w,
          RoomLayout.goalBox.top * h,
          RoomLayout.goalBox.right * w,
          RoomLayout.goalBox.bottom * h,
        );

    if (scene.goal == null) {
      _emptyEasel(box);
      return;
    }
    final Path shape = _goalShape(scene.goal!.icon, box);

    // 🔴 Мечта — сама вещь, а не синий пунктир. Синий контур на первом
    // проходе читался как рамка выделения в редакторе. Теперь вещь видна
    // целиком, но выше уровня накоплений она «призрачная» — прикрыта
    // цветом стены, — а ниже уровня уже настоящая, в полном цвете.
    final double top = box.bottom - box.height * scene.ratio;
    if (scene.reached) {
      _goalColors(scene.goal!.icon, box);
    } else {
      // 🔴 Раскраска — строго внутри контура: иначе свесы крыши торчали
      // за призрак, а его сплошной контур ложился поверх пунктира двойной
      // линией (четвёртая критика: «брак рендера на главном образе»).
      c.save();
      c.clipPath(shape);
      _goalColors(scene.goal!.icon, box);
      c.restore();
    }
    if (!scene.reached) {
      c.save();
      c.clipPath(shape);
      c.drawRect(
          Rect.fromLTRB(box.left - w, box.top - h, box.right + w, top),
          Paint()..color = SceneColors.wall.withValues(alpha: 0.9));
      c.restore();
      // Контур: пунктиром там, где вещи ещё нет, сплошным — где уже есть.
      c.save();
      c.clipRect(Rect.fromLTRB(box.left - w, box.top - h, box.right + w, top));
      _dashed(shape, AppColors.ink.withValues(alpha: 0.7));
      c.restore();
      c.save();
      c.clipRect(Rect.fromLTRB(box.left - w, top, box.right + w, box.bottom + h));
      c.drawPath(shape, line);
      c.restore();
      if (scene.ratio > 0) {
        // Уровень накоплений — индиго копилки.
        c.save();
        c.clipPath(shape);
        c.drawLine(Offset(box.left, top), Offset(box.right, top),
            Paint()
              ..color = AppColors.savings
              ..strokeWidth = w * 0.009);
        c.restore();
      }
    }
  }

  /// Цели ещё нет: на её месте мольберт с табличкой «?» — место под мечту
  /// выглядит задуманным, а не пустым.
  void _emptyEasel(Rect b) {
    final Paint leg = Paint()
      ..color = SceneColors.barkDark
      ..strokeWidth = w * 0.014
      ..strokeCap = StrokeCap.round;
    c.drawLine(Offset(b.left + b.width * 0.28, b.bottom),
        Offset(b.left + b.width * 0.45, b.top + b.height * 0.2), leg);
    c.drawLine(Offset(b.right - b.width * 0.28, b.bottom),
        Offset(b.right - b.width * 0.45, b.top + b.height * 0.2), leg);
    final RRect sign = RRect.fromRectAndRadius(
        Rect.fromLTRB(b.left + b.width * 0.12, b.top + b.height * 0.12,
            b.right - b.width * 0.12, b.top + b.height * 0.66),
        Radius.circular(w * 0.012));
    c.drawRRect(sign, Paint()..color = Colors.white);
    c.drawRRect(sign, line);
    final TextPainter q = TextPainter(
      text: TextSpan(
        text: '?',
        style: AppType.number(sign.height * 0.62, color: AppColors.savings),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    q.paint(c, sign.center - Offset(q.width / 2, q.height / 2));
    q.dispose();
  }

  /// Контур мечты — по ключу иконки цели.
  Path _goalShape(String? key, Rect b) {
    double x(double k) => b.left + b.width * k;
    double y(double k) => b.top + b.height * k;
    switch (key) {
      case 'house':
        return Path()
          ..moveTo(x(0.02), y(0.48))
          ..lineTo(x(0.5), y(0.06))
          ..lineTo(x(0.98), y(0.48))
          ..lineTo(x(0.85), y(0.48))
          ..lineTo(x(0.85), y(1.0))
          ..lineTo(x(0.15), y(1.0))
          ..lineTo(x(0.15), y(0.48))
          ..close();
      case 'scooter':
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromLTRB(x(0.08), y(0.78), x(0.92), y(0.86)),
              Radius.circular(b.width * 0.04)))
          ..addRect(Rect.fromLTRB(x(0.74), y(0.15), x(0.82), y(0.80)))
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromLTRB(x(0.60), y(0.10), x(0.98), y(0.18)),
              Radius.circular(b.width * 0.04)))
          ..addOval(Rect.fromCircle(
              center: Offset(x(0.18), y(0.90)), radius: b.width * 0.1))
          ..addOval(Rect.fromCircle(
              center: Offset(x(0.82), y(0.90)), radius: b.width * 0.1));
      case 'zoo':
        // Впечатление — большой билет, прислонённый к стене: с надрезами
        // по бокам, чтобы не читался ящиком.
        return Path.combine(
          PathOperation.difference,
          Path()
            ..addRRect(RRect.fromRectAndRadius(
                Rect.fromLTRB(x(0.06), y(0.36), x(0.94), y(1.0)),
                Radius.circular(b.width * 0.06))),
          Path()
            ..addOval(Rect.fromCircle(
                center: Offset(x(0.06), y(0.68)), radius: b.width * 0.08))
            ..addOval(Rect.fromCircle(
                center: Offset(x(0.94), y(0.68)), radius: b.width * 0.08)),
        );
      default:
        // Своя цель — подарок с бантом.
        return Path()
          ..addRect(Rect.fromLTRB(x(0.12), y(0.40), x(0.88), y(1.0)))
          ..addRect(Rect.fromLTRB(x(0.06), y(0.28), x(0.94), y(0.42)));
    }
  }

  /// Раскраска мечты: то, что станет видно по мере накопления.
  void _goalColors(String key, Rect b) {
    double x(double k) => b.left + b.width * k;
    double y(double k) => b.top + b.height * k;
    final Path shape = _goalShape(key, b);
    switch (key) {
      case 'house':
        c.drawPath(shape, Paint()..color = const Color(0xFFF2C77B));
        final Path roof = Path()
          ..moveTo(x(0.02), y(0.48))
          ..lineTo(x(0.5), y(0.06))
          ..lineTo(x(0.98), y(0.48))
          ..close();
        c.drawPath(roof, Paint()..color = AppColors.wants);
        c.drawPath(roof, line);
        final RRect door = RRect.fromRectAndCorners(
            Rect.fromLTRB(x(0.38), y(0.66), x(0.62), y(1.0)),
            topLeft: Radius.circular(b.width * 0.12),
            topRight: Radius.circular(b.width * 0.12));
        c.drawRRect(door, Paint()..color = SceneColors.barkDark);
        c.drawRRect(door, line);
        c.drawCircle(Offset(x(0.5), y(0.30)), b.width * 0.07,
            Paint()..color = SceneColors.skyTop);
        c.drawCircle(Offset(x(0.5), y(0.30)), b.width * 0.07, line);
        c.drawPath(shape, line);
      case 'scooter':
        c.drawPath(shape, Paint()..color = AppColors.savings);
        for (final double k in <double>[0.18, 0.82]) {
          c.drawCircle(Offset(x(k), y(0.90)), b.width * 0.1,
              Paint()..color = AppColors.ink);
          c.drawCircle(Offset(x(k), y(0.90)), b.width * 0.04,
              Paint()..color = Colors.white);
        }
        c.drawPath(shape, line);
      case 'zoo':
        // Билет: корешок с перфорацией, звезда и строки «надписи».
        // Отпечаток лапы на первом проходе читался мордочкой на коробке.
        c.drawPath(shape, Paint()..color = const Color(0xFFFFD66B));
        c.save();
        c.clipPath(shape);
        c.drawRect(Rect.fromLTRB(x(0.0), y(0.36), x(0.30), y(1.0)),
            Paint()..color = AppColors.wants);
        c.restore();
        _dashed(Path()
          ..moveTo(x(0.30), y(0.40))
          ..lineTo(x(0.30), y(0.96)), AppColors.ink);
        _star(Offset(x(0.16), y(0.68)), b.width * 0.09);
        final Paint text = Paint()
          ..color = AppColors.ink
          ..strokeWidth = b.width * 0.035
          ..strokeCap = StrokeCap.round;
        c.drawLine(Offset(x(0.42), y(0.55)), Offset(x(0.82), y(0.55)), text);
        c.drawLine(Offset(x(0.42), y(0.70)), Offset(x(0.72), y(0.70)), text);
        c.drawLine(Offset(x(0.42), y(0.85)), Offset(x(0.78), y(0.85)), text);
        c.drawPath(shape, line);
      default:
        c.drawPath(shape, Paint()..color = AppColors.needs);
        c.drawRect(Rect.fromLTRB(x(0.44), y(0.28), x(0.56), y(1.0)),
            Paint()..color = AppColors.coin);
        c.drawPath(shape, line);
    }
  }

  /// Пунктир по контуру — «чертёж» вещи, которой ещё нет.
  void _dashed(Path path, Color color) {
    final Paint dash = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.008
      ..strokeCap = StrokeCap.round;
    final double on = w * 0.022;
    final double off = w * 0.016;
    for (final PathMetric m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        c.drawPath(m.extractPath(d, math.min(d + on, m.length)), dash);
        d += on + off;
      }
    }
  }
}

/// Сцена целиком: комната, Финни в ней и описание для TalkBack.
///
/// Касание Финни — подскок: маленький ответ на действие ребёнка, ничего не
/// меняющий в игре. Так сцена отзывается, но не «живёт сама».
class RoomView extends StatefulWidget {
  const RoomView({
    super.key,
    required this.scene,
    required this.species,
    required this.palette,
    required this.meters,
    this.accessories = const <String>{},
    this.onShop,
    this.onTasks,
    this.onSavings,
    this.pose = FinniPose.idle,
    this.hopOnOpen = false,
  });

  /// Подскочить один раз при появлении — только когда сцену открыло
  /// действие ребёнка (карточка после покупки), а не главный экран.
  final bool hopOnOpen;

  /// Поза Финни в комнате: радуется — только в карточке после покупки.
  final FinniPose pose;

  final RoomScene scene;
  final PetSpecies species;
  final PetPalette palette;
  final PetMeters meters;
  final Set<String> accessories;

  /// Куда ведут места в комнате. Не заданы — места просто нарисованы
  /// (так сцена стоит в знакомстве, где идти ещё некуда).
  final VoidCallback? onShop;
  final VoidCallback? onTasks;
  final VoidCallback? onSavings;

  @override
  State<RoomView> createState() => _RoomViewState();
}

class _RoomViewState extends State<RoomView>
    with SingleTickerProviderStateMixin {
  /// 🔴 Создаются в initState, а не лениво: поле, до которого впервые
  /// дошли из dispose, создаёт тикер на уже отсоединённом элементе.
  late final AnimationController _hop;
  late final CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    _hop = AnimationController(vsync: this, duration: Motion.nod, value: 1);
    _curve = CurvedAnimation(parent: _hop, curve: Motion.nodCurve);
    if (widget.hopOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _poke();
      });
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _hop.dispose();
    super.dispose();
  }

  void _poke() {
    _hop
      ..duration = context.motion(Motion.nod)
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double w = box.maxWidth;
        final double h = w * RoomLayout.aspect;
        final double fs = w * RoomLayout.finniSize;
        final Widget room = SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Semantics(
                  label: widget.scene.describe(),
                  child: RepaintBoundary(
                    child: CustomPaint(painter: RoomPainter(widget.scene)),
                  ),
                ),
              ),
              // Сами предметы тоже нажимаются — ребёнок тычет в дверь, а не
              // в подпись. Для TalkBack действие одно — у подписи.
              for (final (Rect r, VoidCallback? go) in <(Rect, VoidCallback?)>[
                (RoomLayout.door, widget.onShop),
                (RoomLayout.board, widget.onTasks),
                (RoomLayout.jar, widget.onSavings),
              ])
                if (go != null)
                  Positioned(
                    left: r.left * w,
                    top: r.top * h,
                    width: r.width * w,
                    height: r.height * h,
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: go,
                      ),
                    ),
                  ),
              Positioned(
                left: w * RoomLayout.finniX - fs / 2,
                top: h * RoomLayout.floorY - fs * 0.92,
                child: GestureDetector(
                  onTap: _poke,
                  child: FinniView(
                    species: widget.species,
                    palette: widget.palette,
                    stage: widget.scene.stage,
                    meters: widget.meters,
                    accessories: widget.accessories,
                    size: fs,
                    hop: _curve,
                    pose: widget.pose,
                  ),
                ),
              ),
              if (widget.onShop != null)
                _PlaceTag(
                  label: 'Покупки',
                  pic: Pic.shop,
                  color: AppColors.wants,
                  centerX: RoomLayout.door.center.dx * w,
                  // Вывеска лавки — на самой двери, как у настоящей лавки:
                  // над дверью она сталкивалась с вывеской доски.
                  centerY: (RoomLayout.door.top + 0.065) * h,
                  onTap: widget.onShop!,
                ),
              if (widget.onTasks != null)
                _PlaceTag(
                  label: 'Задания',
                  pic: Pic.task,
                  color: AppColors.needs,
                  centerX: RoomLayout.board.center.dx * w,
                  centerY: (RoomLayout.board.bottom + 0.065) * h,
                  onTap: widget.onTasks!,
                ),
              if (widget.onSavings != null)
                _PlaceTag(
                  label: 'Копилка',
                  pic: Pic.jar,
                  color: AppColors.savings,
                  centerX: RoomLayout.jar.center.dx * w,
                  centerY: (RoomLayout.shelfY + 0.075) * h,
                  onTap: widget.onSavings!,
                ),
            ],
          ),
        );
        if (widget.scene.fulfilled.isEmpty) return room;
        // 🔴 Двор появляется с первой исполненной мечтой: мир Финни
        // разрастается наружу, а место под следующую мечту в комнате
        // остаётся свободным.
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            room,
            ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size(w, w * RoomLayout.yardAspect),
                  painter: _YardPainter(widget.scene),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Мечта отдельно от комнаты — крупно, на кусочке стены и пола. Тот же
/// рисунок, что стоит в комнате на главном: одна картинка мечты на всё
/// приложение, а не «иконка цели» в одном месте и чертёж в другом.
class DreamArt extends StatelessWidget {
  const DreamArt({super.key, required this.goal, required this.saved, this.height = 150});

  final Goal goal;
  final int saved;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _DreamPainter(goal, saved)),
      ),
    );
  }
}

class _DreamPainter extends CustomPainter {
  _DreamPainter(this.goal, this.saved);

  final Goal goal;
  final int saved;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect frame = RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(Radii.chip));
    canvas.save();
    canvas.clipRRect(frame);
    canvas.drawRect(Offset.zero & size, Paint()..color = SceneColors.wall);
    final Paint plank = Paint()
      ..color = SceneColors.wallLine
      ..strokeWidth = 2;
    for (double x = size.width * 0.08; x < size.width; x += size.width * 0.12) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), plank);
    }
    final double floor = size.height * 0.86;
    canvas.drawRect(Rect.fromLTRB(0, floor, size.width, size.height),
        Paint()..color = SceneColors.floor);
    final double bh = size.height * 0.76;
    final double bw = bh * 0.9;
    final Rect box = Rect.fromLTWH(
        (size.width - bw) / 2, floor - bh, bw, bh);
    _Room(
      canvas,
      size,
      RoomScene(
        stage: PetStage.novice,
        keepsakes: const <(CatalogItem, int)>[],
        goal: goal,
        saved: saved,
      ),
      lineScale: bw / 0.26,
    )._goal(box);
    canvas.drawLine(Offset(0, floor), Offset(size.width, floor), Paint()
      ..color = AppColors.ink
      ..strokeWidth = 2);
    canvas.restore();
    canvas.drawRRect(
        frame,
        Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_DreamPainter old) =>
      old.goal.id != goal.id || old.saved != saved || old.goal.price != goal.price;
}

/// Подпись места в комнате: белая табличка с пиктограммой и словом.
///
/// 🔴 Навигация — предметами комнаты, но **всегда с подписью**. Дверь без
/// слова семилетка может не опознать как «Покупки», а TalkBack вообще не
/// видит рисунок. Табличка — это и подпись, и кнопка: зона касания 56 dp
/// при видимой табличке поменьше.
class _PlaceTag extends StatelessWidget {
  const _PlaceTag({
    required this.label,
    required this.pic,
    required this.color,
    required this.centerX,
    required this.centerY,
    required this.onTap,
  });

  final String label;
  final Pic pic;
  final Color color;
  final double centerX;
  final double centerY;
  final VoidCallback onTap;

  static const double _hit = TapSize.min;

  /// Тёмное дерево вывески: белый текст на нём — 7:1.
  static const Color _wood = Color(0xFF6E4326);
  static const Color _cream = Color(0xFFF7E6C8);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: centerY - _hit / 2,
      height: _hit,
      child: CustomSingleChildLayout(
        delegate: _CenterAt(centerX),
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            // Зона касания добирается отступом, а не выравниванием: Container
            // с alignment растягивается на всю ширину, и табличка теряла
            // свою точку — все три съезжались в середину сцены.
            // 🔴 Вывеска — часть мира: деревянная дощечка, прибитая к
            // стене, а не белая «пилюля» интерфейса поверх рисунка. Белые
            // таблички на втором проходе закрывали сами предметы и читались
            // отдельным слоем приложения.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 11),
              child: MediaQuery.withClampedTextScaling(
                // Сцена не растёт вместе со шрифтом, и вывеска на ×1.3
                // закрывала соседний предмет. Крупнее 1.15 — не нужно:
                // подпись и так 16 sp полужирным.
                maxScaleFactor: 1.15,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(Gap.sm + 2, 4, Gap.sm + 4, 5),
                  decoration: BoxDecoration(
                    color: _wood,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.ink, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Pictogram(pic, size: 18, color: _cream),
                      const SizedBox(width: 5),
                      Text(label,
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ставит табличку центром в точку по горизонтали, но не за край сцены.
class _CenterAt extends SingleChildLayoutDelegate {
  const _CenterAt(this.x);

  final double x;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => c.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final double left =
        (x - child.width / 2).clamp(4.0, math.max(4.0, size.width - child.width - 4));
    return Offset(left, (size.height - child.height) / 2);
  }

  @override
  bool shouldRelayout(_CenterAt old) => old.x != x;
}

/// Заголовок подэкрана: кусок стены комнаты, Финни и его реплика.
///
/// 🔴 Чтобы игра не кончалась на главном экране. Вторая критика: «ребёнок
/// уходит из комнаты по табличке „Покупки“ и попадает в каталог — это
/// анкета». Теперь на покупках, заданиях и плане Финни стоит в той же
/// комнате и говорит, что здесь делать, — одна короткая фраза вместо
/// строки-инструкции.
///
/// Реплики только подсказывают и никогда не просят и не упрекают (§3.5).
class SceneHeader extends StatelessWidget {
  const SceneHeader({
    super.key,
    required this.say,
    this.title,
    this.finniSize = 104,
  });

  /// Что говорит Финни. Одна-две короткие фразы.
  final String say;

  /// Крупная строка над репликой — например «Разложи 10 монеток».
  final String? title;

  final double finniSize;

  @override
  Widget build(BuildContext context) {
    final AppState? app = _appOrNull(context);
    if (app == null || !app.ready) {
      return _Bubble(title: title, say: say);
    }
    final Game g = app.game;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.envelope),
        boxShadow: Paper.cut(SceneColors.barkDark),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.envelope),
        child: CustomPaint(
          painter: const _WallPainter(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.sm, Gap.sm, Gap.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                FinniView(
                  species: g.profile.species,
                  palette: g.profile.palette,
                  stage: g.snapshot.stage,
                  meters: g.snapshot.meters,
                  accessories: g.profile.accessories,
                  size: finniSize,
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Gap.md),
                    child: _Bubble(title: title, say: say, tail: true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static AppState? _appOrNull(BuildContext context) {
    try {
      return context.watch<AppState>();
    } on Object {
      return null;
    }
  }
}

/// Облачко реплики: белое, с чернильным контуром и хвостиком к Финни.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.say, this.title, this.tail = false});

  final String? title;
  final String say;
  final bool tail;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: tail ? const _BubbleTail() : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(Gap.sm + 4, Gap.sm, Gap.sm + 4, Gap.sm + 2),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.button),
          border: Border.all(color: AppColors.ink, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (title != null)
              Semantics(
                header: true,
                child: Text(title!, style: AppType.title(19)),
              ),
            if (title != null) const SizedBox(height: 2),
            Text(say,
                style: const TextStyle(
                    fontSize: 17, height: 1.35, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

class _BubbleTail extends CustomPainter {
  const _BubbleTail();

  @override
  void paint(Canvas canvas, Size size) {
    final Path tail = Path()
      ..moveTo(1, size.height - 28)
      ..lineTo(-12, size.height - 10)
      ..lineTo(1, size.height - 14)
      ..close();
    canvas.drawPath(tail, Paint()..color = AppColors.surface);
    canvas.drawPath(
        tail,
        Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
    // Закрыть стык хвостика с облачком белым, чтобы контур не резал.
    canvas.drawLine(Offset(2, size.height - 27), Offset(2, size.height - 15),
        Paint()
          ..color = AppColors.surface
          ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_BubbleTail old) => false;
}

/// Стена и пол комнаты — фон заголовка подэкрана.
class _WallPainter extends CustomPainter {
  const _WallPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = SceneColors.wall);
    final Paint plank = Paint()
      ..color = SceneColors.wallLine
      ..strokeWidth = 2;
    for (double x = 36; x < size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), plank);
    }
    final double floor = size.height - 14;
    canvas.drawRect(Rect.fromLTRB(0, floor, size.width, size.height),
        Paint()..color = SceneColors.floor);
    canvas.drawLine(Offset(0, floor), Offset(size.width, floor), Paint()
      ..color = AppColors.ink
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_WallPainter old) => false;
}

/// Двор у корней дерева: исполненные мечты, в полном цвете.
///
/// Рисунок каждой мечты — тот же, что стоял в комнате «призраком», пока
/// ребёнок копил: вещь, которую он видел проявляющейся, теперь стоит в
/// мире насовсем. Видны последние четыре; все перечислены в описании
/// сцены для TalkBack.
class _YardPainter extends CustomPainter {
  _YardPainter(this.scene);

  final RoomScene scene;

  /// Места во дворе в порядке заполнения: ближе к стволу — раньше.
  static const List<double> _slots = <double>[0.64, 0.14, 0.80, -0.01];

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Paint line = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.007
      ..strokeJoin = StrokeJoin.round;
    final Rect all = Offset.zero & size;
    canvas.save();
    canvas.clipRect(all);
    canvas.drawRect(
      all,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // Небо двора темнее к горизонту, как над кроной: светлое у ствола
          // читалось белыми пятнами, а не небом.
          colors: <Color>[SceneColors.skyTop, Color(0xFFA9D6EE)],
        ).createShader(all),
    );
    final double ground = h * 0.80;
    // Кусты по горизонту — у двора есть даль, а не пустое небо по бокам.
    Path bushes = Path();
    for (final (double x, double r) in <(double, double)>[
      (0.02, 0.09), (0.13, 0.07), (0.24, 0.085), (0.76, 0.08), (0.87, 0.09),
      (0.98, 0.07),
    ]) {
      bushes = Path.combine(
          PathOperation.union,
          bushes,
          Path()
            ..addOval(Rect.fromCircle(
                center: Offset(w * x, ground - h * 0.12), radius: w * r)));
    }
    canvas.drawPath(bushes, Paint()..color = SceneColors.leafDark);
    canvas.drawPath(bushes, line);
    // Ствол сужается к корням.
    final Path trunk = Path()
      ..moveTo(w * 0.02, -2)
      ..lineTo(w * 0.98, -2)
      ..quadraticBezierTo(w * 0.66, h * 0.08, w * 0.62, h * 0.45)
      ..quadraticBezierTo(w * 0.60, ground - h * 0.05, w * 0.70, ground + 2)
      ..lineTo(w * 0.30, ground + 2)
      ..quadraticBezierTo(w * 0.40, ground - h * 0.05, w * 0.38, h * 0.45)
      ..quadraticBezierTo(w * 0.34, h * 0.08, w * 0.02, -2)
      ..close();
    canvas.drawPath(trunk, Paint()..color = SceneColors.bark);
    canvas.drawPath(trunk, line);
    // Трава.
    final Path grass = Path()
      ..moveTo(0, ground)
      ..quadraticBezierTo(w * 0.5, ground - h * 0.08, w, ground)
      ..lineTo(w, h + 2)
      ..lineTo(0, h + 2)
      ..close();
    canvas.drawPath(grass, Paint()..color = SceneColors.leaf);
    canvas.drawPath(grass, line);

    final List<Goal> shown = scene.fulfilled.length <= _slots.length
        ? scene.fulfilled
        : scene.fulfilled.sublist(scene.fulfilled.length - _slots.length);
    final double bw = w * 0.20;
    final double bh = bw * 1.1;
    for (int i = 0; i < shown.length; i++) {
      final double left = w * _slots[i];
      final Rect box = Rect.fromLTWH(left, ground - bh + h * 0.02, bw, bh);
      final Goal g = shown[i];
      final _Room pen = _Room(
        canvas,
        size,
        RoomScene(
          stage: PetStage.novice,
          keepsakes: const <(CatalogItem, int)>[],
          goal: g,
          saved: g.price,
        ),
        lineScale: w,
      );
      pen._goal(box);
      if (scene.freshDream && i == shown.length - 1) {
        pen._sparkle(box.center, bw * 0.55);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_YardPainter old) => old.scene != scene;
}
