import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/home/room_screen.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/world_explain.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/tap_target_guideline.dart';
import '../../support/world_harness.dart';

/// Объяснения модели «7 дней» (Денис 17.10, `ekonomika-7-dnej-raskladka.md`
/// п. 3, 5, 6, 8): везение на смене, почему меняется настроение, как
/// считается опыт и сон. Всё — за флагом `day_cycle.explain_ui`.
String _read(String f) =>
    File('${WorldContentLoader.base}/$f').readAsStringSync();

/// `economy.json` сборки с подменённым `day_cycle.explain_ui`; `null` —
/// ключа нет вовсе.
WorldContent _economyWith({required bool? explainUi}) {
  final Map<String, Object?> eco =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  final Map<String, Object?> dc = <String, Object?>{
    ...(eco['day_cycle']! as Map<String, Object?>),
  };
  dc.remove('explain_ui');
  if (explainUi != null) dc['explain_ui'] = explainUi;
  eco['day_cycle'] = dc;
  return WorldContent.parse(
    economy: jsonEncode(eco),
    jobs: _read('jobs.json'),
    events: _read('events.json'),
  );
}

/// Мир дней сборки; [luck] — оставить в `day_cycle.shift_luck` только эти
/// сценарии и выпадать им всегда (chance 1): итог смены детерминирован.
WorldGame _dayWorld({List<String>? luck}) {
  final Map<String, Object?> eco =
      jsonDecode(_read('economy.json')) as Map<String, Object?>;
  final Map<String, Object?> dc = <String, Object?>{
    ...(eco['day_cycle']! as Map<String, Object?>),
  };
  if (luck != null) {
    final Map<String, Object?> sl = dc['shift_luck']! as Map<String, Object?>;
    dc['shift_luck'] = <String, Object?>{
      'chance': 1,
      'scenarios': <Object?>[
        for (final Object? s in sl['scenarios']! as List<Object?>)
          if (luck.contains((s! as Map<String, Object?>)['id'])) s,
      ],
    };
  }
  eco['day_cycle'] = dc;
  final WorldGame w = WorldGame(
      config: worldConfigFromContent(WorldContent.parse(
    economy: jsonEncode(eco),
    jobs: _read('jobs.json'),
    events: _read('events.json'),
  )));
  ok(w.startWeek());
  ok(w.plan(needs: 100, wants: 100, goal: 0));
  return w;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Кассир без ошибок: сдачу считаем по тексту покупки на экране
/// («Булочка стоит 7. Покупатель даёт 10.») и даём её крупными монетами.
/// Не по зашитым ответам: порядок покупателей зависит от раунда и контента
/// (в RC 17.10 он сменился, и тест играл чужие ответы).
Future<void> _playCashier(WidgetTester tester) async {
  await _tap(tester, 'job:start');
  for (int i = 0; i < 2; i++) {
    final String deal = _text(tester, 'cashier:purchase');
    final RegExpMatch m =
        RegExp(r'стоит (\d+)\. Покупатель даёт (\d+)').firstMatch(deal)!;
    int change = int.parse(m.group(2)!) - int.parse(m.group(1)!);
    for (final int c in <int>[10, 5, 2, 1]) {
      while (change >= c) {
        await _tap(tester, 'cashier:coin:$c');
        change -= c;
      }
    }
    await _tap(tester, 'cashier:give');
    await _tap(tester, 'cashier:next');
  }
}

String _text(WidgetTester tester, String key) => tester
    .widgetList<Text>(find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(Text),
        matchRoot: true))
    .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join(' ');

/// `luckPay` последней смены в журнале.
int _luckPay(WorldGame w) => w.journal
    .lastWhere((WorldEntry e) => e.kind == WorldLedgerKind.jobPayout)
    .args['luckPay']! as int;

