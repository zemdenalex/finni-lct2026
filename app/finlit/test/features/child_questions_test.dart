import 'package:finlit/features/adult/parent_questions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Вопросы «спроси ребёнка» на экране взрослого (S14, ТЗ 2.5.12).
///
/// Перенесены из теста старого раздела взрослого: экран v1 удалён, а
/// [ChildQuestions] показывает раздел взрослого нового мира.
void main() {
  // Защищает: ни один вопрос не затрагивает нехватку денег в семье.
  // Уронит: новый вопрос со словом «зарплата», «хватает ли», «долг».
  test('вопросы ребёнка взрослому не спрашивают про деньги семьи', () {
    // 🔴 Ребёнку, у которого дома не хватает, вопрос «сколько ты
    // зарабатываешь» или «хватает ли нам» делает хуже, а не лучше.
    // Разговор про выбор работает, разговор про нехватку пугает.
    // Совпадение ищется по началу слова, а не по подстроке: «долго»
    // содержит «долг», и грубая проверка ловила безобидный вопрос.
    final List<RegExp> forbidden = <RegExp>[
      RegExp(r'\bзарабатыва'),
      RegExp(r'\bзарплат'),
      RegExp(r'\bхватает ли'),
      RegExp(r'\bсколько денег'),
      RegExp(r'\bсколько у нас'),
      RegExp(r'\bдолг(и|ов|а|у|ом)?\b'),
      RegExp(r'\bкредит'),
      RegExp(r'\bбедн'),
    ];
    for (final ChildQuestion q in ChildQuestions.all) {
      final String text = '${q.ask} ${q.why}'.toLowerCase();
      for (final RegExp bad in forbidden) {
        expect(bad.hasMatch(text), isFalse,
            reason: 'вопрос «${q.ask}» затрагивает нехватку денег в семье');
      }
    }
  });

  // Защищает: за демо (5 недель) взрослый не видит один вопрос дважды.
  // Уронит: ofPeriod начал брать вопрос по модулю меньшего числа.
  test('за пять игровых недель вопросы не повторяются', () {
    final Set<String> seen = <String>{
      for (int period = 1; period <= 5; period++)
        ChildQuestions.ofPeriod(period).ask,
    };
    expect(seen.length, 5);
  });
}
