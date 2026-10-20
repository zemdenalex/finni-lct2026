import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:finlit/features/world/room_iso/iso_painter.dart';
import 'package:finlit/features/world/room_iso/iso_room.dart';
import 'package:finlit/features/world/room_iso/iso_room_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Iso room frame (n6-room2, Денис 20.10 12:51: «камеру нужно ближе к
/// Финни»; n6-room-bg, Денис 20.10 22:21: «Не надо продолжениями стены и
/// пола, это выглядит плохо, лучше простой фон»).
///
/// Protects: the room opens close to Finni (he is bigger than in the
/// whole-room view and near the middle, the button offers «Вся комната»),
/// and around the whole room the scene shows its plain dark background on a
/// tall phone, a phone on its side and a desktop window.
/// Would fail on: the old first frame (the whole room, «К Финни»), and the
/// n6-room2 fill, which went on with walls and floor to the view's edges
/// (no background pixel left).
/// Why not covered elsewhere: the camera tests only read Finni's size
/// relative to the first frame, and nothing reads the scene's pixels.

IsoRoomSpec _spec() => IsoRoomSpec.parse(
    File('assets/content/world/room_layout_iso.json').readAsStringSync());

const List<Size> _sizes = <Size>[
  Size(360, 800),
  Size(800, 360),
  Size(1440, 900),
];

/// Screen points within [tol] (per channel) of the scene background,
/// sampled every [step] px, outside [skip].
int _bare(ByteData px, int w, int h, Rect skip, {int step = 3, int tol = 10}) {
  const Color b = IsoColors.back;
  final int br = (b.r * 255).round(),
      bg = (b.g * 255).round(),
      bb = (b.b * 255).round();
  int n = 0;
  for (int y = 0; y < h; y += step) {
    for (int x = 0; x < w; x += step) {
      if (skip.contains(Offset(x.toDouble(), y.toDouble()))) continue;
      final int i = (y * w + x) * 4;
      if ((px.getUint8(i) - br).abs() <= tol &&
          (px.getUint8(i + 1) - bg).abs() <= tol &&
          (px.getUint8(i + 2) - bb).abs() <= tol) {
        n++;
      }
    }
  }
  return n;
}

void main() {
  final IsoRoomSpec spec = _spec();
  late RoomArt art;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    art = await RoomArt.load();
  });

  const ValueKey<String> spot = ValueKey<String>('room:finni:spot');
  const ValueKey<String> camera = ValueKey<String>('room:iso:camera');
  final GlobalKey shot = GlobalKey();

  Future<void> pump(WidgetTester tester, Size size, double topInset) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: true),
      child: MaterialApp(
        home: Material(
          child: RepaintBoundary(
            key: shot,
            child: IsoRoomScene(
              art: art,
              stage: WorldStage.town,
              species: 'finni-a2',
              idleTag: 'idle-1',
              finniName: 'Финни',
              happiness: 60,
              spec: spec,
              topInset: topInset,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<int> bareCount(WidgetTester tester, Size size) async {
    final Rect button = tester.getRect(find.byKey(camera)).inflate(2);
    final int? n = await tester.runAsync(() async {
      final RenderRepaintBoundary b =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await b.toImage();
      final ByteData px =
          (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      return _bare(px, img.width, img.height, button);
    });
    return n!;
  }

  for (final Size size in _sizes) {
    final String name = '${size.width.toInt()}×${size.height.toInt()}';
    // The room screen puts the HUD over the top of the scene.
    final double inset = size.width > size.height ? 96 : 120;

    testWidgets('$name: комната открывается близко к Финни',
        (WidgetTester tester) async {
      await pump(tester, size, inset);
      final double close = tester.getSize(find.byKey(spot)).height;
      final Rect f = tester.getRect(find.byKey(spot));
      final Offset mid = Offset(size.width / 2, inset + (size.height - inset) / 2);
      expect((f.center.dx - mid.dx).abs(), lessThan(size.width * 0.2),
          reason: 'Финни у середины по ширине: ${f.center}');
      expect(f.top, greaterThanOrEqualTo(inset - 1),
          reason: 'голова Финни не под строкой сверху: $f');
      expect(f.bottom, lessThanOrEqualTo(size.height + 1),
          reason: 'ноги Финни в кадре: $f');
      expect(find.text('Вся комната'), findsOneWidget);

      await tester.tap(find.byKey(camera));
      await tester.pumpAndSettle();
      final double whole = tester.getSize(find.byKey(spot)).height;
      // Finni a set share of the view, not a fixed ×2.2 (1440×900 blew him
      // past the frame); at least ×1.3 closer, at most ×2.2.
      final double z = close / whole;
      expect(z, greaterThanOrEqualTo(IsoRoomScene.minCloseZoom - 0.01),
          reason: 'первый кадр ближе, чем вся комната');
      expect(z, lessThanOrEqualTo(IsoRoomScene.finniZoom + 0.01));
      final double want = (size.height - inset) * IsoRoomScene.finniShare;
      expect(
          (close - want).abs() <= 1 ||
              (z - IsoRoomScene.minCloseZoom).abs() < 0.01 ||
              (z - IsoRoomScene.finniZoom).abs() < 0.01,
          isTrue,
          reason: 'Финни $close из нужных $want, ×$z');
      expect(find.text('К Финни'), findsOneWidget);
    });

    testWidgets('$name: вокруг всей комнаты простой фон, без продолжений',
        (WidgetTester tester) async {
      await pump(tester, size, inset);
      await tester.tap(find.byKey(camera));
      await tester.pumpAndSettle();
      expect(await bareCount(tester, size), greaterThan(0),
          reason: 'вся комната: вокруг ровный фон сцены');
    });
  }
}
