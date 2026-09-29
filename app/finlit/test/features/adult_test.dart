import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/features/adult/adult_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:finlit/features/adult/parent_questions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget wrap(AppState app, Widget child) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildAppTheme(), home: child),
    );

/// Высокое окно: ListView строит детей лениво, а проверять нужно всё
/// содержимое раздела, а не первый экран прокрутки.
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// SnackBar живёт по таймеру: если его не дождаться, тест падает на
/// «A Timer is still pending even after the widget tree was disposed».
Future<void> flushSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// Решает пример барьера и нажимает ту же кнопку, что служит выходом.
Future<void> passBarrier(WidgetTester tester) async {
  final Text question =
      tester.widget<Text>(find.byKey(AdultScreen.barrierQuestionKey));
  final List<String> parts = question.data!.split(' × ');
  final int answer = int.parse(parts[0]) * int.parse(parts[1]);
  await tester.enterText(find.byKey(AdultScreen.barrierFieldKey), '$answer');
  await tester.tap(find.byKey(AdultScreen.gateButtonKey));
  await tester.pumpAndSettle();
}

/// Неделя, в которой ребёнок взял монетки из копилки.
Future<AppState> weekWithWithdraw(Storage storage) async {
  final AppState app = AppState(storage);
  await app.boot();
  await app.act((Game g) => g.startPeriod());
  await app.act((Game g) =>
      g.confirmPlan(const Allocation(needs: 4, wants: 3, savings: 3)));
  await app.act((Game g) =>
      g.move(from: Envelope.savings, to: Envelope.wants, amount: 2));
  await app.closePeriod();
  return app;
}

/// Неделя, в которой покупку отклонили из-за нехватки монеток.
Future<AppState> weekWithDeclined(Storage storage) async {
  final AppState app = AppState(storage);
  await app.boot();
  await app.act((Game g) => g.startPeriod());
  await app.act((Game g) =>
      g.confirmPlan(const Allocation(needs: 4, wants: 3, savings: 3)));
  final CatalogItem expensive = app.game.content.catalog
      .reduce((CatalogItem a, CatalogItem b) => a.price >= b.price ? a : b);
  await app.act((Game g) => g.declinePurchase(expensive));
  await app.closePeriod();
  return app;
}

