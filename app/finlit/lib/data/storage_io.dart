import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'storage.dart';

/// Хранилище по умолчанию для этой платформы: JSON-файлы в документах
/// приложения.
Future<Storage> openDefaultStorage() => FileStorage.open();

class FileStorage implements Storage {
  const FileStorage(this._dir);

  final Directory _dir;

  static Future<FileStorage> open() async {
    final Directory d = await getApplicationDocumentsDirectory();
    final Directory sub = Directory('${d.path}/finlit');
    if (!sub.existsSync()) sub.createSync(recursive: true);
    return FileStorage(sub);
  }

  File _file(String key) => File('${_dir.path}/$key.json');

  @override
  Future<Map<String, Object?>?> read(String key) async {
    final File f = _file(key);
    if (!f.existsSync()) return null;
    String raw = '';
    try {
      raw = await f.readAsString();
      return (jsonDecode(raw) as Map<Object?, Object?>).cast<String, Object?>();
    } on Object catch (e) {
      // Ошибка ввода-вывода — не порча: файл не трогаем, пусть решает
      // вызывающий.
      if (e is! FormatException && e is! TypeError) rethrow;
      // Битый файл не должен ронять запуск: §3.4 запрещает потерю прогресса,
      // но упавшее на старте приложение хуже, чем начатая заново игра.
      // Не JSON, не объект, не UTF-8. Содержимое откладывается в
      // [brokenKey], а не стирается: его ещё можно разобрать.
      try {
        await write(brokenKey(key), <String, Object?>{'raw': raw});
      } on Object {
        // Отложить не вышло — запуск всё равно важнее.
      }
      await f.delete();
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, Object?> value) async {
    // Запись через временный файл: обрыв на середине не оставит
    // наполовину записанный профиль.
    final File tmp = File('${_file(key).path}.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(_file(key).path);
  }

  @override
  Future<void> delete(String key) async {
    final File f = _file(key);
    if (f.existsSync()) await f.delete();
  }
}