/// Комната анимирована без конца: pumpAndSettle не дождётся — кадр и
/// время на переход диалога.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Кнопка [key] — не меньше 48×48 dp, у неё есть подпись для TalkBack
/// [label], касание открывает подсказку с [text]; «Понятно» её закрывает.
Future<void> _helpOpens(WidgetTester tester, String key,
    {required String label, required String text}) async {
  final Finder b = find.byKey(ValueKey<String>(key));
  expect(b, findsOneWidget, reason: key);
  await tester.ensureVisible(b);
  await _settle(tester);
  final Size sz = tester.getSize(b);
  expect(sz.width, greaterThanOrEqualTo(48), reason: '$key: ширина');
  expect(sz.height, greaterThanOrEqualTo(48), reason: '$key: высота');
  final SemanticsHandle h = tester.ensureSemantics();
  expect(
      tester.getSemantics(b).getSemanticsData().label +
          tester.getSemantics(b).getSemanticsData().tooltip,
      contains(label),
      reason: '$key: подпись TalkBack');
  h.dispose();
  await tester.tap(b);
  await _settle(tester);
  expect(find.textContaining(text), findsOneWidget, reason: '$key: текст');
  expect(tester.takeException(), isNull);
  await tester.tap(find.text('Понятно'));
  await _settle(tester);
}

