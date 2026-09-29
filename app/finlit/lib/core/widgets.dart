import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../app_state.dart';
import '../domain/game.dart' show ActionResult, Game;
import '../domain/phrases.dart';
import 'feel.dart';
import 'finni_art.dart';
import 'icons.dart';
import 'speaker.dart';
import '../domain/models/envelope.dart';
import '../domain/models/pet.dart';
import 'theme.dart';
import 'world_art.dart';
import 'world_theme.dart';

/// Сумма монеток. Всегда с монеткой рядом: «12» без единицы измерения
/// семилетке ничего не говорит.
///
/// Число набрано второй гарнитурой — Unbounded: монетки — самое важное
/// число в игре, и оно должно выглядеть как число из игры, а не из анкеты.
class Coins extends StatelessWidget {
  const Coins(this.amount, {super.key, this.size = 20, this.color});

  final int amount;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$amount ${_word(amount)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CoinDot(size: size * 1.05),
          SizedBox(width: size * 0.28),
          Text('$amount',
              style: AppType.number(size * 0.92,
                  color: color ??
                      (Theme.of(context).brightness == Brightness.dark
                          ? WorldColors.text
                          : AppColors.ink))),
        ],
      ),
    );
  }

  static String _word(int n) {
    final int m10 = n % 10;
    final int m100 = n % 100;
    if (m100 >= 11 && m100 <= 14) return 'монеток';
    if (m10 == 1) return 'монетка';
    if (m10 >= 2 && m10 <= 4) return 'монетки';
    return 'монеток';
  }

  /// «раз / раза / раз» — для числа решений, а не монеток.
  static String timesWord(int n) => Phrases.timesWord(n);

  static String word(int n) => _word(n);

  /// Винительный падеж: «взять одну монетку», а не «взять 1 монетка».
  static String wordAccusative(int n) {
    final int m10 = n % 10;
    final int m100 = n % 100;
    if (m100 >= 11 && m100 <= 14) return 'монеток';
    if (m10 == 1) return 'монетку';
    if (m10 >= 2 && m10 <= 4) return 'монетки';
    return 'монеток';
  }
}

/// Монетка — та же, что в лапках у Финни: золото, внутренний ободок и
/// чернильный контур.
class CoinDot extends StatelessWidget {
  const CoinDot({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child:
            CustomPaint(size: Size.square(size), painter: const _CoinPainter()),
      );
}

class _CoinPainter extends CustomPainter {
  const _CoinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.shortestSide / 2;
    final Offset c = size.center(Offset.zero);
    canvas.drawCircle(c, r * 0.92, Paint()..color = AppColors.coin);
    canvas.drawCircle(
        c,
        r * 0.58,
        Paint()
          ..color = AppColors.coinDeep
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.16);
    canvas.drawCircle(
        c,
        r * 0.92,
        Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.15);
  }

  @override
  bool shouldRepaint(_CoinPainter old) => false;
}

/// Белая поверхность со сплошным нижним краем — «плашка на столе».
///
/// 🔴 Одна на весь продукт. Раньше каждый экран собирал свою карточку из
/// `Card` и рамок, и радиусы с отступами расходились от экрана к экрану.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.md),
    this.color = AppColors.surface,
    this.edge = Paper.edge,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color edge;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    // Тёмная тема мира (`WorldTheme`): белая плашка по умолчанию становится
    // тёмной плиткой, иначе светлый текст мира ложится на белое.
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color color = dark && this.color == AppColors.surface
        ? WorldColors.raised
        : this.color;
    final Color edge =
        dark && this.edge == Paper.edge ? WorldColors.line : this.edge;
    final BorderRadius radius = BorderRadius.circular(Radii.envelope);
    Widget body = Padding(padding: padding, child: child);
    if (onTap != null) {
      body = InkWell(onTap: onTap, borderRadius: radius, child: body);
    }
    // 🔴 Уступ — только у того, что нажимается. У справочной панели —
    // ровная рамка: иначе по виду нельзя отличить кнопку от сведений.
    final Widget panel = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: onTap == null
            ? null
            : Paper.cut(dark ? WorldColors.raisedEdge : edge),
      ),
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: edge, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: body,
      ),
    );
    if (semanticLabel == null) return panel;
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: panel,
    );
  }
}

/// Заголовок раздела внутри экрана: пиктограмма и слово.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.icon, this.color});

  final String text;
  final Pic? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Pictogram(icon!, size: 26, color: color ?? AppColors.primary),
            const SizedBox(width: Gap.sm),
          ],
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
          ),
        ],
      ),
    );
  }
}

