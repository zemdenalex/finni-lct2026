import '../domain/world/contract.dart';
import 'storage.dart';

/// Прогресс онбординга нового мира в [Storage] (карточка A14).
///
/// Домен сохраняет через [OnboardingSave] и не знает про файлы; здесь —
/// адаптер. 🔴 В приложении онбордингом владеет `SavedWorld`
/// (`world_save.dart`): он читает его при запуске, пишет в одной очереди с
/// журналом и стирает при сбросе. Функции ниже — его кирпичи и помощники
/// тестов; `main.dart` их напрямую не зовёт.
const String onboardingStorageKey = 'world_onboarding';

/// Сохранённый прогресс или пустой, если его нет.
Future<OnboardingProgress> loadOnboarding(Storage storage) async =>
    OnboardingProgress.fromJson(await storage.read(onboardingStorageKey));

/// Хук сохранения для `FakeWorld` / `WorldGame`.
OnboardingSave saveOnboardingTo(Storage storage) =>
    (Map<String, Object?> json) => storage.write(onboardingStorageKey, json);

/// Забыть прогресс онбординга.
Future<void> clearOnboarding(Storage storage) async {
  await storage.delete(onboardingStorageKey);
  await storage.delete(brokenKey(onboardingStorageKey));
}
