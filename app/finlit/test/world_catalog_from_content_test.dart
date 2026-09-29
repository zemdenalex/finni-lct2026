import 'dart:convert';
import 'dart:io';

import 'package:finlit/data/onboarding_store.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/data/world_game_loader.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// Файл контента с диска — те же байты, что едут в assets.
Future<String> _read(String path) => File(path).readAsString();

List<Map<String, Object?>> _items(Object? list) => (list! as List<Object?>)
    .map((Object? o) => (o! as Map<Object?, Object?>).cast<String, Object?>())
    .toList();

/// Цены прямо из `economy.json`, мимо парсера и `worldConfigFromContent`:
/// ожидание не должно считаться тем же кодом, который проверяем.
({Map<String, int> price, Map<String, int> weekly}) _fromFile() {
  final Map<String, Object?> e = (jsonDecode(
          File('${WorldContentLoader.base}/economy.json')
              .readAsStringSync()) as Map<Object?, Object?>)
      .cast<String, Object?>();
  Map<String, Object?> sec(String k) =>
      (e[k]! as Map<Object?, Object?>).cast<String, Object?>();
  final Map<String, int> price = <String, int>{};
  final Map<String, int> weekly = <String, int>{};

  for (final Map<String, Object?> f in _items(sec('food')['options'])) {
    price[f['id']! as String] = f['price']! as int;
  }
  for (final Map<String, Object?> h in _items(sec('homes')['options'])) {
    if (h['is_goal'] != true) continue;
    price[h['id']! as String] = h['price']! as int;
    weekly[h['id']! as String] = h['weekly_cost']! as int;
  }
  for (final Map<String, Object?> p in _items(sec('pets')['roster'])) {
    if (p['tier'] != 'demo') continue;
    price[p['id']! as String] = p['price']! as int;
    weekly[p['id']! as String] = p['food_per_week']! as int;
  }
  for (final Map<String, Object?> t in _items(sec('tech')['options'])) {
    price[t['id']! as String] = t['price']! as int;
  }
  final Map<String, Object?> transport = sec('transport');
  for (final Map<String, Object?> t in _items(transport['options'])) {
    price[t['id']! as String] = transport['price']! as int;
  }
  for (final Map<String, Object?> c in _items(sec('clothing')['items'])) {
    price[c['id']! as String] = c['price']! as int;
  }
  for (final Map<String, Object?> d in _items(sec('decor')['items'])) {
    price[d['id']! as String] = d['price']! as int;
  }
  final Map<String, Object?> snack =
      (sec('energy')['snack']! as Map<Object?, Object?>)
          .cast<String, Object?>();
  price[snack['id']! as String] = snack['price']! as int;
  for (final Map<String, Object?> l in _items(sec('leisure')['options'])) {
    price[l['id']! as String] = l['price']! as int;
  }
  return (price: price, weekly: weekly);
}

void main() {
  // Защищает: цена на карточке магазина = число в economy.json (A11, «не
  // хардкодить цены»). Уронит: позицию забыли в каталоге, лишняя позиция
  // или цена взята не из файла.
  test('A11: каталог настоящего мира — ровно позиции и цены economy.json',
      () async {
    final WorldGame w =
        await openWorldGame(read: _read, storage: MemoryStorage());
    final ({Map<String, int> price, Map<String, int> weekly}) file =
        _fromFile();

    expect(w.catalog.map((WorldCatalogItem i) => i.id).toSet(),
        file.price.keys.toSet());
    for (final WorldCatalogItem i in w.catalog) {
      expect(i.price, file.price[i.id], reason: '${i.id}: цена');
      final int? weekly = file.weekly[i.id];
      if (weekly != null) {
        expect(i.weeklyCost, weekly, reason: '${i.id}: в неделю');
      }
    }
  });

  // Защищает: мир, открытый из файлов, показывает события events.json
  // (A10). Уронит: загрузчик не передал события в WorldConfig — тесты
  // событий читают файл сами, мимо загрузчика, и этого не видят.
  test('A10: мир из content/ показывает событие недели после плана', () async {
    final WorldGame w =
        await openWorldGame(read: _read, storage: MemoryStorage());
    expect(w.startWeek().ok, isTrue);
    final int have = w.snapshot.unallocated;
    expect(w.plan(needs: have, wants: 0, goal: 0).ok, isTrue);
    expect(w.pendingEvent?.id, 'slot_machine_sim');
    expect(w.eventBuildingId, 'park');
  });

  // Защищает: опечатка в events.json видна при загрузке ошибкой загрузчика
  // с именем файла, а не другим типом исключения. Уронит: FormatException
  // разбора событий ушла наружу как есть.
  test('A10: неизвестный эффект в events.json — WorldContentError', () async {
    Future<String> broken(String path) async {
      final String text = await _read(path);
      return path.endsWith('events.json')
          ? text.replaceFirst('"leisure": "cinema"', '"leisur": "cinema"')
          : text;
    }

    await expectLater(
      openWorldGame(read: broken, storage: MemoryStorage()),
      throwsA(isA<WorldContentError>()
          .having((WorldContentError e) => e.file, 'file', 'events.json')
          .having((WorldContentError e) => e.path, 'path',
              'events[0].options[0].effects.leisur')),
    );
  });

  // Защищает: онбординг переживает перезапуск на настоящем файловом
  // хранилище (A14). MemoryStorage не кодирует JSON и не перезаписывает
  // файл — здесь проверяется и то и другое. Уронит: в toJson попал не-JSON
  // тип (enum), запись поверх старого файла не прошла.
  test('A14: прогресс онбординга переживает перезапуск в FileStorage',
      () async {
    final Directory dir = Directory.systemTemp.createTempSync('finlit_onb_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final WorldGame first =
        await openWorldGame(read: _read, storage: FileStorage(dir));
    expect((await first.setNickname('Кузя')).reasonCode, 'onboarding.nick');
    expect(
        (await first.setFinniLook(
                species: 'finni-a2', gender: FinniGender.girl, look: 3))
            .reasonCode,
        'onboarding.look');
    expect((await first.setFinniName('Бублик')).reasonCode, 'onboarding.name');

    // «Перезапуск»: новое хранилище над тем же каталогом.
    final WorldGame again =
        await openWorldGame(read: _read, storage: FileStorage(dir));
    final OnboardingProgress p = again.onboarding;
    expect(p.nickname, 'Кузя');
    expect(p.finniSpecies, 'finni-a2');
    expect(p.finniGender, FinniGender.girl);
    expect(p.finniLook, 3);
    expect(p.finniName, 'Бублик');
    expect(p.step, OnboardingProgress.stepMoney);

    await clearOnboarding(FileStorage(dir));
    final WorldGame fresh =
        await openWorldGame(read: _read, storage: FileStorage(dir));
    expect(fresh.onboarding.nickname, isEmpty);
    expect(fresh.onboarding.step, OnboardingProgress.stepIntro);
  });
}
