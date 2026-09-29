import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/art/sprite_anim.dart';
import '../../../core/feel.dart';
import '../../../core/theme.dart';
import '../../../domain/world/contract.dart';
import '../finni_walker.dart';
import '../joystick.dart';
import '../onboarding/onboarding_script.dart';
import '../world_help.dart';
import '../world_layout.dart';
import '../world_routes.dart';
import '../home/hud_chips.dart';
import '../home/hud_strip.dart';
import '../world_state.dart';
import '../../../core/world_theme.dart';
import 'city_filler.dart';
import 'city_geometry.dart';

export 'city_geometry.dart' show CityVariant, cityVariant;

/// Куда ведёт здание города: id из `assets/art/registry.json → buildings`
/// → маршрут нового мира (`docs/game/screen-city-iso.md`, «Правила»).
///
/// `home` — возврат в комнату: экран города снимается со стека, если под
/// ним есть что-то, иначе заменяется комнатой.
const Map<String, String> cityBuildingRoutes = <String, String>{
  'home': WorldRoutes.room, // S1
  'grocery': WorldRoutes.shop, // S4
  'job-centre': WorldRoutes.jobs, // S6
  'pet-shop': WorldRoutes.petShop, // S5
  'park': WorldRoutes.leisure, // S8
  'cinema': WorldRoutes.leisure, // S8
  'piggy-bank': WorldRoutes.piggy, // S9
};

/// Здание на карте: подпись и значок запасной кнопки. Клетка — у варианта
/// раскладки ([CityGeometry.cells]).
@immutable
class CityBuilding {
  const CityBuilding(this.id, this.name, this.icon);

  final String id;
  final String name;
  final IconData icon;

  String get route => cityBuildingRoutes[id]!;
}

/// Семь зданий в порядке запасного списка.
const List<CityBuilding> cityBuildings = <CityBuilding>[
  CityBuilding('home', 'Дом', Icons.home_rounded),
  CityBuilding('grocery', 'Магазин', Icons.shopping_basket_rounded),
  CityBuilding('job-centre', 'Дом работы', Icons.work_rounded),
  CityBuilding('pet-shop', 'Зоомагазин', Icons.pets_rounded),
  CityBuilding('park', 'Парк', Icons.park_rounded),
  CityBuilding('cinema', 'Кино и кафе', Icons.local_movies_rounded),
  CityBuilding('piggy-bank', 'Копилка', Icons.savings_rounded),
];

/// Башни Москва-Сити за городом ([CityGeometry.skyline]): декор стадии
/// «В Москве», не место. Рисуются раньше зданий, поэтому ни одно здание не
/// закрывают, и в [_CityMapState._hit] их нет — тап по башне попадает в
/// здание перед ней или никуда.

/// S2 · Город: 7 зданий в изометрии, тап по силуэту ведёт в экран здания,
/// «!» — над зданием, где ждёт событие. Под картой — те же здания кнопками
/// (доступность и слабые устройства).
///
/// Здание с «!» — `World.eventBuildingId` (A10): событие недели ждёт выбора.
///
/// Город растёт вместе с Финни: на стадии «В Москве» за домами встают башни
/// Москва-Сити ([citySkyline]). Деревня и город — те же семь зданий.
class CityScreen extends StatefulWidget {
  const CityScreen({super.key, this.variant = cityVariant});

  /// Раскладка карты: A — вертикально, B — как Clash of Clans.
  final CityVariant variant;

  /// Размер карты при 1× варианта по умолчанию: сетка, коробка здания,
  /// место над картой для значков и «!».
  static Size get mapBase => mapBaseFor(cityVariant);

  static Size mapBaseFor(CityVariant v) => CityGeometry.of(v).base;

  @override
  State<CityScreen> createState() => _CityScreenState();
}

class _CityScreenState extends State<CityScreen> {
  AssetRegistry? _reg;

  /// Куда отведена ручка джойстика — карта ведёт по нему Финни.
  final ValueNotifier<Offset> _stick = ValueNotifier<Offset>(Offset.zero);

  /// Здание, выбранное кнопкой списка или TalkBack: камера едет к нему.
  /// Счётчик — чтобы повторный выбор того же здания тоже сработал.
  final ValueNotifier<(CityBuilding, int)?> _focus =
      ValueNotifier<(CityBuilding, int)?>(null);

  CityGeometry get _geo => CityGeometry.of(widget.variant);

  /// Здание, у которого Финни остановился джойстиком: кнопка «войти».
  CityBuilding? _near;

