import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/icons.dart';
import '../../core/music.dart';
import '../../core/theme.dart';
import '../../core/world_theme.dart';
import '../../domain/world/contract.dart';
import 'home/day_energy_looks.dart' show progressIcon;
import 'home/hud_strip.dart' show HudStrip;
import 'home/plan_sheet.dart' show showPlanSheet;
import 'pic_text.dart';
import 'settings/world_reset.dart' show adultSectionOn;
import 'world_layout.dart';
import 'world_routes.dart';
import 'world_state.dart';

/// Раздел нижнего меню по макету Алины (концепт 03, `navGroup()` её
/// `app.js`): меню видно на **каждом** экране ребёнка, раздел экрана
/// подсвечен золотом.
///
/// Какой экран в каком разделе: комната — Дом; город, доска работ, смена,
/// магазин, зоомагазин, досуг, событие — Город; копилка, итоги недели,
/// перевод в банк — План; «Мой путь» и награды — Мой путь; настройки и
/// словарик — Ещё. Знакомство, «Взрослым», проверка и барьеры меню не
/// показывают — это не экраны игры.
///
/// [id] — часть ключа: `room:nav:<id>` в комнате, `dock:nav:<id>` на
/// остальных экранах (прежние ключи комнаты не меняются).
enum DockSection {
  home('home', Pic.house, 'Дом', 'Дом'),
  city('city', Pic.city, 'Город',
      'Город: работа — мини-игры, магазин, прогулки'),
  plan('week', Pic.wallet, 'План', 'План недели и копилка'),
  progress('progress', Pic.flag, 'Мой путь', 'Мой путь: прогресс'),
  more('more', Pic.list, 'Ещё', 'Ещё: настройки и другое');

  const DockSection(this.id, this.pic, this.label, this.said);

  final String id;
  final Pic pic;
  final String label;

  /// Подпись для TalkBack, когда раздел не текущий.
  final String said;
}

/// Нижнее меню: Дом · Город · План · Мой путь · Ещё (макет Алины, 18.10).
///
/// Значок и подпись светлые, текущий раздел — золотой ([WorldColors.goldText]).
/// «Ещё» — меню ([more]): музыка, «Взрослым» (за флагом), настройки, в
/// комнате ещё «Расставить вещи».
///
/// Подписи — одного кегля и не мельче 14 sp; если самая длинная («Мой
/// путь») не влезает в ячейку при крупном шрифте, все ужимаются одним общим
/// множителем, а не каждая по-своему.
///
/// [axis] — [Axis.vertical] в альбомной на экранах (столбец слева): высота
/// там дороже ширины, полоса 60 dp снизу съела бы шестую часть экрана.
class WorldDock extends StatelessWidget {
  const WorldDock({
    super.key,
    required this.current,
    required this.onTap,
    required this.more,
    this.prefix = 'dock',
    this.axis = Axis.horizontal,
  });

  final DockSection current;

  /// Касание раздела; null — раздел не нажимается (комната: «Дом»).
  final VoidCallback? Function(DockSection section) onTap;

  /// Оборачивает ячейку «Ещё» в меню (`<prefix>:menu`).
  final Widget Function(Widget child) more;

  /// `room` или `dock`: ключи `<prefix>:nav:<id>`.
  final String prefix;

  final Axis axis;

  /// Высота полосы снизу.
  static const double height = 60;

  /// Ширина столбца слева (альбомная).
  static const double railWidth = 84;

  /// Самая узкая ячейка — палец.
  static const double minCell = 48;

  /// Поле подписи с каждой стороны ячейки.
  static const double _pad = 2;

  static const TextStyle _label = TextStyle(
    fontSize: 14,
    height: 1.15,
    fontWeight: FontWeight.w700,
    shadows: HudStrip.textShadow,
  );

  /// Светлый цвет неактивного пункта (её `.dock button` `#ffefda`).
  static const Color idle = WorldColors.textTitle;

