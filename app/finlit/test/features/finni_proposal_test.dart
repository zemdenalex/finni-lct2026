import 'package:finlit/app_state.dart';
import 'package:finlit/core/theme.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/demo_autopilot.dart';
import 'package:finlit/domain/game.dart';
import 'package:finlit/domain/models/pet.dart';
import 'package:finlit/features/plan/plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Стадия «Хранитель копилки» обещает: «Финни сам раскладывает монетки
/// по конвертам». До 23.09 это была только строка описания стадии.
void main() {
  setUp(rootBundle.clear);

  Future<AppState> demoAt(PetStage stage) async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    await app.setDemoMode(true);
    await app.act((Game g) {
      DemoAutopilot.playTo(g, stage);
      return const ActionResult(title: '', text: '', nextStep: '');
    });
    return app;
  }

  Widget wrap(AppState app) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(theme: buildAppTheme(), home: const PlanScreen()),
      );

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test('автопилот демо-режима доходит до стадии честными неделями', () async {
    final AppState app = await demoAt(PetStage.planner);
    final Game g = app.game;
    expect(g.snapshot.stage, PetStage.planner);
    expect(g.phase, PeriodPhase.planning,
        reason: 'следующая неделя открыта: карманные пришли, плана нет');
    expect(g.profile.plans.length, greaterThanOrEqualTo(3));
  });

  test('на игре ребёнка автопилот не работает', () async {
    final AppState app = AppState(MemoryStorage());
    await app.boot();
    expect(() => DemoAutopilot.playTo(app.game, PetStage.planner),
        throwsStateError);
  });

  testWidgets('«Хранитель»: Финни предлагает раскладку, решает ребёнок',
      (WidgetTester tester) async {
    tall(tester);
    final AppState app = await demoAt(PetStage.planner);
    final int available = app.game.snapshot.wallet.unallocated;
    final SemanticsHandle handle = tester.ensureSemantics();

    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();

    expect(find.textContaining('Я разложил, как обычно делаешь ты'),
        findsOneWidget);
    expect(find.text('Разложить как на прошлой неделе'), findsNothing,
        reason: 'на этой стадии вместо повтора — раскладка Финни');

    await tester.tap(find.text('Взять раскладку Финни'));
    await tester.pumpAndSettle();

    expect(app.game.currentPlan, isNull,
        reason: 'раскладка заполняет черновик, но не подтверждает план');
    expect(
        find.bySemanticsLabel(RegExp(r'^Осталось разложить: 0 ')),
        findsOneWidget,
        reason: 'раскладка Финни раскладывает все $available');
    handle.dispose();
  });

  testWidgets('до «Хранителя» Финни раскладку не предлагает',
      (WidgetTester tester) async {
    tall(tester);
    final AppState app = await demoAt(PetStage.saver);
    await tester.pumpWidget(wrap(app));
    await tester.pumpAndSettle();
    expect(find.text('Взять раскладку Финни'), findsNothing);
  });
}
