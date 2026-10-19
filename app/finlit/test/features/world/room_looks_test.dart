import 'dart:io';

import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_save.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/core/art/sprite_anim.dart';
import 'package:finlit/features/world/home/room_layout.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:finlit/features/world/home/room_skins.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Комната с купленным видом мебели — критерии `docs/final/room-kriterii.md`
/// (Денис 1623: «кровать на кровать не находила», масштаб, лимит места,
/// сохранение).
Future<String> _read(String path) => File(path).readAsString();

Directory _dir() {
  final Directory d = Directory.systemTemp.createTempSync('finlit_looks_');
  addTearDown(() {
    try {
      d.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows держит файл хранилища до конца процесса — не беда.
    }
  });
  return d;
}

/// Мир с деньгами на покупки: автопилот доигрывает недели, новая неделя
/// спланирована всем свободным в «хочу».
Future<SavedWorld> _richWorld(Directory dir) async {
  final SavedWorld s =
      await openSavedWorld(read: _read, storage: FileStorage(dir));
  WorldAutopilot(s.world).playWeeks(4);
  final WorldGame w = s.world;
  if (w.phase == WeekPhase.review) w.payBills();
  if (w.phase == WeekPhase.weekStart) w.startWeek();
  if (w.phase == WeekPhase.planning) {
    w.plan(needs: 0, wants: w.snapshot.unallocated, goal: 0);
  }
  return s;
}

