import 'package:finlit/core/theme.dart';
import 'package:finlit/domain/phrases.dart';
import 'package:finlit/domain/world/lesson_rules.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/jobs/games/consultant_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// «N монет» со склонением (кадры релиза 0.1.2+3, night4 #1): «24 монет» у
/// консультанта и «Копилка: 244 монет» для TalkBack — должно быть «24
/// монеты», «244 монеты». Правило Насти: слово «монеты», не «монетки».
///
/// Защищает: число и слово согласованы там, где число подставляется в
/// строку. Уронит: снова «$n монет» без [Phrases.coinsNom].
/// Почему не ловили: тесты сверяли число (`contains('${s.saved}')`), а не
/// слово рядом с ним.

/// Число, у которого «монет» — ошибка (1, 2–4 и 21–24, но не 11–14).
bool _needsOtherForm(int n) => Phrases.coinsNom(n) != 'монет';

/// Метка начинается ровно с [s] (дальше — конец или текст детей с новой строки).
RegExp _starts(String s) => RegExp('^${RegExp.escape(s)}(\\n|\$)');

void main() {
  test('урок: «{goal} монет» — со склонением по числу, которое спишет мир', () {
    const String finni = '{goal} монет уже в копилке, до пенала ближе.';
    for (final (int n, String want) in <(int, String)>[
      (24, '24 монеты уже в копилке, до пенала ближе.'),
      (21, '21 монета уже в копилке, до пенала ближе.'),
      (12, '12 монет уже в копилке, до пенала ближе.'),
      (30, '30 монет уже в копилке, до пенала ближе.'),
    ]) {
      final LessonMove m =
          (toGoal: n, toNeed: 0, fromFree: 0, fromWant: 0, block: null);
      expect(lessonText(finni, m, pay: 100), want);
    }
  });

  testWidgets('консультант: товар для TalkBack — «24 монеты», не «24 монет»',
      (WidgetTester tester) async {
    final ConsultantContent content = contentJobGames.consultant;
    // Раунд, где в выборе есть цена с формой «монета/монеты».
    int round = -1;
    for (int r = 0; r < 40 && round < 0; r++) {
      if (content
          .setFor(r)
          .items
          .any((ConsultantItem i) => _needsOtherForm(i.price))) {
        round = r;
      }
    }
    expect(round, greaterThanOrEqualTo(0),
        reason: 'в контенте нет цены 1–4 / 21–24 — тест ничего не проверит');
    final ConsultantSet set = content.setFor(round);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConsultantGame(
              content: content, round: round, onDone: (double _) {}),
        ),
      ),
    ));
    // Шаг 1 верно: каждый товар на своей полке, «Проверить» — открыт выбор.
    for (final ConsultantItem i in set.items) {
      final Finder f = find
          .byKey(ValueKey<String>('consultant:shelf:${i.id}:${set.tierOf(i)}'));
      if (f.evaluate().isEmpty) continue;
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }
    final Finder scan = find.byKey(const ValueKey<String>('consultant:scan'));
    await tester.ensureVisible(scan);
    await tester.pumpAndSettle();
    await tester.tap(scan);
    await tester.pumpAndSettle();
    int checked = 0;
    for (final ConsultantItem i in set.items) {
      if (find
          .byKey(ValueKey<String>('consultant:pick:${i.id}'))
          .evaluate()
          .isEmpty) {
        continue;
      }
      expect(
          find.bySemanticsLabel(_starts(
              '${i.name}, ${i.price} ${Phrases.coinsNom(i.price)}. Выбрать')),
          findsOneWidget,
          reason: '${i.name}: ${i.price}');
      if (_needsOtherForm(i.price)) checked++;
    }
    expect(checked, greaterThan(0), reason: 'цена 1–4 / 21–24 не на экране');
    h.dispose();
  });

  testWidgets('копилка в комнате для TalkBack: «Копилка: 22 монеты»',
      (WidgetTester tester) async {
    final WorldGame w = contentDayWorld();
    ok(w.startWeek());
    ok(w.demoGiveCoins(1000));
    final int now = w.snapshot.saved;
    // Довести копилку до числа с формой «монеты».
    int add = 22 - now % 100;
    if (add <= 0) add += 100;
    ok(w.depositToGoal(add));
    final int saved = w.snapshot.saved;
    expect(_needsOtherForm(saved), isTrue, reason: '$saved');
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.runAsync(() async {
      await pumpWorldScreen(tester, const RoomScreen(), world: w);
      for (int i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump();
      }
    });
    await tester.pump();
    final Finder piggy = find.bySemanticsLabel(RegExp(r'^Копилка: \d+ монет'));
    expect(piggy, findsOneWidget,
        reason: 'зона копилки в комнате с подписью для TalkBack');
    expect(
        find.bySemanticsLabel(
            _starts('Копилка: $saved ${Phrases.coinsNom(saved)}')),
        findsOneWidget);
    h.dispose();
  });
}
