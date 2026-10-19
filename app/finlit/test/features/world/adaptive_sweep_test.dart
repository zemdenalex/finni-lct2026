import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/achievements/achievements_screen.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/world_routes.dart' show JobPlayArgs;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Обход адаптива (финал, «Camera and adaptive for interface»): все экраны,
/// которые ребёнок открывает из меню комнаты и из города, на 360×640,
/// 640×360, 768×1024 и 1440×900 при шрифте 1,0 и 1,3, с настоящим шрифтом.
///
/// Защищает: нет переполнения (RenderFlex и т. п.), подпись кнопки не
/// обрезана («Пропустит» вместо «Пропустить»), цели касания ≥ 48 dp,
/// кнопка вне прокрутки не свисает за край экрана. Уронит: любая из этих
/// поломок на любом экране и размере.
///
/// Экран — строка в [sweepScreens]; тап-состояния (лист «План», меню «Ещё»,
/// холодильник) — строка с [SweepOpen]. Кадры — `tool/render_adaptive_sweep_test.dart`.

typedef SweepOpen = Future<void> Function(WidgetTester tester);

World _day() {
  final World w = contentDayWorld()..startWeek();
  ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
  return w;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Экраны обхода: из общей карты — те, что открывает ребёнок (без «Взрослым»
/// и «Проверки»), плюс мини-игры всех работ, награды, комната в режиме дней
/// и тап-состояния комнаты.
Map<String, ((Widget, World Function()), SweepOpen?)> sweepScreens() {
  final WorldKind kind = worldKinds.last;
  final Map<String, (Widget, World Function())> base = worldScreens(kind);
  World living() => livingWorld(kind);
  World allJobs() {
    final World w = livingWorld(kind);
    ok(w.demoUnlockAllJobs());
    return w;
  }

  return <String, ((Widget, World Function()), SweepOpen?)>{
    for (final MapEntry<String, (Widget, World Function())> e in base.entries)
      if (!e.key.startsWith('S14') && !e.key.startsWith('S16'))
        e.key: (e.value, null),
    // Все работы открыты (демо-действие): курьер и программист иначе
    // закрыты — экран показал бы «Такой работы нет», а не игру.
    for (final (String job, String? variant) in <(String, String?)>[
      ('accountant', null),
      ('consultant', null),
      ('cashier', null),
      ('gardener', null),
      ('courier', 'near'),
      ('programmer', 'easy'),
      ('dog_walker', null),
    ]) ...<String, ((Widget, World Function()), SweepOpen?)>{
      'S7 смена $job': (
        (JobPlayScreen(args: JobPlayArgs(job, variant: variant)), allJobs),
        null
      ),
      // Сама мини-игра: «Начать» на карточке смены.
      'S7 мини-игра $job': (
        (JobPlayScreen(args: JobPlayArgs(job, variant: variant)), allJobs),
        (WidgetTester t) => _tapKey(t, 'job:start'),
      ),
    },
    'S12 награды': ((const AchievementsScreen(), living), null),
    'S1 комната · дни': ((const RoomScreen(), _day), null),
    'S1 комната · лист «План»': (
      (const RoomScreen(), _day),
      (WidgetTester t) => _tapKey(t, 'room:nav:week'),
    ),
    'S1 комната · меню «Ещё»': (
      (const RoomScreen(), _day),
      (WidgetTester t) => _tapKey(t, 'room:nav:more'),
    ),
  };
}

const List<Size> sweepSizes = <Size>[
  Size(360, 640),
  Size(640, 360),
  Size(768, 1024),
  Size(1440, 900),
];

/// Что не так на экране [size]: обрезанные подписи кнопок и кнопки вне
/// прокрутки, свисающие за край.
List<String> adaptiveProblems(WidgetTester tester, Size size) {
  final List<String> out = <String>[];
  final Rect screen = (Offset.zero & size).inflate(0.5);
  bool isButton(Widget w) =>
      w is ButtonStyleButton || w is IconButton || w is PopupMenuButton;
  for (final Element e in find
      .descendant(
          of: find.byWidgetPredicate(isButton), matching: find.byType(RichText))
      .evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is RenderParagraph &&
        ro.attached &&
        ro.hasSize &&
        ro.didExceedMaxLines) {
      out.add('обрезана подпись «${ro.text.toPlainText()}»');
    }
  }
  for (final Element e in find.byWidgetPredicate(isButton).evaluate()) {
    if (e.findAncestorStateOfType<ScrollableState>() != null) continue;
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.attached || !ro.hasSize || ro.size.isEmpty) {
      continue;
    }
    final Rect r = ro.localToGlobal(Offset.zero) & ro.size;
    if (!screen.contains(r.topLeft) || !screen.contains(r.bottomRight)) {
      out.add('кнопка ${e.widget.key ?? e.widget.runtimeType} $r за краем');
    }
  }
  return out;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(rootBundle.clear);

  for (final MapEntry<String, ((Widget, World Function()), SweepOpen?)> s
      in sweepScreens().entries) {
    for (final Size size in sweepSizes) {
      for (final double scale in <double>[1.0, 1.3]) {
        testWidgets(
            '${s.key} · ${size.width.toInt()}×${size.height.toInt()} · '
            'шрифт $scale', (WidgetTester tester) async {
          final SemanticsHandle sem = tester.ensureSemantics();
          await pumpListedScreen(tester, s.key, s.value.$1,
              size: size, textScale: scale);
          if (s.value.$2 case final SweepOpen open) await open(tester);
          expect(tester.takeException(), isNull, reason: 'переполнение');
          final List<String> bad = adaptiveProblems(tester, size);
          expect(bad, isEmpty, reason: bad.join('; '));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          sem.dispose();
        });
      }
    }
  }
}
