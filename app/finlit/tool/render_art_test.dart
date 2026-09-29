import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finlit/core/finni_art.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_art.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/goal.dart';
import 'package:finlit/domain/models/pet.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fonts.dart';

/// Лист всех обликов Финни: три вида × три расцветки × три стадии, плюс
/// настроения, поза радости и шапочка. Не тест поведения — он нужен, чтобы
/// на рисунок можно было посмотреть, а не рассуждать о нём по коду.
///
///     flutter test tool/render_art_test.dart   →   build/art/finni-sheet.png
///
/// 🔴 Рисуется напрямую в `PictureRecorder`, без дерева виджетов. Старый
/// лист (`generate_finni_sheet_test.dart`) собирался из виджетов и после
/// записи PNG не завершался; здесь нечему висеть.
void main() {
  setUpAll(loadAppFonts);
  test('лист Финни', () async {
    const double cell = 220;
    const List<PetMeters> moods = <PetMeters>[
      PetMeters(fullness: 2, cleanliness: 3, mood: 2),
      PetMeters(fullness: 6, cleanliness: 6, mood: 5),
      PetMeters(fullness: 10, cleanliness: 9, mood: 9),
    ];
    final List<FinniLook> looks = <FinniLook>[
      for (final PetSpecies sp in PetSpecies.values) ...<FinniLook>[
        for (final PetPalette p in PetPalette.values)
          FinniLook(
            species: sp,
            palette: FinniPalette.of(p),
            stage: PetStage.novice,
            meters: moods[2],
          ),
        for (final PetStage st in PetStage.values)
          FinniLook(
            species: sp,
            palette: FinniPalette.of(PetPalette.values[sp.index]),
            stage: st,
            meters: moods[1],
          ),
        FinniLook(
          species: sp,
          palette: FinniPalette.of(PetPalette.values[sp.index]),
          stage: PetStage.novice,
          meters: moods[0],
        ),
        FinniLook(
          species: sp,
          palette: FinniPalette.of(PetPalette.values[sp.index]),
          stage: PetStage.saver,
          meters: moods[2],
          pose: FinniPose.cheer,
          accessories: const <String>{'hat'},
        ),
      ],
    ];
    const int cols = 8;
    final int rows = (looks.length / cols).ceil();
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas canvas = Canvas(rec);
    canvas.drawRect(const Rect.fromLTWH(0, 0, cols * cell, 10000),
        Paint()..color = AppColors.paper);
    for (int i = 0; i < looks.length; i++) {
      canvas.save();
      canvas.translate((i % cols) * cell, (i ~/ cols) * cell);
      FinniPainter(look: looks[i]).paint(canvas, const Size(cell, cell));
      canvas.restore();
    }
    final ui.Image img = await rec
        .endRecording()
        .toImage((cols * cell).toInt(), (rows * cell).toInt());
    final ByteData? png = await img.toByteData(format: ui.ImageByteFormat.png);
    final File out = File('build/art/finni-sheet.png');
    await out.create(recursive: true);
    await out.writeAsBytes(png!.buffer.asUint8List());
  });

  test('комната', () async {
    CatalogItem item(String id, String icon) => CatalogItem(
          id: id,
          title: id,
          envelope: Envelope.wants,
          price: 1,
          effect: const PetMeters(fullness: 0, cleanliness: 0, mood: 1),
          hint: '',
          icon: icon,
          keeps: true,
        );
    const Goal house = Goal(
        id: 'house', title: 'Домик', price: 30, isExperience: false,
        icon: 'house');
    const Goal scooter = Goal(
        id: 'scooter', title: 'Самокат', price: 40, isExperience: false,
        icon: 'scooter');
    const Goal zoo = Goal(
        id: 'zoo', title: 'Зоопарк', price: 20, isExperience: true,
        icon: 'zoo');
    final List<(RoomScene, PetSpecies, PetPalette)> scenes =
        <(RoomScene, PetSpecies, PetPalette)>[
      (const RoomScene(stage: PetStage.novice, keepsakes: <(CatalogItem, int)>[]),
          PetSpecies.squirrel, PetPalette.apricot),
      (RoomScene(
          stage: PetStage.saver,
          keepsakes: <(CatalogItem, int)>[
            (item('stickers', 'star'), 3),
            (item('ball', 'ball'), 1),
            (item('book', 'book'), 2),
          ],
          goal: house,
          saved: 12), PetSpecies.fox, PetPalette.apricot),
      (RoomScene(
          stage: PetStage.planner,
          keepsakes: <(CatalogItem, int)>[
            (item('stickers', 'star'), 5),
            (item('ball', 'ball'), 2),
            (item('book', 'book'), 4),
            (item('hat', 'hat'), 2),
            (item('kite', 'kite'), 1),
          ],
          goal: scooter,
          saved: 40), PetSpecies.owl, PetPalette.lilac),
      (const RoomScene(
          stage: PetStage.novice,
          keepsakes: <(CatalogItem, int)>[],
          goal: zoo,
          saved: 5), PetSpecies.squirrel, PetPalette.mint),
    ];
    const double w = 660;
    const double h = w * RoomLayout.aspect;
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas canvas = Canvas(rec);
    for (int i = 0; i < scenes.length; i++) {
      final (RoomScene sc, PetSpecies sp, PetPalette pal) = scenes[i];
      canvas.save();
      canvas.translate((i % 2) * (w + 20), (i ~/ 2) * (h + 20));
      RoomPainter(sc).paint(canvas, const Size(w, h));
      const double fs = w * RoomLayout.finniSize;
      canvas.translate(w * RoomLayout.finniX - fs / 2,
          h * RoomLayout.floorY - fs * 0.92);
      FinniPainter(
        look: FinniLook(
          species: sp,
          palette: FinniPalette.of(pal),
          stage: sc.stage,
          meters: const PetMeters(fullness: 8, cleanliness: 8, mood: 8),
          accessories: sc.countOf('hat') > 0 ? const <String>{'hat'} : const <String>{},
        ),
      ).paint(canvas, const Size(fs, fs));
      canvas.restore();
    }
    final ui.Image img = await rec
        .endRecording()
        .toImage((2 * w + 20).toInt(), (2 * h + 20).toInt());
    final ByteData? png = await img.toByteData(format: ui.ImageByteFormat.png);
    final File out = File('build/art/rooms.png');
    await out.create(recursive: true);
    await out.writeAsBytes(png!.buffer.asUint8List());
  });
}