/// Шкала состояния питомца.
///
/// §3.6.5: цвет не единственный носитель смысла — рядом иконка, подпись
/// словами и заполненные точки, которые видно в градациях серого.
///
/// Точки загораются по одной (§6 «Движения»): показатель вырос на две —
/// видно, что загорелись именно две, и какие.
class MeterRow extends StatefulWidget {
  const MeterRow({
    super.key,
    required this.meter,
    required this.value,
    this.compact = false,
  });

  final Meter meter;
  final int value;

  /// Столбиком для трёх шкал в ряд: пиктограмма и название, под ними
  /// точки. Состояние словами — в подписи для TalkBack и на экране
  /// прогресса; на главном место нужно комнате и главной кнопке.
  final bool compact;

  /// Сколько точек горит при таком значении. Одна точка — два очка.
  static int dotsOf(int value) => (value / 2).round().clamp(0, 5);

  @override
  State<MeterRow> createState() => _MeterRowState();
}

class _MeterRowState extends State<MeterRow>
    with SingleTickerProviderStateMixin {
  /// 🔴 Создаётся в initState, а не лениво при объявлении: поле, до которого
  /// впервые дошли из dispose, создаёт тикер на уже отсоединённом элементе.
  late final AnimationController _fill;

  /// Сколько точек горело до роста — с них начинается заливка.
  late int _from;

  @override
  void initState() {
    super.initState();
    _fill = AnimationController(
      vsync: this,
      duration: Motion.meterDot,
      // 1 — покой: точки уже на местах. Первый кадр экрана ничего не
      // разжигает — §6 разрешает движение только в ответ на действие.
      value: 1,
    );
    _from = MeterRow.dotsOf(widget.value);
  }

  @override
  void didUpdateWidget(MeterRow old) {
    super.didUpdateWidget(old);
    final int before = MeterRow.dotsOf(old.value);
    final int now = MeterRow.dotsOf(widget.value);
    if (now == before) return;
    // 🔴 Без setState: didUpdateWidget вызывается внутри перестроения.
    // Убавление показывается сразу: «стало меньше» растягивать незачем.
    if (now < before) {
      _from = now;
      _fill.value = 1;
      return;
    }
    _from = before;
    _fill
      ..duration = context.motion(Motion.meterDot * (now - before))
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget dots = CustomPaint(
      size: const Size(_MeterDots.width, _MeterDots.dot),
      painter: _MeterDots(
        progress: _fill,
        from: _from,
        to: MeterRow.dotsOf(widget.value),
      ),
    );
    if (widget.compact) {
      return Semantics(
        label: '${widget.meter.title}: ${widget.meter.label(widget.value)}, '
            '${widget.value} из ${PetMeters.max}',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Название — отдельной строкой: рядом с пиктограммой
            // «Настроение» не влезало в треть экрана и ужималось ниже 16 sp.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(widget.meter.title,
                  maxLines: 1,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
            ),
            const SizedBox(height: Gap.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Pictogram(_pic, size: 18, color: AppColors.primary),
                  const SizedBox(width: 3),
                  dots,
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Semantics(
      label: '${widget.meter.title}: ${widget.meter.label(widget.value)}, '
          '${widget.value} из ${PetMeters.max}',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Pictogram(_pic, size: 24, color: AppColors.primary),
          const SizedBox(width: Gap.sm),
          // Название шкалы — и под ним состояние словами. Одна фраза
          // «пора прибраться» рядом с двумя точками читалась двояко:
          // две точки чистоты или две точки беспорядка? Название делает
          // шкалу однозначной: точек больше — лучше.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  widget.meter.title,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink),
                ),
                Text(
                  widget.meter.label(widget.value),
                  style:
                      const TextStyle(fontSize: 16, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          // 🔴 Точки рисует painter: кадр заливки — только repaint.
          CustomPaint(
            size: const Size(_MeterDots.width, _MeterDots.dot),
            painter: _MeterDots(
              progress: _fill,
              from: _from,
              to: MeterRow.dotsOf(widget.value),
            ),
          ),
        ],
      ),
    );
  }

  Pic get _pic => switch (widget.meter) {
        Meter.fullness => Pic.bowl,
        Meter.cleanliness => Pic.drop,
        Meter.mood => Pic.smile,
      };
}

/// Пять точек показателя: от [from] загоревшихся к [to].
class _MeterDots extends CustomPainter {
  _MeterDots({
    required this.progress,
    required this.from,
    required this.to,
  }) : super(repaint: progress);

  static const double dot = 15;
  static const double step = 19;
  static const double width = step * 5;

  final Animation<double> progress;
  final int from;
  final int to;

  final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final Paint _core = Paint()
    ..style = PaintingStyle.fill
    ..color = AppColors.primary;

  static const Color _emptyRing = Color(0xFF7A8A7D);

  @override
  void paint(Canvas canvas, Size size) {
    final double lit = from + (to - from) * progress.value;
    for (int i = 0; i < 5; i++) {
      final double k = (lit - i).clamp(0.0, 1.0);
      final Offset c = Offset(i * step + dot / 2, size.height / 2);
      // Пустая точка — обводкой 3:1 к белому: иначе «2 из 5» читалось
      // как «2», максимума шкалы не было видно.
      _ring.color = Color.lerp(_emptyRing, AppColors.primary, k)!;
      canvas.drawCircle(c, dot / 2 - 1, _ring);
      if (k > 0) canvas.drawCircle(c, dot / 2 * k, _core);
    }
  }

  @override
  bool shouldRepaint(_MeterDots old) =>
      old.from != from || old.to != to || old.progress != progress;
}

/// Число, которое досчитывает до нового значения, а не прыгает.
///
/// Конечное значение всегда равно модели: анимируется только показ.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.builder});

  final int value;
  final Widget Function(BuildContext context, int shown) builder;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // begin не задан: первый показ числа — не событие.
      tween: Tween<double>(end: value.toDouble()),
      duration: context.motion(Motion.count),
      curve: Motion.travel,
      builder: (BuildContext c, double v, Widget? _) => builder(c, v.round()),
    );
  }
}

