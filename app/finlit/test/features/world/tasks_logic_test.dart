import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/games/cashier_game.dart';
import 'package:finlit/features/world/jobs/games/consultant_game.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/pic_text.dart';
import 'package:finlit/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Логика заданий (эксперт 16.10 [02:19–03:09]: «не хотим, чтобы ребёнок
/// играл в угадайку»; разбор `docs/final/zadaniya-logika-i-slozhnost.md` §3).
/// Каждый тест — дефект, где ответ не следовал из условия или текст врал.
void main() {
  final List<ConsultantSet> allSets = <ConsultantSet>[
    ...contentJobGames.consultant.sets,
    ...contentJobGames.accountant.sets,
  ];

  // Уронит: «Наушники 1 / 2 / 3» — номер в названии подсказывает порядок
  // цены (или путает), а не свойства товара.
  test('шаг 1: в названиях товаров нет номеров', () {
    for (final ConsultantSet s in allSets) {
      for (final ConsultantItem i in s.items) {
        expect(i.name, isNot(matches(RegExp(r'\d\s*$'))),
            reason: '${s.id}: ${i.name}');
      }
    }
  });

  // Уронит: в наборах, где порядок цены не следовал из свойств (металл
  // против пластика, «25 часов» против «провода»), следующий товар снова не
  // содержит всё, что есть у предыдущего.
  for (final String id in <String>['headphones', 'bottles']) {
    test('шаг 1 «$id»: лесенка — у дорогого свойств больше', () {
      final ConsultantSet s =
          allSets.firstWhere((ConsultantSet x) => x.id == id);
      final List<ConsultantItem> byPrice = <ConsultantItem>[...s.items]
        ..sort((ConsultantItem a, ConsultantItem b) => a.price - b.price);
      for (int k = 1; k < byPrice.length; k++) {
        expect(
            byPrice[k].traits.length, greaterThan(byPrice[k - 1].traits.length),
            reason: '${byPrice[k].name}: свойств больше');
      }
    });
  }

  // Уронит: до сканера все цены скрыты — раскладка «от дешёвого к дорогому»
  // превращается в угадайку. Минимум: один ценник-якорь (средний товар).
  testWidgets('шаг 1: до сканера виден один ценник — у среднего товара',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ConsultantSet set = contentJobGames.consultant.setFor(0);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ConsultantGame(
              content: contentJobGames.consultant, onDone: (double _) {}),
        ),
      ),
    ));
    final List<String> shown = tester
        .widgetList<PicText>(find.byType(PicText))
        .map((PicText p) => p.text)
        .where((String t) => t.startsWith('💰'))
        .toList();
    final ConsultantItem mid =
        set.items.firstWhere((ConsultantItem i) => set.tierOf(i) == 1);
    expect(shown.where((String t) => t == '💰 ?'),
        hasLength(set.items.length - 1));
    expect(shown, contains('💰 ${mid.price}'));
  });

  // Уронит: после неудачной смены следующая даёт тот же набор (раунд считался
  // по хорошим сменам) — ребёнок угадывает по памяти, а не по условию. И
  // NAS-7 А (Настя 18.10): раунд по общему счёту смен — на ступени из двух
  // наборов «консультант → садовник → консультант» снова давал тот же набор.
  test('следующая смена той же работы — другой набор, и через другие работы',
      () {
    final WorldGame w = contentWorld();
    ok(w.startWeek());
    ok(w.plan(needs: 0, wants: 0, goal: 0));
    final int r0 = JobPlayScreen.roundFor(w.snapshot, 'consultant');
    ok(w.completeJob('consultant', score: 0));
    final int r1 = JobPlayScreen.roundFor(w.snapshot, 'consultant');
    expect(contentJobGames.consultant.setFor(r1).id,
        isNot(contentJobGames.consultant.setFor(r0).id));

    final ConsultantContent two = contentJobGames.forStage(2).consultant;
    expect(two.sets, hasLength(2), reason: 'случай, где общий счёт ломался');
    ok(w.completeJob('consultant', score: 0));
    ok(w.completeJob('gardener', score: 1));
    final int r2 = JobPlayScreen.roundFor(w.snapshot, 'consultant');
    expect(two.setFor(r2).id, isNot(two.setFor(r1).id),
        reason: 'раунды $r1 и $r2');
  });

  // Уронит: первая смена кассира снова начинается со сдачи с 50 (50 − 12);
  // самые трудные покупки (с сотни) — не в конце списка. С C3 (20 покупок)
  // сдача с сотни — последний блок, а не последние две покупки.
  test('кассир: первая смена — сдача с 10, сдача с 100 — в конце', () {
    final CashierContent c = contentJobGames.cashier;
    for (final CashierPurchase p in c.purchasesFor(0)) {
      expect(p.paidWith, 10, reason: '${p.item}: на входе только «до 10»');
    }
    final int first =
        c.purchases.indexWhere((CashierPurchase p) => p.paidWith == 100);
    expect(first, greaterThan(0), reason: 'сдача с сотни есть');
    for (int i = first; i < c.purchases.length; i++) {
      expect(c.purchases[i].paidWith, 100,
          reason: '${c.purchases[i].item}: после первой сотни — только сотни');
    }
    expect(c.purchases.last.paidWith, 100);
  });

  // Уронит: кнопка урока говорит «треть», а откладывается 0,3 (с 180 — 50,
  // а не 60); или «пятая часть» / «десятая» с другим числом.
  test('уроки: доля на кнопке совпадает с числом', () {
    const Map<String, double> words = <String, double>{
      'десятую': 0.1,
      'пятую': 0.2,
      'треть': 1 / 3,
      'половину': 0.5,
    };
    for (final WorldLesson l in contentConfig.lessons) {
      for (final WorldLessonChoice ch in l.choices) {
        for (final MapEntry<String, double> e in words.entries) {
          if (!ch.label.toLowerCase().contains(e.key)) continue;
          final double share = ch.goalShare > 0 ? ch.goalShare : ch.needShare;
          expect(share, closeTo(e.value, 0.01),
              reason: '${l.jobId}: «${ch.label}»');
        }
      }
    }
  });
}
