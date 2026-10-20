import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/feel.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../domain/world/contract.dart';
import '../../../domain/world/fridge_stock.dart';
import '../joystick.dart';
import '../room_iso/iso_room_scene.dart';
import '../world_explain.dart';
import '../world_help.dart';
import '../world_routes.dart';
import '../world_layout.dart';
import '../tutorial/tutorial_steps.dart' show tutorialRoomFocus;
import '../world_dock.dart';
import '../world_state.dart';
import 'day_energy_looks.dart';
import 'finni_reaction.dart';
import 'room_hud.dart';
import 'room_scene.dart';
import 'room_skins.dart';
import 'hud_strip.dart';
import 'hud_chips.dart';
import 'world_hud.dart';
import '../../../core/world_theme.dart';
import '../pic_text.dart';

/// S1 — комната Финни сбоку, HUD, полоса «Цель» и карточка «Сейчас»
/// (`docs/game/screen-home-room.md`).
///
/// Показатели сверху (HUD и полоса цели), управление снизу (фидбек
/// дизайнера 28.09, п. 2).
///
/// 🔴 Всё на 360 × 640 без прокрутки и при шрифте 1,3 без обрезки
/// (ТЗ 2.5.3.1): комната берёт остаток высоты и масштабируется целым шагом.
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key});

  /// Вариант раскладки: строка цели поверх сцены (В2) или в нижней панели
  /// (В1) — см. [_RoomScreenState.goalOverScene].
  static const bool goalOverScene = _RoomScreenState.goalOverScene;

  /// Разделы нижнего меню по макету Алины (18.10, `alina-01`): Дом · Город ·
  /// План (неделя: план и копилка) · Мой путь (прогресс) · Ещё (бывшее ⋮).
  /// Ключи `room:nav:<id>`; «Ещё» открывает меню `room:menu`.
  static const List<String> navIds = <String>[
    'home',
    'city',
    'week',
    'progress',
    'more',
  ];

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

/// Ближайший шаг — главная кнопка «Сейчас: …» (ТЗ 3.6.2).
class _NextStep {
  const _NextStep(this.text, this.button, this.onTap, {this.why});

  /// Подсказка целиком — для TalkBack и для кровати вне недели.
  final String text;

  /// Короткое действие на кнопке: «Сейчас: в город».
  final String button;

  /// Почему этот шаг — второй строкой на кнопке. Без неё «Сейчас: на
  /// смену» выглядит приказом без причины (путь ребёнка 16.10, дефект 3):
  /// причина раньше была только в тексте для TalkBack.
  final String? why;
  final VoidCallback onTap;
}

