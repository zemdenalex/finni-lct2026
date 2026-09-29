// Файловое хранилище на телефоне, localStorage в браузере. Выбор делает
// компилятор по условному экспорту, поэтому в веб-сборку не попадает dart:io,
// а в Android-сборку — dart:js_interop.
export 'storage_io.dart' if (dart.library.js_interop) 'storage_web.dart';

/// Куда складывается профиль.
///
/// 🔴 Один JSON-файл, а не SQLite с кодогенерацией. §3.2 ТЗ допускает
/// «файловое хранилище или эквивалент» наравне с Room/SQLite. Данных здесь —
/// один профиль, один питомец, пять недель и несколько десятков записей
/// журнала; типизированные запросы и миграции такому объёму не нужны, а
/// build_runner у людей, впервые видящих Dart, съедает день на «generated
/// code is out of date».
abstract interface class Storage {
  Future<Map<String, Object?>?> read(String key);
  Future<void> write(String key, Map<String, Object?> value);
  Future<void> delete(String key);
}

/// Ключ, под которым хранилище откладывает нечитаемое значение [key] вместо
/// того, чтобы стереть его: `{"raw": "<что лежало>"}`. Запуск идёт с чистого
/// листа, а испорченное остаётся для разбора. Стирать его надо вместе с
/// самим ключом — это тоже данные ребёнка (§3.5).
String brokenKey(String key) => '${key}_broken';

/// Хранилище в памяти — для тестов и для предпросмотра экранов.
class MemoryStorage implements Storage {
  final Map<String, Map<String, Object?>> _data =
      <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, Map<String, Object?> value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async => _data.remove(key);
}
