import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/art/sprite_anim.dart';
import '../../../core/feel.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart' show WorldRadii;
import '../../../domain/world/contract.dart';
import '../../../domain/world/fridge_stock.dart';
import '../home/finni_reaction.dart';
import '../joystick.dart';
import '../../../domain/phrases.dart';
import '../home/room_scene.dart'
    show PiggyAmount, RoomArt, decorPlace, fridgeLabel;
import 'iso_depth.dart';
import 'iso_grid.dart';
import 'iso_painter.dart';
import 'iso_room.dart';

/// Iso room (V2, flag `room.view: "iso"`): the room in 2:1 isometry, every
/// place by the slot names of the front room. Walls and floor are painted
/// (no art from Denis yet); furniture, decor, skins, Finni and the pet are
/// the game's pictures. Each thing is its own tap target and TalkBack node,
/// keys as in the front room (`room:bed`, `room:door`, `room:decor:<id>` …),
/// plus `room:iso:slot:<slot>` around every place.
///
/// Walking goes through the screen's flow ([finniNear], as in the front
/// room): the scene moves Finni along a 4-connected path to a free cell next
/// to the thing. «Расставить» ([arrange]): a tap on a thing selects it, a tap
/// on a floor cell or a wall slot moves it ([onPlace]); a thing that already
/// stands can also be dragged to a new place (a ghost shows green or red).
///
/// Camera (Денис 19.10): two fingers zoom from the fit scale up to
/// [maxZoom], one finger pans a zoomed room; the button `room:iso:camera`
/// flies to Finni and follows him, the next press shows the whole room.
class IsoRoomScene extends StatefulWidget {
  const IsoRoomScene({
    super.key,
    required this.art,
    required this.stage,
    required this.species,
    required this.idleTag,
    required this.finniName,
    required this.happiness,
    this.petId,
    this.petAwake = false,
    this.decorIds = const <String>[],
    this.decorTitle,
    this.furnitureSkins = const <String, String>{},
    this.saved = const <String, RoomIsoSpot>{},
    this.arrange = false,
    this.selected,
    this.onSelect,
    this.onPlace,
    this.onRefuse,
    this.onFinniTap,
    this.finniPose,
    this.aboveFinni,
    this.finniKey,
    this.onPetTap,
    this.onBedTap,
    this.onDoorTap,
    this.onPiggyTap,
    this.onDeskTap,
    this.onFridgeTap,
    this.onWalkTo,
    this.piggySaved,
    this.fridge = FridgeStock.empty,
    this.finniNear,
    this.walkTime,
    this.topInset = 0,
    this.cameraFocus,
    this.onStickNear,
    this.spec,
  });

  final RoomArt? art;
  final WorldStage stage;
  final String species;
  final String idleTag;
  final String finniName;
  final int happiness;
  final String? petId;
  final bool petAwake;

  /// Bought decor to show ([decorToShow]): each id stands on its place
  /// ([decorPlace]).
  final List<String> decorIds;

  /// Name of a bought thing for TalkBack («Глобус»); null — the id.
  final String Function(String id)? decorTitle;

  /// Skin per slot (`bed` → `skin_bed__4a`).
  final Map<String, String> furnitureSkins;

  /// Saved iso positions ([ResourceSnapshot.roomIso]).
  final Map<String, RoomIsoSpot> saved;

  final bool arrange;
  final String? selected;
  final ValueChanged<String>? onSelect;
  final void Function(String slot, RoomIsoSpot spot)? onPlace;

  /// A move was refused: why, in words for the child.
  final ValueChanged<String>? onRefuse;

  final VoidCallback? onFinniTap;
  final String? finniPose;
  final Widget? aboveFinni;
  final GlobalKey? finniKey;
  final VoidCallback? onPetTap;
  final VoidCallback? onBedTap;
  final VoidCallback? onDoorTap;
  final VoidCallback? onPiggyTap;
  final VoidCallback? onDeskTap;
  final VoidCallback? onFridgeTap;

  /// Finni walks to a thing without an action (decor, pet bed): the screen
  /// sets [finniNear] to the slot.
  final ValueChanged<String>? onWalkTo;
  final int? piggySaved;
  final FridgeStock fridge;

  /// Thing Finni walked to (`bed`, `desk`, `piggy`, `fridge`, `door` or a
  /// slot name).
  final String? finniNear;
  final Duration? walkTime;

  /// HUD over the top of the scene: the room fits below it.
  final double topInset;

  /// Joystick (finger drawn over the floor, not in «Расставить»): Finni
  /// stopped next to a thing with an action (`bed`, `desk`, `piggy`,
  /// `fridge`, `door`) or left it (null). The screen shows the thing's
  /// button, as in the front room. Null — no joystick.
  final ValueChanged<String?>? onStickNear;

  /// A tutorial step points at a thing of the room (`tutorialRoomFocus`):
  /// while it is set the camera shows the whole room, so the lit thing is
  /// in the picture even after «К Финни» or a pinch.
  final String? cameraFocus;

  /// Room data; null — read from [IsoRoomSpec.asset].
  final IsoRoomSpec? spec;

  /// Things with an action of the front room → their iso slot.
  static const Map<String, String> objectSlot = <String, String>{
    'bed': 'bed',
    'desk': 'desk_chair',
    'piggy': 'bedside_cabinet',
    'fridge': 'fridge',
  };

  /// Places shown without a purchase: furniture with an action.
  static const List<String> fixedSlots = <String>[
    'bed',
    'bedside_cabinet',
    'desk_chair',
    'fridge',
    'pet_corner',
  ];

  /// Largest fit scale on a big screen (the whole room, before zoom).
  static const double maxScale = 2.4;

  /// Zoom over the fit scale: pinch stops here.
  static const double maxZoom = 3;

  /// Largest zoom of the first frame and of the «К Финни» button: the room
  /// opens close to Finni, «Вся комната» shows it whole (Денис 20.10 12:51:
  /// «камеру нужно ближе к Финни»).
  static const double finniZoom = 2.2;

  /// Close up, Finni is this share of the view's height under the HUD: on
  /// a big screen a fixed ×2.2 blew him up past the frame (1440×900).
  static const double finniShare = 0.3;

  /// The close camera is at least this much closer than the whole room: a
  /// low view (800×360) already shows Finni at [finniShare].
  static const double minCloseZoom = 1.3;

  /// Zoom of the close camera: Finni [finniShare] of [viewH], between
  /// [minCloseZoom] and [finniZoom]. [finniH] — Finni in the whole room, px.
  static double closeZoom({required double finniH, required double viewH}) =>
      finniH <= 0
          ? finniZoom
          : (viewH * finniShare / finniH)
              .clamp(minCloseZoom, finniZoom)
              .toDouble();

  /// Width / height of the view above which the room is framed without
  /// the wall tops and the front floor corner ([wideCropTop],
  /// [wideCropBottom], content px).
  static const double wideRatio = 1.6;
  static const double wideCropTop = 40;
  static const double wideCropBottom = 28;

  /// Joystick circle, as in the front room and the city.
  static const double stickSize = 96;

  /// Joystick speed, cells per second: across the room in about 2 s.
  static const double stickSpeed = 3;

  /// Slots of the things with an action → their name for [onStickNear].
  static const Map<String, String> slotObject = <String, String>{
    'bed': 'bed',
    'desk_chair': 'desk',
    'bedside_cabinet': 'piggy',
    'fridge': 'fridge',
    'door': 'door',
  };

  /// The file once read: a room built again (back from the city) draws at
  /// once instead of one blank frame waiting for the future.
  static IsoRoomSpec? _loaded;