  @override
  Widget build(BuildContext context) {
    if (axis == Axis.vertical) {
      return Column(
        children: <Widget>[
          for (final DockSection s in DockSection.values)
            Expanded(child: _item(s, rail: true)),
        ],
      );
    }
    final Widget row = Row(
      children: <Widget>[
        for (final DockSection s in DockSection.values)
          Expanded(child: _item(s)),
      ],
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final TextScaler scaler = MediaQuery.textScalerOf(context);
        double widest = 0;
        for (final DockSection s in DockSection.values) {
          final TextPainter tp = TextPainter(
            text: TextSpan(
              text: s.label,
              style: DefaultTextStyle.of(context).style.merge(_label),
            ),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          widest = math.max(widest, tp.width);
          tp.dispose();
        }
        final double cell = box.maxWidth / DockSection.values.length - 2 * _pad;
        if (widest <= cell || widest == 0) return row;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler:
                TextScaler.linear(scaler.scale(14) / 14 * cell / widest),
          ),
          child: row,
        );
      },
    );
  }

  Widget _item(DockSection s, {bool rail = false}) {
    final bool here = s == current;
    final Color color = here ? WorldColors.goldText : idle;
    // Столбец альбомной: высота пункта — пятая часть 336 dp (телефон боком с
    // полосой состояния). Значок 24, подпись в одну строку; шире столбца
    // («Мой путь» при шрифте ×1,3) — пункт ужимается целиком, на ~1 %.
    final Widget icon = Pictogram(s.pic, size: rail ? 24 : 28, color: color);
    final Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        s == DockSection.progress ? progressIcon(icon) : icon,
        if (!rail) const SizedBox(height: 2),
        Text(
          s.label,
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.center,
          style: _label.copyWith(color: color),
        ),
      ],
    );
    final Widget content = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _pad),
        child: rail ? FittedBox(fit: BoxFit.scaleDown, child: column) : column,
      ),
    );
    final Widget cellBox = rail
        ? SizedBox(width: railWidth, child: content)
        : SizedBox(height: height, child: content);
    // «Ещё» — кнопка меню: TalkBack читает её подсказку («Ещё: …») и
    // открывает меню сам.
    if (s == DockSection.more) {
      return more(
        KeyedSubtree(
          key: ValueKey<String>('$prefix:nav:more'),
          child: cellBox,
        ),
      );
    }
    final VoidCallback? tap = onTap(s);
    return Semantics(
      button: tap != null,
      selected: here,
      label: here ? '${s.label} — ты здесь' : s.said,
      excludeSemantics: true,
      onTap: tap, // иначе excludeSemantics отсекает касание: TalkBack не нажмёт
      child: InkWell(
        key: ValueKey<String>('$prefix:nav:${s.id}'),
        onTap: tap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: minCell, minHeight: 48),
          child: cellBox,
        ),
      ),
    );
  }
}

/// Меню «Ещё»: расставить вещи (только комната, за флагом), музыка,
/// «Взрослым» (DEN-27: за флагом `adult.section`), настройки. Ключи
/// `<prefix>:menu`, `<prefix>:arrange|music|adult|settings`.
class DockMoreMenu extends StatelessWidget {
  const DockMoreMenu({
    super.key,
    required this.prefix,
    required this.child,
    required this.onGo,
    this.onArrange,
  });

  final String prefix;
  final Widget child;

  /// Переход на «Взрослым» или в настройки.
  final void Function(String route) onGo;

  /// «Расставить вещи» — только в комнате; null — пункта нет.
  final VoidCallback? onArrange;

  static const TextStyle _text = TextStyle(fontSize: 18);

