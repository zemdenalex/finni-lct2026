import 'dart:convert';
import 'dart:ui';

/// Одна раскладка комнаты на все стадии: `content/room_layout.json`
/// (копия — `assets/content/world/room_layout.json`).
///
/// Денис 29.09: комната может стать главным меню — касание предмета
/// открывает его экран, поэтому дверь, кровать, стол, копилка и холодильник
/// стоят на одних и тех же местах в деревне, городе и Москве. Все числа —
/// доли стороны квадратного фона (x, y — левый верхний угол).
class RoomLayout {
  const RoomLayout({
    required this.floorY,
    required this.slots,
    required this.walk,
    required this.finni,
    required this.decor,
    required this.stages,
    this.depth = DepthScale.none,
    this.camera = CameraSpec.standard,
  });

  /// Камера за Финни (Paper Mario): мёртвая зона и время догона.
  final CameraSpec camera;

  /// Размер мира, если у фона в реестре нет size_px: квадрат, Финни (114 px)
  /// ≈ 0,31 высоты.
  static const Size defaultWorld = Size(368, 368);

  /// Перспектива: Финни и питомец меньше в глубине комнаты.
  final DepthScale depth;

  /// Низ задней стены, доля стороны.
  final double floorY;

  /// Места предметов по id слота (`door`, `bed`, `desk_chair`, …).
  final Map<String, LayoutSlot> slots;

  /// Где могут стоять ноги Финни, в долях.
  final Rect walk;

  /// Ноги Финни на своём месте, в долях.
  final Offset finni;

  /// Места купленного декора по слоту (`decor_wall`, `decor_globe`, …).
  final Map<String, Rect> decor;

  /// Фон и мебель стадии по id комнаты (`village`, `town`, `moscow`).
  final Map<String, LayoutStage> stages;

  static const String asset = 'assets/content/world/room_layout.json';

  /// id предмета комнаты у слота: так его зовут фокус сценок, кнопка у
  /// предмета и джойстик (`desk_chair` → `desk`).
  static String objectOf(String slot) => switch (slot) {
        'desk_chair' => 'desk',
        'bedside_cabinet' => 'cabinet',
        _ => slot,
      };

  /// Слоты с действием, от главного к прочим: при наложении касание
  /// получает слот с большим priority (копилка поверх тумбы).
  List<MapEntry<String, LayoutSlot>> get tappable =>
      <MapEntry<String, LayoutSlot>>[
        for (final MapEntry<String, LayoutSlot> e in slots.entries)
          if (e.value.action != null) e,
      ]..sort(
          (MapEntry<String, LayoutSlot> a, MapEntry<String, LayoutSlot> b) =>
              b.value.priority.compareTo(a.value.priority));

  static RoomLayout? parse(String json) {
    final Object? root = jsonDecode(json);
    if (root is! Map<String, Object?>) return null;
    final Object? floor = root['floor_y'];
    final Object? slots = root['slots'];
    final Rect? walk = _walk(root['walk']);
    final Object? finni = root['finni'];
    final Object? stages = root['stages'];
    if (floor is! num ||
        slots is! Map<String, Object?> ||
        walk == null ||
        finni is! Map<String, Object?> ||
        stages is! Map<String, Object?>) {
      return null;
    }
    final Object? fx = finni['x'], fy = finni['y'];
    if (fx is! num || fy is! num) return null;
    final Object? decor = root['decor'];
    return RoomLayout(
      depth: DepthScale.parse(root['depth_scale']) ?? DepthScale.none,
      camera: CameraSpec.parse(root['camera']) ?? CameraSpec.standard,
      floorY: floor.toDouble(),
      slots: <String, LayoutSlot>{
        for (final MapEntry<String, Object?> e in slots.entries)
          if (!e.key.startsWith('_'))
            if (LayoutSlot.parse(e.value) case final LayoutSlot s) e.key: s,
      },
      walk: walk,
      finni: Offset(fx.toDouble(), fy.toDouble()),
      decor: <String, Rect>{
        if (decor is Map<String, Object?>)
          for (final MapEntry<String, Object?> e in decor.entries)
            if (!e.key.startsWith('_'))
              if (_rect(e.value) case final Rect r) e.key: r,
      },
      stages: <String, LayoutStage>{
        for (final MapEntry<String, Object?> e in stages.entries)
          if (!e.key.startsWith('_'))
            if (LayoutStage.parse(e.value) case final LayoutStage s) e.key: s,
      },
    );
  }

  static Rect? _rect(Object? v) => v is Map<String, Object?> &&
          v['x'] is num &&
          v['y'] is num &&
          v['w'] is num &&
          v['h'] is num
      ? Rect.fromLTWH((v['x']! as num).toDouble(), (v['y']! as num).toDouble(),
          (v['w']! as num).toDouble(), (v['h']! as num).toDouble())
      : null;