class _RoomScreenState extends State<RoomScreen>
    with SingleTickerProviderStateMixin {
  late final Future<RoomArt> _art = RoomArt.load();
  bool _petAwake = false;

  /// Режим «Расставить» (кастомизация комнаты, флаг room.customize):
  /// выбранная вещь и строка «что получилось / почему нельзя».
  bool _arrange = false;
  String? _sel;
  String? _arrangeSay;

  void _arrangeOn() => setState(() {
        _arrange = true;
        _sel = null;
        _arrangeSay = null;
        _free = null;
      });

  void _arrangeOff() => setState(() {
        _arrange = false;
        _sel = null;
        _arrangeSay = null;
      });

  /// Касание клетки: выбранная вещь встаёт туда (или отказ со словами).
  void _cellTap(int x, int y) {
    final String? id = _sel;
    if (id == null) {
      setState(() => _arrangeSay = 'Сначала выбери вещь внизу.');
      return;
    }
    final WorldResult r = _state.act((World w) => w.placeRoomItem(id, x, y));
    setState(
      () => _arrangeSay = r.ok
          ? r.reason
          : (r.nextStep == null ? r.reason : '${r.reason} ${r.nextStep}.'),
    );
  }

  /// Iso-комната (V2): выбранное место встало в клетку или слот стены.
  void _isoPlace(String slot, RoomIsoSpot spot) {
    final WorldResult r = _state
        .act((World w) => w.placeRoomIso(slot, spot.plane, spot.x, spot.y));
    setState(() => _arrangeSay = r.ok
        ? r.reason
        : (r.nextStep == null ? r.reason : '${r.reason} ${r.nextStep}.'));
  }

  void _removeSel() {
    final String? id = _sel;
    if (id == null) return;
    final WorldResult r = _state.act((World w) => w.removeRoomItem(id));
    setState(() => _arrangeSay = r.reason);
  }

  /// Реакция Финни (вариант A): снимок мира, который ребёнок уже видел в
  /// комнате. Решения с других экранов сравниваются при возврате — пока
  /// комната под другим экраном, снимок не обновляется.
  ResourceSnapshot? _seen;
  FinniReaction? _reaction;
  int _hearts = 0;
  Timer? _reactionTimer;

  /// Спрайт Финни — над ним строка состояния ([FinniBadgeLayer]).
  final GlobalKey _finniKey = GlobalKey();

  /// Сколько держится поза и строка реакции.
  static const Duration reactionTime = Duration(milliseconds: 1500);

  /// Причина настроения по касанию Финни — длиннее, её читают.
  static const Duration reasonTime = Duration(milliseconds: 3000);

  /// Раскладка сцены для хода джойстиком (px фона) — от [RoomScene].
  RoomGeometry? _geo;

  /// Где Финни, если его водят джойстиком (ноги, px фона); null — стоит
  /// на своём месте или у предмета, к которому подошёл по касанию.
  Offset? _free;

  /// Где лежит джойстик поверх сцены (координаты сцены); null — его нет.
  Rect? _stickRect;

  /// Плавающий джойстик (Денис 29.09: «снизу слишком много кнопок»): его не
  /// видно, пока палец не лёг на пол и не повёл. Центр — где коснулись;
  /// null — не показан.
  Offset? _padCenter;
  Offset _padKnob = Offset.zero;

  /// Ход ручки — как у [Joystick]: ручка целиком внутри круга.
  static const double _padTravel = stickSize / 2 - stickSize * 0.21;

  void _padStart(Offset at) => setState(() {
        _padCenter = at;
        _padKnob = Offset.zero;
      });

  void _padMove(Offset at) {
    final Offset? c = _padCenter;
    if (c == null) return;
    Offset d = at - c;
    if (d.distance > _padTravel) d = d / d.distance * _padTravel;
    setState(() => _padKnob = d);
    _stick(d / _padTravel);
  }

  void _padEnd() {
    if (_padCenter == null) return;
    _stick(Offset.zero);
    setState(() => _padCenter = null);
  }

  /// Ручка джойстика отведена — Финни идёт.
  bool _moving = false;

  /// Предмет, у которого Финни остановился джойстиком: над ним кнопка
  /// действия.
  String? _nearFree;

  /// Двигатель джойстика — создаётся при первом касании ручки. 🔴 Не
  /// `late final`: иначе dispose() создавал бы тикер уже после
  /// деактивации (TickerMode ищет предка — падение на Flutter 3.41.7, CI
  /// 29.09), если ручку ни разу не трогали.
  JoystickDriver? _driveOrNull;
  JoystickDriver get _drive =>
      _driveOrNull ??= JoystickDriver(this, onStep: _step);

  /// Скорость хода джойстиком: полвысоты комнаты в секунду — через всю
  /// комнату меньше чем за 2 с.
  static const double _speed = 0.55;

  @override
  void dispose() {
    _reactionTimer?.cancel();
    _driveOrNull?.dispose();
    super.dispose();
  }

  /// Шаг от джойстика: Финни идёт в пределах пола ([RoomGeometry.walk]) и
  /// мимо мебели ([RoomGeometry.move]) — и плавно, и шагами по 250 мс.
  void _step(double seconds, Offset dir) {
    final RoomGeometry? g = _geo;
    if (g == null || !mounted) return;
    final Offset from = _free ?? g.feet;
    final Offset to = from + dir * (g.unit * _speed * seconds);
    final Offset kept = g.move(from, to);
    // Джойстик плавающий — рисуется под пальцем, где бы ни стоял Финни:
    // запрета заходить на его место больше нет (с общей раскладкой запрет
    // не пускал Финни к кровати).
    setState(() {
      _free = kept;
      _moving = true;
      _near = null;
      _nearFree = g.nearest(kept);
    });
  }

  void _stick(Offset dir) {
    _drive.set(dir, stepped: !context.motionOn);
    if (!_drive.moving && _moving) setState(() => _moving = false);
  }

  /// Действие предмета, у которого Финни стоит (кнопка над джойстиком).
  void _actNear(String object) => switch (object) {
        'bed' => _tapBed(),
        'fridge' => _go(WorldRoutes.shop),
        'piggy' => _go(WorldRoutes.piggy),
        'desk' => _go(WorldRoutes.jobs),
        _ => _go(WorldRoutes.city),
      };

  /// Кнопка действия у предмета — в том углу сцены, где она не ложится
  /// на Финни (ревью 29.09: «Копилка» сидела у него на лице): справа
  /// вверху, справа внизу, слева под табличкой имени, слева внизу.
  Widget _nearAt(BoxConstraints box, String object, {Rect? avoid}) {
    final RoomGeometry? g = _geo;
    final Offset? at = _free;
    final Rect? finni = g == null || at == null ? null : g.finniOnScreen(at);
    // Ширина места под кнопку: подпись ужимается в нём (FittedBox).
    final double w = math.min(180, box.maxWidth - 2 * Gap.xs);
    const double h = TapSize.min + 24;
    const double left = Gap.xs;
    // Верхние места — под показателями поверх сцены, не на них.
    final double top = hudOverlayHeight;
    final List<(Rect, Alignment)> spots = <(Rect, Alignment)>[
      (Rect.fromLTWH(box.maxWidth - Gap.xs - w, top, w, h), Alignment.topRight),
      (
        Rect.fromLTWH(
          box.maxWidth - Gap.xs - w,
          box.maxHeight - Gap.xs - h,
          w,
          h,
        ),
        Alignment.bottomRight,
      ),
      (Rect.fromLTWH(Gap.xs, top, w, h), Alignment.topLeft),
      (
        Rect.fromLTWH(left, box.maxHeight - Gap.xs - h, w, h),
        Alignment.bottomLeft,
      ),
    ];
    // И не на свободном месте под палец для джойстика: камера (комната по
    // высоте, 15.10) чаще ставит Финни в верхний угол, и кнопка уходила
    // вниз — под палец, которым ведут Финни.
    final Rect? stick = _stickRect;
    final (Rect r, Alignment a) = spots.firstWhere(
      ((Rect, Alignment) s) =>
          (finni == null || !s.$1.overlaps(finni)) &&
          (stick == null || !s.$1.overlaps(stick)) &&
          (avoid == null || !s.$1.overlaps(avoid)),
      orElse: () => spots.firstWhere(
        ((Rect, Alignment) s) =>
            (finni == null || !s.$1.overlaps(finni)) &&
            (avoid == null || !s.$1.overlaps(avoid)),
        orElse: () => spots.first,
      ),
    );
    return Positioned.fromRect(
      rect: r,
      child: Align(
        alignment: a,
        child: _NearButton(
          key: const ValueKey<String>('room:near'),
          label: _nearLabel(object),
          onTap: () => _actNear(object),
        ),
      ),
    );
  }

  /// Причина под шагом на кнопке действия («на счета не хватает N»).
  static const TextStyle _whyStyle = TextStyle(
    fontSize: 14,
    height: 1.0,
    fontWeight: FontWeight.w600,
  );

  /// «в город» → «В город»: текст кнопки по макету, без «Сейчас:».
  static String _capital(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Подпись кнопки действия у предмета.
  static String _nearLabel(String object) => switch (object) {
        'bed' => 'Кровать — спать',
        'fridge' => 'Холодильник — еда',
        'piggy' => 'Копилка',
        'desk' => 'Стол — работа',
        _ => 'Дверь — в город',
      };

  /// Место джойстика в сцене [box]: первый угол снизу, где он не ложится
  /// ни на предмет, который нажимают (кровать, дверь, копилка, холодильник),
  /// ни на Финни (ревью В2: джойстик лежал на кровати). Раскладки ещё нет —
  /// левый нижний угол.
  Rect _stickSpot(Size box) {
    const double s = _RoomScreenState.stickSize;
    final List<Rect> spots = <Rect>[
      Rect.fromLTWH(Gap.sm, box.height - Gap.sm - s, s, s),
      Rect.fromLTWH(box.width - Gap.sm - s, box.height - Gap.sm - s, s, s),
      Rect.fromLTWH(box.width * 0.25 - s / 2, box.height - Gap.sm - s, s, s),
      Rect.fromLTWH(box.width * 0.75 - s / 2, box.height - Gap.sm - s, s, s),
    ];
    final RoomGeometry? g = _geo;
    if (g == null) return spots.first;
    Rect onScreen(Rect r) => Rect.fromLTRB(
          g.origin.dx + r.left * g.k,
          g.origin.dy + r.top * g.k,
          g.origin.dx + r.right * g.k,
          g.origin.dy + r.bottom * g.k,
        );
    final List<Rect> busy = <Rect>[
      for (final Rect r in g.objects.values) onScreen(r),
      g.finniOnScreen(_free ?? g.feet),
    ];
    return spots.firstWhere(
      (Rect r) => !busy.any((Rect b) => b.overlaps(r)),
      orElse: () => spots.first,
    );
  }

  /// Предмет, к которому Финни подошёл по касанию ребёнка.
  String? _near;

  /// Финни идёт — второе касание предмета ждёт.
  bool _walking = false;

  WorldState get _state => context.read<WorldState>();

  /// Сообщения комнаты — внизу сцены, над панелью разделов: снекбар всего
  /// экрана закрывал «Сейчас» и разделы (скриншот Саши 15.10, «План на эту
  /// неделю уже есть…»).
  final GlobalKey<ScaffoldMessengerState> _sceneMessages =
      GlobalKey<ScaffoldMessengerState>();

  void _say(String text) {
    final ScaffoldMessengerState m =
        _sceneMessages.currentState ?? ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: PicText(text)));
  }

  void _sayResult(WorldResult r) =>
      _say(r.nextStep == null ? r.reason : '${r.reason} ${r.nextStep}');

  Future<void> _go(String route) => Navigator.of(context).pushNamed(route);

  /// Событие недели — тот же экран, что из «!» в городе.
  Future<void> _openEvent() => Navigator.of(
        context,
      ).pushNamed(WorldRoutes.event, arguments: _state.world.eventBuildingId);

  /// Iso-комната (V2, флаг `room.view: "iso"`): те же предметы, действия и
  /// ключи, что у фронтальной сцены; места — по именам слотов.
  Widget _isoScene(
    RoomArt? art,
    WorldState s,
    ResourceSnapshot snap,
    WorldProfile profile,
    double inset,
    List<String> decor,
    Map<String, String> skins, {
    required FinniReaction status,
    required FinniReaction? reaction,
    required String? pose,
    required DayView day,
    String? focus,
  }) =>
      IsoRoomScene(
        cameraFocus: focus,
        // Joystick (0.1.3 had it in the room): Finni stopped by a thing —
        // its button, the same as the front room's.
        onStickNear: (String? object) => setState(() {
          _near = null;
          _nearFree = object;
        }),
        art: art,
        stage: snap.stage,
        species: profile.species,
        idleTag: profile.idleTag,
        finniName: profile.finniName,
        happiness: snap.happiness,
        topInset: inset,
        petId: snap.activePetId,
        petAwake: _petAwake,
        decorIds: decor,
        decorTitle: (String id) => s.world.catalogItem(id)?.title ?? id,
        furnitureSkins: furnitureSkins(skins),
        saved: snap.roomIso,
        arrange: _arrange,
        selected: _sel,
        onSelect: (String slot) => setState(() {
          _sel = slot;
          _arrangeSay = null;
        }),
        onPlace: _isoPlace,
        onRefuse: (String why) => setState(() => _arrangeSay = why),
        onFinniTap: _tapFinni,
        finniPose: pose,
        finniKey: _finniKey,
        aboveFinni: FinniBadge(
          name: s.world.room.petName ? profile.finniName : null,
          status: status,
          reaction: reaction,
          hearts: _hearts,
          leading: switch (day.look) {
            HudLook.fedOnFinni => FedOnFinni(day.fed ?? 0),
            HudLook.moodOnFinni => MoodOnFinni(snap.happiness),
            HudLook.fedWhenLow when day.fedInHud => MoodOnFinni(snap.happiness),
            _ => null,
          },
        ),
        onPetTap:
            snap.activePetId == null ? null : () => _tapPet(snap.activePetId!),
        onBedTap: _arrange ? null : () => _walkThen('bed', _tapBed),
        onDoorTap: _arrange
            ? null
            : () => _walkThen('door', () => _go(WorldRoutes.city)),
        onPiggyTap: _arrange
            ? null
            : () => _walkThen('piggy', () => _go(WorldRoutes.piggy)),
        onDeskTap: _arrange
            ? null
            : () => _walkThen('desk', () => _go(WorldRoutes.jobs)),
        onFridgeTap: _arrange
            ? null
            : () => _walkThen('fridge', () => _go(WorldRoutes.shop)),
        onWalkTo: _arrange ? null : (String id) => _walkThen(id, () {}),
        piggySaved: snap.saved,
        fridge: fridgeOf(snap),
        finniNear: _near,
        walkTime: RoomScene.roomWalk,
      );

  /// Касание предмета комнаты: Финни идёт к нему, потом действие (Денис, 938:
  /// «механика хождения Финни по квартире»). Путь — [RoomScene.roomWalk],
  /// меньше секунды (ТЗ §3.4). «Анимации» выкл. — сразу действие, Финни
  /// уже стоит у предмета. Кнопки внизу делают то же без ходьбы.
  Future<void> _walkThen(String object, VoidCallback act) async {
    if (_walking) return;
    final Duration walk = context.motion(RoomScene.roomWalk);
    if (walk == Duration.zero || (_near == object && _free == null)) {
      setState(() {
        _near = object;
        _free = null;
        _nearFree = null;
      });
      return act();
    }
    // Водили джойстиком — от той же точки Финни идёт к предмету.
    setState(() {
      _near = object;
      _free = null;
      _nearFree = null;
      _walking = true;
    });
    await Future<void>.delayed(walk);
    if (!mounted) return;
    setState(() => _walking = false);
    // Пока Финни шёл, ребёнок открыл экран кнопкой внизу — комната уже под
    // ним, второй переход не нужен.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    act();
  }

  // ───────────────────────────── действия ─────────────────────────────

  Future<void> _plan() => openWeekPlan(context, _state, say: _say);

  Future<void> _startWeek() async {
    final WorldResult r = _state.act((World w) => w.startWeek());
    _sayResult(r);
    if (r.ok && _state.phase == WeekPhase.planning) await _plan();
  }

  Future<void> _sleep() async {
    final WorldState s = _state;
    final ResourceSnapshot snap = s.snapshot;
    final int short = snap.weeklyBill - (snap.need + snap.want + snap.free);
    // День по энергии: «Спать» не в последний день недели — новое утро.
    final bool lastDay = snap.dayInWeek >= snap.daysPerWeek;
    final WorldExplain explain = WorldExplain.of(context);
    final String? sleepShort = explain.sleepShort;
    final String? sleepDetail = explain.sleepDetail;
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Лечь спать?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PicText(
                <String>[
                  // Сколько раз ещё спать до итогов — словами: ребёнок не должен
                  // гадать, почему после сна снова утро, а не итоги.
                  lastDay
                      ? (snap.daysPerWeek > 1
                          ? 'Это последний день недели: после сна — итоги '
                              'недели. ⚡ осталось '
                              '${WorldHud.energyText(snap.energy)}.'
                          : 'Неделя закончится сейчас. '
                              '⚡ осталось ${WorldHud.energyText(snap.energy)}.')
                      : 'День закончится, утром — день ${snap.dayInWeek + 1} '
                          'из ${snap.daysPerWeek}. Итоги недели — после дня '
                          '${snap.daysPerWeek}. ⚡ осталось '
                          '${WorldHud.energyText(snap.energy)}.',
                  if (short > 0 && lastDay)
                    '${s.finniName}: «На счета не хватает $short. '
                        'Может, сначала возьмём смену?»',
                ].join('\n\n'),
              ),
              // Как сон возвращает силы (модель 7 дней, флаг explain_ui).
              // «Подробнее» — в содержимом, а не третьей кнопкой внизу: на
              // 360 dp при шрифте 1,3 три кнопки в ряд не помещаются.
              if ((sleepShort, sleepDetail)
                  case (
                    final String line,
                    final String detail,
                  )) ...<Widget>[
                const SizedBox(height: Gap.sm),
                Text(line, key: const ValueKey<String>('sleep:short')),
                TextButton.icon(
                  key: const ValueKey<String>('sleep:more'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                  ),
                  onPressed: () => showHelp(c, 'Как работает сон', detail),
                  icon: const Pictogram(
                    Pic.question,
                    size: 22,
                    color: WorldColors.gold,
                  ),
                  label: const Text('Подробнее'),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Ещё нет'),
          ),
          TextButton(
            key: const ValueKey<String>('sleep:confirm'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Спать'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final WorldResult r = s.act((World w) => w.sleep());
    if (!r.ok) return _sayResult(r);
    if (r.reasonCode == 'day.next') {
      // Утро той же недели: итогов нет, остаёмся в комнате.
      if (mounted) _sayResult(r);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Спокойной ночи'),
        content: PicText(
          r.nextStep == null ? r.reason : '${r.reason}\n\n${r.nextStep}',
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('sleep:next'),
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('К итогам'),
          ),
        ],
      ),
    );
    if (mounted) await _go(WorldRoutes.review);
  }

  void _tapPet(String petId) {
    setState(() => _petAwake = true);
    _sayResult(_state.act((World w) => w.petTap(petId)));
  }

  /// Кровать — то же, что «Спать», пока неделя идёт; в другой фазе спать
  /// нельзя, и кровать подсказывает ближайший шаг.
  void _tapBed() {
    final WorldState s = _state;
    if (s.phase == WeekPhase.living) {
      _sleep();
    } else {
      // После недели «рано» — неправда: там просто следующий шаг.
      final String next = '${_nextStep(s).text}.';
      _say(s.phase == WeekPhase.review ? next : 'Спать пока рано. $next');
    }
  }

  /// «Неделя» (вариант Б): план недели и копилка — одним листом, по кнопке
  /// на каждое; всё, что было двумя разделами, в одно касание дальше.
  Future<void> _week() async {
    final String? to = await pickWeekPart(context, prefix: 'room');
    if (!mounted || to == null) return;
    if (to == 'plan') {
      await _plan();
    } else {
      await _go(WorldRoutes.piggy);
    }
  }

  /// Показать реакцию: поза и строка над Финни на [time].
  void _react(
    FinniReaction r, {
    Duration time = reactionTime,
    bool pet = false,
  }) {
    _reactionTimer?.cancel();
    setState(() {
      _reaction = r;
      // Реакция мира сменила поглаживание — сердечки уходят вместе с ним.
      _hearts = pet ? _hearts + 1 : 0;
    });
    _reactionTimer = Timer(time, () {
      if (mounted) {
        setState(() {
          _reaction = null;
          _hearts = 0;
        });
      }
    });
  }

  /// Решение изменило мир — реакция, когда комната снова на экране.
  void _watchWorld(WorldState s, ResourceSnapshot snap) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final ResourceSnapshot? before = _seen;
    _seen = snap;
    if (before == null) return;
    final FinniReaction? r = reactionFor(
      before,
      snap,
      tiredBelow: s.world.cheapestActionEnergy,
    );
    if (r == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _react(r);
    });
  }

  /// Тап по Финни — погладить (решение Дениса 16.10): мир даёт +1 😊 раз
  /// в игровой день (`finni.pet`), повтор в тот же день — без начисления
  /// (`finni.pet_again`). Реакция — на каждое касание: сердечки, поза по
  /// настроению, фраза мира; «+1 😊» — только когда начислено.
  void _tapFinni() {
    final WorldState s = _state;
    final WorldResult r = s.act((World w) => w.petFinni());
    // Снимок после касания — уже «виденный»: иначе +1 😊 повторится второй
    // реакцией «Стало веселее» при следующей перерисовке.
    _seen = s.snapshot;
    final FinniMood mood = finniStatus(
      s.snapshot,
      living: s.phase == WeekPhase.living,
      tiredBelow: s.world.cheapestActionEnergy,
    ).mood;
    final String line =
        r.happiness > 0 ? '${r.reason}\n+${r.happiness} 😊' : r.reason;
    _react(FinniReaction(mood, line), time: reasonTime, pet: true);
  }

  void _help() {
    // Режим дней (`day_cycle`): ⚡ — на день, «Спать» кончает день; неделя
    // кончается после последнего дня. Запасной режим «неделя» — как было.
    final bool days = _state.snapshot.daysPerWeek > 1;
    showHelp(
        context,
        'Что здесь?',
        // Под макет Алины (alina-01): «Сейчас» — золотая кнопка внизу
        // справа. ≤ 3 предложений и 260 знаков (правило 7А).
        'Это дом Финни: вверху монеты, силы на ${days ? 'день' : 'неделю'} и '
            'настроение — нажми, и Финни объяснит. Золотая кнопка внизу '
            'справа — следующий шаг, без сил на ней '
            '«Спать»${days ? ' — закончить день' : ' — закончить неделю пораньше, с бонусом'}. '
            'В холодильнике видно, сколько еды осталось до конца недели.');
  }

  /// Неделя идёт, и сил хватает хотя бы на одно дело (смену или досуг).
  ///
  /// Одно условие на подсказку «Сейчас» и на выбор золотой кнопки: пока
  /// можно действовать, главное действие — «В город», а «Спать» тихая;
  /// когда нельзя — золотой становится «Спать» (`docs/design-system.md`
  /// §1 п. 6: одна золотая кнопка — главное действие).
  static bool canAct(WorldState s) =>
      s.phase == WeekPhase.living &&
      s.snapshot.energy + 1e-9 >= s.world.cheapestActionEnergy;

  _NextStep _nextStep(WorldState s) {
    final ResourceSnapshot snap = s.snapshot;
    final int money = snap.need + snap.want + snap.free;
    return switch (s.phase) {
      WeekPhase.onboarding => _NextStep(
          'Познакомься с Финни и выбери цель',
          'знакомство',
          () => _go(WorldRoutes.onboarding),
        ),
      WeekPhase.weekStart => _NextStep(
          'Новая неделя! Получи стипендию',
          'стипендия',
          _startWeek,
        ),
      WeekPhase.planning => _NextStep(
          'Составь план недели: разложи ${snap.unallocated}',
          'план недели',
          _plan,
        ),
      WeekPhase.review => _NextStep(
          'Неделя кончилась — посмотри итоги',
          'итоги недели',
          () => _go(WorldRoutes.review),
        ),
      WeekPhase.living when !canAct(s) => _NextStep(
          'Сил на дела не осталось — пора спать',
          'спать',
          _sleep,
          why: 'сил на дела не осталось',
        ),
      WeekPhase.living when money < snap.weeklyBill => _NextStep(
          'На счета не хватает ${snap.weeklyBill - money} — возьми смену',
          'на смену',
          () => _go(WorldRoutes.jobs),
          why: 'на счета не хватает ${snap.weeklyBill - money}',
        ),
      WeekPhase.living => _NextStep(
          'Сходи в город: работа, покупки, отдых',
          'в город',
          () => _go(WorldRoutes.city),
        ),
    };
  }

  // ─────────────────────────────── вид ───────────────────────────────

  /// Сцена со своим местом для сообщений ([_sceneMessages]). Сообщения —
  /// слоем над сценой, сквозь который проходят касания: снекбар 4 с не
  /// ловит пол под собой (кнопок в нём нет, TalkBack его по-прежнему читает).
  /// [bottom] — сколько снизу занимают меню и кнопка действия: сообщение
  /// встаёт над ними, а не на них.
  Widget _messagesOver(Widget scene, {double bottom = 0}) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          scene,
          Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: IgnorePointer(
              child: ScaffoldMessenger(
                key: _sceneMessages,
                child: const Scaffold(
                  backgroundColor: Colors.transparent,
                  body: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final WorldState s = context.watch<WorldState>();
    final ResourceSnapshot snap = s.snapshot;
    final WorldProfile profile = s.profile;
    final _NextStep next = _nextStep(s);
    // Скины: выбранный из купленных вариант встаёт последним — на своём месте
    // показывается он.
    final Map<String, String> skins = equippedSkins(snap.owned, s.chosenSkins);
    final List<String> decor = decorToShow(<String>[
      ...snap.owned.where((String id) => !skins.containsValue(id)),
      ...skins.values,
    ]);
    _watchWorld(s, snap);
    final FinniReaction worldStatus = finniStatus(
      snap,
      living: s.phase == WeekPhase.living,
      tiredBelow: s.world.cheapestActionEnergy,
    );
    final DayView day = DayView.of(snap);
    // Голод (сытость ниже порога) — строка над Финни; без дней — как сдано.
    final FinniReaction status = day.look != HudLook.asIs && day.hungry
        ? const FinniReaction(FinniMood.hungry, 'Хочется есть')
        : worldStatus;
    final FinniReaction? reaction = _reaction;
    // Поза: на время реакции — её эмоция; в покое прыгать нельзя всё время,
    // поэтому из состояния — только усталость (сидит).
    final FinniMood? posedMood = reaction?.mood ??
        (status.mood == FinniMood.tired ? FinniMood.tired : null);
    final String? pose =
        posedMood == null ? null : finniPoseTag(posedMood, profile.look);
    // Режим «Расставить»: куда выбранную вещь можно поставить.
    final RoomGrid grid = s.world.room.grid;
    final Set<RoomCell> okCells = <RoomCell>{
      if (_arrange && _sel != null)
        for (int y = 0; y < grid.rows; y++)
          for (int x = 0; x < grid.cols; x++)
            if (grid.typeAt(x, y) != null &&
                s.world.canPlaceRoomItem(_sel!, x, y) == null)
              (x: x, y: y),
    };
    final bool iso = s.world.room.iso;
    final Widget? tray = !_arrange
        ? null
        : iso
            ? _IsoArrangeTray(
                say: _arrangeSay,
                selected: _sel,
                onDone: _arrangeOff,
              )
            : _ArrangeTray(
                room: s.world.room,
                owned: snap.roomOwned,
                placed: snap.roomPlaced,
                selected: _sel,
                say: _arrangeSay,
                onSelect: (String id) => setState(() {
                  _sel = id;
                  _arrangeSay = null;
                }),
                onRemove: _removeSel,
                onDone: _arrangeOff,
              );

    // Событие без ответа (флаг `room.event_badge`): раньше его было видно
    // только по «!» у здания в городе — теперь и в комнате, одно касание.
    final PendingEvent? waiting =
        s.world.room.eventBadge && !_arrange ? s.world.pendingEvent : null;
    final List<Widget> tools = <Widget>[
      HelpButton(key: const ValueKey<String>('room:help'), onPressed: _help),
    ];
    // «Ещё» нижнего меню (макет Алины) — бывшее меню ⋮: те же пункты.
    Widget moreMenu(Widget child) => DockMoreMenu(
          prefix: 'room',
          onArrange: _arrangeOn,
          onGo: _go,
          child: child,
        );
    // [inset] — сколько сверху сцены лежит под показателями: комната
    // (общая раскладка) встаёт под них, дверь, копилка и окно не прячутся.
    Widget sceneWith(double inset) => FutureBuilder<RoomArt>(
          future: _art,
          // Шаг обучалки о предмете (дверь) — камера держит его в кадре.
          builder: (BuildContext context, AsyncSnapshot<RoomArt> a) => iso
              ? ValueListenableBuilder<String?>(
                  valueListenable: tutorialRoomFocus,
                  builder: (BuildContext context, String? spot, _) => _isoScene(
                      a.data, s, snap, profile, inset, decor, skins,
                      focus: spot,
                      status: status,
                      reaction: reaction,
                      pose: pose,
                      day: day),
                )
              : ValueListenableBuilder<String?>(
                  valueListenable: tutorialRoomFocus,
                  builder: (BuildContext context, String? spot, _) => RoomScene(
                    cameraFocus: spot,
                    topInset: inset,
                    art: a.data,
                    stage: snap.stage,
                    species: profile.species,
                    idleTag: profile.idleTag,
                    finniName: profile.finniName,
                    // Таблички с именем в комнате нет (решение 29.09): имя слышно в
                    // подписи TalkBack самого Финни.
                    showName: false,
                    happiness: snap.happiness,
                    petId: snap.activePetId,
                    petAwake: _petAwake,
                    decorIds: decor,
                    room: s.world.room,
                    roomPlaced: snap.roomPlaced,
                    gridEdit: _arrange,
                    gridOk: okCells,
                    onCellTap: _cellTap,
                    furnitureSkins: furnitureSkins(skins),
                    onFinniTap: _tapFinni,
                    finniPose: pose,
                    finniKey: _finniKey,
                    aboveFinni: FinniBadge(
                      // DEN-25 A (флаг `room.pet_name`): имя ребёнка над Финни.
                      name: s.world.room.petName ? profile.finniName : null,
                      status: status,
                      reaction: reaction,
                      hearts: _hearts,
                      leading: switch (day.look) {
                        HudLook.fedOnFinni => FedOnFinni(day.fed ?? 0),
                        HudLook.moodOnFinni => MoodOnFinni(snap.happiness),
                        HudLook.fedWhenLow when day.fedInHud =>
                          MoodOnFinni(snap.happiness),
                        _ => null,
                      },
                    ),
                    onPetTap: snap.activePetId == null
                        ? null
                        : () => _tapPet(snap.activePetId!),
                    // «Расставить»: мебель не ведёт на экраны — касание мимо
                    // клетки ничего не делает (кровать не открывает сон).
                    onBedTap: _arrange ? null : () => _walkThen('bed', _tapBed),
                    onDoorTap: _arrange
                        ? null
                        : () => _walkThen('door', () => _go(WorldRoutes.city)),
                    onPiggyTap: _arrange
                        ? null
                        : () =>
                            _walkThen('piggy', () => _go(WorldRoutes.piggy)),
                    // Стол (общая раскладка комнаты) — работа: доска смен.
                    onDeskTap: _arrange
                        ? null
                        : () => _walkThen('desk', () => _go(WorldRoutes.jobs)),
                    // Сумма копилки — над копилкой (из HUD убрана, Денис 29.09).
                    piggySaved: snap.saved,
                    fridge: fridgeOf(snap),
                    // Магазин открывается на вкладке «Еда» (initialTab 0).
                    onFridgeTap: _arrange
                        ? null
                        : () =>
                            _walkThen('fridge', () => _go(WorldRoutes.shop)),
                    // Кнопка у края (камера): Финни подходит, камера за ним.
                    onWalkTo:
                        _arrange ? null : (String id) => _walkThen(id, () {}),
                    finniNear: _near,
                    walkTime: RoomScene.roomWalk,
                    finniFree: _free,
                    finniMoving: _moving,
                    onGeometry: (RoomGeometry g) {
                      final bool first = _geo == null;
                      _geo = g;
                      if (first) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() {});
                        });
                      }
                    },
                  ),
                ),
        );
    // Джойстик (Денис, 1001) — ввод, а не анимация: есть и с выключенными
    // «Анимациями» / «Уменьшить движение», тогда Финни идёт шагами (ТЗ
    // 3.6.7: без плавного хода). Предметы и кнопки внизу работают как
    // раньше. У предмета — кнопка его действия.
    final String? nearFree = _nearFree;
    // Джойстик — вне сцены (ревью 29.09: в углу сцены он закрывал Финни и
    // дверь): в портрете слева от «Сейчас», в альбомной — в правом
    // столбце. У предмета — кнопка его действия, не на Финни.
    // Джойстик — плавающий: касание пола и ход пальцем (см. [_padStart]).
    // Полоса цели: цена · накоплено · осталось (ТЗ 2.5.7.2).
    final String? goalId = snap.activeGoalId;
    final WorldCatalogItem? goal =
        goalId == null ? null : s.world.catalogItem(goalId);
    final int price = goal?.price ?? 0;
    final bool priced = goal != null && price > 0;
    final Widget goalStrip = _GoalStrip(
      key: const ValueKey<String>('room:goal'),
      title: goalId == null ? 'не выбрана' : (goal?.title ?? goalId),
      count: goalId == null
          ? 'в копилке ${snap.saved}'
          : priced
              ? '${snap.saved} из $price'
              : 'накоплено ${snap.saved}',
      rest: !priced
          ? null
          : snap.saved >= price
              ? 'хватает!'
              : 'осталось ${price - snap.saved}',
      progress: priced ? (snap.saved / price).clamp(0.0, 1.0).toDouble() : null,
      onTap: () => _go(WorldRoutes.piggy),
    );
    // Цель тонкой строкой под показателями (ревью В2): ⚑ «Рыбка» · полоса ·
    // «200/400». Без «Финни копит:» — на 360 dp цель не влезала (29.09);
    // имя — табличкой в сцене.
    // [stacked] — в два ряда (узкий боковой столбец альбомной).
    Widget goalLineOf({bool stacked = false, bool bare = false}) => _GoalLine(
          key: const ValueKey<String>('room:goal'),
          stacked: stacked,
          bare: bare,
          name: profile.finniName,
          // В один ряд с «День N из 7» и «в копилке N» на 360 dp полная
          // фраза резалась до «цель не в…» (путь ребёнка rc-7d, n2);
          // TalkBack читает «Цель: не выбрана» из [said].
          title: goalId == null
              ? (stacked ? 'цель не выбрана' : 'без цели')
              : (goal?.title ?? goalId),
          count: goalId == null
              ? 'в копилке ${snap.saved}'
              : priced
                  ? '${snap.saved}/$price'
                  : '${snap.saved}',
          progress:
              priced ? (snap.saved / price).clamp(0.0, 1.0).toDouble() : null,
          said: <String>[
            'Цель: ${goalId == null ? 'не выбрана' : (goal?.title ?? goalId)}',
            if (priced) 'накоплено ${snap.saved} из $price',
            if (priced && snap.saved < price) 'осталось ${price - snap.saved}',
          ].join(', '),
        );
    // Одна главная кнопка «Сейчас: …» (Денис 29.09, вариант В): текст —
    // ближайший шаг, касание — этот шаг. «В город» и «Спать» — в ней,
    // когда это следующий шаг; дверь и кровать в комнате тоже работают.
    final Widget nowButton = Semantics(
      button: true,
      label: 'Сейчас: ${next.text}',
      excludeSemantics: true,
      onTap: next.onTap,
      child: FilledButton(
        key: const ValueKey<String>('room:now'),
        // 48 dp — минимум ТЗ; ниже 56 проекта ради бюджета интерфейса
        // (Денис 29.09: весь интерфейс ≤ 20–30 % высоты). Вид — по макету
        // Алины: золотая кнопка, тёмный текст, значок города слева.
        style: FilledButton.styleFrom(
          backgroundColor: AlinaColors.buttonTop,
          foregroundColor: AlinaColors.buttonText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorldRadii.button),
          ),
          minimumSize: const Size(0, 48),
          // Со второй строкой (причина) поля тоньше: кнопка не растёт выше
          // бюджета интерфейса (room_ui_budget_test, шрифт ×1,3).
          padding: EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: next.why == null ? Gap.xs : 1,
          ),
        ),
        onPressed: next.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Pictogram(Pic.city, size: 24, color: AlinaColors.buttonText),
            const SizedBox(width: Gap.sm),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    // Макет: «В город» — без «Сейчас:» (TalkBack читает
                    // «Сейчас: …» из подписи кнопки).
                    _capital(next.button),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (next.why != null)
                    // Альбомная: кнопка в узком боковом столбце, высоты
                    // хватает — причина в две строки, а не «на счета не
                    // хв…» (проход RC 17.10). Портрет — одна строка (бюджет
                    // высоты), при нехватке ширины ужимается целиком, а не
                    // режется многоточием (обход адаптива: 360 dp ×1,3).
                    WorldLayout.isLandscape(context)
                        ? Text(
                            next.why!,
                            key: const ValueKey<String>('room:now:why'),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _whyStyle,
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              next.why!,
                              key: const ValueKey<String>('room:now:why'),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: _whyStyle,
                            ),
                          ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final Widget bottomBar = WorldDock(
      current: DockSection.home,
      prefix: 'room',
      onTap: (DockSection d) => switch (d) {
        DockSection.home || DockSection.more => null,
        DockSection.city => () => _go(WorldRoutes.city),
        DockSection.plan => _week,
        DockSection.progress => () => _go(WorldRoutes.history),
      },
      more: moreMenu,
    );
    // Сцена во весь экран, показатели и джойстик — поверх неё (бюджет
    // интерфейса по вертикали 20–30 %, Денис 29.09; room_ui_budget_test).
    Widget sceneArea({
      required bool withStick,
      required bool withGoal,
      Widget? nav,
      Widget? action,
    }) =>
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints area) {
            // «Расставить»: Финни не ходит, касание — клеткам сетки. Обёртка
            // джойстика остаётся (без жестов): иначе сцена пересобирается и
            // кадр мигает комнатой без арта.
            // Iso-комната (V2): Финни ходит по клеткам касанием, без джойстика.
            final bool walk = withStick && !_arrange && !iso;
            // Сцена — на всю область; комната (общая раскладка) встаёт сразу
            // под показатели. Масштаб ограничивает сама сцена (кровать и стол
            // в покое видны на ¾, camera.foreground_shown), лишнее снизу —
            // продолжение пола: пустой полосы над стеной нет (29.09).
            // Меню — полосой цвета тёмного пола под сценой (макет Алины):
            // комната не уходит под него, кровать и стол нажимаются целиком.
            final double h = area.maxHeight - (nav == null ? 0 : navHeight);
            // «Расставить»: в портрете — как до макета (≈ 88), в альбомной —
            // только ряд показателей (≈ 60): клетки сетки не мельче пальца.
            final double inset = _arrange
                ? (withGoal ? hudArrangeHeight : Gap.xs + RoomHud.rowHeight)
                : withGoal
                    ? hudOverlayHeight
                    : hudChipsHeight;
            final Widget scene = sceneWith(inset);
            // Низ сцены под кнопкой действия (лежит на сцене, как в макете) —
            // джойстик и кнопка у предмета встают выше.
            final double below = action == null ? 0 : actionHeight;
            final BoxConstraints box = BoxConstraints.tight(
              Size(area.maxWidth, h - below),
            );
            final Rect? badgeAt = waiting == null
                ? null
                : Rect.fromLTWH(
                    area.maxWidth - Gap.xs - TapSize.min,
                    inset + Gap.xs,
                    TapSize.min,
                    TapSize.min,
                  );
            _stickRect =
                walk ? _stickSpot(Size(area.maxWidth, h - below)) : null;
            final Offset? pad = _padCenter;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (nav != null)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: navHeight,
                    child: ColoredBox(color: AlinaColors.navBack),
                  ),
                Positioned(
                  // Ключ: полоса меню перед сценой появляется и пропадает («Расставить»)
                  // — без него сцена пересобралась бы и мигнула комнатой без арта.
                  key: const ValueKey<String>('room:scene:area'),
                  left: 0,
                  right: 0,
                  top: 0,
                  height: h,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      // Касание предмета — его действие; ход пальцем по полу
                      // — плавающий джойстик (ходьба), и без «Анимаций».
                      if (withStick)
                        GestureDetector(
                          onPanStart: walk
                              ? (DragStartDetails d) =>
                                  _padStart(d.localPosition)
                              : null,
                          onPanUpdate: walk
                              ? (DragUpdateDetails d) =>
                                  _padMove(d.localPosition)
                              : null,
                          onPanEnd: walk ? (_) => _padEnd() : null,
                          onPanCancel: walk ? _padEnd : null,
                          child: scene,
                        )
                      else
                        scene,
                      if (nearFree != null && !_arrange)
                        _nearAt(box, nearFree, avoid: badgeAt),
                      // «Событие ждёт» — поверх сцены под показателями
                      // справа, а не в их ряду: там фишки сжимались и
                      // подписи мельчали (text_size_test).
                      if ((waiting, badgeAt)
                          case (
                            final PendingEvent e,
                            final Rect r,
                          ))
                        Positioned.fromRect(
                          rect: r,
                          child: _EventBadge(event: e, onTap: _openEvent),
                        ),
                      // Невидимое место на пустом полу: сюда можно положить
                      // палец наверняка (и Финни под него не заходит).
                      if (_stickRect case final Rect r when walk)
                        Positioned.fromRect(
                          rect: r,
                          child: const IgnorePointer(
                            child: SizedBox.expand(
                              key: ValueKey<String>('room:joystick'),
                            ),
                          ),
                        ),
                      // Джойстик в покое — на его месте, бледнее (макет).
                      if (_stickRect case final Rect r when walk && pad == null)
                        Positioned.fromRect(
                          rect: r,
                          child: const IgnorePointer(
                            child: Opacity(
                              opacity: 0.55,
                              child: _PadView(knob: Offset.zero, rest: true),
                            ),
                          ),
                        ),
                      if (pad != null)
                        Positioned(
                          left: pad.dx - stickSize / 2,
                          top: pad.dy - stickSize / 2,
                          child: IgnorePointer(child: _PadView(knob: _padKnob)),
                        ),
                    ],
                  ),
                ),
                // Макет Алины: текст сверху и меню снизу лежат прямо на
                // сцене; под ними она затемнена — белый текст читается и
                // на светлых обоях (контраст ≥ 4,5).
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: inset + Gap.lg,
                  child: const IgnorePointer(
                    child: DecoratedBox(
                      key: ValueKey<String>('room:scrim:top'),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: <double>[0, 0.75, 1],
                          colors: <Color>[
                            AlinaColors.scrim,
                            AlinaColors.scrim,
                            AlinaColors.scrimClear,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (nav != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: navHeight,
                    height: 2 * Gap.lg,
                    // Пол сцены переходит в полосу меню без шва.
                    child: const IgnorePointer(
                      child: DecoratedBox(
                        key: ValueKey<String>('room:scrim:bottom'),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: <Color>[
                              AlinaColors.navBack,
                              AlinaColors.navBackClear,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (action != null)
                  Positioned(
                    right: Gap.sm,
                    bottom: (nav == null ? 0 : navHeight) + Gap.xs,
                    // Кнопка по содержимому, не шире 0,8 сцены: причина
                    // «на счета не хватает N» при шрифте ×1,3 влезает
                    // (обход адаптива); место под палец — выше кнопки.
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: area.maxWidth * 0.8),
                      child: action,
                    ),
                  ),
                if (nav != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: navHeight,
                    child: nav,
                  ),
                Positioned(
                  left: Gap.sm,
                  right: Gap.sm,
                  top: Gap.xs,
                  // Верхняя строка по макету Алины (18.10): «Дома», «День N
                  // из 7», показатели, «?», «Комната Финни», строка цели.
                  child: FutureBuilder<RoomArt>(
                    future: _art,
                    builder: (BuildContext context, AsyncSnapshot<RoomArt> a) =>
                        RoomHud(
                      snapshot: snap,
                      registry: a.data?.registry,
                      tools: tools,
                      goal: withGoal
                          ? goalLineOf(stacked: true, bare: true)
                          : null,
                      compact: _arrange,
                    ),
                  ),
                ),
              ],
            );
          },
        );

    return Scaffold(
      backgroundColor: WorldColors.night,
      body: SafeArea(
        child: OrientationSplit(
          // Альбомная: сцена с показателями поверх неё и панель разделов
          // под ней; справа узкий столбец (≤ 30 % ширины) — цель, «Сейчас»
          // и джойстик.
          landscape: (BuildContext context) => LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final double side = box.maxWidth * sidePanelShare;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Сцена — на всю высоту экрана (29.09): разделы, «Сейчас» и
                  // цель — в боковом столбце, не полосой под комнатой.
                  Expanded(
                    child: _messagesOver(
                      sceneArea(
                        withStick: true,
                        withGoal: false,
                        nav: tray != null
                            ? null
                            : Material(
                                key: const ValueKey<String>('room:dock'),
                                type: MaterialType.transparency,
                                child: bottomBar,
                              ),
                      ),
                      bottom: tray != null ? 0 : navHeight,
                    ),
                  ),
                  Material(
                    key: const ValueKey<String>('room:side'),
                    color: WorldColors.panel,
                    child: SizedBox(
                      width: side,
                      child: Padding(
                        padding: const EdgeInsets.all(Gap.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: tray != null
                              ? <Widget>[
                                  Expanded(
                                    child: SingleChildScrollView(child: tray),
                                  ),
                                ]
                              : <Widget>[
                                  nowButton,
                                  const SizedBox(height: Gap.sm),
                                  goalLineOf(stacked: true),
                                  const Spacer(),
                                ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          // Портрет (макет Алины): сцена во всю высоту; сверху показатели,
          // снизу на сцене — кнопка действия справа и меню из пяти разделов.
          portrait: (BuildContext context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _messagesOver(
                  sceneArea(
                    withStick: true,
                    withGoal: goalOverScene,
                    action: tray != null ? null : nowButton,
                    nav: tray != null
                        ? null
                        : Material(
                            key: const ValueKey<String>('room:dock'),
                            type: MaterialType.transparency,
                            child: bottomBar,
                          ),
                  ),
                  bottom: tray != null ? 0 : navHeight + actionHeight,
                ),
              ),
              if (tray != null)
                Material(
                  key: const ValueKey<String>('room:dock'),
                  color: WorldColors.panel,
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.sm),
                    child: tray,
                  ),
                ),
              if (!goalOverScene && tray == null) goalStrip,
            ],
          ),
        ),
      ),
    );
  }

  /// Доля ширины бокового столбца в альбомной (бюджет ≤ 30 %).
  static const double sidePanelShare = 0.29;

  /// Где строка цели в портрете. true — вариант В2 (Денис 29.09: «3
  /// намного лучше»): плашкой поверх сцены, третьим рядом под показателями
  /// слева — Финни она не закрывает, а внизу остаются «Сейчас» и разделы
  /// (≈ 21 % высоты). false — В1: строкой в нижней панели над «Сейчас»
  /// (≈ 28 %).
  static const bool goalOverScene = true;

  /// Сколько сверху сцены занимают показатели поверх неё (и плашка цели
  /// в В2): кнопка действия у предмета встаёт ниже.
  static const double hudOverlayHeight = hudChipsHeight;

  /// Верхняя строка поверх сцены ([RoomHud]): отступ · показатели · второй
  /// ряд (цель · сытость · «?»).
  static const double hudChipsHeight =
      Gap.xs + RoomHud.rowHeight + RoomHud.titleHeight;

  /// «Расставить»: только ряд показателей ([RoomHud.compact]) — касание
  /// второго ряда не ложится на клетки сетки; комната того же размера, что
  /// до макета (отступ ≈ 88): крупнее — камера уводит кровать за край.
  static const double hudArrangeHeight = Gap.xs + RoomHud.rowHeight + 28;

  /// Нижнее меню поверх сцены (макет Алины): значок · подпись, палец 48.
  static const double navHeight = WorldDock.height;

  /// Кнопка действия над меню: 48 + причина второй строкой + отступ.
  static const double actionHeight = 48 + 16 + Gap.xs;

  /// Размер джойстика поверх сцены.
  static const double stickSize = 96;
}

