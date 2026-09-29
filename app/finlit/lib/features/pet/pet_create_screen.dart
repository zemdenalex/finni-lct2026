import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/feel.dart';
import '../../core/finni_art.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../domain/ledger/ledger_fold.dart';
import '../../domain/models/pet.dart';
import '../../domain/models/profile.dart';
import '../../routes.dart';

/// Создание питомца (§2.5.2) — и повторная настройка.
///
/// §2.5.2.1 внешний вид, §2.5.2.2 игровое имя. §2.6 требует «не менее 9
/// визуально различимых комбинаций», а способом проверки называет «создание
/// двух разных профилей или повторную настройку» — поэтому экран обязан
/// открываться второй раз и показывать текущий выбор, а не сбрасывать его.
/// Роль различается по [Navigator.canPop]: вернуться некуда — первый запуск,
/// есть куда — правка.
///
/// Персональных данных здесь нет: имя питомца ими не является (§3.5.1).
class PetCreateScreen extends StatefulWidget {
  const PetCreateScreen({super.key});

  @override
  State<PetCreateScreen> createState() => _PetCreateScreenState();
}

class _PetCreateScreenState extends State<PetCreateScreen>
    with SingleTickerProviderStateMixin {
  /// Готовые имена. 🔴 Для семилетки экранная клавиатура — барьер: поле уже
  /// заполнено, а рядом лежат варианты в одно касание. Печатать можно,
  /// но не обязательно.
  static const List<String> _suggestions = <String>[
    'Финни',
    'Монетка',
    'Пушок',
    'Тишка',
    'Умник',
  ];

  static const String _fallbackName = 'Финни';

  PetSpecies? _species;
  PetPalette? _palette;
  TextEditingController? _name;

  /// Кивок предпросмотра в ответ на выбор.
  ///
  /// 🔴 Значение покоя — 1, а не 0: пока ребёнок ничего не выбрал, Финни
  /// обязан сидеть неподвижно. Анимация здесь запускается только из
  /// обработчика касания — §6 «ничего не двигается само по себе».
  /// 🔴 Создаётся в initState, а не лениво: до неготового состояния экран
  /// возвращает заглушку, и первым обращением к полю оказался бы dispose —
  /// тикер на отсоединённом элементе.
  late final AnimationController _nodding;
  late final CurvedAnimation _nod;

  @override
  void initState() {
    super.initState();
    _nodding =
        AnimationController(vsync: this, duration: Motion.nod, value: 1);
    _nod = CurvedAnimation(parent: _nodding, curve: Motion.nodCurve);
  }

  /// Ребёнок выбрал другого зверя или другой цвет — Финни отвечает кивком.
  void _answer(VoidCallback change) {
    setState(change);
    _nodding
      ..duration = context.motion(Motion.nod)
      ..forward(from: 0);
  }

  /// Имя, с которым экран открылся: к нему возвращает «Оставить как есть».
  String _initialName = _fallbackName;

  @override
  void dispose() {
    _name?.dispose();
    _nod.dispose();
    _nodding.dispose();
    super.dispose();
  }

  /// Состояние подхватывается из профиля один раз — иначе повторная настройка
  /// начиналась бы с котёнка вместо того, что ребёнок уже выбрал.
  void _ensureInitialised(GameProfile p) {
    if (_name != null) return;
    _species = p.species;
    _palette = p.palette;
    _initialName = p.petName;
    _name = TextEditingController(text: p.petName);
  }

  Future<void> _submit() async {
    final AppState app = context.read<AppState>();
    final String typed = _name?.text.trim() ?? '';
    await app.updateProfile(app.game.profile.copyWith(
      species: _species,
      palette: _palette,
      // Пустое поле — не ошибка и не повод ругаться: имя просто остаётся
      // прежним. Ребёнок не обязан ничего печатать (§2.2, безопасная ошибка).
      petName: typed.isEmpty ? _fallbackName : typed,
    ));
    if (!mounted) return;
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }
    await Navigator.pushNamedAndRemoveUntil<void>(
      context,
      AppRoutes.home,
      (Route<dynamic> r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    if (!app.ready) {
      return const Scaffold(body: Center(child: Text('Финни')));
    }
    _ensureInitialised(app.game.profile);

    final PetSpecies species = _species ?? PetSpecies.squirrel;
    final PetPalette palette = _palette ?? PetPalette.mint;
    final GameSnapshot snap = app.game.snapshot;
    final bool editing = Navigator.canPop(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Изменить Финни' : 'Твой Финни'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xl),
          children: <Widget>[
            // Живой предпросмотр: любое касание кнопки видно сразу здесь.
            // И не только видно — Финни отвечает кивком, иначе выбор
            // выглядит как переключение картинки в каталоге.
            Center(
              child: Container(
                width: 208,
                height: 208,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[SceneColors.skyTop, SceneColors.skyLow],
                  ),
                  border: Border.all(color: AppColors.ink, width: 2.5),
                ),
                child: FinniView(
                  species: species,
                  palette: palette,
                  stage: snap.stage,
                  meters: snap.meters,
                  accessories: app.game.profile.accessories,
                  size: 168,
                  hop: _nod,
                ),
              ),
            ),
            const SizedBox(height: Gap.sm),
            Center(
              child: Text(
                '${species.title}, ${palette.title.toLowerCase()}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ),
            const SizedBox(height: Gap.md),
            const _Heading('Кто он'),
            const SizedBox(height: Gap.sm),
            Row(
              children: <Widget>[
                for (final PetSpecies s in PetSpecies.values) ...<Widget>[
                  Expanded(
                    child: _SpeciesButton(
                      species: s,
                      palette: palette,
                      selected: s == species,
                      onTap: () => _answer(() => _species = s),
                    ),
                  ),
                  if (s != PetSpecies.values.last)
                    const SizedBox(width: Gap.sm),
                ],
              ],
            ),
            const SizedBox(height: Gap.lg),
            const _Heading('Какого он цвета'),
            const SizedBox(height: Gap.sm),
            // Расцветки строками, а не колонками: «Абрикосовый» — одно длинное
            // слово, в колонке шириной в треть экрана оно обрезается при
            // системном увеличении шрифта (§3.6.4).
            for (final PetPalette p in PetPalette.values) ...<Widget>[
              _PaletteRow(
                palette: p,
                species: species,
                selected: p == palette,
                onTap: () => _answer(() => _palette = p),
              ),
              if (p != PetPalette.values.last) const SizedBox(height: Gap.sm),
            ],
            const SizedBox(height: Gap.lg),
            const _Heading('Как его зовут'),
            const SizedBox(height: Gap.sm),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: 16,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                filled: true,
                fillColor: AppColors.surface,
                counterText: '',
                border: OutlineInputBorder(),
                helperText: 'Имя уже готово — можно ничего не печатать',
                helperMaxLines: 2,
                helperStyle: TextStyle(fontSize: 16, color: AppColors.inkSoft),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: <Widget>[
                for (final String s in _suggestions)
                  _NameChip(
                    label: s,
                    selected: _name?.text.trim() == s,
                    onTap: () => setState(() {
                      _name?.text = s;
                      FocusScope.of(context).unfocus();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              icon: const Pictogram(Pic.undo, color: AppColors.primary),
              label: Text('Оставить как есть: $_initialName'),
              onPressed: () => setState(() {
                _name?.text = _initialName;
                FocusScope.of(context).unfocus();
              }),
            ),
            const SizedBox(height: Gap.lg),
            FilledButton(
              onPressed: _submit,
              child: Text(editing ? 'Сохранить' : 'Готово'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(text,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      );
}

/// Кнопка выбора вида с предпросмотром.
///
/// Выбранное отмечено рамкой **и** галочкой с подписью: §3.6.5 запрещает
/// делать цвет единственным носителем смысла.
class _SpeciesButton extends StatelessWidget {
  const _SpeciesButton({
    required this.species,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final PetSpecies species;
  final PetPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${species.title}${selected ? ', выбрано' : ''}',
      excludeSemantics: true,
      child: Material(
        color: selected ? const Color(0xFFFFF4D6) : AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.envelope),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.envelope),
          child: Container(
            constraints: const BoxConstraints(minHeight: TapSize.primary + 40),
            padding: const EdgeInsets.symmetric(
                horizontal: Gap.xs, vertical: Gap.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.envelope),
              border: Border.all(
                color: selected ? AppColors.ink : AppColors.line,
                width: selected ? 3 : 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FinniView(
                  species: species,
                  palette: palette,
                  stage: PetStage.novice,
                  meters: const PetMeters(fullness: 8, cleanliness: 8, mood: 9),
                  size: 64,
                ),
                Text(
                  species.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Pictogram(
                  selected ? Pic.check : Pic.circleEmpty,
                  size: 22,
                  color: selected ? AppColors.ink : AppColors.inkSoft,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.palette,
    required this.species,
    required this.selected,
    required this.onTap,
  });

  final PetPalette palette;
  final PetSpecies species;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final FinniPalette colors = FinniPalette.of(palette);
    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.title}${selected ? ', выбрано' : ''}',
      excludeSemantics: true,
      child: Material(
        color: selected ? const Color(0xFFFFF4D6) : AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.envelope),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.envelope),
          child: Container(
            constraints: const BoxConstraints(minHeight: TapSize.min),
            padding: const EdgeInsets.all(Gap.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.envelope),
              border: Border.all(
                color: selected ? AppColors.ink : AppColors.line,
                width: selected ? 3 : 2,
              ),
            ),
            child: Row(
              children: <Widget>[
                FinniView(
                  species: species,
                  palette: palette,
                  stage: PetStage.novice,
                  meters: const PetMeters(fullness: 8, cleanliness: 8, mood: 9),
                  size: 52,
                ),
                const SizedBox(width: Gap.sm),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colors.body,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.shade, width: 2),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    palette.title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                Pictogram(
                  selected ? Pic.check : Pic.circleEmpty,
                  size: 26,
                  color: selected ? AppColors.ink : AppColors.inkSoft,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Назвать $label',
      excludeSemantics: true,
      child: Material(
        color: selected ? const Color(0xFFFFF4D6) : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: TapSize.min),
            // Высота добирается отступом, а не выравниванием: Container
            // с alignment растягивается на всю ширину Wrap, и чип имени
            // превращался в полосу через весь экран.
            padding: const EdgeInsets.symmetric(
                horizontal: Gap.md + 2, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.ink : AppColors.line,
                width: selected ? 3 : 2,
              ),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}
