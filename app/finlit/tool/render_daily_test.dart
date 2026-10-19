// Рендер страницы вариантов «Дела дня» (модель «день по энергии» §5):
// docs/final/daily-activities/. Настоящая комната (HUD — вариант A),
// поверх — варианты списка дел; числа моковые (домен дня — отдельно).
//   flutter test tool/render_daily_test.dart → build/daily/*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/icons.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/day_energy_looks.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test/support/world_harness.dart' show contentScript, contentWorld;
import 'test_fonts.dart';

World _town() {
  final WorldGame w = contentWorld();
  WorldAutopilot(w).playToStage(WorldStage.town);
  if (w.phase == WeekPhase.review) w.payBills();
  if (w.phase == WeekPhase.weekStart) w.startWeek();
  if (w.phase == WeekPhase.planning) {
    w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0);
  }
  return w;
}

enum _Look { list, glow, slots }

/// Дело дня (моки по §5 модели): название, цена, что даёт, сделано ли.
class _Act {
  const _Act(this.pic, this.title, this.cost, {this.done = false});
  final Pic pic;
  final String title;
  final String cost;
  final bool done;
}

const List<_Act> _today = <_Act>[
  _Act(Pic.bowl, 'Поесть', 'из холодильника', done: true),
  _Act(Pic.heart, 'Погладить', '+1 😊', done: true),
  _Act(Pic.basket, 'Магазин', '1 ⚡ · еда'),
  _Act(Pic.house, 'Отдых дома', '1 ⚡ · +2 😊'),
  _Act(Pic.task, 'Смена', '3 ⚡ · монеты'),
];

final ValueNotifier<Map<String, Rect>?> _rects =
    ValueNotifier<Map<String, Rect>?>(null);

