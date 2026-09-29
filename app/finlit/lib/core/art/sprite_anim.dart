import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../feel.dart';
import 'asset_registry.dart';
import 'sprite_sheet.dart';

/// Целый масштаб пиксель-арта, который влезает в [box] по высоте.
///
/// 🔴 Только целые шаги (1× / 2× / 3×) и `FilterQuality.none` — иначе
/// пиксели плывут (`assets/README.md`, `docs/game/ui-sound-style.md`).
/// Для арта низкого разрешения; hi-res арт ([artDensity] > 1) масштабируется
/// дробно.
int pixelScaleFor(double frameHeight, double box) {
  if (frameHeight <= 0 || !box.isFinite) return 1;
  final int k = (box / frameHeight).floor();
  return k < 1 ? 1 : k;
}

final RegExp _density = RegExp(r'@(\d+(?:\.\d+)?)x\.png$');

/// Плотность арта из имени файла: `stalinka@4x.png` — 4 пикселя исходника на
/// логический пиксель. Без суффикса — 1 (прежний арт низкого разрешения).
///
/// Hi-res арт показывается в размере «пиксели / плотность» и уменьшается с
/// `FilterQuality.medium` — крупных квадратов нет (`docs/design-system.md` §6).
double artDensity(String path) {
  final Match? m = _density.firstMatch(path);
  final double d = m == null ? 1 : double.parse(m.group(1)!);
  return d > 0 ? d : 1;
}

/// Как рисовать арт плотности [density]: hi-res — сглаженное уменьшение,
/// низкое разрешение — чёткие пиксели.
FilterQuality artFilter(double density) =>
    density > 1 ? FilterQuality.medium : FilterQuality.none;

/// Проигрывает тег спрайт-листа из реестра.
///
/// Анимации выключены (настройки или система) — стоит первый кадр тега:
/// ничего важного движение не несёт (ТЗ 3.6.7).
class SpriteAnim extends StatefulWidget {
  const SpriteAnim({
    super.key,
    required this.sprite,
    this.tag,
    this.scale,
    this.height,
    this.play = true,
    this.semanticLabel,
  });

  final SpriteRef sprite;

  /// Тег анимации (`idle-1`, `walk`, `sleep`, `wake`). null — все кадры.
  final String? tag;

  /// Масштаб в логических пикселях кадра. Не задан — hi-res кадр вписывается
  /// в [height] (и в ширину родителя), прежний — наибольший целый, при котором
  /// кадр не выше [height]; нет и [height] — 1×. Прежний арт округляет
  /// масштаб до целого.
  final double? scale;
  final double? height;

  final bool play;
  final String? semanticLabel;

  @override
  State<SpriteAnim> createState() => _SpriteAnimState();
}

