import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// §3.6.8: «удаление данных и другие действия, заметно меняющие прогресс,
/// требуют подтверждения». Закрытие недели необратимо — до этих проверок
/// оно случалось от одного касания, и ни один тест этого не замечал,
/// потому что кнопку никто не нажимал через интерфейс.
void main() {
  // 🔴 rootBundle кеширует Future из зоны предыдущего теста: без сброса
  // второй boot() в файле виснет навсегда и без вывода.
  setUp(rootBundle.clear);

  Future<AppState> livingWeek(WidgetTester tester) async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await app.act((Game g) => g.startPeriod());
    await app.act((Game g) => g.confirmPlan(
        Allocation(needs: g.snapshot.wallet.unallocated, wants: 0, savings: 0)));
    expect(app.game.phase, PeriodPhase.living);
    return app;
  }

  Future<void> show(WidgetTester tester, AppState app) async {
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const HomeScreen(),
        // После закрытия недели экран уходит на «Итоги». Здесь важно
        // только то, что переход состоялся, — заглушки достаточно.
        onGenerateRoute: (RouteSettings s) => MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: Center(child: Text(s.name ?? ''))),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// 🔴 `ListView` не строит то, что за экраном: `find.text` вернёт пусто,
  /// а `tap` промолчит. Кнопка недели лежит внизу главного экрана, поэтому
  /// до неё надо доскроллить, а не искать.
  Future<void> tapCloseWeek(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Завершить неделю'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Завершить неделю'));
    await tester.pumpAndSettle();
  }

  testWidgets('неделя не закрывается от одного касания',
      (WidgetTester tester) async {
    final AppState app = await livingWeek(tester);
    await show(tester, app);

    final int periodBefore = app.game.periodNo;
    await tapCloseWeek(tester);

    expect(find.text('Закончить неделю?'), findsOneWidget,
        reason: 'необратимое действие обязано спросить');
    expect(app.game.periodNo, periodBefore,
        reason: 'неделя закрылась до подтверждения');
  });

  testWidgets('отказ в диалоге ничего не меняет', (WidgetTester tester) async {
    final AppState app = await livingWeek(tester);
    await show(tester, app);
    final int before = app.game.periodNo;
    final int entries = app.game.ledger.length;

    await tapCloseWeek(tester);
    await tester.tap(find.text('Ещё не всё'));
    await tester.pumpAndSettle();

    expect(app.game.periodNo, before);
    expect(app.game.ledger.length, entries,
        reason: 'отказ оставил запись в журнале');
  });

  testWidgets('подтверждение закрывает неделю', (WidgetTester tester) async {
    final AppState app = await livingWeek(tester);
    await show(tester, app);
    final int before = app.game.periodNo;

    await tapCloseWeek(tester);
    await tester.tap(find.text('Закончить'));
    await tester.pumpAndSettle();

    expect(app.game.periodNo, before + 1);
  });

  testWidgets('вопрос называет, что именно изменится, а не «вы уверены?»',
      (WidgetTester tester) async {
    final AppState app = await livingWeek(tester);
    await show(tester, app);
    await tapCloseWeek(tester);

    // Семилетка на «вы уверены?» отвечает «да» не читая, поэтому текст
    // обязан называть последствие.
    // Без первой буквы: фраза начинается с заглавной или строчной
    // в зависимости от того, остались ли неразложенные монетки.
    expect(find.textContaining('назад будет нельзя'), findsOneWidget);
    expect(find.textContaining('уверен'), findsNothing);
  });
}
