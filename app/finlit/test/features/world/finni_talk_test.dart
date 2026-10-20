import 'package:finlit/features/world/home/finni_talk.dart';
import 'package:flutter_test/flutter_test.dart';

/// Денис 20.10: Финни — друг, по касанию говорит с игроком. Защищает набор
/// реплик: 12–16 штук, без слов питомца, без рода в словах Финни о себе,
/// с ником, без повтора подряд. Уронит: в набор вернулось «мурлычет» или
/// «рад/рада», реплика без ника, выборка дала одну фразу два раза подряд.
void main() {
  final List<String> all = <String>[
    for (final List<String> l in finniTalkLines.values) ...l,
  ];

  test('12–16 реплик, у каждой ник, без питомца и без рода', () {
    expect(all.length, inInclusiveRange(12, 16));
    for (final String l in all) {
      expect(l, contains('{nick}'), reason: l);
      expect(l, isNot(matches(RegExp('мурл|глад|мур-', caseSensitive: false))),
          reason: l);
      // «рад(а)», «устал(а)», «поел(а)» — род Финни; ребёнок любого пола.
      expect(
          l,
          isNot(matches(RegExp(
              r'(?<![а-яё])(рад|рада|устал|устала|поел|поела)(?![а-яё])',
              caseSensitive: false))),
          reason: l);
      expect(l, isNot(contains('%')), reason: l);
    }
  });

  test('подряд разные реплики, ник подставлен, цель — только когда есть', () {
    final List<TalkSituation> sits = <TalkSituation>[
      TalkSituation.goal,
      TalkSituation.any,
    ];
    String? last;
    for (int n = 0; n < 40; n++) {
      final String l = finniTalkLine(
          situations: sits,
          n: n,
          nick: 'Ася',
          goalTitle: 'Велосипед',
          goalLeft: 300,
          last: last);
      expect(l, isNot(last));
      expect(l, contains('Ася'));
      expect(l, isNot(contains('{')));
      last = l;
    }
    // Одна реплика в выборке и она же была — без зацикливания.
    final String only = finniTalkLine(
        situations: <TalkSituation>[TalkSituation.hungry],
        n: 0,
        nick: 'Ася',
        last: null);
    expect(
        finniTalkLine(
            situations: <TalkSituation>[TalkSituation.hungry],
            n: 1,
            nick: 'Ася',
            last: only),
        only);
    // Без цели реплики о цели не попадают даже при TalkSituation.goal.
    for (int n = 0; n < 10; n++) {
      expect(finniTalkLine(situations: sits, n: n, nick: 'Ася'),
          isNot(contains('цел')));
    }
  });
}
