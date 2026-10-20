import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/art/sprite_anim.dart';
import '../../../core/feel.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../domain/world/contract.dart';
import '../../../domain/world/goal_eta.dart';
import '../goal_eta_text.dart';
import '../pic_text.dart';
import '../world_layout.dart';
import '../world_state.dart';
import 'finni_bubble.dart';
import 'onboarding_script.dart';
import '../home/plan_amount.dart';
import '../home/plan_pool.dart';
import '../../../core/world_theme.dart';

/// Регистрация S0 (ник, облик и имя) и то, что показывают сценки знакомства
/// под репликой Финни: конверты, план недели, выбор цели. Состояние держит
/// `WorldOnboardingScreen`, здесь — только то, что видно.

const TextStyle _text =
    TextStyle(fontSize: 18, height: 1.4, color: WorldColors.text);
/// Реплика Финни в облачке: крупнее текста шага.
const TextStyle _bubble = TextStyle(
    fontSize: 20,
    height: 1.35,
    fontWeight: FontWeight.w700,
    color: WorldColors.text);
const TextStyle _soft =
    TextStyle(fontSize: 16, height: 1.4, color: WorldColors.textSoft);

/// Виды, если реестр ещё не загрузился.
const List<String> _speciesFallback = <String>[
  'finni-a1',
  'finni-a2',
  'finni-a3'
];

/// Цели шага 6 из каталога мира ([World.catalog]): все питомцы, транспорт
/// и жильё по одному — чтобы выбор помещался на экран.
List<WorldCatalogItem> onboardingGoals(List<WorldCatalogItem> catalog) {
  WorldCatalogItem? first(WorldCatalogCategory c) =>
      catalog.where((WorldCatalogItem i) => i.category == c).firstOrNull;
  return <WorldCatalogItem>[
    ...catalog
        .where((WorldCatalogItem i) => i.category == WorldCatalogCategory.pet),
    if (first(WorldCatalogCategory.transport) case final WorldCatalogItem t) t,
    if (first(WorldCatalogCategory.home) case final WorldCatalogItem h) h,
  ];
}

