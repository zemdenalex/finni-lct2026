import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:finlit/features/world/room_iso/iso_room_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Мебель iso-комнаты стоит по местам (Денис 20.10: «в комнате всё выглядит
/// не по месту»).
///
/// Защищает: на каждой стадии картинки кровати, тумбы с копилкой, стола и
/// холодильника не лезут друг на друга больше чем на [_maxShare] меньшей из
/// двух; Финни ниже холодильника и двери, лежанка питомца ниже Финни.
/// Уронит: холодильник снова в углу перед кроватью (было 44–54 % его
/// площади), вещь крупнее своего места, Финни выше двери.
/// Почему не ловят другие: `iso_room_scene_test` проверяет, что вещи есть,
/// нажимаются и стоят в порядке глубины, но не как их картинки лежат друг на
/// друге.

const double _maxShare = 0.3;

void main() {
  late RoomArt art;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    art = await RoomArt.load();
  });

  Rect picture(WidgetTester tester, String slot) => tester.getRect(find
      .descendant(
          of: find.byKey(ValueKey<String>('room:iso:slot:$slot')),
          matching: find.byType(Image))
      .first);

  for (final WorldStage stage in WorldStage.values) {
    testWidgets('${stage.name}: мебель не налезает, Финни в масштабе',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
            size: Size(1440, 900), disableAnimations: true),
        child: MaterialApp(
          home: Material(
            child: IsoRoomScene(
              art: art,
              stage: stage,
              species: 'finni-a1',
              idleTag: 'idle-1',
              finniName: 'Финни',
              happiness: 60,
              decorIds: const <String>[],
              petId: 'pet_kitten',
            ),
          ),
        ),
      ));
      for (int i = 0; i < 5; i++) {
        await tester.pump();
      }
      const List<String> furniture = <String>[
        'bed',
        'bedside_cabinet',
        'desk_chair',
        'fridge',
      ];
      final Map<String, Rect> r = <String, Rect>{
        for (final String s in furniture) s: picture(tester, s),
      };
      double area(Rect a) => a.width * a.height;
      for (int i = 0; i < furniture.length; i++) {
        for (int j = i + 1; j < furniture.length; j++) {
          final Rect a = r[furniture[i]]!;
          final Rect b = r[furniture[j]]!;
          final Rect x = a.intersect(b);
          final double over = x.width <= 0 || x.height <= 0 ? 0 : area(x);
          final double share = over / (area(a) < area(b) ? area(a) : area(b));
          expect(share, lessThanOrEqualTo(_maxShare),
              reason: '${furniture[i]} $a и ${furniture[j]} $b: '
                  '${(share * 100).round()} %');
        }
      }
      final double finni = tester
          .getSize(find
              .descendant(
                  of: find.byKey(const ValueKey<String>('room:finni')),
                  matching: find.byType(SizedBox))
              .first)
          .height;
      expect(finni, lessThan(r['fridge']!.height),
          reason: 'Финни ниже холодильника');
      final double door = tester
          .getSize(find.byKey(const ValueKey<String>('room:door')))
          .height;
      expect(finni, lessThan(door * 0.9), reason: 'Финни ниже двери');
      expect(picture(tester, 'pet_corner').height, lessThan(finni * 0.6),
          reason: 'лежанка питомца ниже Финни');
      expect(tester.takeException(), isNull);
    });
  }
}
