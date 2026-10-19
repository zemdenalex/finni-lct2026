import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/phrases.dart';
import '../../../domain/world/contract.dart';
import '../../../domain/world/world_game.dart';
import '../home/world_hud.dart';
import '../pic_text.dart';
import '../world_layout.dart';
import '../world_state.dart';
import '../world_dock.dart';

/// Экран наград открывается из «Прогресса», когда в мире включены награды
/// дней — флаг `achievements_days` в `economy.json` (он же добавляет награды
/// 7 дней). Отдельного флага сборки нет: с ним флаг из файла был не виден
/// игроку (баг-прогон 18.10). Не движок (фейк экранов) — экрана нет.
bool achievementsScreenOn(World world) =>
    world is WorldGame && world.config.achievementsDays;

/// Награды списком: какие получены, какие ещё нет, что
/// сделать и когда выдана. Данные только [ResourceSnapshot.achievements]:
/// правила и получение живут в журнале, у экрана своего хранилища нет.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  /// Строка про условие: что сделать и сколько уже набрано.
  static String conditionLine(AchievementView v) => switch (v.status) {
        AchievementStatus.earned => v.def.hint,
        _ => '${v.def.hint} · ${v.progress} из ${v.target}',
      };

  /// Что даёт награда (DEN-32): бафф словами; без баффа — null.
  static String? effectLine(AchievementEffect? e) => switch (e) {
        MoodBuff(:final int happiness, :final int days) =>
          'Даёт +$happiness 😊 на $days ${Phrases.dayWord(days)}',
        EnergyMaxBuff(:final double value) =>
          'Даёт +${energyShown(value)} ⚡ к запасу сил навсегда',
        null => null,
      };

  /// Строка про выдачу; у невыданной награды её нет.
  static String? earnedLine(AchievementView v) {
    final int? week = v.earnedWeek;
    if (week == null) return null;
    final int? day = v.earnedDay;
    return day == null
        ? 'Получено на неделе $week'
        : 'Получено: день $day недели $week';
  }

  @override
  Widget build(BuildContext context) =>
      WithDock(current: DockSection.progress, child: _screen(context));

  /// Экран без нижнего меню ([WithDock] — снаружи).
  Widget _screen(BuildContext context) {
    final ResourceSnapshot now = context.watch<WorldState>().snapshot;
    final List<AchievementView> all = now.achievements;
    final int earned = all
        .where((AchievementView v) => v.status == AchievementStatus.earned)
        .length;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: WorldLayout.isLandscape(context) ? 48 : null,
        leading: IconButton(
          key: const ValueKey<String>('achievements:back'),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Назад',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        automaticallyImplyLeading: false,
        title: const Text('Награды'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WorldHud(snapshot: now),
            Expanded(
              child: ListView(
                key: const ValueKey<String>('achievements:list'),
                padding: const EdgeInsets.all(Gap.md),
                children: <Widget>[
                  Text(
                    key: const ValueKey<String>('achievements:count'),
                    'Получено $earned из ${all.length}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: WorldColors.text,
                    ),
                  ),
                  for (final AchievementView v in all) ...<Widget>[
                    const SizedBox(height: Gap.sm),
                    _AchievementTile(view: v),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.view});

  final AchievementView view;

  @override
  Widget build(BuildContext context) {
    final AchievementView v = view;
    final bool got = v.status == AchievementStatus.earned;
    final String? when = AchievementsScreen.earnedLine(v);
    final String? effect = AchievementsScreen.effectLine(v.def.effect);
    return Semantics(
      container: true,
      child: Container(
        key: ValueKey<String>('achievements:${v.def.id}'),
        padding: const EdgeInsets.all(Gap.sm + Gap.xs),
        decoration: BoxDecoration(
          color: WorldColors.panel,
          borderRadius: BorderRadius.circular(WorldRadii.tile),
          border: Border.all(
            color: got ? WorldColors.goal : WorldColors.line,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PicText(
              got ? '🏆 ${v.def.title}' : '🔒 ${v.def.title}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: WorldColors.text,
              ),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              AchievementsScreen.conditionLine(v),
              style: const TextStyle(fontSize: 16, color: WorldColors.textSoft),
            ),
            if (effect != null) ...<Widget>[
              const SizedBox(height: Gap.xs),
              PicText(
                key: ValueKey<String>('achievements:effect:${v.def.id}'),
                effect,
                style: const TextStyle(fontSize: 16, color: WorldColors.text),
              ),
            ],
            if (when != null) ...<Widget>[
              const SizedBox(height: Gap.xs),
              Text(
                when,
                style: const TextStyle(fontSize: 16, color: WorldColors.text),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
