import 'dart:convert';
import 'dart:io';

import 'package:finlit/app_state.dart';
import 'package:finlit/core/art/sprite_anim.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:finlit/features/world/city/city_screen.dart';
import 'package:finlit/features/world/finni_walker.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/piggy/piggy_screen.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Ходьба Финни (Денис, 938: «механика хождения Финни по квартире и по
/// городу»): касание предмета комнаты или здания на карте — Финни идёт
/// туда, потом действие. «Анимации» выкл. (ТЗ 3.6.7) — действие сразу.
///
/// Ловит: телепорт вместо ходьбы (экран открывается в тот же кадр, Финни
/// не сдвинулся), ходьба дольше секунды (ТЗ §3.4) или ходьба при
/// выключенных анимациях.
void main() {
  setUp(rootBundle.clear);

  /// Экран под runAsync: арт, реестр и альфа зданий читаются из бандла.
  Future<void> pump(WidgetTester tester, Widget screen,
      {required Size size, bool animations = true}) async {
    await tester.runAsync(() async {
      AppState? app;
      if (!animations) {
        app = AppState(MemoryStorage());
        await app.boot();
        await app.updateProfile(app.game.profile
            .copyWith(settings: const GameSettings(animationsOn: false)));
      }
      await pumpWorldScreen(tester, screen,
          world: livingWorld(worldKinds.last), size: size, app: app);
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pump();
  }

  double xOf(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey<String>(key))).center.dx;

  for (final MapEntry<String, Size> o in bothOrientations.entries) {
    // Все четыре предмета: сначала Финни идёт (цель ходьбы — у предмета),
    // через 150 мс действия ещё нет, после [RoomScene.roomWalk] — есть.
    for (final (String key, Finder Function() done)
        in <(String, Finder Function())>[
      ('room:bed', () => find.text('Лечь спать?')),
      ('room:fridge', () => find.byType(WorldShopScreen)),
      ('room:door', () => find.byType(CityScreen)),
      ('room:piggy', () => find.byType(PiggyScreen)),
    ]) {
      testWidgets('комната · ${o.key}: $key — Финни идёт, потом действие',
          (WidgetTester tester) async {
        await pump(tester, const RoomScreen(), size: o.value);
        Offset target() => tester
            .widget<FinniWalker>(
                find.byKey(const ValueKey<String>('room:finni:spot')))
            .at;
        final Offset before = target();
        await tester.tapAt(pointOn(tester, key));
        await tester.pump(); // кадр, с которого идёт ход
        await tester.pump(const Duration(milliseconds: 150));
        expect(done(), findsNothing, reason: 'сначала Финни идёт, потом $key');
        expect(target(), isNot(before), reason: 'Финни пошёл к $key');
        await tester.pump(RoomScene.roomWalk);
        await tester.pump();
        expect(done(), findsOneWidget, reason: key);
      });
    }

    testWidgets('комната · ${o.key}: копилка — Финни в пути уже через 150 мс',
        (WidgetTester tester) async {
      await pump(tester, const RoomScreen(), size: o.value);
      final double home = xOf(tester, 'room:finni:spot');
      await tester.tap(find.byKey(const ValueKey<String>('room:piggy')));
      await tester.pump(); // кадр, с которого идёт ход
      await tester.pump(const Duration(milliseconds: 150));
      expect(xOf(tester, 'room:finni:spot'), isNot(closeTo(home, 4)),
          reason: 'Финни уже в пути');
      expect(RoomScene.roomWalk, lessThan(const Duration(seconds: 1)),
          reason: 'ТЗ §3.4: отклик не дольше секунды');
      await tester.pump(RoomScene.roomWalk); // дошёл — копилка открылась
      await tester.pump();
    });

    testWidgets('комната · ${o.key}: «Анимации» выкл. — сразу S9, без ходьбы',
        (WidgetTester tester) async {
      await pump(tester, const RoomScreen(), size: o.value, animations: false);
      await tester.tap(find.byKey(const ValueKey<String>('room:piggy')));
      await tester.pump();
      await tester.pump();
      expect(find.byType(PiggyScreen), findsOneWidget);
    });

    for (final CityVariant v in CityVariant.values) {
      testWidgets(
          'город · ${v.name} · ${o.key}: здание — Финни идёт к нему, потом экран',
          (WidgetTester tester) async {
        await pump(tester, CityScreen(variant: v), size: o.value);
        // Дом и копилка на одной вертикали: Финни идёт вниз по улице.
        Offset at() => tester
            .getRect(find.byKey(const ValueKey<String>('city:finni')))
            .center;
        final Offset start = at();
        await tester.ensureVisible(
            find.byKey(const ValueKey<String>('city:building:piggy-bank')));
        await tester.pump();
        final Rect bank = tester.getRect(
            find.byKey(const ValueKey<String>('city:building:piggy-bank')));
        await tester
            .tapAt(Offset(bank.center.dx, bank.top + bank.height * 0.6));
        await tester.pump(); // кадр, с которого идёт ход
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.byType(PiggyScreen), findsNothing,
            reason: 'сначала Финни идёт, экран — потом');
        expect((at() - start).distance, greaterThan(2),
            reason: 'Финни уже в пути');
        await tester.pump(const Duration(milliseconds: 850));
        await tester.pump();
        expect(find.byType(PiggyScreen), findsOneWidget,
            reason: 'путь по карте не дольше секунды (ТЗ §3.4)');
      });

      testWidgets(
          'город · ${v.name} · ${o.key}: «Анимации» выкл. — экран сразу',
          (WidgetTester tester) async {
        await pump(tester, CityScreen(variant: v),
            size: o.value, animations: false);
        await tester.ensureVisible(
            find.byKey(const ValueKey<String>('city:building:piggy-bank')));
        await tester.pump();
        final Rect bank = tester.getRect(
            find.byKey(const ValueKey<String>('city:building:piggy-bank')));
        await tester
            .tapAt(Offset(bank.center.dx, bank.top + bank.height * 0.6));
        await tester.pump();
        await tester.pump();
        expect(find.byType(PiggyScreen), findsOneWidget);
      });

      // Ловит: значок роли не над своим зданием или его нет у части зданий
      // (разведка 29.09, §3; критерий «над каждым зданием иконка»).
      testWidgets(
          'город · ${v.name} · ${o.key}: над каждым зданием — значок его роли',
          (WidgetTester tester) async {
        await pump(tester, CityScreen(variant: v), size: o.value);
        for (final CityBuilding b in cityBuildings) {
          final Rect house = tester
              .getRect(find.byKey(ValueKey<String>('city:building:${b.id}')));
          final Rect icon =
              tester.getRect(find.byKey(ValueKey<String>('city:icon:${b.id}')));
          expect(icon.center.dx, closeTo(house.center.dx, 1), reason: b.id);
          expect(icon.top, lessThan(house.top), reason: b.id);
          expect(icon.bottom, lessThanOrEqualTo(house.top + icon.height),
              reason: b.id);
          final Icon glyph = tester.widget<Icon>(find.descendant(
              of: find.byKey(ValueKey<String>('city:icon:${b.id}')),
              matching: find.byType(Icon)));
          expect(glyph.icon, b.icon, reason: 'значок — тот же, что в списке');
        }
      });
    }
  }

  // Ловит: ребёнок нажал предмет и сразу кнопку внизу — после ходьбы
  // открывается второй экран поверх первого (ревью 29.09).
  testWidgets('комната: предмет, а следом кнопка — только один переход',
      (WidgetTester tester) async {
    await pump(tester, const RoomScreen(), size: portrait);
    await tester.tap(find.byKey(const ValueKey<String>('room:piggy')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('room:nav:progress')));
    await tester.pump();
    await tester.pump(RoomScene.roomWalk + const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.byType(PiggyScreen), findsNothing,
        reason: 'комната уже под «Прогрессом» — копилка не открывается');
  });

  testWidgets('город: здание, а следом кнопка списка — только один переход',
      (WidgetTester tester) async {
    await pump(tester, const CityScreen(), size: landscape);
    final Rect bank = tester.getRect(
        find.byKey(const ValueKey<String>('city:building:piggy-bank')));
    await tester.tapAt(Offset(bank.center.dx, bank.top + bank.height * 0.6));
    await tester.pump();
    final Finder shop =
        find.byKey(const ValueKey<String>('city:button:grocery'));
    await tester.ensureVisible(shop);
    await tester.tap(shop);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(WorldShopScreen), findsOneWidget);
    expect(find.byType(PiggyScreen), findsNothing);
  });

  // Ловит: в городе ходит Финни по умолчанию, а не облик ребёнка (ревью
  // 29.09: в комнате енот, в городе — зелёный росток).
  testWidgets('город: Финни на карте — облик, который выбрал ребёнок',
      (WidgetTester tester) async {
    final World w = livingWorld(worldKinds.last);
    await tester.runAsync(() async {
      final WorldState ws = WorldState(w);
      await ws.setFinniLook(species: 'finni-a2', look: 3);
      await pumpWorldScreen(tester, const CityScreen(),
          state: ws, size: portrait);
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    final Image img = tester.widget<Image>(find.descendant(
        of: find.byKey(const ValueKey<String>('city:finni')),
        matching: find.byType(Image)));
    expect((img.image as AssetImage).assetName, contains('finni-a2-3'));
  });

  // Ловит: в пути у выбранного облика нет своих кадров ходьбы — он скользит
  // статичной картинкой или идёт чужим обликом (арт 29.09: `finni_walk`,
  // тег `walk-<облик>` на каждый облик каждого вида).
  for (final (String where, Widget screen, String tap, String finni)
      in <(String, Widget, String, String)>[
    ('комната', const RoomScreen(), 'room:piggy', 'room:finni'),
    ('город', const CityScreen(), 'city:building:piggy-bank', 'city:finni'),
  ]) {
    testWidgets('$where: в пути — кадры ходьбы выбранного облика',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        final WorldState ws = WorldState(livingWorld(worldKinds.last));
        await ws.setFinniLook(species: 'finni-a2', look: 3);
        await pumpWorldScreen(tester, screen, state: ws, size: portrait);
        for (int i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
      });
      await tester.ensureVisible(find.byKey(ValueKey<String>(tap)));
      await tester.pump();
      await tester.tapAt(pointOn(tester, tap));
      await tester.pump(); // кадр, с которого идёт ход
      await tester.pump(const Duration(milliseconds: 150));
      final SpriteAnim anim = tester.widget<SpriteAnim>(find.descendant(
          of: find.byKey(ValueKey<String>(finni)),
          matching: find.byType(SpriteAnim)));
      expect(anim.sprite.sheet, contains('finni-a2_walk'));
      expect(anim.tag, 'walk-3');
      // Тег есть в самом листе — иначе кадров нет, а тест зелёный.
      final Map<String, Object?> data =
          jsonDecode(File(anim.sprite.data).readAsStringSync())
              as Map<String, Object?>;
      final List<Object?> tags = (data['meta']!
          as Map<String, Object?>)['frameTags']! as List<Object?>;
      expect(tags.map((Object? t) => (t! as Map<String, Object?>)['name']),
          contains('walk-3'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    });
  }

  // Ловит: здания и значки снова налезают друг на друга (ревью 29.09:
  // «Дом касается Магазина, значок Копилки на крыше Дома»).
  for (final CityVariant v in CityVariant.values) {
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      testWidgets(
          'город · ${v.name} · ${o.key}: здания и значки не накрывают '
          'друг друга', (WidgetTester tester) async {
        await pump(tester, CityScreen(variant: v), size: o.value);
        final Map<String, Rect> boxes = <String, Rect>{
          for (final CityBuilding b in cityBuildings) ...<String, Rect>{
            b.id: tester
                .getRect(find.byKey(ValueKey<String>('city:building:${b.id}'))),
            '${b.id}:icon': tester
                .getRect(find.byKey(ValueKey<String>('city:icon:${b.id}'))),
          },
        };
        // Спрайт прочитан — коробка по картинке (парк деревни 96 × 59),
        // а не заглушка 122 × 82.
        expect(boxes['park']!.height / boxes['park']!.width,
            closeTo(59 / 96, 0.01));
        final List<String> ids = boxes.keys.toList();
        for (int i = 0; i < ids.length; i++) {
          for (int j = i + 1; j < ids.length; j++) {
            final String a = ids[i], b = ids[j];
            if (a.split(':').first == b.split(':').first) {
              continue; // свой значок
            }
            final Rect x = boxes[a]!.intersect(boxes[b]!);
            expect(x.width <= 0.5 || x.height <= 0.5, isTrue,
                reason: '$a ${boxes[a]} и $b ${boxes[b]}');
          }
        }
      });
    }
  }

  // Ловит: камера прыгает при включённых «Анимациях» или плывёт при
  // выключенных (ТЗ 3.6.7). Здание из списка — камера едет к нему
  // (Денис, 29.09: «экран должен следовать за финни»).
  for (final bool anim in <bool>[true, false]) {
    testWidgets(
        'город: камера к зданию из списка — ${anim ? 'плавно' : 'сразу'}',
        (WidgetTester tester) async {
      await pump(tester, const CityScreen(variant: CityVariant.iso),
          size: const Size(360, 640), animations: anim);
      ScrollPosition camX() => tester
          .state<ScrollableState>(find
              .descendant(
                  of: find.byKey(const ValueKey<String>('city:cam-x'),
                      skipOffstage: false),
                  matching: find.byType(Scrollable, skipOffstage: false))
              .first)
          .position;
      final double start = camX().pixels;
      final Finder btn =
          find.byKey(const ValueKey<String>('city:button:piggy-bank'));
      await openCityPlaces(tester);
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final double mid = camX().pixels;
      await tester.pump(const Duration(milliseconds: 400));
      final double end = camX().pixels;
      expect((end - start).abs(), greaterThan(20),
          reason: 'камера поехала к Копилке');
      if (anim) {
        expect((mid - end).abs(), greaterThan(1), reason: 'в пути — плавно');
      } else {
        expect(mid, closeTo(end, 0.5), reason: 'без анимаций — сразу');
      }
      await tester.pumpAndSettle();
    });
  }
}
