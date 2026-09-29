import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/art/sprite_anim.dart';
import '../../../domain/world/contract.dart';
import 'city_geometry.dart';

/// Наполнение города (Денис, 29.09: «нужно больше наполнения, кусты,
/// дороги, что-то ещё»): земля с дорогами и декор по стадиям.
///
/// Декор — только картинка: не нажимается (IgnorePointer), не читается
/// TalkBack (ExcludeSemantics), стоит в стороне от зданий и значков.
/// Рисованное кодом — по пиксельной сетке (1 клетка = 1 логический px, как
/// у заготовок `night_items/city_*`), три тона и тёмный контур, без
/// скруглений и градиентов.

/// Палитра земли стадии: деревня — грунт, город — плитка, Москва — асфальт.
@immutable
class CityGround {
  const CityGround({
    required this.outside,
    required this.grass,
    required this.grassAlt,
    required this.tuftLight,
    required this.tuftDark,
    required this.road,
    required this.roadEdge,
    required this.roadMark,
    required this.soil,
  });

  /// Трава вокруг поля (опушка).
  final Color outside;
  final Color grass;

  /// Трава «через клетку» — чуть светлее, читается сетка.
  final Color grassAlt;
  final Color tuftLight;
  final Color tuftDark;
  final Color road;

  /// Бордюр / кромка дороги.
  final Color roadEdge;

  /// Разметка: камешки, швы плитки или белая полоса.
  final Color roadMark;

  /// Бок «плато» под полем (B).
  final Color soil;

  static const CityGround village = CityGround(
    outside: Color(0xFF4E8A46),
    grass: Color(0xFF7DBE5E),
    grassAlt: Color(0xFF84C465),
    tuftLight: Color(0xFFA3D77A),
    tuftDark: Color(0xFF5E9E4A),
    road: Color(0xFFCDA26C),
    roadEdge: Color(0xFFA67B4C),
    roadMark: Color(0xFFB48A5A),
    soil: Color(0xFF8A5F3C),
  );

  static const CityGround town = CityGround(
    outside: Color(0xFF4B8449),
    grass: Color(0xFF78B75F),
    grassAlt: Color(0xFF80BE66),
    tuftLight: Color(0xFF9DD07C),
    tuftDark: Color(0xFF5A9650),
    road: Color(0xFFD3CAB8),
    roadEdge: Color(0xFFA39A89),
    roadMark: Color(0xFFBDB3A0),
    soil: Color(0xFF7D6450),
  );

  static const CityGround moscow = CityGround(
    outside: Color(0xFF487D4B),
    grass: Color(0xFF70AE63),
    grassAlt: Color(0xFF78B569),
    tuftLight: Color(0xFF94C97F),
    tuftDark: Color(0xFF558E52),
    road: Color(0xFF5E6272),
    roadEdge: Color(0xFFBEBDC6),
    roadMark: Color(0xFFEDE8DA),
    soil: Color(0xFF6B6770),
  );

  static CityGround of(WorldStage s) => switch (s) {
        WorldStage.village => village,
        WorldStage.town => town,
        WorldStage.moscow => moscow,
      };
}

/// Земля: опушка, клетки травы, дороги с кромкой и разметкой, травинки.
class CityGroundPainter extends CustomPainter {
  CityGroundPainter({required this.geo, required this.stage, required this.k});

  final CityGeometry geo;
  final WorldStage stage;
  final double k;

  Paint _fill(Color c) => Paint()
    ..color = c
    ..isAntiAlias = false;

  Path _diamond(Offset c, double hw, double hh) => Path()
    ..moveTo(c.dx * k, (c.dy - hh) * k)
    ..lineTo((c.dx + hw) * k, c.dy * k)
    ..lineTo(c.dx * k, (c.dy + hh) * k)
    ..lineTo((c.dx - hw) * k, c.dy * k)
    ..close();

