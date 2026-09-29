import 'package:finlit/domain/world/contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Эмодзи: пиктограммы Unicode, символы-значки и флажок VS16.
final RegExp _emoji = RegExp(
    '[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B50}\u{2B06}\u{2194}-\u{21FF}'
    '\u{FE0F}]',
    unicode: true);

/// Нажимаемое: кнопки Material и плитки на `InkWell`.
final Finder _tappable = find.byWidgetPredicate(
    (Widget w) => w is ButtonStyleButton || w is InkWell || w is IconButton);

/// Интерфейс мира рисует значки вектором (`Pic`), а не эмодзи: на Android 8
/// и в браузере эмодзи берутся из системного шрифта и выглядят по-разному,
/// а на скриншотах сдачи бывают пустыми (`docs/design-system.md` §5).
///
/// Ловит: эмодзи в подписи кнопки, плитки или нижней панели — до 28.09 так
/// были сделаны «🏙 В город», «🌙 Спать» и вся нижняя панель комнаты.
/// Текст из контента (фразы событий, названия товаров) эмодзи держать может:
/// проверяются только надписи внутри нажимаемого.
void main() {
  setUp(rootBundle.clear);

  forEachWorld((WorldKind kind) {
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      for (final MapEntry<String, (Widget, World Function())> s
          in worldScreens(kind).entries) {
        testWidgets('${s.key} · ${o.key}: в кнопках нет эмодзи',
            (WidgetTester tester) async {
          await pumpListedScreen(tester, s.key, s.value, size: o.value);
          final Set<String> found = <String>{};
          for (final Element e in find
              .descendant(of: _tappable, matching: find.byType(RichText))
              .evaluate()) {
            final String t = (e.widget as RichText).text.toPlainText();
            if (t.contains(_emoji)) found.add(t);
          }
          expect(found, isEmpty, reason: 'эмодзи в нажимаемом: $found');
        });
      }
    }

    // Ловит: строку итогов или прогресса, собранную в коде, снова рисуют
    // `Text` с эмодзи («🏠 Финни живёт», «➡️ До переезда», «✅ итоги») —
    // так было до 28.09. Эти строки — не контент, значки в них вектором
    // (`PicText`).
    for (final (String screen, List<String> panels) in <(String, List<String>)>[
      (
        'S11 итоги · оплачено',
        <String>['review:bills_result', 'review:fact', 'review:growth']
      ),
      ('S12 прогресс', <String>['history:summary', 'history:week:1']),
    ]) {
      testWidgets('$screen: в строках итогов нет эмодзи',
          (WidgetTester tester) async {
        await pumpListedScreen(tester, screen, worldScreens(kind)[screen]!,
            size: portrait);
        final Set<String> found = <String>{};
        for (final String key in panels) {
          final Finder panel = find.byKey(ValueKey<String>(key));
          await tester.ensureVisible(panel);
          await tester.pump();
          for (final Element e in find
              .descendant(of: panel, matching: find.byType(RichText))
              .evaluate()) {
            final String t = (e.widget as RichText).text.toPlainText();
            if (t.contains(_emoji)) found.add(t);
          }
        }
        expect(found, isEmpty, reason: 'эмодзи в строках: $found');
      });
    }
  });
}
