import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/job_play_screen.dart';
import 'package:finlit/features/world/pic_text.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_fonts.dart';
import '../../support/fake_world.dart';
import '../../support/world_harness.dart';

/// Мини-решение смены на экране (finni 17.10): вопрос «по пути» на карточке
/// смены, вариант начинает смену, ответ уходит в `completeJob(choice:)`, на
/// итоге — строка «Выбор: …».
///
/// Защищает: вопрос виден и отвечается; ответ доходит до мира (у движка —
/// монеты и запись журнала); число монет на кнопке равно тому, что мир
/// заплатил сверх смены без ответа; вопрос сменился — смена не уходит с
/// чужим ответом; 360×640 и альбомная при шрифте 1,3 без переполнения.
/// Уронит: вопрос не рисуется, `choice` не передаётся, кнопка считает
/// монеты иначе, чем мир, ответ берётся из кэша доски.

const ShiftChoice _gift = ShiftChoice(
  id: 'test_gift',
  work: 'dog_walker',
  question: 'Соседка просит выгулять и её собаку.',
  options: <ShiftChoiceOption>[
    ShiftChoiceOption(
        id: 'two',
        label: 'Взять вторую собаку',
        payX: 1.5,
        energy: 2,
        happiness: 1),
    ShiftChoiceOption(id: 'no', label: 'Отказаться'),
  ],
);

const ShiftChoice _hinted = ShiftChoice(
  id: 'test_hinted',
  work: 'dog_walker',
  question: 'Соседка просит выгулять и её собаку.',
  options: <ShiftChoiceOption>[
    ShiftChoiceOption(
        id: 'two',
        label: 'Взять вторую собаку',
        effectHint: 'больше монет, меньше сил',
        payX: 1.5,
        energy: 2),
    ShiftChoiceOption(id: 'no', label: 'Отказаться', effectHint: 'как обычно'),
  ],
);

const ShiftChoice _rain = ShiftChoice(
  id: 'test_rain',
  work: 'dog_walker',
  question: 'Начинается дождь.',
  options: <ShiftChoiceOption>[
    ShiftChoiceOption(id: 'finish', label: 'Доделать под дождём', payX: 1.1),
    ShiftChoiceOption(id: 'wait', label: 'Переждать и закончить меньше'),
  ],
);

JobOffer _withChoice(JobOffer o, ShiftChoice? q) => JobOffer(
      jobId: o.jobId,
      title: o.title,
      basePay: o.basePay,
      experiencePercent: o.experiencePercent,
      experienceCoins: o.experienceCoins,
      stageStep: o.stageStep,
      pay: o.pay,
      efficiencyBonusMax: o.efficiencyBonusMax,
      energyCost: o.energyCost,
      shiftsLeft: o.shiftsLeft,
      goodScoreMin: o.goodScoreMin,
      goodEnergyExtra: o.goodEnergyExtra,
      goodHappiness: o.goodHappiness,
      variant: o.variant,
      lockedReason: o.lockedReason,
      blockReason: o.blockReason,
      choice: q,
    );

/// Фейк, у выгульщика которого стоит вопрос [question]; запоминает, с каким
/// `choice` пришла смена. Эффекты варианта фейк, как и по контракту,
/// не считает.
class _AskingWorld extends FakeWorld {
  ShiftChoice? question = _gift;
  final List<String?> sent = <String?>[];

  @override
  JobOffer? offer(String jobId, {String? variant}) {
    final JobOffer? o = super.offer(jobId, variant: variant);
    return o == null || jobId != 'dog_walker' ? o : _withChoice(o, question);
  }

  @override
  List<JobOffer> get jobBoard => <JobOffer>[
        for (final JobOffer o in super.jobBoard)
          o.jobId == 'dog_walker' ? _withChoice(o, question) : o,
      ];

  @override
  WorldResult completeJob(String jobId,
      {String? variant, required double score, String? choice}) {
    sent.add(choice);
    return super
        .completeJob(jobId, variant: variant, score: score, choice: choice);
  }
}

