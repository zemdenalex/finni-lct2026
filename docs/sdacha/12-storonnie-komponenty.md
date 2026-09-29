# Сторонние библиотеки, шрифты, изображения, звуки и лицензии

> §5 п.12 ТЗ. Также §3.3: «все использованные изображения, шрифты, звуки и библиотеки должны
> иметь право на использование и распространение в составе прототипа». Ответ Q&A №11:
> графику, созданную ИИ, использовать можно, если указать сервис и модель.

Тексты лицензий шрифтов и дерево зависимостей лежат в `LICENSES/` репозитория для экспертов.
В приложении все лицензии открываются через «Настройки → Лицензии» (`showLicensePage`;
тексты OFL регистрируются в `lib/main.dart`, проверяет `test/features/licenses_test.dart`).

## 1. Библиотеки

| Пакет | Версия (`pubspec.lock`) | Лицензия | Зачем |
|---|---|---|---|
| Flutter SDK | 3.41.7 (CI) | BSD-3-Clause | Фреймворк |
| Dart SDK | 3.11.5 | BSD-3-Clause | Язык |
| `flutter_localizations` | из SDK | BSD-3-Clause | Русские подписи системных элементов («Назад», «Закрыть») для TalkBack |
| [`provider`](https://pub.dev/packages/provider) | 6.1.5+1 | MIT | Состояние в дереве виджетов |
| [`path_provider`](https://pub.dev/packages/path_provider) | 2.1.6 | BSD-3-Clause | Приватный каталог приложения для файлов профиля |
| [`flutter_tts`](https://pub.dev/packages/flutter_tts) | 4.2.5 | MIT | Озвучка объяснений системным синтезатором Android |
| [`flutter_lints`](https://pub.dev/packages/flutter_lints) | 6.0.0 | BSD-3-Clause | Только разработка, в сборку не входит |
| `integration_test`, `flutter_driver` | из SDK | BSD-3-Clause | Только замеры производительности, в сборку не входят |

Транзитивные зависимости — платформенные реализации `path_provider` и базовые пакеты
Dart-экосистемы (`collection`, `meta`, `path`, `plugin_platform_interface`, `nested`, `ffi`,
`win32`, `xdg_directories`). Все под BSD-3-Clause, MIT или Apache-2.0. Точный список с
версиями:

```bash
cd app/finlit && flutter pub deps --style=compact
```

## 2. Шрифты

| Шрифт | Начертания | Лицензия | Правообладатель | Текст лицензии |
|---|---|---|---|---|
| **Onest** | Regular, SemiBold, Bold, ExtraBold | SIL Open Font License 1.1 | The Onest Project Authors, [github.com/googlefonts/onest](https://github.com/googlefonts/onest) | `app/finlit/assets/fonts/OFL-Onest.txt` |
| **Unbounded** | SemiBold, ExtraBold — числа и короткие заголовки | SIL Open Font License 1.1 | The Unbounded Project Authors, [github.com/googlefonts/unbounded](https://github.com/googlefonts/unbounded) | `app/finlit/assets/fonts/OFL-Unbounded.txt` |

Файлы модифицированы: из вариативного файла получены статические начертания, набор глифов
урезан до латиницы, кириллицы, пунктуации, ₽ и №. OFL это разрешает. Зарезервированного имени
(Reserved Font Name) ни у одного шрифта нет, поэтому имена сохранены. Тексты лицензий едут в
сборке вместе со шрифтами.

Только на странице сравнения видов (`docs/design/variants/`, веб-демо `/demo/variants/`, **не в приложении**) шрифты
подключаются с Google Fonts по ссылке, в сборку не входят:

| Шрифт | Где | Лицензия |
|---|---|---|
| Press Start 2P (CodeMan38) | вариант C «всё пиксельное» | SIL Open Font License 1.1 |
| Onest, Unbounded | варианты A и B | SIL Open Font License 1.1 (см. выше) |

## 3. Изображения

### 3.1. Нарисовано командой в коде

| Что | Где |
|---|---|
| Иконка приложения (адаптивная) и иконка 512 × 512 для RuStore | рендерятся из кода: `tool/generate_store_icon_test.dart` |
| Пиктограммы интерфейса прежних экранов | `lib/core/icons.dart` |
| Геометрия зданий и комнаты — основа для генерации (раздел 3.2) | `tools/iso_building.py`, `tools/room_side.py` в рабочем репозитории команды |
| Черновой Финни кодом | `assets/finni/finni-a*.aseprite` |

### 3.2. Сгенерировано ИИ и доработано командой

| Что | Файлы | Сервис / модель | Как получено |
|---|---|---|---|
| Финни: 3 вида × 4 облика, анимация дыхания | `assets/finni/gpt/` | ChatGPT (генерация изображений OpenAI), 🟡 заполнить: Денис — точное название модели (gpt-image-…) и дату условий использования | Сетки 2 × 2 из ChatGPT → скрипт чистки: выравнивание по сетке пикселей, сокращение палитры, прозрачный фон, листы анимации в Aseprite |
| Питомцы: хомяк, котёнок, собака, рыбка, черепаха | `assets/pets/` | то же | то же |
| 7 зданий города | `assets/city/d072/` (вариант `d045` — для сравнения) | **Stable Diffusion XL base 1.0** (Stability AI) + LoRA **Pixel Art XL** (nerijs), локально через ComfyUI, без внешних API | Геометрия здания нарисована кодом → img2img SDXL, сила 0,72 → чистка пикселей |
| Комната Финни сбоку | `assets/room/` | то же | Геометрия комнаты кодом → img2img SDXL → чистка |
| Финни hi-res: вид a1 (4 облика) и енот a2 (4 облика + машет, шагает, прыгает) | `assets/hires/finni/` | ChatGPT (генерация изображений OpenAI) | Сгенерировано командой 27.09 (сетки 2 × 2 и пары комнат) → `tools/pixel_clean.py --hires` (нарезка, прозрачный фон, без выравнивания по сетке и сокращения палитры) → `tools/hires_art.py` (уменьшение до плотности @3x/@4x/@8x, листы анимации) |
| Питомцы hi-res: котёнок, жабка | `assets/hires/pets/` | то же | то же |
| Питомцы hi-res: хомяк, рыбка, черепаха, собака | `assets/hires/pets/`, исходники `assets/gen-sdxl/pets/` | **Stable Diffusion XL base 1.0** + LoRA **Pixel Art XL** (сила 0,6), локально через ComfyUI | Текст-в-картинку 28.09 (промпт и seed — в `tools/hires_generated.py`) → `pixel_clean.py --hires` → листы анимации |
| Здания hi-res: парк, кино, банк-копилка | `assets/hires/city/`, исходники `assets/gen-sdxl/city/` | **Stable Diffusion XL base 1.0** + LoRA **Pixel Art XL** (сила 0,6), локально через ComfyUI | Текст-в-картинку 28.09 (промпт и seed — в `tools/hires_generated.py`) → `pixel_clean.py --hires` → в коробку 120 × 84 |
| Питомцы hi-res: змейка, аксолотль | `assets/hires/pets/`, исходники `assets/gen-sdxl/pets/` | **Stable Diffusion XL base 1.0** + LoRA **Pixel Art XL** (сила 0,6), локально через ComfyUI | Текст-в-картинку 28.09 (промпт и seed — в `tools/hires_generated.py`) → `pixel_clean.py --hires` → листы анимации |
| Вещи магазина и декор комнаты: 4 вида еды, 4 предмета одежды, 3 плаката, 3 растения, лампочка и 2 гирлянды | `assets/hires/items/`, исходники `assets/gen-sdxl/items/` | то же | Текст-в-картинку 28.09, одна картинка на вещь каталога (промпты и seed — в `tools/hires_generated.py`) → прозрачный фон, обрезка по краю, уменьшение до @4x |
| Здания hi-res: сталинка, хрущёвка, рынок, магазин; башни Москва-Сити (в реестре, на карте пока нет места) | `assets/hires/city/` | то же | то же; тайлы с Кремлём из тех же сеток не используются |
| Комнаты стадий hi-res: деревня (пустая), город (та же с мебелью), Москва | `assets/hires/room/` | то же | то же |
| Предметы комнаты, которые нажимаются: дверь, комод с копилкой (деревня), холодильник (этап 4) | `assets/hires/room/door@4x.png`, `dresser@4x.png`, `fridge@4x.png`, исходники `assets/gen-sdxl/room/` | **Stable Diffusion XL base 1.0** + LoRA **Pixel Art XL** (сила 0,6), локально через ComfyUI | Текст-в-картинку 28.09 (промпт и seed — в `tools/hires_generated.py`, шаг `room`; дверь seed 42, комод seed 31, холодильник seed 31) → `pixel_clean.py --hires` → уменьшение до @4x (дверь 68 × 125, комод 47 × 62, холодильник 49 × 62 логических px), дверь отражена ручкой к комнате. На полках холодильника модель нарисовала бутылки — в исходнике они закрашены программной заливкой цветом полок: еду на полки кладёт само приложение (картинки товаров магазина). Передний план комнат (`front-*@3x.png`: кровать, матрас, коробки) вырезан тем же скриптом из фона комнаты по контуру |
| **Временные (placeholder) картинки блюд**, ночь 29.09: суп, сырники, бургер, рыба; плюс предложенные блюда, предметы комнаты и города (`night_items`, ещё не в игре) | `assets/hires/night/`, исходники `assets/gen-sdxl/night/` | **Stable Diffusion XL base 1.0** + LoRA **Pixel Art XL** (сила 0,6), локально через ComfyUI | Текст-в-картинку 29.09 (промпты и seed — в `tools/night_art.py`, шаг `gen`, 768 px) → `pixel_clean.py --hires` → в 64 px по длинной стороне, @4x. Статус в реестре `placeholder`: финальные ассеты рисует команда (промпты генерирует `tools/night_art.py prompts`) |
| **Временные (placeholder) мебель комнаты и вещи работы**, день 29.09: кровать и стол со стулом по стадиям, тумба, копилка, место питомца; ноутбук, мощный ноутбук, велосипед, самокат, скейт, касса, садовые инструменты, сумка курьера, тетрадь учёта, ценники, поводок | `assets/hires/night/room/`, `assets/hires/night/work/`, исходники `assets/gen-sdxl/night/` | **Stable Diffusion XL base 1.0** + LoRA **Pixel Art XL** (сила 0,6), локально через ComfyUI | Текст-в-картинку (промпты и seed — `tools/night_art.py`, блоки `ART2_*`) → та же чистка и сетка, что у ночных картинок; кровать города — перекраска московской, у столов убран второй предмет (`tools/art2_fix.py`). Статус `placeholder` |
| **Временный пустой фон комнаты** (квадрат, 3 стадии), день 29.09 | `assets/hires/room/shell-*@3x.png` | вырезан из загрузки ChatGPT 27.09 (комната деревни) и окон стадий, без генерации | `tools/room_shell.py`: полосы обоев, плинтуса, потолка и пола повторены, окно стадии вписано в место окна раскладки `content/room_layout.json`. Заменяется фонами, которые рисует команда |
| Страница сравнения видов, вариант B «всё гладкое»: комната, енот, котёнок, лягушка, два дома (не в приложении) | `docs/design/variants/src/b-*` | **Stable Diffusion XL base 1.0**, локально через ComfyUI, **без** LoRA | Текст-в-картинку 28.09 → `tools/pixel_clean.py --hires` (прозрачный фон) |

Лицензии моделей:

| Модель | Лицензия | Ссылка |
|---|---|---|
| stabilityai/stable-diffusion-xl-base-1.0 | CreativeML Open RAIL++-M | [карточка модели](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0), [текст лицензии](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/blob/main/LICENSE.md) |
| nerijs/pixel-art-xl (LoRA для SDXL) | CreativeML Open RAIL-M | [карточка модели](https://huggingface.co/nerijs/pixel-art-xl) |

Обе лицензии из семейства OpenRAIL: они разрешают использование модели и её результатов, но
ограничивают назначение использования (список ограничений — приложение к тексту лицензии).
**SDXL base 1.0, CreativeML Open RAIL++-M** ([текст](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/blob/main/LICENSE.md),
сверено 28.09), раздел «The Output You Generate»: *«Except as set forth herein, Licensor claims no rights in the Output
You generate using the Model. You are accountable for the Output you generate and its subsequent uses.»* Ограничения
назначения — Attachment A «Use Restrictions»; детская образовательная игра под них не подпадает.

**Pixel Art XL, CreativeML Open RAIL-M** — лицензия указана на [карточке модели](https://huggingface.co/nerijs/pixel-art-xl).
🟡 заполнить: Денис — процитировать пункт о результатах из текста RAIL-M (страница лицензии на Hugging Face 28.09 не
открылась без браузера; в семействе OpenRAIL это тот же раздел «The Output You Generate»).

**ChatGPT (генерация изображений OpenAI)** — [Terms of Use](https://openai.com/policies/terms-of-use/), сверено 28.09,
раздел «Content»: *«As between you and OpenAI, and to the extent permitted by applicable law, you (a) retain your ownership
rights in Input and (b) own the Output. We hereby assign to you all our right, title, and interest, if any, in and to
Output.»* Права на изображения из генераций — у команды. Там же: результат может быть похож на результаты других
пользователей (assignment «does not extend to other users’ output»); мы не выдаём результат за нарисованный человеком —
происхождение каждого файла указано в этом разделе.

**Референсы для промптов.** Фотографии зданий и животных с Wikimedia Commons (CC BY, CC BY-SA,
public domain) использовались только как референс формы и цвета в запросах к генератору. В
приложение и презентацию они не входят. Список с авторами и лицензиями ведётся в рабочем
репозитории команды. 🟡 заполнить: Денис — нужно ли перечислять их здесь, если это не
исходный материал ассетов.

🔴 Чужих персонажей, мемов и ассетов из других игр в приложении нет. Референс настроения
(стиль комнаты) использовался только словами, его ассеты не копировались.

### 3.3. Скриншоты

`app/finlit/assets/store/world/` — скриншоты нового мира, отрендеренные из экранов приложения
(`tool/render_world_screens_test.dart`): `*-land.png` 1600 × 720, `*-port.png` 720 × 1280. В APK
они не входят. Старые файлы уровнем выше показывают прежний интерфейс и в документацию сдачи не входят.

## 4. Звуки

Звуковых файлов в проекте нет. Отклик на действие — системный щелчок (`SystemSound`) и
вибрация, озвучка — системный синтезатор Android через `flutter_tts`: записанной речи
приложение не содержит.

🟡 заполнить: Алина — если в сборку добавят фоновую музыку lo-fi (CC0) или звуки, записать
сюда источник, автора и лицензию каждого файла.

## 5. Учебный контент

Тексты событий, мини-игр, реплик Финни и справочника написаны командой (`content/`,
`app/finlit/assets/content/`). Образовательные результаты процитированы из Единой рамки
компетенций в области финансовой грамотности (редакция от 05.03.2026) со ссылкой на источник.
Сам документ и ТЗ в репозиторий не включены: §6 ТЗ разрешает их использование только в рамках,
допускаемых правообладателем.

## 6. Лицензия на код проекта

🟡 заполнить: Денис — лицензия на код и ассеты команды (или «все права у команды») после
ответа организатора о правах на результат.