class _SpriteAnimState extends State<SpriteAnim>
    with SingleTickerProviderStateMixin {
  SpriteSheet? _sheet;
  ui.Image? _image;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  late final Ticker _ticker = createTicker(_onTick);

  List<int> _seq = const <int>[0];
  int _step = 0;
  Duration _stepStartedAt = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SpriteAnim old) {
    super.didUpdateWidget(old);
    if (old.sprite != widget.sprite) {
      _load();
    } else if (old.tag != widget.tag) {
      _restart();
    }
  }

  /// Разрешено ли движение — с подпиской на настройки, чтобы тумблер
  /// «Анимации» останавливал спрайт, который уже на экране.
  bool _motion = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = context.motionOnListening;
    _syncTicker();
  }

  Future<void> _load() async {
    final SpriteRef ref = widget.sprite;
    // Строку кеширует rootBundle; своего статического кеша нет (см.
    // AssetRegistry.load).
    final SpriteSheet sheet =
        await rootBundle.loadString(ref.data).then(SpriteSheet.parse);
    if (!mounted || widget.sprite != ref) return;
    _sheet = sheet;
    _resolveImage(ref.sheet);
    _restart();
  }

  void _resolveImage(String path) {
    _stopImage();
    final ImageStream stream =
        AssetImage(path).resolve(createLocalImageConfiguration(context));
    final ImageStreamListener l = ImageStreamListener((ImageInfo info, _) {
      if (!mounted) return;
      setState(() => _image = info.image);
    });
    stream.addListener(l);
    _stream = stream;
    _listener = l;
  }

  void _stopImage() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void _restart() {
    final SpriteSheet? sheet = _sheet;
    if (sheet == null) return;
    setState(() {
      _seq = sheet.sequence(widget.tag);
      _step = 0;
      _stepStartedAt = Duration.zero;
    });
    if (_ticker.isActive) _ticker.stop();
    _syncTicker();
  }

  bool get _animate =>
      widget.play && _sheet != null && _seq.length > 1 && _motion;

  void _syncTicker() {
    if (_animate && !_ticker.isActive) {
      _stepStartedAt = Duration.zero;
      _ticker.start();
    } else if (!_animate && _ticker.isActive) {
      _ticker.stop();
      setState(() => _step = 0);
    }
  }

  void _onTick(Duration elapsed) {
    final SpriteSheet sheet = _sheet!;
    int step = _step;
    Duration started = _stepStartedAt;
    while (elapsed - started >= sheet.frames[_seq[step]].duration) {
      started += sheet.frames[_seq[step]].duration;
      step = (step + 1) % _seq.length;
    }
    if (step != _step) {
      setState(() {
        _step = step;
        _stepStartedAt = started;
      });
    } else {
      _stepStartedAt = started;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _stopImage();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SpriteSheet? sheet = _sheet;
    final ui.Image? image = _image;
    if (sheet == null || image == null) {
      return SizedBox(height: widget.height);
    }
    final Rect src = sheet.frames[_seq[_step]].rect;
    final double d = artDensity(widget.sprite.sheet);
    final Size logical = src.size / d;
    Widget paintAt(double k) => Semantics(
          label: widget.semanticLabel,
          image: widget.semanticLabel != null,
          excludeSemantics: true,
          child: CustomPaint(
            size: logical * k,
            painter: _FramePainter(image, src, artFilter(d)),
          ),
        );
    if (d <= 1) {
      final double? s = widget.scale;
      final int k = s != null
          ? (s.round() < 1 ? 1 : s.round())
          : (widget.height == null
              ? 1
              : pixelScaleFor(src.height, widget.height!));
      return paintAt(k.toDouble());
    }
    final double? s = widget.scale;
    if (s != null) return paintAt(s);
    final double? h = widget.height;
    if (h == null) return paintAt(1);
    // Вписать и по ширине: широкий питомец в узкой карточке не сплющивается.
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      double k = h / logical.height;
      if (c.maxWidth.isFinite && logical.width * k > c.maxWidth) {
        k = c.maxWidth / logical.width;
      }
      return paintAt(k);
    });
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.image, this.src, this.filter);

  final ui.Image image;
  final Rect src;
  final FilterQuality filter;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      Paint()
        ..filterQuality = filter
        ..isAntiAlias = filter != FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.image != image || old.src != src || old.filter != filter;
}

/// Статичная картинка мира (здание, фон комнаты).
///
/// Прежний арт — в целом масштабе с чёткими пикселями; hi-res ([artDensity]
/// > 1) — в размере «пиксели / плотность × [scale]», сглаженное уменьшение.
class PixelImage extends StatelessWidget {
  const PixelImage(this.path,
      {super.key, this.scale = 1, this.semanticLabel, this.fallback});

  final String? path;

  /// Масштаб в логических пикселях. Прежний арт округляет его до целого.
  final double scale;
  final String? semanticLabel;

  /// Что показать, если арта нет в реестре или файл не открылся.
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final String? p = path;
    final Widget stub = fallback ?? const SizedBox.shrink();
    if (p == null) return stub;
    final double d = artDensity(p);
    final int whole = scale.round() < 1 ? 1 : scale.round();
    return Image.asset(
      p,
      scale: d > 1 ? d / scale : 1 / whole,
      filterQuality: artFilter(d),
      isAntiAlias: d > 1,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      errorBuilder: (_, __, ___) => stub,
    );
  }
}