_AskingWorld _askingWorld() {
  final _AskingWorld w = _AskingWorld();
  ok(w.startWeek());
  ok(w.plan(needs: 100, wants: 100, goal: 0));
  ok(w.demoUnlockAllJobs());
  return w;
}

const JobPlayArgs _dog = JobPlayArgs('dog_walker');

Future<void> _tap(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

String _texts(WidgetTester tester, String key) => <String>[
      for (final Text t in tester.widgetList<Text>(find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(Text),
          matchRoot: true)))
        t.data ?? t.textSpan?.toPlainText() ?? '',
    ].join(' ');

String _picText(WidgetTester tester, String key) => <String>[
      for (final PicText t in tester.widgetList<PicText>(find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(PicText))))
        t.text,
    ].join(' ');

/// Мир с днями из сборки, утро первого дня; открыты все работы. Выгульщику
/// (игра «Сделать») подбирается журнал, при котором у смены есть вопрос:
/// каждое касание питомца — новая запись журнала.
WorldGame _dayWorldWithQuestion() {
  for (int pets = 0; pets < 40; pets++) {
    final WorldGame w = contentDayWorld();
    ok(w.startWeek());
    ok(w.plan(needs: 0, wants: 0, goal: 0));
    if (w.pendingEvent case final PendingEvent e) {
      ok(w.resolveEvent(
          e.choices.firstWhere((PendingEventChoice c) => c.available).id));
    }
    ok(w.demoUnlockAllJobs());
    int written = 0;
    while (written < pets) {
      final int before = w.journal.length;
      w.depositToGoal(1);
      if (w.journal.length == before) break;
      written++;
    }
    if (written < pets) continue;
    final JobOffer? o = w.offer('dog_walker');
    if (o != null && o.blockReason == null && o.choice != null) return w;
  }
  fail('за 40 записей журнала у выгульщика ни разу не выпал вопрос');
}

/// Тот же путь, что [_dayWorldWithQuestion], — для сравнения оплаты.
WorldGame _twin(WorldGame w) {
  final WorldGame t = contentDayWorld();
  ok(t.startWeek());
  ok(t.plan(needs: 0, wants: 0, goal: 0));
  if (t.pendingEvent case final PendingEvent e) {
    ok(t.resolveEvent(
        e.choices.firstWhere((PendingEventChoice c) => c.available).id));
  }
  ok(t.demoUnlockAllJobs());
  while (t.journal.length < w.journal.length) {
    ok(t.depositToGoal(1));
  }
  expect(t.offer('dog_walker')?.choice?.id, w.offer('dog_walker')?.choice?.id);
  return t;
}

