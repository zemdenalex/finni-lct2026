import 'package:flutter/material.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/art/sprite_anim.dart';
import '../../../core/theme.dart';
import '../../../domain/world/contract.dart';
import '../home/world_hud.dart';
import '../pic_text.dart';
import '../world_help.dart';
import '../world_layout.dart';
import '../world_routes.dart';
import '../world_state.dart';
import '../../../core/world_theme.dart';

/// S10 · Событие недели (`docs/game/events.md`): ситуация, 2–3 варианта,
/// после выбора — объяснение Финни и что изменилось.
///
/// Событие — `World.pendingEvent` (A10). У каждого варианта **до выбора**
/// видно, что изменится (`preview.text`); недоступный вариант показан, но
/// погашен и подписан причиной. Выбор — `resolveEvent` через
/// [WorldState.act]; на итоге — фраза Финни и настоящие изменения из
/// [WorldResult]. События нет — спокойная заглушка и дорога назад.
class EventScreen extends StatefulWidget {
  const EventScreen({super.key});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  /// Событие, в котором сделан выбор: после [World.resolveEvent] мир его
  /// уже не отдаёт, а экран показывает итог на его фоне.
  PendingEvent? _resolved;

  /// Сделанный выбор и итог мира по нему.
  ({PendingEventChoice choice, WorldResult result})? _outcome;

  /// Мир отказал (вариант погас между показом и нажатием).
  WorldResult? _refusal;