/// Конверт — настоящей формы: с клапаном-треугольником сверху.
///
/// Цвет, пиктограмма, название, сумма: четыре канала смысла вместо одного.
class EnvelopeCard extends StatelessWidget {
  const EnvelopeCard({
    super.key,
    required this.envelope,
    required this.amount,
    this.planned,
    this.onTap,
    this.compact = false,
  });

  final Envelope envelope;
  final int amount;
  final int? planned;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color c = AppColors.of(envelope);
    final Widget content = Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (compact) ...<Widget>[
          // 🔴 Иконка над названием, а не рядом: три конверта в ряд на
          // 360 dp дают около 104 dp на конверт, и «Копилка» рядом с иконкой
          // ломалась на три строки.
          Pictogram(AppColors.picOf(envelope), size: 24, color: c),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(envelope.title,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: c)),
          ),
        ] else
          Row(
            children: <Widget>[
              Pictogram(AppColors.picOf(envelope), size: 24, color: c),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: Text(envelope.title,
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800, color: c)),
              ),
            ],
          ),
        const SizedBox(height: Gap.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Coins(amount, size: compact ? 20 : 24),
        ),
        if (planned != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('план $planned',
                  style:
                      const TextStyle(fontSize: 16, color: AppColors.inkSoft)),
            ),
          ),
      ],
    );

    return Semantics(
      button: onTap != null,
      label: 'Конверт «${envelope.title}», $amount ${Coins.word(amount)}'
          '${planned == null ? '' : ', по плану $planned'}',
      excludeSemantics: true,
      child: CustomPaint(
        painter: _EnvelopeShape(color: c, fill: AppColors.bgOf(envelope)),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Radii.chip),
            child: Container(
              constraints: BoxConstraints(
                  minHeight: compact ? 84 : TapSize.primary + 24),
              padding: EdgeInsets.fromLTRB(
                  compact ? Gap.xs : Gap.md,
                  compact ? Gap.md + 2 : Gap.md + 6,
                  compact ? Gap.xs : Gap.md,
                  compact ? Gap.sm + 2 : Gap.md),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Контур конверта: прямоугольник, клапан-треугольник и уступ снизу.
class _EnvelopeShape extends CustomPainter {
  const _EnvelopeShape({required this.color, required this.fill});

  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const double r = Radii.chip;
    const double edge = 4;
    final Rect body = Rect.fromLTWH(0, 0, size.width, size.height - edge);
    final RRect rr = RRect.fromRectAndRadius(body, const Radius.circular(r));
    // Уступ снизу — цвет конверта: конверт «стоит» на столе.
    canvas.drawRRect(rr.shift(const Offset(0, edge)), Paint()..color = color);
    canvas.drawRRect(rr, Paint()..color = fill);
    // Клапан — неглубокий треугольник от верхних углов к середине.
    final Path flap = Path()
      ..moveTo(r * 0.6, 1)
      ..lineTo(size.width / 2, math.min(size.height * 0.24, 22))
      ..lineTo(size.width - r * 0.6, 1);
    canvas.drawPath(
        flap,
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
    canvas.drawRRect(
        rr.deflate(1),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_EnvelopeShape old) =>
      old.color != color || old.fill != fill;
}

/// Крупная кнопка раздела: пиктограмма в круге и слово.
///
/// Горизонтальная, а не квадратная плитка: у квадрата в три колонки на
/// 360 dp подпись была 15 sp — ниже нашей нормы.
class SectionTile extends StatelessWidget {
  const SectionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.badge,
    this.tint = AppColors.primary,
  });

  final Pic icon;
  final String title;
  final VoidCallback onTap;
  final String? badge;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: badge == null ? title : '$title, $badge',
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onTap,
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll<Size>(Size(0, TapSize.primary)),
          padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.sm, Gap.sm + 3)),
          alignment: Alignment.centerLeft,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Pictogram(icon, size: 26, color: tint),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  if (badge != null)
                    Text(badge!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.inkSoft)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Откуда монетки этой недели: сколько доверили родители и сколько
