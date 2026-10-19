import '../../data/world_content.dart' show EconomyContent;
import 'city/city_guide.dart' show cityLabelScale;
import 'tutorial/tutorial_steps.dart' show tutorialLook, tutorialLookFor;

/// Флаги экранов из `economy.json`, которые живут не в мире, а в переменных
/// экранов: обучалка первого захода (`day_cycle.tutorial_ui`, DEN-4 T1) и
/// подписи города (`city.label_scale`, DEN-30 A). Зовёт `main.dart` до
/// первого кадра — одно место, где файл передаёт их экранам.
void applyContentScreenFlags(EconomyContent e) {
  tutorialLook = tutorialLookFor(tutorialUi: e.tutorialUi);
  cityLabelScale = e.cityLabelScale;
}
