import '../domain/world/world_config.dart';
import '../domain/world/world_game.dart';
import 'content_loader.dart' show ReadAsset;
import 'onboarding_store.dart';
import 'storage.dart';
import 'world_config_from_content.dart';
import 'world_content.dart';

/// Настоящий мир из файлов: `assets/content/world/*.json` → [WorldConfig] →
/// [WorldGame] (карточки A11, A14).
///
/// Цены каталога, работы, еда и перки берутся из контента, а не из значений
/// по умолчанию в коде. Прогресс онбординга читается из [Storage] и
/// сохраняется туда же на каждом шаге. Журнал мира здесь не сохраняется:
/// мир, который переживает перезапуск, — `openSavedWorld`
/// (`lib/data/world_save.dart`, A16). Этот загрузчик — для тестов и
/// автопилота, которым сохранение не нужно.
///
/// ```dart
/// final WorldGame world = await openWorldGame(
///   read: rootBundle.loadString,
///   storage: await openDefaultStorage(),
/// );
/// ```
Future<WorldConfig> loadWorldConfig(ReadAsset read) async =>
    worldConfigFromContent(await WorldContentLoader(read).load());

/// [WorldGame] на числах из контента и с онбордингом из [storage].
Future<WorldGame> openWorldGame({
  required ReadAsset read,
  required Storage storage,
}) async =>
    WorldGame(
      config: await loadWorldConfig(read),
      onboarding: await loadOnboarding(storage),
      saveOnboarding: saveOnboardingTo(storage),
    );