  /// Точка на дороге — там травинок нет.
  bool _onRoad(Offset p) {
    if (geo.iso) {
      for (final CityCell c in geo.roads) {
        if (geo.inCell(c, p)) return true;
      }
      return false;
    }
    // A: дорожки — кромка ромба шириной 18.
    for (final CityCell c in geo.ground) {
      if (!geo.inCell(c, p)) continue;
      final Offset m = geo.center(c);
      final double inner = (p.dx - m.dx).abs() / (geo.tileW / 2 - 18) +
          (p.dy - m.dy).abs() / (geo.tileH / 2 - 9);
      return inner > 1;
    }
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final CityGround g = CityGround.of(stage);
    final Rect all = Offset.zero & size;
    // Опушка — во всю карту: камера показывает её край, не плашку.
    canvas.drawRect(all, _fill(g.outside));
    final double hw = geo.tileW / 2, hh = geo.tileH / 2;
    if (geo.iso) _plate(canvas, g);
    for (final CityCell c in geo.ground) {
      final Offset m = geo.center(c);
      final bool road = geo.roads.contains(c);
      if (road) {
        canvas.drawPath(_diamond(m, hw, hh), _fill(g.road));
      } else if (geo.iso) {
        canvas.drawPath(_diamond(m, hw, hh),
            _fill((c.$1 + c.$2).isEven ? g.grass : g.grassAlt));
      } else {
        // A: вся клетка — дорожка, внутри — трава.
        canvas.drawPath(_diamond(m, hw, hh), _fill(g.road));
        canvas.drawPath(_diamond(m, hw - 18, hh - 9), _fill(g.grass));
      }
    }
    if (geo.iso) _roadEdges(canvas, g);
    _tufts(canvas, size, g);
    if (geo.iso) _roadMarks(canvas, g);
  }

  /// B: поле — плато, у нижних кромок виден бок земли (как у острова).
  void _plate(Canvas canvas, CityGround g) {
    const double side = 6;
    final Offset left = geo.center((0, 4)) - Offset(geo.tileW / 2, 0);
    final Offset bottom = geo.anchor((4, 4));
    final Offset right = geo.center((4, 0)) + Offset(geo.tileW / 2, 0);
    final Path p = Path()
      ..moveTo(left.dx * k, left.dy * k)
      ..lineTo(bottom.dx * k, bottom.dy * k)
      ..lineTo(right.dx * k, right.dy * k)
      ..lineTo(right.dx * k, (right.dy + side) * k)
      ..lineTo(bottom.dx * k, (bottom.dy + side) * k)
      ..lineTo(left.dx * k, (left.dy + side) * k)
      ..close();
    canvas.drawPath(p, _fill(g.soil));
  }

  /// Кромка дороги: только на сторонах, где сосед — не дорога.
  void _roadEdges(Canvas canvas, CityGround g) {
    final Paint edge = Paint()
      ..color = g.roadEdge
      ..strokeWidth = 2 * k
      ..isAntiAlias = false;
    final double hw = geo.tileW / 2, hh = geo.tileH / 2;
    for (final CityCell c in geo.roads) {
      final Offset m = geo.center(c);
      final Offset top = Offset(m.dx, m.dy - hh) * k;
      final Offset right = Offset(m.dx + hw, m.dy) * k;
      final Offset bot = Offset(m.dx, m.dy + hh) * k;
      final Offset left = Offset(m.dx - hw, m.dy) * k;
      bool road(int dc, int dr) => geo.roads.contains((c.$1 + dc, c.$2 + dr));
      if (!road(0, -1)) canvas.drawLine(top, right, edge);
      if (!road(1, 0)) canvas.drawLine(right, bot, edge);
      if (!road(0, 1)) canvas.drawLine(bot, left, edge);
      if (!road(-1, 0)) canvas.drawLine(left, top, edge);
    }
  }

