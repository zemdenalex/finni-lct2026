import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/feel.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../domain/world/contract.dart';
import '../../../domain/world/fridge_stock.dart';
import '../joystick.dart';
import '../world_help.dart';
import '../world_routes.dart';
import '../world_layout.dart';
import '../world_state.dart';
import 'plan_sheet.dart';
import 'room_scene.dart';
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

  /// Разделы внизу. true — вариант Б (выбран командой 29.09): «Неделя» (план и копилка) · «Город» (работа, магазин,
  /// прогулки — здания города) · «Прогресс». false — вариант В: пять
  /// разделов (план · работа · магазин · копилка · прогресс).
  static const bool threeTabs = true;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

/// Ближайший шаг — главная кнопка «Сейчас: …» (ТЗ 3.6.2).
class _NextStep {
  const _NextStep(this.text, this.button, this.onTap);

  /// Подсказка целиком — для TalkBack и для кровати вне недели.
  final String text;

  /// Короткое действие на кнопке: «Сейчас: в город».
  final String button;
  final VoidCallback onTap;
}

class _RoomScreenState extends State<RoomScreen>
    with SingleTickerProviderStateMixin {
  late final Future<RoomArt> _art = RoomArt.load();
  bool _petAwake = false;

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
    _driveOrNull?.dispose();
    super.dispose();
  }

  /// Шаг от джойстика: Финни идёт в пределах пола ([RoomGeometry.walk]).
  void _step(double seconds, Offset dir) {
    final RoomGeometry? g = _geo;
    if (g == null || !mounted) return;
    final Offset from = _free ?? g.feet;
    final Offset to = from + dir * (g.unit * _speed * seconds);
    Offset clampIn(Offset o) => Offset(
          o.dx.clamp(g.walk.left, g.walk.right).toDouble(),
          o.dy.clamp(g.walk.top, g.walk.bottom).toDouble(),
        );
    final Offset kept = clampIn(to);
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
    _drive.set(dir);
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
  Widget _nearAt(BoxConstraints box, String object) {
    final RoomGeometry? g = _geo;
    final Offset? at = _free;
    final Rect? finni = g == null || at == null ? null : g.finniOnScreen(at);
    // Ширина места под кнопку: подпись ужимается в нём (FittedBox).
    final double w = math.min(180, box.maxWidth - 2 * Gap.xs);
    const double h = TapSize.min + 24;
    const double left = Gap.xs;
    // Верхние места — под показателями поверх сцены, не на них.
    const double top = hudOverlayHeight;
    final List<(Rect, Alignment)> spots = <(Rect, Alignment)>[
      (Rect.fromLTWH(box.maxWidth - Gap.xs - w, top, w, h), Alignment.topRight),
      (
        Rect.fromLTWH(
            box.maxWidth - Gap.xs - w, box.maxHeight - Gap.xs - h, w, h),
        Alignment.bottomRight
      ),
      (Rect.fromLTWH(Gap.xs, top, w, h), Alignment.topLeft),
      (
        Rect.fromLTWH(left, box.maxHeight - Gap.xs - h, w, h),
        Alignment.bottomLeft
      ),
    ];
    final (Rect r, Alignment a) = spots.firstWhere(
        ((Rect, Alignment) s) => finni == null || !s.$1.overlaps(finni),
        orElse: () => spots.first);
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
        g.origin.dy + r.bottom * g.k);
    final List<Rect> busy = <Rect>[
      for (final Rect r in g.objects.values) onScreen(r),
      g.finniOnScreen(_free ?? g.feet),
    ];
    return spots.firstWhere((Rect r) => !busy.any((Rect b) => b.overlaps(r)),
        orElse: () => spots.first);
  }

  /// Предмет, к которому Финни подошёл по касанию ребёнка.
  String? _near;

  /// Финни идёт — второе касание предмета ждёт.
  bool _walking = false;

  WorldState get _state => context.read<WorldState>();

  void _say(String text) {
    final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(text)));
  }

  void _sayResult(WorldResult r) =>
      _say(r.nextStep == null ? r.reason : '${r.reason} ${r.nextStep}');

  Future<void> _go(String route) => Navigator.of(context).pushNamed(route);

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

  Future<void> _plan() async {
    final WorldState s = _state;
    if (s.phase == WeekPhase.weekStart) {
      final WorldResult r = s.act((World w) => w.startWeek());
      if (!r.ok) return _sayResult(r);
    }
    if (s.phase != WeekPhase.planning) {
      final ResourceSnapshot snap = s.snapshot;
      return _say('План на эту неделю уже есть: нужно ${snap.need}, '
          'хочу ${snap.want}, в копилке ${snap.goal}.');
    }
    final WorldResult? r = await showPlanSheet(context, s);
    if (r != null && mounted) _sayResult(r);
  }

  Future<void> _startWeek() async {
    final WorldResult r = _state.act((World w) => w.startWeek());
    _sayResult(r);
    if (r.ok && _state.phase == WeekPhase.planning) await _plan();
  }

  Future<void> _sleep() async {
    final WorldState s = _state;
    final ResourceSnapshot snap = s.snapshot;
    final int short = snap.weeklyBill - (snap.need + snap.want + snap.free);
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Лечь спать?'),
        content: PicText(<String>[
          'Неделя закончится сейчас. '
              '⚡ осталось ${WorldHud.energyText(snap.energy)}.',
          if (short > 0)
            '${s.finniName}: «На счета не хватает $short. '
                'Может, сначала возьмём смену?»',
        ].join('\n\n')),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Ещё нет')),
          TextButton(
              key: const ValueKey<String>('sleep:confirm'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Спать')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final WorldResult r = s.act((World w) => w.sleep());
    if (!r.ok) return _sayResult(r);
    await showDialog<void>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Спокойной ночи'),
        content: Text(
            r.nextStep == null ? r.reason : '${r.reason}\n\n${r.nextStep}'),
        actions: <Widget>[
          TextButton(
              key: const ValueKey<String>('sleep:next'),
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('К итогам')),
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
    final String? to = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Неделя', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: Gap.sm),
              OutlinedButton.icon(
                key: const ValueKey<String>('room:week:plan'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(TapSize.min)),
                onPressed: () => Navigator.of(c).pop('plan'),
                icon: const Pictogram(Pic.envelope,
                    size: 24, color: WorldColors.text),
                label: const Text('План недели'),
              ),
              const SizedBox(height: Gap.sm),
              OutlinedButton.icon(
                key: const ValueKey<String>('room:week:piggy'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(TapSize.min)),
                onPressed: () => Navigator.of(c).pop('piggy'),
                icon:
                    const Pictogram(Pic.jar, size: 24, color: WorldColors.text),
                label: const Text('Копилка'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || to == null) return;
    if (to == 'plan') {
      await _plan();
    } else {
      await _go(WorldRoutes.piggy);
    }
  }

  /// Тап по Финни — причина настроения одной фразой от мира (ТЗ 2.5.10.3).
  void _tapFinni() => _say(_state.snapshot.moodReason.text);

  void _help() {
    showHelp(
        context,
        'Что здесь?',
        'Это дом Финни.\n\n'
            'Вверху: монеты, которые можно тратить, копилка на цель, '
            'силы на неделю и настроение. Нажми на любое — Финни '
            'объяснит.\n\n'
            'Полоса «Цель» — сколько накоплено и сколько осталось.\n\n'
            'Работа — это финансовые задания: каждая смена — мини-игра.\n\n'
            '«Сейчас» подсказывает следующий шаг. Внизу: «Работа» — '
            'смены; «Магазин» — еда, вещи и питомцы; «Прогулки» — парк, '
            'кино и кафе. «Спать» — закончить неделю пораньше и получить '
            'бонус.\n\n'
            'Нажми на Финни — узнаешь, какое у Финни настроение.\n\n'
            'Кровать, дверь, копилку и холодильник тоже можно нажимать — '
            'Финни к ним подойдёт. Или веди Финни сам джойстиком внизу '
            'слева: у предмета появится кнопка его действия.\n\n'
            'В холодильнике видно, сколько еды осталось на неделю.\n\n'
            'Ползунки вверху — звук и анимации. Замок — раздел для '
            'взрослого.');
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
      WeekPhase.onboarding => _NextStep('Познакомься с Финни и выбери цель',
          'знакомство', () => _go(WorldRoutes.onboarding)),
      WeekPhase.weekStart =>
        _NextStep('Новая неделя! Получи карманные', 'карманные', _startWeek),
      WeekPhase.planning => _NextStep(
          'Составь план недели: разложи ${snap.unallocated}',
          'план недели',
          _plan),
      WeekPhase.review => _NextStep('Неделя кончилась — посмотри итоги',
          'итоги недели', () => _go(WorldRoutes.review)),
      WeekPhase.living when !canAct(s) =>
        _NextStep('Сил на дела не осталось — пора спать', 'спать', _sleep),
      WeekPhase.living when money < snap.weeklyBill => _NextStep(
          'На счета не хватает ${snap.weeklyBill - money} — возьми смену',
          'на смену',
          () => _go(WorldRoutes.jobs)),
      WeekPhase.living => _NextStep('Сходи в город: работа, покупки, отдых',
          'в город', () => _go(WorldRoutes.city)),
    };
  }

  // ─────────────────────────────── вид ───────────────────────────────

  @override
  Widget build(BuildContext context) {
    final WorldState s = context.watch<WorldState>();
    final ResourceSnapshot snap = s.snapshot;
    final WorldProfile profile = s.profile;
    final _NextStep next = _nextStep(s);
    final List<String> decor = decorToShow(snap.owned);

    // Замок (раздел взрослого, S14, ТЗ 2.5.12) и ⚙ (звук и анимации, ТЗ
    // 3.6.7) — в одном меню ⋮; «?» — отдельно, в одно касание (ТЗ 2.5.1.3).
    final List<Widget> tools = <Widget>[
      HelpButton(
        key: const ValueKey<String>('room:help'),
        onPressed: _help,
      ),
      PopupMenuButton<String>(
        key: const ValueKey<String>('room:menu'),
        tooltip: 'Ещё: взрослым, настройки',
        icon: const Icon(Icons.more_vert_rounded,
            size: 28, color: WorldColors.text),
        color: WorldColors.panel,
        onSelected: (String v) =>
            _go(v == 'adult' ? WorldRoutes.adult : WorldRoutes.settings),
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            key: ValueKey<String>('room:adult'),
            value: 'adult',
            height: TapSize.min,
            child: Row(children: <Widget>[
              Pictogram(Pic.lock, size: 24, color: WorldColors.text),
              SizedBox(width: Gap.sm),
              Text('Взрослым', style: TextStyle(fontSize: 18)),
            ]),
          ),
          const PopupMenuItem<String>(
            key: ValueKey<String>('room:settings'),
            value: 'settings',
            height: TapSize.min,
            child: Row(children: <Widget>[
              Pictogram(Pic.sliders, size: 24, color: WorldColors.text),
              SizedBox(width: Gap.sm),
              Text('Настройки', style: TextStyle(fontSize: 18)),
            ]),
          ),
        ],
      ),
    ];
    // [inset] — сколько сверху сцены лежит под показателями: комната
    // (общая раскладка) встаёт под них, дверь, копилка и окно не прячутся.
    Widget sceneWith(double inset) => FutureBuilder<RoomArt>(
          future: _art,
          builder: (BuildContext context, AsyncSnapshot<RoomArt> a) =>
              RoomScene(
            topInset: inset,
            art: a.data,
            stage: snap.stage,
            species: profile.species,
            idleTag: profile.idleTag,
            finniName: profile.finniName,
            // Имя — табличкой в ряду показателей: в углу сцены его накрыли бы
            // фишки поверх комнаты.
            showName: false,
            happiness: snap.happiness,
            petId: snap.activePetId,
            petAwake: _petAwake,
            decorIds: decor,
            onFinniTap: _tapFinni,
            onPetTap: snap.activePetId == null
                ? null
                : () => _tapPet(snap.activePetId!),
            onBedTap: () => _walkThen('bed', _tapBed),
            onDoorTap: () => _walkThen('door', () => _go(WorldRoutes.city)),
            onPiggyTap: () => _walkThen('piggy', () => _go(WorldRoutes.piggy)),
            // Стол (общая раскладка комнаты) — работа: доска смен.
            onDeskTap: () => _walkThen('desk', () => _go(WorldRoutes.jobs)),
            // Сумма копилки — над копилкой (из HUD убрана, Денис 29.09).
            piggySaved: snap.saved,
            fridge: fridgeOf(snap),
            // Магазин открывается на вкладке «Еда» (initialTab 0).
            onFridgeTap: () => _walkThen('fridge', () => _go(WorldRoutes.shop)),
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
        );
    // Джойстик (Денис, 1001) — поверх сцены в левом нижнем углу; с
    // выключенными «Анимациями» его нет: ходьбы нет (ТЗ 3.6.7). Предметы и
    // кнопки внизу работают как раньше. У предмета — кнопка его действия.
    final bool stick = context.motionOnListening;
    final String? nearFree = _nearFree;
    // Джойстик — вне сцены (ревью 29.09: в углу сцены он закрывал Финни и
    // дверь): в портрете слева от «Сейчас», в альбомной — в правом
    // столбце. У предмета — кнопка его действия, не на Финни.
    // Джойстик — плавающий: касание пола и ход пальцем (см. [_padStart]).
    final bool joystick = stick;
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
    // Цель тонкой строкой под показателями (ревью В2): «Финни копит:
    // Рыбка» · полоса · «200/400». Имя — здесь: так понятно, чьё оно.
    // [stacked] — в два ряда (узкий боковой столбец альбомной).
    Widget goalLineOf({bool stacked = false}) => _GoalLine(
          key: const ValueKey<String>('room:goal'),
          stacked: stacked,
          name: profile.finniName,
          title: goalId == null ? 'цель не выбрана' : (goal?.title ?? goalId),
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
        // (Денис 29.09: весь интерфейс ≤ 20–30 % высоты).
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding:
              const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
        ),
        onPressed: next.onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Flexible(
              child: Text('Сейчас: ${next.button}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            const Icon(Icons.chevron_right_rounded, size: 26),
          ],
        ),
      ),
    );
    Widget bottomBar({required bool compact}) => _BottomBar(
          compact: compact,
          onPlan: _plan,
          onWeek: _week,
          onCity: () => _go(WorldRoutes.city),
          onJobs: () => _go(WorldRoutes.jobs),
          onShop: () => _go(WorldRoutes.shop),
          onPiggy: () => _go(WorldRoutes.piggy),
          onProgress: () => _go(WorldRoutes.history),
        );
    // Сцена во весь экран, показатели и джойстик — поверх неё (бюджет
    // интерфейса по вертикали 20–30 %, Денис 29.09; room_ui_budget_test).
    Widget sceneArea({required bool withStick, required bool withGoal}) =>
        LayoutBuilder(builder: (BuildContext context, BoxConstraints area) {
          // Сцена — на всю область; комната (общая раскладка, по высоте
          // сцены за вычетом [inset]) встаёт под показатели и не выше
          // [roomMaxAspect] ширины: иначе на длинном экране (360×800) камера
          // за Финни срезает холодильник. Лишнее сверху — цвет стены.
          final double h = area.maxHeight;
          final double inset = math.max(
              withGoal ? hudOverlayHeight : hudChipsHeight,
              h - area.maxWidth * roomMaxAspect);
          final Widget scene = sceneWith(inset);
          final BoxConstraints box =
              BoxConstraints.tight(Size(area.maxWidth, h));
          _stickRect =
              withStick && joystick ? _stickSpot(Size(area.maxWidth, h)) : null;
          final Offset? pad = _padCenter;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: h,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    // Касание предмета — его действие; ход пальцем по полу
                    // — плавающий джойстик (ходьба). Без «Анимаций» — нет.
                    if (withStick && joystick)
                      GestureDetector(
                        onPanStart: (DragStartDetails d) =>
                            _padStart(d.localPosition),
                        onPanUpdate: (DragUpdateDetails d) =>
                            _padMove(d.localPosition),
                        onPanEnd: (_) => _padEnd(),
                        onPanCancel: _padEnd,
                        child: scene,
                      )
                    else
                      scene,
                    if (nearFree != null) _nearAt(box, nearFree),
                    // Невидимое место на пустом полу: сюда можно положить
                    // палец наверняка (и Финни под него не заходит).
                    if (_stickRect case final Rect r when withStick)
                      Positioned.fromRect(
                        rect: r,
                        child: const IgnorePointer(
                          child: SizedBox.expand(
                              key: ValueKey<String>('room:joystick')),
                        ),
                      ),
                    if (pad != null)
                      Positioned(
                        left: pad.dx - stickSize / 2,
                        top: pad.dy - stickSize / 2,
                        child: IgnorePointer(
                          child: _PadView(knob: _padKnob),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: Gap.sm,
                right: Gap.sm,
                top: Gap.xs,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    HudChips(snapshot: snap, trailing: tools),
                    if (withGoal) ...<Widget>[
                      const SizedBox(height: Gap.xs),
                      goalLineOf(),
                    ],
                  ],
                ),
              ),
            ],
          );
        });

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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(
                            // Цель — в боковом столбце: над комнатой только
                            // ряд фишек, иначе на 360 dp высоты комната
                            // мельчает (Финни уже 48 dp касания).
                            child: sceneArea(withStick: true, withGoal: false)),
                        bottomBar(compact: true),
                      ],
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
                          children: <Widget>[
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
          // Портрет: сцена во всю высоту с показателями поверх; внизу одна
          // панель — строка цели, «Сейчас: …» и разделы.
          portrait: (BuildContext context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                  child: sceneArea(withStick: true, withGoal: goalOverScene)),
              Material(
                key: const ValueKey<String>('room:dock'),
                color: WorldColors.panel,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.sm, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (!goalOverScene) ...<Widget>[
                            goalStrip,
                            const SizedBox(height: Gap.xs + 2),
                          ],
                          nowButton,
                        ],
                      ),
                    ),
                    bottomBar(compact: false),
                  ],
                ),
              ),
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
  static const double hudOverlayHeight =
      hudChipsHeight + (goalOverScene ? goalLineHeight + Gap.xs : 0);

  /// Ряд фишек сверху с отступами: отступ · 48 · отступ.
  static const double hudChipsHeight = Gap.xs + 48 + Gap.xs;

  /// Комната не выше этой доли ширины экрана: Финни в центре (x 0,5), край
  /// холодильника на 0,87 ширины квадратной раскладки — он в кадре, пока
  /// ширина комнаты ≤ экран / 0,74 (запас на ходьбу).
  static const double roomMaxAspect = 1.3;

  /// Строка цели ([_GoalLine]): 5 + строка 16 × 1,1 + 5, с запасом.
  static const double goalLineHeight = 28;

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
    const TextStyle main =
        TextStyle(fontSize: 16, height: 1.15, color: WorldColors.text);
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
          borderRadius: BorderRadius.circular(Radii.chip),
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
                            constraints:
                                BoxConstraints(maxWidth: box.maxWidth * 0.6),
                            child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: t),
                          );
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text.rich(
                                  TextSpan(children: <InlineSpan>[
                                    const TextSpan(
                                        text: 'Цель: ',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    TextSpan(text: title),
                                  ]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: main,
                                ),
                              ),
                              const SizedBox(width: Gap.sm),
                              capped(Text(count,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: main.copyWith(
                                      fontWeight: FontWeight.w800))),
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
                                  capped(Text(rest!,
                                      maxLines: 1,
                                      softWrap: false,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          height: 1.15,
                                          color: WorldColors.textSoft))),
                                ],
                              ],
                            ),
                          ],
                        ],
                      );
                    }),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 20, color: WorldColors.textSoft),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Нижняя панель: один тап до плана, работы, магазина, прогулок, копилки