/// заработано самому — и сколько ещё можно.
///
/// 🔴 Главный продуктовый тезис команды — взросление как рост
/// самостоятельности — здесь виден каждую неделю, а не только на питче:
/// серый отрезок «от родителей» с каждой стадией короче, золотой
/// «заработал сам» — длиннее. Лимит подработки нарисован заранее
/// пунктиром: ребёнок видит его до того, как упрётся, а не узнаёт
/// о нём постфактум.
class TrustBar extends StatelessWidget {
  const TrustBar({
    super.key,
    required this.fromParents,
    required this.earnCap,
    required this.earned,
    this.showLegend = true,
    this.height = 18,
  });

  final int fromParents;
  final int earnCap;
  final int earned;
  final bool showLegend;
  final double height;

  /// Доля родителей — своим тёплым цветом, а не серым: серый на первом
  /// проходе читался как «выключено» или «уже потрачено».
  static const Color parents = Color(0xFF6FB3D9);

  @override
  Widget build(BuildContext context) {
    final int left = math.max(0, earnCap - earned);
    final String legend = left > 0
        ? '$fromParents от родителей, $earned за задания, '
            'можно ещё $left'
        : '$fromParents от родителей, $earned за задания. '
            'Больше на этой неделе заработать нельзя';
    return Semantics(
      label: legend,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CustomPaint(
            size: Size(double.infinity, height),
            painter: _TrustPainter(
              parents: fromParents,
              cap: earnCap,
              earned: math.min(earned, earnCap),
            ),
          ),
          if (showLegend) ...<Widget>[
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.md,
              runSpacing: Gap.xs,
              children: <Widget>[
                // 🔴 Одни и те же три слова везде, где стоит полоса.
                _Legend(
                  swatch: parents,
                  pic: Pic.family,
                  text: '$fromParents от родителей',
                ),
                _Legend(
                  swatch: AppColors.coin,
                  pic: Pic.task,
                  text: '$earned за задания',
                ),
                _Legend(
                  dashed: true,
                  text: left > 0 ? 'можно ещё $left' : 'можно ещё 0',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(
      {this.swatch, this.pic, required this.text, this.dashed = false});

  final Color? swatch;
  final Pic? pic;
  final String text;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Образец — со своей пиктограммой: цвет не единственный носитель
        // смысла (§3.6.5).
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: swatch ?? const Color(0xFFFFF1CF),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
                color: dashed ? AppColors.coinDeep : AppColors.ink, width: 1.5),
          ),
          child: pic == null
              // Образец «можно ещё» — той же штриховкой, что на полосе.
              ? (dashed
                  ? const CustomPaint(
                      size: Size(19, 19), painter: _HatchSwatch())
                  : null)
              : Pictogram(pic!, size: 16, color: AppColors.ink),
        ),
        const SizedBox(width: Gap.xs),
        // Flexible: при крупном шрифте подпись длиннее ширины экрана и
        // должна переноситься, а не вылезать за край.
        Flexible(
          child: Text(text,
              style: const TextStyle(fontSize: 16, color: AppColors.ink)),
        ),
      ],
    );
  }
}

