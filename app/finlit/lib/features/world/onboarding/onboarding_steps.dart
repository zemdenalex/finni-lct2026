import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/art/sprite_anim.dart';
import '../../../core/feel.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../domain/world/contract.dart';
import '../pic_text.dart';
import '../world_layout.dart';
import '../world_state.dart';
import 'onboarding_script.dart';
import '../../../core/world_theme.dart';

/// Регистрация S0 (ник, облик и имя) и то, что показывают сценки знакомства
/// под репликой Финни: конверты, план недели, выбор цели. Состояние держит
/// `WorldOnboardingScreen`, здесь — только то, что видно.

const TextStyle _text =
    TextStyle(fontSize: 18, height: 1.4, color: WorldColors.text);
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
  const _Page({required this.title, this.text, required this.children});

  final String title;
  final String? text;
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
          Semantics(
              header: true,
              child: Text(title,
                  style:
                      AppType.title(land ? 21 : 24, color: WorldColors.text))),
          if (text != null) ...<Widget>[
            SizedBox(height: land ? Gap.xs : Gap.sm),
            Text(text!, style: _text),
          ],
          SizedBox(height: land ? Gap.sm : Gap.md),
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
              title: 'НУЖНО',
              text: need),
          const SizedBox(height: Gap.xs),
          _Decision(
              key: const ValueKey<String>('envelope:want'),
              color: WorldColors.wants,
              bg: WorldColors.wantsBg,
              title: 'ХОЧУ',
              text: want),
          const SizedBox(height: Gap.xs),
          _Decision(
              key: const ValueKey<String>('envelope:goal'),
              color: WorldColors.goal,
              bg: WorldColors.goalBg,
              title: 'ЦЕЛЬ',
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
        child: Text.rich(
          TextSpan(children: <InlineSpan>[
            TextSpan(text: '$title  ', style: AppType.title(16, color: color)),
            TextSpan(text: text),
          ]),
          style: _soft.copyWith(color: WorldColors.text),
        ),
      );
}

// ──────────────────────────── ник ────────────────────────────

class NickStep extends StatelessWidget {
  const NickStep(
      {super.key,
      required this.ui,
      required this.controller,
      required this.onChanged});

  /// Подписи — из `onboarding.json → ui`.
  final OnboardingScript ui;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => _Page(
        title: ui.t('nick_title'),
        text: ui.t('nick_text'),
        children: <Widget>[
          TextField(
            key: const ValueKey<String>('onboarding-nick'),
            controller: controller,
            maxLength: 16,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            textCapitalization: TextCapitalization.sentences,
            style: _text,
            decoration: InputDecoration(
              labelText: ui.t('nick_label'),
              hintText: ui.t('nick_hint'),
            ),
            onChanged: (_) => onChanged(),
          ),
        ],
      );
}

// ─────────────────────────── облик ───────────────────────────

class LookStep extends StatelessWidget {
  const LookStep({
    super.key,
    required this.ui,
    required this.registry,
    required this.profile,
    required this.name,
    required this.onPick,
    required this.onGender,
    this.showArt = true,
  });

  /// Подписи и названия видов — из `onboarding.json`.
  final OnboardingScript ui;
  final AssetRegistry? registry;
  final WorldProfile profile;
  final TextEditingController name;
  final void Function(String species, int look) onPick;

  /// Мальчик или девочка (open-questions К11). 🟡 Арта по полу в реестре
  /// пока нет — выбор сохраняется, картинка та же.
  final ValueChanged<FinniGender> onGender;

  /// Крупный Финни над плитками. В альбомной он стоит в левой панели.
  final bool showArt;

