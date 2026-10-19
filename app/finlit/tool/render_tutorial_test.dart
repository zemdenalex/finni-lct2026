// Рендер страницы вариантов обучалки (D6, созвон 15.10):
// docs/final/tutorial/. Настоящие экраны комнаты и магазина, поверх —
// варианты подсказок (только здесь, в инструменте; в приложении их нет).
//   flutter test tool/render_tutorial_test.dart  → build/tutorial/*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/art/asset_registry.dart';
import 'package:finlit/core/art/sprite_anim.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
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

enum _Look { spotlight, dialog, hints }

/// Шаг обучалки: экран, цель подсказки (ключ или первый подходящий), текст.
class _Beat {
  const _Beat(this.id, this.shop, this.target, this.text, this.short);
  final String id;
  final bool shop;
  final bool Function(String key) target;
  final String Function(World w) text;

  /// Короткая подсказка «на месте» (вариант T3).
  final String Function(World w) short;
}

final List<_Beat> _beats = <_Beat>[
  _Beat(
    '1-hello',
    false,
    (String k) => k == 'room:finni',
    (_) => 'Привет! Я Финни. Это мой дом — теперь я тут живу. Поможешь?',
    (_) => 'Это я, Финни. Нажми на меня',
  ),
  _Beat(
    '2-rent',
    false,
    (String k) => k == 'room:door',
    (World w) => 'Тук-тук! Это хозяйка квартиры. За жильё и еду '
        'на неделе — ${w.snapshot.weeklyBill} монет. Отложим их первыми.',
    (World w) => 'Стучат: счета недели — ${w.snapshot.weeklyBill}',
  ),
  _Beat(
    '3-shop',
    true,
    (String k) => k.startsWith('card:'),
    // Сколько обычно уходит на еду — из мира: домашнее блюдо × приёмы
    // недели (та же сумма входит в счета, что назвала хозяйка).
    (World w) => 'Еда нужна каждый день. Обычно на неделю уходит около '
        '${_food(w)} монет — выбери, чем кормить.',
    (World w) => 'Обычно на еду уходит ~${_food(w)} в неделю',
  ),
  _Beat(
    '4-done',
    false,
    (String k) => k == 'room:help',
    (_) => 'Дальше — твой ход! Что непонятно, жми «?» наверху.',
    (_) => 'Подсказки — здесь',
  ),
];

int _food(World w) {
  final ResourceSnapshot s = w.snapshot;
  final int price =
      s.foodId == null ? 0 : (w.catalogItem(s.foodId!)?.price ?? 0);
  return price * s.mealsPerWeek;
}

final ValueNotifier<Rect?> _target = ValueNotifier<Rect?>(null);

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  final String only = Platform.environment['ONLY'] ?? '';
  for (final _Look look in _Look.values) {
    for (final _Beat beat in _beats) {
      final String name = '${look.name}-${beat.id}';
      if (only.isNotEmpty && !name.contains(only)) continue;
      testWidgets(name, (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 640) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        _target.value = null;
        final GlobalKey key = GlobalKey();
        await tester.runAsync(() async {
          final AssetRegistry reg = await AssetRegistry.load();
          final World world = _town();
          final WorldState ws = WorldState(world);
          await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: Provider<OnboardingScript>.value(
              value: contentScript,
              child: ChangeNotifierProvider<WorldState>.value(
                value: ws,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: buildAppTheme(),
                  routes: worldRoutes,
                  builder: (BuildContext c, Widget? child) => Stack(
                    children: <Widget>[
                      child!,
                      ValueListenableBuilder<Rect?>(
                        valueListenable: _target,
                        builder: (BuildContext c, Rect? r, Widget? _) =>
                            r == null
                                ? const SizedBox.shrink()
                                : WorldTheme(
                                    child: _Overlay(
                                      look: look,
                                      step: _beats.indexOf(beat) + 1,
                                      target: r,
                                      text: beat.text(world),
                                      short: beat.short(world),
                                      finni: reg.finni(ws.profile.species),
                                      idle: ws.profile.idleTag,
                                    ),
                                  ),
                      ),
                    ],
                  ),
                  home: WorldTheme(
                    child: beat.shop
                        ? const WorldShopScreen()
                        : const RoomScreen(),
                  ),
                ),
              ),
            ),
          ));
          for (int i = 0; i < 10; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await tester.pump(const Duration(milliseconds: 50));
          }
          final Finder f = find.byWidgetPredicate((Widget w) {
            final Key? k = w.key;
            return k is ValueKey<String> && beat.target(k.value);
          });
          _target.value = tester.getRect(f.first);
          for (int i = 0; i < 4; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await tester.pump(const Duration(milliseconds: 50));
          }
          final RenderRepaintBoundary b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final ui.Image img = await b.toImage(pixelRatio: 2);
          final ByteData? png =
              await img.toByteData(format: ui.ImageByteFormat.png);
          final File out = File('build/tutorial/$name.png');
          await out.create(recursive: true);
          await out.writeAsBytes(png!.buffer.asUint8List());
        });
      });
    }
  }
}

