import 'package:finlit/core/theme.dart';
import 'package:finlit/features/world/jobs/games/cashier_game.dart';
import 'package:finlit/features/world/jobs/games/consultant_game.dart';
import 'package:finlit/features/world/pic_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/world_harness.dart';

/// Ответы Насти 18.10 по заданиям мини-игр (NAS-1…NAS-7,
/// `docs/final/nas-games.md`). Каждый тест — её решение, которое код
/// нарушал на `trial/rc-7d`.
Future<void> _host(WidgetTester tester, Widget game) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body:
          SingleChildScrollView(padding: const EdgeInsets.all(16), child: game),
    ),
  ));
}

Future<void> _tap(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

List<String> _prices(WidgetTester tester) => tester
    .widgetList<PicText>(find.byType(PicText))
    .map((PicText p) => p.text)
    .where((String t) => t.startsWith('💰'))
    .toList();

String _cashierFeedback(WidgetTester tester) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(const ValueKey<String>('cashier:feedback')),
        matching: find.byType(Text)))
    .data!;

void main() {
  final Map<String, ConsultantContent> engines = <String, ConsultantContent>{
    'консультант': contentJobGames.consultant,
    'бухгалтер': contentJobGames.accountant,
  };

  for (final MapEntry<String, ConsultantContent> e in engines.entries) {
    // NAS-1 А. Уронит: ценник-якорь снова на каждой смене — после первой
    // смены раскладка остаётся «сравни с подписанной ценой», а не рассуждение.
    testWidgets('NAS-1 ${e.key}: со второй смены профессии якоря нет',
        (WidgetTester tester) async {
      await _host(tester,
          ConsultantGame(content: e.value, round: 1, onDone: (double _) {}));
      final List<String> shown = _prices(tester);
      expect(shown, hasLength(3));
      expect(shown, everyElement('💰 ?'),
          reason: 'до сканера цены скрыты: якорь только на первой смене');
    });

    // NAS-7 А. Уронит: за неверную полку снова −0,25 — две ошибки раскладки
    // (ответ и так показан после проверки) роняют смену до 0,5.
    testWidgets('NAS-7 ${e.key}: две неверные полки — штраф мягче 0,25',
        (WidgetTester tester) async {
      double? score;
      await _host(tester,
          ConsultantGame(content: e.value, onDone: (double v) => score = v));
      final ConsultantSet s = e.value.setFor(0);
      ConsultantItem at(int t) =>
          s.items.firstWhere((ConsultantItem i) => s.tierOf(i) == t);
      String shelf(ConsultantItem i, int t) => 'consultant:shelf:${i.id}:$t';
      await _tap(tester, shelf(at(0), 2));
      await _tap(tester, shelf(at(1), 1));
      await _tap(tester, shelf(at(2), 0));
      await _tap(tester, 'consultant:scan');
      await _tap(tester, shelf(at(0), 0));
      await _tap(tester, shelf(at(2), 2));
      await _tap(tester, 'consultant:scan');
      await _tap(tester, 'consultant:pick:${s.best.id}');
      await _tap(tester, 'consultant:done');
      expect(score, greaterThan(0.5));
      expect(e.value.shelfPenalty, lessThan(e.value.pickPenalty),
          reason: 'полка мягче неверного совета');
    });

    // NAS-6 Б. Уронит: отзыв называет цену (второй якорь), растёт до
    // нескольких предложений, обращается с родом («купила») или появляется
    // не только в первых двух наборах.
    test(
        'NAS-6 ${e.key}: отзывы — у всех товаров первых двух наборов, '
        'коротко, без цен и рода', () {
      final RegExp past = RegExp(r'[аеиоуыяю]л(а|и|ся|ась)?(?![А-Яа-яЁё])',
          caseSensitive: false);
      for (int k = 0; k < e.value.sets.length; k++) {
        for (final ConsultantItem i in e.value.sets[k].items) {
          final String? r = i.review;
          if (k >= 2) {
            expect(r, isNull, reason: '${i.id}: отзывы только в наборах 1–2');
            continue;
          }
          expect(r, isNotNull, reason: i.id);
          expect(r!.length, lessThanOrEqualTo(90), reason: r);
          expect(r, isNot(matches(RegExp(r'\d'))), reason: 'без цены: $r');
          expect(r, isNot(matches(RegExp(r'[.!?…].'))),
              reason: 'одно предложение: $r');
          expect(r, isNot(contains('«')), reason: r);
          expect(past.hasMatch(r), isFalse, reason: 'без рода: $r');
        }
      }
    });
  }

  // NAS-6 Б. Уронит: у первых двух наборов нет отзывов — шаг 1 снова без
  // второго источника подсказки, кроме одного ценника.
  testWidgets('NAS-6: отзывы видны на шаге 1 первого набора',
      (WidgetTester tester) async {
    final List<Object?> sets =
        shippedContent.jobData['consultant']!['sets']! as List<Object?>;
    final List<Object?> items =
        (sets.first! as Map<String, Object?>)['items']! as List<Object?>;
    final List<String> reviews = <String>[
      for (final Object? i in items)
        ((i! as Map<String, Object?>)['review'] as String?) ?? '',
    ];
    expect(reviews, everyElement(isNotEmpty));
    await _host(
        tester,
        ConsultantGame(
            content: contentJobGames.consultant, onDone: (double _) {}));
    for (final String r in reviews) {
      expect(find.textContaining(r), findsOneWidget, reason: r);
    }
  });

  testWidgets('NAS-6: в третьем наборе отзывов нет',
      (WidgetTester tester) async {
    await _host(
        tester,
        ConsultantGame(
            content: contentJobGames.consultant,
            round: 2,
            onDone: (double _) {}));
    expect(find.textContaining('Отзыв:'), findsNothing);
  });

  group('кассир', () {
    final CashierContent c = contentJobGames.cashier;
    final CashierPurchase p = c.purchasesFor(0).first;

    // NAS-2 А. Уронит: подсказка снова учит вычитать («из того, что дали,
    // вычти цену») — Настя выбрала «досчитай от цены до купюры».
    test('NAS-2: «Как играть» учит досчитывать вверх, не вычитать', () {
      expect(cashierHelp, isNot(contains('вычт')));
      expect(cashierHelp, contains('от цены'));
    });

    // NAS-2 А + NAS-3 A (Настя 19.10, «Оставить»). Уронит: после первой
    // ошибки снова только «посчитай ещё раз» без недостачи (её В от 18.10),
    // или расчёт с готовым ответом вычитанием («10 − 9 = 1»).
    testWidgets(
        'NAS-3: уже первая ошибка показывает, на сколько; счёт вверх с '
        'суммой ребёнка; верный ответ — «цена + сдача = купюра»',
        (WidgetTester tester) async {
      await _host(tester, CashierGame(content: c, onDone: (double _) {}));
      final int wrong = c.coins.firstWhere((int x) => x > p.change);
      await _tap(tester, 'cashier:coin:$wrong');
      await _tap(tester, 'cashier:give');
      final String first = _cashierFeedback(tester);
      expect(first, contains('лишнее: ${wrong - p.change}'),
          reason: 'первая ошибка: видно, на сколько');
      expect(first,
          contains('${p.price} + $wrong = ${p.price + wrong}, а покупатель'),
          reason: 'счёт вверх с суммой ребёнка, не готовая сдача');
      expect(first, isNot(contains('−')));

      await _tap(tester, 'cashier:undo');
      await _tap(tester, 'cashier:coin:${p.change}');
      await _tap(tester, 'cashier:give');
      final String right = _cashierFeedback(tester);
      expect(right, contains('${p.price} + ${p.change} = ${p.paidWith}'));
      expect(right, isNot(contains('−')));
    });
  });

  // NAS-4 А. Уронит: первой на доске снова финансовая работа с арифметикой.
  test('NAS-4: садовник первым на доске работ (неделя и дни)', () {
    expect(contentWorld().jobBoard.first.jobId, 'gardener');
    expect(contentDayWorld().jobBoard.first.jobId, 'gardener');
  });
}
