import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'data/content_loader.dart';
import 'data/storage.dart';
import 'domain/content.dart';
import 'domain/custom_goal.dart';
import 'domain/economy/period_rules.dart';
import 'domain/game.dart';
import 'domain/models/pet.dart';
import 'domain/models/profile.dart';

/// Ключи файлов профиля. Обычный и тестовый профиль живут отдельно —
/// сброс демонстрационного (§2.5.13) не должен трогать игру ребёнка.
const String _kMain = 'profile';
const String _kDemo = 'profile_demo';

/// Состояние приложения поверх игрового ядра.
///
/// Здесь нет ни одной формулы: всё вычисляет [Game]. Этот класс только
/// сохраняет, загружает и уведомляет виджеты.
class AppState extends ChangeNotifier {
  AppState(this._storage);

  final Storage _storage;

  Game? _game;
  bool _demoMode = false;
  ActionResult? _lastFeedback;
  PeriodOutcome? _lastOutcome;
  PetStage? _stageBefore;

  bool get ready => _game != null;

  /// Контент, по которому идёт игра.
  ///
  /// 🔴 Одно поле, а не два. Раньше AppState держал свой `_content`, а [Game]
  /// — свой, и при смене масштаба обновлялся только первый: экран показывал
  /// цену каши 10, движок списывал 2, а карманные приходили старые. Теперь
  /// расходиться нечему — контент у экрана и у движка один и тот же объект,
  /// и это проверяется тестом (`identical`).
  GameContent get content => _game!.content;
  Game get game => _game!;
  bool get demoMode => _demoMode;
  ActionResult? get lastFeedback => _lastFeedback;

  /// Итоги последней закрытой недели (§2.5.11.1).
  ///
  /// 🔴 Поле в памяти — только кеш только что закрытой недели. Если его нет
  /// (например, приложение перезапустили), итог пересчитывается из журнала:
  /// иначе блок «Итоги недели» исчезал после каждого перезапуска.
  PeriodOutcome? get lastOutcome =>
      _lastOutcome ?? _game?.outcomeOfPeriod((_game!.periodNo) - 1);

  /// Стадия сменилась после последнего действия — экран показывает карточку
  /// «Финни научился» (§2.5.10, третий пункт).
  PetStage? takeStageUp() {
    final PetStage? before = _stageBefore;
    _stageBefore = null;
    if (before == null) return null;
    return before == game.snapshot.stage ? null : game.snapshot.stage;
  }

  Future<void> boot() => _openProfile(_kMain, isDemo: false);

  /// Открывает профиль из хранилища и подбирает под него контент.
  ///
  /// 🔴 Порядок именно такой: сначала профиль, потом контент. Масштаб «чисел
  /// покрупнее» лежит в настройках профиля, и узнать его можно только после
  /// чтения. Раньше контент грузился первым, а масштаб брался из ещё не
  /// созданной игры и потому всегда равнялся единице: флаг сохранялся, а
  /// после перезапуска не применялся ни разу.
  Future<void> _openProfile(String key, {required bool isDemo}) async {
    final Map<String, Object?>? saved = await _storage.read(key);
    final GameProfile profile = saved == null
        ? GameProfile.fresh(isDemo: isDemo)
        : GameProfile.fromJson((saved['profile']! as Map<Object?, Object?>)
            .cast<String, Object?>());
    final GameContent loaded = await _loadContent(profile.settings.scale);
    _game = saved == null
        ? Game(content: loaded, profile: profile)
        : Game.fromJson(saved, loaded);
    CustomGoals.restore(loaded, profile.goalId);
    notifyListeners();
  }

  Future<GameContent> _loadContent(int scale) =>
      ContentLoader(rootBundle.loadString).load(scale: scale);

  /// Переключение между игрой ребёнка и тестовым профилем (§2.5.13).
  Future<void> setDemoMode(bool on) async {
    if (_demoMode == on) return;
    await save();
    _demoMode = on;
    // У тестового профиля свои настройки, в том числе свой масштаб чисел,
    // поэтому контент перечитывается вместе с профилем.
    await _openProfile(on ? _kDemo : _kMain, isDemo: on);
  }

  Future<void> save() async {
    if (_game == null) return;
    await _storage.write(_demoMode ? _kDemo : _kMain, _game!.toJson());
  }

  /// Сброс тестового профиля к исходному состоянию (§2.5.13).
  Future<void> resetDemoProfile() async {
    await _deleteProfile(_kDemo);
    // Сброшенный профиль — это профиль с обычными числами, значит и контент
    // ему нужен обычный: иначе экраны остались бы в масштабе стёртой игры.
    if (_demoMode) await _openProfile(_kDemo, isDemo: true);
  }

  /// Удаление профиля, в котором игра идёт прямо сейчас. Доступно взрослому
  /// без обращения к разработчику (§3.5, предпоследний пункт).
  ///
  /// 🔴 Удаляется именно активный профиль, а не всегда файл ребёнка. Раньше
  /// метод стирал `_kMain` при любом режиме, а пересоздавал состояние только
  /// вне демонстрационного: взрослый, зашедший сюда с включённым демо-режимом,
  /// уничтожал игру ребёнка молча — на экране не менялось ничего, а сообщение
  /// уверяло, что Финни остался на месте.
  Future<void> deleteActiveProfile() async {
    final String key = _demoMode ? _kDemo : _kMain;
    await _deleteProfile(key);
    await _openProfile(key, isDemo: _demoMode);
  }

  /// Профиль и его отложенная испорченная копия ([brokenKey]): хранилище
  /// откладывает нечитаемый профиль, а не стирает его, и копия — тоже
  /// данные ребёнка (§3.5).
  Future<void> _deleteProfile(String key) async {
    await _storage.delete(key);
    await _storage.delete(brokenKey(key));
  }

  /// Любое игровое действие проходит здесь: результат становится карточкой
  /// последствия (§2.5.9), состояние сохраняется, виджеты обновляются.
  Future<void> act(ActionResult Function(Game g) action) async {
    _stageBefore = game.snapshot.stage;
    _lastFeedback = action(game);
    await save();
    notifyListeners();
  }

  Future<void> closePeriod() async {
    _stageBefore = game.snapshot.stage;
    _lastOutcome = game.closePeriod();
    _lastFeedback = null;
    await save();
    notifyListeners();
  }

  Future<void> updateProfile(GameProfile p) async {
    final bool scaleChanged = p.settings.scale != game.profile.settings.scale;
    game.updateProfile(p);
    if (scaleChanged) {
      // 🔴 Контент и движок меняются одним шагом. Перечитать контент мало:
      // пока игра держала старый, диалог обещал «вместо 10 монеток — 50»,
      // на витрине стояли новые цены, а начислялись и списывались старые
      // монетки. Журнал при пересоздании переносится целиком — накопленное
      // остаётся, как и обещано в том же диалоге.
      final GameContent next = await _loadContent(p.settings.scale);
      _game = game.withContent(next);
      CustomGoals.restore(next, p.goalId);
    }
    await save();
    notifyListeners();
  }

  void clearFeedback() {
    _lastFeedback = null;
    _lastOutcome = null;
    notifyListeners();
  }
}
