import 'package:finlit/app_state.dart';
import 'package:finlit/core/music.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Плеер-запись: что [BackgroundMusic] просила играть.
class _Sink implements MusicSink {
  final List<String> calls = <String>[];
  @override
  Future<void> play(String asset) async => calls.add('play');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> dispose() async {}
}

void main() {
  // Контракт: выбор «Музыка: выкл.» доживает до следующего запуска, и после
  // запуска мелодия не играет. Падает, если флаг не пишется в профиль или
  // плеер не слушает его.
  testWidgets('музыка выключена — после перезапуска тишина', (
    WidgetTester tester,
  ) async {
    final MemoryStorage storage = MemoryStorage();
    final AppState first = AppState(storage);
    await tester.runAsync(first.boot);
    final GameProfile p = first.game.profile;
    await tester.runAsync(() => first.updateProfile(
        p.copyWith(settings: p.settings.copyWith(musicOn: false))));

    final AppState again = AppState(storage);
    await tester.runAsync(again.boot);
    expect(again.game.profile.settings.musicOn, isFalse);

    final _Sink sink = _Sink();
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: again,
      child: BackgroundMusic(createSink: () => sink, child: const SizedBox()),
    ));
    expect(sink.calls, isNot(contains('play')));

    // Включили — играет.
    final GameProfile q = again.game.profile;
    await tester.runAsync(() => again.updateProfile(
        q.copyWith(settings: q.settings.copyWith(musicOn: true))));
    await tester.pump();
    expect(sink.calls.last, 'play');
  });

  test('сохранение до 15.10 без поля musicOn — музыка включена', () {
    final GameSettings s = GameSettings.fromJson(<String, Object?>{
      'soundOn': true,
      'animationsOn': true,
      'readAloud': false,
      'bigNumbers': false,
    });
    expect(s.musicOn, isTrue);
  });
}