  /// Slots present for [decorIds]: fixed furniture plus every decor place
  /// that has a bought thing.
  static Map<String, String?> presentSlots(List<String> decorIds) =>
      <String, String?>{
        for (final String s in fixedSlots) s: null,
        for (final String id in decorIds) decorPlace(id).slot: id,
      };

  @override
  State<IsoRoomScene> createState() => _IsoRoomSceneState();
}

/// The view of the last build: what a gesture needs to turn screen points
/// into room points.
typedef _IsoView = ({
  IsoRoomSpec spec,
  IsoArrangement room,
  Set<(int, int)> hero,
  double fit,
  double zoom,
  double k,
  Offset off,
  Offset centre,
  Offset viewCentre,
  Size content,
  Size viewSize,
  List<(String, Rect)> hits,
});

class _IsoRoomSceneState extends State<IsoRoomScene>
    with TickerProviderStateMixin {
  IsoRoomSpec? _spec;
  // Created in initState, not lazily: a lazy controller first touched in
  // dispose() would look up TickerMode on a deactivated element.
  late final AnimationController _walk;

  /// Finni's cell and the path he is walking (cells, from the start).
  (int, int)? _cell;
  List<(int, int)> _path = const <(int, int)>[];

  // ───────────── camera ─────────────
  /// Zoom over the fit scale, 1 — the whole room. The room opens close to
  /// Finni ([initState]).
  double _zoom = 1;

  /// Room point (content px) at the centre of the view; null — the room's
  /// centre.
  Offset? _centre;

  /// The camera keeps Finni in the centre (after «К Финни»).
  bool _follow = false;
  late final AnimationController _cam;
  double _camFromZoom = 1;
  Offset? _camFromCentre;

  _IsoView? _view;

  /// Where a fresh one-finger touch began; null once a gesture used it or
  /// a second finger came (a drag starts only from a fresh touch).
  Offset? _downAt;
  int _fingers = 0;

  /// The OS took the touch away (back swipe, shade): a drag is undone.
  bool _cancelled = false;
  double _zoomAtStart = 1;
  Offset _anchor = Offset.zero;

  // ───────────── joystick ─────────────
  /// Feet moved by the joystick (cell units); null — Finni stands on [_cell].
  ({double x, double y})? _free;

  /// Where the finger put the joystick; null — not shown.
  Offset? _padCenter;
  Offset _padKnob = Offset.zero;
  String? _stickNear;
  bool _sticking = false;

  /// Created at the first touch; not `late final` (dispose must not make it).
  JoystickDriver? _driveOrNull;
  JoystickDriver get _drive =>
      _driveOrNull ??= JoystickDriver(this, onStep: _stickStep);

  static const double _padTravel =
      IsoRoomScene.stickSize / 2 - IsoRoomScene.stickSize * 0.21;

  void _padStart(Offset at) => setState(() {
        _sticking = true;
        _padCenter = at;
        _padKnob = Offset.zero;
      });

  void _padMove(Offset at) {
    final Offset? c = _padCenter;
    if (c == null) return;
    Offset d = at - c;
    if (d.distance > _padTravel) d = d / d.distance * _padTravel;
    setState(() => _padKnob = d);
    _drive.set(d / _padTravel, stepped: !context.motionOn);
  }

  void _padEnd() {
    if (!_sticking) return;
    _driveOrNull?.set(Offset.zero, stepped: !context.motionOn);
    setState(() {
      _sticking = false;
      _padCenter = null;
      _padKnob = Offset.zero;
    });
  }

  /// One joystick step: along the floor, around the furniture.
  void _stickStep(double seconds, Offset dir) {
    final _IsoView? v = _view;
    if (v == null || !mounted) return;
    final ({double x, double y}) d = isoStickDir(v.spec.grid, dir);
    final double len =
        math.min(1, dir.distance) * IsoRoomScene.stickSpeed * seconds;
    final (int, int) c = _cell ?? (v.spec.finniX, v.spec.finniY);
    final ({double x, double y}) from = _free ?? (x: c.$1 + 0.5, y: c.$2 + 0.5);
    final ({double x, double y}) to = isoSlide(v.room, from,
        (x: from.x + d.x * len, y: from.y + d.y * len), v.spec.finniR);
    final String? near = isoNearThing(
        v.spec,
        v.room,
        to,
        IsoRoomScene.slotObject.keys
            .where((String k) => k == 'door' || v.room.placed.containsKey(k)));
    _walk.stop();
    setState(() {
      _free = to;
      _path = const <(int, int)>[];
      _cell = (to.x.floor(), to.y.floor());
    });
    final String? name = near == null ? null : IsoRoomScene.slotObject[near];
    if (name != _stickNear) {
      _stickNear = name;
      widget.onStickNear?.call(name);
    }
  }

  // ───────────── Finni alive ─────────────
  /// Finni looks left (the pictures look right): the way he last went.
  bool _faceLeft = false;
  Offset? _lastFeet;

  /// A hop when patted (a short run, then still: tests can settle).
  late final AnimationController _hop;

  /// Height of the hop, share of Finni's height.
  static const double _hopLift = 0.12;

  void _patFinni() {
    if (context.motionOn) {
      _hop
        ..duration = const Duration(milliseconds: 360)
        ..forward(from: 0);
    }
    widget.onFinniTap?.call();
  }

  // ───────────── drag in «Расставить» ─────────────
  String? _dragId;
  IsoPlacement? _ghost;
  Offset _grab = Offset.zero;

  @override
  void initState() {
    super.initState();
    _walk = AnimationController(vsync: this)..addListener(_tick);
    _cam = AnimationController(vsync: this)..addListener(_tick);
    _hop = AnimationController(vsync: this);
    // Close to Finni from the first frame; «Расставить» shows the room whole.
    if (!widget.arrange) {
      _follow = true;
    }
    _spec = widget.spec ?? IsoRoomScene._loaded;
    if (_spec == null) {
      // Each room reads until one read succeeded (the bundle caches the
      // text): a shared pending future could belong to a room already gone.
      rootBundle.loadString(IsoRoomSpec.asset).then(IsoRoomSpec.parse).then(
          (IsoRoomSpec s) {
        IsoRoomScene._loaded = s;
        if (mounted) setState(() => _spec = s);
      }, onError: (Object e, StackTrace st) {
        // A broken room file must be seen, not leave a blank room.
        FlutterError.reportError(
            FlutterErrorDetails(exception: e, stack: st, library: 'room_iso'));
      });
    }
  }

  void _tick() => setState(() {});

  @override
  void dispose() {
    _driveOrNull?.dispose();
    _walk.dispose();
    _cam.dispose();
    _hop.dispose();
    super.dispose();
  }

  /// «К Финни» ↔ «Вся комната».
  void _toggleCamera() {
    final _IsoView? v = _view;
    final bool toFinni = !(_follow || (v?.zoom ?? _zoom) > 1.01);
    _camFromZoom = v?.zoom ?? _zoom;
    // Following, the zoom is the close one of the build ([closeZoom]).
    _camFromCentre = v?.centre;
    final Duration d = context.motion(const Duration(milliseconds: 380));
    setState(() {
      _zoom = 1;
      _follow = toFinni;
      _centre = null;
    });
    if (d == Duration.zero) return;
    _cam
      ..duration = d
      ..forward(from: 0);
  }

  /// Placed thing under a screen point, the front one first.
  String? _hitAt(_IsoView v, Offset local) {
    for (final (String id, Rect r) in v.hits.reversed) {
      if (r.contains(local)) return id;
    }
    return null;
  }

  void _scaleStart(ScaleStartDetails d) {
    final _IsoView? v = _view;
    // A tutorial step holds the camera (and dims the room anyway).
    if (v == null || widget.cameraFocus != null) return;
    final Offset? down = _downAt;
    _downAt = null;
    _cancelled = false;
    if (down != null && d.pointerCount == 1 && widget.arrange) {
      final String? id = _hitAt(v, down);
      final IsoPlacement? p = id == null ? null : v.room.placed[id];
      if (p != null) {
        final Offset c = (down - v.off) / v.k;
        _grab = p.isWall
            ? Offset(p.u + p.spec.len / 2 - _wallU(v.spec.grid, p.side!, c), 0)
            : _gridOf(v.spec.grid, c).scale(-1, -1) +
                Offset(p.x + p.spec.w / 2, p.y + p.spec.d / 2);
        setState(() {
          _dragId = p.id;
          _ghost = p;
        });
        // The detector starts only past the slop: the finger is already
        // away from [down], so the ghost follows at once.
        _dragMove(v, d.localFocalPoint);
        if (widget.selected != p.id) widget.onSelect?.call(p.id);
        return;
      }
    }
    if (down != null &&
        d.pointerCount == 1 &&
        !widget.arrange &&
        widget.onStickNear != null) {
      _padStart(down);
      _padMove(d.localFocalPoint);
      return;
    }
    _startZoom(v, d.localFocalPoint);
  }

  void _startZoom(_IsoView v, Offset focal) {
    _cam.stop();
    _zoomAtStart = v.zoom;
    _anchor = (focal - v.off) / v.k;
    if (_follow || _centre == null || _zoom != v.zoom) {
      setState(() {
        _follow = false;
        _zoom = v.zoom;
        _centre = v.centre;
      });
    }
  }

  void _scaleUpdate(ScaleUpdateDetails d) {
    final _IsoView? v = _view;
    if (v == null || widget.cameraFocus != null) return;
    if (_dragId != null) return _dragMove(v, d.localFocalPoint);
    if (_sticking) {
      // A second finger: the joystick lets go, the pinch zooms.
      if (d.pointerCount < 2) return _padMove(d.localFocalPoint);
      _padEnd();
      return _startZoom(v, d.localFocalPoint);
    }
    final double z =
        (_zoomAtStart * d.scale).clamp(1.0, IsoRoomScene.maxZoom).toDouble();
    final double k = v.fit * z;
    // Stored clamped, and the room point under the fingers is re-taken
    // from what is seen: a pan back from the edge moves the room at once.
    final Offset c = isoClampCentre(
        (v.viewCentre - d.localFocalPoint) / k + _anchor,
        v.content,
        v.viewSize,
        k);
    _anchor = (d.localFocalPoint - v.viewCentre) / k + c;
    setState(() {
      _zoom = z;
      _centre = c;
    });
  }

  void _scaleEnd(ScaleEndDetails d) {
    _padEnd();
    final _IsoView? v = _view;
    final String? id = _dragId;
    final IsoPlacement? ghost = _ghost;
    if (id == null) return;
    setState(() {
      _dragId = null;
      _ghost = null;
    });
    // Only a lift of the last finger drops the thing; a second finger or a
    // cancelled touch puts it back.
    if (d.pointerCount > 0 || _cancelled) return;
    if (v == null || ghost == null || !widget.arrange) return;
    if (v.room.placed[id]?.spot == ghost.spot) return;
    _place(v.room, ghost, v.hero);
  }

  /// The ghost under the finger: snapped to a cell (floor) or a slot (wall),
  /// kept inside the room so it never leaves the picture.
  void _dragMove(_IsoView v, Offset local) {
    final IsoPlacement? p = v.room.placed[_dragId];
    if (p == null) return;
    final IsoGrid g = v.spec.grid;
    final Offset c = (local - v.off) / v.k;
    final IsoPlacement next;
    if (p.isWall) {
      final IsoWall side = c.dx < g.origin.dx ? IsoWall.left : IsoWall.right;
      final int u = (_wallU(g, side, c) + _grab.dx - p.spec.len / 2)
          .round()
          .clamp(0, math.max(0, g.wallLen(side) - p.spec.len));
      next = IsoPlacement.wall(p.spec, side, u);
    } else {
      final Offset at = _gridOf(g, c) + _grab;
      next = IsoPlacement.floor(
        p.spec,
        (at.dx - p.spec.w / 2).round().clamp(0, math.max(0, g.cols - p.spec.w)),
        (at.dy - p.spec.d / 2).round().clamp(0, math.max(0, g.rows - p.spec.d)),
      );
    }
    if (next.spot != _ghost?.spot) setState(() => _ghost = next);
  }

  /// A move by the rules of the room: placed ([IsoRoomScene.onPlace]) or
  /// refused with words for the child.
  void _place(IsoArrangement room, IsoPlacement want, Set<(int, int)> hero) {
    final IsoBlock b = room.check(want, hero: hero);
    if (b == IsoBlock.ok) {
      widget.onPlace?.call(want.id, want.spot);
      return;
    }
    widget.onRefuse?.call(switch (b) {
      IsoBlock.outside => 'Сюда не помещается. Выбери клетку ближе к середине.',
      IsoBlock.overlap =>
        'Здесь уже стоит другая вещь. Выбери свободное место.',
      IsoBlock.feature => want.spec.band == IsoBand.sill
          ? 'Это ставится только на подоконник.'
          : 'Здесь дверь или окно. Выбери другое место на стене.',
      IsoBlock.hero => 'Здесь стоит Финни.',
      IsoBlock.ok => '',
    });
  }

  IsoArrangement _room(IsoRoomSpec spec) => IsoArrangement.resolve(
      spec, IsoRoomScene.presentSlots(widget.decorIds).keys, widget.saved);

  @override
  void didUpdateWidget(IsoRoomScene old) {
    super.didUpdateWidget(old);
    // «Расставить» shows the room whole, as a room opened in it.
    if (widget.arrange && !old.arrange) {
      _follow = false;
      _zoom = 1;
      _centre = null;
    }
    if (!widget.arrange && _dragId != null) {
      _dragId = null;
      _ghost = null;
    }
    final IsoRoomSpec? spec = _spec;
    if (spec != null && widget.finniNear != old.finniNear) {
      final String? near = widget.finniNear;
      if (near != null) _walkTo(spec, near);
    }
  }

  (int, int) _home(IsoRoomSpec spec, IsoArrangement room) {
    final (int, int) home = (spec.finniX, spec.finniY);
    if (!room.blockedCells().contains(home)) return home;
    for (int x = 0; x < spec.grid.cols; x++) {
      for (int y = 0; y < spec.grid.rows; y++) {
        if (!room.blockedCells().contains((x, y))) return (x, y);
      }
    }
    return home;
  }

  /// Where Finni is now (continuous grid point, cell centre at rest).
  ({double x, double y}) _feet((int, int) cell) {
    final ({double x, double y})? free = _free;
    if (free != null && !_walk.isAnimating) return free;
    if (!_walk.isAnimating || _path.length < 2) {
      return (x: cell.$1 + 0.5, y: cell.$2 + 0.5);
    }
    final double t = _walk.value * (_path.length - 1);
    final int i = math.min(t.floor(), _path.length - 2);
    final double f = t - i;
    final (int, int) a = _path[i], b = _path[i + 1];
    return (
      x: a.$1 + (b.$1 - a.$1) * f + 0.5,
      y: a.$2 + (b.$2 - a.$2) * f + 0.5,
    );
  }

  void _walkTo(IsoRoomSpec spec, String target) {
    final IsoArrangement room = _room(spec);
    final (int, int) from = _cell ?? _home(spec, room);
    (int, int)? to;
    if (target == 'door') {
      final IsoFeature d = spec.door;
      to = isoStandCell(
          room,
          IsoPlacement.wall(
              IsoSlotSpec(id: 'door', layer: IsoLayer.wall, len: d.len),
              d.side,
              d.u),
          from);
    } else if (room.placed[IsoRoomScene.objectSlot[target] ?? target]
        case final IsoPlacement p) {
      // The bed is low and wide: Finni right at its side covered its middle
      // (in the morning a finger on the bed patted Finni). He stands one
      // cell further in front when that cell is free.
      if (target == 'bed') to = isoStandBack(room, p, from);
      to ??= isoStandCell(room, p, from);
    }
    if (to != null) _go(spec, room, from, to);
  }

  void _go(
      IsoRoomSpec spec, IsoArrangement room, (int, int) from, (int, int) to) {
    final List<(int, int)>? path = isoPath(
        from, to, room.blockedCells()..remove(from),
        cols: spec.grid.cols, rows: spec.grid.rows);
    if (path == null) return;
    final Duration d =
        context.motion(widget.walkTime ?? const Duration(milliseconds: 450));
    _stickNear = null;
    setState(() {
      _cell = to;
      _free = null;
      _path = <(int, int)>[from, ...path];
    });
    if (d == Duration.zero || path.isEmpty) return;
    _walk
      ..duration = d
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final IsoRoomSpec? spec = _spec;
    if (spec == null) {
      return const ColoredBox(color: IsoColors.wallRight);
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) =>
          _scene(context, spec, Size(box.maxWidth, box.maxHeight)),
    );
  }

  Widget _scene(BuildContext context, IsoRoomSpec spec, Size size) {
    final IsoGrid g = spec.grid;
    final Size content = g.contentSize;
    final double availH = math.max(1, size.height - widget.topInset);
    final AssetRegistry? reg = widget.art?.registry;
    final IsoArrangement room = _room(spec);
    final Map<String, String?> present =
        IsoRoomScene.presentSlots(widget.decorIds);
    final (int, int) cell = _cell ?? _home(spec, room);
    final ({double x, double y}) feet = _feet(cell);
    final String stageName = widget.stage.name;

    // ───────────── camera ─────────────
    // Fit scale: the whole room under the HUD. Zoom multiplies it; the
    // centre is a room point kept inside the room's edges.
    // A wide, low view (a phone on its side, 800×360): the whole room fitted
    // by height came out small (Finni ~45 dp). There the frame leaves out
    // the empty wall tops above the door and the window and the bare floor
    // corner in front — every thing stays in the picture, bigger.
    final bool wide = size.width / availH > IsoRoomScene.wideRatio;
    final double cropTop = wide ? IsoRoomScene.wideCropTop : 0;
    final double frameH =
        content.height - cropTop - (wide ? IsoRoomScene.wideCropBottom : 0);
    final double fit = math.min(
      IsoRoomScene.maxScale,
      math.min(size.width * 0.96 / content.width, availH * 0.96 / frameH),
    );
    final Offset viewCentre =
        Offset(size.width / 2, widget.topInset + availH / 2);
    final Offset roomCentre = Offset(content.width / 2, cropTop + frameH / 2);
    final Offset finniCentre =
        g.toScreen(feet.x, feet.y) - Offset(0, spec.finniH * 0.45);
    final double close =
        IsoRoomScene.closeZoom(finniH: spec.finniH * fit, viewH: availH);
    double zoom;
    Offset centre;
    if (_cam.isAnimating) {
      final double t = Curves.easeInOut.transform(_cam.value);
      final double to = _follow ? close : _zoom;
      zoom = _camFromZoom + (to - _camFromZoom) * t;
      centre = Offset.lerp(_camFromCentre ?? roomCentre,
          _follow ? finniCentre : (_centre ?? roomCentre), t)!;
    } else {
      zoom = _follow ? close : _zoom;
      centre = _follow ? finniCentre : (_centre ?? roomCentre);
    }
    if (widget.cameraFocus != null) {
      zoom = 1;
      centre = roomCentre;
    }
    zoom = zoom.clamp(1.0, IsoRoomScene.maxZoom).toDouble();
    final double k = fit * zoom;
    centre = isoClampCentre(centre, content, Size(size.width, availH), k);
    Offset off = viewCentre - centre * k;
    // A tutorial card needs a strip next to the lit thing: on a tall phone
    // the whole room sits in the middle and leaves two strips too short for
    // the card (its buttons were cut off). While a step points at the room,
    // the room moves up under the HUD and the strip below it is one.
    if (widget.cameraFocus != null && content.height * k < availH - Gap.md) {
      off = Offset(off.dx, widget.topInset + Gap.sm);
    }
    Offset toView(Offset p) => off + p * k;
    Rect rectView(Rect r) => Rect.fromLTRB(off.dx + r.left * k,
        off.dy + r.top * k, off.dx + r.right * k, off.dy + r.bottom * k);

    // While a thing is dragged it is drawn at the ghost's place; the rules
    // still read the room as it stands.
    final String? dragId = _dragId;
    final IsoPlacement? ghost = dragId == null ? null : _ghost;
    final IsoArrangement shown = ghost == null
        ? room
        : (IsoArrangement(spec)
          ..placed.addAll(room.placed)
          ..placed[ghost.id] = ghost);
    final List<(String, Rect)> hits = <(String, Rect)>[];

    String? spriteOf(IsoPlacement p) {
      final String? skin = widget.furnitureSkins[p.id];
      if (skin != null) return reg?.item(skin);
      final String? decor = present[p.id];
      if (decor != null) return reg?.item(decor);
      final String? id = p.spec.sprite?.replaceAll('{stage}', stageName);
      if (id == null) return null;
      return reg?.item(id) ?? reg?.roomObject(id)?.path;
    }

    Size? sizeOf(IsoPlacement p) {
      final String? skin = widget.furnitureSkins[p.id];
      final String? id = skin ??
          present[p.id] ??
          p.spec.sprite?.replaceAll('{stage}', stageName);
      if (id == null) return null;
      final Size? s = reg?.itemSize(id);
      if (s != null) return s;
      final RoomObjectArt? o = reg?.roomObject(id);
      return o == null ? null : Size(o.width, o.height);
    }

    /// Picture rectangle of a floor thing, content px: as wide as its
    /// footprint on screen × fit, bottom at the front corner.
    Rect floorRect(IsoPlacement p) {
      final Rect f = g.footprintRect(
          p.x.toDouble(), p.y.toDouble(), p.x1.toDouble(), p.y1.toDouble());
      if (p.spec.layer == IsoLayer.rug) return f;
      final Size s = sizeOf(p) ?? const Size(1, 1);
      // A tall picture (a skin drawn as a cupboard) is fitted by height:
      // nothing stands taller than [_maxThing] of the wall.
      double w = f.width * p.spec.fit;
      double h = w * s.height / s.width;
      final double maxH = g.wallH * _maxThing;
      if (h > maxH) {
        w *= maxH / h;
        h = maxH;
      }
      final double bottom = f.bottom - g.halfH * 0.35;
      return Rect.fromLTRB(
          f.center.dx - w / 2, bottom - h, f.center.dx + w / 2, bottom);
    }

    final bool arrange = widget.arrange;
    final String? sel = widget.selected;
    final Set<(int, int)> heroCells = <(int, int)>{cell};
    final bool ghostOk =
        ghost == null || room.check(ghost, hero: heroCells) == IsoBlock.ok;

    /// A dragged thing on a refused place is see-through.
    Widget faded(String id, Widget child) =>
        id == dragId && !ghostOk ? Opacity(opacity: 0.55, child: child) : child;

    // ───────────── what a tap does ─────────────
    ({String key, String label, VoidCallback? onTap}) actionOf(String slot) {
      final String? decor = present[slot];
      if (arrange) {
        final String name = _slotName(slot, decor);
        return (
          key: _keyOf(slot, decor),
          label: sel == slot ? '$name, выбрано' : 'Выбрать: $name',
          onTap: widget.onSelect == null ? null : () => widget.onSelect!(slot),
        );
      }
      return switch (slot) {
        'bed' => (
            key: 'room:bed',
            label: 'Кровать — лечь спать',
            onTap: widget.onBedTap
          ),
        'desk_chair' => (
            key: 'room:desk',
            label: 'Стол — работа',
            onTap: widget.onDeskTap
          ),
        'bedside_cabinet' => (
            key: 'room:piggy',
            label: widget.piggySaved == null
                ? 'Копилка'
                : 'Копилка: ${widget.piggySaved} '
                    '${Phrases.coinsNom(widget.piggySaved!)}',
            onTap: widget.onPiggyTap
          ),
        'fridge' => (
            key: 'room:fridge',
            label: fridgeLabel(widget.fridge),
            onTap: widget.onFridgeTap
          ),
        'pet_corner' => (
            key: 'room:iso:pet_corner',
            label: 'Лежанка питомца',
            onTap:
                widget.onWalkTo == null ? null : () => widget.onWalkTo!(slot),
          ),
        _ => (
            key: _keyOf(slot, decor),
            label: _slotName(slot, decor),
            onTap:
                widget.onWalkTo == null ? null : () => widget.onWalkTo!(slot),
          ),
      };
    }

    Widget thing(IsoPlacement p, Rect pic, {Widget? extra}) {
      final String? path = spriteOf(p);
      final ({String key, String label, VoidCallback? onTap}) a =
          actionOf(p.id);
      final Rect r = rectView(pic);
      final Rect zone = _atLeast(r, TapSize.min);
      hits.add((p.id, zone));
      return Positioned.fromRect(
        key: ValueKey<String>('room:iso:slot:${p.id}'),
        rect: zone,
        child: _IsoTap(
          key: ValueKey<String>(a.key),
          label: a.label,
          onTap: a.onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: r.left - zone.left,
                top: r.top - zone.top,
                width: r.width,
                height: r.height,
                child: faded(
                    p.id,
                    path == null
                        ? CustomPaint(
                            painter:
                                IsoStubPainter(p.spec.layer == IsoLayer.rug))
                        : Image.asset(
                            path,
                            fit: BoxFit.contain,
                            alignment: Alignment.bottomCenter,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, __, ___) => CustomPaint(
                                painter: IsoStubPainter(
                                    p.spec.layer == IsoLayer.rug)),
                          )),
              ),
              if (extra != null) extra,
            ],
          ),
        ),
      );
    }

    Widget wallThing(IsoPlacement p) {
      final (double lo, double hi) = spec.bandOf(p.spec.band);
      final Rect band =
          _wallRect(g, p.side!, p.u.toDouble(), p.spec.len.toDouble(), lo, hi);
      final String? path = spriteOf(p);
      final ({String key, String label, VoidCallback? onTap}) a =
          actionOf(p.id);
      // A wall thing stands [_wallLift] cells off the wall toward the room:
      // a shadow on the wall, a darker body (its thickness), the picture on
      // top. Code only, from the same picture (Денис 19.10: «плоско»).
      final Offset lift = g.wallNormal(p.side!) * (_wallLift * k);
      final Rect flat = rectView(band);
      final Rect r = flat.expandToInclude(flat.shift(lift));
      final Rect zone = _atLeast(r, TapSize.min);
      hits.add((p.id, zone));
      // The picture is drawn frontally, sheared onto the wall plane.
      final Offset tl = toView(
          _wallCorner(g, p.side!, p.u.toDouble(), p.spec.len.toDouble(), hi));
      final Offset tr = toView(_wallCorner(
          g, p.side!, p.u.toDouble(), p.spec.len.toDouble(), hi,
          right: true));
      final double hpx = (hi - lo) * k;
      Widget layer(Offset at, {Color? tint, BlendMode? mode}) => Positioned(
            left: at.dx - zone.left,
            top: at.dy - zone.top,
            width: 100,
            height: 100,
            child: Transform(
              alignment: Alignment.topLeft,
              transform: _shear(tr - tl, hpx),
              child: path == null
                  ? (tint == null
                      ? const CustomPaint(painter: IsoStubPainter(false))
                      : const SizedBox.shrink())
                  : Image.asset(path,
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                      filterQuality: FilterQuality.medium,
                      color: tint,
                      colorBlendMode: mode,
                      errorBuilder: (_, __, ___) => tint == null
                          ? const CustomPaint(painter: IsoStubPainter(false))
                          : const SizedBox.shrink()),
            ),
          );
      return Positioned.fromRect(
        key: ValueKey<String>('room:iso:slot:${p.id}'),
        rect: zone,
        child: _IsoTap(
          key: ValueKey<String>(a.key),
          label: a.label,
          onTap: a.onTap,
          child: faded(
            p.id,
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                layer(tl + Offset(0, 4 * k),
                    tint: IsoColors.wallShadow, mode: BlendMode.srcIn),
                for (int i = 1; i <= 3; i++)
                  layer(tl + lift * (i / 4),
                      tint: IsoColors.body, mode: BlendMode.modulate),
                layer(tl + lift),
              ],
            ),
          ),
        ),
      );
    }

    // ───────────── draw order ─────────────
    const String finniId = '~finni';
    const String petId = '~pet';
    final IsoPlacement? petBed = shown.placed['pet_corner'];
    (int, int)? petCell;
    if (widget.petId != null && petBed != null) {
      petCell = widget.petAwake
          ? isoStandCell(shown, petBed, (petBed.x, petBed.y + 1))
          : (petBed.x, petBed.y);
    }
    final List<IsoBox> boxes = <IsoBox>[
      for (final IsoPlacement p in shown.placed.values)
        if (!p.isWall && p.spec.layer != IsoLayer.rug) p.box,
      IsoBox.mover(finniId, feet.x, feet.y, spec.finniR),
      if (petCell != null)
        IsoBox.mover(petId, petCell.$1 + 0.5, petCell.$2 + 0.5,
            widget.petAwake ? 0.2 : 0.45),
    ];
    final List<IsoBox> order = isoDepthOrder(boxes).order;

    Widget finniWidget() {
      final SpriteRef? sheet = reg?.finni(widget.species);
      final SpriteRef? walk = reg?.finniWalk(widget.species);
      // Walks along a path (a tap on a thing) or under the joystick: the
      // joystick is the main way to move, he must not glide standing.
      final bool moving =
          _walk.isAnimating || (_sticking && _padKnob != Offset.zero);
      // Faces the way he goes, on screen (the pictures look right).
      final Offset here = g.toScreen(feet.x, feet.y);
      final Offset? was = _lastFeet;
      if (was != null && (here.dx - was.dx).abs() > 0.01) {
        _faceLeft = here.dx < was.dx;
      }
      _lastFeet = here;
      final Offset f = toView(here);
      final double h = spec.finniH * k;
      final double w = h * 0.76;
      final String? pose = widget.finniPose;
      final SpriteRef? poseSheet =
          pose != null && (reg?.finniHasPose(widget.species, pose) ?? false)
              ? reg?.finniPoses(widget.species)
              : null;
      final bool walking = moving && walk != null;
      // Both pictures stay built (the hidden one paused): starting and
      // stopping the joystick swaps them at once, without a blank frame
      // while a sheet loads.
      final Widget picture = sheet == null
          ? const CustomPaint(painter: IsoStubPainter(false))
          : Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Visibility(
                  visible: !walking,
                  maintainState: true,
                  child: SpriteAnim(
                      key: ValueKey<String>(
                          'room:finni:pose:${poseSheet != null && !moving ? pose : widget.idleTag}'),
                      sprite: poseSheet != null && !moving ? poseSheet : sheet,
                      tag: poseSheet != null && !moving ? pose : widget.idleTag,
                      // Standing: breathes (the two idle frames are nearly
                      // the same picture).
                      breathe: true,
                      height: h),
                ),
                if (walk != null)
                  Visibility(
                    visible: walking,
                    maintainState: true,
                    child: SpriteAnim(
                        key: const ValueKey<String>('room:finni:walk'),
                        sprite: walk,
                        tag: 'walk-${widget.idleTag.replaceFirst('idle-', '')}',
                        height: h),
                  ),
              ],
            );
      // Turned and hopping inside the picture's box: the touch zone and
      // the badge over his head ([finniKey]) stay put.
      final Widget sprite = AnimatedBuilder(
        animation: _hop,
        builder: (BuildContext context, Widget? child) => Transform.translate(
          offset: Offset(0, -math.sin(_hop.value * math.pi) * h * _hopLift),
          child: child,
        ),
        child: Transform.flip(flipX: _faceLeft, child: picture),
      );
      // The picture keeps its size; the touch zone is at least a finger
      // (a small room on a phone on its side shrinks Finni below 48 dp).
      final Rect pic = Rect.fromLTWH(f.dx - w / 2, f.dy - h * 0.97, w, h);
      final Rect zone = _atLeast(pic, TapSize.min);
      return Positioned.fromRect(
        key: const ValueKey<String>('room:finni:spot'),
        rect: zone,
        child: Semantics(
          button: true,
          label: '${widget.finniName}. Настроение ${widget.happiness}',
          excludeSemantics: true,
          onTap: widget.onFinniTap == null ? null : _patFinni,
          child: GestureDetector(
            key: const ValueKey<String>('room:finni'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onFinniTap == null ? null : _patFinni,
            child: Center(
              child: SizedBox(
                width: w,
                height: h,
                child: KeyedSubtree(
                  key: widget.finniKey,
                  child: IgnorePointer(child: sprite),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget petWidget((int, int) c) {
      final SpriteRef? sheet = reg?.pet(widget.petId!);
      final Offset f = toView(g.cellCenter(c.$1, c.$2));
      final double h = spec.petH * k;
      final Rect r = Rect.fromLTWH(f.dx - h * 0.7, f.dy - h, h * 1.4, h);
      final Rect zone = _atLeast(r, TapSize.min);
      return Positioned.fromRect(
        rect: zone,
        child: Semantics(
          button: widget.onPetTap != null,
          label: 'Питомец',
          excludeSemantics: true,
          onTap: widget.onPetTap,
          child: GestureDetector(
            key: ValueKey<String>('room:pet:${widget.petId}'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPetTap,
            child: Align(
              // Centred: the zone grows evenly from the picture.
              alignment: Alignment.center,
              child: SizedBox(
                width: r.width,
                height: r.height,
                child: sheet == null
                    ? const CustomPaint(painter: IsoStubPainter(false))
                    : SpriteAnim(
                        sprite: sheet,
                        tag: widget.petAwake ? 'wake' : 'sleep',
                        height: h),
              ),
            ),
          ),
        ),
      );
    }

    Widget? piggyOn(IsoPlacement cab, Rect cabPic) {
      final String? path = reg?.item('room_piggy');
      final Rect r = rectView(cabPic);
      final Rect zone = _atLeast(r, TapSize.min);
      final double w = r.width * 0.62;
      final Size s = reg?.itemSize('room_piggy') ?? const Size(1, 1);
      final double h = w * s.height / s.width;
      return Positioned(
        left: r.center.dx - w / 2 - zone.left,
        top: r.top - h * 0.8 - zone.top,
        width: w,
        height: h,
        child: IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              if (path != null)
                Positioned.fill(
                    child: Image.asset(path,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink())),
              if (widget.piggySaved != null && !arrange)
                Positioned(
                  // As wide as the front room's label: four digits fit.
                  left: w / 2 - 60,
                  width: 120,
                  bottom: h + 2,
                  child: ExcludeSemantics(
                    child: Center(
                      child: PiggyAmount(
                        key: const ValueKey<String>('room:piggy:amount'),
                        amount: widget.piggySaved!,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // ───────────── arrange: where the selected thing fits ─────────────
    final IsoPlacement? selP = sel == null ? null : room.placed[sel];
    final Set<(int, int)> okCells = <(int, int)>{};
    final Set<(IsoWall, int)> okWall = <(IsoWall, int)>{};
    if (arrange && selP != null) {
      if (selP.isWall) {
        for (final IsoWall side in IsoWall.values) {
          for (int u = 0; u < g.wallLen(side); u++) {
            if (room.check(IsoPlacement.wall(selP.spec, side, u)) ==
                IsoBlock.ok) {
              okWall.add((side, u));
            }
          }
        }
      } else {
        for (int x = 0; x < g.cols; x++) {
          for (int y = 0; y < g.rows; y++) {
            if (room.check(IsoPlacement.floor(selP.spec, x, y),
                    hero: heroCells) ==
                IsoBlock.ok) {
              okCells.add((x, y));
            }
          }
        }
      }
    }

    void place(IsoPlacement want) => _place(room, want, heroCells);

    void tapCell(int x, int y) {
      if (!arrange) {
        if (room.blockedCells().contains((x, y))) return;
        _go(spec, room, cell, (x, y));
        return;
      }
      if (selP == null) {
        widget.onRefuse?.call('Сначала выбери вещь: нажми на неё.');
        return;
      }
      if (selP.isWall) {
        widget.onRefuse?.call('Эта вещь вешается на стену.');
        return;
      }
      place(IsoPlacement.floor(selP.spec, x, y));
    }

    void tapWall(IsoWall side, int u) {
      if (!arrange) return;
      if (selP == null) {
        widget.onRefuse?.call('Сначала выбери вещь: нажми на неё.');
        return;
      }
      if (!selP.isWall) {
        widget.onRefuse?.call('Эта вещь ставится на пол.');
        return;
      }
      place(IsoPlacement.wall(selP.spec, side, u));
    }

    // Built in draw order, so [hits] runs back to front.
    final List<Widget> walls = <Widget>[
      for (final IsoPlacement p in shown.placed.values)
        if (p.isWall) wallThing(p),
    ];
    final List<Widget> rugs = <Widget>[
      for (final IsoPlacement p in shown.placed.values)
        if (p.spec.layer == IsoLayer.rug) thing(p, floorRect(p)),
    ];
    final Rect doorRect = _wallRect(g, spec.door.side, spec.door.u + 0.15,
        spec.door.len - 0.3, 0, spec.door.top);
    final List<Widget> standing = <Widget>[
      for (final IsoBox b in order)
        if (b.id == finniId)
          finniWidget()
        else if (b.id == petId)
          petWidget(petCell!)
        else if (shown.placed[b.id] case final IsoPlacement p)
          p.id == 'bedside_cabinet'
              ? thing(p, floorRect(p), extra: piggyOn(p, floorRect(p)))
              : thing(p, floorRect(p)),
    ];
    _view = (
      spec: spec,
      room: room,
      hero: heroCells,
      fit: fit,
      zoom: zoom,
      k: k,
      off: off,
      centre: centre,
      viewCentre: viewCentre,
      content: content,
      viewSize: Size(size.width, availH),
      hits: hits,
    );

    final Widget sceneStack = Stack(
      clipBehavior: Clip.hardEdge,
      children: <Widget>[
        Positioned.fill(
          child: CustomPaint(
            key: const ValueKey<String>('room:iso:shell'),
            painter: IsoShellPainter(
              spec: spec,
              k: k,
              offset: off,
              arrange: arrange,
              okCells: okCells,
              okWall: okWall,
              selected: arrange && ghost == null ? selP : null,
              ghost: ghost,
              ghostOk: ghostOk,
              grounded: <IsoPlacement>[
                for (final IsoPlacement p in shown.placed.values)
                  if (!p.isWall && p.spec.layer != IsoLayer.rug) p,
              ],
            ),
          ),
        ),
        // One detector for the floor and the walls: the diamond under the
        // finger, not a rectangle around it.
        // No node of its own for TalkBack: things, cells and wall slots
        // have theirs; a nameless 360 dp «button» would only confuse.
        Positioned.fill(
          child: ExcludeSemantics(
            child: GestureDetector(
              key: const ValueKey<String>('room:iso:floor'),
              behavior: HitTestBehavior.translucent,
              onTapUp: (TapUpDetails d) {
                final Offset p = (d.localPosition - off) / k;
                final (int, int)? c = g.cellAt(p);
                if (c != null) return tapCell(c.$1, c.$2);
                final IsoWallPoint? w = g.wallAt(p);
                if (w != null) tapWall(w.side, w.u.floor());
              },
            ),
          ),
        ),
        // Door: the game's picture sheared onto the left wall, set back in
        // its opening; the frame is painted over its edges.
        _door(reg, rectView(doorRect), toView, g, spec),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: IsoDoorFramePainter(spec: spec, k: k, offset: off),
            ),
          ),
        ),
        ...walls,
        ...rugs,
        ...standing,
        // TalkBack: in «Расставить» every cell and wall slot is its own
        // node (room-lab A could not be used with TalkBack on). The node is
        // at least a finger; touch still goes to the diamond detector.
        // The ghost's outline over the furniture: a refused place is often
        // under another thing.
        if (ghost != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const ValueKey<String>('room:iso:ghost'),
                painter: IsoGhostPainter(
                    spec: spec, k: k, offset: off, ghost: ghost, ok: ghostOk),
              ),
            ),
          ),
        if (arrange)
          for (int x = 0; x < g.cols; x++)
            for (int y = 0; y < g.rows; y++)
              Positioned.fromRect(
                rect: _atLeast(
                    rectView(g.footprintRect(
                        x.toDouble(), y.toDouble(), x + 1.0, y + 1.0)),
                    TapSize.min),
                child: Semantics(
                  key: ValueKey<String>('room:iso:cell:$x:$y'),
                  button: true,
                  label: 'Клетка пола, ряд ${y + 1}, место ${x + 1}: '
                      '${okCells.contains((
                        x,
                        y
                      )) ? 'можно поставить' : room.itemAtCell(x, y) == null ? 'свободно' : 'занято'}',
                  onTap: () => tapCell(x, y),
                  child: const SizedBox.expand(),
                ),
              ),
        if (arrange)
          for (final IsoWall side in IsoWall.values)
            for (int u = 0; u < g.wallLen(side); u++)
              Positioned.fromRect(
                rect: _atLeast(
                    rectView(_wallRect(g, side, u.toDouble(), 1,
                        spec.bandBottom, spec.bandTop)),
                    TapSize.min),
                child: Semantics(
                  key: ValueKey<String>('room:iso:wall:${side.name}:$u'),
                  button: true,
                  label: '${side == IsoWall.left ? 'Левая' : 'Правая'} стена, '
                      'место ${u + 1}'
                      '${okWall.contains((side, u)) ? ': можно повесить' : ''}',
                  onTap: () => tapWall(side, u),
                  child: const SizedBox.expand(),
                ),
              ),
      ],
    );
    final Widget? above = widget.aboveFinni;
    final bool zoomed = _follow || zoom > 1.01;
    // Clipped: the walls and the floor that continue past the room (tall
    // screens) are painted beyond the scene's box and covered the menu rail
    // on its left (n6-room 20.10).
    return ClipRect(
        child: ColoredBox(
      color: IsoColors.back,
      child: Stack(
        children: <Widget>[
          // Camera and drag: one scale detector over the whole scene. Taps
          // still reach the things and the floor (a tap never moves past
          // the slop, so the scale detector does not take it).
          Positioned.fill(
            child: Listener(
              onPointerDown: (PointerDownEvent e) {
                _downAt = _fingers == 0 ? e.localPosition : null;
                _fingers++;
              },
              onPointerUp: (PointerUpEvent _) =>
                  _fingers = math.max(0, _fingers - 1),
              onPointerCancel: (PointerCancelEvent _) {
                _fingers = math.max(0, _fingers - 1);
                _cancelled = true;
              },
              child: GestureDetector(
                key: const ValueKey<String>('room:iso:gestures'),
                onScaleStart: _scaleStart,
                onScaleUpdate: _scaleUpdate,
                onScaleEnd: _scaleEnd,
                child: sceneStack,
              ),
            ),
          ),
          // Top left: the top right of the room screen holds the «!» of the
          // week's event.
          if (widget.cameraFocus == null)
            Positioned(
              left: Gap.sm,
              top: widget.topInset + Gap.sm,
              child: _CameraButton(zoomed: zoomed, onTap: _toggleCamera),
            ),
          // Joystick at rest, pale (as in the front room): it says «draw a
          // finger over the floor». Bottom left: the screen's main button
          // lies on the bottom right of the scene.
          if (widget.onStickNear != null &&
              !widget.arrange &&
              widget.cameraFocus == null &&
              _padCenter == null)
            const Positioned(
              left: Gap.sm,
              bottom: Gap.sm,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.55,
                  child: JoystickPad(
                      key: ValueKey<String>('room:iso:joystick'),
                      knob: Offset.zero,
                      size: IsoRoomScene.stickSize),
                ),
              ),
            ),
          if (_padCenter case final Offset c)
            Positioned(
              left: c.dx - IsoRoomScene.stickSize / 2,
              top: c.dy - IsoRoomScene.stickSize / 2,
              child: IgnorePointer(
                child: JoystickPad(
                    key: const ValueKey<String>('room:iso:pad'),
                    knob: _padKnob,
                    size: IsoRoomScene.stickSize),
              ),
            ),
          if (above != null && widget.finniKey != null)
            Positioned.fill(
              child: FinniBadgeLayer(
                finniKey: widget.finniKey!,
                topLimit: widget.topInset,
                child: above,
              ),
            ),
        ],
      ),
    ));
  }

  Widget _door(AssetRegistry? reg, Rect r, Offset Function(Offset) toView,
      IsoGrid g, IsoRoomSpec spec) {
    final IsoFeature d = spec.door;
    final String? path = reg?.roomObject('door')?.path;
    final Rect zone = _atLeast(r, TapSize.min);
    // The leaf stands at the back of the opening ([isoDoorRecess] cells
    // into the wall); the frame painter draws the jamb in front of it.
    final Offset back =
        toView(g.wallNormal(d.side) * -isoDoorRecess) - toView(Offset.zero);
    final Offset tl =
        toView(_wallCorner(g, d.side, d.u + 0.15, d.len - 0.3, d.top)) + back;
    final Offset tr = toView(_wallCorner(
            g, d.side, d.u + 0.15, d.len - 0.3, d.top,
            right: true)) +
        back;
    final double hpx = (d.top - d.bottom) *
        (toView(const Offset(0, 1)) - toView(Offset.zero)).dy;
    final bool can = !widget.arrange && widget.onDoorTap != null;
    // The set-back leaf is seen only through the opening.
    final List<Offset> opening = <Offset>[
      for (final (double u, double h) in <(double, double)>[
        (d.u + 0.15, 0),
        (d.u + d.len - 0.15, 0),
        (d.u + d.len - 0.15, d.top),
        (d.u + 0.15, d.top),
      ])
        toView(g.wallToScreen(d.side, u, h)) - zone.topLeft,
    ];
    return Positioned.fromRect(
      key: const ValueKey<String>('room:iso:slot:door'),
      rect: zone,
      child: _IsoTap(
        key: const ValueKey<String>('room:door'),
        label: 'Дверь — в город',
        onTap: can ? widget.onDoorTap : null,
        child: ClipPath(
          clipper: _PolyClip(opening),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: tl.dx - zone.left,
                top: tl.dy - zone.top,
                width: 100,
                height: 100,
                child: Transform(
                  alignment: Alignment.topLeft,
                  transform: _shear(tr - tl, hpx),
                  child: path == null
                      ? const CustomPaint(painter: IsoDoorPainter())
                      : Image.asset(path,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) =>
                              const CustomPaint(painter: IsoDoorPainter())),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Clip to a polygon given in the child's px.
class _PolyClip extends CustomClipper<Path> {
  const _PolyClip(this.points);
  final List<Offset> points;

  @override
  Path getClip(Size size) => Path()..addPolygon(points, true);

  @override
  bool shouldReclip(_PolyClip old) => !listEquals(old.points, points);
}

/// Name of a place for TalkBack.
String _slotName(String slot, String? decor) => switch (slot) {
      'bed' => 'Кровать',
      'desk_chair' => 'Стол',
      'bedside_cabinet' => 'Тумба с копилкой',
      'fridge' => 'Холодильник',
      'pet_corner' => 'Лежанка питомца',
      'decor_wall' => 'Постер',
      'decor_floor' => 'Растение',
      'decor_ceiling' => 'Светильник',
      'item_sill' => 'Вещь на подоконнике',
      'decor_books' => 'Книги',
      'decor_globe' => 'Глобус',
      'decor_bear' => 'Мишка',
      'decor_rug' => 'Коврик',
      _ => decor ?? slot,
    };

/// Tap key of a place: front keys for decor (`room:decor:<id>`).
String _keyOf(String slot, String? decor) => switch (slot) {
      'bed' => 'room:bed',
      'desk_chair' => 'room:desk',
      'bedside_cabinet' => 'room:piggy',
      'fridge' => 'room:fridge',
      'pet_corner' => 'room:iso:pet_corner',
      _ => decor == null ? 'room:iso:$slot' : 'room:decor:$decor',
    };

/// Top-left (or top-right) corner of a wall area, as seen on screen: the
/// left wall runs right to left with u.
Offset _wallCorner(IsoGrid g, IsoWall side, double u0, double len, double h,
        {bool right = false}) =>
    side == IsoWall.left
        ? g.wallToScreen(side, right ? u0 : u0 + len, h)
        : g.wallToScreen(side, right ? u0 + len : u0, h);

/// Bounding box of a wall area [u0, u0+len) × [lo, hi] px above the floor.
Rect _wallRect(
    IsoGrid g, IsoWall side, double u0, double len, double lo, double hi) {
  final List<Offset> q = <Offset>[
    g.wallToScreen(side, u0, lo),
    g.wallToScreen(side, u0 + len, lo),
    g.wallToScreen(side, u0 + len, hi),
    g.wallToScreen(side, u0, hi),
  ];
  double l = double.infinity, t = double.infinity;
  double r = -double.infinity, b = -double.infinity;
  for (final Offset o in q) {
    l = math.min(l, o.dx);
    t = math.min(t, o.dy);
    r = math.max(r, o.dx);
    b = math.max(b, o.dy);
  }
  return Rect.fromLTRB(l, t, r, b);
}

/// Zone not smaller than a finger: grows from the centre.
Rect _atLeast(Rect r, double min) => Rect.fromCenter(
      center: r.center,
      width: math.max(r.width, min),
      height: math.max(r.height, min),
    );

/// Maps a 100 × 100 box onto a wall parallelogram: top edge [top], height
/// [h] straight down (column-major).
Matrix4 _shear(Offset top, double h) => Matrix4(
    top.dx / 100,
    top.dy / 100,
    0,
    0, //
    0,
    h / 100,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1);

/// How far a wall thing stands off the wall, cells toward the room.
const double _wallLift = 0.08;

/// Tallest floor thing, as a share of the wall height.
const double _maxThing = 0.8;

/// Camera centre (room px) moved so the room covers the view on each axis
/// where it is bigger than the view, and centred where it is smaller.
Offset isoClampCentre(Offset c, Size content, Size view, double k) {
  double axis(double v, double len, double vis) {
    final double half = vis / 2 / k;
    if (len <= 2 * half) return len / 2;
    return v.clamp(half, len - half).toDouble();
  }

  return Offset(axis(c.dx, content.width, view.width),
      axis(c.dy, content.height, view.height));
}

/// Continuous grid point under a room point, as an offset (x, y).
Offset _gridOf(IsoGrid g, Offset c) {
  final ({double x, double y}) p = g.toGrid(c);
  return Offset(p.x, p.y);
}

/// Slot coordinate along [side] under a room point.
double _wallU(IsoGrid g, IsoWall side, Offset c) => side == IsoWall.left
    ? (g.origin.dx - c.dx) / g.halfW
    : (c.dx - g.origin.dx) / g.halfW;

/// «К Финни» / «Вся комната»: a finger-sized button over the scene.
class _CameraButton extends StatelessWidget {
  const _CameraButton({required this.zoomed, required this.onTap});

  final bool zoomed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: zoomed ? 'Показать всю комнату' : 'Приблизить к Финни',
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          key: const ValueKey<String>('room:iso:camera'),
          color: IsoColors.ink,
          borderRadius: BorderRadius.circular(WorldRadii.button),
          child: InkWell(
            borderRadius: BorderRadius.circular(WorldRadii.button),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  minWidth: TapSize.min, minHeight: TapSize.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(zoomed ? Icons.zoom_out_map : Icons.zoom_in,
                        color: Colors.white, size: 22),
                    const SizedBox(width: Gap.xs),
                    Text(zoomed ? 'Вся комната' : 'К Финни',
                        maxLines: 1,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// A thing that can be pressed: a TalkBack button and a short press
/// feedback. Copy of the front room's `_RoomTap` without its follow-camera
/// part: the iso camera lives in the scene (zoom over the fit scale).
class _IsoTap extends StatefulWidget {
  const _IsoTap({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_IsoTap> createState() => _IsoTapState();
}

class _IsoTapState extends State<_IsoTap> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) {
      return IgnorePointer(child: ExcludeSemantics(child: widget.child));
    }
    final Duration d = MediaQuery.maybeDisableAnimationsOf(context) ?? false
        ? Duration.zero
        : const Duration(milliseconds: 90);
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: d,
          scale: _down ? 0.96 : 1,
          alignment: Alignment.bottomCenter,
          child: widget.child,
        ),
      ),
    );
  }
}
