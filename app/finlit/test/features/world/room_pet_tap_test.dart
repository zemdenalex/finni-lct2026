import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show HitTestEntry, HitTestResult;
import 'package:flutter/rendering.dart' show RenderObject, SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Питомец в комнате (n5 #7, перепроверка Саши A1): зона касания была ровно
/// по кадру спрайта и в альбомной 640×360 меньше 48 dp (на 91986699 —
/// у всех пяти питомцев магазина, см. red-7). Для TalkBack — картинка «Питомец» без роли
/// кнопки, хотя по касанию его можно погладить.
///
/// Защищает: зона касания каждого купленного питомца не меньше 48×48 dp в
/// обеих ориентациях и при шрифте 1,3; для TalkBack это кнопка «Питомец»;
/// расширенная зона не забирает касание у центра соседних зон комнаты.
/// Уронит: зона снова по размеру спрайта, роль кнопки потеряна, зона
/// питомца легла поверх кровати или копилки.
/// Почему не ловили: `tap_targets_test` берёт мир `livingWorld`, где питомца
/// нет.
const double _min = 48;

Future<void> _pumpRoom(WidgetTester tester, World w, Size size, double scale) =>
    tester.runAsync(() async {
      await pumpWorldScreen(tester, const RoomScreen(),
          world: w, size: size, textScale: scale);
      for (int i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump();
      }
    });

Set<RenderObject> _renders(WidgetTester tester, Finder of) => <RenderObject>{
      for (final Element e in <Element>[
        ...of.evaluate(),
        ...find
            .descendant(of: of, matching: find.byWidgetPredicate((_) => true))
            .evaluate(),
      ])
        if (e.renderObject != null) e.renderObject!,
    };

void main() {
  final World probe = contentDayWorld();
  final List<String> pets = <String>[
    for (final WorldCatalogItem i in probe.catalog)
      if (i.category == WorldCatalogCategory.pet) i.id,
  ];

  test('в каталоге есть питомцы — тест ниже проверяет каждого', () {
    expect(pets, isNotEmpty);
  });

  for (final String pet in pets) {
    testWidgets('$pet: зона касания ≥ 48×48, кнопка «Питомец», соседи целы',
        (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      final List<String> small = <String>[];
      final List<String> stolen = <String>[];
      final List<String> noButton = <String>[];
      for (final (String o, Size size) in <(String, Size)>[
        ('портрет', portrait),
        ('альбом', landscape),
      ]) {
        for (final double scale in const <double>[1, 1.3]) {
          await _pumpRoom(tester, petWorld(dayWorldKind, pet), size, scale);
          final String at = '$o ×$scale';
          final Finder f = find.byKey(ValueKey<String>('room:pet:$pet'));
          expect(f, findsOneWidget, reason: '$at: питомца нет в комнате');
          final Rect r = tester.getRect(f);
          if (r.width < _min || r.height < _min) {
            small.add('$at: ${r.width.toStringAsFixed(1)}×'
                '${r.height.toStringAsFixed(1)}');
          }
          if (find.semantics
                  .byPredicate((SemanticsNode n) =>
                      n.getSemanticsData().label == 'Питомец' &&
                      n.getSemanticsData().flagsCollection.isButton)
                  .evaluate()
                  .length !=
              1) {
            noButton.add(at);
          }
          // Соседние зоны комнаты: их центр не уходит под питомца.
          final Set<RenderObject> petRender = _renders(tester, f);
          final Finder zones = find.byWidgetPredicate((Widget x) =>
              x.runtimeType.toString() == '_RoomTap' &&
              x.key is ValueKey<String>);
          for (final Element z in zones.evaluate()) {
            final Offset c = tester.getCenter(find.byWidget(z.widget));
            final HitTestResult hit = tester.hitTestOnBinding(c);
            if (hit.path
                .any((HitTestEntry e) => petRender.contains(e.target))) {
              stolen.add('$at: ${(z.widget.key! as ValueKey<String>).value}');
            }
          }
        }
      }
      expect(small, isEmpty, reason: '$pet: зона касания меньше 48 dp');
      expect(stolen, isEmpty, reason: '$pet: питомец закрыл центр соседа');
      expect(noButton, isEmpty, reason: '$pet: TalkBack — не кнопка «Питомец»');
      h.dispose();
    });
  }
}