void main() {
  // 🔴 rootBundle кеширует не строку, а Future, созданный в зоне того теста,
  // где ассет прочитали впервые. Второй AppState.boot() в том же файле ждёт
  // этот Future вечно — тест виснет без единого сообщения.
  setUp(rootBundle.clear);

  testWidgets('§2.5.12.1 барьер не пускает без верного ответа', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    final AppState app = AppState(MemoryStorage());
    await app.boot();

    await tester.pumpWidget(wrap(app, const AdultScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Этот раздел — для взрослого'), findsOneWidget);
    expect(find.text('О чём спросить'), findsNothing,
        reason: 'до ответа на пример содержимое раздела недоступно');

    // Заведомо неверный ответ: пример строится из чисел 11…39 и 3…9,
    // единица произведением быть не может.
    await tester.enterText(find.byKey(AdultScreen.barrierFieldKey), '1');
    await tester.tap(find.byKey(AdultScreen.gateButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('О чём спросить'), findsNothing);
    expect(find.text('Не сходится. Вот другой пример.'), findsOneWidget,
        reason: '§3.6.5: об ошибке сообщает текст, а не только цвет рамки');

    await passBarrier(tester);
    expect(find.text('О чём спросить'), findsOneWidget);
    expect(find.text('Чему учит приложение'), findsOneWidget);
    // §2.5.13: демонстрационный режим — для экспертной проверки, а эксперт
    // здесь взрослый. Второй вход, кроме настроек.
    expect(find.text('Демонстрационный режим и проверка'), findsOneWidget);
  });

  testWidgets('вход и выход — одна кнопка в одном месте', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    final AppState app = AppState(MemoryStorage());
    await app.boot();

    await tester.pumpWidget(wrap(app, const AdultScreen()));
    await tester.pumpAndSettle();

    final Offset before =
        tester.getCenter(find.byKey(AdultScreen.gateButtonKey));
    expect(find.text('Войти в раздел'), findsOneWidget);

    await passBarrier(tester);

    final Offset after =
        tester.getCenter(find.byKey(AdultScreen.gateButtonKey));
    expect(find.text('Выйти в детский режим'), findsOneWidget);
    expect(after, before,
        reason: 'переключение «родитель ↔ ребёнок» не должно менять место '
            'кнопки — на этом отдельно ловили конкурента');
  });

  testWidgets('§2.5.12.2 в разделе нет негативных оценок ребёнка', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    final AppState app = await weekWithWithdraw(MemoryStorage());

    await tester.pumpWidget(wrap(app, const AdultScreen()));
    await tester.pumpAndSettle();
    await passBarrier(tester);

    const List<String> forbidden = <String>[
      '%',
      'процент',
      'отста',
      'слаб',
      'не справ',
      'ошиб',
      'хуже',
      'неправильн',
      'балл',
    ];
    final Iterable<Text> texts = tester.widgetList<Text>(find.byType(Text));
    expect(texts.length, greaterThan(20));
    for (final Text t in texts) {
      final String? data = t.data;
      if (data == null) continue;
      final String lower = data.toLowerCase();
      for (final String bad in forbidden) {
        expect(lower.contains(bad), isFalse,
            reason: '§2.5.12.2 запрещает негативные оценки ребёнка, '
                'а в тексте «$data» встретилось «$bad»');
      }
    }
  });

  testWidgets('«О чём спросить» зависит от журнала недели', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    const String withdrawQuestion =
        'Спроси: на что не хватило и не жалко ли было брать из копилки?';
    const String declinedQuestion =
        'Спроси, чего не хватило и что решено делать дальше.';

    // Разные ключи: без них Flutter переиспользует State первого экрана
    // вместе с уже снятым барьером, и второй половины теста просто нет.
    final AppState withWithdraw = await weekWithWithdraw(MemoryStorage());
    await tester.pumpWidget(
        wrap(withWithdraw, const AdultScreen(key: ValueKey<String>('a'))));
    await tester.pumpAndSettle();
    await passBarrier(tester);
    expect(find.text(withdrawQuestion), findsOneWidget);
    expect(find.text(declinedQuestion), findsNothing);

    final AppState withDeclined = await weekWithDeclined(MemoryStorage());
    await tester.pumpWidget(
        wrap(withDeclined, const AdultScreen(key: ValueKey<String>('b'))));
    await tester.pumpAndSettle();
    await passBarrier(tester);
    expect(find.text(declinedQuestion), findsOneWidget);
    expect(find.text(withdrawQuestion), findsNothing);
  });

  testWidgets('§3.6 удаление профиля требует подтверждения', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    final MemoryStorage storage = MemoryStorage();
    final AppState app = await weekWithWithdraw(storage);
    expect(app.game.ledger, isNotEmpty);

    await tester.pumpWidget(wrap(app, const AdultScreen()));
    await tester.pumpAndSettle();
    await passBarrier(tester);

    await tester.tap(find.text('Удалить профиль'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить профиль?'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(app.game.ledger, isNotEmpty,
        reason: 'отмена не должна ничего удалять');

    await tester.tap(find.text('Удалить профиль'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();

    expect(app.game.ledger, isEmpty);
    expect(await storage.read('profile'), isNull,
        reason: '§3.5: удаление локальных данных доступно взрослому');
    await flushSnack(tester);
  });

  testWidgets('§3.6 сброс прогресса требует подтверждения и щадит Финни', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    final AppState app = await weekWithWithdraw(MemoryStorage());
    await app.updateProfile(app.game.profile.copyWith(petName: 'Мурзик'));

    await tester.pumpWidget(wrap(app, const AdultScreen()));
    await tester.pumpAndSettle();
    await passBarrier(tester);

    await tester.tap(find.text('Сбросить прогресс'));
    await tester.pumpAndSettle();
    expect(find.text('Сбросить прогресс?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Сбросить'));
    await tester.pumpAndSettle();

    expect(app.game.ledger, isEmpty);
    expect(app.game.profile.petName, 'Мурзик',
        reason: 'сброс прогресса — не удаление питомца');
    await flushSnack(tester);
  });

  testWidgets('§2.5.12.3 взрослый открывает задание, а не монетки', (
    WidgetTester tester,
  ) async {
    tallScreen(tester);
    final AppState app = await weekWithWithdraw(MemoryStorage());
    final int moneyBefore = app.game.snapshot.wallet.everything;

    await tester.pumpWidget(wrap(app, const AdultScreen()));
    await tester.pumpAndSettle();
    await passBarrier(tester);

    await tester.tap(find.text('Открыть дополнительное задание'));
    await tester.pumpAndSettle();

    expect(app.game.profile.parentUnlockedTasks, 1);
    expect(app.game.snapshot.wallet.everything, moneyBefore,
        reason: '§2.1: монетки от взрослого обнулили бы ограниченность '
            'ресурсов');
  });

  test('вопросы ребёнка взрослому не спрашивают про деньги семьи', () {
    // 🔴 Ребёнку, у которого дома не хватает, вопрос «сколько ты
    // зарабатываешь» или «хватает ли нам» делает хуже, а не лучше.
    // Разговор про выбор работает, разговор про нехватку пугает.
    // Совпадение ищется по началу слова, а не по подстроке: «долго»
    // содержит «долг», и грубая проверка ловила безобидный вопрос.
    final List<RegExp> forbidden = <RegExp>[
      RegExp(r'\bзарабатыва'),
      RegExp(r'\bзарплат'),
      RegExp(r'\bхватает ли'),
      RegExp(r'\bсколько денег'),
      RegExp(r'\bсколько у нас'),
      RegExp(r'\bдолг(и|ов|а|у|ом)?\b'),
      RegExp(r'\bкредит'),
      RegExp(r'\bбедн'),
    ];
    for (final ChildQuestion q in ChildQuestions.all) {
      final String text = '${q.ask} ${q.why}'.toLowerCase();
      for (final RegExp bad in forbidden) {
        expect(bad.hasMatch(text), isFalse,
            reason: 'вопрос «${q.ask}» затрагивает нехватку денег в семье');
      }
    }
  });

  test('вопрос недели не меняется при повторном открытии экрана', () {
    for (int period = 1; period <= 12; period++) {
      expect(ChildQuestions.ofPeriod(period).ask,
          ChildQuestions.ofPeriod(period).ask);
    }
    // И за пять игровых недель вопросы не повторяются.
    final Set<String> seen = <String>{};
    for (int period = 1; period <= 5; period++) {
      seen.add(ChildQuestions.ofPeriod(period).ask);
    }
    expect(seen.length, 5);
  });
}
