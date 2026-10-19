import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/games/gardener_game.dart'
    show gardenerSummary;
import 'package:finlit/features/world/review/week_review_screen.dart'
    show eatenAtHomeText, sleptText;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Правило 5Б Насти (18.10): фразы о герое — в роде, выбранном в знакомстве
/// («две версии каждой такой строки»); пол не выбран — фраза без рода, как
/// по 5А.
///
/// Защищает: событие из `events.json` (`situation_boy` / `situation_girl`)
/// и строки домена и экранов выбирают свою форму по полу героя.
/// Уронит: форма девочки потерялась (девочке снова «был», «полил»), или
/// без выбранного пола вылезла родовая форма вместо безродной.
const String _hero = 'Соня';

WorldGame _world(FinniGender? g) => contentDayWorld(
    onboarding: OnboardingProgress(finniGender: g, finniName: _hero));

void main() {
  // Ожидаемые строки написаны целиком, не собраны тем же хелпером.
  final Map<String, Map<FinniGender?, String>> events =
      <String, Map<FinniGender?, String>>{
    'rain_umbrella': <FinniGender?, String>{
      null: 'Соня в магазине, а на улице пошёл сильный дождь. '
          'Зонт можно купить тут же.',
      FinniGender.boy: 'Пока Соня был в магазине, пошёл сильный дождь. '
          'Зонт можно купить тут же.',
      FinniGender.girl: 'Пока Соня была в магазине, пошёл сильный дождь. '
          'Зонт можно купить тут же.',
    },
    'pizza_split': <FinniGender?, String>{
      null: 'Друзья заказали большую пиццу и предлагают заплатить каждому '
          'одинаково. Соня хочет только пару кусочков.',
      FinniGender.boy: 'Друзья заказали большую пиццу и предлагают заплатить '
          'каждому одинаково. Соня съел бы только пару кусочков.',
      FinniGender.girl: 'Друзья заказали большую пиццу и предлагают '
          'заплатить каждому одинаково. Соня съела бы только пару кусочков.',
    },
  };

  for (final MapEntry<String, Map<FinniGender?, String>> ev in events.entries) {
    for (final MapEntry<FinniGender?, String> f in ev.value.entries) {
      test('событие ${ev.key}, герой ${f.key?.name ?? 'без пола'}', () {
        final WorldGame w = _world(f.key);
        ok(w.startWeek());
        ok(w.plan(needs: 300, wants: 300, goal: 0));
        if (w.pendingEvent?.id != ev.key) ok(w.demoShowEvent(ev.key));
        expect(w.pendingEvent!.text, f.value);
      });
    }
  }

  test('первая неделя и предел еды на день — в роде героя', () {
    final Map<FinniGender?, (String, String)> want =
        <FinniGender?, (String, String)>{
      null: ('Новый дом!', 'На сегодня еда кончилась'),
      FinniGender.boy: ('Соня переехал!', 'Сегодня Соня уже поел'),
      FinniGender.girl: ('Соня переехала!', 'Сегодня Соня уже поела'),
    };
    for (final MapEntry<FinniGender?, (String, String)> e in want.entries) {
      final WorldGame w = _world(e.key);
      final WorldResult first = ok(w.startWeek());
      expect(first.reason, startsWith(e.value.$1), reason: '${e.key}');
      ok(w.plan(needs: 300, wants: 300, goal: 0));
      final String food = w.snapshot.foodId!;
      BlockReason? b = w.canDo(WorldAction.eat, id: food);
      for (int i = 0; i < 5 && b == null; i++) {
        ok(w.eat(food));
        b = w.canDo(WorldAction.eat, id: food);
      }
      expect(b?.code, 'eat.day_limit');
      expect(b!.text, startsWith(e.value.$2), reason: '${e.key}');
    }
  });

  test('строки экранов: садовник, сон, съеденное дома', () {
    final Map<FinniGender?, List<String>> want = <FinniGender?, List<String>>{
      null: <String>[
        'Получилось полить 4 грядки из 6.',
        'Неделя закончилась. Если силы остались, сон был ещё лучше.',
        'Еда на 90 уже съедена и оплачена.',
      ],
      FinniGender.boy: <String>[
        'Соня полил 4 грядки из 6.',
        'Если к ночи оставались силы, Соня выспался ещё лучше.',
        'Еду на 90 Соня поел сам — она уже оплачена.',
      ],
      FinniGender.girl: <String>[
        'Соня полила 4 грядки из 6.',
        'Если к ночи оставались силы, Соня выспалась ещё лучше.',
        'Еду на 90 Соня поела сама — она уже оплачена.',
      ],
    };
    for (final MapEntry<FinniGender?, List<String>> e in want.entries) {
      expect(<String>[
        gardenerSummary(4, 6, _hero, e.key),
        sleptText(_hero, e.key),
        eatenAtHomeText(90, _hero, e.key),
      ], e.value, reason: '${e.key}');
    }
  });
}
