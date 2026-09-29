import 'package:finlit/app_state.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/economy/period_rules.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/ledger/ledger_entry.dart';
import 'package:finlit/domain/ledger/ledger_fold.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:finlit/domain/models/task.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// Дефекты, найденные аудитом, а не тестами. Каждый тест здесь падал до
/// исправления — это и есть причина, по которой файл существует.
void main() {
  // 🔴 rootBundle кеширует не строку, а Future из зоны предыдущего теста:
  // без этой строки второй boot() в файле виснет навсегда и без вывода.
  setUp(rootBundle.clear);

  testWidgets('§3.5.5 взрослый в демо-режиме не стирает игру ребёнка',
      (WidgetTester tester) async {
    final MemoryStorage storage = MemoryStorage();

    // Ребёнок играет: неделя начата, монетки разложены.
    final AppState app = AppState(storage);
    await app.boot();
    await app.act((Game g) => g.startPeriod());
    final int childCoins = app.game.snapshot.wallet.unallocated;
    expect(childCoins, greaterThan(0));

    // Взрослый включает демонстрационный режим и удаляет профиль оттуда.
    await app.setDemoMode(true);
    await app.deleteActiveProfile();

    // Файл ребёнка обязан пережить это без единой потери.
    expect(await storage.read('profile'), isNotNull,
        reason: 'удаление из демо-режима стёрло игру ребёнка');
    await app.setDemoMode(false);
    expect(app.game.snapshot.wallet.unallocated, childCoins);
  });

  // Защищает: §3.5 — удаление профиля не оставляет его копий. С A16
  // хранилище не стирает нечитаемый профиль, а откладывает в
  // `profile_broken`; удаление, которое стирало только `profile`, оставляло
  // эту копию навсегда. Уронит: удаление или сброс забывают [brokenKey].
  testWidgets('§3.5 удаление профиля стирает и отложенную испорченную копию',
      (WidgetTester tester) async {
    final MemoryStorage storage = MemoryStorage();
    await storage.write(brokenKey('profile'), <String, Object?>{'raw': 'x'});
    await storage
        .write(brokenKey('profile_demo'), <String, Object?>{'raw': 'y'});

    final AppState app = AppState(storage);
    await app.boot();
    await app.deleteActiveProfile();
    expect(await storage.read(brokenKey('profile')), isNull);

    await app.setDemoMode(true);
    await app.resetDemoProfile();
    expect(await storage.read(brokenKey('profile_demo')), isNull);
  });

  testWidgets('§2.5.4.2 задание до начала недели не съедает карманные',
      (WidgetTester tester) async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();

    // Первая неделя прожита целиком.
    await app.act((Game g) => g.startPeriod());
    await app.act((Game g) => g.confirmPlan(Allocation(
        needs: 0, wants: 0, savings: g.snapshot.wallet.unallocated)));
    await app.closePeriod();

    // Ребёнок открывает задания раньше, чем нажимает «Начать неделю».
    final GameTask task = app.content.tasks.first;
    await app.act((Game g) => g.completeTask(task, best: true));

    // Монетки за задание не должны выдавать неделю за начатую.
    expect(app.game.phase, PeriodPhase.closing,
        reason: 'награда за задание сама перевела игру в планирование');

    await app.act((Game g) => g.startPeriod());
    expect(app.game.pocketMoneyReceived, isTrue);
    expect(app.game.snapshot.wallet.unallocated,
        app.content.economy.pocketMoney + task.reward,
        reason: 'карманные за неделю потерялись');
  });

  testWidgets('карманные за одну неделю приходят ровно один раз',
      (WidgetTester tester) async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await app.act((Game g) => g.startPeriod());
    final int once = app.game.snapshot.wallet.unallocated;
    await app.act((Game g) => g.startPeriod());
    expect(app.game.snapshot.wallet.unallocated, once,
        reason: 'повторное касание кнопки удвоило доход');
  });

  testWidgets('§2.5.13.1 перезапуск сохраняет все шесть обязательных величин',
      (WidgetTester tester) async {
    final MemoryStorage storage = MemoryStorage();

    final AppState first = AppState(storage);
    await first.boot();
    await first.updateProfile(first.game.profile.copyWith(
      petName: 'Мурзик',
      species: PetSpecies.values.last,
      palette: PetPalette.values.last,
    ));
    first.game.chooseGoal('scooter');
    await first.act((Game g) => g.startPeriod());

    final CatalogItem need =
        first.content.catalog.firstWhere((CatalogItem i) => i.isNeed);
    final int income = first.game.snapshot.wallet.unallocated;
    await first.act((Game g) => g.confirmPlan(Allocation(
          needs: need.price,
          wants: 0,
          savings: income - need.price,
        )));
    await first.act((Game g) => g.buy(need));
    await first
        .act((Game g) => g.completeTask(first.content.tasks.first, best: true));
    await first.act((Game g) =>
        g.allocate(Envelope.savings, first.game.snapshot.wallet.unallocated));

    final GameSnapshot before = first.game.snapshot;
    final int purchases = first.game.ledger
        .where((LedgerEntry e) => e.kind == LedgerKind.purchase)
        .length;
    expect(purchases, 1);

    // Приложение закрыли и открыли заново.
    final AppState second = AppState(storage);
    await second.boot();
    final GameSnapshot after = second.game.snapshot;

    expect(second.game.profile.petName, 'Мурзик', reason: 'профиль');
    expect(second.game.profile.species, PetSpecies.values.last);
    expect(second.game.profile.palette, PetPalette.values.last);
    expect(after.wallet.envelopes.byEnvelope(Envelope.needs),
        before.wallet.envelopes.byEnvelope(Envelope.needs),
        reason: 'баланс конвертов');
    expect(
        second.game.ledger
            .where((LedgerEntry e) => e.kind == LedgerKind.purchase)
            .length,
        purchases,
        reason: 'покупки');
    expect(after.wallet.savings, before.wallet.savings, reason: 'накопления');
    expect(second.game.goal?.id, 'scooter', reason: 'цель');
    expect(after.stage, before.stage, reason: 'прогресс питомца');
    expect(second.game.periodNo, first.game.periodNo);
  });

  testWidgets('§2.5.11.1 итоги недели переживают перезапуск',
      (WidgetTester tester) async {
    final MemoryStorage storage = MemoryStorage();

    final AppState first = AppState(storage);
    await first.boot();
    await first.act((Game g) => g.startPeriod());
    await first.act((Game g) => g.confirmPlan(Allocation(
        needs: g.snapshot.wallet.unallocated, wants: 0, savings: 0)));
    await first
        .act((Game g) => g.completeTask(first.content.tasks.first, best: true));
    await first.act((Game g) =>
        g.allocate(Envelope.savings, first.game.snapshot.wallet.unallocated));
    await first.closePeriod();

    final PeriodOutcome before = first.lastOutcome!;
    expect(before.carePoints, isNotEmpty);

    // Приложение закрыли и открыли заново: поле в памяти пропало,
    // но итог обязан быть виден — §2.5.11.1 требует итоги последнего
    // периода, а не «итоги, пока не выключал».
    final AppState second = AppState(storage);
    await second.boot();
    final PeriodOutcome? after = second.lastOutcome;

    expect(after, isNotNull, reason: 'итоги недели исчезли после перезапуска');
    expect(after!.points, before.points);
    expect(after.carePoints.length, before.carePoints.length);
    expect(after.deviations.length, before.deviations.length);
  });

  test('профиль с котом, сохранённый до 23.09, открывается белкой', () {
    // 🔴 Первым видом раньше был кот. `byName('cat')` после переименования
    // бросил бы исключение, и ребёнок потерял бы игру при обновлении.
    final Map<String, Object?> json = GameProfile.fresh(isDemo: false).toJson()
      ..['species'] = 'cat';
    final GameProfile p = GameProfile.fromJson(json);
    expect(p.species, PetSpecies.squirrel);
  });
}