void main() {
  // Шрифт приложения: проверки «влезает ли» на подстановочном шрифте теста
  // (квадраты шире букв) ничего не говорят о телефоне.
  setUpAll(loadAppFonts);

  group('FakeWorld с вопросом', () {
    testWidgets('вопрос вместо «Начать смену», вариант уходит в completeJob',
        (WidgetTester tester) async {
      final _AskingWorld w = _askingWorld();
      await pumpWorldScreen(tester, const JobPlayScreen(args: _dog),
          world: w, games: contentJobGamesDogStub);
      expect(find.byKey(const ValueKey<String>('job:choice')), findsOneWidget);
      expect(_texts(tester, 'job:choice:question'), _gift.question);
      expect(find.byKey(const ValueKey<String>('job:start')), findsNothing,
          reason: 'вариант и есть начало смены');
      // Последствия значками; без них — только подпись.
      expect(_picText(tester, 'job:choice:two'), contains('−2 ⚡'));
      expect(_picText(tester, 'job:choice:two'), contains('+1 😊'));
      expect(_picText(tester, 'job:choice:two'), contains('💰'));
      expect(_picText(tester, 'job:choice:no'), isEmpty);
      // TalkBack: словами, «силы» (правило 4А).
      final String said = tester
          .getSemantics(find.byKey(const ValueKey<String>('job:choice:two')))
          .label;
      expect(said, startsWith('Взять вторую собаку.'));
      expect(said, contains('силы −2'));
      expect(said, contains('настроение +1'));
      expect(said, contains('Монеты +'));
      expect(said, isNot(contains('⚡')));

      await _tap(tester, 'job:choice:two');
      await _tap(tester, 'game:placeholder:do');
      expect(w.sent, <String?>['two']);
      expect(_texts(tester, 'job:result:choice'),
          contains('Выбор: Взять вторую собаку'));
    });

    testWidgets('без вопроса — как раньше: «Начать смену», choice null',
        (WidgetTester tester) async {
      final _AskingWorld w = _askingWorld()..question = null;
      await pumpWorldScreen(tester, const JobPlayScreen(args: _dog),
          world: w, games: contentJobGamesDogStub);
      expect(find.byKey(const ValueKey<String>('job:choice')), findsNothing);
      await _tap(tester, 'job:start');
      await _tap(tester, 'game:placeholder:do');
      expect(w.sent, <String?>[null]);
      expect(find.byKey(const ValueKey<String>('job:result:choice')),
          findsNothing);
    });

    testWidgets('вопрос сменился до нажатия — смена не начинается, новый виден',
        (WidgetTester tester) async {
      final _AskingWorld w = _askingWorld();
      await pumpWorldScreen(tester, const JobPlayScreen(args: _dog),
          world: w, games: contentJobGamesDogStub);
      // Мир сменил вопрос без перерисовки (как запись журнала из другого
      // места): кнопка старого вопроса ещё на экране.
      w.question = _rain;
      await _tap(tester, 'job:choice:two');
      expect(find.byKey(const ValueKey<String>('game:placeholder:do')),
          findsNothing);
      expect(_texts(tester, 'job:choice:question'), _rain.question);
      expect(_texts(tester, 'job:choice:changed'), 'Вопрос изменился');
      expect(w.sent, isEmpty);
    });

    // Ревью (17.10): подсказка словами не заменяет
    // числа — на кнопке и то и другое, TalkBack читает подпись, слова и
    // последствия словами. Уронит: подсказка снова вместо значков или
    // TalkBack без чисел.
    testWidgets('подсказка словами и значки вместе; TalkBack — всё словами',
        (WidgetTester tester) async {
      final _AskingWorld w = _askingWorld()..question = _hinted;
      await pumpWorldScreen(tester, const JobPlayScreen(args: _dog),
          world: w, games: contentJobGamesDogStub);
      expect(
          tester
              .widget<Text>(find.descendant(
                  of: find.byKey(const ValueKey<String>('job:choice:two')),
                  matching:
                      find.byKey(const ValueKey<String>('job:choice:hint'))))
              .data,
          'больше монет, меньше сил');
      expect(_picText(tester, 'job:choice:two'), contains('−2 ⚡'));
      final String said = tester
          .getSemantics(find.byKey(const ValueKey<String>('job:choice:two')))
          .label;
      expect(
          said, startsWith('Взять вторую собаку. больше монет, меньше сил.'));
      expect(said, contains('силы −2'));
      expect(said, isNot(contains('⚡')));
    });

    testWidgets('вопрос сменился во время игры — смена без ответа, без отказа',
        (WidgetTester tester) async {
      final _AskingWorld w = _askingWorld();
      await pumpWorldScreen(tester, const JobPlayScreen(args: _dog),
          world: w, games: contentJobGamesDogStub);
      await _tap(tester, 'job:choice:two');
      w.question = _rain;
      await _tap(tester, 'game:placeholder:do');
      expect(w.sent, <String?>[null]);
      expect(find.byKey(const ValueKey<String>('job:result:title')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('job:result:choice')),
          findsNothing);
    });

    for (final MapEntry<String, Size> s in bothOrientations.entries) {
      testWidgets('${s.key}, шрифт 1,3: без переполнения, цели ≥ 48 dp',
          (WidgetTester tester) async {
        final SemanticsHandle h = tester.ensureSemantics();
        final _AskingWorld w = _askingWorld()..question = _rain;
        await pumpWorldScreen(tester, const JobPlayScreen(args: _dog),
            world: w,
            size: s.value,
            textScale: 1.3,
            games: contentJobGamesDogStub);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey<String>('job:choice:wait')),
            findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        for (final String id in <String>['finish', 'wait']) {
          expect(
              tester
                  .getSize(find.byKey(ValueKey<String>('job:choice:$id')))
                  .height,
              greaterThanOrEqualTo(48));
        }
        await _tap(tester, 'job:choice:finish');
        await _tap(tester, 'game:placeholder:do');
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey<String>('job:result:choice')),
            findsOneWidget);
        h.dispose();
      });
    }
  });

  testWidgets(
      'альбомная 640×360, шрифт 1,3: каждый из 21 вопроса сборки и его '
      'варианты видны без прокрутки', (WidgetTester tester) async {
    // Альбомная — основная ориентация; прежняя «Начать смену» была видна
    // сразу, варианты вместо неё — тоже.
    final List<ShiftChoice> all = contentDayConfig.dayCycle.shiftChoices;
    expect(all, hasLength(28));
    final List<String> hidden = <String>[];
    for (final ShiftChoice q in all) {
      final _AskingWorld w = _askingWorld()..question = q;
      await pumpWorldScreen(tester, const JobPlayScreen(args: _dog),
          world: w,
          size: landscape,
          textScale: 1.3,
          games: contentJobGamesDogStub);
      await tester.pumpAndSettle();
      for (final String key in <String>[
        'job:choice:question',
        for (final ShiftChoiceOption o in q.options) 'job:choice:${o.id}',
      ]) {
        final double bottom =
            tester.getRect(find.byKey(ValueKey<String>(key))).bottom;
        if (bottom > landscape.height) hidden.add('${q.id} $key: $bottom');
      }
    }
    expect(hidden, isEmpty);
  });

  group('WorldGame, режим дней', () {
    testWidgets(
        'монеты на кнопке = сколько мир доплатил; ответ в журнале смены',
        (WidgetTester tester) async {
      final WorldGame w = _dayWorldWithQuestion();
      final WorldGame plain = _twin(w);
      final ShiftChoice q = w.offer('dog_walker')!.choice!;
      // Вариант с монетами, если есть, иначе первый.
      final ShiftChoiceOption opt = q.options.firstWhere(
          (ShiftChoiceOption o) => o.payX != 1,
          orElse: () => q.options.first);

      await pumpWorldScreen(tester, const JobPlayScreen(args: _dog),
          world: w, games: contentJobGamesDogStub);
      expect(_texts(tester, 'job:choice:question'), q.question);
      final String shown = _picText(tester, 'job:choice:${opt.id}');

      await _tap(tester, 'job:choice:${opt.id}');
      await _tap(tester, 'game:placeholder:do');

      final WorldEntry payout = w.journal
          .lastWhere((WorldEntry e) => e.kind == WorldLedgerKind.jobPayout);
      expect(payout.args['choice'], q.id);
      expect(payout.args['choiceOption'], opt.id);

      // Тот же путь без ответа: разница оплат — это и есть вклад варианта.
      ok(plain.completeJob('dog_walker', score: 1));
      final WorldEntry payout0 = plain.journal
          .lastWhere((WorldEntry e) => e.kind == WorldLedgerKind.jobPayout);
      expect(payout0.args.containsKey('choice'), isFalse);
      final int delta = payout.free - payout0.free;
      // У каждого вопроса выгульщика есть вариант с pay_x ≠ 1.
      expect(opt.payX, isNot(1));
      expect(delta, isNonZero);
      final String sign = delta > 0 ? '+' : '−';
      expect(shown, contains('$sign${delta.abs()} 💰'));
      expect(_texts(tester, 'job:result:choice:pay'), '$sign${delta.abs()}');
      expect(
          _texts(tester, 'job:result:choice'), contains('Выбор: ${opt.label}'));
    });
  });
}
