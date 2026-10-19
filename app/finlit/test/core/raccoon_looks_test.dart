import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finlit/core/art/asset_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Какой будет Финни?» (кадры 0.1.2+3, night4 #3): четыре облика енота
/// выглядели одинаково — четыре генерации одного промпта, у всех та же синяя
/// толстовка. Кода оттенка нет: облик — отдельная картинка, так что разница
/// должна быть в самих картинках (`tools/recolor_raccoon.py`).
///
/// Защищает: превью четырёх обликов каждого вида заметно различаются по
/// цвету. Мера — гистограмма оттенка насыщенных пикселей (12 корзин по 30°,
/// без контура и бликов), попарное расстояние L1 (0 — одинаково, 2 — ничего
/// общего). Четыре синих енота давали 0,05–0,18; перекрашенные — от 1,25.
/// Уронит: облики снова одного цвета или перекраска не дошла до картинки,
/// которую показывает экран выбора (путь из `registry.json`).
/// Почему не ловили: тесты реестра проверяли, что файлы облика есть и
/// разные по байтам, а не что их видно разными.
const double _minDistance = 0.5;

Future<List<double>> _hueHistogram(String path) async {
  final Uint8List bytes = File(path).readAsBytesSync();
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.Image image = (await codec.getNextFrame()).image;
  final ByteData data =
      (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  final List<double> bins = List<double>.filled(12, 0);
  int n = 0;
  for (int i = 0; i < data.lengthInBytes; i += 4) {
    if (data.getUint8(i + 3) < 128) continue;
    final double r = data.getUint8(i) / 255;
    final double g = data.getUint8(i + 1) / 255;
    final double b = data.getUint8(i + 2) / 255;
    final double mx = math.max(r, math.max(g, b));
    final double mn = math.min(r, math.min(g, b));
    final double l = (mx + mn) / 2;
    if (l < 0.22 || l > 0.85 || mx == mn) continue;
    final double d = mx - mn;
    final double s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (s < 0.3) continue;
    double h;
    if (mx == r) {
      h = ((g - b) / d) % 6;
    } else if (mx == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    bins[((h / 6) * 12).floor() % 12]++;
    n++;
  }
  return <double>[for (final double v in bins) n == 0 ? 0 : v / n];
}

double _l1(List<double> a, List<double> b) {
  double s = 0;
  for (int i = 0; i < a.length; i++) {
    s += (a[i] - b[i]).abs();
  }
  return s;
}

void main() {
  final AssetRegistry reg =
      AssetRegistry.parse(File('assets/art/registry.json').readAsStringSync());

  testWidgets('енот: четыре облика в выборе различаются цветом',
      (WidgetTester tester) async {
    final List<String> looks = reg.finniLooks('finni-a2');
    expect(looks, hasLength(4));
    final List<List<double>> h = <List<double>>[];
    await tester.runAsync(() async {
      for (final String p in looks) {
        h.add(await _hueHistogram(p));
      }
    });
    for (int i = 0; i < 4; i++) {
      for (int j = i + 1; j < 4; j++) {
        expect(_l1(h[i], h[j]), greaterThanOrEqualTo(_minDistance),
            reason: 'облики ${i + 1} и ${j + 1} одного цвета');
      }
    }
  });
}
