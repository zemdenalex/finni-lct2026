import 'package:finlit/app_state.dart';
import 'package:finlit/core/finni_art.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:finlit/features/pet/pet_create_screen.dart';
import 'package:finlit/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Первый запуск: вернуться некуда, «Готово» уводит на главную.
Widget wrapFirstRun(AppState app) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const PetCreateScreen(),
        routes: <String, WidgetBuilder>{
          AppRoutes.home: (_) =>
              const Scaffold(body: Center(child: Text('главная'))),
        },
      ),
    );

/// Повторная настройка: экран открыт поверх главного (§2.6, способ проверки).
Widget wrapEditing(AppState app) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const PetCreateScreen()),
                ),
                child: const Text('изменить'),
              ),
            ),
          ),
        ),
      ),
    );

/// Крупный предпросмотр — он и показывает выбранную комбинацию.
FinniView preview(WidgetTester tester) => tester.widget<FinniView>(
      find.byWidgetPredicate((Widget w) => w is FinniView && w.size == 168),
    );

void main() {
  // 🔴 rootBundle кеширует не строку, а Future, созданный в зоне предыдущего
  // теста. Второй AppState.boot() в том же файле висит навсегда, и без этой
  // строки отладка выглядит как «тест зависает без причины».
  setUp(rootBundle.clear);

  testWidgets('§2.6 девять комбинаций выбираются и видны в предпросмотре', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await tester.pumpWidget(wrapFirstRun(app));
    await tester.pumpAndSettle();

    final Set<String> seen = <String>{};
    for (final PetSpecies s in PetSpecies.values) {
      for (final PetPalette p in PetPalette.values) {
        await tester.tap(find.text(s.title));
        await tester.pump();
        await tester.tap(find.text(p.title));
        await tester.pump();

        final FinniView shown = preview(tester);
        expect(shown.species, s);
        expect(shown.palette, p);
        seen.add('${s.name}/${p.name}');
      }
    }
    expect(seen.length, 9,
        reason: '§2.6: не менее девяти визуально различимых комбинаций');
  });

  testWidgets('§2.5.2.2 имя предзаполнено, подсказки ставят его без печати', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await tester.pumpWidget(wrapFirstRun(app));
    await tester.pumpAndSettle();

    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'Финни',
        reason: 'печать не должна быть условием прохождения экрана');

    await tester.tap(find.text('Монетка'));
    await tester.pumpAndSettle();
    expect(field.controller?.text, 'Монетка');

    await tester.tap(find.text('Оставить как есть: Финни'));
    await tester.pumpAndSettle();
    expect(field.controller?.text, 'Финни');

    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.text('главная'), findsOneWidget);
    expect(app.game.profile.petName, 'Финни');
  });

  testWidgets('§2.6 повторная настройка меняет питомца и возвращает назад', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await tester.pumpWidget(wrapEditing(app));
    await tester.tap(find.text('изменить'));
    await tester.pumpAndSettle();

    expect(find.text('Изменить Финни'), findsOneWidget);
    expect(find.text('Сохранить'), findsOneWidget);
    expect(find.text('Готово'), findsNothing);

    await tester.tap(find.text('Совёнок'));
    await tester.pump();
    await tester.tap(find.text('Сиреневый'));
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(find.byType(PetCreateScreen), findsNothing,
        reason: 'повторная настройка возвращает туда, откуда пришла');
    expect(app.game.profile.species, PetSpecies.owl);
    expect(app.game.profile.palette, PetPalette.lilac);
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
          home: const PetCreateScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
