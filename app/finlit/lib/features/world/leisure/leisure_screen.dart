import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../domain/world/contract.dart';
import '../day_end.dart';
import '../home/world_hud.dart';
import '../world_help.dart';
import '../shop/shop_kit.dart' show catalogOf, isPhaseBlock, requirementMet;
import '../world_layout.dart';
import '../world_routes.dart';
import '../world_state.dart';
import '../../../core/world_theme.dart';
import '../pic_text.dart';
import '../world_dock.dart';

/// S8 · Парк / Кино и кафе (`docs/game/leisure.md`).
///
/// Место приходит аргументом маршрута из города: `'park'` или `'cinema'`
/// (кино и кафе — одно здание). Его варианты — первыми, остальные ниже.
///
/// Цена, ⚡ и 😊 до выбора — из каталога мира ([World.catalog]): ⚡ там уже
/// с поправкой на 😊 и +1 «на жизнь», поэтому каталог читается заново при
/// каждой перерисовке. Можно ли пойти — решает мир ([World.canDo]): кнопка
/// гаснет, а на карточке — его причина. Итог и «почему» — из [WorldResult].
class LeisureScreen extends StatefulWidget {
  const LeisureScreen({super.key, this.place});

  /// `'park'` / `'cinema'`; null — из аргумента маршрута.
  final String? place;

  /// Порядок вариантов для места: сначала то, что есть в этом здании.
  static List<String> orderFor(String? place) => switch (place) {
        'cinema' => const <String>['cinema', 'cafe', 'park', 'pet_play'],
        _ => const <String>['park', 'pet_play', 'cafe', 'cinema'],
      };

  static String titleFor(String? place) => switch (place) {
        'park' => 'Парк',
        'cinema' => 'Кино и кафе',
        _ => 'Отдых',
      };

  /// Где проходит досуг — подпись на карточке.
  static String whereOf(String kind) => switch (kind) {
        'park' => 'в парке',
        'cafe' || 'cinema' => 'в «Кино и кафе»',
        _ => 'дома, в комнате',
      };

  static Pic iconOf(String kind) => switch (kind) {
        'park' => Pic.leaf,
        'cafe' => Pic.cake,
        'cinema' => Pic.play,
        _ => Pic.paw,
      };

  @override
  State<LeisureScreen> createState() => _LeisureScreenState();
}

class _LeisureScreenState extends State<LeisureScreen> {
  WorldResult? _result;
  String? _resultKind;

  /// День и силы до отдыха: если отдых закончил день (силы ниже самого
  /// дешёвого дела), внизу — строка «Уже утро» ([DayEndStrip]), как на
  /// итоге смены (путь ребёнка rc-7d, D2 и k43).
  int? _dayBefore;
  double _energyBefore = 0;

