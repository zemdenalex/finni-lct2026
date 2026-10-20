import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../../core/feel.dart';
import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';
import '../../../domain/world/fridge_stock.dart';
import '../onboarding/finni_bubble.dart';
import '../pic_text.dart';

/// Реакция Финни (вариант A, выбор Дениса 15.10, `docs/final/pet-react`):
/// после решения Финни на 1,5 с меняет позу, над головой — строка причины;
/// в покое над ним одна строка состояния. Экономику не трогает: только то,
/// что уже есть в снимке мира.

/// Эмоция Финни. Позы нарисованы для радости и усталости; грусть и голод
/// пока обычной позой со строкой (арт — `docs/final/prompty-finni-final.txt`).
enum FinniMood { calm, joy, tired, sad, hungry }

/// Эмоция + одна строка для ребёнка.
@immutable
class FinniReaction {
  const FinniReaction(this.mood, this.line, {this.speech = false});

  final FinniMood mood;
  final String line;

  /// Финни говорит сам (касание — разговор с другом): облачко над ним, а не
  /// строка-плашка.
  final bool speech;

  @override
  bool operator ==(Object other) =>
      other is FinniReaction &&
      other.mood == mood &&
      other.line == line &&
      other.speech == speech;

  @override
  int get hashCode => Object.hash(mood, line, speech);

  @override
  String toString() => 'FinniReaction($mood: $line)';
}

/// Тег позы в `finni_poses` для эмоции и облика; null — обычная поза.
String? finniPoseTag(FinniMood mood, int look) => switch (mood) {
      FinniMood.joy => 'joy-$look',
      FinniMood.tired => 'sleep-$look',
      _ => null,
    };

/// Строка состояния над Финни — всегда, коротко. [tiredBelow] — ⚡ самого
/// дешёвого действия: меньше — Финни устал.
FinniReaction finniStatus(
  ResourceSnapshot s, {
  required bool living,
  required double tiredBelow,
}) {
  // Пустой холодильник — не голод и не штраф (fridge_stock.dart): Финни
  // доест дома в итогах недели. Строка — факт, без «купи».
  if (living && s.mealsPerWeek > 0 && fridgeOf(s).portions == 0) {
    return const FinniReaction(FinniMood.hungry, 'Холодильник пуст');
  }
  if (living && s.energy + 1e-9 < tiredBelow) {
    return const FinniReaction(FinniMood.tired, 'Сил нет, пора спать');
  }
  if (s.happiness <= 30) {
    return const FinniReaction(FinniMood.sad, 'Грустно');
  }
  if (s.happiness >= 70) {
    return const FinniReaction(FinniMood.joy, 'Отличное настроение');
  }
  return const FinniReaction(FinniMood.calm, 'Всё хорошо');
}

/// Что изменилось между двумя снимками — одна реакция или null. Порядок —
/// от главного: рост, цель, голод, усталость, грусть, настроение, еда.
FinniReaction? reactionFor(
  ResourceSnapshot before,
  ResourceSnapshot after, {
  required double tiredBelow,
}) {
  if (after.stage.index > before.stage.index) {
    return const FinniReaction(FinniMood.joy, 'Новый дом!');
  }
  final int toGoal = after.goal - before.goal;
  if (toGoal > 0) return FinniReaction(FinniMood.joy, '+$toGoal на цель!');
  if (after.weekNo > before.weekNo) {
    return const FinniReaction(FinniMood.joy, 'Новая неделя!');
  }
  final int foodBefore = fridgeOf(before).portions;
  final int foodAfter = fridgeOf(after).portions;
  if (foodBefore > 0 && foodAfter == 0) {
    return const FinniReaction(
        FinniMood.hungry, 'Холодильник пуст — доем дома в конце недели');
  }
  if (after.energy < before.energy - 1e-9 && after.energy + 1e-9 < tiredBelow) {
    return const FinniReaction(FinniMood.tired, 'Сил нет: пора спать');
  }
  if (before.want > 0 && after.want == 0 && after.goal == 0) {
    return const FinniReaction(FinniMood.sad, 'На цель ничего не осталось');
  }
  final int mood = after.happiness - before.happiness;
  if (mood >= 5) return const FinniReaction(FinniMood.joy, 'Стало веселее!');
  if (mood <= -5) return const FinniReaction(FinniMood.sad, 'Стало грустнее');
  if (foodAfter > foodBefore) {
    return const FinniReaction(FinniMood.joy, 'Еда есть!');
  }
  return null;
}

/// Строка над головой Финни: в покое — состояние, после решения — причина
/// (ярче, с рамкой), а слова Финни ([FinniReaction.speech]) — облачком.
/// Касания не ловит: Финни под
/// ней нажимается как раньше.
class FinniBadge extends StatelessWidget {
  const FinniBadge({
    super.key,
    required this.status,
    this.reaction,
    this.maxWidth = 236,
    this.leading,
    this.name,
  });

  /// Имя Финни, которое выбрал ребёнок (флаг `room.pet_name`, DEN-25): в
  /// покое строка — «Имя · состояние». null — как сдано, без имени.
  final String? name;

  /// Слева от строки состояния (варианты HUD: сытость или настроение).
  final Widget? leading;