  @override
  Widget build(BuildContext context) {
    final WorldState s = context.watch<WorldState>();
    // Читается здесь, а не в itemBuilder: тот строится и в закрывающемся
    // меню, где искать предков уже нельзя.
    final ({bool on, Future<void> Function() toggle})? music =
        musicSwitch(context);
    final bool adult = adultSectionOn(s.world);
    final bool arrange = onArrange != null && s.world.room.enabled;
    Widget row(Widget icon, String text) => Row(
          children: <Widget>[
            icon,
            const SizedBox(width: Gap.sm),
            Flexible(child: Text(text, style: _text)),
          ],
        );
    return PopupMenuButton<String>(
      key: ValueKey<String>('$prefix:menu'),
      tooltip: adult ? 'Ещё: взрослым, настройки' : 'Ещё: настройки',
      color: WorldColors.panel,
      onSelected: (String v) {
        if (v == 'music') {
          music?.toggle();
          return;
        }
        if (v == 'arrange') {
          onArrange?.call();
          return;
        }
        onGo(v == 'adult' ? WorldRoutes.adult : WorldRoutes.settings);
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (arrange)
          PopupMenuItem<String>(
            key: ValueKey<String>('$prefix:arrange'),
            value: 'arrange',
            height: TapSize.min,
            child: row(
              const Icon(Icons.grid_on_rounded,
                  size: 24, color: WorldColors.text),
              'Расставить вещи',
            ),
          ),
        // Выключить мелодию в одно касание (финал 15.10); выбор
        // сохраняется в настройках.
        if (music case (on: final bool on, toggle: _))
          PopupMenuItem<String>(
            key: ValueKey<String>('$prefix:music'),
            value: 'music',
            height: TapSize.min,
            child: row(
              Icon(
                on ? Icons.music_off_rounded : Icons.music_note_rounded,
                size: 24,
                color: WorldColors.text,
              ),
              on ? 'Выключить музыку' : 'Включить музыку',
            ),
          ),
        if (adult)
          PopupMenuItem<String>(
            key: ValueKey<String>('$prefix:adult'),
            value: 'adult',
            height: TapSize.min,
            child: row(
              const Pictogram(Pic.lock, size: 24, color: WorldColors.text),
              'Взрослым',
            ),
          ),
        PopupMenuItem<String>(
          key: ValueKey<String>('$prefix:settings'),
          value: 'settings',
          height: TapSize.min,
          child: row(
            const Pictogram(Pic.sliders, size: 24, color: WorldColors.text),
            'Настройки',
          ),
        ),
        // «Сборка» — во «Взрослым» (правило 8, C10), не на экране ребёнка.
      ],
      child: child,
    );
  }
}

/// Лист «Неделя»: план недели или копилка. Ключи `<prefix>:week:plan`,
/// `<prefix>:week:piggy`. Возвращает `plan`, `piggy` или null.
Future<String?> pickWeekPart(BuildContext context, {required String prefix}) =>
    showModalBottomSheet<String>(
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
                key: ValueKey<String>('$prefix:week:plan'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(TapSize.min),
                ),
                onPressed: () => Navigator.of(c).pop('plan'),
                icon: const Pictogram(
                  Pic.envelope,
                  size: 24,
                  color: WorldColors.text,
                ),
                label: const Text('План недели'),
              ),
              const SizedBox(height: Gap.sm),
              OutlinedButton.icon(
                key: ValueKey<String>('$prefix:week:piggy'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(TapSize.min),
                ),
                onPressed: () => Navigator.of(c).pop('piggy'),
                icon: const Pictogram(
                  Pic.jar,
                  size: 24,
                  color: WorldColors.text,
                ),
                label: const Text('Копилка'),
              ),
            ],
          ),
        ),
      ),
    );

/// План недели: в начале недели — сначала её начать; план уже есть —
/// сказать, какой; иначе лист плана. [say] — куда писать ответ мира.
Future<void> openWeekPlan(
  BuildContext context,
  WorldState s, {
  required void Function(String text) say,
}) async {
  void sayResult(WorldResult r) =>
      say(r.nextStep == null ? r.reason : '${r.reason} ${r.nextStep}');
  if (s.phase == WeekPhase.weekStart) {
    final WorldResult r = s.act((World w) => w.startWeek());
    if (!r.ok) return sayResult(r);
  }
  if (s.phase != WeekPhase.planning) {
    final ResourceSnapshot snap = s.snapshot;
    return say(
      'План на эту неделю уже есть: нужно ${snap.need}, '
      'хочу ${snap.want}, в копилке ${snap.goal}.',
    );
  }
  final WorldResult? r = await showPlanSheet(context, s);
  if (r != null && context.mounted) sayResult(r);
}

/// Переход в раздел с экрана не-комнаты: назад до комнаты (или до [route],
/// если он уже в стеке), затем [route]. Стек не растёт: город → магазин →
/// «Город» → … и системная «назад» после любого раздела ведёт в комнату.
/// [route] null — сама комната.
void goToRoute(NavigatorState nav, String? route) {
  String? landed;
  nav.popUntil((Route<dynamic> r) {
    final String? name = r.settings.name;
    if ((route != null && name == route) ||
        name == WorldRoutes.room ||
        r.isFirst) {
      landed = name;
      return true;
    }
    return false;
  });
  if (route == null) {
    if (landed != WorldRoutes.room) nav.pushReplacementNamed(WorldRoutes.room);
    return;
  }
  if (landed != route) nav.pushNamed(route);
}

