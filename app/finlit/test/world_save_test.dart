import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/onboarding_store.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_save.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_autopilot.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// Файл контента с диска — те же байты, что едут в assets.
Future<String> _read(String path) => File(path).readAsString();

/// Пустой каталог под `FileStorage`, стирается после теста.
Directory _dir() {
  final Directory d = Directory.systemTemp.createTempSync('finlit_a16_');
  addTearDown(() => d.deleteSync(recursive: true));
  return d;
}

/// «Запуск приложения»: новое хранилище над тем же каталогом.
Future<SavedWorld> _launch(Directory dir) =>
    openSavedWorld(read: _read, storage: FileStorage(dir));

File _file(Directory dir, String key) => File('${dir.path}/$key.json');

String _describe(WorldGame w) => <Object?>[
      w.phase,
      w.snapshot.weekNo,
      w.snapshot.need,
      w.snapshot.want,
      w.snapshot.goal,
      w.snapshot.free,
      w.snapshot.unallocated,
      w.snapshot.energy,
      w.snapshot.happiness,
      w.snapshot.growthPoints,
      w.snapshot.stage,
      w.snapshot.experience,
      (w.snapshot.owned.toList()..sort()).join(','),
      w.snapshot.activeGoalId,
      w.pendingEvent?.id,
    ].join(' | ');

void main() {
  // Защищает: ТЗ 2.5.13.1 / Приложение А шаг 11 — закрыть и открыть, всё на
  // месте: деньги, неделя, покупки, онбординг и сам журнал. На настоящем
  // FileStorage: MemoryStorage держит объект по ссылке и не проверил бы, что
  // журнал переживает jsonEncode. Уронит: журнал не сохраняется после
  // действия, сохраняется посреди действия из нескольких записей, запись
  // не переживает JSON, или онбординг и журнал пишутся вразнобой.
  test('A16: сохранили → перезапуск → тот же мир и тот же журнал', () async {
    final Directory dir = _dir();
    final SavedWorld first = await _launch(dir);
    expect(first.restored, WorldRestore.empty);
    await first.world.setNickname('Кузя');
    await first.world.setFinniName('Бублик');
    WorldAutopilot(first.world).playWeeks(2);
    // Действие посреди недели: последнее сохранение — не на границе недели.
    first.world.startWeek();
    expect(first.world.journal.length, greaterThan(10));
    await first.flush();
    expect(first.lastSaveError, isNull);

    final SavedWorld again = await _launch(dir);
    expect(again.restored, WorldRestore.restored);
    expect(jsonEncode(again.world.toJson()), jsonEncode(first.world.toJson()));
    expect(_describe(again.world), _describe(first.world));
    expect(again.world.onboarding.nickname, 'Кузя');
    expect(again.world.onboarding.finniName, 'Бублик');

    // И дальше сохраняет восстановленный мир, а не только первый.
    final int before = again.world.journal.length;
    expect(again.world.plan(needs: 0, wants: 0, goal: 0).ok, isTrue);
    await again.flush();
    final SavedWorld third = await _launch(dir);
    expect(third.world.journal.length, greaterThan(before));
    expect(_describe(third.world), _describe(again.world));
  });

  // Защищает: испорченное сохранение не роняет запуск (§3.4) и не стирается
  // бесследно — мир начинается заново, исходное лежит в brokenKey. Три
  // вида порчи: не JSON вовсе, JSON не той формы, запись неизвестного вида.
  // Уронит: исключение из read/fromJson ушло наружу на старте, испорченное
  // удалено без копии, или мир из пропущенных записей выдан за целый.
  group('A16: испорченное сохранение', () {
    test('не JSON — чистый мир, файл отложен', () async {
      final Directory dir = _dir();
      _file(dir, worldJournalKey).writeAsStringSync('{"v":1,"journal":[{');

      final SavedWorld s = await _launch(dir);
      expect(s.world.journal, isEmpty);
      expect(s.world.phase, WeekPhase.onboarding);
      final Map<String, Object?>? aside =
          await FileStorage(dir).read(brokenKey(worldJournalKey));
      expect(aside?['raw'], '{"v":1,"journal":[{');
      expect(_file(dir, worldJournalKey).existsSync(), isFalse);
    });

    test('JSON не той формы — broken, чистый мир, значение отложено', () async {
      final Directory dir = _dir();
      _file(dir, worldJournalKey).writeAsStringSync('{"v":1,"journal":"ой"}');

      final SavedWorld s = await _launch(dir);
      expect(s.restored, WorldRestore.broken);
      expect(s.world.journal, isEmpty);
      final Map<String, Object?>? aside =
          await FileStorage(dir).read(brokenKey(worldJournalKey));
      expect(jsonDecode(aside!['raw']! as String),
          <String, Object?>{'v': 1, 'journal': 'ой'});

      // Игра идёт и сохраняется поверх.
      expect(s.world.startWeek().ok, isTrue);
      await s.flush();
      expect((await _launch(dir)).restored, WorldRestore.restored);
    });

    test('запись неизвестного вида — partial, остальное на месте', () async {
      final Directory dir = _dir();
      final SavedWorld s = await _launch(dir);
      s.world.startWeek();
      await s.flush();
      final Map<String, Object?> saved =
          (await FileStorage(dir).read(worldJournalKey))!;
      final List<Object?> journal = <Object?>[
        ...saved['journal']! as List<Object?>,
        <String, Object?>{'seq': 99, 'kind': 'world.fromTheFuture'},
      ];
      await FileStorage(dir).write(
          worldJournalKey, <String, Object?>{'v': 1, 'journal': journal});

      final SavedWorld again = await _launch(dir);
      expect(again.restored, WorldRestore.partial);
      expect(again.world.unreadable, 1);
      expect(_describe(again.world), _describe(s.world));
      expect(
          await FileStorage(dir).read(brokenKey(worldJournalKey)), isNotNull);
    });
  });

  // Защищает: сброс (демо-панель, раздел взрослого) стирает журнал,
  // онбординг и отложенное (§3.5), и запоздалое действие старого мира не
  // воскрешает стёртую игру. Уронит: сохранение старого мира после сброса
  // или стирание без очереди — перезапуск вернёт прежнюю игру.
  test('A16: сброс — перезапуск даёт чистый мир', () async {
    final Directory dir = _dir();
    final SavedWorld s = await _launch(dir);
    await s.world.setNickname('Кузя');
    final WorldGame old = s.world..startWeek();

    // Как WorldState.reset: новый мир, затем стирание.
    final WorldGame fresh = s.freshWorld();
    await s.forget();
    old.plan(needs: 0, wants: 0, goal: 0); // старый экран ещё жив
    await fresh.setNickname('Новый');
    await s.flush();

    final SavedWorld again = await _launch(dir);
    expect(again.restored, WorldRestore.empty);
    expect(again.world.journal, isEmpty);
    expect(again.world.onboarding.nickname, 'Новый');

    await again.forget();
    expect(await FileStorage(dir).read(onboardingStorageKey), isNull);
    expect(dir.listSync(), isEmpty);
  });
}
