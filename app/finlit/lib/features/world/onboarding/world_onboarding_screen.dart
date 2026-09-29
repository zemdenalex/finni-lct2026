import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../../../core/art/asset_registry.dart';
import '../../../core/feel.dart';
import '../../../core/theme.dart';
import '../../../domain/world/contract.dart';
import '../../../domain/world/fridge_stock.dart';
import '../home/room_scene.dart';
import '../pic_text.dart';
import '../world_help.dart';
import '../world_layout.dart';
import '../world_routes.dart';
import '../world_state.dart';
import 'onboarding_script.dart';
import 'onboarding_steps.dart';
import '../../../core/world_theme.dart';

/// S0 «Финни переезжает»: короткая регистрация, потом сценки в комнате
/// (Денис, 29.09: «не куча вопросов, как в опроснике, а только свой ник и
/// выбор персонажа Финни, дальше Финни должен объяснить уже в самой игре»).
///
/// Регистрация — два шага: ник · облик и имя Финни (превью сразу). Переход с
/// облика начинает неделю 1 (`startWeek`). Дальше — комната: Финни сам
/// подходит к копилке, холодильнику и двери и говорит короткими репликами
/// из `onboarding.json`; в сценке плана ребёнок раскладывает карманные по
/// конвертам, в сценке цели — выбирает цель. «Пропустить» ведёт сразу к
/// плану: план и цель — решения ребёнка, их не пропускают.
///
/// Сохранённый шаг мира ([OnboardingProgress]) не менялся: 0–2 — ник,
/// 3 — облик, 4 — сценки и план, 5 — цель, 6 — готово.
///
/// 🔴 Неделя 1 стартует ровно один раз: `startWeek` зовётся только из
/// [WeekPhase.onboarding]. Экран, открытый заново посреди знакомства,
/// начинает с шага, который соответствует фазе мира.
class WorldOnboardingScreen extends StatefulWidget {
  const WorldOnboardingScreen({super.key});

  @override
  State<WorldOnboardingScreen> createState() => _WorldOnboardingScreenState();
}

class _WorldOnboardingScreenState extends State<WorldOnboardingScreen> {
  /// Шагов регистрации: ник · облик и имя.
  static const int _regTotal = 2;
  static const int _stepFinni = OnboardingProgress.stepFinni;
  static const int _stepMoney = OnboardingProgress.stepMoney;
  static const int _stepGoal = OnboardingProgress.stepGoal;

  final Future<AssetRegistry?> _registry = AssetRegistry.load()
      .then<AssetRegistry?>((AssetRegistry r) => r,
          onError: (Object _) => null);

  /// Сценарий сценок: из провайдера (`main.dart`, тесты) или из бандла.
  late final Future<OnboardingScript> _script;
  OnboardingScript? _loaded;

  late final TextEditingController _nick;
  late final TextEditingController _name;
  late WorldProfile _profile;

  /// Сохранённый шаг: ≤ [_stepFinni] — регистрация, дальше — сценки.
  late int _step;

  /// Сценка и реплика в ней.
  int _scene = 0;
  int _line = 0;

  /// Раскладка плана, пока не подтверждена.
  int _needs = 0;
  int _wants = 0;
  int _goal = 0;

  /// Выбранная цель и фраза мира про неё.
  String? _goalId;
  String? _goalReason;

  /// Идёт сохранение шага — «Дальше» и «Назад» ждут.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final WorldState ws = context.read<WorldState>();
    final OnboardingProgress saved = ws.onboarding;
    _profile = WorldProfile.of(saved);
    _nick = TextEditingController(text: saved.nickname);
    _name = TextEditingController(text: saved.finniName);
    _goalId = ws.snapshot.activeGoalId;
    // Продолжаем с сохранённого шага, но шаги 4–5 решает фаза мира (A14).
    // «Готово» здесь — последний шаг: экран открыли заново уже после.
    final int resume = saved.resumeFrom(phase: ws.phase, snapshot: ws.snapshot);
    _step = resume > _stepGoal ? _stepGoal : resume;
    if (ws.phase == WeekPhase.planning) _presetPlan(ws.snapshot);