/// Нижнее меню экрана не-комнаты, с переходами по разделам.
///
/// [onBlocked] — вместо любого перехода (смена с обязательным уроком: сначала
/// ответ, потом меню).
class PageDock extends StatelessWidget {
  const PageDock({
    super.key,
    required this.current,
    this.onBlocked,
    this.axis = Axis.horizontal,
  });

  final DockSection current;
  final VoidCallback? onBlocked;
  final Axis axis;

  static const String prefix = 'dock';

  Future<void> _plan(BuildContext context) async {
    final WorldState ws = context.read<WorldState>();
    final String? to = await pickWeekPart(context, prefix: prefix);
    if (!context.mounted || to == null) return;
    if (to == 'piggy') {
      goToRoute(Navigator.of(context), WorldRoutes.piggy);
      return;
    }
    await openWeekPlan(context, ws, say: (String text) {
      if (!context.mounted) return;
      final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
      m.hideCurrentSnackBar();
      m.showSnackBar(SnackBar(content: PicText(text)));
    });
  }

  VoidCallback? _tap(BuildContext context, DockSection s) {
    if (onBlocked case final VoidCallback blocked) return blocked;
    return switch (s) {
      DockSection.home => () => goToRoute(Navigator.of(context), null),
      DockSection.city => () =>
          goToRoute(Navigator.of(context), WorldRoutes.city),
      DockSection.progress => () =>
          goToRoute(Navigator.of(context), WorldRoutes.history),
      DockSection.plan => () => _plan(context),
      DockSection.more => null,
    };
  }

  @override
  Widget build(BuildContext context) => WorldDock(
        current: current,
        prefix: prefix,
        axis: axis,
        onTap: (DockSection s) => _tap(context, s),
        more: (Widget child) => onBlocked == null
            ? DockMoreMenu(
                prefix: prefix,
                onGo: (String route) => goToRoute(Navigator.of(context), route),
                child: child,
              )
            : Semantics(
                button: true,
                label: DockSection.more.said,
                excludeSemantics: true,
                onTap: onBlocked,
                child: InkWell(
                  key: const ValueKey<String>('$prefix:menu'),
                  onTap: onBlocked,
                  child: child,
                ),
              ),
      );
}

/// Экран ребёнка с нижним меню: в портрете — полоса снизу, в альбомной —
/// столбец слева. Экран под меню не получает нижнего (левого) системного
/// поля — его забирает меню.
class WithDock extends StatelessWidget {
  const WithDock({
    super.key,
    required this.current,
    required this.child,
    this.onBlocked,
    this.inPortrait = true,
  });

  final DockSection current;
  final Widget child;
  final VoidCallback? onBlocked;

  /// Полоса снизу в портрете. false — экран-поток, который кончается своей
  /// кнопкой (итоги недели → «Новая неделя»): навигация там не нужна, а 60 dp
  /// на 360×640 при шрифте 1,3 уводили вывод недели под кнопку
  /// (review_fits_test). Столбец в альбомной остаётся.
  final bool inPortrait;

  /// Сколько ширины экрану оставляет столбец меню в альбомной. Раскладки
  /// альбомной (сетка магазина, две колонки копилки, список города)
  /// рассчитаны на 640 dp: где столбец их сузил бы, меню на экране нет —
  /// остаются «назад» в шапке и меню комнаты (телефон 640×360). Шире
  /// (телефоны ~780 dp, планшеты) — столбец слева.
  static const double minContentWidth = 640;

  /// Есть ли меню на экране размера [size].
  static bool shown(Size size) =>
      size.width <= size.height ||
      size.width - WorldDock.railWidth >= minContentWidth;

  @override
  Widget build(BuildContext context) {
    final bool land = WorldLayout.isLandscape(context);
    if (!shown(MediaQuery.sizeOf(context))) return child;
    if (!land && !inPortrait) return child;
    final Widget dock = Material(
      key: const ValueKey<String>('dock'),
      color: WorldColors.dock,
      child: SafeArea(
        top: land,
        right: false,
        left: land,
        child: land
            ? SizedBox(
                width: WorldDock.railWidth,
                child: PageDock(
                  current: current,
                  onBlocked: onBlocked,
                  axis: Axis.vertical,
                ),
              )
            : SizedBox(
                height: WorldDock.height,
                child: PageDock(current: current, onBlocked: onBlocked),
              ),
      ),
    );
    if (land) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          dock,
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              child: child,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: child,
          ),
        ),
        dock,
      ],
    );
  }
}
