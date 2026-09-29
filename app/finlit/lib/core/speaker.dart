import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Озвучка ключевых объяснений.
///
/// 🔴 Зачем это вообще есть. §3.6.1 ТЗ требует коротких фраз, и тексты у нас
/// короткие — но нижняя граница аудитории это семь лет, а семилетка читает
/// 30–40 слов в минуту. Британский Children's Code для полосы 6–9 формулирует
/// прямо: «ability or willingness to engage with written materials cannot be
/// assumed». Значит, ребёнок, который не хочет читать, должен иметь возможность
/// послушать — иначе объяснение, которым мы гордимся, до него не доходит.
///
/// 🔴 И почему это не обязательная часть сценария. Синтезатор — системный:
/// на устройстве может не оказаться русского голоса, а качать его на ходу мы
/// не будем (§3.1.5 — основной цикл работает без сети). Поэтому озвучка
/// **необязательна по построению**: если голоса нет, приложение не предлагает
/// её вовсе, и ни один экран от этого не ломается.
class Speaker {
  Speaker._();

  static final Speaker instance = Speaker._();

  FlutterTts? _tts;
  bool _checked = false;
  final ValueNotifier<bool> _available = ValueNotifier<bool>(false);

  /// Доступна ли озвучка на этом устройстве. До первой проверки — false.
  bool get available => _available.value;

  /// 🔴 Доступность наблюдаемая, а не просто поле. Проверка голоса больше не
  /// блокирует запуск (см. `main.dart`), поэтому первые кадры рисуются, когда
  /// ответа от системы ещё нет. Экран, которому важно предложить озвучку,
  /// подписывается и перерисовывается сам, когда ответ придёт.
  ValueListenable<bool> get availability => _available;

  /// Проверяет наличие русского голоса. Вызывается один раз при запуске;
  /// любая ошибка означает «озвучки нет», а не падение.
  Future<void> prepare() async {
    if (_checked) return;
    _checked = true;
    try {
      final FlutterTts tts = FlutterTts();
      final bool ru =
          await tts.isLanguageAvailable('ru-RU') as bool? ?? false;
      if (!ru) return;
      await tts.setLanguage('ru-RU');
      // Медленнее обычного: детская речь воспринимается лучше, а объяснение
      // не гонка.
      await tts.setSpeechRate(0.42);
      await tts.setPitch(1.05);
      _tts = tts;
      _available.value = true;
    } on Object catch (e) {
      // В виджет-тестах канала платформы нет — это нормальный путь, а не сбой.
      debugPrint('Озвучка недоступна: $e');
    }
  }

  Future<void> speak(String text) async {
    final FlutterTts? tts = _tts;
    if (tts == null) return;
    try {
      await tts.stop();
      await tts.speak(text);
    } on Object catch (e) {
      debugPrint('Не удалось озвучить: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts?.stop();
    } on Object catch (e) {
      debugPrint('Не удалось остановить озвучку: $e');
    }
  }

  /// Только для тестов: подменить состояние, не трогая платформу.
  @visibleForTesting
  void debugSetAvailable({required bool value}) {
    _checked = true;
    _available.value = value;
  }
}
