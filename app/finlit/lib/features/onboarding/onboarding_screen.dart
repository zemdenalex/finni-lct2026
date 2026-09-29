import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/feel.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/world_art.dart';
import '../../domain/models/catalog_item.dart';
import '../../domain/models/goal.dart';
import '../../domain/models/envelope.dart';
import '../../domain/models/pet.dart';
import '../../domain/models/profile.dart';
import '../../routes.dart';

/// Знакомство с игрой (§2.5.1) — и оно же подсказка (§2.5.1.3).
///
/// 🔴 Один экран на две роли. §2.5.1.3 требует «возможность вернуться к
/// подсказке в любой момент», и второй, отдельный экран справки означал бы
/// два текста, которые расходятся на третьей правке. Роль различается по
/// [Navigator.canPop]: если вернуться некуда — это первый запуск, и в конце
/// стоит «Поехали»; если есть куда — это подсказка с главного, и в конце
/// стоит «Закрыть».
///
/// §2.5.1.2: работа в гостевом режиме. Здесь не спрашивается ни имя ребёнка,
/// ни возраст, ни почта — §3.5.1 требует, чтобы обязательный сценарий
/// проходился без сбора персональных данных.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next(int total) {
    if (_index >= total - 1) {
      _finish();
      return;
    }
    _goTo(_index + 1);
  }

  void _back() {
    if (_index == 0) return;
    _goTo(_index - 1);
  }

  /// Переход к странице знакомства.
  ///
  /// 🔴 §3.6.7: при выключённых анимациях (или системном «уменьшить
  /// движение») страница меняется мгновенно. Ветка нужна именно ветка:
  /// [PageController.animateToPage] с нулевой длительностью не «не
  /// анимирует», а падает на assert внутри DrivenScrollActivity.
  void _goTo(int page) {
    if (!context.motionOn) {
      _pages.jumpToPage(page);
      return;
    }
    // Переход страницы — не украшение, а обратная связь на нажатие, поэтому
    // длительность короткая.
    _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _finish() {
    if (Navigator.canPop(context)) {
      // Подсказка, открытая с главного: возвращаемся туда, откуда пришли.
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacementNamed<void, void>(context, AppRoutes.petCreate);
  }

  @override
  Widget build(BuildContext context) {
    // Профиль нужен только для картинки: если ребёнок уже собрал своего
    // Финни, подсказка показывает именно его. Тип нулевой — экран обязан
    // открываться и до того, как появилось состояние игры (§2.5.1.2).
    final AppState? app = context.watch<AppState?>();
    final bool ready = app != null && app.ready;
    final PetSpecies species =
        ready ? app.game.profile.species : PetSpecies.squirrel;
    final PetPalette palette =
        ready ? app.game.profile.palette : PetPalette.mint;
    final String petName = ready ? app.game.profile.petName : 'Финни';

    final List<_Slide> slides = <_Slide>[
      _Slide(
        // §2.5.1.1: цель игры. «Учитесь вместе», а не «ухаживай»: ребёнок
        // здесь напарник, который умеет, а не тот, кого отчитывают.
        title: 'Это $petName',
        text: 'Ты учишь его обращаться с монетками. '
            'От твоих решений меняется его комната.',
        picture: _ScenePicture(species: species, palette: palette),
      ),
      const _Slide(
        // §2.5.1.1 дословно: три типа решений — потратить на обязательное,
        // потратить на желаемое, отложить. У каждого — своё последствие.
        // 🔴 Конверты и решения — одна страница: на двух подряд они
        // повторяли одно и то же (третья критика).
        title: 'Три конверта',
        text: 'Монетки живут в трёх конвертах. Каждую ты решаешь, куда '
            'отправить.',
        picture: _DecisionsPicture(),
      ),
      _Slide(
        // Освободившаяся страница — обещание: зачем всё это. Мечта стоит
        // в комнате и проявляется по мере накоплений.
        title: 'Мечта в комнате',
        text: 'Выбери, на что копить, — мечта встанет в комнате и будет '
            'проявляться, пока откладываешь.',
        picture: _ScenePicture(
            species: species, palette: palette, withDream: true),
      ),
      const _Slide(
        title: 'Откуда монетки',
        text: 'Часть монеток доверяют родители, часть ты зарабатываешь '
            'за задания. Новые приходят каждую неделю.',
        picture: _CoinsPicture(),
      ),
    ];

    final bool canPop = Navigator.canPop(context);
    final bool last = _index == slides.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Как играть'),
        leading: canPop
            ? IconButton(
                tooltip: 'Закрыть подсказку',
                icon: const Pictogram(Pic.cross, color: AppColors.ink),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: slides.length,
                onPageChanged: (int i) => setState(() => _index = i),
                itemBuilder: (BuildContext context, int i) => _SlideView(
                  slide: slides[i],
                  number: i + 1,
                  total: slides.length,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
              child: Column(
                children: <Widget>[
                  _Dots(index: _index, total: slides.length),
                  const SizedBox(height: Gap.sm),
                  FilledButton(
                    onPressed: () => _next(slides.length),
                    child: Text(
                      last ? (canPop ? 'Закрыть' : 'Поехали') : 'Дальше',
                    ),
                  ),
                  SizedBox(
                    height: TapSize.min,
                    child: _index == 0
                        ? const SizedBox.shrink()
                        : TextButton(
                            onPressed: _back,
                            child: const Text('Назад'),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Одна страница знакомства: картинка, заголовок в два слова и одна фраза.
///
/// Растровых ассетов в проекте нет принципиально (§3.3 — право на
/// использование изображений), поэтому картинки — это сцена, Финни и
/// пиктограммы, нарисованные кодом.
class _Slide {
  const _Slide(
      {required this.title, required this.text, required this.picture});

  final String title;
  final String text;
  final Widget picture;
}

class _SlideView extends StatelessWidget {
  const _SlideView({
    required this.slide,
    required this.number,
    required this.total,
  });

  final _Slide slide;
  final int number;
  final int total;

  @override
  Widget build(BuildContext context) {
    // Прокрутка внутри страницы: при системном увеличении шрифта (§3.6.4)
    // картинка и фраза перестают помещаться на маленьком экране, и лучше
    // проскроллить, чем обрезать.
    final Widget picture = Semantics(
      label: 'Страница $number из $total',
      child: slide.picture,
    );
    final List<Widget> words = <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
        child: Semantics(
          header: true,
          child: Text(slide.title, style: AppType.title(26)),
        ),
      ),
      const SizedBox(height: Gap.sm),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
        child: Text(
          slide.text,
          style: const TextStyle(
            fontSize: 20,
            height: 1.4,
            color: AppColors.ink,
          ),
        ),
      ),
    ];
    // 🔴 При крупном системном шрифте слова идут первыми, картинка — под
    // ними. Тот, кто увеличил шрифт, пришёл читать, а при картинке сверху
    // фраза на 360×640 уходила под точки страниц и обрезалась на полуслове
    // (test/features/onboarding_fits_test.dart). Прокрутка есть, но
    // догадаться листать страницу вниз ребёнок не обязан.
    final bool wordsFirst = MediaQuery.textScalerOf(context).scale(1) > 1.15;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: wordsFirst
            ? <Widget>[...words, const SizedBox(height: Gap.lg), picture]
            : <Widget>[picture, const SizedBox(height: Gap.lg), ...words],
      ),
    );
  }
}

/// Комната Финни — пустая, с чертежом мечты: сразу видно, во что
/// превращаются решения.
class _ScenePicture extends StatelessWidget {
  const _ScenePicture({
    required this.species,
    required this.palette,
    this.withDream = false,
  });

  final PetSpecies species;
  final PetPalette palette;

  /// Показать мечту, накопленную наполовину, — страница-обещание.
  final bool withDream;

  static const Goal _house = Goal(
    id: 'house',
    title: 'Домик',
    price: 30,
    isExperience: false,
    icon: 'house',
  );

  @override
  Widget build(BuildContext context) {
    // На низком экране (360×640) комната во всю ширину оставляла фразе
    // одну строку над кнопкой. Ширина сцены ограничена высотой экрана:
    // под картинкой всегда остаётся место для заголовка и фразы.
    // 🔴 Место под текст растёт вместе с системным шрифтом (§3.6.4): при 1,5
    // фиксированный запас оставлял фразу обрезанной под точками страниц —
    // на полуслове, и догадаться, что страницу надо листать вниз, нельзя.
    final double textRoom = 380 * MediaQuery.textScalerOf(context).scale(1);
    final double maxW =
        (MediaQuery.sizeOf(context).height - textRoom) / RoomLayout.aspect;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW.clamp(200.0, 600.0)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.scene),
          child: RoomView(
            scene: RoomScene(
              stage: PetStage.novice,
              keepsakes: const <(CatalogItem, int)>[],
              goal: withDream ? _house : null,
              saved: withDream ? 14 : 0,
            ),
            species: species,
            palette: palette,
            meters: const PetMeters(fullness: 8, cleanliness: 8, mood: 9),
          ),
        ),
      ),
    );
  }
}

