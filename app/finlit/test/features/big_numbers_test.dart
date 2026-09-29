import 'package:finlit/app_state.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/custom_goal.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/goal.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// Режим «числа покрупнее» (§2.5.8.4) целиком, через [AppState].
///
/// 🔴 Проверка идёт именно через AppState, а не через ContentLoader. Тесты
/// контента дёргали загрузчик напрямую с scale: 5 и видели ровно работавшую
/// половину: контент умножался. Разъезжались же контент экрана и контент
/// движка — а между ними как раз AppState, которого в тех тестах не было.
void main() {
  // 🔴 rootBundle кеширует не строку, а Future, созданный в зоне того теста,
  // где ассет прочитали впервые. Второй AppState.boot() в том же файле ждёт
  // этот Future вечно — тест виснет без единого сообщения.
  setUp(rootBundle.clear);

  Future<void> setBigNumbers(AppState app, {required bool on}) {
    final GameProfile p = app.game.profile;
    return app.updateProfile(
        p.copyWith(settings: p.settings.copyWith(bigNumbers: on)));
  }

  testWidgets('масштаб доходит до движка, а не только до экранов', (
    WidgetTester tester,
  ) async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    expect(app.content.economy.pocketMoney, 10);

    await setBigNumbers(app, on: true);

    expect(identical(app.content, app.game.content), isTrue,
        reason: 'экран и движок обязаны смотреть в один и тот же контент');
    expect(app.content.economy.scale, 5);
    expect(app.game.content.economy.scale, 5);
    expect(app.game.content.economy.pocketMoney, 50);
    expect(app.game.content.item('porridge').price, 10,
        reason: 'цена на витрине и цена в движке — одно число');
  });

  testWidgets('начисляется ровно то, что обещает диалог подтверждения', (
    WidgetTester tester,
  ) async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await setBigNumbers(app, on: true);

    // Диалог в настройках дословно обещает «вместо 10 монеток в неделю — 50».
    await app.act((Game g) => g.startPeriod());
    expect(app.game.snapshot.wallet.unallocated, 50);
  });

  testWidgets('настройка переживает перезапуск приложения', (
    WidgetTester tester,
  ) async {
    final MemoryStorage storage = MemoryStorage();
    final AppState app = AppState(storage);
    await app.boot();
    await setBigNumbers(app, on: true);
    await app.act((Game g) => g.startPeriod());

    final AppState again = AppState(storage);
    await again.boot();

    expect(again.game.profile.settings.bigNumbers, isTrue);
    expect(again.content.economy.pocketMoney, 50,
        reason: 'масштаб читается из профиля до загрузки контента');
    expect(identical(again.content, again.game.content), isTrue);
    expect(again.game.snapshot.wallet.unallocated, 50,
        reason: 'журнал переживает перезапуск вместе с настройкой');
  });

  testWidgets('смена масштаба сохраняет журнал и накопленное', (
    WidgetTester tester,
  ) async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await app.act((Game g) => g.startPeriod());
    final int entriesBefore = app.game.ledger.length;
    expect(app.game.snapshot.wallet.unallocated, 10);

    await setBigNumbers(app, on: true);

    expect(app.game.ledger.length, entriesBefore,
        reason: 'баланс — это свёртка журнала, потерять его нельзя');
    expect(app.game.snapshot.wallet.unallocated, 10,
        reason: 'накопленное не пропадает и не умножается задним числом');

    // И обратно: возврат к обычным числам тоже ничего не стирает.
    await setBigNumbers(app, on: false);
    expect(app.game.ledger.length, entriesBefore);
    expect(app.content.economy.pocketMoney, 10);
    expect(identical(app.content, app.game.content), isTrue);
  });

  testWidgets('своя цель дорожает вместе со всем остальным', (
    WidgetTester tester,
  ) async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();

    final String id = CustomGoals.idFor(1, 1);
    CustomGoals.restore(app.content, id);
    await app.act((Game g) {
      g.chooseGoal(id);
      return const ActionResult(title: 'Цель выбрана', text: '');
    });
    final int priceBefore = app.game.goal!.price;
    expect(priceBefore, app.content.customGoalPrices[1]);

    await setBigNumbers(app, on: true);

    final Goal? goal = app.game.goal;
    expect(goal, isNotNull,
        reason: 'цель не должна исчезать при смене масштаба');
    expect(goal!.price, priceBefore * 5,
        reason: 'иначе своя цель остаётся в старых монетках, '
            'когда всё вокруг умножено на пять');
  });

  testWidgets('тестовый профиль живёт со своим масштабом', (
    WidgetTester tester,
  ) async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await setBigNumbers(app, on: true);

    // §2.5.13: демонстрационный профиль отдельный — и настройки у него свои.
    await app.setDemoMode(true);
    expect(app.content.economy.pocketMoney, 10,
        reason: 'у свежего тестового профиля обычные числа');
    expect(identical(app.content, app.game.content), isTrue);

    await app.setDemoMode(false);
    expect(app.content.economy.pocketMoney, 50,
        reason: 'игра ребёнка вернулась в своём масштабе');
    expect(identical(app.content, app.game.content), isTrue);
  });
}
