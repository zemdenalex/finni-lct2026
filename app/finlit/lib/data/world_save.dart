import 'dart:async';
import 'dart:convert';

import '../domain/world/contract.dart';
import '../domain/world/world_config.dart';
import '../domain/world/world_game.dart';
import 'content_loader.dart' show ReadAsset;
import 'onboarding_store.dart';
import 'storage.dart';
import 'world_config_from_content.dart';
import 'world_content.dart';

/// Журнал мира в [Storage] (карточка A16, ТЗ 2.5.13.1, Приложение А шаг 11:
/// закрыть и открыть — всё на месте).
///
/// Значение — `{"v": 1, "journal": [...записи...]}`: хранилище держит
/// объекты, а журнал — список.
const String worldJournalKey = 'world_journal';

/// Что нашлось в хранилище при запуске.
enum WorldRestore {
  /// Сохранения не было — первый запуск (или после сброса).
  empty,

  /// Журнал прочитан целиком.
  restored,

  /// Журнал прочитан, но часть записей неизвестного вида пропущена
  /// ([WorldGame.unreadable]). Исходное значение отложено в
  /// `brokenKey(worldJournalKey)`.
  partial,

  /// Сохранение не прочиталось — мир начат заново, испорченное отложено в
  /// `brokenKey(worldJournalKey)`.
  broken,
}

/// Мир из контента и сохранения — **одна функция для экранов**.
///
/// ```dart
/// final SavedWorld saved = await openSavedWorld(
///   read: rootBundle.loadString,
///   storage: await openDefaultStorage(),
/// );
/// WorldState.persistent(
///   saved.world,
///   freshWorld: saved.freshWorld,
///   onReset: saved.forget,
/// );
/// ```
///
/// Дальше экраны ничего не зовут: после каждого действия, которое что-то
/// записало в журнал, журнал сохраняется сам; отказ ничего не пишет и не
/// сохраняет. Онбординг — так же, через тот же порядок записи.
///
/// Никогда не бросает на испорченном сохранении: мир начинается заново,
/// испорченное откладывается (см. [WorldRestore]).
Future<SavedWorld> openSavedWorld({
  required ReadAsset read,
  required Storage storage,
}) async {
  final WorldContent content = await WorldContentLoader(read).load();
  final SavedWorld saved =
      SavedWorld._(storage, worldConfigFromContent(content), content);
  await saved._restore();
  return saved;
}

/// Сохранение нового мира: держит текущий [WorldGame] и пишет его журнал и
/// онбординг в [Storage].
///
/// 🔴 Все записи идут **по одной, в порядке вызова**. Две одновременные
/// записи файла делят один `.tmp` и дерутся за переименование, а стирание
/// при сбросе, обогнанное запоздалой записью старого мира, вернуло бы
/// стёртую игру. Сохранение старого мира после [freshWorld] отбрасывается.
class SavedWorld {
  SavedWorld._(this._storage, this.config, this.content);

  final Storage _storage;

  /// Числа мира из контента — общие для восстановленного и нового мира.
  final WorldConfig config;

  /// Контент целиком — для того, что берут экраны, а не движок (мини-игры
  /// профессий: `JobGames` в `main.dart`). Файлы читаются один раз.
  final WorldContent content;

  late WorldGame _world;
  WorldRestore _restored = WorldRestore.empty;

  /// Номер текущего мира: растёт при [freshWorld]. Сохранения с чужим
  /// номером отбрасываются.
  int _generation = 0;

  /// Сохранение журнала уже стоит в очереди — ещё одно не нужно: оно
  /// прочитает журнал целиком, когда до него дойдёт очередь.
  bool _journalQueued = false;

  Future<void> _tail = Future<void>.value();

  /// Текущий мир. После [freshWorld] — новый.
  WorldGame get world => _world;

  /// Что нашлось при запуске.
  WorldRestore get restored => _restored;

  /// Последняя неудачная запись журнала или null, если последняя удалась.
  /// Мир в памяти при этом цел: следующее действие попробует снова.
  Object? get lastSaveError => _lastSaveError;
  Object? _lastSaveError;