/// Полоса цели в нижней панели: название · «N из M» · полоса · «осталось K» · ›.
///
/// Тап — копилка (S9). Название ужимается многоточием, числа — никогда:
/// «сколько осталось» ребёнок видит всегда (ТЗ 2.5.7.2).
class _GoalStrip extends StatelessWidget {
  const _GoalStrip({
    super.key,
    required this.title,
    required this.count,
    required this.rest,
    required this.progress,
    required this.onTap,
  });

  final String title;
  final String count;
  final String? rest;
  final double? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const TextStyle main = TextStyle(
      fontSize: 16,
      height: 1.15,
      color: WorldColors.text,
    );
    final String said = <String>[
      'Цель: $title',
      count,
      if (rest != null) rest!,
    ].join(', ');
    return Semantics(
      button: true,
      label: said,
      excludeSemantics: true,
      onTap:
          onTap, // иначе excludeSemantics отсекает касание: TalkBack не нажмёт
      child: Material(
        color: WorldColors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorldRadii.button),
          side: const BorderSide(color: WorldColors.line, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.xs, 0),
              child: Row(
                children: <Widget>[
                  const Pictogram(Pic.flag, size: 20, color: WorldColors.goal),
                  const SizedBox(width: Gap.xs + 2),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints box) {
                        // Числа не режутся: при нехватке места (крупный
                        // шрифт) ужимаются, но не шире 60 % полосы — остальное
                        // название.
                        Widget capped(Widget t) => ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: box.maxWidth * 0.6,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: t,
                              ),
                            );
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Flexible(
                                  child: Text.rich(
                                    TextSpan(
                                      children: <InlineSpan>[
                                        const TextSpan(
                                          text: 'Цель: ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        TextSpan(text: title),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: main,
                                  ),
                                ),
                                const SizedBox(width: Gap.sm),
                                capped(
                                  Text(
                                    count,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: main.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (progress != null || rest != null) ...<Widget>[
                              const SizedBox(height: 3),
                              Row(
                                children: <Widget>[
                                  if (progress != null)
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          minHeight: 6,
                                          color: WorldColors.goal,
                                          backgroundColor: WorldColors.panel,
                                        ),
                                      ),
                                    ),
                                  if (rest != null) ...<Widget>[
                                    const SizedBox(width: Gap.sm),
                                    capped(
                                      Text(
                                        rest!,
                                        maxLines: 1,
                                        softWrap: false,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          height: 1.15,
                                          color: WorldColors.textSoft,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: WorldColors.textSoft,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка действия предмета, у которого Финни стоит после джойстика: по
/// ширине подписи (тема растягивает кнопки во всю ширину), не ниже 48 dp.
class _NearButton extends StatelessWidget {
  const _NearButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: WorldColors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorldRadii.button),
          side: const BorderSide(color: WorldColors.gold, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: TapSize.min,
              minWidth: TapSize.min,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                // Крупный шрифт на узком экране: подпись ужимается, а не
                // наезжает на джойстик.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: WorldColors.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Тонкая строка цели под показателями (ревью В2): «Имя копит: цель» ·
/// полоса · «200/400». Не кнопка — копилка открывается разделом «Копилка»;
/// TalkBack читает цель, накопленное и остаток одной фразой.
class _GoalLine extends StatelessWidget {
  const _GoalLine({
    super.key,
    required this.name,
    required this.title,
    required this.count,
    required this.progress,
    required this.said,
    this.stacked = false,
    this.bare = false,
  });

  final bool stacked;

  /// Внутри верхней плашки ([HudStrip]): без своей подложки, белый текст с
  /// тенью — на полупрозрачном фоне плашки.
  final bool bare;
  final String name;
  final String title;
  final String count;
  final double? progress;
  final String said;

  @override
  Widget build(BuildContext context) {
    final TextStyle main = bare
        ? const TextStyle(
            fontSize: 16,
            height: 1.1,
            color: Colors.white,
            shadows: HudStrip.textShadow,
          )
        : const TextStyle(fontSize: 16, height: 1.1, color: WorldColors.text);
    Widget back(Widget child) => bare ? child : HudBacking(child: child);
    return Semantics(
      label: said,
      excludeSemantics: true,
      child: back(
        Padding(
          padding: bare
              ? const EdgeInsets.fromLTRB(Gap.xs, 3, Gap.xs, 3)
              : const EdgeInsets.fromLTRB(Gap.sm, 3, Gap.sm, 3),
          child: NoLargerText(
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Pictogram(
                            Pic.flag,
                            size: 16,
                            color: WorldColors.goal,
                          ),
                          const SizedBox(width: Gap.xs),
                          Expanded(child: GoalTitle(title, style: main)),
                        ],
                      ),
                      const SizedBox(height: Gap.xs),
                      Row(
                        children: <Widget>[
                          if (progress case final double p) ...<Widget>[
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  WorldRadii.tag,
                                ),
                                child: LinearProgressIndicator(
                                  value: p,
                                  minHeight: 6,
                                  color: WorldColors.goal,
                                  backgroundColor: WorldColors.raised,
                                ),
                              ),
                            ),
                            const SizedBox(width: Gap.xs),
                          ],
                          // «в копилке 1220» без цели: ужимается, не режется.
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: progress == null
                                  ? Alignment.centerLeft
                                  : Alignment.centerRight,
                              child: Text(
                                count,
                                maxLines: 1,
                                softWrap: false,
                                style: main.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: <Widget>[
                      const Pictogram(
                        Pic.flag,
                        size: 16,
                        color: WorldColors.goal,
                      ),
                      const SizedBox(width: Gap.xs),
                      Expanded(
                        child: GoalTitle(
                          title,
                          style: main.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: Gap.xs),
                      // Числа над короткой полосой — название цели целиком
                      // помещается в строку на 360 dp (29.09). Рядом с меткой
                      // дня («День 1 из 3») места меньше — числа ужимаются,
                      // а не вылезают за край.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Text(
                                count,
                                key: const ValueKey<String>('room:goal:count'),
                                maxLines: 1,
                                softWrap: false,
                                style: main.copyWith(
                                  fontSize: 14,
                                  height: 1.0,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (progress case final double p) ...<Widget>[
                                const SizedBox(height: 2),
                                SizedBox(
                                  width: 64,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      WorldRadii.tag,
                                    ),
                                    child: LinearProgressIndicator(
                                      value: p,
                                      minHeight: 4,
                                      color: WorldColors.goal,
                                      backgroundColor: WorldColors.raised,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Вид плавающего джойстика: круг и ручка, как у [Joystick]; касания не
/// ловит — их ведёт сцена.
class _PadView extends StatelessWidget {
  const _PadView({required this.knob, this.rest = false});

  final Offset knob;

  /// В покое (макет Алины: джойстик виден всегда, бледнее) — под пальцем
  /// его ещё нет; ключ свой, `room:pad` — только у ведомого.
  final bool rest;

  @override
  Widget build(BuildContext context) {
    // Тот же круг, что у города ([FloatingJoystick]).
    return SizedBox.square(
      key: ValueKey<String>(rest ? 'room:pad:rest' : 'room:pad'),
      dimension: _RoomScreenState.stickSize,
      child: JoystickPad(knob: knob, size: _RoomScreenState.stickSize),
    );
  }
}

/// Название цели в строке: целиком, если влезает; не влезает — сначала
/// ужимается шрифт (не мельче 12), чтобы первое слово было видно целиком, а
/// многоточие — только после него (29.09: «Кв…» не давало прочитать цель).
class GoalTitle extends StatelessWidget {
  const GoalTitle(this.title, {super.key, required this.style});

  final String title;
  final TextStyle style;

  static const double minSize = 12;

  /// До какого кегля ужимается название, чтобы влезть целиком.
  static const double fitSize = 14;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final TextScaler scaler = MediaQuery.textScalerOf(context);
          // Мерить тем же шрифтом, что нарисует Text: стиль темы + свой.
          final TextStyle full =
              DefaultTextStyle.of(context).style.merge(style);
          double width(String t, double size) => (TextPainter(
                text: TextSpan(
                  text: t,
                  style: full.copyWith(fontSize: size),
                ),
                textDirection: TextDirection.ltr,
                textScaler: scaler,
                maxLines: 1,
              )..layout())
                  .width;
          final double base = style.fontSize ?? 16;
          // Не влезает целиком — должно влезть первое слово с многоточием.
          final List<String> words = title.split(' ');
          final String head = words.length > 1 ? '${words.first}…' : title;
          double size = base;
          // Сначала — всё название чуть мельче (не мельче [fitSize]).
          final double whole = width(title, base);
          if (whole > box.maxWidth &&
              base * box.maxWidth / whole * 0.98 >= fitSize) {
            size = base * box.maxWidth / whole * 0.98;
          } else if (whole > box.maxWidth && width(head, base) > box.maxWidth) {
            // С запасом на округление ширины глифов при другом кегле.
            size = (base * box.maxWidth / width(head, base) * 0.98)
                .clamp(minSize, base)
                .toDouble();
          }
          return Text(
            title,
            key: const ValueKey<String>('room:goal:title'),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(fontSize: size),
          );
        },
      );
}

/// Панель режима «Расставить» (кастомизация комнаты): купленные вещи —
/// выбрать касанием, потом нажать клетку в комнате; «Убрать» снимает
/// выбранную с сетки; строка «что получилось / почему нельзя»; «Готово».
class _ArrangeTray extends StatelessWidget {
  const _ArrangeTray({
    required this.room,
    required this.owned,
    required this.placed,
    required this.selected,
    required this.say,
    required this.onSelect,
    required this.onRemove,
    required this.onDone,
  });

  final RoomCatalog room;
  final Set<String> owned;
  final Map<String, RoomCell> placed;
  final String? selected;
  final String? say;
  final ValueChanged<String> onSelect;
  final VoidCallback onRemove;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final List<RoomItemSpec> items = <RoomItemSpec>[
      for (final RoomItemSpec i in room.items)
        if (owned.contains(i.id)) i,
    ];
    final RoomItemSpec? sel = selected == null ? null : room.item(selected!);
    final String line = say ??
        (items.isEmpty
            ? 'Вещей для комнаты пока нет. Их продают в магазине, '
                'вкладка «Комната».'
            : sel == null
                ? 'Выбери вещь, потом нажми клетку в комнате.'
                : '${sel.name}: подходящие клетки отмечены знаком «+».');
    return Column(
      key: const ValueKey<String>('room:arrange:tray'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          line,
          key: const ValueKey<String>('room:arrange:say'),
          style: const TextStyle(fontSize: 15, color: WorldColors.text),
        ),
        const SizedBox(height: Gap.xs),
        if (items.isNotEmpty)
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (final RoomItemSpec i in items)
                  Padding(
                    padding: const EdgeInsets.only(right: Gap.xs),
                    child: _TrayItem(
                      item: i,
                      selected: i.id == selected,
                      placed: placed.containsKey(i.id),
                      onTap: () => onSelect(i.id),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: Gap.xs),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.xs,
          alignment: WrapAlignment.end,
          children: <Widget>[
            OutlinedButton(
              key: const ValueKey<String>('room:arrange:remove'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(TapSize.min, TapSize.min),
              ),
              onPressed:
                  sel != null && placed.containsKey(sel.id) ? onRemove : null,
              child: const Text('Убрать'),
            ),
            FilledButton(
              key: const ValueKey<String>('room:arrange:done'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(TapSize.min, TapSize.min),
              ),
              onPressed: onDone,
              child: const Text('Готово'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Панель «Расставить» iso-комнаты (V2): вещи выбираются касанием в самой
/// комнате, клетки и слоты стены подсвечены; здесь — подсказка и «Готово».
class _IsoArrangeTray extends StatelessWidget {
  const _IsoArrangeTray({
    required this.say,
    required this.selected,
    required this.onDone,
  });

  final String? say;
  final String? selected;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey<String>('room:arrange:tray'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Two lines kept for the words: a one-line answer after a drop
          // used to shorten the tray, and the room jumped ~20 px down.
          ConstrainedBox(
            constraints: BoxConstraints(
                minHeight:
                    MediaQuery.textScalerOf(context).scale(15) * 1.35 * 2),
            child: Text(
              say ??
                  (selected == null
                      ? 'Перетащи вещь пальцем или нажми на неё, потом — на клетку пола или стену.'
                      : 'Куда поставить? Подходящие места подсвечены зелёным.'),
              key: const ValueKey<String>('room:arrange:say'),
              style: const TextStyle(
                  fontSize: 15, height: 1.35, color: WorldColors.text),
            ),
          ),
          const SizedBox(height: Gap.xs),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey<String>('room:arrange:done'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(TapSize.min, TapSize.min),
              ),
              onPressed: onDone,
              child: const Text('Готово'),
            ),
          ),
        ],
      );
}

/// Вещь в панели «Расставить»: картинка 64 dp; выбранная — в рамке,
/// поставленная — с отметкой. TalkBack слышит название и состояние.
class _TrayItem extends StatelessWidget {
  const _TrayItem({
    required this.item,
    required this.selected,
    required this.placed,
    required this.onTap,
  });

  final RoomItemSpec item;
  final bool selected;
  final bool placed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        key: ValueKey<String>('room:arrange:item:${item.id}'),
        button: true,
        selected: selected,
        label: '${item.name}${placed ? ', стоит в комнате' : ''}'
            '${selected ? ', выбрано' : ''}',
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: WorldColors.raised,
              borderRadius: BorderRadius.circular(WorldRadii.tag),
              border: Border.all(
                color: selected ? WorldColors.gold : Colors.transparent,
                width: 3,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Image.asset(
                  item.sprite,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.inventory_2_rounded,
                    color: WorldColors.textSoft,
                  ),
                ),
                if (placed)
                  const Align(
                    alignment: Alignment.bottomRight,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: WorldColors.gold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

/// Кнопка «Событие ждёт» в ряду инструментов комнаты: золотой круг с «!»,
/// как у здания в городе. 48 dp; TalkBack читает название события.
class _EventBadge extends StatelessWidget {
  const _EventBadge({required this.event, required this.onTap});

  final PendingEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Событие ждёт: ${event.title}',
        excludeSemantics: true,
        onTap: onTap,
        child: SizedBox(
          width: TapSize.min,
          height: TapSize.min,
          child: Material(
            type: MaterialType.transparency,
            child: InkResponse(
              key: const ValueKey<String>('room:event'),
              onTap: onTap,
              radius: TapSize.min / 2,
              child: const Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: WorldColors.gold,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(
                      Icons.priority_high_rounded,
                      size: 24,
                      color: WorldColors.panel,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