class _HatchSwatch extends CustomPainter {
  const _HatchSwatch();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final Paint hatch = Paint()
      ..color = AppColors.coinDeep.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    for (double x = -size.height; x < size.width; x += 7) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), hatch);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchSwatch old) => false;
}

class _TrustPainter extends CustomPainter {
  _TrustPainter(
      {required this.parents, required this.cap, required this.earned});

  final int parents;
  final int cap;
  final int earned;

  @override
  void paint(Canvas canvas, Size size) {
    final int total = math.max(1, parents + cap);
    final double unit = size.width / total;
    final double h = size.height;
    final RRect whole =
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(h / 2));
    canvas.save();
    canvas.clipRRect(whole);
    canvas.drawRect(Rect.fromLTWH(0, 0, parents * unit, h),
        Paint()..color = TrustBar.parents);
    canvas.drawRect(Rect.fromLTWH(parents * unit, 0, earned * unit, h),
        Paint()..color = AppColors.coin);
    // Остаток лимита — светлый, с поперечной штриховкой: «ещё можно».
    final Rect rest =
        Rect.fromLTWH((parents + earned) * unit, 0, (cap - earned) * unit, h);
    canvas.drawRect(rest, Paint()..color = const Color(0xFFFFF1CF));
    final Paint hatch = Paint()
      ..color = AppColors.coinDeep.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    for (double x = rest.left - h; x < rest.right; x += 7) {
      canvas.drawLine(Offset(x, h), Offset(x + h, 0), hatch);
    }
    // Деления по монеткам — видно, что это штучные монетки, а не проценты.
    final Paint tick = Paint()
      ..color = AppColors.surface.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    for (int i = 1; i < total; i++) {
      if (i == parents) continue;
      canvas.drawLine(
          Offset(i * unit, h * 0.3), Offset(i * unit, h * 0.7), tick);
    }
    canvas.restore();
    // Граница «от родителей | сам» — чернилами: главное деление полосы.
    canvas.drawLine(
        Offset(parents * unit, 0),
        Offset(parents * unit, h),
        Paint()
          ..color = AppColors.ink
          ..strokeWidth = 2);
    canvas.drawRRect(
        whole,
        Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_TrustPainter old) =>
      old.parents != parents || old.cap != cap || old.earned != earned;
}

/// Хочет ли ребёнок слушать объяснения и может ли устройство их прочитать.
bool _canSpeak(BuildContext context) {
  if (!Speaker.instance.available) return false;
  // 🔴 «Звуки» выключают и голос тоже (§3.6.7).
  if (!context.soundOn) return false;
  try {
    return context.read<AppState>().game.profile.settings.readAloud;
  } on Object {
    return false;
  }
}

/// Кто сейчас Финни — для реакции в карточке последствия. null, если
/// состояния нет (виджет-тесты без провайдера, экран до загрузки).
Game? _gameOrNull(BuildContext context) {
  try {
    final AppState app = context.read<AppState>();
    return app.ready ? app.game : null;
  } on Object {
    return null;
  }
}

/// Карточка последствия (§2.5.9): что изменилось · почему · что дальше.
///
/// Здесь же — единственный отклик на действие: звук §3.6.7 и реакция
/// Финни. Если передан [holding], Финни держит в лапках то, что только что
/// купили; если [cheer] — радуется. Реакция — ответ на действие ребёнка,
/// поэтому ей можно двигаться: один подскок при появлении.
Future<void> showFeedback(
  BuildContext context,
  ActionResult f, {
  Cue cue = Cue.done,
  Pic? holding,
  Color? holdingColor,
  bool cheer = false,
  RoomScene? room,
}) {
  unawaited(context.cue(cue));
  final bool speak = _canSpeak(context);
  if (speak) {
    Speaker.instance.speak(
      <String>[f.title, f.text, if (f.nextStep != null) f.nextStep!].join('. '),
    );
  }
  final Game? g =
      (holding != null || cheer || room != null) ? _gameOrNull(context) : null;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    // §3.6.7: с выключёнными анимациями карточка не выезжает, а появляется.
    sheetAnimationStyle: AnimationStyle(
      duration: context.motion(const Duration(milliseconds: 250)),
      reverseDuration: context.motion(const Duration(milliseconds: 200)),
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.scene)),
    ),
    builder: (BuildContext ctx) => _FeedbackBody(
      f: f,
      speak: speak,
      game: g,
      holding: holding,
      holdingColor: holdingColor,
      cheer: cheer,
      room: room,
    ),
  );
}