const TextStyle _say = TextStyle(
    fontSize: 16, height: 1.3, color: WorldColors.text, fontFamily: 'Onest');

class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.look,
    required this.step,
    required this.target,
    required this.text,
    required this.short,
    required this.finni,
    required this.idle,
  });

  final _Look look;
  final int step;
  final Rect target;
  final String text;
  final String short;
  final SpriteRef? finni;
  final String idle;

  Widget _face(double scale) => finni == null
      ? const SizedBox(width: 44, height: 58)
      : SpriteAnim(sprite: finni!, tag: idle, scale: scale);

  Widget _buttons({bool last = false}) => Row(
        children: <Widget>[
          TextButton(
            onPressed: () {},
            child: const Text('Пропустить',
                style: TextStyle(color: WorldColors.textSoft)),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () {},
            style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
            child: Text(last ? 'Играть' : 'Дальше'),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final Rect hole = target.inflate(8);
    final bool below = hole.center.dy < size.height / 2;
    switch (look) {
      case _Look.spotlight:
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: CustomPaint(painter: _Dim(hole)),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: below ? hole.bottom + 12 : null,
              bottom: below ? null : size.height - hole.top + 12,
              child: _Card(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _face(0.45),
                        const SizedBox(width: Gap.sm),
                        Expanded(child: Text(text, style: _say)),
                      ],
                    ),
                    _Dots(step),
                    _buttons(last: step == 4),
                  ],
                ),
              ),
            ),
          ],
        );
      case _Look.dialog:
        return Stack(
          children: <Widget>[
            Positioned.fromRect(
              rect: hole,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.chip),
                    border: Border.all(color: WorldColors.gold, width: 3),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: WorldColors.panel,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(Radii.scene)),
                  side: BorderSide(color: WorldColors.line, width: 1.5),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Gap.md, Gap.md, Gap.md, Gap.sm),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _face(0.6),
                            const SizedBox(width: Gap.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text('Финни · $step из 4',
                                      style: AppType.title(15,
                                          color: WorldColors.gold)),
                                  const SizedBox(height: 4),
                                  Text(text, style: _say),
                                ],
                              ),
                            ),
                          ],
                        ),
                        _buttons(last: step == 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      case _Look.hints:
        // В магазине — под строкой названия карточки, не на тексте над ней.
        final bool inCard = hole.height > 120;
        final double w = 210;
        final double left =
            (hole.center.dx - w / 2).clamp(8.0, size.width - w - 8);
        return Stack(
          children: <Widget>[
            Positioned(
              left: left,
              width: w,
              top: inCard
                  ? hole.bottom - 4
                  : below
                      ? hole.bottom + 6
                      : null,
              bottom: inCard || below ? null : size.height - hole.top + 6,
              child: _Card(
                padding: const EdgeInsets.fromLTRB(Gap.sm, 6, 4, 6),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(short, style: _say.copyWith(fontSize: 14)),
                    ),
                    const Icon(Icons.close_rounded,
                        size: 20, color: WorldColors.textSoft),
                  ],
                ),
              ),
            ),
            // Выключить все подсказки — один раз, в углу (не перекрывает HUD).
            if (step == 1)
              Positioned(
                right: 8,
                bottom: 150,
                child: _Card(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Gap.sm, vertical: 6),
                  child: Text('Без подсказок',
                      style: _say.copyWith(
                          fontSize: 14, color: WorldColors.textSoft)),
                ),
              ),
          ],
        );
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Material(
        color: WorldColors.panel,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.chip),
          side: const BorderSide(color: WorldColors.gold, width: 2),
        ),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(Gap.md),
          child: child,
        ),
      );
}

class _Dots extends StatelessWidget {
  const _Dots(this.step);
  final int step;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Gap.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int i = 1; i <= 4; i++)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == step ? WorldColors.gold : WorldColors.line,
                ),
              ),
          ],
        ),
      );
}

class _Dim extends CustomPainter {
  _Dim(this.hole);
  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final Path p = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()
        ..addRRect(
            RRect.fromRectAndRadius(hole, const Radius.circular(Radii.chip))),
    );
    canvas.drawPath(p, Paint()..color = const Color(0xA6000000));
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole, const Radius.circular(Radii.chip)),
      Paint()
        ..color = WorldColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_Dim old) => old.hole != hole;
}
