import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'app_state.dart';
import 'core/speaker.dart';
import 'data/storage.dart';
import 'data/world_save.dart';
import 'features/world/jobs/job_games.dart';
import 'features/world/onboarding/onboarding_script.dart';
import 'features/world/world_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(fontLicenses);
  final Storage storage = await openDefaultStorage();
  // Новый мир: журнал и онбординг — оба у SavedWorld (A16). Он сам
  // сохраняет после каждого действия, [SavedWorld.freshWorld] даёт мир для
  // сброса, [SavedWorld.forget] стирает сохранённое.
  //
  // До первого кадра здесь читаются три файла контента мира и сохранённый
  // журнал (свёртка). Испорченное сохранение не бросает — мир начинается
  // заново.
  final SavedWorld saved = await openSavedWorld(
    read: rootBundle.loadString,
    storage: storage,
  );
  // Содержание мини-игр профессий — из того же прочитанного jobs.json.
  final JobGames jobGames = JobGames.fromData(saved.content.jobData,
      university: saved.content.university);
  // Реплики сценок знакомства (`onboarding.json`) — тоже до первого кадра:
  // первый запуск идёт прямо в знакомство.
  // Битый файл не останавливает запуск — будет знакомство без реплик.
  final OnboardingScript script =
      await OnboardingScript.load(rootBundle.loadString);
  runApp(
    Provider<JobGames>.value(
      value: jobGames,
      child: Provider<OnboardingScript>.value(
        value: script,
        child: MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<AppState>(create: (_) => AppState(storage)),
            ChangeNotifierProvider<WorldState>(
              create: (_) => WorldState.persistent(
                saved.world,
                freshWorld: saved.freshWorld,
                onReset: saved.forget,
              ),
            ),
          ],
          child: const FinniApp(),
        ),
      ),
    ),
  );

  // 🔴 Проверка голоса идёт ПОСЛЕ первого кадра и без ожидания.
  //
  // Раньше здесь стоял `await Speaker.instance.prepare()` до `runApp`, то есть
  // до четырёх последовательных обращений к системному синтезатору Android
  // через канал платформы — и всё это время на экране не было вообще ничего.
  // §3.4.5 отводит на холодный старт пять секунд, и тратить их на
  // необязательную подсистему нельзя: если русского голоса на устройстве нет,
  // приложение просто не предложит озвучку, и ни один экран от этого
  // не ломается (§3.1.5 — основной цикл работает без сети).
  //
  // Доступность наблюдаемая, поэтому экран настроек покажет озвучку сам,
  // как только ответ придёт.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(Speaker.instance.prepare());
  });
}

/// Лицензии шрифтов для экрана «Настройки → Лицензии».
///
/// Пакеты Dart Flutter регистрирует сам, а шрифты — это ассеты, о которых он
/// не знает. OFL 1.1 требует, чтобы текст лицензии шёл вместе со шрифтом,
/// поэтому оба файла лежат в сборке и читаются только когда экран открыт.
Stream<LicenseEntry> fontLicenses() async* {
  for (final (String family, String file) in <(String, String)>[
    ('Onest', 'assets/fonts/OFL-Onest.txt'),
    ('Unbounded', 'assets/fonts/OFL-Unbounded.txt'),
  ]) {
    yield LicenseEntryWithLineBreaks(
        <String>[family], await rootBundle.loadString(file));
  }
}