  /// Новый мир с нуля — для сброса (демо-панель, раздел взрослого). Прежний
  /// мир больше не сохраняется. Сохранённое стирает [forget].
  WorldGame freshWorld() {
    _generation++;
    _journalQueued = false;
    return _world = _build(const <Object?>[], const OnboardingProgress());
  }

  /// Стереть сохранённое: журнал, онбординг и отложенные испорченные
  /// значения (§3.5 — удаление без обращения к разработчику). Становится в
  /// ту же очередь, что и записи: всё, что поставлено раньше, записано до
  /// стирания; всё, что позже, — после.
  Future<void> forget() => _enqueue(() async {
        for (final String key in <String>[
          worldJournalKey,
          brokenKey(worldJournalKey),
          onboardingStorageKey,
          brokenKey(onboardingStorageKey),
        ]) {
          await _storage.delete(key);
        }
      });

  /// Дождаться, пока всё поставленное в очередь записано.
  Future<void> flush() => _tail;

  Future<void> _restore() async {
    OnboardingProgress onboarding = const OnboardingProgress();
    try {
      onboarding = await loadOnboarding(_storage);
    } on Object {
      // Онбординг проходится заново — это не повод не запуститься.
    }

    Map<String, Object?>? raw;
    try {
      raw = await _storage.read(worldJournalKey);
    } on Object {
      // Файл есть, но не читается (ввод-вывод). Отложить нечего — запуск
      // всё равно важнее; честно говорим, что сохранение не прочиталось.
      _world = _build(const <Object?>[], onboarding);
      _restored = WorldRestore.broken;
      return;
    }
    if (raw == null) {
      _world = _build(const <Object?>[], onboarding);
      _restored = WorldRestore.empty;
      return;
    }

    try {
      final Object? journal = raw['journal'];
      if (raw['v'] != 1 || journal is! List) {
        throw FormatException('неизвестный формат журнала: v=${raw['v']}');
      }
      _world = _build(journal, onboarding);
      if (_world.unreadable == 0) {
        _restored = WorldRestore.restored;
        return;
      }
      _restored = WorldRestore.partial;
      await _setAside(raw);
    } on Object {
      _world = _build(const <Object?>[], onboarding);
      _restored = WorldRestore.broken;
      await _setAside(raw);
      try {
        await _storage.delete(worldJournalKey);
      } on Object {
        // Не стёрлось — первое же действие перезапишет.
      }
    }
  }

  /// Отложить исходное значение журнала в [brokenKey].
  Future<void> _setAside(Map<String, Object?> raw) async {
    try {
      await _storage.write(brokenKey(worldJournalKey),
          <String, Object?>{'raw': jsonEncode(raw)});
    } on Object {
      // Отложить не вышло — запуск всё равно важнее.
    }
  }

  WorldGame _build(List<Object?> journal, OnboardingProgress onboarding) {
    final int generation = _generation;
    return WorldGame.fromJson(
      journal,
      config: config,
      onboarding: onboarding,
      saveOnboarding: (Map<String, Object?> json) => generation == _generation
          ? _enqueue(() => _storage.write(onboardingStorageKey, json))
          : Future<void>.value(),
      onJournalChanged: () => _journalChanged(generation),
    );
  }

  /// Запись в журнал: сохранить, когда действие закончится. Очередь
  /// выполняет задачу не раньше следующей микрозадачи, а действие мира
  /// синхронно — так что журнал читается уже после всех его записей.
  void _journalChanged(int generation) {
    if (generation != _generation || _journalQueued) return;
    _journalQueued = true;
    unawaited(_enqueue(() async {
      if (generation != _generation) return;
      _journalQueued = false;
      await _storage.write(worldJournalKey, <String, Object?>{
        'v': 1,
        'journal': _world.toJson(),
      });
    }).then<void>((_) {
      _lastSaveError = null;
    }, onError: (Object e) {
      _lastSaveError = e;
    }));
  }

  /// Поставить запись в очередь. Возвращает её итог (ошибку — тоже, чтобы
  /// онбординг честно сказал «не сохранилось»), но ошибка не ломает очередь
  /// для следующих записей.
  Future<void> _enqueue(Future<void> Function() op) {
    final Future<void> run = _tail.then((_) => op());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }
}