class _FeedbackBody extends StatefulWidget {
  const _FeedbackBody({
    required this.f,
    required this.speak,
    required this.game,
    required this.holding,
    required this.holdingColor,
    required this.cheer,
    required this.room,
  });

  /// Комната после покупки: вещь уже стоит на своём месте.
  final RoomScene? room;

  final ActionResult f;
  final bool speak;
  final Game? game;
  final Pic? holding;
  final Color? holdingColor;
  final bool cheer;

  @override
  State<_FeedbackBody> createState() => _FeedbackBodyState();
}

class _FeedbackBodyState extends State<_FeedbackBody>
    with SingleTickerProviderStateMixin {
  /// 🔴 Создаются в initState, а не лениво: поле, до которого впервые
  /// дошли из dispose, создаёт тикер на уже отсоединённом элементе.
  late final AnimationController _hop;
  late final CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    _hop = AnimationController(vsync: this, duration: Motion.nod, value: 1);
    _curve = CurvedAnimation(parent: _hop, curve: Motion.nodCurve);
    // Подскок — ответ на то действие, которое открыло карточку.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.game == null) return;
      _hop
        ..duration = context.motion(Motion.nod)
        ..forward(from: 0);
    });
  }

  @override
  void dispose() {
    _curve.dispose();
    _hop.dispose();
    super.dispose();
  }

  void _say() => Speaker.instance.speak(
        <String>[
          widget.f.title,
          widget.f.text,
          if (widget.f.nextStep != null) widget.f.nextStep!,
        ].join('. '),
      );

  @override
  Widget build(BuildContext context) {
    final ActionResult f = widget.f;
    final Game? g = widget.game;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (g != null && widget.room != null) ...<Widget>[
              // 🔴 Купленная вещь, которая остаётся, — сразу в комнате.
              // Анализ референсов: «покупка появляется в пространстве,
              // а не исчезает в инвентаре», и персонаж на неё реагирует.
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.envelope),
                child: RoomView(
                  scene: widget.room!,
                  species: g.profile.species,
                  palette: g.profile.palette,
                  meters: g.snapshot.meters,
                  accessories: g.profile.accessories,
                  pose: FinniPose.cheer,
                  hopOnOpen: true,
                ),
              ),
              const SizedBox(height: Gap.md),
            ] else if (g != null)
              Center(
                child: FinniView(
                  species: g.profile.species,
                  palette: g.profile.palette,
                  stage: g.snapshot.stage,
                  meters: g.snapshot.meters,
                  accessories: g.profile.accessories,
                  size: 124,
                  hop: _curve,
                  pose: widget.cheer ? FinniPose.cheer : FinniPose.idle,
                  holding: widget.holding,
                  holdingColor: widget.holdingColor,
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(f.title,
                        style: Theme.of(context).textTheme.headlineSmall),
                  ),
                ),
                if (widget.speak)
                  IconButton(
                    tooltip: 'Прослушать',
                    iconSize: 30,
                    constraints: const BoxConstraints(
                        minWidth: TapSize.min, minHeight: TapSize.min),
                    icon: const Pictogram(Pic.sound,
                        size: 30, color: AppColors.primary),
                    onPressed: _say,
                  ),
              ],
            ),
            if (g != null && widget.room != null) ...<Widget>[
              const SizedBox(height: Gap.xs),
              // Прошедшее время: вещь уже стоит в комнате, это видно выше.
              Row(
                children: <Widget>[
                  const Pictogram(Pic.house,
                      size: 22, color: AppColors.savings),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      widget.room!.freshDream
                          ? 'Мечта теперь стоит во дворе — насовсем.'
                          : 'Теперь это стоит в комнате — насовсем.',
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.savings),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Gap.sm),
            Text(f.text, style: Theme.of(context).textTheme.bodyLarge),
            if (f.nextStep != null) ...<Widget>[
              const SizedBox(height: Gap.md),
              Container(
                padding: const EdgeInsets.all(Gap.md),
                decoration: BoxDecoration(
                  color: AppColors.needsBg,
                  borderRadius: BorderRadius.circular(Radii.chip),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Pictogram(Pic.arrowRight,
                        size: 24, color: AppColors.needs),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(f.nextStep!,
                          style: const TextStyle(
                              fontSize: 18, color: AppColors.ink)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: Gap.lg),
            FilledButton(
              onPressed: () {
                Speaker.instance.stop();
                Navigator.of(context).pop();
              },
              child: const Text('Понятно'),
            ),
          ],
        ),
      ),
    );
  }
}
