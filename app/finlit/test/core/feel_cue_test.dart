import 'package:finlit/app_state.dart';
import 'package:finlit/core/feel.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// §3.6.7 «звуки отключаются» — на единственной двери звука мира.
///
/// Защищает: щелчок и вибрация мини-игр и выплаты смены идут только через
/// `context.cue`, и переключатель «Звуки» в настройках её глушит.
/// Уронит: `cue` перестал читать настройку (или читает не тот профиль) —
/// тогда при выключенных звуках щелчок уходит на платформу.
/// Раньше это ловил тест старого магазина v1; экран удалён, проверка
/// переехала на саму дверь, которую зовут все игры мира.

final List<MethodCall> _platform = <MethodCall>[];

List<String> get _feel => _platform
    .map((MethodCall c) => c.method)
    .where(
        (String m) => m == 'SystemSound.play' || m == 'HapticFeedback.vibrate')
    .toList();

Future<AppState> _app(GameSettings s) async {
  final AppState app = AppState(MemoryStorage());
  await app.boot();
  await app.updateProfile(app.game.profile.copyWith(settings: s));
  return app;
}

/// Кнопка, которая зовёт `cue`, как это делают игры профессий.
Widget _host(AppState app) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: GestureDetector(
                onTap: () => ctx.cue(Cue.done),
                child: const Text('смена удалась'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  setUp(() {
    rootBundle.clear();
    _platform.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform,
            (MethodCall c) async {
      _platform.add(c);
      return null;
    });
  });

  for (final (bool on, String name) in <(bool, String)>[
    (true, 'со звуками — щелчок и вибрация'),
    (false, 'без звуков — ни щелчка, ни вибрации'),
  ]) {
    testWidgets('§3.6.7 cue: $name', (WidgetTester tester) async {
      // Только iOS: на Android Material сам щёлкает на каждое касание, и
      // «тишина» перестала бы проверяться. Флаг снимается в finally, иначе
      // упавший expect уронил бы весь остаток файла.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final AppState app =
            (await tester.runAsync(() => _app(GameSettings(soundOn: on))))!;
        await tester.pumpWidget(_host(app));
        _platform.clear();

        await tester.tap(find.text('смена удалась'));
        await tester.pump();

        if (on) {
          expect(_feel, containsAll(<String>['SystemSound.play']),
              reason: 'переключатель «Звуки» включён — отклик должен быть');
        } else {
          expect(_feel, isEmpty,
              reason: 'переключатель «Звуки» выключен — тишина');
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
