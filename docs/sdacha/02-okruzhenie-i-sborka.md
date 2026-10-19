# Окружение и сборка релизного APK

> §5 п.2 ТЗ: требования к окружению, версии инструментов и пошаговая сборка релизного APK.
> Также §3.3: подписанный release-APK и готовность к RuStore.

По этому документу сборку должен повторить человек, который видит проект впервые.

## 1. Окружение

| Что | Версия | Где задано |
|---|---|---|
| Flutter | **3.41.7** stable | CI: `FLUTTER_VERSION` в `.github/workflows/ci.yml` |
| Dart | 3.11.5 (входит во Flutter 3.41.7) | там же |
| Ограничение SDK в проекте | `>=3.5.0 <4.0.0` | `app/finlit/pubspec.yaml` |
| Gradle | 9.3.1 | `app/finlit/android/gradle/wrapper/gradle-wrapper.properties`, скачивается сам |
| Android Gradle Plugin | 8.9.1 | `app/finlit/android/settings.gradle.kts` |
| Kotlin | 2.4.0 | там же |
| JDK | 17 или 21 | CI ставит Temurin 17; локально проверено на OpenJDK 21 из Android Studio |
| Android SDK Platform / Build-Tools | android-36 / 36.1.0 | SDK Manager |
| Android SDK cmdline-tools | latest | 🔴 без него не собирается AAB (см. раздел 5) |
| Android NDK | подтягивается Gradle по `flutter.ndkVersion` | — |
| compileSdk / targetSdk / minSdk | 36 / 36 / **26** (Android 8.0) | `app/finlit/android/app/build.gradle.kts` |
| Пакет | `ru.lct2026.finlit` | там же |

Проект также проходит `flutter analyze` и `flutter test` на Flutter 3.47.4: второй версией
пользуется один из разработчиков. Версия Flutter выложенной сборки записана в разделе 4 (из отчёта гейта).

🔴 **В пути к репозиторию не должно быть кириллицы.** Analysis server Flutter на таком пути
падает с `FormatException … exited with code 255`, и про путь в сообщении ничего нет.

Проверка окружения:

```bash
flutter --version
flutter doctor -v     # нужны две зелёные строки: Flutter и Android toolchain
```

## 2. Ключ подписи

Без подписи Android не установит APK. Keystore создаётся один раз и хранится **вне
репозитория**:

```bash
keytool -genkeypair -v \
  -keystore ~/keys/finlit-upload.p12 -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 -alias upload \
  -dname "CN=LCT 2026 Team, O=LCT, L=Moscow, C=RU"
```

Ключ подключается файлом `key.properties` в каталоге `app/finlit/android/`. Заготовка без значений лежит
рядом, `key.properties.example`:

```bash
cd app/finlit/android
cp key.properties.example key.properties   # вписать storeFile, storePassword, keyAlias, keyPassword
git check-ignore -v key.properties          # должна что-то напечатать: файл перекрыт .gitignore
```

🔴 **Если `key.properties` нет, сборка не падает**, а молча подписывает release отладочным
ключом. Так сделано нарочно, чтобы свежий клон и CI собирались. Но успешная сборка ничего
не говорит о подписи: подпись проверяется отдельно (раздел 4).

## 3. Сборка

```bash
cd app/finlit
flutter pub get
flutter clean
find android -name GeneratedPluginRegistrant.java -delete

flutter build apk --release                  # universal APK — для экспертов и RuStore
#   → build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release            # AAB — дополнительный формат по §3.3
#   → build/app/outputs/bundle/release/app-release.aab
flutter build apk --release --split-per-abi  # по архитектурам — только для справки о размере
```

Экспертам отдаётся universal APK: он ставится на любой телефон, поэтому именно он выложен как `finni.apk`.

⚠ В RuStore грузится только universal APK. У сплитов Flutter меняет `versionCode`
(`ABI × 1000 + versionCode`), и после них universal с меньшим номером магазин уже не примет.

Первая сборка на новой машине идёт долго и требует сети: Gradle скачивает себя, AGP и NDK
(около 9 ГБ на диске).

## 4. Проверка собранного APK

Утилиты лежат в `$ANDROID_HOME/build-tools/36.1.0/`.

```bash
cd app/finlit/build/app/outputs/flutter-apk
apksigner verify --print-certs -v app-release.apk   # ждём CN=LCT 2026 Team, RSA 4096
aapt2 dump permissions app-release.apk              # пользовательских разрешений нет
aapt2 dump badging app-release.apk | head -5        # пакет, версия, minSdk 26, название
```

🔴 Если в подписи `CN=Android Debug`, значит `key.properties` не подхватился. Такой файл
нельзя отдавать ни экспертам, ни в RuStore.