  void _back() {
    final NavigatorState nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed(WorldRoutes.city);
    }
  }

  void _help() {
    showHelp(
        context,
        'Что здесь?',
        'Это событие недели — случай из жизни Финни.\n\n'
            'Правильного ответа нет: выбери, как поступил бы ты. После '
            'выбора Финни расскажет, что из этого вышло.');
  }

  void _choose(PendingEvent ev, PendingEventChoice c) {
    final WorldState? ws = maybeWorldState(context, listen: false);
    if (ws == null) return;
    final WorldResult r = ws.act((World w) => w.resolveEvent(c.id));
    setState(() {
      if (r.ok) {
        _resolved = ev;
        _outcome = (choice: c, result: r);
        _refusal = null;
      } else {
        _refusal = r;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final WorldState? ws = maybeWorldState(context);
    final PendingEvent? ev = _resolved ?? ws?.world.pendingEvent;
    final String finni = ws?.finniName ?? 'Финни';
    final ({PendingEventChoice choice, WorldResult result})? outcome = _outcome;
    final WorldResult? refusal = _refusal;
    final bool land = WorldLayout.isLandscape(context);

    /// Варианты выбора или, после выбора, что из этого вышло.
    List<Widget> side(PendingEvent ev, {required bool compact}) => outcome !=
            null
        ? <Widget>[
            _Outcome(
                choice: outcome.choice,
                result: outcome.result,
                finni: finni,
                onDone: _back)
          ]
        : <Widget>[
            if (compact)
              const Padding(
                padding: EdgeInsets.only(bottom: Gap.sm),
                child: Text('Как поступит Финни?',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            if (refusal != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Text(
                    refusal.nextStep == null
                        ? refusal.reason
                        : '${refusal.reason} ${refusal.nextStep}',
                    key: const ValueKey<String>('event:refusal'),
                    style:
                        const TextStyle(fontSize: 16, color: WorldColors.text)),
              ),
            for (final PendingEventChoice c in ev.choices)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: _ChoiceButton(
                  choice: c,
                  compact: compact,
                  onPressed: () => _choose(ev, c),
                ),
              ),
          ];

    return Scaffold(
      backgroundColor: WorldColors.night,
      appBar: AppBar(
        // Альбомная — основная: низкая шапка, высота нужна тексту.
        toolbarHeight: land ? 48 : null,
        leading: IconButton(
          key: const ValueKey<String>('event:back'),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Назад',
          onPressed: _back,
        ),
        automaticallyImplyLeading: false,
        title: const Text('Событие'),
        actions: <Widget>[
          HelpButton(
            key: const ValueKey<String>('event:help'),
            onPressed: _help,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (ws != null) WorldHud(snapshot: ws.snapshot),
            Expanded(
              child: ev == null
                  ? _Empty(onBack: _back)
                  : land
                      // Альбомная: ситуация с картинкой здания слева, выбор
                      // (а после него — последствия) справа.
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Expanded(
                              flex: 11,
                              child: SingleChildScrollView(
                                key: const ValueKey<String>('event:situation'),
                                padding: const EdgeInsets.fromLTRB(
                                    Gap.md, Gap.sm, Gap.sm, Gap.md),
                                child: _Situation(event: ev, art: true),
                              ),
                            ),
                            Expanded(
                              flex: 9,
                              child: SingleChildScrollView(
                                key: const ValueKey<String>('event:side'),
                                padding: const EdgeInsets.fromLTRB(
                                    Gap.sm, Gap.sm, Gap.md, Gap.md),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: side(ev, compact: true),
                                ),
                              ),
                            ),
                          ],
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(
                              Gap.md, Gap.sm, Gap.md, Gap.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _Situation(event: ev, art: false),
                              const SizedBox(height: Gap.md),
                              ...side(ev, compact: false),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ситуация события: «!», заголовок, текст; в альбомной — ещё и здание.
class _Situation extends StatelessWidget {
  const _Situation({required this.event, required this.art});

  final PendingEvent event;
  final bool art;

  @override
  Widget build(BuildContext context) {
    final Widget title = Semantics(
      header: true,
      child: Text(event.title,
          key: const ValueKey<String>('event:title'),
          style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: WorldColors.text)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment:
              art ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: <Widget>[
            if (art) ...<Widget>[
              _BuildingArt(event.buildingId),
              const SizedBox(width: Gap.sm),
            ] else ...<Widget>[
              const Icon(Icons.priority_high_rounded, color: WorldColors.wants),
              const SizedBox(width: Gap.xs),
            ],
            Expanded(child: title),
          ],
        ),
        const SizedBox(height: Gap.sm),
        Text(event.text,
            key: const ValueKey<String>('event:text'),
            style: const TextStyle(fontSize: 18)),
      ],
    );
  }
}

/// Здание, где случилось событие, с «!» в углу. Арт — из реестра; пока он
/// читается или если его нет — значок «!».
class _BuildingArt extends StatelessWidget {
  const _BuildingArt(this.buildingId);

  final String buildingId;

  static const double size = 88;

  @override
  Widget build(BuildContext context) {
    const Widget mark = CircleAvatar(
      radius: 14,
      backgroundColor: WorldColors.wants,
      child: Icon(Icons.priority_high_rounded, color: Colors.white, size: 20),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: FutureBuilder<AssetRegistry>(
                future: AssetRegistry.load(),
                builder: (BuildContext c, AsyncSnapshot<AssetRegistry> s) {
                  final String? path = s.data?.building(buildingId);
                  if (path == null) {
                    return const DecoratedBox(
                      decoration: BoxDecoration(
                          color: WorldColors.wantsBg, shape: BoxShape.circle),
                    );
                  }
                  return Image.asset(path,
                      fit: BoxFit.contain,
                      filterQuality: artFilter(artDensity(path)),
                      errorBuilder: (_, __, ___) => const SizedBox.shrink());
                },
              ),
            ),
            const Positioned(top: 0, right: 0, child: mark),
          ],
        ),
      ),
    );
  }
}

/// Вариант выбора: подпись и **до выбора** — что изменится. Недоступный
/// вариант виден, но погашен, и под ним — почему.
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton(
      {required this.choice, required this.compact, required this.onPressed});

  final PendingEventChoice choice;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final PendingEventChoice c = choice;
    final BlockReason? block = c.blockReason;
    return OutlinedButton(
      key: ValueKey<String>('event:choice:${c.id}'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(TapSize.min),
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(
            horizontal: compact ? Gap.sm : Gap.md, vertical: Gap.sm),
      ),
      onPressed: block == null ? onPressed : null,
      child: Row(
        children: <Widget>[
          Icon(block == null
              ? Icons.chevron_right_rounded
              : Icons.lock_outline_rounded),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(c.label, style: const TextStyle(fontSize: 16)),
                PicText(c.preview.text,
                    key: ValueKey<String>('event:preview:${c.id}'),
                    style: const TextStyle(
                        fontSize: 15, color: WorldColors.textSoft)),
                if (block != null)
                  Text(
                      block.nextStep == null
                          ? block.text
                          : '${block.text} ${block.nextStep}',
                      key: ValueKey<String>('event:blocked:${c.id}'),
                      style: const TextStyle(
                          fontSize: 16, color: WorldColors.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Событий сейчас нет: неделя ещё не идёт или выбор этой недели уже
/// сделан.
class _Empty extends StatelessWidget {
  const _Empty({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          key: const ValueKey<String>('event:empty'),
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('Сейчас ничего не случилось',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: Gap.sm),
              const Text(
                  'События приходят, когда неделя идёт. Загляни в город: '
                  'где «!» — там что-то ждёт.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16)),
              const SizedBox(height: Gap.md),
              FilledButton(
                key: const ValueKey<String>('event:empty:back'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(TapSize.min)),
                onPressed: onBack,
                child: const Text('Назад'),
              ),
            ],
          ),
        ),
      );
}

class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.choice,
    required this.result,
    required this.finni,
    required this.onDone,
  });

  final PendingEventChoice choice;
  final WorldResult result;
  final String finni;
  final VoidCallback onDone;

  /// Что изменилось — числа итога мира. Добавки к счёту недели в итоге
  /// нет, она берётся из превью выбранного варианта.
  String get _changes {
    final EffectPreview real = EffectPreview(
      coins: result.coins,
      goal: result.goal,
      energy: result.energy,
      happiness: result.happiness,
      weeklyBill: choice.preview.weeklyBill,
    );
    return real.isEmpty ? 'числа не изменились.' : real.text;
  }

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey<String>('event:outcome'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(Gap.sm + Gap.xs),
            decoration: BoxDecoration(
              color: WorldColors.needsBg,
              borderRadius: BorderRadius.circular(Radii.chip),
              border: Border.all(color: WorldColors.needs),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.check_circle_rounded,
                        color: WorldColors.needs),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text('Выбор: ${choice.label}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Text('$finni: «${result.reason}»',
                    key: const ValueKey<String>('event:finni'),
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(height: Gap.sm),
                Text('Что изменилось: $_changes',
                    key: const ValueKey<String>('event:changes'),
                    style: const TextStyle(
                        fontSize: 16, color: WorldColors.textSoft)),
                if (result.nextStep != null) ...<Widget>[
                  const SizedBox(height: Gap.sm),
                  Text('Что дальше: ${result.nextStep}',
                      key: const ValueKey<String>('event:next'),
                      style: const TextStyle(fontSize: 16)),
                ],
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          FilledButton(
            key: const ValueKey<String>('event:done'),
            onPressed: onDone,
            child: const Text('Дальше'),
          ),
        ],
      );
}