  /// Разметка по стадии: деревня — камешки, город — швы плитки, Москва —
  /// белая прерывистая полоса и зебра на перекрёстке.
  void _roadMarks(Canvas canvas, CityGround g) {
    final Paint mark = _fill(g.roadMark);
    final math.Random rnd = math.Random(7);
    for (final CityCell c in geo.roads) {
      final Offset m = geo.center(c);
      final bool alongC = geo.roads.contains((c.$1 + 1, c.$2)) ||
          geo.roads.contains((c.$1 - 1, c.$2));
      final bool alongR = geo.roads.contains((c.$1, c.$2 + 1)) ||
          geo.roads.contains((c.$1, c.$2 - 1));
      switch (stage) {
        case WorldStage.village:
          for (int i = 0; i < 9; i++) {
            final Offset p = m +
                Offset((rnd.nextDouble() - 0.5) * geo.tileW * 0.6,
                    (rnd.nextDouble() - 0.5) * geo.tileH * 0.6);
            canvas.drawRect(
                Rect.fromLTWH(p.dx.floorToDouble() * k,
                    p.dy.floorToDouble() * k, 2 * k, 1 * k),
                mark);
          }
        case WorldStage.town:
          // Швы плитки: короткие штрихи по двум осям ромба.
          for (int i = -2; i <= 2; i++) {
            final Offset a = m + Offset(i * 12.0, i * 6.0);
            canvas.drawRect(
                Rect.fromLTWH(a.dx.floorToDouble() * k,
                    a.dy.floorToDouble() * k, 4 * k, 1 * k),
                mark);
            final Offset b =
                m + Offset(i * 12.0, -i * 6.0) + const Offset(0, 3);
            canvas.drawRect(
                Rect.fromLTWH(b.dx.floorToDouble() * k,
                    b.dy.floorToDouble() * k, 4 * k, 1 * k),
                mark);
          }
        case WorldStage.moscow:
          if (alongC && alongR) {
            // Зебра: полосы поперёк обеих дорог.
            for (int i = -2; i <= 2; i++) {
              final Offset a = m + Offset(i * 8.0 - 26, i * -4.0 - 13);
              canvas.drawRect(
                  Rect.fromLTWH(a.dx * k, a.dy * k, 6 * k, 2 * k), mark);
              final Offset b = m + Offset(i * 8.0 + 26, i * -4.0 + 13);
              canvas.drawRect(
                  Rect.fromLTWH(b.dx * k, b.dy * k, 6 * k, 2 * k), mark);
            }
          } else {
            // Прерывистая полоса вдоль дороги.
            final Offset dir = alongC
                ? Offset(geo.tileW / 2, geo.tileH / 2)
                : Offset(-geo.tileW / 2, geo.tileH / 2);
            final Paint line = Paint()
              ..color = g.roadMark
              ..strokeWidth = 2 * k
              ..isAntiAlias = false;
            for (final double t in <double>[-0.4, 0.1]) {
              final Offset a = m + dir * t;
              final Offset b = m + dir * (t + 0.25);
              canvas.drawLine(a * k, b * k, line);
            }
          }
      }
    }
  }

  /// Травинки: пиксельные штрихи по траве, мимо дорог.
  void _tufts(Canvas canvas, Size size, CityGround g) {
    final math.Random rnd = math.Random(11 + stage.index);
    final Paint light = _fill(g.tuftLight), dark = _fill(g.tuftDark);
    final int n = (geo.base.width * geo.base.height / 260).round();
    for (int i = 0; i < n; i++) {
      final Offset p = Offset(
          (rnd.nextDouble() * geo.base.width).floorToDouble(),
          (rnd.nextDouble() * geo.base.height).floorToDouble());
      final bool isLight = rnd.nextBool();
      if (_onRoad(p)) continue;
      canvas.drawRect(Rect.fromLTWH(p.dx * k, p.dy * k, 1 * k, 2 * k),
          isLight ? light : dark);
      canvas.drawRect(
          Rect.fromLTWH((p.dx + 2) * k, (p.dy + 1) * k, 1 * k, 1 * k),
          isLight ? light : dark);
    }
  }

  @override
  bool shouldRepaint(CityGroundPainter old) =>
      old.k != k || old.stage != stage || !identical(old.geo, geo);
}

// ─── Пиксельные спрайты кодом ─────────────────────────────────────────────

/// Спрайт по пиксельной сетке: размер в логических px и цвет каждой клетки
/// (null — прозрачно).
@immutable
class PixelSprite {
  const PixelSprite(this.width, this.height, this.px);

  final int width;
  final int height;
  final List<Color?> px;

  Size get size => Size(width.toDouble(), height.toDouble());
}

const Color _outline = Color(0xFF1F4A33);
const Color _leafDark = Color(0xFF2E7045);
const Color _leaf = Color(0xFF45924F);
const Color _leafLight = Color(0xFF6FBF5E);
const Color _leafShine = Color(0xFF9CD67C);
const Color _shadow = Color(0x33000000);

