import 'package:finlit/domain/world/contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';
import '../../support/world_screens.dart';

/// Кадры экранов 0.1.3 (перепроверка Саши, `sasha-a1-screens.md`), мир с
/// днями, как в релизе.
///
/// Защищает: при шрифте 1,3 текст, который ребёнок должен прочесть,
/// читается целиком — заголовок итогов недели без многоточия, причина на
/// карточке досуга не сжата кнопкой до трёх букв в строке; на зоомагазине
/// нет «Копилка копим в копилке»; «живёт в деревне» — со строчной.
/// Уронит: заголовок снова режется, причина снова слева от «Пойти», повтор
/// слова вернулся, «живёт: В деревне».
/// Почему не ловили: «влезает при шрифте 1,3» проверяют только отсутствие
/// исключений, а многоточие и узкая колонка исключения не дают.
final Map<String, (Widget, World Function())> _screens =
    worldScreens(dayWorldKind);

/// Текст абзаца обрезан: строки сверх `maxLines` или одна строка без
/// переноса уже своей длины (многоточие у края).
bool _cut(RenderParagraph p) =>
    p.didExceedMaxLines ||
    (!p.softWrap &&
        p.size.width + 0.5 < p.getMaxIntrinsicWidth(double.infinity));

void main() {
  for (final String name in <String>['S11 итоги', 'S11 итоги · оплачено']) {
    testWidgets('$name: портрет ×1,3 — заголовок «Итоги недели N» целиком',
        (WidgetTester tester) async {
      await pumpListedScreen(tester, name, _screens[name]!,
          size: portrait, textScale: 1.3);
      final Finder title = find.descendant(
          of: find.byType(AppBar),
          matching: find.textContaining('Итоги недели'));
      expect(title, findsOneWidget);
      final RenderParagraph p = tester.renderObject<RenderParagraph>(title);
      expect(_cut(p), isFalse,
          reason: 'ширина ${p.size.width.toStringAsFixed(1)} из '
              '${p.getMaxIntrinsicWidth(double.infinity).toStringAsFixed(1)}');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('S8 досуг: альбом ×1,3 — причина на всю ширину, не у кнопки',
      (WidgetTester tester) async {
    const String name = 'S8 досуг';
    await pumpListedScreen(tester, name, _screens[name]!,
        size: landscape, textScale: 1.3);
    expect(tester.takeException(), isNull);
    final Finder blocks = find.byWidgetPredicate((Widget x) =>
        x.key is ValueKey<String> &&
        (x.key! as ValueKey<String>).value.startsWith('leisure:block:'));
    expect(blocks, findsWidgets, reason: 'в мире есть закрытый вариант');
    for (final Element e in blocks.evaluate()) {
      final String id = (e.widget.key! as ValueKey<String>)
          .value
          .substring('leisure:block:'.length);
      final Rect card =
          tester.getRect(find.byKey(ValueKey<String>('leisure:card:$id')));
      final Rect block = tester.getRect(find.byWidget(e.widget));
      expect(block.width, greaterThanOrEqualTo(card.width * 0.8),
          reason: '$id: причина ${block.width.toStringAsFixed(0)} из '
              '${card.width.toStringAsFixed(0)} — её сжала кнопка');
      final Rect go =
          tester.getRect(find.byKey(ValueKey<String>('leisure:go:$id')));
      expect(go.top, greaterThanOrEqualTo(block.bottom - 0.5),
          reason: '$id: «Пойти» под причиной');
      expect(go.height, greaterThanOrEqualTo(48));
    }
  });

  // Вкладки магазина за правым краем: у ребёнка должен быть признак, что
  // ленту можно листать. Признак — пока справа есть ещё вкладки.
  testWidgets('S4 магазин: портрет ×1,3 — признак «ещё вкладки» у края',
      (WidgetTester tester) async {
    const String name = 'S4 магазин';
    await pumpListedScreen(tester, name, _screens[name]!,
        size: portrait, textScale: 1.3);
    final Finder more = find.byKey(const ValueKey<String>('shop:tabs:more'));
    expect(more, findsOneWidget, reason: 'вкладки за краем, признака нет');
    expect(tester.getRect(more).right, closeTo(portrait.width, 1));
    // Лента до конца — признак уходит.
    await tester.drag(
        find.byKey(const ValueKey<String>('tab:food')), const Offset(-2000, 0));
    await tester.pump(const Duration(milliseconds: 600));
    expect(more, findsNothing, reason: 'дальше вкладок нет');
  });

  testWidgets('S5 зоомагазин: без «Копилка копим в копилке»',
      (WidgetTester tester) async {
    const String name = 'S5 зоомагазин';
    await pumpListedScreen(tester, name, _screens[name]!, size: portrait);
    expect(find.text('Копилка'), findsWidgets, reason: 'метка «из копилки»');
    expect(find.textContaining('копим в копилке'), findsNothing);
  });

  // До оплаты блока «Звёзды» с этой строкой в итогах ещё нет.
  for (final String name in <String>['S11 итоги · оплачено', 'S12 прогресс']) {
    testWidgets('$name: «живёт в деревне» — со строчной, без двоеточия',
        (WidgetTester tester) async {
      await pumpListedScreen(tester, name, _screens[name]!, size: portrait);
      expect(find.textContaining('живёт в деревне', findRichText: true),
          findsOneWidget);
      expect(find.textContaining(RegExp('живёт: В'), findRichText: true),
          findsNothing);
    });
  }
}