/// Полоса прогресса из шести отрезков.
class StepBar extends StatelessWidget {
  const StepBar({
    super.key,
    required this.step,
    required this.total,
    required this.label,
    this.padding = const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm),
  });

  final int step;
  final int total;

  /// Для TalkBack: «Шаг 1 из 2» (`onboarding.json → ui.step_of`).
  final String label;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        excludeSemantics: true,
        child: Padding(
          padding: padding,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < total; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: context.motion(Motion.state),
                    height: 6,
                    margin: EdgeInsets.only(right: i == total - 1 ? 0 : Gap.xs),
                    decoration: BoxDecoration(
                      color: i <= step ? WorldColors.text : WorldColors.line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// Прокручиваемая страница шага: заголовок, текст, содержимое.
class _Page extends StatelessWidget {
  const _Page({this.title, required this.children});

  /// Заголовок; null — его роль играет облачко Финни в [children].
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Альбомная: высоты мало — заголовок мельче, отступы короче.
    final bool land = WorldLayout.isLandscape(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Gap.md, land ? 0 : Gap.sm, Gap.md, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title case final String t) ...<Widget>[
            Semantics(
                header: true,
                child: Text(t,
                    style: AppType.title(land ? 21 : 24,
                        color: WorldColors.text))),
            SizedBox(height: land ? Gap.sm : Gap.md),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// Финни выбранного вида и облика. Нет арта — пустое место той же высоты.
class _Finni extends StatelessWidget {
  const _Finni({required this.registry, required this.profile});

  final AssetRegistry? registry;
  final WorldProfile profile;

  @override
  Widget build(BuildContext context) {
    final SpriteRef? f = registry?.finni(profile.species);
    if (f == null) return const SizedBox(height: 117);
    return SpriteAnim(
      key: ValueKey<String>('${profile.species}:${profile.idleTag}'),
      sprite: f,
      tag: profile.idleTag,
      height: 120,
      semanticLabel: profile.finniName,
    );
  }
}

/// Финни во весь рост на панели (левая половина первого экрана в
/// альбомной): высота — по панели, пиксели не плывут.
class FinniPortrait extends StatelessWidget {
  const FinniPortrait({super.key, required this.registry, required this.profile});

  final AssetRegistry? registry;
  final WorldProfile profile;

  @override
  Widget build(BuildContext context) => ColoredBox(
        key: const ValueKey<String>('onboarding:portrait'),
        color: WorldColors.panel,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final SpriteRef? f = registry?.finni(profile.species);
            if (f == null) return const SizedBox.expand();
            final double h =
                math.min(box.maxHeight * 0.8, box.maxWidth * 1.1);
            return Center(
              child: SpriteAnim(
                key: ValueKey<String>(
                    'onboarding:portrait:${profile.species}:${profile.idleTag}'),
                sprite: f,
                tag: profile.idleTag,
                height: h,
                semanticLabel: profile.finniName,
              ),
            );
          },
        ),
      );
}

// ─────────────────────────── конверты ───────────────────────────

/// Три конверта со смыслом (ТЗ 2.5.1.1, 2.5.5.4): под репликой Финни в
/// сценке про конверты. Смысл — из `onboarding.json → envelopes`.
class EnvelopeCards extends StatelessWidget {
  const EnvelopeCards(
      {super.key, required this.need, required this.want, required this.goal});

  final String need;
  final String want;
  final String goal;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Decision(
              key: const ValueKey<String>('envelope:need'),
              color: WorldColors.needs,
              bg: WorldColors.needsBg,
              title: 'Нужно',
              text: need),
          const SizedBox(height: Gap.xs),
          _Decision(
              key: const ValueKey<String>('envelope:want'),
              color: WorldColors.wants,
              bg: WorldColors.wantsBg,
              title: 'Хочу',
              text: want),
          const SizedBox(height: Gap.xs),
          _Decision(
              key: const ValueKey<String>('envelope:goal'),
              color: WorldColors.goal,
              bg: WorldColors.goalBg,
              title: 'Копилка',
              text: goal),
        ],
      );
}

class _Decision extends StatelessWidget {
  const _Decision(
      {super.key,
      required this.color,
      required this.bg,
      required this.title,
      required this.text});