  @override
  void dispose() {
    _stick.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setNear(CityBuilding? b) {
    if (!identical(b, _near) && mounted) setState(() => _near = b);
  }

  /// Полоса внизу под джойстик и кнопку «войти» (Денис, 1001): своё место,
  /// а не поверх карты и списка — ничего нажимаемого не закрывает (ревью
  /// 29.09). С выключенными «Анимациями» джойстика нет — ходьбы нет (ТЗ
  /// 3.6.7); здания, значки и список мест работают как раньше.
  Widget? _stickBar() {
    final bool on = context.motionOnListening;
    final CityBuilding? near = _near;
    if (!on && near == null) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.sm, Gap.xs),
      child: SizedBox(
        height: 96,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: near == null
                    ? const SizedBox.shrink()
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _EnterButton(
                          key: const ValueKey<String>('city:near'),
                          building: near,
                          onTap: () => _open(near),
                        ),
                      ),
              ),
            ),
            if (on)
              Joystick(
                key: const ValueKey<String>('city:joystick'),
                size: 96,
                onChanged: (Offset d) => _stick.value = d,
              ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    AssetRegistry.load().then((AssetRegistry r) {
      if (mounted) setState(() => _reg = r);
    }, onError: (Object _) {});
  }

  void _open(CityBuilding b) {
    final NavigatorState nav = Navigator.of(context);
    if (b.id == 'home') {
      if (nav.canPop()) {
        nav.pop();
      } else {
        nav.pushReplacementNamed(WorldRoutes.room);
      }
      return;
    }
    // Парк и кино ведут в один экран досуга — он узнаёт место по аргументу.
    nav.pushNamed(b.route, arguments: b.id);
  }

  void _openEvent(CityBuilding b) =>
      Navigator.of(context).pushNamed(WorldRoutes.event, arguments: b.id);

  void _back() {
    final NavigatorState nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed(WorldRoutes.room);
    }
  }

  /// Здание, где ждёт событие недели, — из мира; без [WorldState] — нет.
  String? get _eventId => maybeWorldState(context)?.world.eventBuildingId;

  /// Стадия роста — из мира; без [WorldState] — деревня.
  WorldStage get _stage =>
      maybeWorldState(context)?.snapshot.stage ?? WorldStage.village;

  CityBuilding? get _eventBuilding {
    final String? id = _eventId;
    for (final CityBuilding b in cityBuildings) {
      if (b.id == id) return b;
    }
    return null;
  }

  void _help() {
    showHelp(
        context,
        'Что здесь?',
        'Это город. Нажми на здание — и Финни дойдёт туда. Или веди '
            'Финни сам джойстиком внизу и жми кнопку у здания. Значок над '
            'зданием говорит, что там делают.\n\n'
            'Дом работы — смены и монеты. Магазин и Зоомагазин — покупки. '
            'Парк и Кино — отдых для 😊. Копилка — цель.\n\n'
            '«!» над зданием — там что-то ждёт. Здания есть и кнопками '
            'в списке мест.');
  }

  Widget _helpButton() => HelpButton(
        key: const ValueKey<String>('city:help'),
        onPressed: _help,
      );

  Widget _backButton() => IconButton(
        key: const ValueKey<String>('city:back'),
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        tooltip: 'Назад',
        onPressed: _back,
      );

  /// Подсказка над картой — коротко, для 7–11 лет (корневая сессия, 1014):
  /// из `onboarding.json → city`; файла нет — запасная.
  String _hint(CityBuilding? ev) {
    final OnboardingScript? s = context.read<OnboardingScript?>();
    if (ev == null) return s?.cityHint ?? 'Куда пойдём? Нажми на здание.';
    return s?.cityEvent[ev.id] ?? '${ev.name}: там что-то ждёт!';
  }

  Widget _map(CityBuilding? ev) => _CityMap(
        geo: _geo,
        focus: _focus,
        registry: _reg,
        eventBuildingId: ev?.id,
        stage: _stage,
        profile: maybeWorldState(context)?.profile ?? const WorldProfile(),
        stick: _stick,
        onNear: _setNear,
        onOpen: _open,
        onEvent: _openEvent,
      );

  /// Кнопка списка: камера едет к зданию (Денис, 29.09: экран следует за
  /// Финни), и сразу — экран здания; вернёшься — город стоит у него.
  Widget _button(CityBuilding b, CityBuilding? ev, {VoidCallback? before}) =>
      _BuildingButton(
        building: b,
        hasEvent: b.id == ev?.id,
        onTap: () {
          before?.call();
          _focus.value = (b, (_focus.value?.$2 ?? 0) + 1);
          _open(b);
        },
      );

  @override
  Widget build(BuildContext context) {
    final CityBuilding? ev = _eventBuilding;
    return OrientationSplit(
      landscape: (BuildContext context) => _landscape(context, ev),
      portrait: (BuildContext context) => _portrait(context, ev),
    );
  }

  /// Альбомная — основная: карта во всю высоту слева (целый масштаб по
  /// высоте), «Назад» — в её пустом левом верхнем углу; справа «Город»,
  /// подсказка и здания кнопками (столбец прокручивается).
  Widget _landscape(BuildContext context, CityBuilding? ev) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: _landMap(ev)),
            const VerticalDivider(
                width: 1, thickness: 1, color: WorldColors.line),
            // Джойстик — справа внизу, над пустой правой частью кнопок
            // списка. Карта — окно камеры на всё свободное место, список —
            // узкий столбец.
            SizedBox(
              width: _landListWidth,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // Показатели — фишками, как в комнате (вариант В); не
                        // на карте: там здания, которые нажимают.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              Gap.sm, Gap.sm, Gap.sm, 0),
                          child: _chips(),
                        ),
                        // Заголовок «Город» снят (вариант В): высота — списку
                        // мест под показателями; подсказка — в прокрутке.
                        Expanded(
                          child: SingleChildScrollView(
                            key: const ValueKey<String>('city:list'),
                            padding: const EdgeInsets.fromLTRB(
                                Gap.md, Gap.xs, Gap.md, Gap.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                // Подсказка — в прокрутке: узкий столбец и
                                // шрифт 1,3 не выдавливают список.
                                Text(_hint(ev), style: text.bodyLarge),
                                const SizedBox(height: Gap.sm),
                                for (final CityBuilding b in cityBuildings)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: Gap.sm),
                                    child: _button(b, ev),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_stickBar() case final Widget bar) bar,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Альбомная: окно камеры на всю высоту, «Назад» — поверх в углу.
  Widget _landMap(CityBuilding? ev) => Stack(
        children: <Widget>[
          Positioned.fill(child: _map(ev)),
          Positioned(left: 0, top: 0, child: _backButton()),
        ],
      );

  /// Альбомная: ширина столбца мест — «Кино и кафе» при шрифте 1,3
  /// переносится, а не режется.
  static const double _landListWidth = 220;

  /// Портрет: подсказка, окно камеры на всё место, джойстик поверх карты
  /// справа внизу (полупрозрачный), внизу — тонкая полоса с кнопкой «Все
  /// места» (список — листом) и «войти» у здания. Полоса ≤ 12 % высоты.
  Widget _portrait(BuildContext context, CityBuilding? ev) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool on = context.motionOnListening;
    final CityBuilding? near = _near;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Одна полоса сверху (≤ ~21 % на обе полосы, 29.09): «Назад»,
            // показатели, «?» — как в комнате. «Назад» и «?» всегда под
            // пальцем (ТЗ 2.5.1.3). Не на карте: там «!» и здания.
            Padding(
              key: const ValueKey<String>('city:top'),
              padding:
                  const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.sm, Gap.xs),
              // Та же стеклянная полоса, что в комнате (29.09): один ряд —
              // подсказка остаётся внизу, полосы ≤ 21 % высоты.
              child: switch (maybeWorldState(context)) {
                final WorldState ws => HudStrip(
                    snapshot: ws.snapshot,
                    registry: _reg,
                    leading: _backButton(),
                    tools: <Widget>[_helpButton()]),
                null => Row(children: <Widget>[
                    HudBacking(child: _backButton()),
                    const Spacer(),
                    HudBacking(child: _helpButton()),
                  ]),
              },
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(child: _map(ev)),
                  if (on)
                    Positioned(
                      right: Gap.sm,
                      bottom: Gap.sm,
                      child: Opacity(
                        opacity: _stickOpacity,
                        child: Joystick(
                          key: const ValueKey<String>('city:joystick'),
                          size: 96,
                          onChanged: (Offset d) => _stick.value = d,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              key: const ValueKey<String>('city:bar'),
              padding:
                  const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.xs),
              child: Row(
                children: <Widget>[
                  _placesButton(ev),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      // Подсказка — в нижней полосе рядом с «Все места»;
                      // у здания её место занимает «войти».
                      child: near == null
                          ? Text(_hint(ev),
                              key: const ValueKey<String>('city:hint'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: text.bodyMedium)
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _EnterButton(
                                key: const ValueKey<String>('city:near'),
                                building: near,
                                onTap: () => _open(near),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Показатели города (альбомная, над списком мест) — те же фишки, что в
  /// комнате, и «?»; без мира (отдельный тест экрана) — только «?».
  Widget _chips() {
    final WorldState? ws = maybeWorldState(context);
    if (ws == null) {
      return Align(
          alignment: Alignment.centerRight,
          child: HudBacking(child: _helpButton()));
    }
    return HudChips(
        snapshot: ws.snapshot, dense: true, trailing: <Widget>[_helpButton()]);
  }

  /// Джойстик поверх карты — полупрозрачный: город под ним виден.
  static const double _stickOpacity = 0.75;

  /// «Все места»: запасной вход ко всем зданиям — лист со списком. «!» на
  /// кнопке — где-то ждёт событие.
  Widget _placesButton(CityBuilding? ev) => OutlinedButton(
        key: const ValueKey<String>('city:places'),
        onPressed: () => _showPlaces(ev),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(TapSize.min, TapSize.min),
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.list_rounded),
            const SizedBox(width: Gap.sm),
            const Text('Все места'),
            if (ev != null) ...<Widget>[
              const SizedBox(width: Gap.sm),
              _EventDot(key: ValueKey<String>('city:button-event:${ev.id}')),
            ],
          ],
        ),
      );

  void _showPlaces(CityBuilding? ev) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheet) {
        final TextTheme text = Theme.of(sheet).textTheme;
        return SafeArea(
          child: SingleChildScrollView(
            key: const ValueKey<String>('city:list'),
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Все места', style: text.titleMedium),
                const SizedBox(height: Gap.sm),
                for (final CityBuilding b in cityBuildings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child:
                        _button(b, ev, before: () => Navigator.of(sheet).pop()),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Карта: неподвижная картинка из спрайтов с зонами касания по силуэту.
class _CityMap extends StatefulWidget {
  const _CityMap({
    required this.geo,
    required this.registry,
    required this.eventBuildingId,
    required this.stage,
    required this.profile,
    required this.stick,
    required this.onNear,
    required this.onOpen,
    required this.onEvent,
    required this.focus,
  });

  /// Раскладка варианта: сетка, клетки зданий, дороги, декор.
  final CityGeometry geo;
  final AssetRegistry? registry;
  final String? eventBuildingId;
  final WorldStage stage;

  /// Облик Финни, который ходит по карте.
  final WorldProfile profile;

  /// Ручка джойстика: пока отведена, Финни идёт по земле города.
  final ValueListenable<Offset> stick;

  /// Финни встал у здания (или отошёл — null).
  final ValueChanged<CityBuilding?> onNear;
  final ValueChanged<CityBuilding> onOpen;
  final ValueChanged<CityBuilding> onEvent;

  /// Здание, выбранное списком или TalkBack: камера едет к нему.
  final ValueListenable<(CityBuilding, int)?> focus;

  /// Коробка под спрайт, пока арт не пришёл (и для нарезки зон касания).
  static const Size box = Size(122, 82);

  /// Значок роли над зданием: диаметр в логических px.
  static const double badge = 32;

  /// Зона касания значка — не меньше 48 dp (ТЗ §3.6), рисунок — [badge].
  static const double badgeTap = 48;

  /// Высота Финни на карте при 1×.
  static const double finniHeight = 40;

  @override
  State<_CityMap> createState() => _CityMapState();
}

class _CityMapState extends State<_CityMap>
    with SingleTickerProviderStateMixin {
  /// Реальные размеры спрайтов и их альфа — для попадания в силуэт.
  final Map<String, _Alpha> _alpha = <String, _Alpha>{};
  AssetRegistry? _loadedFor;

  CityGeometry get _geo => widget.geo;

  /// У какого здания стоит Финни: выходит из дома, потом — где был.
  CityBuilding _at = cityBuildings.first;

  /// Финни идёт — второе касание ждёт.
  bool _walking = false;

  /// Сколько длится текущий путь (для [FinniWalker]).
  Duration _walk = Duration.zero;

  /// Где Финни, если его водят джойстиком (ноги, px карты при 1×).
  Offset? _free;

  /// Ручка отведена — кадры ходьбы.
  bool _moving = false;

  /// Масштаб карты — постоянный для варианта ([CityCamera.scale]).
  double get _k => CityCamera.scale(_geo.variant);

  /// Камера (Денис, 29.09: «как в paper mario экран должен следовать за
  /// финни»): карта крупнее окна, окно — две прокрутки. Палец листает
  /// карту, ходьба Финни везёт камеру за ним.
  final ScrollController _camX = ScrollController();
  final ScrollController _camY = ScrollController();

  /// Для какого окна камера уже вставала на Финни (поворот — заново).
  Size? _centeredFor;

  /// Поле вокруг карты, если окно больше неё: карта по центру окна.
  Offset _inset = Offset.zero;

  /// Двигатель джойстика — создаётся при первом касании ручки. 🔴 Не
  /// `late final`: иначе dispose() создавал бы тикер уже после
  /// деактивации (TickerMode ищет предка — падение на Flutter 3.41.7, CI
  /// 29.09), если ручку ни разу не трогали.
  JoystickDriver? _driveOrNull;
  JoystickDriver get _drive =>
      _driveOrNull ??= JoystickDriver(this, onStep: _step);

  /// Скорость хода джойстиком, px карты в секунду: через весь город за ~3 с.
  static const double _speed = 150;

  @override
  void initState() {
    super.initState();
    widget.stick.addListener(_onStick);
    widget.focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(_CityMap old) {
    super.didUpdateWidget(old);
    if (!identical(old.stick, widget.stick)) {
      old.stick.removeListener(_onStick);
      widget.stick.addListener(_onStick);
    }
    if (!identical(old.focus, widget.focus)) {
      old.focus.removeListener(_onFocus);
      widget.focus.addListener(_onFocus);
    }
    _loadAlpha();
  }

  @override
  void dispose() {
    widget.stick.removeListener(_onStick);
    widget.focus.removeListener(_onFocus);
    _driveOrNull?.dispose();
    _camX.dispose();
    _camY.dispose();
    super.dispose();
  }

  /// Здание выбрано списком или TalkBack: Финни уже там (он вошёл), камера
  /// едет к зданию.
  void _onFocus() {
    final CityBuilding? b = widget.focus.value?.$1;
    if (b == null || !mounted) return;
    setState(() {
      _free = null;
      _at = b;
      _walk = Duration.zero;
    });
    _follow(_stand(b), animate: true, centre: true);
  }

  void _onStick() {
    _drive.set(widget.stick.value);
    if (!_drive.moving && _moving) setState(() => _moving = false);
  }

  /// Камера держит точку карты [p] (px при 1×) в мёртвой зоне — средних
  /// [CityCamera.deadZone] окна; вышла — окно сдвигается ровно настолько,
  /// чтобы вернуть её на край зоны. [centre] — поставить точку в центр.
  /// Всегда в пределах карты (прокрутка не выходит за края). [animate] —
  /// плавно за [CityCamera.ease]; «Анимации» выкл. — сразу.
  void _follow(Offset p, {bool animate = false, bool centre = false}) {
    final Duration ease =
        animate ? context.motion(CityCamera.ease) : Duration.zero;
    for (final (ScrollController cam, double at)
        in <(ScrollController, double)>[
      (_camX, p.dx * _k + _inset.dx),
      (_camY, p.dy * _k + _inset.dy),
    ]) {
      if (!cam.hasClients) continue;
      final ScrollPosition pos = cam.position;
      final double vp = pos.viewportDimension, now = pos.pixels;
      double to;
      if (centre) {
        to = at - vp / 2;
      } else {
        final double zone = vp * CityCamera.deadZone;
        final double lo = now + (vp - zone) / 2, hi = lo + zone;
        to = at < lo
            ? now - (lo - at)
            : at > hi
                ? now + (at - hi)
                : now;
      }
      to = to.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if ((to - now).abs() < 0.5) continue;
      if (ease == Duration.zero) {
        cam.jumpTo(to);
      } else {
        cam.animateTo(to, duration: ease, curve: Curves.easeOut);
      }
    }
  }

  /// Куда камера смотрит на входе: между Финни и зданием с «!» (с самим
  /// «!» над ним), без события — между Финни и центром города. Так видно и
  /// героя, и то, куда идти.
  Offset _startFocus() {
    final Offset f = _free ?? _stand(_at);
    Offset other = _geo.base.center(Offset.zero);
    for (final CityBuilding b in cityBuildings) {
      if (b.id == widget.eventBuildingId) {
        other = _rect(b).topCenter - const Offset(0, 40);
      }
    }
    return Offset((f.dx + other.dx) / 2, (f.dy + other.dy) / 2);
  }

  /// Камера на входе: на [_startFocus]; если Финни и «!» вместе в окно не
  /// влезают — окно сдвигается так, чтобы «!» был виден целиком.
  void _startCamera() {
    _follow(_startFocus(), centre: true);
    for (final CityBuilding b in cityBuildings) {
      if (b.id != widget.eventBuildingId) continue;
      final Rect r = _rect(b);
      // Как рисуется «!»: над значком роли, 48 × 48 (не масштабируется).
      const double side = 48, pad = 8;
      final double top = r.top * _k - _CityMap.badge / 2 - side + 4 + _inset.dy;
      final double left = r.center.dx * _k - side / 2 + _inset.dx;
      for (final (ScrollController cam, double lo, double hi)
          in <(ScrollController, double, double)>[
        (_camY, top, top + side),
        (_camX, left, left + side),
      ]) {
        if (!cam.hasClients) continue;
        final ScrollPosition p = cam.position;
        double to = p.pixels;
        if (lo - pad < to) to = lo - pad;
        if (hi + pad > to + p.viewportDimension) {
          to = hi + pad - p.viewportDimension;
        }
        to = to.clamp(p.minScrollExtent, p.maxScrollExtent);
        if (to != p.pixels) cam.jumpTo(to);
      }
    }
  }

  /// Шаг от джойстика: по земле; упёрся — скользит вдоль края.
  void _step(double seconds, Offset dir) {
    if (!mounted || _walking) return;
    final Offset from = _free ?? _stand(_at);
    final Offset d = dir * (_speed * seconds);
    Offset to = from + d;
    // Стоит у края земли (у крайнего здания) — ходить можно, лишь бы шаг
    // вёл на землю или вдоль неё; вне земли шаг не делается.
    if (_geo.onGround(from)) {
      if (!_geo.onGround(to)) to = from + Offset(d.dx, 0);
      if (!_geo.onGround(to)) to = from + Offset(0, d.dy);
      if (!_geo.onGround(to)) to = from;
    }
    CityBuilding? near;
    double best = _geo.tileW * 0.3;
    for (final CityBuilding b in cityBuildings) {
      final double dist = (_stand(b) - to).distance;
      if (dist <= best) {
        best = dist;
        near = b;
      }
    }
    setState(() {
      _free = to;
      _moving = true;
      _walk = Duration.zero;
      if (near != null) _at = near;
    });
    _follow(to);
    widget.onNear(near);
  }

  /// Путь по карте: в пределах секунды (ТЗ §3.4 — отклик ≤ 1 с).
  static const int _walkMinMs = 350;
  static const int _walkMaxMs = 850;

  Duration _walkTime(CityBuilding from, CityBuilding to) {
    final double t = (_stand(to) - _stand(from)).distance / _geo.base.width;
    return Duration(
        milliseconds:
            (_walkMinMs + (_walkMaxMs - _walkMinMs) * t.clamp(0.0, 1.0))
                .round());
  }

  /// Где Финни стоит у здания (ноги, px карты при 1×): на улице справа от
  /// его переднего угла, чуть ближе к зрителю — перед зданием, не за ним.
  Offset _stand(CityBuilding b) => _anchor(b) + Offset(_geo.tileW * 0.26, 2);

  /// Тап по зданию на карте: Финни идёт туда, потом экран здания.
  /// «Анимации» выкл. или Финни уже там — сразу.
  Future<void> _walkTo(CityBuilding b) async {
    if (_walking) return;
    final Duration walk = context.motion(_walkTime(_at, b));
    if (_free != null) {
      // Водили джойстиком — от этой точки Финни идёт к зданию.
      setState(() => _free = null);
      widget.onNear(null);
    }
    if (identical(b, _at) || walk == Duration.zero) {
      setState(() {
        _at = b;
        _walk = Duration.zero;
      });
      return widget.onOpen(b);
    }
    setState(() {
      _at = b;
      _walk = walk;
      _walking = true;
    });
    _follow(_stand(b), animate: true);
    await Future<void>.delayed(walk);
    if (!mounted) return;
    setState(() {
      _walking = false;
      _walk = Duration.zero;
    });
    // Пока Финни шёл, ребёнок открыл место кнопкой списка — город уже
    // закрыт другим экраном, второй переход не нужен.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    widget.onOpen(b);
  }

  /// Финни на карте: облик ребёнка; кадры ходьбы нарисованы для первого
  /// облика — остальные идут своим обликом, покачиваясь.
  Widget _finni(AssetRegistry? reg, bool walking, double k) {
    final WorldProfile p = widget.profile;
    final SpriteRef? sheet = reg?.finni(p.species);
    // Кадры ходьбы своего облика (`finni_walk`, ветка арта), если есть.
    final SpriteRef? walkSheet = reg?.finniWalk(p.species);
    if (walking && walkSheet != null) {
      return SpriteAnim(
          sprite: walkSheet,
          tag: 'walk-${p.look}',
          height: _CityMap.finniHeight * k);
    }
    if (walking &&
        sheet != null &&
        p.look == 1 &&
        (reg?.finniHasTag(p.species, 'walk') ?? false)) {
      return SpriteAnim(
          sprite: sheet, tag: 'walk', height: _CityMap.finniHeight * k);
    }
    final List<String> looks = reg?.finniLooks(p.species) ?? const <String>[];
    final String? still =
        looks.length >= p.look ? looks[p.look - 1] : looks.firstOrNull;
    return SizedBox(
      height: _CityMap.finniHeight * k,
      child: Image.asset(
        still ?? '',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) =>
            SizedBox.square(dimension: _CityMap.finniHeight * k),
      ),
    );
  }

  /// Дальние первыми: так они и рисуются (painter's algorithm).
  List<CityBuilding> get _backToFront => List<CityBuilding>.of(cityBuildings)
    ..sort((CityBuilding a, CityBuilding b) {
      final Offset pa = _anchor(a), pb = _anchor(b);
      return pa.dy != pb.dy ? pa.dy.compareTo(pb.dy) : pa.dx.compareTo(pb.dx);
    });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAlpha();
  }

  void _loadAlpha() {
    final AssetRegistry? reg = widget.registry;
    if (reg == null || identical(reg, _loadedFor)) return;
    _loadedFor = reg;
    for (final String id in <String>[
      for (final CityBuilding b in cityBuildings) b.id,
      for (final (String id, Offset _) in _geo.skyline) id,
    ]) {
      final String? path = reg.building(id);
      if (path == null) continue;
      _Alpha.load(path).then((_Alpha a) {
        if (mounted) setState(() => _alpha[id] = a);
      }, onError: (Object _) {});
    }
  }

  /// Нижний угол клетки здания (якорь спрайта) в пикселях карты при 1×.
  Offset _anchor(CityBuilding b) => _geo.anchor(_geo.cells[b.id]!);

  Size _spriteSize(CityBuilding b) {
    final _Alpha? a = _alpha[b.id];
    return a == null ? _CityMap.box : a.size;
  }

  /// Прямоугольник спрайта при 1×: якорь — низ-центр.
  Rect _rect(CityBuilding b) {
    final Offset a = _anchor(b);
    final Size s = _spriteSize(b);
    return Rect.fromLTWH(
        a.dx - s.width / 2, a.dy - s.height, s.width, s.height);
  }

  /// От ближнего к дальнему: сперва попадание в непрозрачный пиксель, затем —
  /// в прямоугольник спрайта (альфа ещё не прочитана или тап мимо силуэта).
  CityBuilding? _hit(Offset p) {
    final List<CityBuilding> front = _backToFront.reversed.toList();
    for (final CityBuilding b in front) {
      final _Alpha? a = _alpha[b.id];
      final Rect r = _rect(b);
      if (a != null && r.contains(p) && a.opaqueAt(p - r.topLeft)) return b;
    }
    for (final CityBuilding b in front) {
      if (_rect(b).contains(p)) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final Size base = _geo.base;
          final double k = _k;
          // Окно камеры; без границ (карта вне окна) — карта целиком.
          final Size view = Size(
              c.hasBoundedWidth ? c.maxWidth : base.width * k,
              c.hasBoundedHeight ? c.maxHeight : base.height * k);
          _inset = Offset(math.max(0, (view.width - base.width * k) / 2),
              math.max(0, (view.height - base.height * k) / 2));
          final AssetRegistry? reg = widget.registry;
          final List<Widget> layers = <Widget>[
            Positioned.fill(
              child: CustomPaint(
                painter:
                    CityGroundPainter(geo: _geo, stage: widget.stage, k: k),
              ),
            ),
          ];
          // Башни — за зданиями, без подписи и касания: это вид, не место.
          // Размер известен только после чтения картинки — до того башни нет.
          if (widget.stage == WorldStage.moscow) {
            for (final (String id, Offset bottom) in _geo.skyline) {
              final Size? s = _alpha[id]?.size;
              if (s == null) continue;
              layers.add(Positioned(
                key: ValueKey<String>('city:skyline:$id'),
                left: (bottom.dx - s.width / 2) * k,
                top: (bottom.dy - s.height) * k,
                width: s.width * k,
                height: s.height * k,
                // Верх картинки срезан по кадру — растворяем его в небе,
                // чтобы башня уходила вверх, а не обрывалась.
                child: IgnorePointer(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (Rect r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Color(0x00000000), Color(0xFF000000)],
                      stops: <double>[0, 0.3],
                    ).createShader(r),
                    child: PixelImage(reg?.building(id), scale: k),
                  ),
                ),
              ));
            }
          }
          // Финни: у здания, где он сейчас, или там, куда довёл джойстик.
          // Сменился масштаб (поворот) — Финни встаёт на место сразу.
          final Offset feet = _free ?? _stand(_at);
          if (_centeredFor != view) {
            _centeredFor = view;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _startCamera();
            });
          }
          final Widget finniLayer = KeyedSubtree(
            key: ValueKey<String>('city:finni:frame:$k'),
            child: FinniWalker(
              key: const ValueKey<String>('city:finni'),
              at: feet * k,
              duration: _free != null ? Duration.zero : _walk,
              bob: 2.0 * k,
              builder: (bool walking) => IgnorePointer(
                child: ExcludeSemantics(
                  child: _finni(reg, walking || _moving, k),
                ),
              ),
            ),
          );
          // Простое 2.5D: здания, декор и Финни — по низу, дальние первыми.
          // При равном низе Финни впереди (он стоит перед своим зданием).
          final List<(double, int, Widget)> depth = <(double, int, Widget)>[
            (feet.dy, 1, finniLayer),
          ];
          final List<CityDecor> decor = _geo.decor(widget.stage);
          for (int i = 0; i < decor.length; i++) {
            final CityDecor d = decor[i];
            final Rect r = cityDecorRect(d);
            depth.add((
              d.y,
              0,
              Positioned(
                key: ValueKey<String>('city:decor:$i'),
                left: r.left * k,
                top: r.top * k,
                width: r.width * k,
                height: r.height * k,
                child: CityDecorView(decor: d, k: k, registry: reg),
              ),
            ));
          }
          for (final CityBuilding b in _backToFront) {
            final Rect r = _rect(b);
            depth.add((
              _anchor(b).dy,
              0,
              Positioned(
                key: ValueKey<String>('city:layer:${b.id}'),
                left: r.left * k,
                top: r.top * k,
                width: r.width * k,
                height: r.height * k,
                child: Semantics(
                  button: true,
                  label: b.name,
                  onTap: () {
                    _at = b;
                    _follow(_stand(b), animate: true, centre: true);
                    widget.onOpen(b);
                  },
                  excludeSemantics: true,
                  child: KeyedSubtree(
                    key: ValueKey<String>('city:building:${b.id}'),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: PixelImage(
                        reg?.building(b.id),
                        scale: k,
                        fallback: _NoArt(b),
                      ),
                    ),
                  ),
                ),
              ),
            ));
          }
          // При равных низе и приоритете — порядок добавления.
          final List<int> order = List<int>.generate(depth.length, (int i) => i)
            ..sort((int a, int b) {
              final (double ya, int pa, _) = depth[a];
              final (double yb, int pb, _) = depth[b];
              if (ya != yb) return ya.compareTo(yb);
              if (pa != pb) return pa.compareTo(pb);
              return a.compareTo(b);
            });
          layers.addAll(order.map((int i) => depth[i].$3));
          // Значок роли над каждым зданием: что там делают (разведка 29.09,
          // §3). Касание — то же, что по зданию; для TalkBack здание уже
          // кнопка со словом. Рисунок 32, зона касания 48 (ТЗ §3.6).
          for (final CityBuilding b in cityBuildings) {
            final Rect r = _rect(b);
            const double d = _CityMap.badge, t = _CityMap.badgeTap;
            layers.add(Positioned(
              left: r.center.dx * k - t / 2,
              top: r.top * k - t / 2,
              width: t,
              height: t,
              child: ExcludeSemantics(
                child: GestureDetector(
                  key: ValueKey<String>('city:icon-tap:${b.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _walkTo(b),
                  child: Center(
                    child: SizedBox.square(
                      key: ValueKey<String>('city:icon:${b.id}'),
                      dimension: d,
                      child: _RoleBadge(b),
                    ),
                  ),
                ),
              ),
            ));
          }
          final String? evId = widget.eventBuildingId;
          for (final CityBuilding b in cityBuildings) {
            if (b.id != evId) continue;
            final Rect r = _rect(b);
            const double side = 48;
            layers.add(Positioned(
              left: r.center.dx * k - side / 2,
              top: r.top * k - _CityMap.badge / 2 - side + 4,
              width: side,
              height: side,
              child: _EventMarker(
                key: ValueKey<String>('city:event:${b.id}'),
                label: 'Событие: ${b.name}',
                onTap: () => widget.onEvent(b),
              ),
            ));
          }
          final Widget map = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (TapUpDetails d) {
              final CityBuilding? b = _hit(d.localPosition / k);
              if (b != null) _walkTo(b);
            },
            child: SizedBox(
              key: const ValueKey<String>('city:map'),
              width: base.width * k,
              height: base.height * k,
              child: Stack(clipBehavior: Clip.none, children: layers),
            ),
          );
          // Камера: окно на карту, листается пальцем по обеим осям, края
          // карты — упор (ClampingScrollPhysics), без «резинки».
          return SingleChildScrollView(
            key: const ValueKey<String>('city:cam-y'),
            controller: _camY,
            physics: const ClampingScrollPhysics(),
            child: SingleChildScrollView(
              key: const ValueKey<String>('city:cam-x'),
              controller: _camX,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              // Окно больше карты — поля той же травой, что опушка.
              child: ColoredBox(
                color: CityGround.of(widget.stage).outside,
                child: SizedBox(
                  width: math.max(view.width, base.width * k),
                  height: math.max(view.height, base.height * k),
                  child: Center(child: map),
                ),
              ),
            ),
          );
        },
      );
}

/// «!» над зданием с событием: отдельная цель касания 48 × 48.
class _EventMarker extends StatelessWidget {
  const _EventMarker({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap:
            onTap, // иначе excludeSemantics отсекает касание: TalkBack не нажмёт
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: onTap,
            radius: 24,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: WorldColors.gold,
                  shape: BoxShape.circle,
                  border: Border.all(color: WorldColors.goldEdge, width: 2),
                ),
                child: const Text(
                  '!',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: WorldColors.onGold,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Значок роли над зданием: круг панели с золотой каймой и значком того, что
/// там делают (тот же, что у кнопки в списке).
class _RoleBadge extends StatelessWidget {
  const _RoleBadge(this.building);

  final CityBuilding building;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: WorldColors.panel,
          shape: BoxShape.circle,
          border: Border.all(color: WorldColors.gold, width: 2),
        ),
        child: Center(
          child: Icon(building.icon, size: 18, color: WorldColors.text),
        ),
      );
}

/// Кнопка «войти» у здания, где Финни остановился джойстиком: значок и
/// название здания, не ниже 48 dp.
class _EnterButton extends StatelessWidget {
  const _EnterButton({super.key, required this.building, required this.onTap});

  final CityBuilding building;
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(building.icon, size: 20, color: WorldColors.text),
                  const SizedBox(width: Gap.xs),
                  Text(building.name,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: WorldColors.text)),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Заглушка, пока арт не загружен или его нет в реестре.
class _NoArt extends StatelessWidget {
  const _NoArt(this.building);

  final CityBuilding building;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: WorldColors.panel.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Center(child: Icon(building.icon, color: WorldColors.text)),
      );
}

/// Запасной вход: здание кнопкой со значком и подписью.
class _BuildingButton extends StatelessWidget {
  const _BuildingButton({
    required this.building,
    required this.hasEvent,
    required this.onTap,
  });

  final CityBuilding building;
  final bool hasEvent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        key: ValueKey<String>('city:button:${building.id}'),
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(TapSize.min),
          alignment: Alignment.centerLeft,
          padding:
              const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
        ),
        child: Row(
          children: <Widget>[
            Icon(building.icon),
            const SizedBox(width: Gap.sm),
            Expanded(child: Text(building.name)),
            if (hasEvent)
              Semantics(
                label: 'есть событие',
                child: Container(
                  key: ValueKey<String>('city:button-event:${building.id}'),
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: WorldColors.gold,
                    shape: BoxShape.circle,
                  ),
                  child: const ExcludeSemantics(
                    child: Text(
                      '!',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: WorldColors.onGold,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Жёлтый «!» на кнопке — там ждёт событие.
class _EventDot extends StatelessWidget {
  const _EventDot({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'есть событие',
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: WorldColors.gold,
            shape: BoxShape.circle,
          ),
          child: const ExcludeSemantics(
            child: Text(
              '!',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: WorldColors.onGold,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
}

/// Альфа-канал спрайта здания: попадание тапа в силуэт, а не в коробку.
class _Alpha {
  _Alpha(this.width, this.height, this._rgba, this.density);

  final int width;
  final int height;
  final Uint8List _rgba;

  /// Пикселей картинки на логический пиксель (`@4x` в имени файла).
  final double density;

  /// Размер на карте при 1×, в логических пикселях.
  Size get size => Size(width / density, height / density);

  static final Map<String, Future<_Alpha>> _cache = <String, Future<_Alpha>>{};

  static Future<_Alpha> load(String path) => _cache[path] ??= () async {
        final ByteData data = await rootBundle.load(path);
        final ui.Codec codec =
            await ui.instantiateImageCodec(data.buffer.asUint8List());
        final ui.Image img = (await codec.getNextFrame()).image;
        final ByteData? px =
            await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        final _Alpha a = _Alpha(
          img.width,
          img.height,
          px?.buffer.asUint8List() ?? Uint8List(0),
          artDensity(path),
        );
        img.dispose();
        return a;
      }();

  /// Непрозрачен ли пиксель в точке [p] (в логических пикселях спрайта).
  bool opaqueAt(Offset p) {
    final int x = (p.dx * density).floor(), y = (p.dy * density).floor();
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    final int i = (y * width + x) * 4 + 3;
    return i < _rgba.length && _rgba[i] > 16;
  }
}
