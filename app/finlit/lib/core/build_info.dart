/// Коммит, из которого собрана сборка: `--dart-define=BUILD_SHA=<hash>`.
/// Виден в меню ⋮ комнаты, чтобы по экрану понять, какая сборка открыта
/// (устаревший кэш веб-демо дважды выдавал старую).
const String buildSha =
    String.fromEnvironment('BUILD_SHA', defaultValue: 'dev');
