import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../domain/models/profile.dart';

/// Фоновая мелодия — «Peaceful Days», Juhani Junkala (SubspaceAudio),
/// CC0 1.0, opengameart.org/content/jrpg-pack-4-calm: 64 с по кругу.
/// Файлы — `assets/audio/` (ffmpeg, Ogg Vorbis: Opus в Ogg Android
/// читает только с 10-й версии, а у нас 8.0+).
abstract class MusicSink {
  Future<void> play(String asset);
  Future<void> stop();
  Future<void> dispose();
}

/// Настоящий плеер. В тестах не создаётся: [BackgroundMusic] без
/// [BackgroundMusic.createSink] молчит, и виджет-тесты не упираются в канал
/// платформы.
class AudioplayersSink implements MusicSink {
  final AudioPlayer _player = AudioPlayer(playerId: 'music');
  String? _now;

  @override
  Future<void> play(String asset) async {
    try {
      await _play(asset);
    } on Object catch (e) {
      // Нет звука — не беда: браузер до первого касания, занятый плеер.
      debugPrint('music: $e');
    }
  }

  Future<void> _play(String asset) async {
    if (_now == asset && _player.state == PlayerState.playing) return;
    _now = asset;
    await _player.setReleaseMode(ReleaseMode.loop);
    // Тихо: музыка под игрой, а не вместо подсказок и озвучки.
    await _player.setVolume(0.35);
    // Не забирать фокус у озвучки и чужих приложений.
    await _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        usageType: AndroidUsageType.game,
        contentType: AndroidContentType.music,
        audioFocus: AndroidAudioFocus.none,
      ),
    ));
    await _player.play(AssetSource(asset.replaceFirst('assets/', '')));
  }

  @override
  Future<void> stop() async {
    _now = null;
    try {
      await _player.stop();
    } on Object catch (e) {
      debugPrint('music: $e');
    }
  }

  @override
  Future<void> dispose() => _player.dispose();
}

/// Играет мелодию, пока включены «Звуки» и «Музыка» и приложение на экране;
/// свернули — пауза, вернулись — снова.
///
/// [enabled] — флаг контента `audio.background_music` (DEN-34): false —
/// мелодии в игре нет вовсе: плеер не создаётся, тумблер «Музыка» и пункт
/// меню комнаты скрыты ([available]). Звуки и вибрация от него не зависят.
class BackgroundMusic extends StatefulWidget {
  const BackgroundMusic({
    super.key,
    required this.child,
    this.enabled = true,
    this.createSink,
  });

  /// Мелодия («Peaceful Days», CC0 1.0); трек меняется заменой файла, код
  /// не трогается.
  static const String track = 'assets/audio/music.ogg';

  final Widget child;

  /// Есть ли мелодия в этой сборке (`audio.background_music`).
  final bool enabled;

  /// Создаёт плеер — лениво, когда мелодия впервые нужна: при выключенном
  /// флаге или «Музыке» плеера нет совсем. Нет — тишина (тесты, экраны без
  /// звука).
  final MusicSink Function()? createSink;

  /// Есть ли мелодия в игре: экраны прячут свои ручки «Музыки», когда нет.
  /// Без [BackgroundMusic] выше (тесты одного экрана) — есть, как до флага.
  static bool available(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MusicScope>()?.enabled ??
      true;

  @override
  State<BackgroundMusic> createState() => _BackgroundMusicState();
}

class _MusicScope extends InheritedWidget {
  const _MusicScope({required this.enabled, required super.child});

  final bool enabled;

  @override
  bool updateShouldNotify(_MusicScope old) => old.enabled != enabled;
}

class _BackgroundMusicState extends State<BackgroundMusic>
    with WidgetsBindingObserver {
  bool _foreground = true;
  bool? _playing;
  MusicSink? _sink;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sink?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    final Widget child =
        _MusicScope(enabled: widget.enabled, child: widget.child);
    // Мелодии нет в сборке — профиль не слушаем и плеер не создаём.
    if (!widget.enabled) {
      if (_playing ?? false) unawaited(_sink?.stop());
      _playing = false;
      return child;
    }
    final bool on = context.select<AppState, bool>((AppState a) =>
        a.ready &&
        a.game.profile.settings.soundOn &&
        a.game.profile.settings.musicOn);
    final bool want = on && _foreground;
    if (want != _playing) {
      _playing = want;
      if (want) _sink ??= widget.createSink?.call();
      final MusicSink? s = _sink;
      if (s != null) {
        unawaited(want ? s.play(BackgroundMusic.track) : s.stop());
      }
    }
    return child;
  }
}

/// Быстрый выключатель мелодии (меню ⋮ комнаты): AppState есть — состояние
/// и переключение, нет (тесты отдельного экрана) или мелодии нет в сборке
/// ([BackgroundMusic.available]) — null, пункта в меню нет.
({bool on, Future<void> Function() toggle})? musicSwitch(BuildContext context) {
  if (!BackgroundMusic.available(context)) return null;
  final AppState app;
  try {
    app = Provider.of<AppState>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
  if (!app.ready) return null;
  final GameSettings s = app.game.profile.settings;
  final bool on = s.soundOn && s.musicOn;
  return (
    on: on,
    // Включить из меню — значит слышать: «Звуки» включаются вместе с ней.
    toggle: () => app.updateProfile(app.game.profile.copyWith(
        settings: on
            ? s.copyWith(musicOn: false)
            : s.copyWith(musicOn: true, soundOn: true))),
  );
}