void main() {
  // Защищает: флаг объяснений читается из json и в сборке включён; без
  // ключа — выключен (старые сохранения и ветки без флага не меняются).
  // Уронит: ключ не разобран (всегда по умолчанию), не тот ключ, флаг
  // выключен в сборке.
  group('флаг day_cycle.explain_ui', () {
    test('в сборке включён', () {
      expect(contentDayConfig.dayCycle.explainUi, isTrue);
    });

    test('читается из json: false и нет ключа — выключен, true — включён', () {
      expect(_economyWith(explainUi: true).economy.dayCycle.explainUi, isTrue);
      expect(
          _economyWith(explainUi: false).economy.dayCycle.explainUi, isFalse);
      expect(_economyWith(explainUi: null).economy.dayCycle.explainUi, isFalse);
    });

    // Ревью (17.10): выключает UI именно ключ в json, а не только
    // `WorldExplain.off` в тестах экранов. Уронит: `parse` не смотрит на
    // флаг (тексты есть при false) или смотрит не на тот.
    test('explain_ui: false в json — WorldExplain без текстов', () {
      final String file = _read('explain.json');
      WorldExplain of(bool? flag) => WorldExplain.parse(file,
          dayCycle: _economyWith(explainUi: flag).economy.dayCycle);
      expect(of(true).enabled, isTrue);
      expect(of(true).sleepShort, isNotNull);
      for (final bool? flag in <bool?>[false, null]) {
        final WorldExplain e = of(flag);
        expect(e.enabled, isFalse, reason: 'explain_ui: $flag');
        expect(e.sleepShort, isNull, reason: 'explain_ui: $flag');
        expect(e.sleepDetail, isNull, reason: 'explain_ui: $flag');
      }
    });
  });

  // Защищает: на итоге смены видно, что везение (домен: `job.payout.luck`)
  // изменило оплату, — строка «Сегодня повезло / Не повезло», подсказка
  // и монеты из журнала. Уронит: строка не выведена, перепутаны good/bad,
  // монеты не из `luckPay`, строка видна без флага, переполнение на 360 dp.
  group('итог смены: везение', () {
    for (final (String size, Size s) in <(String, Size)>[
      ('портрет 360×640', portrait),
      ('альбомная 640×360', landscape),
    ]) {
      testWidgets('повезло — строка, подсказка и +монеты · $size, шрифт 1,3',
          (WidgetTester tester) async {
        final WorldGame w = _dayWorld(luck: <String>['cashier_good_exact']);
        await pumpWorldScreen(
            tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
            world: w, size: s, textScale: 1.3);
        await _playCashier(tester);
        final ShiftLuck sc = w.config.dayCycle.luck.single;
        expect(
            _text(tester, 'job:result:luck'),
            allOf(contains('Сегодня повезло: ${sc.text}'),
                contains('чуть больше за смену')));
        expect(_luckPay(w), greaterThan(0));
        expect(_text(tester, 'job:result:luck:pay'), '+${_luckPay(w)}');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('не повезло — «Не повезло: …» и −монеты',
        (WidgetTester tester) async {
      final WorldGame w = _dayWorld(luck: <String>['cashier_bad_till']);
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
          world: w, textScale: 1.3);
      await _playCashier(tester);
      expect(_text(tester, 'job:result:luck'),
          contains('Не повезло: Заедает касса'));
      expect(_luckPay(w), lessThan(0));
      expect(_text(tester, 'job:result:luck:pay'), '−${-_luckPay(w)}');
      expect(tester.takeException(), isNull);
    });

    testWidgets('флаг выключен — строки нет, хотя сценарий выпал',
        (WidgetTester tester) async {
      final WorldGame w = _dayWorld(luck: <String>['cashier_good_exact']);
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
          world: w, explain: WorldExplain.off);
      await _playCashier(tester);
      expect(_luckPay(w), greaterThan(0), reason: 'сценарий выпал');
      expect(
          find.byKey(const ValueKey<String>('job:result:luck')), findsNothing);
    });

    test('подсказка есть у каждого сценария домена и не врёт о знаке', () {
      final WorldExplain ex = explainFor(_dayWorld());
      final List<ShiftLuck> all = contentDayConfig.dayCycle.luck;
      expect(all, hasLength(35));
      for (final ShiftLuck l in all) {
        final String? h = ex.luckHints[l.id];
        expect(h, isNotNull, reason: 'нет подсказки для ${l.id}');
        if (l.payX > 1) expect(h, contains('больше'), reason: l.id);
        if (l.payX < 1) expect(h, contains('меньше'), reason: l.id);
        if (l.energyBack > 0) expect(h, contains('сил'), reason: l.id);
      }
      expect(ex.luckHints.keys.toSet(), all.map((ShiftLuck l) => l.id).toSet(),
          reason: 'лишних подсказок нет');
    });

    test('копия explain.json в сборке совпадает с content/', () {
      expect(_read('explain.json'),
          File('../../content/explain.json').readAsStringSync());
    });
  });

  // Защищает: у строки «Настроение» после смены — «?» с объяснением
  // mood_why (почему настроение то выше, то ниже), подпись для TalkBack.
  // Уронит: кнопки нет, нет подписи, цель меньше 48 dp, видна без флага.
  group('настроение после смены: «?»', () {
    testWidgets('«?» открывает mood_why · шрифт 1,3',
        (WidgetTester tester) async {
      final WorldGame w = _dayWorld(luck: <String>[]);
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
          world: w, textScale: 1.3);
      await _playCashier(tester);
      expect(find.byKey(const ValueKey<String>('job:result:happiness')),
          findsOneWidget);
      await _helpOpens(tester, 'job:result:moodWhy',
          label: 'Почему меняется настроение',
          text: heroText(explainFor(w).moodWhy!, w.onboarding.finniName));
    });

    testWidgets('флаг выключен — «?» нет', (WidgetTester tester) async {
      final WorldGame w = _dayWorld(luck: <String>[]);
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
          world: w, explain: WorldExplain.off);
      await _playCashier(tester);
      expect(find.byKey(const ValueKey<String>('job:result:moodWhy')),
          findsNothing);
    });
  });

  // Защищает: на карточке смены перед игрой — опыт одной строкой (xp_short)
  // и «Как это считается» с подробностями (xp_detail). Уронит: строки или
  // кнопки нет, цель меньше 48 dp, видно без флага, переполнение.
  group('карточка смены: опыт', () {
    for (final (String size, Size s) in <(String, Size)>[
      ('портрет 360×640', portrait),
      ('альбомная 640×360', landscape),
    ]) {
      testWidgets('xp_short и «Как это считается» · $size, шрифт 1,3',
          (WidgetTester tester) async {
        final WorldGame w = _dayWorld(luck: <String>[]);
        final WorldExplain ex = explainFor(w);
        await pumpWorldScreen(
            tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
            world: w, size: s, textScale: 1.3);
        expect(_text(tester, 'job:offer:xp'), contains(ex.xpShort!));
        expect(tester.takeException(), isNull);
        await _helpOpens(tester, 'job:offer:xpHow',
            label: 'Как это считается', text: ex.xpDetail!);
      });
    }

    testWidgets('флаг выключен — строки опыта нет',
        (WidgetTester tester) async {
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
          world: _dayWorld(luck: <String>[]), explain: WorldExplain.off);
      expect(find.byKey(const ValueKey<String>('job:offer:xp')), findsNothing);
      expect(
          find.byKey(const ValueKey<String>('job:offer:xpHow')), findsNothing);
    });
  });

  // Защищает: в диалоге «Спать» — как сон возвращает силы (sleep_short) и
  // «Подробнее» (sleep_detail), числа — из sleep_rule, а не из текста.
  // Уронит: строки нет, числа разошлись с таблицей сна, кнопка не
  // открывает подробности, видно без флага, сон перестал работать.
  group('диалог «Спать»: сон', () {
    Future<WorldGame> openSleep(WidgetTester tester,
        {WorldExplain? explain, double textScale = 1.3}) async {
      final WorldGame w = _dayWorld(luck: <String>[]);
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const RoomScreen(),
            world: w, explain: explain, textScale: textScale);
      });
      await tester.runAsync(() async {
        for (int i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await tester.pump();
        }
      });
      await tester.tap(find.byKey(const ValueKey<String>('room:bed')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('День закончится'), findsOneWidget);
      return w;
    }

    testWidgets('sleep_short с числами sleep_rule, «Подробнее», сон идёт',
        (WidgetTester tester) async {
      final WorldGame w = await openSleep(tester);
      final WorldExplain ex = explainFor(w);
      final SleepRule r = w.config.dayCycle.sleepRule!;
      expect(ex.sleepShort, contains('минимум до ${r.floor.round()}'));
      expect(ex.sleepShort, contains('не выше ${r.cap.round()}'));
      expect(ex.sleepDetail, contains('Больше ${r.cap.round()} не бывает'));
      expect(ex.sleepShort, isNot(contains('{')));
      expect(_text(tester, 'sleep:short'), contains(ex.sleepShort!));
      expect(tester.takeException(), isNull);
      await _helpOpens(tester, 'sleep:more',
          label: 'Подробнее', text: ex.sleepDetail!);
      // Подсказка закрылась — диалог сна на месте, сон работает как был.
      await tester.tap(find.byKey(const ValueKey<String>('sleep:confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(w.snapshot.dayInWeek, 2);
    });

    testWidgets('флаг выключен — строки сна нет', (WidgetTester tester) async {
      await openSleep(tester, explain: WorldExplain.off);
      expect(find.byKey(const ValueKey<String>('sleep:short')), findsNothing);
      expect(find.byKey(const ValueKey<String>('sleep:more')), findsNothing);
    });
  });

  // Защищает: новые кнопки и строки объяснений проходят те же правила
  // доступности, что остальные экраны (цели 48 dp, подписи у касаемого).
  // Контраст здесь не проверяется: textContrastGuideline на этих экранах
  // пропустил бледный текст (проверено мутацией 17.10). Общие тесты доступности гоняют режим «неделя», где
  // объяснений нет, поэтому здесь — дни. Уронит: кнопка без подписи, цель
  // меньше 48 dp.
  group('доступность объяснений', () {
    /// Правила проверяют только видимое: сначала прокрутить к [key].
    Future<void> guidelines(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(ValueKey<String>(key)));
      await tester.pumpAndSettle();
      final SemanticsHandle h = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(edgeTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      h.dispose();
    }

    testWidgets('карточка смены с опытом', (WidgetTester tester) async {
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
          world: _dayWorld(luck: <String>[]), textScale: 1.3);
      expect(find.byKey(const ValueKey<String>('job:offer:xpHow')),
          findsOneWidget);
      await guidelines(tester, 'job:offer:xpHow');
    });

    testWidgets('итог смены с везением и «?» настроения',
        (WidgetTester tester) async {
      await pumpWorldScreen(
          tester, const JobPlayScreen(args: JobPlayArgs('cashier')),
          world: _dayWorld(luck: <String>['cashier_bad_till']), textScale: 1.3);
      await _playCashier(tester);
      expect(find.byKey(const ValueKey<String>('job:result:luck')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('job:result:moodWhy')),
          findsOneWidget);
      await guidelines(tester, 'job:result:moodWhy');
    });
  });
}
