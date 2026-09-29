import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/catalog_item.dart';
import 'package:finlit/domain/models/envelope.dart';
import 'package:finlit/features/progress/progress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Счётчик решений про «хочу» — единственное число в игре, которое
/// рассказывает ребёнку о нём самом. Пока он только считался и нигде
/// не показывался.
void main() {
  // 🔴 rootBundle кеширует Future из зоны предыдущего теста: без сброса
  // второй boot() в файле виснет навсегда и без вывода.
  setUp(rootBundle.clear);

  Future<void> show(WidgetTester tester, AppState app) async {
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const ProgressScreen(),
        onGenerateRoute: (RouteSettings s) => MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<AppState> boot() async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await app.act((Game g) => g.startPeriod());
    await app.act((Game g) => g.confirmPlan(
        Allocation(needs: 0, wants: g.snapshot.wallet.unallocated, savings: 0)));
    return app;
  }

  testWidgets('пока ребёнок ничего не откладывал, блок объясняет механику',
      (WidgetTester tester) async {
    final AppState app = await boot();
    await show(tester, app);
    await tester.scrollUntilVisible(
        find.text('Решения про «хочу»'), 200,
        scrollable: find.byType(Scrollable).first);

    expect(find.textContaining('можно не покупать сразу'), findsOneWidget);
  });

  testWidgets('после недели ожидания видно оба исхода',
      (WidgetTester tester) async {
    final AppState app = await boot();
    final List<CatalogItem> waitable = app.content.catalog
        .where((CatalogItem i) => app.game.canWait(i))
        .toList();
    expect(waitable.length, greaterThanOrEqualTo(2));

    await app.act((Game g) => g.addToWishList(waitable[0]));
    await app.act((Game g) => g.addToWishList(waitable[1]));
    await app.closePeriod();
    await app.act((Game g) => g.startPeriod());
    await app.act((Game g) => g.keepWish(waitable[0]));
    await app.act((Game g) => g.dropWish(waitable[1]));

    await show(tester, app);
    await tester.scrollUntilVisible(
        find.text('Решения про «хочу»'), 200,
        scrollable: find.byType(Scrollable).first);

    expect(find.textContaining('Подождать с покупкой получилось 2 раза'), findsOneWidget);
    expect(find.textContaining('1 — через неделю всё ещё хотелось'),
        findsOneWidget);
    expect(find.textContaining('1 — через неделю уже не хотелось'),
        findsOneWidget);
  });

  testWidgets('🔴 ни один из двух исходов не назван правильным',
      (WidgetTester tester) async {
    // §8.1 оценивает «отсутствие давления, стыда и манипулятивных механик».
    // «Передумал всего 2 раза из 9» — это стыд, выданный за статистику.
    final AppState app = await boot();
    final CatalogItem item =
        app.content.catalog.firstWhere((CatalogItem i) => app.game.canWait(i));
    await app.act((Game g) => g.addToWishList(item));
    await app.closePeriod();
    await app.act((Game g) => g.startPeriod());
    await app.act((Game g) => g.dropWish(item));

    await show(tester, app);
    await tester.scrollUntilVisible(
        find.text('Решения про «хочу»'), 200,
        scrollable: find.byType(Scrollable).first);

    // Смотрю только на свой блок: на экране есть соседние карточки со
    // своими словами, и проверка по всему экрану ловила их.
    final Iterable<String> mine = tester
        .widgetList<Text>(find.descendant(
          of: find.byKey(const ValueKey<String>('wish-tally')),
          matching: find.byType(Text),
        ))
        .map((Text t) => (t.data ?? '').toLowerCase());
    final String text = mine.join(' ');

    for (final String judgement in <String>[
      'всего лишь',
      'только',
      'молодец',
      'к сожалению',
      'зря',
      'правильно',
      'неправильно',
      'ошибка',
    ]) {
      expect(text.contains(judgement), isFalse,
          reason: 'оценка «$judgement» рядом с числом решений ребёнка');
    }
  });
}
