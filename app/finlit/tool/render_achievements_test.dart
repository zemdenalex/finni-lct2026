// Рендер страницы вариантов «Ачивки и прогресс» (D3, созвон 15.10):
// docs/final/achievements/. 🟡 Награды — моковые: домен ачивок
// делается отдельно; здесь только вид. Комната и «как сдано» — настоящие.
//   flutter test tool/render_achievements_test.dart → build/achievements/*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/icons.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/core/widgets.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/history/history_screen.dart';
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

enum _State { got, going, locked }

/// Моковая награда: тема, значок, название, условие, прогресс.
class _Ach {
  const _Ach(this.theme, this.pic, this.title, this.how, this.state,
      {this.now = 0, this.of = 0, this.isNew = false});
  final String theme;
  final Pic pic;
  final String title;
  final String how;
  final _State state;
  final int now;
  final int of;
  final bool isNew;
}

const List<_Ach> _all = <_Ach>[
  _Ach('Работа', Pic.task, 'Первая смена', 'Отработай одну смену', _State.got,
      isNew: true),
  _Ach(
      'Работа', Pic.star, 'Мастер смены', 'Пять смен на «хорошо»', _State.going,
      now: 3, of: 5),
  _Ach('Деньги', Pic.flag, 'Первая цель', 'Накопи на первую цель', _State.got),
  _Ach('Деньги', Pic.trophy, 'Три цели', 'Купи три цели из копилки',
      _State.going,
      now: 1, of: 3),
  _Ach('Деньги', Pic.check, 'Неделя без нехватки',
      'Оплати счета без помощи семьи', _State.got,
      isNew: true),
  _Ach('Деньги', Pic.calc, 'Без долга', 'Три недели подряд без долга',
      _State.going,
      now: 2, of: 3),
  _Ach('Деньги', Pic.jar, 'Копилка 1000', 'Накопи 1000 в копилке', _State.going,
      now: 640, of: 1000),
  _Ach('Знания', Pic.school, 'Правильный урок', 'Ответь верно на урок',
      _State.got),
  _Ach('Знания', Pic.dictionary, 'Знаток', 'Пять уроков верно', _State.going,
      now: 3, of: 5),
  _Ach('Финни', Pic.paw, 'Свой питомец', 'Заведи питомца — цель «питомец»',
      _State.locked),
  _Ach('Финни', Pic.house, 'Переезд', 'Переехать в город', _State.got),
  _Ach('Финни', Pic.city, 'Москва', 'Дорасти до квартиры в Москве',
      _State.locked),
];

int get _got => _all.where((_Ach a) => a.state == _State.got).length;

const TextStyle _t = TextStyle(fontSize: 16, color: WorldColors.text);
const TextStyle _soft = TextStyle(fontSize: 14, color: WorldColors.textSoft);

Color _tone(_State s) => switch (s) {
      _State.got => WorldColors.gold,
      _State.going => WorldColors.text,
      _State.locked => WorldColors.textMute,
    };

/// Шапка экрана «Прогресс» с вкладками «Награды · История».
PreferredSizeWidget _bar(BuildContext c) => AppBar(
      title: const Text('Прогресс'),
      leading: const Icon(Icons.arrow_back_rounded),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: Row(
          children: <Widget>[
            for (final (String t, bool on) in <(String, bool)>[
              ('Награды', true),
              ('История', false),
            ])
              Expanded(
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: on ? WorldColors.gold : WorldColors.line,
                          width: on ? 3 : 1),
                    ),
                  ),
                  child: Text(t,
                      style: _t.copyWith(
                          fontWeight: FontWeight.w700,
                          color: on ? WorldColors.gold : WorldColors.textSoft)),
                ),
              ),
          ],
        ),
      ),
    );

Widget _summary() => Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.sm),
      child: Row(
        children: <Widget>[
          const Pictogram(Pic.trophy, size: 28, color: WorldColors.gold),
          const SizedBox(width: Gap.sm),
          Text('$_got из ${_all.length}',
              style: AppType.number(22, color: WorldColors.text)),
          const SizedBox(width: Gap.sm),
          const Expanded(
            child: Text('наград получено', style: _soft),
          ),
        ],
      ),
    );

/// A — список с полосками.
class _ListLook extends StatelessWidget {
  const _ListLook();

