import 'dart:ui' as ui;

import 'package:finlit/core/theme.dart';
import 'package:finlit/core/world_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_fonts.dart';

/// Ловит (ревью 29.09): в Onest нет знака минус U+2212 — «−3 😊» и «−50 из
/// копилки» рисовались как «3» и «50», смысл наоборот. Знак берётся из
/// Unbounded (тот же OFL, уже в приложении) через fontFamilyFallback темы.
/// Проверка по пикселям: у знака есть «чернила».
Future<int> _ink(WidgetTester tester, ThemeData theme, TextStyle? style) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: Colors.white,
            width: 60,
            height: 40,
            alignment: Alignment.center,
            child: Text('−',
                style: (style ?? const TextStyle())
                    .copyWith(color: Colors.black, fontSize: 28)),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  final RenderRepaintBoundary rb =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ui.Image img = await tester.runAsync(() => rb.toImage()) as ui.Image;
  final ByteData? raw = await tester.runAsync<ByteData?>(
      () => img.toByteData(format: ui.ImageByteFormat.rawRgba));
  final ByteData data = raw!;
  int dark = 0;
  for (int i = 0; i < data.lengthInBytes; i += 4) {
    if (data.getUint8(i) < 128) dark++;
  }
  return dark;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('минус виден в теме мира и в старой теме',
      (WidgetTester t) async {
    expect(await _ink(t, buildWorldTheme(), null), greaterThan(20),
        reason: 'тема мира: «−» без чернил');
    expect(await _ink(t, buildAppTheme(), null), greaterThan(20),
        reason: 'старая тема: «−» без чернил');
  });

  testWidgets('минус виден в числах (AppType.number)', (WidgetTester t) async {
    expect(
        await _ink(
            t, buildWorldTheme(), AppType.number(28, color: Colors.black)),
        greaterThan(20));
  });
}
