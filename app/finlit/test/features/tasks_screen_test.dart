import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/features/tasks/tasks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget wrap(AppState app) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildAppTheme(), home: const TasksScreen()),
    );

Future<AppState> booted() async {
  final AppState app = AppState(MemoryStorage());
  await app.boot();
  return app;
}

void useTallScreen(WidgetTester tester, {double width = 400}) {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Открыть задание по его названию в списке.
///
/// Сначала прокрутка: над списком стоит панель подработки недели, и при
/// крупном шрифте последние задания оказываются ниже окна, а `ListView`
/// невидимое не строит.
Future<void> openTaskNamed(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(find.text(title), 300,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> tapTimes(WidgetTester tester, Finder finder, int times) async {
  for (int i = 0; i < times; i++) {
    await tester.tap(finder);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  // 🔴 rootBundle кеширует не строку, а Future, созданный в зоне предыдущего
  // теста: без сброса второй AppState.boot() в этом файле виснет навсегда.
  setUp(rootBundle.clear);


  testWidgets('§2.5.8.1 задания есть минимум по трём темам',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();
    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    for (final String topic in <String>[
      'Планирую бюджет',
      'Коплю',
      'Покупаю',
    ]) {
      expect(find.text(topic), findsOneWidget,
          reason: '§2.5.8.1: тема «$topic» обязательна');
    }
  });

  testWidgets(
      '§2.5.8.2–3 распределение: объяснение приходит и при неудачном '
      'раскладе', (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();
    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    await openTaskNamed(tester, 'Неделя Финни');
    // Всё в «Хочу» — условие mustCover не выполнено, «лучшего» исхода нет.
    await tapTimes(tester, find.byTooltip('Хочу: больше на одну'), 10);
    expect(find.text('Разложено 10 из 10'), findsOneWidget);

    await tester.tap(find.text('Готово, так и разложим'));
    await tester.pumpAndSettle();

    // §2.5.8.3: объяснение показывается независимо от правильности.
    expect(find.textContaining('Сначала — «Нужное»'), findsOneWidget);
    expect(find.textContaining('Задание выполнено'), findsOneWidget);
    expect(app.game.profile.completedTaskIds, contains('a1_week'));
  });

  testWidgets('«Финни ошибается»: ребёнок правит раскладку, Финни благодарит',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();
    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    await openTaskNamed(tester, 'Финни ошибается');
    // Предложение Финни показано репликой и уже разложено — исправляем его.
    expect(find.textContaining('Я всё положил в «Хочу»'), findsOneWidget);
    expect(find.text('Разложено 10 из 10'), findsOneWidget);

    await tapTimes(tester, find.byTooltip('Хочу: меньше на одну'), 4);
    await tapTimes(tester, find.byTooltip('Нужное: больше на одну'), 4);

    await tester.tap(find.text('Объяснить Финни'));
    await tester.pumpAndSettle();

    // Финни не обижается и не грустит: он благодарит и говорит, что понял.
    expect(find.textContaining('Задание выполнено'), findsOneWidget);
    expect(
        find.textContaining('не обиделся, а научился'), findsOneWidget);

    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Спасибо за подсказку'), findsOneWidget);
  });

  testWidgets('«Дождливый день»: четвёртый вариант — перенести, и он работает',
      (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();
    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    await openTaskNamed(tester, 'Дождливый день');
    expect(find.text('Взять из «Копилка»'), findsOneWidget);
    expect(find.text('Взять из «Хочу»'), findsOneWidget);
    final Finder defer =
        find.text('Обойтись пледом из дома и перенести на следующую неделю');
    expect(defer, findsOneWidget);

    await tester.tap(defer);
    await tester.pumpAndSettle();

    expect(find.textContaining('подушка безопасности'), findsOneWidget,
        reason: '§2.5.8.3: объяснение приходит при любом выборе');
  });

  testWidgets(
      '§2.5.8.2 порядок покупок: стрелки двигают позиции, '
      'монетки кончаются', (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();
    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    await openTaskNamed(tester, 'Собери корзину');
    // Перетаскивание пальцем ненадёжно для семилетки — есть стрелки.
    expect(find.byTooltip('Опустить ниже: Овощи и фрукты'), findsOneWidget);
    await tester.tap(find.byTooltip('Опустить ниже: Овощи и фрукты'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Поднять выше: Овощи и фрукты'), findsOneWidget);

    await tester.tap(find.text('Купить по моему порядку'));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Монетки закончились на позиции'), findsOneWidget);
    expect(find.textContaining('это не ошибка'), findsOneWidget,
        reason: '§2.5.8.3: объяснение приходит при любом порядке');
  });

  testWidgets(
      '§2.5.8.3 число: разбор вычисления показывается при неверном '
      'ответе', (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();
    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    await openTaskNamed(tester, 'Сдача');
    await tapTimes(tester, find.byTooltip('Ответ: больше на одну'), 1);
    await tester.tap(find.text('Ответить'));
    await tester.pumpAndSettle();

    expect(find.textContaining('= 3 монетки'), findsWidgets,
        reason: '§2.5.8.3: разбор вычисления показывается независимо '
            'от правильности');
    expect(find.textContaining('Получается другое число'), findsOneWidget);
    expect(find.textContaining('неправильно'), findsNothing);
    expect(find.textContaining('Задание выполнено'), findsOneWidget,
        reason: 'монетки приходят за попытку, а не за правильный ответ');
  });

  testWidgets(
      '§2.5.8.3 число: разбор вычисления показывается и при верном '
      'ответе', (WidgetTester tester) async {
    useTallScreen(tester);
    final AppState app = await booted();
    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    await openTaskNamed(tester, 'Сдача');
    await tapTimes(tester, find.byTooltip('Ответ: больше на одну'), 3);
    await tester.tap(find.text('Ответить'));
    await tester.pumpAndSettle();

    expect(find.textContaining('= 3 монетки'), findsWidgets);
    expect(find.textContaining('Столько и получается'), findsOneWidget);
    expect(find.textContaining('молодец'), findsNothing);
  });

  testWidgets('задания не переполняются на 360 dp при крупном шрифте',
      (WidgetTester tester) async {
    useTallScreen(tester, width: 360);
    final AppState app = await booted();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const TasksScreen(),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await openTaskNamed(tester, 'Собери корзину');
    expect(tester.takeException(), isNull);
  });
}
