import 'dart:convert';
import 'dart:js_interop';

import 'storage.dart';

/// Хранилище по умолчанию для браузера: `window.localStorage`.
///
/// Если браузер localStorage не даёт (приватное окно Safari, запрет
/// сайтовых данных), игра всё равно запускается, но прогресс живёт только
/// до перезагрузки: упавший старт хуже потерянного сохранения.
Future<Storage> openDefaultStorage() async =>
    WebStorage.available() ? const WebStorage() : MemoryStorage();

@JS('localStorage')
external _JSStorage get _localStorage;

extension type _JSStorage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

/// Профиль в `localStorage`, один ключ на запись, значение — JSON.
///
/// 🔴 localStorage общий на весь домен, а не на путь: сборка под `/quiz/`
/// и сборка под `/` на одном домене читали бы одни и те же ключи. Поэтому
/// у каждой сборки свой префикс.
class WebStorage implements Storage {
  const WebStorage({this.prefix = 'finni/'});

  final String prefix;

  /// Проверка записью: сам доступ к `localStorage` может бросить
  /// SecurityError, а запись — QuotaExceededError.
  static bool available() {
    try {
      const String probe = 'finni/__probe__';
      _localStorage.setItem(probe, '1');
      _localStorage.removeItem(probe);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _key(String key) => '$prefix$key';

  @override
  Future<Map<String, Object?>?> read(String key) async {
    final String? raw;
    try {
      raw = _localStorage.getItem(_key(key));
    } catch (_) {
      return null;
    }
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map<Object?, Object?>).cast<String, Object?>();
    } on Object {
      // То же правило, что у файла: битая запись не роняет запуск, а
      // откладывается в [brokenKey].
      try {
        await write(brokenKey(key), <String, Object?>{'raw': raw});
      } on Object {
        // Квота кончилась — запуск всё равно важнее.
      }
      await delete(key);
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, Object?> value) async {
    // localStorage пишет строку целиком и синхронно — наполовину записанного
    // профиля, от которого файл спасает временным файлом, здесь не бывает.
    _localStorage.setItem(_key(key), jsonEncode(value));
  }

  @override
  Future<void> delete(String key) async {
    try {
      _localStorage.removeItem(_key(key));
    } catch (_) {
      // Нечего удалять — нечего и чинить.
    }
  }
}
