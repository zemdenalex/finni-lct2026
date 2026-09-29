import 'contract.dart';

/// Прогресс онбординга и его сохранение (карточка A14) — общий для
/// `WorldGame` и `FakeWorld`.
///
/// Каждый шаг сохраняется **сразу**, через [OnboardingSave] (адаптер над
/// `Storage` — `lib/data/onboarding_store.dart`). Сохранение не удалось —
/// выбор всё равно запомнен в памяти, итог говорит об этом честно: лучше
/// пройти шаг заново после перезапуска, чем застрять на нём сейчас.
class OnboardingKeeper {
  OnboardingKeeper(this._progress, this._save);

  OnboardingProgress _progress;
  final OnboardingSave? _save;

  OnboardingProgress get progress => _progress;

  static int _max(int a, int b) => a > b ? a : b;

  Future<WorldResult> setNickname(String raw) async {
    final String nick = raw.trim();
    if (nick.isEmpty) {
      return const WorldResult.refused(
          'onboarding.nick_empty', 'Придумай ник — хотя бы одну букву.');
    }
    if (nick.length > OnboardingProgress.maxNameLength) {
      return const WorldResult.refused('onboarding.nick_long',
          'Ник длинноват — до ${OnboardingProgress.maxNameLength} символов.');
    }
    return _commit(
      _progress.copyWith(
          nickname: nick,
          step: _max(_progress.step, OnboardingProgress.stepFinni)),
      'onboarding.nick',
      'Привет, $nick!',
    );
  }

  Future<WorldResult> setFinniLook(
      {String? species, FinniGender? gender, int? look}) {
    return _commit(
      _progress.copyWith(
        finniSpecies: species,
        finniGender: gender,
        finniLook: look,
        step: _max(_progress.step, OnboardingProgress.stepFinni),
      ),
      'onboarding.look',
      'Отличный облик!',
    );
  }

  Future<WorldResult> setFinniName(String raw) async {
    final String trimmed = raw.trim();
    final String name =
        trimmed.isEmpty ? OnboardingProgress.defaultFinniName : trimmed;
    if (name.length > OnboardingProgress.maxNameLength) {
      return const WorldResult.refused('onboarding.name_long',
          'Имя длинновато — до ${OnboardingProgress.maxNameLength} символов.');
    }
    return _commit(
      _progress.copyWith(
          finniName: name,
          step: _max(_progress.step, OnboardingProgress.stepMoney)),
      'onboarding.name',
      'Приятно познакомиться, я $name!',
    );
  }

  Future<WorldResult> setStep(int step) => _commit(
        _progress.copyWith(
            step: step.clamp(
                OnboardingProgress.stepIntro, OnboardingProgress.stepDone)),
        'onboarding.step',
        'Шаг сохранён.',
      );

  Future<WorldResult> _commit(
      OnboardingProgress next, String code, String reason) async {
    _progress = next;
    final OnboardingSave? save = _save;
    if (save != null) {
      try {
        await save(next.toJson());
      } on Exception {
        return WorldResult(
          ok: true,
          reasonCode: 'onboarding.not_saved',
          reason: '$reason Только сохранить не вышло — если закрыть игру, '
              'этот шаг придётся повторить.',
        );
      }
    }
    return WorldResult(ok: true, reasonCode: code, reason: reason);
  }
}
