import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/feel.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../onboarding/onboarding_script.dart';
import '../../../core/widgets.dart';

/// Строка «На неделю: N» над конвертами плана и копилка отдельно от неё.
///
/// Первые телефоны 29.09: Саша не понял, что монеты уже разложены, когда
/// «+» ничего не делал («стоит в этот момент потрясти элемент Пришло»);
/// Денис: «всего 600, в копилке то, что ты не можешь трогать… получше
/// написать». Поэтому:
///
/// * [shake] растёт на каждое «+» без остатка — строка трясётся (с
///   выключенными «Анимациями» — нет, ТЗ 3.6.7) и под ней красное «Всё уже
///   разложено» ([full]);
/// * копилка — отдельной строкой «на цель, тратить нельзя», а не в сумме,
///   которую раскладывают.
///
/// Подписи — `onboarding.json → ui` (`pool`, `pool_full`, `piggy_locked`).
class PlanPool extends StatefulWidget {
  const PlanPool({
    super.key,
    required this.amount,
    required this.saved,
    required this.shake,
    required this.full,
    this.compact = false,
  });

  /// Сколько раскладывают на эту неделю.
  final int amount;

  /// В копилке — на цель, в план не входит.
  final int saved;

  /// Счётчик попыток «+» без остатка: сменился — строка трясётся.
  final int shake;

  /// Показать «Всё уже разложено».
  final bool full;

  /// Альбомная сценка: высоты нет — сумма и копилка только в реплике,
  /// здесь лишь «Всё уже разложено» (оно же и трясётся).
  final bool compact;

  @override
  State<PlanPool> createState() => _PlanPoolState();
}

class _PlanPoolState extends State<PlanPool>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrlOrNull;
  AnimationController get _ctrl => _ctrlOrNull ??= AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360));

  @override
  void didUpdateWidget(PlanPool old) {
    super.didUpdateWidget(old);
    if (widget.shake != old.shake) {
      // Вибрация — где приложение и так откликается (переключатель «Звуки»).
      if (context.motionOn) {
        _ctrl.forward(from: 0);
      }
      if (context.soundOn) HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _ctrlOrNull?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OnboardingScript? s = context.read<OnboardingScript?>();
    String t(String key, String fallback) => s?.ui[key] ?? fallback;
    const TextStyle text = TextStyle(fontSize: 18, color: WorldColors.text);
    final Widget full = Text(
      t('pool_full', 'Всё уже разложено'),
      key: const ValueKey<String>('plan:full'),
      style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700, color: WorldColors.wants),
    );
    final Widget row = widget.compact
        ? full
        : Row(
            children: <Widget>[
              Flexible(child: Text(t('pool', 'На неделю:'), style: text)),
              const SizedBox(width: Gap.sm),
              Coins(widget.amount, size: 22),
            ],
          );
    final AnimationController? c = _ctrlOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (!widget.compact || widget.full)
          KeyedSubtree(
            key: const ValueKey<String>('plan:pool'),
            child: c == null
                ? row
                : AnimatedBuilder(
                    animation: c,
                    builder: (BuildContext _, Widget? child) {
                      // Три затухающих качания влево-вправо.
                      final double v = c.value;
                      final double dx =
                          c.isAnimating ? 8 * (1 - v) * _wave(v) : 0;
                      return Transform.translate(
                          offset: Offset(dx, 0), child: child);
                    },
                    child: row,
                  ),
          ),
        if (widget.full && !widget.compact) full,
        if (widget.saved > 0 && !widget.compact)
          Text(
            (s?.ui['piggy_locked'] ??
                    'В копилке: {saved} — на цель, тратить нельзя')
                .replaceAll('{saved}', '${widget.saved}'),
            key: const ValueKey<String>('plan:piggy'),
            // Вторая строка — мельче, в одну строку на 360 dp.
            style: const TextStyle(fontSize: 14, color: WorldColors.textSoft),
          ),
      ],
    );
  }

  static double _wave(double v) {
    // sin без dart:math: треугольная волна на 3 периода.
    final double p = (v * 3) % 1;
    return p < 0.25
        ? p * 4
        : p < 0.75
            ? 2 - p * 4
            : p * 4 - 4;
  }
}