  final FinniReaction status;
  final FinniReaction? reaction;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final FinniReaction? r = reaction;
    final bool motion =
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    final Key labelKey = ValueKey<String>(
      r == null ? 'finni:status' : 'finni:reaction:${r.line}',
    );
    if (r != null && r.speech) {
      // Слова Финни — облачком с хвостиком к нему (как в знакомстве).
      return IgnorePointer(
        child: Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: Gap.xs),
            child: AnimatedSwitcher(
              duration:
                  motion ? const Duration(milliseconds: 150) : Duration.zero,
              child: ConstrainedBox(
                key: labelKey,
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: SpeechBubble(
                  child: PicText(
                    r.line,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: WorldColors.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final Widget label = Container(
      key: labelKey,
      // С именем строка шире: имя до 12 знаков — целиком (DEN-25).
      constraints: BoxConstraints(
          maxWidth: maxWidth + (r == null && name != null ? 90 : 0)),
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 4),
      decoration: BoxDecoration(
        color: WorldColors.panel.withValues(alpha: r == null ? 0.78 : 0.94),
        borderRadius: BorderRadius.circular(WorldRadii.button),
        border: r == null ? null : Border.all(color: _edge(r.mood), width: 2),
      ),
      // PicText: «+1 😊» за разговор — значком приложения, не эмодзи.
      child: _withLeading(
          r == null ? leading : null,
          _withName(
            r == null ? name : null,
            PicText(
              r?.line ?? status.line,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: r == null ? 14 : 15,
                height: 1.2,
                fontWeight: r == null ? FontWeight.w500 : FontWeight.w700,
                color: r == null ? WorldColors.textSoft : WorldColors.text,
              ),
            ),
          )),
    );
    return IgnorePointer(
      child: Semantics(
        liveRegion: r != null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedSwitcher(
              duration:
                  motion ? const Duration(milliseconds: 150) : Duration.zero,
              child: label,
            ),
            const SizedBox(height: Gap.xs),
          ],
        ),
      ),
    );
  }

  static Color _edge(FinniMood m) => switch (m) {
        FinniMood.joy => WorldColors.gold,
        FinniMood.sad || FinniMood.hungry => WorldColors.wants,
        FinniMood.tired => WorldColors.textMute,
        FinniMood.calm => WorldColors.line,
      };
}

/// Строка над Финни — верхним слоем сцены (ревью 16.10): в слое Финни её
/// закрывали кровать и холодильник, когда он за ними, а у края кадра она
/// обрезалась. Каждый кадр берёт прямоугольник Финни ([finniKey]) и ставит
/// [child] над его макушкой, внутри своих границ и не выше [topLimit].
class FinniBadgeLayer extends StatefulWidget {
  const FinniBadgeLayer({
    super.key,
    required this.finniKey,
    required this.child,
    this.topLimit = 0,
  });

  final GlobalKey finniKey;
  final Widget child;
  final double topLimit;

  @override
  State<FinniBadgeLayer> createState() => _FinniBadgeLayerState();
}

class _FinniBadgeLayerState extends State<FinniBadgeLayer>
    with SingleTickerProviderStateMixin {
  final GlobalKey _badge = GlobalKey();
  late final Ticker _ticker;
  Offset? _at;

  /// Когда строка последний раз сдвинулась: стоит 300 мс — тикер спит.
  Duration _movedAt = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _wake();
  }

  @override
  void didUpdateWidget(FinniBadgeLayer old) {
    super.didUpdateWidget(old);
    _wake();
  }

  /// Сцена перестроилась (Финни пошёл, камера поехала): ставим строку после
  /// кадра и, если анимации включены, ведём её за Финни, пока он движется.
  /// С выключенными «Анимациями» тикера нет — комната неподвижна (ТЗ 3.6.7).
  void _wake() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _place();
    });
    final bool motion =
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
            context.motionOn;
    if (motion && !_ticker.isActive) {
      _movedAt = Duration.zero;
      _ticker.start();
    } else if (!motion && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    if (_place()) _movedAt = elapsed;
    if (elapsed - _movedAt > const Duration(milliseconds: 300)) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// true — строка сдвинулась.
  bool _place() {
    final RenderObject? f = widget.finniKey.currentContext?.findRenderObject();
    final RenderObject? me = context.findRenderObject();
    final RenderObject? b = _badge.currentContext?.findRenderObject();
    if (f is! RenderBox || me is! RenderBox || !f.hasSize || !me.hasSize) {
      return false;
    }
    final Rect finni = me.globalToLocal(f.localToGlobal(Offset.zero)) & f.size;
    final Size badge = b is RenderBox && b.hasSize ? b.size : Size.zero;
    final double maxLeft = math.max(0, me.size.width - badge.width);
    final Offset at = Offset(
      (finni.center.dx - badge.width / 2).clamp(0, maxLeft).toDouble(),
      math.max(widget.topLimit, finni.top - badge.height),
    );
    if (_at != null && (at - _at!).distance <= 0.5) return false;
    setState(() => _at = at);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final Offset? at = _at;
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: at?.dx ?? 0,
            top: at?.dy ?? 0,
            child: Opacity(
              // До первого замера — невидима: не мигает в углу.
              opacity: at == null ? 0 : 1,
              child: KeyedSubtree(key: _badge, child: widget.child),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Имя · состояние»: имя одной строкой по своей ширине (до 170 px, дальше
/// «…»), состояние — в остатке строки.
Widget _withName(String? name, Widget status) => name == null
    ? status
    : Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              name,
              key: const ValueKey<String>('finni:name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: WorldColors.text,
              ),
            ),
          ),
          const Text(' · ',
              style: TextStyle(fontSize: 14, color: WorldColors.textSoft)),
          Flexible(child: status),
        ],
      );

Widget _withLeading(Widget? leading, Widget text) => leading == null
    ? text
    : Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          leading,
          const SizedBox(width: Gap.xs + 2),
          Flexible(child: text),
        ],
      );