void main() {
  const String cheap = 'skin_cabinet__19a', dear = 'skin_cabinet__20a';

  // К6. Уронит: выбор вида не пишется в журнал (живёт в памяти процесса)
  // или журнал его не сворачивает обратно.
  test('К6: выбранный вид тумбы переживает перезапуск', () async {
    final Directory dir = _dir();
    final SavedWorld first = await _richWorld(dir);
    expect(first.world.buy(cheap).ok, isTrue, reason: 'настройка: денег');
    expect(first.world.buy(dear).ok, isTrue, reason: 'настройка: денег');
    // Последний купленный — дорогой; ребёнок вернул дешёвый.
    expect(first.world.chooseSkin(cheap).ok, isTrue);
    await first.flush();

    final SavedWorld again =
        await openSavedWorld(read: _read, storage: FileStorage(dir));
    final ResourceSnapshot s = again.world.snapshot;
    expect(s.chosenSkins, <String, String>{'skin_cabinet': cheap});
    expect(equippedSkins(s.owned, s.chosenSkins)['skin_cabinet'], cheap,
        reason: 'в комнате выбранный, а не последний купленный');
  });

  // К4 + К5. Уронит: не купленный вариант встал в комнату или отказ всё
  // равно пишет в журнал.
  test('К5: не купленный вид — отказ с подсказкой, журнал не меняется',
      () async {
    final SavedWorld s = await _richWorld(_dir());
    final int before = s.world.journal.length;
    final WorldResult r = s.world.chooseSkin(dear);
    expect(r.ok, isFalse);
    expect(r.reason, contains('купи'));
    expect(s.world.journal.length, before);
    expect(s.world.snapshot.chosenSkins, isEmpty);
  });

  // К1–К3 на экране. Уронит: под новым видом выглядывает нарисованная
  // мебель (нет пустой комнаты под ним), вид вылез за своё место на
  // соседей или растянут крупнее нарисованного.
  testWidgets('К1–К3: вид мебели в своём месте, под ним пустая комната',
      (WidgetTester tester) async {
    late RoomArt art;
    await tester.runAsync(() async => art = await RoomArt.load());
    const Map<String, String> skins = <String, String>{
      'bed': 'skin_bed__4a',
      'desk_chair': 'skin_desk__10a',
      'bedside_cabinet': cheap,
    };
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(640, 360), disableAnimations: true),
      child: MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 640,
            height: 360,
            child: RoomScene(
              art: art,
              stage: WorldStage.town,
              species: 'finni-a2',
              idleTag: 'idle-1',
              finniName: 'Финни',
              happiness: 60,
              furnitureSkins: skins,
            ),
          ),
        ),
      ),
    ));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    // Место предмета на экране — слот стадии на картинке фона.
    final Rect bg = tester.getRect(find
        .byWidgetPredicate((Widget w) =>
            w is PixelImage && (w.path ?? '').contains('gen-town'))
        .last);
    final RoomLayout town = art.layout!.forStage(art.layout!.stages['town']!);
    Rect slotOf(String id) {
      final Rect f = town.slots[id]!.rect;
      return Rect.fromLTWH(bg.left + f.left * bg.width,
          bg.top + f.top * bg.height, f.width * bg.width, f.height * bg.height);
    }

    final Map<String, Rect> place = <String, Rect>{};
    for (final String slot in skins.keys) {
      final Finder empty =
          find.byKey(ValueKey<String>('room:furniture:empty:$slot'));
      final Finder skin =
          find.byKey(ValueKey<String>('room:furniture:skin:$slot'));
      expect(empty, findsOneWidget, reason: '$slot: под видом нет пустой');
      expect(skin, findsWidgets, reason: '$slot: вида нет');
      final Rect e = slotOf(slot);
      place[slot] = e;
      // К1: пустая комната закрывает всё место нарисованного предмета.
      final Rect cover = tester.getRect(empty);
      expect(
          cover.contains(e.topLeft) &&
              cover.contains(e.bottomRight - const Offset(0.01, 0.01)),
          isTrue,
          reason: '$slot: пустая $cover не закрывает место $e');
      for (final Element el in skin.evaluate()) {
        final Rect r = tester.getRect(find.byWidget(el.widget));
        // К3/К2: внутри своего места (с допуском 0,5 px) — не крупнее
        // нарисованной мебели и не на соседях.
        expect(r.left, greaterThanOrEqualTo(e.left - 0.5), reason: slot);
        expect(r.right, lessThanOrEqualTo(e.right + 0.5), reason: slot);
        expect(r.top, greaterThanOrEqualTo(e.top - 0.5), reason: slot);
        expect(r.bottom, lessThanOrEqualTo(e.bottom + 0.5), reason: slot);
        // И не крошечный: хотя бы одной стороной во всё место.
        expect(r.width >= e.width - 1 || r.height >= e.height - 1, isTrue,
            reason: '$slot: вид $r меньше места $e по обеим сторонам');
      }
    }
    // К1: пустая комната закрывает всё место нарисованного предмета, и
    // рисуется под видом (раньше в дереве).
    final List<Widget> order = tester
        .widgetList(find.byWidgetPredicate((Widget w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('room:furniture:')))
        .toList();
    int idx(String k) => order.indexWhere((Widget w) =>
        (w.key! as ValueKey<String>).value == 'room:furniture:$k');
    for (final String slot in skins.keys) {
      expect(idx('empty:$slot'), lessThan(idx('skin:$slot')), reason: slot);
    }
  });

  // Слияние bed-depth и видов. Уронит: форма нарисованных кровати и стола
  // (одна картинка на обе) рисуется поверх купленной вещи — старая видна над
  // новой; или не купленная вещь режется прямоугольником места — Финни у неё
  // опять теряет туловище (баг-репорт 15.10). [shapes] — какие вещи идут
  // своей формой по месту; `*` — форма целиком.
  for (final (String name, Map<String, String> skins, Set<String> shapes)
      in <(String, Map<String, String>, Set<String>)>[
    ('без видов — форма целиком', <String, String>{}, <String>{'*'}),
    (
      'куплена кровать — стол своей формой',
      <String, String>{'bed': 'skin_bed__4a'},
      <String>{'desk_chair'},
    ),
    (
      'куплен стол — кровать своей формой',
      <String, String>{'desk_chair': 'skin_desk__10a'},
      <String>{'bed'},
    ),
  ]) {
    testWidgets('глубина: $name', (WidgetTester tester) async {
      late RoomArt art;
      await tester.runAsync(() async => art = await RoomArt.load());
      await tester.pumpWidget(MediaQuery(
        data:
            const MediaQueryData(size: Size(640, 360), disableAnimations: true),
        child: MaterialApp(
          home: SizedBox(
            width: 640,
            height: 360,
            child: RoomScene(
              art: art,
              stage: WorldStage.town,
              species: 'finni-a2',
              idleTag: 'idle-1',
              finniName: 'Финни',
              happiness: 60,
              furnitureSkins: skins,
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('room:front:shape')),
          shapes.contains('*') ? findsOneWidget : findsNothing);
      for (final String id in <String>['bed', 'desk_chair']) {
        expect(find.byKey(ValueKey<String>('room:furniture:shape:$id')),
            shapes.contains(id) ? findsOneWidget : findsNothing,
            reason: '$id: форма по месту');
        // Прямоугольник фона (старый срез) — нигде, раз форма есть.
        expect(find.byKey(ValueKey<String>('room:furniture:$id')), findsNothing,
            reason: '$id: срез прямоугольником');
      }
    });
  }
}