const TextStyle _t = TextStyle(
  fontSize: 15,
  color: WorldColors.text,
  fontFamily: 'Onest',
);
const TextStyle _soft = TextStyle(
  fontSize: 13,
  color: WorldColors.textSoft,
  fontFamily: 'Onest',
);

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  tearDown(() {
    hudLook = HudLook.fedOnFinni;
    dayMock = null;
    progressNew = 0;
  });
  final String only = Platform.environment['ONLY'] ?? '';
  for (final _Look look in _Look.values) {
    for (final bool evening in <bool>[false, true]) {
      final String name = '${look.name}-${evening ? 'evening' : 'day'}';
      if (only.isNotEmpty && !name.contains(only)) continue;
      testWidgets(name, (WidgetTester tester) async {
        hudLook = HudLook.fedOnFinni;
        dayMock = DayMock(
          fed: evening ? 0.45 : 0.7,
          time: evening ? DayTime.evening : DayTime.day,
        );
        _rects.value = null;
        tester.view.physicalSize = const Size(360, 640) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final GlobalKey key = GlobalKey();
        await tester.runAsync(() async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: Provider<OnboardingScript>.value(
                value: contentScript,
                child: ChangeNotifierProvider<WorldState>.value(
                  value: WorldState(_town()),
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: buildAppTheme(),
                    routes: worldRoutes,
                    builder: (BuildContext c, Widget? child) => Stack(
                      children: <Widget>[
                        child!,
                        ValueListenableBuilder<Map<String, Rect>?>(
                          valueListenable: _rects,
                          builder: (BuildContext c, Map<String, Rect>? r, _) =>
                              r == null
                              ? const SizedBox.shrink()
                              : WorldTheme(
                                  child: _Overlay(
                                    look: look,
                                    evening: evening,
                                    r: r,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    home: const WorldTheme(child: RoomScreen()),
                  ),
                ),
              ),
            ),
          );
          for (int i = 0; i < 10; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await tester.pump(const Duration(milliseconds: 50));
          }
          Rect at(String k) =>
              tester.getRect(find.byKey(ValueKey<String>(k)).first);
          _rects.value = <String, Rect>{
            for (final String k in <String>[
              'room:now',
              'room:fridge',
              'room:bed',
              'room:finni',
              'hud:strip',
            ])
              k: at(k),
          };
          for (int i = 0; i < 4; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await tester.pump(const Duration(milliseconds: 50));
          }
          final RenderRepaintBoundary b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final ui.Image img = await b.toImage(pixelRatio: 2);
          final ByteData? png = await img.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final File out = File('build/daily/$name.png');
          await out.create(recursive: true);
          await out.writeAsBytes(png!.buffer.asUint8List());
        });
      });
    }
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({required this.look, required this.evening, required this.r});
  final _Look look;
  final bool evening;
  final Map<String, Rect> r;

  /// «Спать» на месте «Сейчас» вечером — главное действие вечера.
  Widget _sleep() {
    final Rect now = r['room:now']!;
    return Positioned.fromRect(
      rect: now,
      child: FilledButton.icon(
        onPressed: () {},
        style: FilledButton.styleFrom(minimumSize: Size(now.width, now.height)),
        icon: const Pictogram(Pic.moon, size: 22, color: WorldColors.onGold),
        label: const Text('Вечер: спать'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Rect now = r['room:now']!;
    final Rect hud = r['hud:strip']!;
    final List<Widget> layer = <Widget>[];
    switch (look) {
      case _Look.list:
        layer.add(
          Positioned(
            left: 8,
            right: 8,
            bottom: MediaQuery.sizeOf(context).height - now.top + 6,
            child: _Panel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        evening ? 'Вечер' : 'Сегодня',
                        style: AppType.title(15, color: WorldColors.gold),
                      ),
                      const Spacer(),
                      const Pictogram(
                        Pic.bolt,
                        size: 16,
                        color: WorldColors.energy,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        evening
                            ? 'сил нет — день кончился'
                            : 'хватит на 3 дела',
                        style: _soft,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final _Act a in _today)
                        _Chip(a, off: evening && !a.done),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      case _Look.glow:
        // Полоса «солнце»: от утра до вечера = от полной ⚡ до нуля.
        layer.add(
          Positioned(
            left: hud.left + 6,
            right: 360 - hud.right + 6,
            top: hud.bottom + 4,
            child: _SunTrack(evening ? 0.92 : 0.35),
          ),
        );
        if (!evening) {
          layer
            ..add(_Marker(r['room:fridge']!, Pic.basket, 'Магазин · 1 ⚡'))
            ..add(_Marker(r['room:bed']!, Pic.house, 'Отдых · 1 ⚡'))
            ..add(_Marker(r['room:finni']!, Pic.heart, 'Погладь', below: true));
        } else {
          layer.add(_Marker(r['room:bed']!, Pic.moon, 'Спать'));
        }
      case _Look.slots:
        final int used = evening ? 4 : 2;
        layer.add(
          Positioned(
            left: 8,
            right: 8,
            bottom: MediaQuery.sizeOf(context).height - now.top + 6,
            child: _Panel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    evening
                        ? 'Вечер: все дела дня сделаны'
                        : 'Ещё 2 дела до вечера',
                    style: _t.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      for (int i = 0; i < 4; i++) ...<Widget>[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: _Slot(
                            i < used
                                ? <(Pic, String)>[
                                    (Pic.bowl, 'Поел'),
                                    (Pic.task, 'Смена'),
                                    (Pic.basket, 'Магазин'),
                                    (Pic.house, 'Отдых'),
                                  ][i]
                                : null,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
    }
    if (evening) layer.add(_sleep());
    return IgnorePointer(child: Stack(children: layer));
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: WorldColors.panel.withValues(alpha: 0.95),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WorldRadii.tile),
      side: const BorderSide(color: WorldColors.line, width: 1.5),
    ),
    child: Padding(padding: const EdgeInsets.all(Gap.sm), child: child),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.a, {this.off = false});
  final _Act a;
  final bool off;

  @override
  Widget build(BuildContext context) {
    final Color c = a.done
        ? WorldColors.needs
        : off
        ? WorldColors.textMute
        : WorldColors.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: WorldColors.raised,
        borderRadius: BorderRadius.circular(WorldRadii.tag),
        border: Border.all(
          color: a.done ? WorldColors.needs : WorldColors.line,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          a.done
              ? const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: WorldColors.needs,
                )
              : Pictogram(a.pic, size: 16, color: c),
          const SizedBox(width: 4),
          Text(a.title, style: _t.copyWith(fontSize: 14, color: c)),
          // Цена — значком ⚡ и числом: строка «1 сил · еда» рвала ряд.
          if (!a.done && a.cost.contains('⚡')) ...<Widget>[
            const SizedBox(width: 4),
            Pictogram(
              Pic.bolt,
              size: 13,
              color: off ? WorldColors.textMute : WorldColors.energy,
            ),
            Text(a.cost.split(' ').first, style: _soft.copyWith(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker(this.at, this.pic, this.text, {this.below = false});
  final Rect at;
  final Pic pic;
  final String text;
  final bool below;

  @override
  Widget build(BuildContext context) => Positioned(
    // По центру предмета, не за край кадра (~75 dp — половина ярлыка).
    left: at.center.dx.clamp(80.0, 360 - 80.0),
    top: below ? at.bottom - 30 : at.top - 8,
    child: FractionalTranslation(
      translation: const Offset(-0.5, 0),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: WorldColors.panel,
            borderRadius: BorderRadius.circular(WorldRadii.tag),
            border: Border.all(color: WorldColors.gold, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Pictogram(pic, size: 16, color: WorldColors.gold),
              const SizedBox(width: 4),
              Text(text.split(' · ').first, style: _t.copyWith(fontSize: 13)),
              if (text.contains('⚡')) ...<Widget>[
                const SizedBox(width: 4),
                const Pictogram(Pic.bolt, size: 13, color: WorldColors.energy),
                Text(
                  text.split(' · ').last.split(' ').first,
                  style: _soft.copyWith(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _SunTrack extends StatelessWidget {
  const _SunTrack(this.t);

  /// 0 — утро, 1 — вечер.
  final double t;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 22,
    child: LayoutBuilder(
      builder: (BuildContext c, BoxConstraints box) => Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: 0,
            right: 0,
            top: 9,
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    WorldColors.energy,
                    WorldColors.gold,
                    Color(0xFFFF7A2E),
                  ],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            left: (box.maxWidth - 22) * t,
            top: 0,
            child: Icon(
              t > 0.8 ? Icons.wb_twilight_rounded : Icons.wb_sunny_rounded,
              size: 22,
              color: WorldColors.gold,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Slot extends StatelessWidget {
  const _Slot(this.done);
  final (Pic, String)? done;

  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    decoration: BoxDecoration(
      color: done == null ? Colors.transparent : WorldColors.raised,
      borderRadius: BorderRadius.circular(WorldRadii.tag),
      border: Border.all(
        color: done == null ? WorldColors.line : WorldColors.gold,
        width: 1.5,
      ),
    ),
    child: done == null
        ? const Center(
            child: Pictogram(Pic.bolt, size: 18, color: WorldColors.line),
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Pictogram(done!.$1, size: 18, color: WorldColors.gold),
              Text(done!.$2, style: _soft.copyWith(fontSize: 12)),
            ],
          ),
  );
}
