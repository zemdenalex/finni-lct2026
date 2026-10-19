import 'package:finlit/core/theme.dart';
import 'package:finlit/features/world/jobs/games/consultant_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/world_harness.dart';

/// Штраф консультанта и помощника бухгалтера (один движок): каждая ошибка
/// считается один раз за шаг. Уронит: «Проверить» после ошибки снова
/// прибавляет штраф за каждый неверный товар — пять нажатий без исправления
/// давали оценку 0 (pm и Денис 17.10: баг, не педагогика).
///
/// Правило: штраф = `shelf_penalty` × разных товаров, хоть раз проверенных не
/// на своей полке, + `pick_penalty` × разных неверных советов покупателю
/// (оба числа — `jobs.json`, NAS-7 А), оценка не ниже 0.
Future<void> _tap(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, ConsultantContent content,
    void Function(double) on) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConsultantGame(content: content, onDone: on),
      ),
    ),
  ));
}

class _Shelves {
  _Shelves(this.set)
      : cheap = set.items.firstWhere((ConsultantItem i) => set.tierOf(i) == 0),
        mid = set.items.firstWhere((ConsultantItem i) => set.tierOf(i) == 1),
        dear = set.items.firstWhere((ConsultantItem i) => set.tierOf(i) == 2);

  final ConsultantSet set;
  final ConsultantItem cheap;
  final ConsultantItem mid;
  final ConsultantItem dear;

  static String shelf(ConsultantItem i, int t) => 'consultant:shelf:${i.id}:$t';
  static String pick(ConsultantItem i) => 'consultant:pick:${i.id}';
}

/// Дешёвый и дорогой — на чужих полках (поменяны местами), средний — на своей.
Future<void> _swapped(WidgetTester tester, _Shelves s) async {
  await _tap(tester, _Shelves.shelf(s.cheap, 2));
  await _tap(tester, _Shelves.shelf(s.mid, 1));
  await _tap(tester, _Shelves.shelf(s.dear, 0));
}

Future<void> _scan(WidgetTester tester, {int times = 1}) async {
  for (int k = 0; k < times; k++) {
    await _tap(tester, 'consultant:scan');
  }
}

Future<void> _pickBestAndFinish(WidgetTester tester, _Shelves s) async {
  expect(
      find.byKey(const ValueKey<String>('consultant:customer')), findsOneWidget,
      reason: 'раскладка верна — шаг 2 открыт');
  await _tap(tester, _Shelves.pick(s.set.best));
  await _tap(tester, 'consultant:done');
}

void main() {
  final Map<String, ConsultantContent> engines = <String, ConsultantContent>{
    'консультант': contentJobGames.consultant,
    'бухгалтер': contentJobGames.accountant,
  };

  for (final MapEntry<String, ConsultantContent> e in engines.entries) {
    final String who = e.key;
    final ConsultantContent content = e.value;
    final _Shelves s = _Shelves(content.setFor(0));

    testWidgets(
        '$who: пять проверок без исправления — штраф за 2 товара один раз',
        (WidgetTester tester) async {
      double? score;
      await _pump(tester, content, (double v) => score = v);
      await _swapped(tester, s);
      await _scan(tester, times: 5);
      expect(find.byKey(ValueKey<String>('consultant:why:${s.cheap.id}')),
          findsOneWidget);
      expect(find.byKey(ValueKey<String>('consultant:why:${s.dear.id}')),
          findsOneWidget);
      await _tap(tester, _Shelves.shelf(s.cheap, 0));
      await _tap(tester, _Shelves.shelf(s.dear, 2));
      await _scan(tester);
      await _pickBestAndFinish(tester, s);
      expect(score, closeTo(1 - 2 * content.shelfPenalty, 1e-9));
    });

    testWidgets(
        '$who: исправил один — повторные проверки и снова испорченный '
        'товар штраф не растят', (WidgetTester tester) async {
      double? score;
      await _pump(tester, content, (double v) => score = v);
      await _swapped(tester, s);
      await _scan(tester);
      // Исправил дешёвый: остался один неверный, проверка его не удваивает.
      await _tap(tester, _Shelves.shelf(s.cheap, 0));
      await _scan(tester, times: 3);
      expect(find.byKey(ValueKey<String>('consultant:why:${s.cheap.id}')),
          findsNothing);
      expect(find.byKey(ValueKey<String>('consultant:why:${s.dear.id}')),
          findsOneWidget);
      // Испортил дешёвый снова (на другую чужую полку) — тот же товар.
      await _tap(tester, _Shelves.shelf(s.cheap, 1));
      await _scan(tester);
      await _tap(tester, _Shelves.shelf(s.cheap, 0));
      await _tap(tester, _Shelves.shelf(s.dear, 2));
      await _scan(tester);
      await _pickBestAndFinish(tester, s);
      expect(score, closeTo(1 - 2 * content.shelfPenalty, 1e-9));
    });

    testWidgets('$who: идеальная раскладка и верный совет — оценка 1',
        (WidgetTester tester) async {
      double? score;
      await _pump(tester, content, (double v) => score = v);
      await _tap(tester, _Shelves.shelf(s.cheap, 0));
      await _tap(tester, _Shelves.shelf(s.mid, 1));
      await _tap(tester, _Shelves.shelf(s.dear, 2));
      await _scan(tester);
      await _pickBestAndFinish(tester, s);
      expect(score, 1.0);
    });

    testWidgets('$who: один неверный совет, нажатый трижды, — одна ошибка',
        (WidgetTester tester) async {
      double? score;
      await _pump(tester, content, (double v) => score = v);
      await _tap(tester, _Shelves.shelf(s.cheap, 0));
      await _tap(tester, _Shelves.shelf(s.mid, 1));
      await _tap(tester, _Shelves.shelf(s.dear, 2));
      await _scan(tester);
      final ConsultantItem wrong =
          s.set.items.firstWhere((ConsultantItem i) => i.id != s.set.best.id);
      for (int k = 0; k < 3; k++) {
        await _tap(tester, _Shelves.pick(wrong));
      }
      await _pickBestAndFinish(tester, s);
      expect(score, closeTo(1 - content.pickPenalty, 1e-9));
    });
  }
}