Единственная строка `uses-permission` в выводе — `ru.lct2026.finlit.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
Её добавляет `androidx.core` при targetSdk 33+. Уровень защиты у неё `signature`, у пользователя
она не запрашивается (подробно — в [09-razresheniya-i-dannye.md](09-razresheniya-i-dannye.md)).

**Замеры выложенной сборки.** Числа ниже вписываются только из отчётов той сборки, которая выложена
(`tools/release_gate.sh` → `release-gate.txt`, `tools/stage_release.sh` → `finni.apk.sha256`), скриптом
`tools/fill_release_facts.py`; руками их не набирают. Сборки не воспроизводятся побайтно, поэтому SHA-256 и размер
относятся ровно к выложенному файлу. МБ = 10⁶ байт.

| Параметр | Значение |
|---|---|
| Коммит сборки (строка «Сборка …» в «Настройках», файл `finni.apk.build`) | `9198669` (`919866990cf361898526b8e2927164814f90bcd8`) |
| Версия (`version:` в `pubspec.yaml` = `versionName+versionCode`) | `0.1.3+4`: `versionName` 0.1.3, `versionCode` 4 |
| Flutter, на котором прошёл гейт (`flutter analyze` + полный `flutter test`) | 3.41.7, 19.10.2026 |
| Размер universal APK (`finni.apk`) | **104,2 МБ** (104 235 202 байт) |
| SHA-256 `finni.apk` | `0ebbc25620d4bf1e1d27d20150535549fec39f2270de86377bb90213fabe7a2e` |
| Подпись (`apksigner verify --print-certs`) | `CN=LCT 2026 Team` (ключ команды, не `Android Debug`); `tool/check_manifest.sh` сверяет SHA-256 сертификата |
| `aapt2 dump badging` | `package: ru.lct2026.finlit`, `versionCode 4`, `versionName 0.1.3`, `minSdkVersion 26`, `targetSdkVersion 36`, `application-label 'Питомец Финни'`, `native-code arm64-v8a armeabi-v7a x86_64` |

`versionCode` выложенной сборки больше, чем у сданной 29.09 (1), поэтому она ставится обновлением поверх, без удаления
(`tool/check_manifest.sh` требует `versionCode` ≥ 4). Основной вес APK — пиксель-арт высокого разрешения
(`assets/art/hires/`) и три архитектуры в одном файле: движок Flutter и код игры лежат в трёх копиях.

**Контрольная сумма.** Рядом с APK в https://finni.archifex.space/eksperty/files/ лежит SHA-256 того же файла
(`finni.apk.sha256`), чтобы эксперт сверил скачанное: `sha256sum app-release.apk`
(Windows — `certutil -hashfile app-release.apk SHA256`).

## 5. Грабли

| Симптом | Причина | Что делать |
|---|---|---|
| AAB: «failed to strip debug symbols from native libraries» | Нет `cmdline-tools` в Android SDK: AAB проверяется утилитой `apkanalyzer` | SDK Manager → Android SDK Command-line Tools (latest). CI проверяет это отдельным шагом |
| Сборка падает на старом `GeneratedPluginRegistrant.java` | Сгенерированный файл остался от прошлой версии плагинов | Удалить его перед сборкой (шаг в разделе 3) |
| Сборка успешна, а подпись `Android Debug` | Нет `key.properties` | Раздел 2 |
| Google Play Защита блокирует установку (так было на телефоне участника команды 28.09) | APK не из магазина, ключ команды Google не знаком | «Подробнее» → «Всё равно установить»; порядок — [01-readme.md](01-readme.md#установка-apk-на-телефон) |
| `flutter analyze` падает с `FormatException` | Кириллица в пути | Перенести репозиторий |

## 6. Минификация — не обфускация

Flutter в release включает R8, и это минификация Java/Kotlin-части. Dart-код в APK
скомпилирован заранее (AOT), а обфускация Dart (`--obfuscate`) не применяется. Требование §7.2
«исходный код без обфускации» относится к репозиторию: весь исходный код здесь.

## 7. CI

`.github/workflows/ci.yml`:

- на каждый push и PR — `flutter pub get`, `dart format` (только отчёт), `flutter analyze`,
  `flutter test`;
- по кнопке (workflow_dispatch) — release APK и AAB. Они подписаны **отладочным** ключом,
  потому что keystore в CI не передаётся. Артефакт так и называется:
  `finlit-release-DEBUG-SIGNED-do-not-ship`.

Сборку для экспертов делает человек с ключом, на своей машине, по разделам 2–4.

## 8. Готовность к RuStore

Публиковать приложение во время хакатона не требуется (§2.7.4), нужна готовность к
публикации (§3.3): уникальный пакет `ru.lct2026.finlit`, подписанный universal APK, minSdk 26,
разрешений нет. Черновик карточки (рабочий документ команды, в этот репозиторий не входит): название «Питомец Финни»,
категория «Образование» (дополнительная — «Родителям»), краткое и подробное описание, возрастная маркировка 0+
с обоснованием: рекламы, покупок и сбора данных
нет. Иконка 512 × 512 и скриншоты — `app/finlit/assets/store/` (нового интерфейса — `world/`, отрисованы
автотестом; снимков с телефона в комплекте нет).
