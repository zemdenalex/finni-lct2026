import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';
import '../pic_text.dart';
import '../world_state.dart';
import 'finni_bubble.dart';
import 'onboarding_script.dart';

/// Ключ «уже показано» подсказок первого выхода в город ([World.seen]).
/// Сброс мира и «Демо-режим» начинают с нового знакомства — и подсказки
/// покажутся снова.
const String cityIntroSeen = 'city.intro';

/// Подсказки первого выхода в город поверх [child] (экран города): 2–3
/// реплики Финни облачком над ним — куда идти, зачем Дом работы и Банк, как
/// ходить. Один раз за мир (Денис 20.10: «онбординг при первом выходе в
/// город»). Тексты — `onboarding.json → city.intro` (ТЗ 3.2.3).
///
/// Экран города о подсказках не знает: Финни ищется в поддереве [child] по
/// ключу `city:finni`, как обучалка комнаты ищет свои цели.
class CityIntroGate extends StatefulWidget {
  const CityIntroGate({super.key, required this.child});

  final Widget child;

  @override
  State<CityIntroGate> createState() => _CityIntroGateState();
}

class _CityIntroGateState extends State<CityIntroGate> {
  final GlobalKey _childKey = GlobalKey();
  bool _on = false;
  int _i = 0;
  late final List<String> _lines;

  @override
  void initState() {
    super.initState();
    final WorldState ws = context.read<WorldState>();
    OnboardingScript? script;
    try {
      script = context.read<OnboardingScript?>();
    } on ProviderNotFoundException {
      script = null;
    }
    _lines = (script ?? OnboardingScript.fallback).cityIntro;
    final World w = ws.world;
    _on = _lines.isNotEmpty &&
        w.onboarding.done &&
        w.phase != WeekPhase.onboarding &&
        !w.seen(cityIntroSeen);
    // Показано — запомнено сразу: вышел из города посреди подсказок —
    // второй раз они не держат игру.
    if (_on) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(ws.markSeen(cityIntroSeen));
      });
    }
  }

  void _next() {
    if (_i + 1 >= _lines.length) return _close();
    setState(() => _i++);
  }

  void _close() => setState(() => _on = false);

  /// Спрайт Финни в городе: внутри `city:finni` — кадр, уже сдвинутый к
  /// ногам (FractionalTranslation), его прямоугольник и нужен.
  Rect? _finni(RenderBox layer) {
    final BuildContext? root = _childKey.currentContext;
    if (root == null) return null;
    const ValueKey<String> want = ValueKey<String>('city:finni');
    Element? found;
    void visit(Element e) {
      if (found != null) return;
      if (e.widget.key == want) {
        found = e;
        return;
      }
      e.visitChildElements(visit);
    }

    (root as Element).visitChildElements(visit);
    final RenderObject? walker = found?.renderObject;
    RenderBox? sprite;
    walker?.visitChildren((RenderObject c) {
      if (c is RenderBox) sprite ??= c;
    });
    final RenderBox? s = sprite;
    if (s == null || !s.hasSize || !s.attached) return null;
    return layer.globalToLocal(s.localToGlobal(Offset.zero)) & s.size;
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = KeyedSubtree(key: _childKey, child: widget.child);
    if (!_on) return child;
    final bool last = _i == _lines.length - 1;
    final String name = context.watch<WorldState>().finniName;
    return Stack(
      children: <Widget>[
        child,
        Positioned.fill(
          // Слой над Scaffold города: без Material текст был бы без темы
          // (жёлтое подчёркивание, чужой шрифт).
          child: Material(
            type: MaterialType.transparency,
            child: BlockSemantics(
            child: Stack(
              children: <Widget>[
                // Город ждёт, пока идут подсказки: касания мимо облачка
                // гасятся, карта чуть притушена.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: const ColoredBox(color: Color(0x66000000)),
                  ),
                ),
                Positioned.fill(
                  child: FinniSpeechLayer(
                    key: const ValueKey<String>('city:intro'),
                    bubbleKey: ValueKey<String>('city:intro:$_i'),
                    locate: _finni,
                    scroll: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text('$name · ${_i + 1} из ${_lines.length}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.title(15, color: WorldColors.gold)),
                        const SizedBox(height: Gap.xs),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Semantics(
                              liveRegion: true,
                              child: PicText(
                                fillLine(_lines[_i],
                                    <String, String>{'name': name}),
                                style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.3,
                                    color: WorldColors.text),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: Gap.sm),
                        Row(
                          children: <Widget>[
                            if (!last) ...<Widget>[
                              Expanded(
                                child: TextButton(
                                  key: const ValueKey<String>(
                                      'city:intro:skip'),
                                  onPressed: _close,
                                  style: TextButton.styleFrom(
                                      minimumSize: const Size(0, TapSize.min),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: Gap.xs)),
                                  child: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text('Пропустить',
                                        maxLines: 1,
                                        style: TextStyle(
                                            color: WorldColors.textSoft)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: Gap.sm),
                            ],
                            Expanded(
                              child: FilledButton(
                                key: const ValueKey<String>('city:intro:next'),
                                onPressed: _next,
                                style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, TapSize.min),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: Gap.sm)),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(last ? 'Понятно' : 'Дальше',
                                      maxLines: 1),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ],
    );
  }
}