  @override
  Widget build(BuildContext context) {
    final List<String> species = registry?.ids('finni') ?? _speciesFallback;
    return _Page(
      title: ui.t('look_title'),
      children: <Widget>[
        // Имя — рядом с превью, над плитками: на 360 × 640 его видно без
        // прокрутки (ТЗ 2.5.2.2, Приложение А шаг 3).
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
                maxLength: 16,
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
            for (final (FinniGender g, String title) in <(FinniGender, String)>[
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
        const SizedBox(height: Gap.sm),
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
    final BorderRadius r = BorderRadius.circular(Radii.chip);
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
class PlanEditor extends StatelessWidget {
  const PlanEditor({
    super.key,
    required this.ui,
    required this.snapshot,
    required this.planning,
    required this.needs,
    required this.wants,
    required this.goal,
    required this.onChange,
  });

  final ResourceSnapshot snapshot;

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
  Widget build(BuildContext context) {
    if (!planning) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(ui.t('plan_ready'), style: _text),
          const SizedBox(height: Gap.xs),
          Wrap(
            spacing: Gap.md,
            runSpacing: Gap.xs,
            children: <Widget>[
              _Sum('НУЖНО', snapshot.need, WorldColors.needs),
              _Sum('ХОЧУ', snapshot.want, WorldColors.wants),
              _Sum('ЦЕЛЬ', snapshot.goal, WorldColors.goal),
            ],
          ),
        ],
      );
    }
    final int step = ui.planStep;
    final int pool = snapshot.unallocated;
    final int left = pool - needs - wants - goal;
    // Альбомная: три конверта в ряд — все видны без прокрутки (ревью
    // 29.09). Портрет: три компактные строки.
    final bool row = WorldLayout.isLandscape(context);
    final List<Widget> steppers = <Widget>[
      _Stepper(
        id: 'need',
        title: 'НУЖНО',
        // Счета — в реплике Финни; в альбомном ряду место только на смысл.
        hint: row
            ? ui.envelopesShort.need
            : '${ui.envelopesShort.need}, ${ui.t('bills', <String, String>{
                    'bill': '${snapshot.weeklyBill}'
                  })}',
        color: WorldColors.needs,
        value: needs,
        step: step,
        column: row,
        canAdd: left >= step,
        onSet: (int v) => onChange(v, wants, goal),
      ),
      _Stepper(
        id: 'want',
        title: 'ХОЧУ',
        hint: ui.envelopesShort.want,
        color: WorldColors.wants,
        value: wants,
        step: step,
        column: row,
        canAdd: left >= step,
        onSet: (int v) => onChange(needs, v, goal),
      ),
      _Stepper(
        id: 'goal',
        title: 'ЦЕЛЬ',
        hint: ui.envelopesShort.goal,
        color: WorldColors.goal,
        value: goal,
        step: step,
        column: row,
        canAdd: left >= step,
        onSet: (int v) => onChange(needs, wants, v),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Сколько пришло — и в реплике; в альбомной высоты на строку нет.
        if (!row) ...<Widget>[
          Row(
            children: <Widget>[
              Flexible(child: Text(ui.t('pool'), style: _text)),
              const SizedBox(width: Gap.sm),
              Coins(pool, size: 22),
            ],
          ),
          const SizedBox(height: Gap.xs),
        ],
        if (row)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < steppers.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: Gap.xs),
                Expanded(child: steppers[i]),
              ],
            ],
          )
        else
          ...steppers,
        Text(
          left > 0
              ? ui.t('unallocated', <String, String>{'left': '$left'})
              : planAllSpentLine,
          style: _soft,
        ),
      ],
    );
  }
}

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
    required this.canAdd,
    required this.onSet,
  });

  final String id;
  final String title;
  final String hint;
  final Color color;
  final int value;
  final int step;
  final bool column;
  final bool canAdd;
  final ValueChanged<int> onSet;

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
        _RoundButton(
          key: ValueKey<String>('minus:$id'),
          icon: Icons.remove,
          label: '$title: меньше',
          onTap: value >= step ? () => onSet(value - step) : null,
        ),
        SizedBox(
          width: column ? 34 : 56,
          // Крупный шрифт: число ужимается, а не ломается на «40 / 0».
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('$value',
                maxLines: 1,
                textAlign: TextAlign.center,
                style: AppType.number(18, color: WorldColors.text)),
          ),
        ),
        _RoundButton(
          key: ValueKey<String>('plus:$id'),
          icon: Icons.add,
          label: '$title: больше',
          onTap: canAdd
              ? () => onSet(value + step)
              : () => ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(
                    key: ValueKey<String>('plan:full'),
                    content: Text(planAllSpentHint))),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: 2),
        edge: color,
        child: column
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  label,
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

class _RoundButton extends StatelessWidget {
  const _RoundButton(
      {super.key, required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
        tooltip: label,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        iconSize: 24,
        icon: Icon(icon),
        onPressed: onTap,
      );
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
  });

  /// Подписи — из `onboarding.json → ui`.
  final OnboardingScript ui;
  final int saved;

  /// Цели с названием и ценой — из каталога мира ([onboardingGoals]).
  final List<WorldCatalogItem> goals;
  final String? chosen;
  final String? reason;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) => Column(
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
                  label: PicText('${g.title} · ${g.price} 💰',
                      style: const TextStyle(fontSize: 18)),
                  selected: chosen == g.id,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  padding: const EdgeInsets.symmetric(
                      horizontal: Gap.sm, vertical: Gap.sm),
                  onSelected: (_) => onChoose(g.id),
                ),
            ],
          ),
          if (reason != null) ...<Widget>[
            const SizedBox(height: Gap.sm),
            Text(reason!, style: _text),
          ],
        ],
      );
}