    final OnboardingScript? given = context.read<OnboardingScript?>();
    _script = given != null
        ? Future<OnboardingScript>.value(given)
        : OnboardingScript.load(rootBundle.loadString);
    _loaded = given;
    if (given != null) {
      _enterScenes(given);
    } else {
      unawaited(_script.then((OnboardingScript s) {
        if (!mounted) return;
        setState(() {
          _loaded = s;
          _enterScenes(s);
        });
      }, onError: (Object _) {}));
    }
  }

  @override
  void dispose() {
    _nick.dispose();
    _name.dispose();
    super.dispose();
  }

  /// С какой сценки начать: план подтверждён — с цели, иначе с начала.
  void _enterScenes(OnboardingScript s) {
    _scene = _step >= _stepGoal ? s.goalIndex : 0;
    _line = 0;
  }

  bool get _inScenes => _step >= _stepMoney;

  /// Шаг регистрации: 0 — ник (сохранённые 0–2), 1 — облик и имя.
  int get _regStep => _step >= _stepFinni ? 1 : 0;

  OnboardingScene? get _current {
    final OnboardingScript? s = _loaded;
    if (s == null || !_inScenes) return null;
    return s.scenes[_scene];
  }

  /// Подписи знакомства: из сценария, пока его нет — запасные.
  OnboardingScript get _ui => _loaded ?? OnboardingScript.fallback;

  String get _stepOf => _ui.t('step_of',
      <String, String>{'n': '${_regStep + 1}', 'total': '$_regTotal'});

  bool get _lastScene =>
      _loaded != null && _scene == _loaded!.scenes.length - 1;

  /// По умолчанию всё — в НУЖНО, сколько просит счёт недели. Ребёнок может
  /// переложить.
  void _presetPlan(ResourceSnapshot s) {
    final int toBill =
        s.weeklyBill < s.unallocated ? s.weeklyBill : s.unallocated;
    _needs = toBill;
    _wants = 0;
    _goal = 0;
  }

  String get _nickText => _nick.text.trim();

  String get _finniName {
    final String n = _name.text.trim();
    return n.isEmpty ? OnboardingProgress.defaultFinniName : n;
  }

  bool get _canGoOn {
    if (_busy) return false;
    if (!_inScenes) {
      return _regStep == 1 ||
          (_nickText.isNotEmpty &&
              _nickText.length <= OnboardingProgress.maxNameLength);
    }
    final OnboardingScene? sc = _current;
    if (sc == null) return false;
    return switch (sc.kind) {
      SceneKind.talk => true,
      SceneKind.plan => _canPlan,
      SceneKind.goal => _goalId != null,
    };
  }

  bool get _canPlan {
    final WorldState ws = context.read<WorldState>();
    if (ws.phase != WeekPhase.planning) return true;
    return _needs + _wants + _goal <= ws.snapshot.unallocated;
  }

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Облик сохраняется в мире сразу при выборе — превью и сохранение
  /// меняются вместе.
  void _pickLook({String? species, int? look, FinniGender? gender}) {
    setState(() => _profile =
        _profile.copyWith(species: species, look: look, gender: gender));
    unawaited(context
        .read<WorldState>()
        .setFinniLook(species: species, look: look, gender: gender));
  }

  /// Облик (с выбранным по умолчанию) и имя.
  Future<WorldResult> _saveLookAndName(WorldState ws) async {
    final WorldResult look = await ws.setFinniLook(
        species: _profile.species,
        look: _profile.look,
        gender: _profile.gender);
    if (!look.ok) return look;
    return ws.setFinniName(_name.text);
  }

  Future<void> _next() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await (_inScenes ? _nextScene() : _nextRegistration());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _nextRegistration() async {
    final WorldState ws = context.read<WorldState>();
    if (_regStep == 0) {
      final WorldResult r = await ws.setNickname(_nickText);
      if (!mounted) return;
      if (!r.ok) return _say(r.reason);
      setState(() => _step = _stepFinni);
      return;
    }
    final WorldResult r = await _saveLookAndName(ws);
    if (!mounted) return;
    if (!r.ok) return _say(r.reason);
    _profile = _profile.copyWith(finniName: ws.onboarding.finniName);
    if (ws.phase == WeekPhase.onboarding) {
      final WorldResult w = ws.act((World w) => w.startWeek());
      if (!w.ok) return _say(w.reason);
      _presetPlan(ws.snapshot);
    }
    setState(() {
      _step = _stepMoney;
      final OnboardingScript? s = _loaded;
      if (s != null) _enterScenes(s);
    });
  }

  Future<void> _nextScene() async {
    final OnboardingScene? sc = _current;
    if (sc == null) return;
    final WorldState ws = context.read<WorldState>();
    switch (sc.kind) {
      case SceneKind.talk:
        if (_line < sc.lines.length - 1) {
          setState(() => _line++);
          return;
        }
      case SceneKind.plan:
        if (ws.phase == WeekPhase.planning) {
          final WorldResult r = ws.act(
              (World w) => w.plan(needs: _needs, wants: _wants, goal: _goal));
          if (!r.ok) return _say(r.reason);
        }
        if (_step < _stepGoal) {
          await ws.setOnboardingStep(_stepGoal);
          if (!mounted) return;
          _step = _stepGoal;
        }
      case SceneKind.goal:
        break;
    }
    await _toScene(_scene + 1);
  }

  /// Сценка [i]; за последней — комната.
  Future<void> _toScene(int i) async {
    final OnboardingScript s = _loaded!;
    if (i < s.scenes.length) {
      setState(() {
        _scene = i;
        _line = 0;
      });
      return;
    }
    final WorldState ws = context.read<WorldState>();
    await ws.setOnboardingStep(OnboardingProgress.stepDone);
    if (!mounted) return;
    unawaited(
        Navigator.pushReplacementNamed<void, void>(context, WorldRoutes.room));
  }

  /// «Пропустить»: разговор — да, решения — нет. До плана — сразу к плану,
  /// после цели — сразу в комнату (живой показ: не листать реплики).
  Future<void> _skip() async {
    final OnboardingScript? s = _loaded;
    if (s == null || _busy) return;
    int i = _scene + 1;
    while (i < s.scenes.length && s.scenes[i].kind == SceneKind.talk) {
      i++;
    }
    await _toScene(i);
  }

  bool get _canSkip =>
      _loaded != null && _inScenes && _current?.kind == SceneKind.talk;

  Future<void> _back() async {
    if (_busy) return;
    final WorldState ws = context.read<WorldState>();
    if (_inScenes) {
      if (_line > 0) return setState(() => _line--);
      if (_scene > 0) {
        final OnboardingScene prev = _loaded!.scenes[_scene - 1];
        return setState(() {
          _scene--;
          _line = prev.lines.length - 1;
        });
      }
    } else if (_regStep == 0) {
      return;
    }
    setState(() => _busy = true);
    // Уже набранное не теряется: ник и имя сохраняются и при «Назад».
    if (_regStep == 1 && !_inScenes) await _saveLookAndName(ws);
    final int to = _inScenes ? _stepFinni : OnboardingProgress.stepNickname;
    await ws.setOnboardingStep(to);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = to;
    });
  }

  bool get _canBack => _inScenes || _regStep > 0;

  void _chooseGoal(String id) {
    final WorldResult r =
        context.read<WorldState>().act((World w) => w.chooseGoal(id));
    setState(() {
      if (r.ok) _goalId = id;
      _goalReason = r.reason;
    });
  }

  /// Подстановки в реплики: числа — от мира, не из файла.
  Map<String, String> _values(WorldState ws) {
    final ResourceSnapshot s = ws.snapshot;
    return <String, String>{
      'nick': ws.onboarding.nickname,
      'name': _finniName,
      'pool':
          '${ws.phase == WeekPhase.planning ? s.unallocated : s.need + s.want + s.free}',
      'bill': '${s.weeklyBill}',
      'saved': '${s.saved}',
      'step': '${_ui.planStep}',
    };
  }

  void _help() {
    final OnboardingScene? sc = _current;
    if (sc != null) {
      showHelp(
          context,
          'Что здесь?',
          fillLine(sc.helpFor(_profile.gender),
              _values(context.read<WorldState>())));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // ТЗ 3.6.7: с выключенными анимациями лист не выезжает, а появляется.
      sheetAnimationStyle: AnimationStyle(
        duration: context.motion(const Duration(milliseconds: 250)),
        reverseDuration: context.motion(const Duration(milliseconds: 200)),
      ),
      builder: (BuildContext c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.lg),
          child: Text(_ui.t(_regStep == 0 ? 'nick_help' : 'look_help'),
              style: const TextStyle(
                  fontSize: 18, height: 1.4, color: WorldColors.text)),
        ),
      ),
    );
  }

  Widget _backButton() => IconButton(
        tooltip: _ui.t('back'),
        iconSize: 28,
        icon: const Icon(Icons.arrow_back),
        onPressed: _back,
      );

  Widget _helpButton() => HelpButton(
        key: const ValueKey<String>('onboarding:help'),
        onPressed: _help,
      );

  /// [compact] — альбомная: кнопка 56 dp вместо 64, чтобы шагу осталась
  /// высота.
  Widget _nextButton({bool compact = false}) {
    final OnboardingScene? sc = _current;
    final String label = !_inScenes
        ? _ui.t(_regStep == 0 ? 'next' : 'go')
        : switch (sc?.kind) {
            SceneKind.plan
                when context.read<WorldState>().phase == WeekPhase.planning =>
              _ui.t('plan_done'),
            _
                when _lastScene &&
                    (sc!.kind != SceneKind.talk ||
                        _line == sc.lines.length - 1) =>
              _ui.t('to_room'),
            _ => _ui.t('next'),
          };
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: const ValueKey<String>('onboarding-next'),
        style: compact
            ? FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(TapSize.min))
            : null,
        onPressed: _canGoOn ? _next : null,
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final WorldState ws = context.watch<WorldState>();
    if (_inScenes) {
      return OrientationSplit(
        landscape: (BuildContext context) => _scenesLandscape(ws),
        portrait: (BuildContext context) => _scenesPortrait(ws),
      );
    }
    return OrientationSplit(
      landscape: (BuildContext context) => _regLandscape(ws),
      portrait: (BuildContext context) => _regPortrait(ws),
    );
  }

  // ───────────────────────────── регистрация ─────────────────────────────

  Widget _regBody(AssetRegistry? reg, {bool showArt = true}) => _regStep == 0
      ? NickStep(ui: _ui, controller: _nick, onChanged: () => setState(() {}))
      : LookStep(
          ui: _ui,
          registry: reg,
          profile: _profile,
          showArt: showArt,
          name: _name,
          onPick: (String species, int look) =>
              _pickLook(species: species, look: look),
          onGender: (FinniGender g) => _pickLook(gender: g),
        );

  Widget _regSteps({bool showArt = true}) => FutureBuilder<AssetRegistry?>(
        future: _registry,
        builder: (BuildContext c, AsyncSnapshot<AssetRegistry?> s) =>
            AnimatedSwitcher(
          duration: context.motion(Motion.state),
          child: KeyedSubtree(
            key: ValueKey<int>(_regStep),
            child: _regBody(s.data, showArt: showArt),
          ),
        ),
      );

  /// Альбомная: слева комната с Финни (выбранный облик виден сразу), справа
  /// шаг и кнопка «Дальше»; шапка — одна строка.
  Widget _regLandscape(WorldState ws) => Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: 52,
                child: Row(
                  children: <Widget>[
                    if (_canBack)
                      _backButton()
                    else
                      const SizedBox(width: Gap.md),
                    Text(_stepOf,
                        style: AppType.title(18, color: WorldColors.text)),
                    Expanded(
                      child: StepBar(
                        step: _regStep,
                        total: _regTotal,
                        label: _stepOf,
                        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                      ),
                    ),
                    _helpButton(),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints box) {
                    final double side =
                        (box.maxWidth * 0.36).clamp(200.0, 420.0).toDouble();
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(
                          width: side,
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(Gap.md, 0, 0, Gap.md),
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(Radii.envelope),
                              child: _Stage(
                                  profile: _profile, snapshot: ws.snapshot),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(child: _regSteps(showArt: false)),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    Gap.md, Gap.xs, Gap.md, Gap.md),
                                child: _nextButton(compact: true),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

  Widget _regPortrait(WorldState ws) => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: _canBack ? _backButton() : null,
          title: Text(_stepOf),
          actions: <Widget>[_helpButton()],
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              StepBar(step: _regStep, total: _regTotal, label: _stepOf),
              Expanded(child: _regSteps()),
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
                child: _nextButton(),
              ),
            ],
          ),
        ),
      );

  // ──────────────────────────────── сценки ────────────────────────────────

  /// Шапка сценок: назад · «Знакомство» или «Пропустить» · «?». Пока
  /// можно пропустить, вместо заголовка — кнопка: на 640 × 360 правой
  /// панели не хватает ширины на оба.
  Widget _scenesBar() => SizedBox(
        height: 52,
        child: Row(
          children: <Widget>[
            _backButton(),
            Expanded(
              child: _canSkip
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const ValueKey<String>('onboarding:skip'),
                        style: TextButton.styleFrom(
                            minimumSize: const Size(TapSize.min, TapSize.min)),
                        onPressed: _skip,
                        child: FittedBox(
                            fit: BoxFit.scaleDown, child: Text(_loaded!.skip)),
                      ),
                    )
                  : Text(_ui.t('scenes_title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.title(18, color: WorldColors.text)),
            ),
            _helpButton(),
          ],
        ),
      );

  /// Комната: Финни подходит к предмету сцены. В разговоре касание комнаты,
  /// Финни или предмета, к которому он подошёл, — то же, что «Дальше»;
  /// для TalkBack это кнопки «Финни» и, например, «Копилка».
  Widget _room(WorldState ws) {
    final OnboardingScene? sc = _current;
    final VoidCallback? next =
        sc?.kind == SceneKind.talk && _canGoOn ? _next : null;
    VoidCallback? on(String object) => sc?.focus == object ? next : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: next,
      child: _SceneRoom(
        profile: _profile.copyWith(finniName: _finniName),
        snapshot: ws.snapshot,
        focus: sc?.focus,
        onFinniTap: next,
        onPiggyTap: on('piggy'),
        onFridgeTap: on('fridge'),
        onDoorTap: on('door'),
        onBedTap: on('bed'),
      ),
    );
  }

  /// Реплика Финни и то, что под ней: конверты, план или цели.
  Widget _speech(WorldState ws) {
    final OnboardingScript? s = _loaded;
    final OnboardingScene? sc = _current;
    if (s == null || sc == null) return const SizedBox(height: 48);
    final Map<String, String> v = _values(ws);
    final List<String> lines = sc.linesFor(_profile.gender);
    final String line = sc.kind == SceneKind.talk
        ? fillLine(lines[_line], v)
        : lines.map((String l) => fillLine(l, v)).join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // План и цель длинные: имя над репликой уступает место конвертам.
        if (sc.kind == SceneKind.talk) ...<Widget>[
          Text(_finniName, style: AppType.title(16, color: WorldColors.gold)),
          const SizedBox(height: 2),
        ],
        AnimatedSwitcher(
          duration: context.motion(Motion.state),
          // Реплика прижата влево, как имя над ней, а не по центру.
          layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
            alignment: Alignment.topLeft,
            children: <Widget>[...previous, if (current != null) current],
          ),
          // TalkBack читает новую реплику сам после «Дальше».
          child: Semantics(
            key: ValueKey<String>('onboarding:line:${sc.id}:$_line'),
            liveRegion: true,
            // ⚡ и 😊 — векторные значки, как на остальных экранах мира.
            child: PicText(
              line,
              style: const TextStyle(
                  fontSize: 18, height: 1.35, color: WorldColors.text),
            ),
          ),
        ),
        if (sc.showEnvelopes) ...<Widget>[
          const SizedBox(height: Gap.sm),
          EnvelopeCards(
              need: s.envelopes.need,
              want: s.envelopes.want,
              goal: s.envelopes.goal),
        ],
        if (sc.isPlan) ...<Widget>[
          const SizedBox(height: Gap.xs),
          PlanEditor(
            ui: s,
            snapshot: ws.snapshot,
            planning: ws.phase == WeekPhase.planning,
            needs: _needs,
            wants: _wants,
            goal: _goal,
            onChange: (int n, int w, int g) => setState(() {
              _needs = n;
              _wants = w;
              _goal = g;
            }),
          ),
        ],
        if (sc.isGoal) ...<Widget>[
          const SizedBox(height: Gap.sm),
          GoalPicker(
            ui: s,
            saved: ws.snapshot.goal,
            goals: onboardingGoals(ws.world.catalog),
            chosen: _goalId,
            reason: _goalReason,
            onChoose: _chooseGoal,
          ),
        ],
      ],
    );
  }

  /// Панель реплики: текст на тёмной панели, не на картинке (дизайн-система
  /// §1 п. 1); длинное (план, цели) прокручивается, «Дальше» — всегда внизу.
  Widget _panel(WorldState ws, {required bool compact}) => Material(
        color: WorldColors.panel,
        child: Column(
          // Портрет: панель по содержимому, остальное — комнате.
          mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Flexible(
              child: SingleChildScrollView(
                key: ValueKey<String>('onboarding:panel:$_scene'),
                padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, 0),
                child: _speech(ws),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  Gap.md, Gap.sm, Gap.md, compact ? Gap.sm : Gap.md),
              child: _nextButton(compact: compact),
            ),
          ],
        ),
      );

  Widget _scenesPortrait(WorldState ws) => Scaffold(
        backgroundColor: WorldColors.night,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Material(color: WorldColors.panel, child: _scenesBar()),
                Expanded(child: _room(ws)),
                ConstrainedBox(
                  // План и цель выше реплики: три конверта — без прокрутки.
                  constraints: BoxConstraints(
                      maxHeight: box.maxHeight *
                          (_current?.kind == SceneKind.talk ? 0.62 : 0.72)),
                  child: _panel(ws, compact: false),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _scenesLandscape(WorldState ws) => Scaffold(
        backgroundColor: WorldColors.night,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              // План и цели длиннее реплики: панели — больше ширины, чтобы
              // смысл конверта вставал в строку, а не по слову.
              final bool wide = _current?.kind != SceneKind.talk;
              final double side = (box.maxWidth * (wide ? 0.72 : 0.46))
                  .clamp(280.0, 560.0)
                  .toDouble();
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: _room(ws)),
                  SizedBox(
                    width: side,
                    child: Material(
                      color: WorldColors.panel,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _scenesBar(),
                          Expanded(child: _panel(ws, compact: true)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
}

/// Комната сценок: та же, что в S1, Финни выбранного облика подходит к
/// предмету сцены ([focus]).
class _SceneRoom extends StatefulWidget {
  const _SceneRoom({
    required this.profile,
    required this.snapshot,
    required this.focus,
    this.onFinniTap,
    this.onPiggyTap,
    this.onFridgeTap,
    this.onDoorTap,
    this.onBedTap,
  });

  final WorldProfile profile;
  final ResourceSnapshot snapshot;
  final String? focus;
  final VoidCallback? onFinniTap;
  final VoidCallback? onPiggyTap;
  final VoidCallback? onFridgeTap;
  final VoidCallback? onDoorTap;
  final VoidCallback? onBedTap;

  @override
  State<_SceneRoom> createState() => _SceneRoomState();
}

class _SceneRoomState extends State<_SceneRoom> {
  late final Future<RoomArt> _art = RoomArt.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<RoomArt>(
        future: _art,
        builder: (BuildContext context, AsyncSnapshot<RoomArt> a) => RoomScene(
          key: const ValueKey<String>('onboarding:stage'),
          art: a.data,
          stage: widget.snapshot.stage,
          species: widget.profile.species,
          idleTag: widget.profile.idleTag,
          finniName: widget.profile.finniName,
          happiness: widget.snapshot.happiness,
          fridge: fridgeOf(widget.snapshot),
          focus: widget.focus,
          // Имя — над репликой; табличка в углу легла бы на дверь.
          showName: false,
          // Полоса комнаты над планом узкая — без швов по бокам.
          cover: true,
          onFinniTap: widget.onFinniTap,
          onPiggyTap: widget.onPiggyTap,
          onFridgeTap: widget.onFridgeTap,
          onDoorTap: widget.onDoorTap,
          onBedTap: widget.onBedTap,
        ),
      );
}

/// Левая панель альбомной регистрации: комната из S1 с Финни выбранного
/// вида и облика в целом масштабе.
class _Stage extends StatefulWidget {
  const _Stage({required this.profile, required this.snapshot});

  final WorldProfile profile;
  final ResourceSnapshot snapshot;

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  late final Future<RoomArt> _art = RoomArt.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<RoomArt>(
        future: _art,
        builder: (BuildContext context, AsyncSnapshot<RoomArt> a) => RoomScene(
          key: const ValueKey<String>('onboarding:stage'),
          art: a.data,
          stage: widget.snapshot.stage,
          species: widget.profile.species,
          idleTag: widget.profile.idleTag,
          finniName: widget.profile.finniName,
          happiness: widget.snapshot.happiness,
        ),
      );
}