  final Color color;
  final Color bg;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Panel(
        color: bg,
        edge: color,
        padding:
            const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
        // Правило 1Б Насти (18.10): «конверт» — образ методики, и в
        // обучении его один раз показывают картинкой — здесь, у трёх частей.
        child: Row(
          children: <Widget>[
            Pictogram(Pic.envelope, size: 28, color: color),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text.rich(
                TextSpan(children: <InlineSpan>[
                  TextSpan(
                      text: '$title  ', style: AppType.title(16, color: color)),
                  TextSpan(text: text),
                ]),
                style: _soft.copyWith(color: WorldColors.text),
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────── знакомство ───────────────────────────

/// Первый экран (Денис 20.10 13:46: «слева Финни, справа "привет я Финни,
/// а как зовут тебя?" и там ввод ника игрока и выбор внешнего вида Финни»):
/// Финни и облачко его реплики, поле ника, плитки обликов. В альбомной
/// крупный Финни стоит в левой панели экрана ([showArt] = false).
class WelcomeStep extends StatelessWidget {
  const WelcomeStep({
    super.key,
    required this.ui,
    required this.registry,
    required this.profile,
    required this.finniName,
    required this.controller,
    required this.onChanged,
    required this.onPick,
    this.showArt = true,
  });

  /// Подписи и названия видов — из `onboarding.json`.
  final OnboardingScript ui;
  final AssetRegistry? registry;
  final WorldProfile profile;

  /// Имя друга в реплике («Привет, я Финни!»).
  final String finniName;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final void Function(String species, int look) onPick;
  final bool showArt;

  @override
  Widget build(BuildContext context) {
    final Widget say = SpeechBubble(
      key: const ValueKey<String>('onboarding:welcome:say'),
      tail: BubbleTail.left,
      child: Semantics(
        header: true,
        child: Text(ui.t('nick_title', <String, String>{'name': finniName}),
            style: _bubble),
      ),
    );
    return _Page(
      children: <Widget>[
        if (showArt)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _Finni(registry: registry, profile: profile),
              const SizedBox(width: Gap.xs),
              Expanded(child: say),
            ],
          )
        else
          say,
        const SizedBox(height: Gap.sm),
        // Альбомная: высоты мало — поле ника сразу под облачком (пояснение
        // есть в «?»).
        if (showArt) ...<Widget>[
          Text(ui.t('nick_text'), style: _soft),
          const SizedBox(height: Gap.xs),
        ],
        TextField(
          key: const ValueKey<String>('onboarding-nick'),
          controller: controller,
          maxLength: OnboardingProgress.maxNameLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          textCapitalization: TextCapitalization.sentences,
          style: _text,
          decoration: InputDecoration(
            labelText: ui.t('nick_label'),
            hintText: ui.t('nick_hint'),
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: Gap.xs),
        Text(ui.t('look_pick'), style: _text),
        const SizedBox(height: Gap.sm),
        _LookTiles(
            ui: ui, registry: registry, profile: profile, onPick: onPick),
      ],
    );
  }
}

/// Облик: плитки обликов каждого вида, выбранная — с рамкой.
class _LookTiles extends StatelessWidget {
  const _LookTiles({
    required this.ui,
    required this.registry,
    required this.profile,
    required this.onPick,
  });

  final OnboardingScript ui;
  final AssetRegistry? registry;
  final WorldProfile profile;
  final void Function(String species, int look) onPick;

  @override
  Widget build(BuildContext context) {
    final List<String> species = registry?.ids('finni') ?? _speciesFallback;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final String s in species) ...<Widget>[
          Text(ui.species[s] ?? s, style: _soft),
          const SizedBox(height: Gap.xs),
          Row(
            children: <Widget>[
              for (int look = 1; look <= _lookCount(s); look++) ...<Widget>[
                if (look > 1) const SizedBox(width: Gap.sm),
                Expanded(
                  child: _LookTile(
                    key: ValueKey<String>('look:$s:$look'),
                    path: _lookPath(s, look),
                    label: ui.t('look_tile', <String, String>{
                      'species': ui.species[s] ?? s,
                      'n': '$look',
                    }),
                    selected: profile.species == s && profile.look == look,
                    onTap: () => onPick(s, look),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Gap.sm),
        ],
      ],
    );
  }

  int _lookCount(String s) {
    final int n = registry?.finniLooks(s).length ?? 0;
    return n == 0 ? 4 : n;
  }

  String? _lookPath(String s, int look) {
    final List<String>? looks = registry?.finniLooks(s);
    if (looks == null || looks.length < look) return null;
    return looks[look - 1];
  }
}

// ─────────────────────────── имя друга ───────────────────────────

/// Второй экран: имя друга, мальчик или девочка (облик выбран на первом).
class FriendStep extends StatelessWidget {
  const FriendStep({
    super.key,
    required this.ui,
    required this.registry,
    required this.profile,
    required this.name,
    required this.onGender,
    this.showArt = true,
  });

  final OnboardingScript ui;
  final AssetRegistry? registry;
  final WorldProfile profile;
  final TextEditingController name;

  /// Мальчик или девочка (open-questions К11). 🟡 Арта по полу в реестре
  /// пока нет — выбор меняет слова реплик, картинка та же.
  final ValueChanged<FinniGender> onGender;

  /// Финни рядом с полем имени. В альбомной он стоит в левой панели.
  final bool showArt;

  @override
  Widget build(BuildContext context) => _Page(
        title: ui.t('look_title'),
        children: <Widget>[
          // Имя — рядом с превью: на 360 × 640 его видно без прокрутки
          // (ТЗ 2.5.2.2, Приложение А шаг 3).
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (showArt) ...<Widget>[
                _Finni(registry: registry, profile: profile),
                const SizedBox(width: Gap.sm),
              ],
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('onboarding-finni-name'),
                  controller: name,
                  maxLength: OnboardingProgress.maxNameLength,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  textCapitalization: TextCapitalization.sentences,
                  style: _text,
                  decoration: InputDecoration(labelText: ui.t('name_label')),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: <Widget>[
              for (final (FinniGender g, String title)
                  in <(FinniGender, String)>[
                (FinniGender.boy, ui.t('boy')),
                (FinniGender.girl, ui.t('girl')),
              ]) ...<Widget>[
                if (g != FinniGender.boy) const SizedBox(width: Gap.sm),
                Expanded(
                  child: _GenderButton(
                    key: ValueKey<String>('gender:${g.name}'),
                    title: title,
                    selected: profile.gender == g,
                    onTap: () => onGender(g),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
}

/// Кнопка «Мальчик» / «Девочка»: выбранная залита, у неё галочка — не
/// только цвет (ТЗ 3.6.5). Крупный шрифт ужимает подпись, а не ломает ряд.
class _GenderButton extends StatelessWidget {
  const _GenderButton({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget label = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (selected) ...<Widget>[
            // Builder: цвет берётся внутри кнопки — тот же, что у подписи.
            Builder(
              builder: (BuildContext c) => Pictogram(Pic.check,
                  size: 20, color: IconTheme.of(c).color ?? WorldColors.text),
            ),
            const SizedBox(width: Gap.xs),
          ],
          Text(title, maxLines: 1, style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
    const Size min = Size(0, TapSize.min);
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      excludeSemantics: true,
      onTap:
          onTap, // иначе excludeSemantics отсекает касание: TalkBack не нажмёт
      child: selected
          ? FilledButton.tonal(
              style: FilledButton.styleFrom(
                  minimumSize: min,
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm)),
              onPressed: onTap,
              child: label)
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                  minimumSize: min,
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm)),
              onPressed: onTap,
              child: label),
    );
  }
}

/// Плитка облика: голова Финни в 1× (пиксели не плывут), рамка — выбор.
class _LookTile extends StatelessWidget {
  const _LookTile({
    super.key,
    required this.path,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String? path;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius r = BorderRadius.circular(WorldRadii.button);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap:
          onTap, // иначе excludeSemantics отсекает касание: TalkBack не нажмёт
      child: Material(
        color: selected ? WorldColors.goalBg : WorldColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: BorderSide(
            color: selected ? WorldColors.goal : WorldColors.line,
            width: selected ? 3 : 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // Герой целиком, вписанный в плитку: арт высокого разрешения
          // выше плитки, и срез «по макушке» показывал только уши.
          child: SizedBox(
            height: TapSize.min + Gap.sm,
            child: Padding(
              padding: const EdgeInsets.all(Gap.xs),
              child: FittedBox(
                fit: BoxFit.contain,
                child: PixelImage(path,
                    fallback: const SizedBox(width: 48, height: 48)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────── план ────────────────────────────

/// План первой недели в сценке: пришло · три степпера со смыслом конверта
/// · остаток. План уже подтверждён — только итог по конвертам.
///
/// Смысл конвертов ([meanings]) стоит прямо под названием: ребёнок, который
/// пропустил разговор, всё равно видит три решения (ТЗ 2.5.1.1).
class PlanEditor extends StatefulWidget {
  const PlanEditor({
    super.key,
    required this.ui,
    required this.snapshot,
    required this.planning,
    required this.needs,
    required this.wants,
    required this.goal,
    required this.onChange,
    this.finniName = 'Финни',
  });

  final ResourceSnapshot snapshot;

  /// Имя Финни на кнопке совета: «Как советует Бублик».
  final String finniName;

  /// Ждёт ли мир плана. Нет — план уже подтверждён, видно только итог.
  final bool planning;

  /// Подписи, смысл конвертов коротко и шаг «−» / «+» — из
  /// `onboarding.json`.
  final OnboardingScript ui;
  final int needs;
  final int wants;
  final int goal;
  final void Function(int needs, int wants, int goal) onChange;

  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  /// «+» без остатка: сколько раз (строка «На неделю» трясётся) и показать
  /// ли «Всё уже разложено».
  int _shake = 0;
  bool _full = false;

  @override
  void didUpdateWidget(PlanEditor old) {
    super.didUpdateWidget(old);
    if (old.needs != widget.needs ||
        old.wants != widget.wants ||
        old.goal != widget.goal) {
      _full = false;
    }
  }

  void _onFull() => setState(() {
        _shake++;
        _full = true;
      });

  @override
  Widget build(BuildContext context) {
    final OnboardingScript ui = widget.ui;
    final ResourceSnapshot snapshot = widget.snapshot;
    final int needs = widget.needs, wants = widget.wants, goal = widget.goal;
    final void Function(int, int, int) onChange = widget.onChange;
    if (!widget.planning) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(ui.t('plan_ready'), style: _text),
          const SizedBox(height: Gap.xs),
          Wrap(
            spacing: Gap.md,
            runSpacing: Gap.xs,
            children: <Widget>[
              _Sum('Нужно', snapshot.need, WorldColors.needs),
              _Sum('Хочу', snapshot.want, WorldColors.wants),
              _Sum('Копилка', snapshot.goal, WorldColors.goal),
            ],
          ),
        ],
      );
    }
    final int step = ui.planStep;
    final int pool = snapshot.unallocated;
    final int left = pool - needs - wants - goal;
    final bool row = WorldLayout.isLandscape(context);
    final Widget advice = PlanAdviceButton(
      name: widget.finniName,
      compact: row,
      onPressed: left > 0
          ? () {
              final ({int need, int want, int goal}) r = advisePlan(
                pool: pool,
                bill: snapshot.weeklyBill,
                step: step,
                advice: ui.planAdvice,
                need: needs,
                want: wants,
                goal: goal,
              );
              onChange(r.need, r.want, r.goal);
            }
          : null,
    );
    // Альбомная: три конверта в ряд — все видны без прокрутки (ревью
    // 29.09). Портрет: три компактные строки.
    final List<Widget> steppers = <Widget>[
      _Stepper(
        id: 'need',
        title: 'Нужно',
        // Счета — в реплике Финни («Счета недели — …»): строка конверта
        // короткая, копилке под «На неделю» хватает места на 360 dp.
        hint: ui.envelopesShort.need,
        color: WorldColors.needs,
        value: needs,
        step: step,
        column: row,
        left: left,
        onFull: _onFull,
        digits: '$pool'.length,
        onSet: (int v) => onChange(v, wants, goal),
      ),
      _Stepper(
        id: 'want',
        title: 'Хочу',
        hint: ui.envelopesShort.want,
        color: WorldColors.wants,
        value: wants,
        step: step,
        column: row,
        left: left,
        onFull: _onFull,
        digits: '$pool'.length,
        onSet: (int v) => onChange(needs, v, goal),
      ),
      _Stepper(
        id: 'goal',
        title: 'Копилка',
        hint: ui.envelopesShort.goal,
        color: WorldColors.goal,
        value: goal,
        step: step,
        column: row,
        left: left,
        onFull: _onFull,
        digits: '$pool'.length,
        onSet: (int v) => onChange(needs, wants, v),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Сколько пришло — и в реплике; в альбомной высоты на строку нет.
        // Альбомная тоже: «Всё уже разложено» и копилка отдельно нужны везде.
        PlanPool(
          amount: pool,
          saved: snapshot.saved,
          shake: _shake,
          full: _full,
          compact: row,
        ),
        // Альбомная: «На неделю» пустая (кроме «Всё уже разложено») — без
        // отступа под ней, иначе кнопка совета внизу срезается на 640×360.
        if (!row || _full) const SizedBox(height: Gap.xs),
        // Портрет: совет над строками. Альбомная: высоты нет — справа от
        // «Не разложено» под строками.
        if (!row) ...<Widget>[
          Align(alignment: Alignment.centerLeft, child: advice),
          const SizedBox(height: Gap.xs),
        ],
        if (row)
          // Одной высоты (скриншот Саши 15.10: «ЦЕЛЬ» была ниже соседей).
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < steppers.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: Gap.xs),
                  Expanded(child: steppers[i]),
                ],
              ],
            ),
          )
        else
          ...steppers,
        // Альбомная, всё разложено: совету делать нечего — строка
        // «Переложить…» во всю ширину, а не в три строки рядом с кнопкой.
        if (row && left > 0)
          Row(
            children: <Widget>[
              Expanded(child: _leftLine(ui, left)),
              const SizedBox(width: Gap.xs),
              Flexible(child: advice),
            ],
          )
        else
          _leftLine(ui, left),
      ],
    );
  }
}

Widget _leftLine(OnboardingScript ui, int left) => Text(
      left > 0
          ? ui.t('unallocated', <String, String>{'left': '$left'})
          : planAllSpentLine,
      style: _soft,
    );

class _Sum extends StatelessWidget {
  const _Sum(this.title, this.amount, this.color);

  final String title;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title, style: AppType.title(16, color: color)),
          const SizedBox(width: Gap.xs),
          Coins(amount, size: 18),
        ],
      );
}

/// Конверт плана: название и смысл коротко, «−», сумма, «+».
///
/// [column] — альбомная: конверты в ряд, название над кнопками. Иначе —
/// одна строка: название слева, кнопки справа. Смысл — 14 sp под названием.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.id,
    required this.title,
    required this.hint,
    required this.color,
    required this.value,
    required this.step,
    required this.column,
    required this.left,
    required this.onFull,
    required this.onSet,
    this.digits = 2,
  });

  final String id;
  final String title;
  final String hint;
  final Color color;
  final int value;
  final int step;
  final bool column;

  /// Остаток: «+» и ввод не кладут больше, чем [value] + [left].
  final int left;

  /// «+», когда раскладывать уже нечего.
  final VoidCallback onFull;
  final ValueChanged<int> onSet;

  /// Цифр в самой большой сумме (всё, что пришло): место под число одно на
  /// все три конверта — «390» не мельче «10» (скриншот Саши 15.10).
  final int digits;

  static const TextStyle _hintStyle =
      TextStyle(fontSize: 14, height: 1.2, color: WorldColors.textSoft);

  @override
  Widget build(BuildContext context) {
    final Widget label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(title, style: AppType.title(16, color: color)),
        Text(hint, style: _hintStyle),
      ],
    );
    final Widget buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Касание — шаг, удержание — повтор с разгоном (plan_amount.dart).
        HoldStepButton(
          key: ValueKey<String>('minus:$id'),
          icon: Icons.remove,
          label: '$title: меньше',
          value: value,
          max: value + left,
          step: step,
          up: false,
          onChanged: onSet,
        ),
        // Касание числа — ввод с цифровой клавиатуры. Альбомная: число
        // узкое (34 dp), цель ввода для TalkBack — заголовок строки.
        AmountTap(
          key: column ? null : ValueKey<String>('amount:$id'),
          semantic: !column,
          title: title,
          value: value,
          max: value + left,
          onChanged: onSet,
          child: SizedBox(
            width: column ? 34 : 56,
            // Крупный шрифт: число ужимается, а не ломается на «40 / 0».
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('$value',
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  // Одна сумма шрифта на все три конверта — по самой длинной
                  // возможной сумме, а не ужатие каждого числа отдельно.
                  style: AppType.number(column && digits >= 3 ? 13 : 18,
                          color: WorldColors.text)
                      .copyWith(
                          decoration: TextDecoration.underline,
                          decorationColor: WorldColors.textSoft)),
            ),
          ),
        ),
        HoldStepButton(
          key: ValueKey<String>('plus:$id'),
          icon: Icons.add,
          label: '$title: больше',
          value: value,
          max: value + left,
          step: step,
          up: true,
          onChanged: onSet,
          onBlocked: onFull,
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: Panel(
        // Заголовок не на рамке: скругление съедало верхний край «НУЖНО».
        padding: column
            ? const EdgeInsets.fromLTRB(Gap.xs, Gap.xs + 2, Gap.xs, Gap.xs)
            : const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: 2),
        edge: color,
        child: column
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  AmountTap(
                    key: ValueKey<String>('amount:$id'),
                    title: title,
                    value: value,
                    max: value + left,
                    onChanged: onSet,
                    alignment: AlignmentDirectional.centerStart,
                    child: label,
                  ),
                  FittedBox(fit: BoxFit.scaleDown, child: buttons),
                ],
              )
            : Row(
                children: <Widget>[
                  Expanded(child: label),
                  buttons,
                ],
              ),
      ),
    );
  }
}

