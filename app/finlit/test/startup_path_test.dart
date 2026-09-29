import 'dart:io';

import 'package:finlit/core/speaker.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🔴 Первый кадр не ждёт необязательные подсистемы.
///
/// §3.4.5 отводит на холодный старт пять секунд. До 19.09 `main()` вызывал
/// `await Speaker.instance.prepare()` ДО `runApp()` — до четырёх
/// последовательных обращений к системному синтезатору Android через канал
/// платформы, и всё это время экран был пустой. Замерить это на машине
/// не удалось (не хватало памяти под эмулятор), но ждать первого кадра ради
/// озвучки неправильно независимо от замера.
///
/// Тест сторожит исходник, а не поведение: поведение здесь зависит от
/// платформы, которой в виджет-тесте нет.
void main() {
  /// Код без комментариев: в комментариях эта строка процитирована нарочно,
  /// чтобы следующий читатель понял, почему так делать нельзя.
  String codeOf(String path) => File(path)
      .readAsLinesSync()
      .where((String l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('main() не ждёт озвучку до первого кадра', () {
    final String src = codeOf('lib/main.dart');
    final int runApp = src.indexOf('runApp(');
    expect(runApp, greaterThan(0), reason: 'не нашёл вызов runApp');

    // Импорты отбрасываем: строка `import '.../speaker.dart'` стоит выше
    // любого кода и сама по себе ничего не задерживает.
    final String beforeFirstFrame = src
        .substring(0, runApp)
        .split('\n')
        .where((String l) => !l.trimLeft().startsWith('import '))
        .join('\n');
    expect(beforeFirstFrame.contains('Speaker.instance'), isFalse,
        reason: 'озвучка готовится до первого кадра — это задерживает старт');
    expect(RegExp(r'await\s+Speaker').hasMatch(src), isFalse,
        reason: 'ожидание озвучки в запуске приложения');
  });

  test('до проверки озвучка считается недоступной', () {
    // Значение по умолчанию важно: пока ответа от системы нет, приложение
    // не должно предлагать то, чего может не оказаться.
    expect(Speaker.instance.availability.value,
        Speaker.instance.available,
        reason: 'наблюдаемое значение разошлось с геттером');
  });

  test('экран настроек подписан на доступность, а не читает её разово', () {
    // Проверка голоса идёт после первого кадра, поэтому экран, собранный
    // раньше ответа, обязан перестроиться сам.
    final String src = codeOf('lib/features/settings/settings_screen.dart');
    expect(src.contains('Speaker.instance.availability'), isTrue,
        reason: 'экран не подписан на доступность озвучки');
    expect(src.contains('if (Speaker.instance.available)'), isFalse,
        reason: 'разовое чтение доступности переживёт отложенную проверку '
            'как «озвучки нет»');
  });
}
