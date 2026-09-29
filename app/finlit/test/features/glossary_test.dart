import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/features/glossary/glossary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget wrap(AppState app) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const GlossaryScreen(),
      ),
    );

void main() {
  // 🔴 rootBundle кеширует не строку, а Future, созданный в зоне предыдущего
  // теста. Второй AppState.boot() в том же файле висит навсегда, и без этой
  // строки отладка выглядит как «тест зависает без причины».
  setUp(rootBundle.clear);

  testWidgets(
      '§2.5.11.2 словарик показывает термины, в том числе не встреченные', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    // Список доступен целиком: и открытые термины, и ещё не встреченные.
    expect(find.text('Конверт'), findsOneWidget);
    expect(find.text('Бюджет'), findsOneWidget);
    expect(find.text('Подушка безопасности'), findsOneWidget);
    expect(find.text('откроется, когда встретится в игре'), findsWidgets);
  });

  testWidgets('текст не встреченного термина всё равно открывается по тапу', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    // Свежий профиль ещё не встречал «Бюджет».
    expect(app.game.profile.unlockedTerms.contains('budget'), isFalse);

    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    expect(find.textContaining('на что ты их разделишь'), findsNothing);
    await tester.tap(find.text('Бюджет'));
    await tester.pumpAndSettle();
    expect(find.textContaining('на что ты их разделишь'), findsOneWidget,
        reason: 'прятать знание от ребёнка незачем');
  });

  testWidgets('§3.1.2 не переполняется на 360 dp при увеличенном шрифте', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildAppTheme(),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const GlossaryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // Ловит (критерии ночи §8 п. 3): слово из урока не отмечено в Словарике
  // или не поднято наверх.
  testWidgets('слова из уроков — наверху и с пометкой «изучено в уроке»',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildAppTheme(),
        home:
            const GlossaryScreen(allOpen: true, learned: <String>{'estimate'}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('glossary:learned:estimate')),
        findsOneWidget);
    expect(tester.getTopLeft(find.text('Смета')).dy,
        lessThan(tester.getTopLeft(find.text('Бюджет')).dy));
  });
}