  static Rect? _walk(Object? v) => v is Map<String, Object?> &&
          v['x0'] is num &&
          v['x1'] is num &&
          v['y0'] is num &&
          v['y1'] is num
      ? Rect.fromLTRB(
          (v['x0']! as num).toDouble(),
          (v['y0']! as num).toDouble(),
          (v['x1']! as num).toDouble(),
          (v['y1']! as num).toDouble())
      : null;
}

/// Место предмета: прямоугольник в долях, действие касания (`city`,
/// `sleep`, `jobs`, `piggy`, `food`; нет — просто место), приоритет
/// касания и с кем место заявлено перекрываться.
class LayoutSlot {
  const LayoutSlot(this.rect,
      {this.action, this.priority = 0, this.overlaps = const <String>[]});

  final Rect rect;
  final String? action;
  final int priority;
  final List<String> overlaps;

  static LayoutSlot? parse(Object? v) {
    final Rect? r = RoomLayout._rect(v);
    if (r == null) return null;
    final Map<String, Object?> m = v! as Map<String, Object?>;
    final Object? a = m['action'], p = m['priority'], o = m['overlaps'];
    return LayoutSlot(r,
        action: a is String ? a : null,
        priority: p is num ? p.toInt() : 0,
        overlaps: <String>[
          if (o is List<Object?>)
            for (final Object? s in o)
              if (s is String) s,
        ]);
  }
}

/// Комната стадии: фон (id в группе `room` реестра), есть ли мебель в
/// самом фоне, спрайт мебели по слоту и цвета полей.
class LayoutStage {
  const LayoutStage({
    required this.background,
    required this.backgroundHasFurniture,
    required this.furniture,
    this.edgeWall,
    this.edgeFloor,
  });

  final String background;
  final bool backgroundHasFurniture;
  final Map<String, String> furniture;
  final Color? edgeWall;
  final Color? edgeFloor;

  static LayoutStage? parse(Object? v) {
    if (v is! Map<String, Object?>) return null;
    final Object? bg = v['background'];
    final Object? has = v['background_has_furniture'];
    final Object? f = v['furniture'];
    if (bg is! String || has is! bool) return null;
    return LayoutStage(
      background: bg,
      backgroundHasFurniture: has,
      furniture: <String, String>{
        if (f is Map<String, Object?>)
          for (final MapEntry<String, Object?> e in f.entries)
            if (e.value is String) e.key: e.value! as String,
      },
      edgeWall: _hex(v['edge_wall']),
      edgeFloor: _hex(v['edge_floor']),
    );
  }

  static Color? _hex(Object? v) {
    if (v is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)) return null;
    return Color(0xFF000000 | int.parse(v.substring(1), radix: 16));
  }
}

/// Масштаб по глубине (Денис 29.09: «чем дальше в глубине Финни, тем он
/// чуть меньше»): линейно по y ног (доли кадра) от [yBack] ([back]) до
/// [yFront] ([front]); за краями — значение края.
class DepthScale {
  const DepthScale(
      {required this.yBack,
      required this.back,
      required this.yFront,
      required this.front});

  static const DepthScale none =
      DepthScale(yBack: 0, back: 1, yFront: 1, front: 1);

  final double yBack, back, yFront, front;

  /// Масштаб при ногах на [y] (доля кадра).
  double at(double y) {
    if (yFront <= yBack) return front;
    final double t = ((y - yBack) / (yFront - yBack)).clamp(0.0, 1.0);
    return back + (front - back) * t;
  }

  static DepthScale? parse(Object? v) {
    if (v is! Map<String, Object?>) return null;
    final Object? yb = v['y_back'], b = v['scale_back'];
    final Object? yf = v['y_front'], f = v['scale_front'];
    if (yb is! num || b is! num || yf is! num || f is! num) return null;
    return DepthScale(
        yBack: yb.toDouble(),
        back: b.toDouble(),
        yFront: yf.toDouble(),
        front: f.toDouble());
  }
}

/// Камера комнаты: доля ширины экрана, где Финни ходит без сдвига камеры
/// ([deadZone]), и за сколько камера его догоняет ([ease]).
class CameraSpec {
  const CameraSpec(
      {required this.deadZone, required this.ease, this.foregroundShown = 0});

  static const CameraSpec standard =
      CameraSpec(deadZone: 0.3, ease: Duration(milliseconds: 250));

  final double deadZone;
  final Duration ease;

  /// Какая доля ширины кровати и стола (передний план у краёв) видна, когда
  /// камера в центре комнаты: масштаб не крупнее, чтобы они не прятались
  /// наполовину за краем. 0 — без ограничения.
  final double foregroundShown;

  static CameraSpec? parse(Object? v) {
    if (v is! Map<String, Object?>) return null;
    final Object? d = v['dead_zone'], e = v['ease_ms'];
    final Object? f = v['foreground_shown'];
    if (d is! num || e is! num) return null;
    return CameraSpec(
        deadZone: d.toDouble(),
        ease: Duration(milliseconds: e.toInt()),
        foregroundShown: f is num ? f.toDouble() : 0);
  }
}
