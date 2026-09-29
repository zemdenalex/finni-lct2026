import 'package:finlit/core/art/sprite_anim.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/room_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Фон комнаты по стадии — имена файлов из `assets/art/registry.json`
/// (группа `room`, фоны общей раскладки `<stage>_room` из
/// `room_layout.json`), выписаны руками, а не взяты из `roomIdByStage`.
const Map<WorldStage, String> _bgByStage = <WorldStage, String>{
  WorldStage.village: 'gen-village@3x.png',
  WorldStage.town: 'gen-town@3x.png',
  WorldStage.moscow: 'gen-moscow@3x.png',
};

/// Ловит (ТЗ 2.5.10.1): на всех стадиях одна комната — стадия не доходит
/// до фона, id стадии не совпал с реестром и сцена молча взяла прежнюю
/// комнату `home`. Проверяет сцену при данной стадии; что комната берёт
/// стадию из мира — `room_screen.dart` (`snap.stage`).
void main() {
  late RoomArt art;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    art = await RoomArt.load();
  });

  for (final MapEntry<WorldStage, String> e in _bgByStage.entries) {
    testWidgets('стадия ${e.key.name} → фон ${e.value}',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 360,
          height: 400,
          child: RoomScene(
            art: art,
            stage: e.key,
            species: 'finni-a2',
            idleTag: 'idle-1',
            finniName: 'Финни',
            happiness: 60,
          ),
        ),
      ));
      await tester.pump();

      final List<String> paths = tester
          .widgetList<PixelImage>(find.byType(PixelImage))
          .map((PixelImage p) => p.path ?? '')
          .toList();
      for (final MapEntry<WorldStage, String> other in _bgByStage.entries) {
        final bool shown = paths.any((String p) => p.endsWith(other.value));
        expect(shown, other.key == e.key,
            reason: '${other.value} на стадии ${e.key.name}: $paths');
      }
    });
  }

  // Ревью 28.09: знакомство рисует комнату без обработчиков — дверь, кровать
  // и холодильник были кнопками TalkBack без действия. Без обработчика это
  // просто картинка.
  for (final WorldStage stage in WorldStage.values) {
    testWidgets(
        'без обработчиков предметы — картинки, не кнопки · ${stage.name}',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 800,
          height: 360,
          child: RoomScene(
            art: art,
            stage: stage,
            species: 'finni-a2',
            idleTag: 'idle-1',
            finniName: 'Финни',
            happiness: 60,
          ),
        ),
      ));
      await tester.pump();
      final List<String> paths = tester
          .widgetList<PixelImage>(find.byType(PixelImage))
          .map((PixelImage p) => p.path ?? '')
          .toList();
      // Мебель в готовом фоне: кровать — его вырезка поверх Финни.
      expect(find.byKey(const ValueKey<String>('room:furniture:bed')),
          findsOneWidget,
          reason: 'кровать нарисована — иначе проверка пустая: $paths');
      expect(
          find.bySemanticsLabel(
              RegExp(r'^(Холодильник|Дверь — в город|Кровать — лечь спать)')),
          findsNothing);
      sem.dispose();
    });
  }
}