// ──────────────────────────── цель ────────────────────────────

/// Выбор первой цели в сценке: в копилке · цели с ценой · фраза мира.
class GoalPicker extends StatelessWidget {
  const GoalPicker({
    super.key,
    required this.ui,
    required this.saved,
    required this.goals,
    required this.chosen,
    required this.reason,
    required this.onChoose,
    this.history = const <WeekPlanFact>[],
  });

  /// Подписи — из `onboarding.json → ui`.
  final OnboardingScript ui;
  final int saved;

  /// Недели мира ([World.weekHistory]) — для срока до цели ([goalEta]).
  final List<WeekPlanFact> history;

  /// Цели с названием и ценой — из каталога мира ([onboardingGoals]).
  final List<WorldCatalogItem> goals;
  final String? chosen;
  final String? reason;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    // Срок до каждой цели — тем же расчётом, что в копилке (ТЗ 2.5.7.4).
    final Map<String, String?> eta = <String, String?>{};
    // Почему срока нет — у всех целей одна история, причина одна.
    GoalEtaGap gap = GoalEtaGap.noDeposit;
    for (final WorldCatalogItem g in goals) {
      final GoalEta? e = goalEta(history, g.price - saved);
      eta[g.id] = goalEtaShort(e);
      if (e?.reason case final GoalEtaGap r) gap = r;
    }
    final bool noEta = eta.values.every((String? e) => e == null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(child: Text(ui.t('in_piggy'), style: _text)),
            const SizedBox(width: Gap.sm),
            Coins(saved, size: 22),
          ],
        ),
        const SizedBox(height: Gap.sm),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: <Widget>[
            // Цена видна до выбора (ТЗ 2.5.7.2).
            for (final WorldCatalogItem g in goals)
              ChoiceChip(
                key: ValueKey<String>('goal:${g.id}'),
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    PicText('${g.title} · ${g.price} 💰',
                        style: const TextStyle(fontSize: 18)),
                    if (eta[g.id] case final String e)
                      Text(e,
                          key: ValueKey<String>('goal:eta:${g.id}'),
                          style: const TextStyle(
                              fontSize: 14, color: WorldColors.textSoft)),
                  ],
                ),
                selected: chosen == g.id,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                padding: const EdgeInsets.symmetric(
                    horizontal: Gap.sm, vertical: Gap.sm),
                onSelected: (_) => onChoose(g.id),
              ),
          ],
        ),
        if (noEta) ...<Widget>[
          const SizedBox(height: Gap.sm),
          Text(goalEtaGapText(gap),
              key: const ValueKey<String>('goal:eta:none'), style: _text),
        ],
        if (reason != null) ...<Widget>[
          const SizedBox(height: Gap.sm),
          Text(reason!, style: _text),
        ],
      ],
    );
  }
}