  String? get _place {
    if (widget.place != null) return widget.place;
    final Object? a = ModalRoute.of(context)?.settings.arguments;
    return a is String ? a : null;
  }

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
        'Здесь Финни отдыхает: отдых тратит силы, но поднимает '
            'настроение. Платим из «Хочу», потом из заработка, а парк — '
            'бесплатно. Если отдыхать очень много, радости становится меньше.');
  }

  void _go(String kind) {
    final WorldState ws = context.read<WorldState>();
    final int dayBefore = ws.snapshot.dayInWeek;
    final double energyBefore = ws.snapshot.energy;
    final WorldResult r = ws.act((World w) => w.leisure(kind));
    setState(() {
      _result = r;
      _resultKind = kind;
      _dayBefore = dayBefore;
      _energyBefore = energyBefore;
    });
  }

  @override
  Widget build(BuildContext context) =>
      WithDock(current: DockSection.city, child: _screen(context));

  /// Экран без нижнего меню ([WithDock] — снаружи).
  Widget _screen(BuildContext context) {
    final WorldState ws = context.watch<WorldState>();
    // Каталог живой: ⚡ досуга зависит от 😊 — читаем при каждой перерисовке.
    final World w = ws.world;
    final ResourceSnapshot snap = ws.snapshot;
    final WeekPhase phase = ws.phase;
    final String? place = _place;
    final List<WorldCatalogItem> all =
        catalogOf(w, WorldCatalogCategory.leisure);
    final List<String> order = LeisureScreen.orderFor(place);
    int rank(WorldCatalogItem i) {
      final int r = order.indexOf(i.id);
      return r < 0 ? order.length : r;
    }

    // Порядок — по зданию; то, что пока закрыто (питомца нет), — запиской.
    final List<WorldCatalogItem> sorted = <WorldCatalogItem>[...all]
      ..sort((WorldCatalogItem a, WorldCatalogItem b) => rank(a) - rank(b));
    final List<WorldCatalogItem> options = <WorldCatalogItem>[
      for (final WorldCatalogItem i in sorted)
        if (requirementMet(w, i)) i,
    ];
    final List<WorldCatalogItem> locked = <WorldCatalogItem>[
      for (final WorldCatalogItem i in sorted)
        if (!requirementMet(w, i)) i,
    ];
    final String? banner = switch (phase) {
      WeekPhase.living => null,
      WeekPhase.review =>
        'Неделя кончилась. Отдохнём на следующей — сначала итоги дома.',
      _ => 'Отдых — после плана недели. Вернись домой и нажми «План».',
    };

    final bool land = WorldLayout.isLandscape(context);
    final ({String short, String full})? night = dayEndText(
        result: _result,
        dayBefore: _dayBefore,
        energyBefore: _energyBefore,
        now: snap);
    final Widget? result = _result == null
        ? null
        : _ResultCard(
            result: _result!,
            reason: night?.full,
            title: w.catalogItem(_resultKind!)?.title ?? '');
    const TextStyle body = TextStyle(fontSize: 16, color: WorldColors.text);
    final Widget? bannerNote = banner == null
        ? null
        : _Note(
            key: const ValueKey<String>('leisure:banner'),
            icon: Icons.event_note_rounded,
            text: banner);
    const Widget intro = Text(
        'Работать или отдохнуть — решаешь ты. '
        'Цена и радость видны заранее.',
        key: ValueKey<String>('leisure:intro'),
        style: TextStyle(fontSize: 16, color: WorldColors.text));
    // Закрытый вариант — короткая записка: условие из каталога.
    final List<Widget> lockedNotes = <Widget>[
      for (final WorldCatalogItem i in locked)
        _Note(
            key: ValueKey<String>(i.id == 'pet_play'
                ? 'leisure:pet_note'
                : 'leisure:locked:${i.id}'),
            icon: i.id == 'pet_play' ? Icons.pets_rounded : Icons.lock_rounded,
            text: '${i.requiresText ?? 'Пока закрыто'} — тогда '
                '«${i.title}»${i.price == 0 ? ', бесплатно' : ''}.'),
    ];
    Widget card(WorldCatalogItem e) => _OptionCard(
          entry: e,
          block: w.canDo(WorldAction.leisure, id: e.id),
          compact: land,
          onGo: () => _go(e.id),
        );

    return Scaffold(
      appBar: AppBar(
        // Альбомная — основная: низкая шапка, высота нужна карточкам.
        toolbarHeight: land ? 48 : null,
        leading: IconButton(
          key: const ValueKey<String>('leisure:back'),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Назад',
          onPressed: _back,
        ),
        automaticallyImplyLeading: false,
        title: Text(LeisureScreen.titleFor(place)),
        actions: <Widget>[
          HelpButton(
            key: const ValueKey<String>('leisure:help'),
            onPressed: _help,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WorldHud(snapshot: snap),
            Expanded(
              child: land
                  ? _landscape(<Widget>[
                      for (final WorldCatalogItem e in options) card(e),
                      // Клетка питомца, пока его нет, — короткая записка.
                      ...lockedNotes,
                    ], side: <Widget>[
                      if (result != null) result,
                      if (bannerNote != null) bannerNote,
                      if (result == null && bannerNote == null) intro,
                    ])
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                          Gap.md, Gap.sm, Gap.md, Gap.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (result != null) ...<Widget>[
                            result,
                            const SizedBox(height: Gap.md),
                          ],
                          if (bannerNote != null) ...<Widget>[
                            bannerNote,
                            const SizedBox(height: Gap.md),
                          ] else if (result == null) ...<Widget>[
                            intro,
                            const SizedBox(height: Gap.sm),
                          ],
                          for (final WorldCatalogItem e in options)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Gap.sm),
                              child: card(e),
                            ),
                          ...lockedNotes,
                        ],
                      ),
                    ),
            ),
            // «Уже утро» — под прокруткой, всегда на экране; в альбомной во
            // всю ширину: в колонке итога (184 dp) строка рвалась на три.
            if (night != null)
              DayEndStrip(
                  key: const ValueKey<String>('leisure:night'),
                  text: night.short,
                  style: body),
          ],
        ),
      ),
    );
  }

  /// Альбомная: варианты слева сеткой 2 × 2 — все четыре видны сразу;
  /// справа колонка «что происходит»: подсказка, баннер или итог выбора.
  Widget _landscape(List<Widget> tiles, {required List<Widget> side}) {
    const int perRow = 2;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey<String>('leisure:grid'),
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.sm, Gap.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < tiles.length; i += perRow)
                  Padding(
                    padding: EdgeInsets.only(
                        bottom: i + perRow < tiles.length ? Gap.sm : 0),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (int j = i; j < i + perRow; j++) ...<Widget>[
                            if (j > i) const SizedBox(width: Gap.sm),
                            Expanded(
                                child: j < tiles.length
                                    ? tiles[j]
                                    : const SizedBox.shrink()),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 184,
          child: SingleChildScrollView(
            key: const ValueKey<String>('leisure:side'),
            padding: const EdgeInsets.fromLTRB(0, Gap.sm, Gap.md, Gap.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < side.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: Gap.sm),
                  side[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Карточка варианта: 💰 / ⚡ / 😊 до выбора (из каталога) и кнопка.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.entry,
    required this.block,
    required this.onGo,
    this.compact = false,
  });

  final WorldCatalogItem entry;

  /// Почему сейчас нельзя — ответ мира ([World.canDo]); null — можно.
  /// Отказ этапа недели на карточке не пишется: он в баннере.
  final BlockReason? block;
  final VoidCallback onGo;

  /// Альбомная сетка: без строки «где», кнопка 48 dp прижата к низу,
  /// предупреждения короче — четыре карточки влезают на 640 × 360.
  final bool compact;

  /// Предупреждение: значок + текст (не только цвет).
  static Widget _warnLine(String w, {Key? key, double top = Gap.xs}) => Padding(
        key: key,
        padding: EdgeInsets.only(top: top),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.info_outline_rounded,
                size: 20, color: WorldColors.wants),
            const SizedBox(width: Gap.xs),
            Expanded(
                child: Text(w,
                    style: const TextStyle(
                        fontSize: 16, color: WorldColors.text))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final WorldCatalogItem e = entry;
    final BlockReason? b = block;
    // ⚡ в каталоге со знаком (досуг тратит): на карточке — сколько уйдёт.
    final double energy = -e.energy;
    final List<String> warn = <String>[
      if (b != null && !isPhaseBlock(b)) ...<String>[
        b.text,
        if (!compact && b.nextStep != null) 'Что можно: ${b.nextStep}',
      ],
    ];
    Widget stat(String key, Pic pic, Color color, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Pictogram(pic, size: 18, color: color),
            const SizedBox(width: Gap.xs),
            Flexible(
              child: Text(
                  key: ValueKey<String>(key),
                  text,
                  style: const TextStyle(fontSize: 16)),
            ),
          ],
        );
    final List<Widget> stats = <Widget>[
      stat('leisure:price:${e.id}', Pic.coin, WorldColors.gold,
          e.price == 0 ? 'бесплатно' : '${e.price}'),
      stat('leisure:energy:${e.id}', Pic.bolt, WorldColors.energy,
          WorldHud.energyText(energy)),
      stat('leisure:happiness:${e.id}', Pic.smile, WorldColors.mood,
          '+${e.happiness}'),
    ];
    // Карточка сетки 2 × 2: предупреждение слева от кнопки, а не над ней,
    // иначе две строки карточек не влезают в 640 × 360.
    final Widget go = FilledButton(
      key: ValueKey<String>('leisure:go:${e.id}'),
      style: compact
          ? FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(horizontal: Gap.sm + Gap.xs))
          : null,
      onPressed: b == null ? onGo : null,
      child: Text(e.id == 'pet_play' ? 'Поиграть' : 'Пойти'),
    );
    return Container(
      key: ValueKey<String>('leisure:card:${e.id}'),
      padding: EdgeInsets.all(compact ? Gap.sm : Gap.sm + Gap.xs),
      decoration: BoxDecoration(
        color: WorldColors.panel,
        borderRadius: BorderRadius.circular(WorldRadii.button),
        border: Border.all(color: WorldColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Pictogram(LeisureScreen.iconOf(e.id),
                  size: compact ? 22 : 30, color: WorldColors.textSoft),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(e.title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    if (!compact)
                      Text(LeisureScreen.whereOf(e.id),
                          style: const TextStyle(
                              fontSize: 16, color: WorldColors.textSoft)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 2 : Gap.sm),
          Wrap(
            spacing: compact ? Gap.sm + Gap.xs : Gap.md,
            runSpacing: Gap.xs,
            children: stats,
          ),
          if (!compact) ...<Widget>[
            for (int i = 0; i < warn.length; i++)
              _warnLine(warn[i],
                  key: i == 0
                      ? ValueKey<String>('leisure:block:${e.id}')
                      : null),
            const SizedBox(height: Gap.sm),
            go,
          ] else ...<Widget>[
            const Spacer(),
            const SizedBox(height: Gap.xs),
            // n5 (кадры 0.1.3): причина слева от «Пойти» при шрифте 1,3
            // сжималась до трёх букв в строке («Не хв / атает 150.») —
            // теперь она над кнопкой, на всю ширину карточки.
            for (int i = 0; i < warn.length; i++)
              _warnLine(warn[i],
                  key:
                      i == 0 ? ValueKey<String>('leisure:block:${e.id}') : null,
                  top: 0),
            if (warn.isNotEmpty) const SizedBox(height: Gap.xs),
            go,
          ],
        ],
      ),
    );
  }
}