/// и прогресса (S12, ТЗ 2.5.3.2). «Взрослым» — значок-замок сверху.
///
/// «Работа» — вход в мини-игры (доска смен S6): значок геймпада и подпись
/// для TalkBack «Работа — мини-игры». «Магазин» (S4) и «Прогулки» (S8) —
/// раздельно: НУЖНО и ХОЧУ на разных кнопках (фидбек дизайнера 28.09,
/// п. 1 и 3).
///
/// [compact] — альбомная: высота ровно 48 dp, чтобы комнате над панелью
/// хватило высоты на масштаб ×2.
///
/// Подписи — одного кегля и не мельче 14 sp: шесть равных ячеек на 360 dp
/// — по 60, а «Прогулки» и «Прогресс» в 14 sp шире 66. Поэтому ширина
/// ячейки — по ширине её подписи (не меньше 48 dp), а если и так не
/// влезает — все подписи ужимаются одним общим множителем.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.compact,
    required this.onPlan,
    required this.onWeek,
    required this.onCity,
    required this.onJobs,
    required this.onShop,
    required this.onPiggy,
    required this.onProgress,
  });

  final bool compact;
  final VoidCallback onPlan;
  final VoidCallback onWeek;
  final VoidCallback onCity;
  final VoidCallback onJobs;
  final VoidCallback onShop;
  final VoidCallback onPiggy;
  final VoidCallback onProgress;

  /// Высота компактной панели.
  static const double compactHeight = 48;

  /// Самая узкая ячейка — палец.
  static const double minCell = 48;

  /// Поле подписи с каждой стороны: соседние подписи не слипаются.
  static const double pad = 2;

  // Трекинг чуть плотнее: шесть подписей в 14 sp встают в 360 dp без
  // сжатия и с зазором.
  static const TextStyle _label = TextStyle(
      fontSize: 14,
      height: 1.15,
      letterSpacing: -0.4,
      fontWeight: FontWeight.w700,
      color: WorldColors.text);

  /// Ширина подписи в [_label] — как её нарисует `Text`.
  static double _width(BuildContext context, String label) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
          text: label, style: DefaultTextStyle.of(context).style.merge(_label)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final double w = tp.width.ceilToDouble();
    tp.dispose();
    return w;
  }

  /// Общий множитель подписей: 1, если ячейки по ширине подписей (не уже
  /// [minCell], с полями [pad]) влезают в [room]; иначе наибольший, при
  /// котором влезают.
  static double _squeeze(List<double> widths, double room) {
    double need(double k) => widths.fold(
        0, (double a, double w) => a + math.max(w * k + 2 * pad, minCell));
    if (need(1) <= room) return 1;
    double lo = 0, hi = 1;
    for (int i = 0; i < 30; i++) {
      final double mid = (lo + hi) / 2;
      if (need(mid) <= room) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  Widget build(BuildContext context) {
    // Значки крупнее (Денис 29.09: «иконки по-больше и более понятными»).
    Widget pic(Pic p) =>
        Pictogram(p, size: compact ? 24 : 28, color: WorldColors.text);
    Widget icon(IconData i) =>
        Icon(i, size: compact ? 26 : 30, color: WorldColors.text);
    final List<(String, Widget, String, String, VoidCallback)> items =
        RoomScreen.threeTabs
            ? <(String, Widget, String, String, VoidCallback)>[
                (
                  'week',
                  pic(Pic.week),
                  'Неделя',
                  'Неделя: план и копилка',
                  onWeek
                ),
                (
                  'city',
                  pic(Pic.city),
                  'Город',
                  'Город: работа — мини-игры, магазин, прогулки',
                  onCity
                ),
                (
                  'progress',
                  pic(Pic.chart),
                  'Прогресс',
                  'Прогресс',
                  onProgress
                ),
              ]
            : <(String, Widget, String, String, VoidCallback)>[
                ('plan', pic(Pic.envelope), 'План', 'План', onPlan),
                (
                  'jobs',
                  icon(Icons.sports_esports_rounded),
                  'Работа',
                  'Работа — мини-игры',
                  onJobs
                ),
                (
                  'shop',
                  icon(Icons.storefront_rounded),
                  'Магазин',
                  'Магазин',
                  onShop
                ),
                ('piggy', pic(Pic.jar), 'Копилка', 'Копилка', onPiggy),
                (
                  'progress',
                  pic(Pic.chart),
                  'Прогресс',
                  'Прогресс',
                  onProgress
                ),
              ];
    final List<double> widths = <double>[
      for (final (String, Widget, String, String, VoidCallback) i in items)
        _width(context, i.$3),
    ];

    return Material(
      color: WorldColors.panel,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          // Запас 1 dp: веса округляются, и ячейка в [minCell] не должна выйти
          // на 47,99.
          final double k = _squeeze(widths, box.maxWidth - 1);
          return Row(
            children: <Widget>[
              for (int n = 0; n < items.length; n++)
                _item(items[n], widths[n], k),
            ],
          );
        },
      ),
    );
  }

  Widget _item((String, Widget, String, String, VoidCallback) i, double width,
      double k) {
    final (
      String key,
      Widget icon,
      String label,
      String said,
      VoidCallback onTap
    ) = i;
    // Подпись в коробке своей ширины, ужатая ровно в k раз: у всех шести
    // один кегль, и у «Плана» в широкой ячейке тоже.
    final Widget content = SizedBox(
      width: width * k,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              icon,
              SizedBox(height: compact ? 1 : 2),
              Text(label,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: _label),
            ],
          ),
        ),
      ),
    );
    // Ячейки делят ширину по весу подписи: лишнее раздаётся пропорционально,
    // а вес не меньше [minCell] — ячейка не уже пальца.
    return Expanded(
      flex: (math.max(width * k + 2 * pad, minCell) * 100).round(),
      child: Semantics(
        button: true,
        label: said,
        excludeSemantics: true,
        onTap:
            onTap, // иначе excludeSemantics отсекает касание: TalkBack не нажмёт
        child: InkWell(
          key: ValueKey<String>('room:nav:$key'),
          onTap: onTap,
          child: compact
              ? SizedBox(height: compactHeight, child: Center(child: content))
              : ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: TapSize.min),
                  child: Center(child: content),
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
          borderRadius: BorderRadius.circular(Radii.chip),
          side: const BorderSide(color: WorldColors.gold, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                minHeight: TapSize.min, minWidth: TapSize.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                // Крупный шрифт на узком экране: подпись ужимается, а не
                // наезжает на джойстик.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: WorldColors.text)),
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
  });

  final bool stacked;
  final String name;
  final String title;
  final String count;
  final double? progress;
  final String said;

  @override
  Widget build(BuildContext context) {
    const TextStyle main =
        TextStyle(fontSize: 16, height: 1.1, color: WorldColors.text);
    return Semantics(
      label: said,
      excludeSemantics: true,
      child: HudBacking(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.sm, 3, Gap.sm, 3),
          child: NoLargerText(
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (name.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            key: const ValueKey<String>('room:name'),
                            fit: BoxFit.scaleDown,
                            child: Text(name,
                                maxLines: 1,
                                softWrap: false,
                                style:
                                    main.copyWith(fontWeight: FontWeight.w800)),
                          ),
                        ),
                      Text(name.isEmpty ? title : 'копит: $title',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: main),
                      const SizedBox(height: Gap.xs),
                      Row(children: <Widget>[
                        if (progress case final double p) ...<Widget>[
                          Expanded(
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(WorldRadii.tag),
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
                            child: Text(count,
                                maxLines: 1,
                                softWrap: false,
                                style:
                                    main.copyWith(fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ]),
                    ],
                  )
                : Row(
                    children: <Widget>[
                      const Pictogram(Pic.flag,
                          size: 16, color: WorldColors.goal),
                      const SizedBox(width: Gap.xs),
                      if (name.isNotEmpty)
                        Flexible(
                          flex: 2,
                          child: FittedBox(
                            key: const ValueKey<String>('room:name'),
                            fit: BoxFit.scaleDown,
                            child: Text(name,
                                maxLines: 1,
                                softWrap: false,
                                style:
                                    main.copyWith(fontWeight: FontWeight.w800)),
                          ),
                        ),
                      Flexible(
                        flex: 3,
                        child: Text(name.isEmpty ? title : ' копит: $title',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: main),
                      ),
                      const SizedBox(width: Gap.sm),
                      if (progress case final double p)
                        SizedBox(
                          width: 48,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(WorldRadii.tag),
                            child: LinearProgressIndicator(
                              value: p,
                              minHeight: 6,
                              color: WorldColors.goal,
                              backgroundColor: WorldColors.raised,
                            ),
                          ),
                        ),
                      const SizedBox(width: Gap.xs),
                      Text(count,
                          maxLines: 1,
                          softWrap: false,
                          style: main.copyWith(fontWeight: FontWeight.w800)),
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
  const _PadView({required this.knob});

  final Offset knob;

  @override
  Widget build(BuildContext context) {
    const double size = _RoomScreenState.stickSize;
    const double k = size * 0.42;
    return SizedBox.square(
      key: const ValueKey<String>('room:pad'),
      dimension: size,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: WorldColors.panel.withValues(alpha: 0.55),
                shape: BoxShape.circle,
                border: Border.all(color: WorldColors.line, width: 2),
              ),
            ),
          ),
          Positioned(
            left: size / 2 + knob.dx - k / 2,
            top: size / 2 + knob.dy - k / 2,
            width: k,
            height: k,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: WorldColors.raised,
                shape: BoxShape.circle,
                border: Border.all(color: WorldColors.gold, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
