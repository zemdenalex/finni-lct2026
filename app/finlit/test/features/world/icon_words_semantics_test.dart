import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/jobs/job_board_screen.dart';
import 'package:finlit/features/world/shop/world_shop_screen.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Правило 3А Насти: значок ⚡ 😊 💰 в тексте рисуется картинкой и читается
/// словом. TalkBack не должен произносить имя эмодзи («высоковольтный
/// знак») — ни на карточке еды, ни в причине «Нужно ⚡ 3, есть 2» на доске.
///
/// Уронит: подпись `Semantics` снова собрана из сырой строки со значками.
final RegExp _rawIcon = RegExp('[⚡😊💰]');

void main() {
  setUp(rootBundle.clear);

  testWidgets('магазин: подпись карточки еды — словами', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final WorldGame w = contentDayWorld();
    ok(w.startWeek());
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    await pumpWorldScreen(tester, const WorldShopScreen(), world: w);
    expect(find.bySemanticsLabel(RegExp('Польза: .*настроения')), findsWidgets);
    expect(find.bySemanticsLabel(_rawIcon), findsNothing);
    h.dispose();
  });

  testWidgets('доска: причина «не хватает сил» — словами', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final WorldGame w = contentDayWorld();
    ok(w.startWeek());
    ok(w.plan(needs: w.snapshot.unallocated, wants: 0, goal: 0));
    // Смены, пока какая-то работа не упрётся в ⚡.
    bool short() =>
        w.jobBoard.any((JobOffer o) => o.blockReason?.code == 'job.energy');
    while (!short()) {
      final JobOffer o = w.jobBoard.firstWhere((JobOffer o) => !o.blocked);
      ok(w.completeJob(o.jobId, variant: o.variant, score: 0));
      if (w.pendingLesson case final LessonOffer l) {
        // Доступный вариант: в 7 днях первый («купить») бывает не по
        // карману — тогда урок отказывает, а тест не про урок.
        ok(w.resolveLesson(
            l.choices.firstWhere((LessonChoiceView c) => c.available).id));
      }
    }
    await pumpWorldScreen(tester, const JobBoardScreen(), world: w);
    expect(find.bySemanticsLabel(RegExp('Сейчас не взять: Нужно сил')),
        findsWidgets);
    expect(find.bySemanticsLabel(_rawIcon), findsNothing);
    h.dispose();
  });
}
