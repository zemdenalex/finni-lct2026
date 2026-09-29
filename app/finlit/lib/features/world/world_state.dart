import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../domain/world/contract.dart';

/// Состояние нового мира для экранов потока B.
///
/// 🔴 Экраны читают и делают всё через [world] (контракт
/// `domain/world/contract.dart`). В приложении это `WorldGame` из
/// `openSavedWorld` (`main.dart`); в тестах — любой [World].
///
/// Выбор ребёнка в онбординге (ник, вид, мальчик/девочка, облик, имя
/// Финни) хранит сам мир — [World.onboarding] (карточка A14); здесь только
/// чтение и вызовы с перерисовкой.
class WorldState extends ChangeNotifier {
  /// Мир без сохранения и без сброса — для тестов одного экрана.
  WorldState(World world)
      : _world = world,
        _freshWorld = null,
        _onReset = null;

  /// Мир с сохранением: [freshWorld] собирает мир для [reset] (с тем же
  /// сохранением), [onReset] стирает сохранённое (`SavedWorld.forget`). Про
  /// диск [WorldState] не знает — хуки даёт `main.dart`.
  WorldState.persistent(
    World world, {
    World Function()? freshWorld,
    Future<void> Function()? onReset,
  })  : _world = world,
        _freshWorld = freshWorld,
        _onReset = onReset;

  World _world;
  final World Function()? _freshWorld;
  final Future<void> Function()? _onReset;

  World get world => _world;

  ResourceSnapshot get snapshot => _world.snapshot;
  WeekPhase get phase => _world.phase;

  /// Что ребёнок выбрал в онбординге (S0) и с какого шага продолжить.
  OnboardingProgress get onboarding => _world.onboarding;

  /// Имя Финни для фраз экранов.
  String get finniName => _world.onboarding.finniName;

  /// Выбор онбординга одним значением — для рисования Финни.
  ///
  /// Только чтение: менять — через [setNickname], [setFinniLook],
  /// [setFinniName]. Геттер оставлен для экранов, которые читали прежний
  /// профиль.
  WorldProfile get profile => WorldProfile.of(_world.onboarding);

  /// Последний итог действия — для карточки «почему» на экране.
  WorldResult? lastResult;

  /// Здание с событием недели («!» в городе, S2) — из мира (A10).
  String? get eventBuildingId => _world.eventBuildingId;

  /// Выполнить действие мира и перерисовать всех слушателей.
  WorldResult act(WorldResult Function(World w) action) {
    final WorldResult r = action(_world);
    lastResult = r;
    notifyListeners();
    return r;
  }

  Future<WorldResult> _onboard(
      Future<WorldResult> Function(World w) action) async {
    final WorldResult r = await action(_world);
    notifyListeners();
    return r;
  }

  /// Онбординг: ник. Мир сохраняет его сразу.
  Future<WorldResult> setNickname(String nickname) =>
      _onboard((World w) => w.setNickname(nickname));

  /// Онбординг: вид, мальчик/девочка, облик; null — не менять.
  Future<WorldResult> setFinniLook(
          {String? species, FinniGender? gender, int? look}) =>
      _onboard((World w) =>
          w.setFinniLook(species: species, gender: gender, look: look));

  /// Онбординг: имя Финни (пусто — «Финни»).
  Future<WorldResult> setFinniName(String name) =>
      _onboard((World w) => w.setFinniName(name));

  /// Онбординг: шаг без выбора, «назад», «готово».
  Future<WorldResult> setOnboardingStep(int step) =>
      _onboard((World w) => w.setOnboardingStep(step));

  /// Сброс к первому запуску (демо-панель, раздел взрослого): новый мир и
  /// стёртый сохранённый онбординг.
  ///
  /// 🔴 Ждать завершения: стирание сохранённого идёт после замены мира, и
  /// выбор в онбординге, сделанный до конца стирания, был бы стёрт вместе
  /// со старым.
  Future<void> reset([World? world]) async {
    final World? next = world ?? _freshWorld?.call();
    if (next == null) {
      throw StateError('reset() без нового мира: у WorldState нет freshWorld');
    }
    _world = next;
    lastResult = null;
    notifyListeners();
    final Future<void> Function()? hook = _onReset;
    if (hook != null) await hook();
  }
}

/// Выбор ребёнка в онбординге одним значением — для рисования Финни.
/// Источник — [OnboardingProgress] мира; пока ничего не выбрано — облик по
/// умолчанию.
@immutable
class WorldProfile {
  const WorldProfile({
    this.species = defaultSpecies,
    this.look = 1,
    this.gender,
    this.childNick = '',
    this.finniName = OnboardingProgress.defaultFinniName,
  });

  factory WorldProfile.of(OnboardingProgress p) => WorldProfile(
        species: p.finniSpecies ?? defaultSpecies,
        look: p.finniLook ?? 1,
        gender: p.finniGender,
        childNick: p.nickname,
        finniName: p.finniName,
      );

  static const String defaultSpecies = 'finni-a1';

  /// Вид Финни — id из `assets/registry.json → finni`.
  final String species;

  /// Облик 1..4 — тег `idle-N` в листе вида.
  final int look;

  /// Мальчик или девочка; null — ещё не выбрано. 🟡 В реестре арта нет
  /// вариантов по полу — картинка пока одна на вид × облик.
  final FinniGender? gender;

  final String childNick;
  final String finniName;

  /// Тег покоя в листе вида.
  String get idleTag => 'idle-$look';

  WorldProfile copyWith({
    String? species,
    int? look,
    FinniGender? gender,
    String? childNick,
    String? finniName,
  }) =>
      WorldProfile(
        species: species ?? this.species,
        look: look ?? this.look,
        gender: gender ?? this.gender,
        childNick: childNick ?? this.childNick,
        finniName: finniName ?? this.finniName,
      );
}

/// [WorldState] над деревом или null — для экранов, которые показывают и в
/// тестах без провайдера.
WorldState? maybeWorldState(BuildContext context, {bool listen = true}) {
  try {
    return Provider.of<WorldState>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}
