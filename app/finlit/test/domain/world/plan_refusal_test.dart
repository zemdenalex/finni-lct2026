import 'package:finlit/domain/world/contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

/// Ловит (ТЗ 2.5.5.2): план больше доступного проходит (деньги из воздуха)
/// или отказ всё-таки что-то записал — конверты, фазу, план недели.
void main() {
  forEachWorld((WorldKind kind) {
    test('план больше доступного — отказ plan.too_much, ничего не записано',
        () {
      final World w = kind.make();
      ok(w.startWeek());
      final ResourceSnapshot before = w.snapshot;
      final int have = before.unallocated;
      expect(have, greaterThan(0), reason: 'настройка: есть что раскладывать');

      final WorldResult r = w.plan(needs: have, wants: 0, goal: 1);
      expect(r.ok, isFalse);
      expect(r.reasonCode, 'plan.too_much');

      final ResourceSnapshot after = w.snapshot;
      expect((
        after.unallocated,
        after.need,
        after.want,
        after.goal,
        after.free
      ), (
        before.unallocated,
        before.need,
        before.want,
        before.goal,
        before.free
      ));
      expect(w.phase, WeekPhase.planning);
      expect(w.weekHistory.last.planMade, isFalse);

      // Ровно всё доступное — можно.
      ok(w.plan(needs: have, wants: 0, goal: 0));
      expect(w.phase, WeekPhase.living);
      expect(w.snapshot.unallocated, 0);
    });
  });
}
