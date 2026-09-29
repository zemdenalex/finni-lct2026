import 'dart:io';
import 'dart:ui' as ui;

import 'package:finlit/core/art/asset_registry.dart';
import 'package:finlit/core/art/sprite_anim.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Стенд комнат по стадиям и hi-res спрайтов:
///
///     flutter test tool/render_room_stages_test.dart  →  build/world/rooms-*.png
///
/// Экранный стенд показывает только текущую стадию FakeWorld; здесь — все
/// три, с питомцем спящим и проснувшимся, в размерах сцены альбомной и
/// портретной. Плюс лист питомцев и Финни в карточке 72 × 64. На CI не гоняется.
void main() {
  Future<void> shoot(WidgetTester tester, String name, Size size,
      Widget Function(RoomArt art, AssetRegistry reg) build) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final GlobalKey key = GlobalKey();
    await tester.runAsync(() async {
      final RoomArt art = await RoomArt.load();
      final AssetRegistry reg = await AssetRegistry.load();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MediaQuery(
          // Кадр без движения: снимок стоит на первом кадре тега.
          data: const MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ColoredBox(color: Colors.white, child: build(art, reg)),
          ),
        ),
      ));
      for (int i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
      final RenderRepaintBoundary b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await b.toImage(pixelRatio: 2);
      final ByteData? png =
          await img.toByteData(format: ui.ImageByteFormat.png);
      final File out = File('build/world/rooms-$name.png');
      await out.create(recursive: true);
      await out.writeAsBytes(png!.buffer.asUint8List());
    });
  }

  // Сцена комнаты на экране: альбомная ≈ 358 × 256, портретная ≈ 360 × 300.
  const Map<String, Size> boxes = <String, Size>{
    'land': Size(358, 256),
    'port': Size(360, 300),
  };
  for (final MapEntry<String, Size> box in boxes.entries) {
    testWidgets('stages-${box.key}', (WidgetTester tester) async {
      final Size b = box.value;
      await shoot(
          tester,
          'stages-${box.key}',
          Size(b.width * 3 + 16, b.height * 3 + 16),
          (RoomArt art, AssetRegistry reg) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final (String sp, String? pet, bool awake)
                      in <(String, String?, bool)>[
                    ('finni-a1', 'pet_kitten', false),
                    ('finni-a2', 'pet_frog', true),
                    ('finni-a3', 'pet_dog', true),
                  ])
                    for (final WorldStage st in WorldStage.values)
                      SizedBox.fromSize(
                        size: b,
                        child: RoomScene(
                          art: art,
                          stage: st,
                          species: sp,
                          idleTag: 'idle-1',
                          finniName: 'Финни',
                          happiness: 5,
                          petId: pet,
                          petAwake: awake,
                          decorIds: decorToShow(<String>[
                            'poster_city',
                            'plant_floor',
                            'plant_cactus',
                            'light_garland_long',
                          ]),
                        ),
                      ),
                ],
              ));
    });
  }

  testWidgets('sprites', (WidgetTester tester) async {
    await shoot(
        tester,
        'sprites',
        const Size(640, 300),
        (RoomArt art, AssetRegistry reg) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String id in reg.ids('pets'))
                  for (final String tag in <String>['sleep', 'wake'])
                    if (reg.pet(id) case final SpriteRef p)
                      Container(
                        width: 72,
                        height: 64,
                        color: const Color(0xFFEEEEEE),
                        child: Center(
                            child: SpriteAnim(
                                sprite: p, tag: tag, height: 64, play: false)),
                      ),
                for (final String s in reg.ids('finni'))
                  for (final String tag in <String>['idle-1', 'walk', 'wave'])
                    if (reg.finni(s) case final SpriteRef f)
                      SpriteAnim(sprite: f, tag: tag, height: 120, play: false),
              ],
            ));
  });
}
