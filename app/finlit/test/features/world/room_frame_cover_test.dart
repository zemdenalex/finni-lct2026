import 'package:finlit/features/world/home/room_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ловит: в сценках знакомства узкая полоса комнаты снова в тёмных полях
/// по бокам (ревью 29.09, «швы») — с `cover` фон закрывает сцену целиком.
void main() {
  const RoomSlots slots = RoomSlots(Size(272, 400), <String, Offset>{
    'finni': Offset(136, 380),
  });
  for (final Size box in <Size>[
    const Size(360, 200),
    const Size(360, 330),
    const Size(330, 360),
  ]) {
    test('cover: фон закрывает сцену $box без полей', () {
      final RoomFrame f = roomFrame(slots, box: box, hires: true, cover: true);
      final Rect bg = Rect.fromLTWH(
          f.left, f.top, slots.size.width * f.k, slots.size.height * f.k);
      expect(bg.left, lessThanOrEqualTo(0));
      expect(bg.top, lessThanOrEqualTo(0));
      expect(bg.right, greaterThanOrEqualTo(box.width - 0.01));
      expect(bg.bottom, greaterThanOrEqualTo(box.height - 0.01));
    });
  }
}