/// Итог выбора: что изменилось и почему — числа мира, не превью.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.title, this.reason});

  final WorldResult result;
  final String title;

  /// Текст итога вместо [WorldResult.reason] (отдых закончил день).
  final String? reason;

  static String _signed(num v, String Function(num) f) =>
      v > 0 ? '+${f(v)}' : (v < 0 ? '−${f(-v)}' : '0');

  @override
  Widget build(BuildContext context) {
    final WorldResult r = result;
    return Container(
      key: const ValueKey<String>('leisure:result'),
      padding: const EdgeInsets.all(Gap.sm + Gap.xs),
      decoration: BoxDecoration(
        color: r.ok ? WorldColors.needsBg : WorldColors.wantsBg,
        borderRadius: BorderRadius.circular(WorldRadii.button),
        border: Border.all(color: r.ok ? WorldColors.needs : WorldColors.wants),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(r.ok ? Icons.check_circle_rounded : Icons.block_rounded,
                  color: r.ok ? WorldColors.needs : WorldColors.wants),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(r.ok ? 'Готово: $title' : 'Не получилось: $title',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          PicText(reason ?? r.reason,
              key: const ValueKey<String>('leisure:reason'),
              style: const TextStyle(fontSize: 16)),
          if (r.ok) ...<Widget>[
            const SizedBox(height: Gap.xs),
            PicText(
              key: const ValueKey<String>('leisure:delta'),
              '💰 ${_signed(r.coins, (num v) => '$v')} · '
              '⚡ ${_signed(r.energy, (num v) => WorldHud.energyText(v.toDouble()))} · '
              '😊 ${_signed(r.happiness, (num v) => '$v')}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
          if (r.nextStep != null) ...<Widget>[
            const SizedBox(height: Gap.xs),
            Text('Что дальше: ${r.nextStep}',
                key: const ValueKey<String>('leisure:next'),
                style: const TextStyle(fontSize: 16)),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Gap.sm + Gap.xs),
        decoration: BoxDecoration(
          color: WorldColors.goalBg,
          borderRadius: BorderRadius.circular(WorldRadii.button),
          border: Border.all(color: WorldColors.goal),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: WorldColors.goal),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(text,
                  style:
                      const TextStyle(fontSize: 16, color: WorldColors.text)),
            ),
          ],
        ),
      );
}