/// Три типа решений (§2.5.1.1) — и что из каждого получается.
class _DecisionsPicture extends StatelessWidget {
  const _DecisionsPicture();

  @override
  Widget build(BuildContext context) {
    const List<(Envelope, String, String)> decisions =
        <(Envelope, String, String)>[
      (Envelope.needs, 'Потратить на нужное', 'Финни сыт и в чистоте'),
      (
        Envelope.wants,
        'Потратить на то, что хочется',
        'вещь появится в комнате'
      ),
      (Envelope.savings, 'Отложить в копилку', 'мечта станет ближе'),
    ];
    return Column(
      children: <Widget>[
        for (final (Envelope e, String label, String result) in decisions)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm + 2),
            child: Container(
              constraints: const BoxConstraints(minHeight: TapSize.min),
              padding: const EdgeInsets.fromLTRB(
                  Gap.md, Gap.sm + 4, Gap.md, Gap.sm + 4),
              decoration: BoxDecoration(
                color: AppColors.bgOf(e),
                borderRadius: BorderRadius.circular(Radii.envelope),
                // Без уступа: это пример, а не кнопка.
                border: Border.all(color: AppColors.of(e), width: 2),
              ),
              child: Row(
                children: <Widget>[
                  Pictogram(AppColors.picOf(e),
                      size: 32, color: AppColors.of(e)),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(label,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink)),
                        Text(result,
                            style: const TextStyle(
                                fontSize: 16, color: AppColors.ink)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Откуда монетки: доверили родители + заработано самому, и предел недели.
class _CoinsPicture extends StatelessWidget {
  const _CoinsPicture();

  @override
  Widget build(BuildContext context) {
    return const Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Например, неделя Финни',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          SizedBox(height: Gap.md),
          // Пример, а не данные игры: 10 от родителей и 3 за задания — те же
          // 13 монеток, что разложены в конверты на второй странице.
          TrustBar(fromParents: 10, earnCap: 4, earned: 3),
        ],
      ),
    );
  }
}

/// Индикатор страниц. Подпись словами — потому что точки не читает
/// ни экранный диктор, ни ребёнок, который их не заметил.
class _Dots extends StatelessWidget {
  const _Dots({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Страница ${index + 1} из $total',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(total, (int i) {
          final bool on = i == index;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
            child: Container(
              width: on ? 14 : 12,
              height: on ? 14 : 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: on ? AppColors.primary : AppColors.line,
                  width: 2,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
