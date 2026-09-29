// ignore_for_file: deprecated_member_use
// hasFlag устарел в 3.47, но flagsCollection нет в 3.41 на CI.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// `androidTapTargetGuideline` (48 × 48 dp, ТЗ 3.6.3) — но без его пропуска
/// целей, касающихся края экрана.
///
/// 🔴 Штатное правило молча пропускает всё, что касается края окна: оно
/// рассчитано на прокрутку, где такой узел может быть обрезан. В мире игры
/// у края стоят HUD и нижняя панель комнаты — ровно те кнопки, в которые
/// ребёнок тычет чаще всего, и их штатная проверка не видела вовсе
/// (проверено: панель высотой 40 dp проходила её зелёной).
///
/// Пропуск у края прокручиваемой области оставлен: там узел и правда
/// может быть обрезан прокруткой.
class EdgeTapTargetGuideline extends AccessibilityGuideline {
  const EdgeTapTargetGuideline({this.size = const Size(48, 48)});

  final Size size;

  @override
  String get description => 'Tappable objects should be at least $size, '
      'including those touching the screen edge';

  @override
  FutureOr<Evaluation> evaluate(WidgetTester tester) {
    Evaluation result = const Evaluation.pass();
    for (final RenderView view in tester.binding.renderViews) {
      result += _traverse(
          view.flutterView, view.owner!.semanticsOwner!.rootSemanticsNode!);
    }
    return result;
  }

  Evaluation _traverse(ui.FlutterView view, SemanticsNode node) {
    Evaluation result = const Evaluation.pass();
    node.visitChildren((SemanticsNode child) {
      result += _traverse(view, child);
      return true;
    });
    if (node.isMergedIntoParent) return result;
    final SemanticsData data = node.getSemanticsData();
    if ((!data.hasAction(ui.SemanticsAction.tap) &&
            !data.hasAction(ui.SemanticsAction.longPress)) ||
        data.hasFlag(ui.SemanticsFlag.isHidden) ||
        data.hasFlag(ui.SemanticsFlag.isLink)) {
      return result;
    }
    Rect bounds = node.rect;
    SemanticsNode? current = node;
    while (current != null) {
      final Matrix4? t = current.transform;
      if (t != null) bounds = MatrixUtils.transformRect(t, bounds);
      if (current.hasFlag(ui.SemanticsFlag.hasImplicitScrolling) &&
          _atBoundary(bounds, current.rect)) {
        return result;
      }
      current = current.parent;
    }
    final Size found = bounds.size / view.devicePixelRatio;
    if (found.width < size.width - precisionErrorTolerance ||
        found.height < size.height - precisionErrorTolerance) {
      result += Evaluation.fail('«${data.label}» ($node): '
          'expected tap target of at least $size, found $found');
    }
    return result;
  }

  static bool _atBoundary(Rect child, Rect parent) =>
      !(child.left - parent.left > 0.001 &&
          parent.right - child.right > 0.001 &&
          child.top - parent.top > 0.001 &&
          parent.bottom - child.bottom > 0.001);
}

/// Цели касания ≥ 48 dp, в том числе у края экрана.
const AccessibilityGuideline edgeTapTargetGuideline = EdgeTapTargetGuideline();