  @override
  Widget build(BuildContext context) {
    final List<_Ach> order = <_Ach>[
      ..._all.where((_Ach a) => a.isNew),
      ..._all.where((_Ach a) => a.state == _State.going),
      ..._all.where((_Ach a) => a.state == _State.got && !a.isNew),
      ..._all.where((_Ach a) => a.state == _State.locked),
    ];
    return Scaffold(
      appBar: _bar(context),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Gap.lg),
        children: <Widget>[
          _summary(),
          for (final _Ach a in order)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
              child: Panel(
                padding: const EdgeInsets.all(Gap.sm),
                edge: a.isNew ? WorldColors.gold : WorldColors.line,
                child: Row(
                  children: <Widget>[
                    _Badge(a, size: 44),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(children: <Widget>[
                            Flexible(
                              child: Text(a.title,
                                  style: _t.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: a.state == _State.locked
                                          ? WorldColors.textMute
                                          : WorldColors.text)),
                            ),
                            if (a.isNew) ...<Widget>[
                              const SizedBox(width: Gap.xs),
                              const _NewTag(),
                            ],
                          ]),
                          Text(a.how, style: _soft),
                          if (a.state == _State.going) ...<Widget>[
                            const SizedBox(height: 4),
                            Row(children: <Widget>[
                              Expanded(
                                  child: ValueBar(
                                      a.now / a.of, WorldColors.gold,
                                      height: 6)),
                              const SizedBox(width: Gap.sm),
                              // Счётчики одной колонкой: «3 / 5» и «640 / 1000»
                              // кончаются у одного края.
                              SizedBox(
                                  width: 84,
                                  child: Text('${a.now} / ${a.of}',
                                      textAlign: TextAlign.right,
                                      style: _soft)),
                            ]),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// B — значки по темам.
class _MapLook extends StatelessWidget {
  const _MapLook();

  @override
  Widget build(BuildContext context) {
    final List<String> themes = <String>['Работа', 'Деньги', 'Знания', 'Финни'];
    return Scaffold(
      appBar: _bar(context),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Gap.lg),
        children: <Widget>[
          _summary(),
          for (final String t in themes) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, 4),
              child: Text(t,
                  style: AppType.title(16, color: WorldColors.textSoft)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: <Widget>[
                  for (final _Ach a in _all.where((_Ach a) => a.theme == t))
                    SizedBox(
                      width: 78,
                      child: Column(
                        children: <Widget>[
                          Stack(
                            clipBehavior: Clip.none,
                            children: <Widget>[
                              _Badge(a, size: 60, ring: true),
                              if (a.isNew)
                                const Positioned(
                                    right: -6, top: -4, child: _NewTag()),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(a.title,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              style: _soft.copyWith(
                                  fontSize: 12.5,
                                  height: 1.15,
                                  color: _tone(a.state) == WorldColors.textMute
                                      ? WorldColors.textMute
                                      : WorldColors.text)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 0),
            child: Text(
                'Нажми на значок — условие и прогресс. Серые — пока закрыты.',
                style: _soft),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.a, {required this.size, this.ring = false});
  final _Ach a;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final bool got = a.state == _State.got;
    final bool locked = a.state == _State.locked;
    final Widget core = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: got ? WorldColors.gold : WorldColors.raised,
        border: Border.all(
            color: locked ? WorldColors.line : WorldColors.gold, width: 2),
      ),
      alignment: Alignment.center,
      child: locked
          ? Icon(Icons.lock_rounded,
              size: size * 0.42, color: WorldColors.textMute)
          : Pictogram(a.pic,
              size: size * 0.5,
              color: got ? WorldColors.onGold : WorldColors.gold),
    );
    if (!ring || a.state != _State.going) return core;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          core,
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: a.now / a.of,
              strokeWidth: 4,
              color: WorldColors.gold,
              backgroundColor: const Color(0x33FFFFFF),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewTag extends StatelessWidget {
  const _NewTag();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: WorldColors.gold,
          borderRadius: BorderRadius.circular(WorldRadii.tag),
        ),
        child:
            Text('новое', style: AppType.title(11, color: WorldColors.onGold)),
      );
}

/// C — полка наград на стене комнаты (поверх настоящей комнаты).
class _Shelf extends StatelessWidget {
  const _Shelf();

  @override
  Widget build(BuildContext context) {
    final List<_Ach> got =
        _all.where((_Ach a) => a.state == _State.got).toList();
    return Positioned(
      left: 6,
      top: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final _Ach a in got.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _Badge(a, size: 32),
                ),
            ],
          ),
          Container(
            width: 116,
            height: 10,
            decoration: BoxDecoration(
              color: const Color(0xFF6B4226),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: const Color(0xFF5E3B20)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Баннер получения: сверху, под HUD, 1,5 с; кнопки внизу не закрывает.
class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) => Positioned(
        left: 12,
        right: 12,
        top: 92,
        child: Material(
          color: WorldColors.panel,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.chip),
            side: const BorderSide(color: WorldColors.gold, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Gap.sm),
            child: Row(
              children: <Widget>[
                _Badge(_all.first, size: 40),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Новая награда!',
                          style: AppType.title(14, color: WorldColors.gold)),
                      Text('Первая смена — ты отработал первую смену',
                          style: _t),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// (файл, экран, что поверх комнаты).
final List<(String, Widget, Widget?)> _cases = <(String, Widget, Widget?)>[
  ('0-asis', const HistoryScreen(), null),
  ('A-list', const _ListLook(), null),
  ('B-map', const _MapLook(), null),
  ('C-shelf', const RoomScreen(), const _Shelf()),
  ('banner', const RoomScreen(), const _Banner()),
];

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);
  tearDown(() => progressNew = 0);
  final String only = Platform.environment['ONLY'] ?? '';
  for (final (String name, Widget screen, Widget? over) in _cases) {
    if (only.isNotEmpty && !name.contains(only)) continue;
    testWidgets(name, (WidgetTester tester) async {
      progressNew = 2;
      tester.view.physicalSize = const Size(360, 640) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final GlobalKey key = GlobalKey();
      await tester.runAsync(() async {
        await tester.pumpWidget(RepaintBoundary(
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
                    if (over != null) WorldTheme(child: over),
                  ],
                ),
                home: WorldTheme(child: screen),
              ),
            ),
          ),
        ));
        for (int i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          await tester.pump(const Duration(milliseconds: 50));
        }
        final RenderRepaintBoundary b =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final ui.Image img = await b.toImage(pixelRatio: 2);
        final ByteData? png =
            await img.toByteData(format: ui.ImageByteFormat.png);
        final File out = File('build/achievements/$name.png');
        await out.create(recursive: true);
        await out.writeAsBytes(png!.buffer.asUint8List());
      });
    });
  }
}