PixelSprite _blob(int w, int h, List<(double, double, double)> circles,
    {int seed = 1}) {
  final List<Color?> px = List<Color?>.filled(w * h, null);
  final int body = h - 1; // нижний ряд — тень
  bool inside(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= body) return false;
    for (final (double cx, double cy, double r) in circles) {
      final double dx = x + 0.5 - cx, dy = y + 0.5 - cy;
      if (dx * dx + dy * dy <= r * r) return true;
    }
    return false;
  }

  final math.Random rnd = math.Random(seed);
  for (int y = 0; y < body; y++) {
    for (int x = 0; x < w; x++) {
      if (!inside(x, y)) continue;
      final bool edge = !inside(x - 1, y) ||
          !inside(x + 1, y) ||
          !inside(x, y - 1) ||
          !inside(x, y + 1);
      Color c;
      if (edge) {
        c = _outline;
      } else {
        // Свет сверху-слева: светлее к верху, темнее к низу.
        final double t = y / body - (x / w - 0.5) * 0.3;
        c = t < 0.35
            ? _leafLight
            : t < 0.7
                ? _leaf
                : _leafDark;
        if (t < 0.45 && rnd.nextDouble() < 0.12) c = _leafShine;
        if (t >= 0.45 && rnd.nextDouble() < 0.1) c = _leafDark;
      }
      px[y * w + x] = c;
    }
  }
  for (int x = 2; x < w - 2; x++) {
    px[body * w + x] = _shadow;
  }
  return PixelSprite(w, h, px);
}

PixelSprite _flowers() {
  const int w = 14, h = 7;
  final List<Color?> px = List<Color?>.filled(w * h, null);
  const List<Color> petals = <Color>[
    Color(0xFFE8544E),
    Color(0xFFF5C84A),
    Color(0xFFFFFFFF),
    Color(0xFFE77BB0),
  ];
  const List<(int, int)> heads = <(int, int)>[
    (1, 2),
    (4, 1),
    (7, 3),
    (10, 1),
    (12, 3),
    (5, 4),
    (9, 4)
  ];
  int i = 0;
  for (final (int x, int y) in heads) {
    for (int yy = y + 1; yy < h - 1; yy++) {
      px[yy * w + x] = _leaf;
    }
    px[y * w + x] = petals[i++ % petals.length];
  }
  for (int x = 1; x < w - 1; x++) {
    px[(h - 1) * w + x] = _leafDark;
  }
  return PixelSprite(w, h, px);
}

PixelSprite _lamp() {
  const int w = 7, h = 28;
  const Color post = Color(0xFF3B3F52), postLine = Color(0xFF23263A);
  const Color glass = Color(0xFFFFD873), glow = Color(0xFFFFF1B8);
  final List<Color?> px = List<Color?>.filled(w * h, null);
  void set(int x, int y, Color c) => px[y * w + x] = c;
  // Фонарь: крышка, стекло, низ.
  for (int x = 1; x < 6; x++) {
    set(x, 0, postLine);
  }
  for (int y = 1; y < 6; y++) {
    set(0, y, postLine);
    set(6, y, postLine);
    for (int x = 1; x < 6; x++) {
      set(x, y, y < 3 ? glow : glass);
    }
  }
  for (int x = 1; x < 6; x++) {
    set(x, 6, postLine);
  }
  // Столб.
  for (int y = 7; y < h - 3; y++) {
    set(2, y, postLine);
    set(3, y, post);
    set(4, y, postLine);
  }
  // Основание.
  for (int y = h - 3; y < h - 1; y++) {
    for (int x = 1; x < 6; x++) {
      set(x, y, x == 1 || x == 5 ? postLine : post);
    }
  }
  for (int x = 0; x < w; x++) {
    set(x, h - 1, _shadow);
  }
  return PixelSprite(w, h, px);
}

/// Деревянный забор вдоль изо-оси: [down] — «\», иначе «/».
PixelSprite _fence({required bool down}) {
  const int w = 30, rise = 15, postH = 9;
  const int h = rise + postH + 1;
  const Color wood = Color(0xFFB07E50), woodDark = Color(0xFF6A4328);
  final List<Color?> px = List<Color?>.filled(w * h, null);
  void set(int x, int y, Color c) {
    if (x >= 0 && x < w && y >= 0 && y < h) px[y * w + x] = c;
  }

  // Низ забора по оси: y = base(x).
  int base(int x) => down ? postH + x ~/ 2 : postH + rise - x ~/ 2;
  // Перекладины.
  for (int x = 0; x < w; x++) {
    set(x, base(x) - 3, wood);
    set(x, base(x) - 2, woodDark);
    set(x, base(x) - 7, wood);
    set(x, base(x) - 6, woodDark);
  }
  // Столбики через 7 px.
  for (int x = 1; x < w; x += 7) {
    for (int y = base(x) - postH; y <= base(x); y++) {
      set(x, y, woodDark);
      set(x + 1, y, wood);
    }
  }
  return PixelSprite(w, h, px);
}

final Map<DecorKind, PixelSprite> _pixelCache = <DecorKind, PixelSprite>{};

/// Рисованный кодом спрайт декора; null — у вида есть картинка-заготовка.
PixelSprite? cityPixelSprite(DecorKind kind) {
  PixelSprite? make() => switch (kind) {
        DecorKind.bush => _blob(
            26,
            17,
            const <(double, double, double)>[
              (8, 10, 6.5),
              (14, 7.5, 7),
              (19.5, 10.5, 6),
            ],
            seed: 3),
        DecorKind.bushSmall => _blob(
            17,
            12,
            const <(double, double, double)>[
              (6, 7, 5),
              (11, 6.5, 5.5),
            ],
            seed: 5),
        DecorKind.flowers => _flowers(),
        DecorKind.lamp => _lamp(),
        DecorKind.fenceDown => _fence(down: true),
        DecorKind.fenceUp => _fence(down: false),
        _ => null,
      };
  final PixelSprite? cached = _pixelCache[kind];
  if (cached != null) return cached;
  final PixelSprite? made = make();
  if (made != null) _pixelCache[kind] = made;
  return made;
}

/// id заготовки трека арта для вида декора (`night_items`).
String? cityDecorArtId(DecorKind kind) => switch (kind) {
      DecorKind.tree => 'city_tree',
      DecorKind.bench => 'city_bench',
      DecorKind.fountain => 'city_fountain',
      DecorKind.busstop => 'city_busstop',
      DecorKind.kiosk => 'city_kiosk',
      DecorKind.flowerbed => 'city_flowerbed',
      _ => null,
    };

/// Размер заготовки при 1× (`size_px` в реестре) — чтобы место декора было
/// известно до чтения картинки.
Size cityDecorSize(DecorKind kind) =>
    cityPixelSprite(kind)?.size ??
    switch (kind) {
      DecorKind.tree => const Size(35, 40),
      DecorKind.bench => const Size(40, 32),
      DecorKind.fountain => const Size(55, 55),
      DecorKind.busstop => const Size(56, 51),
      DecorKind.kiosk => const Size(37, 38),
      DecorKind.flowerbed => const Size(44, 37),
      _ => Size.zero,
    };

/// Прямоугольник декора при 1×: низ-центр — точка на земле.
Rect cityDecorRect(CityDecor d) {
  final Size s = cityDecorSize(d.kind);
  return Rect.fromLTWH(d.x - s.width / 2, d.y - s.height, s.width, s.height);
}

class _PixelPainter extends CustomPainter {
  _PixelPainter(this.sprite, this.k);

  final PixelSprite sprite;
  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()..isAntiAlias = false;
    for (int y = 0; y < sprite.height; y++) {
      for (int x = 0; x < sprite.width; x++) {
        final Color? c = sprite.px[y * sprite.width + x];
        if (c == null) continue;
        p.color = c;
        // +0.5: без щелей между клетками при дробном масштабе.
        canvas.drawRect(Rect.fromLTWH(x * k, y * k, k + 0.5, k + 0.5), p);
      }
    }
  }

  @override
  bool shouldRepaint(_PixelPainter old) =>
      old.k != k || !identical(old.sprite, sprite);
}

/// Декор на карте: картинка-заготовка или пиксельный спрайт. Только вид.
class CityDecorView extends StatelessWidget {
  const CityDecorView(
      {super.key, required this.decor, required this.k, this.registry});

  final CityDecor decor;
  final double k;
  final AssetRegistry? registry;

  @override
  Widget build(BuildContext context) {
    final PixelSprite? px = cityPixelSprite(decor.kind);
    final Widget child = px != null
        ? SizedBox.expand(child: CustomPaint(painter: _PixelPainter(px, k)))
        : PixelImage(registry?.item(cityDecorArtId(decor.kind)!), scale: k);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Align(alignment: Alignment.bottomCenter, child: child),
      ),
    );
  }
}
