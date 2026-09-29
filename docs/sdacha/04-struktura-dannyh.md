# Структура данных: профиль, экономика, работа, прогресс

> §5 п.4 ТЗ: «структура данных профиля, игровой экономики, заданий и прогресса».
> Источники: `app/finlit/lib/domain/world/contract.dart`, `world_entry.dart`, `world_fold.dart`
> и `content/*.json`.

## 1. Общий принцип

Данные делятся на две части:

- **контент** — числа и тексты игры, одинаковые у всех (`content/*.json`, только чтение);
- **профиль** — то, что сделал ребёнок: выбор в онбординге и журнал игровых действий.

Деньги, ⚡, 😊, опыт, очки роста и стадия **не хранятся отдельными полями**: это результат
свёртки журнала (`WorldState.fold`).

## 2. Профиль

### 2.1. Онбординг — `OnboardingProgress`

Хранится в ключе `world_onboarding` (`lib/data/onboarding_store.dart`).

| Поле | Тип | Что | Требование |
|---|---|---|---|
| `step` | int 0–6 | С какого шага продолжить онбординг | перезапуск на середине |
| `nickname` | string, 1–16 символов | Ник ребёнка; реальное имя не спрашивается | 2.5.1.2, 3.5.1 |
| `finniSpecies` | string | Вид Финни, id из `assets/registry.json` (`finni-a1` …) | 2.5.2.1 |
| `finniGender` | `boy` / `girl` | Облик мальчика или девочки | 2.5.2.1 |
| `finniLook` | int | Вариант облика внутри вида (тег `idle-N`) | 2.5.2.1 |
| `finniName` | string, 1–16 символов, по умолчанию «Финни» | Игровое имя | 2.5.2.2 |

### 2.2. Журнал — `WorldEntry`

Одна запись = одно изменение и его причина. Все числа в записи — **изменения**, а не значения.

| Поле | Тип | Что |
|---|---|---|
| `seq` | int | Порядковый номер, с 0 |
| `weekNo` | int | Игровая неделя |
| `kind` | string | Вид записи: `world.*` (новый мир), `ledger.*` (общие виды), `choice.*` (выбор без денег), `demo.*` (панель «Проверка») |
| `reasonCode` | string | Код причины — ключ текста для ребёнка |
| `need` · `want` · `goal` · `free` · `unallocated` | int | Изменение конвертов НУЖНО, ХОЧУ, ЦЕЛЬ, кошелька заработка и неразложенных карманных |
| `energy` | double | Изменение ⚡ |
| `happiness` | int | Изменение 😊, уже с учётом границ 0–100 |
| `args` | object | Подробности: id работы, товара, сумма, оценка смены, итог недели |

Сериализация — `WorldEntry.toJson` / `fromJson`. Запись неизвестного вида (от старой или
будущей версии) пропускается и не роняет приложение.

**Виды записей** (`WorldLedgerKind` в `contract.dart`): `weekStarted`, `startGift`, `billPaid`,
`billMissed`, `jobStarted`, `jobPayout`, `goalSliderDeposit`, `leisure`, `sleep`, `energyOut`,
`eventShown`, `eventChoice`, `petBought`, `transportBought`, `homeBought`, `itemOwned`,
`activePetChanged`, `petTapHappiness`, `familyHelp`, `simulationRun`, `parentBonus`,
`stageChanged`, `dayPassed`, `lessonChoice` (урок после смены: `args.jobId`, `choiceId`, `title`, `word`), `techBought` (куплена техника — цель), `mealEaten` (Финни поел: `args.foodId`, `args.price`; монеты из
НУЖНО → заработок → ХОЧУ, ⚡ и 😊 сразу). Из общих видов (`LedgerKind`) новый мир использует `pocketMoney`,
`planConfirmed`, `purchase`, `savingsWithdraw`, `periodClosed`. Выборы без денег
(`WorldChoiceKind`): `goalChosen`, `foodChosen` (домашнее меню — что Финни ест дома за
невыбранные приёмы). Демо для эксперта (`WorldDemoKind`):
`unlockAllJobs` — «Открыть все профессии», без денег, ⚡, 😊 и покупок; `showEvent` —
«Показать событие»: `args.eventId` становится событием недели (ждёт выбора, как `eventShown`,
но расписание не сдвигает), без денег, ⚡ и 😊; закрывает его обычный `eventChoice`.

Пример записи — оплата хорошей смены консультанта:

```json
{"seq": 7, "weekNo": 1, "kind": "world.jobPayout", "reasonCode": "job.payout",
 "free": 357, "energy": -3.5, "happiness": -1,
 "args": {"jobId": "consultant", "pay": 300, "bonus": 57, "score": 0.95, "good": true}}
```

**Хранение журнала (ТЗ 2.5.13.1).** `openSavedWorld` (`lib/data/world_save.dart`) пишет журнал
под ключом `world_journal` как `{"v": 1, "journal": [...записи выше...]}` после каждого
действия, которое что-то записало (отказ ничего не пишет), и собирает мир из него на старте
(`WorldGame.fromJson`). Записи идут по одной, в порядке вызова; журнал читается после того, как
действие закончилось, а не посреди него. Онбординг — отдельно, `world_onboarding`. Испорченное
сохранение не роняет запуск: мир начинается заново, исходное значение откладывается в
`world_journal_broken`; записи неизвестного вида пропускаются, их число — `WorldGame.unreadable`.
Подключено в `lib/main.dart`: приложение стартует с сохранённого мира.

### 2.3. Снимок — `ResourceSnapshot` (выводится, не хранится)

| Поле | Что |
|---|---|
| `weekNo` | Номер недели, с 1 (до первой — 0) |
| `need`, `want`, `goal`, `free`, `unallocated` | Конверты НУЖНО, ХОЧУ, ЦЕЛЬ (= накоплено), кошелёк заработка, неразложенное |
| `available` | Доступно (💰 в HUD) = НУЖНО + ХОЧУ + заработок + неразложенное. ЦЕЛЬ сюда не входит |
| `energy` | ⚡ 0–14 |
| `happiness` | 😊 0–100 |
| `growthPoints` | Очки роста за всю игру, никогда не уменьшаются |
| `stage` | `village` / `town` / `moscow` |
| `experience` | Число хорошо сделанных смен за всю игру |
| `shiftsThisWeek` | Смен на этой неделе |
| `weeklyBill` | Сколько спишется в конце недели: еда (домашнее меню × невыбранные приёмы) + корм + жильё + добавка события |
| `foodId` | Домашнее меню |
| `mealsThisWeek`, `mealsPerWeek` | Сколько раз Финни поел на этой неделе и сколько можно (`food.meals_per_week`) |
| `owned` | id всего, чем Финни владеет: питомцы, транспорт, жильё, вещи |
| `activeGoalId`, `activePetId` | Текущая цель и питомец в комнате |
| `endedBy` | Чем кончилась неделя: `energyOut` или `sleep` |
| `moodReason` | Причина настроения одной фразой |

## 3. Экономика — `content/economy.json`

| Раздел | Ключевые поля | Значения сейчас |
|---|---|---|
| `pocket_money` | `base`, `index_curve` | 400 в неделю; индексация выключена (все 1,0) |
| `start_gift` | `amount`, `to` | 200 в ЦЕЛЬ при первом запуске |
| `week` | `max_shifts_per_week`, `max_shifts_per_job_per_week`, `required_charged_at` | 3 смены (Денис 28.09), 2 на одну работу; обязательное списывается в конце недели |
| `energy` | `base_per_week`, `max_per_week`, `living_drain_per_action`, `sleep`, `exhausted`, `snack` | 10, 14, 1; сон +1 ⚡ и +3 😊; перекус 60 → +1 ⚡, до 2 в неделю |
| `happiness` | `start`, `pay_mult`, `energy_cost_mult`, `weekly_decay`, `day_drain`, `week_growth`, `leisure_weekly_cap`, `goal_reached_bonus` | 50; ±0,004 и ±0,005 на пункт от 😊 на начало недели; остывание 6 + 0,7 × (😊₀ − 50); −1 за игровой день; рост недели +2, без роста −3 × недель подряд (до −9), рост дохода от 10 %; досуг ≤ 16 в неделю; цель +10 |
| `food` | `meals_per_week`; `options[]`: `price`, `happiness` (вкус), `energy_now` (польза), `treat` (вкусное без пользы — для итогов недели) | 3 приёма в неделю; 13 блюд за приём: бутерброд с чаем 60 / 0 / 0 · мороженое 70 / +2 / 0 (вкусное без пользы) · овсянка 80 / +1 / 0,5 · макароны 100 / +2 / 0,5 · омлет 130 / +1 / 1,5 · роллы 260 / +4 / 1 · каша 70 / 0 / 0,5 · суп 90 / 0 / 1 · гречка 120 / +1 / 1 · сырники 150 / +2 / 1 · бургер 160 / +3 / 0 · пицца 200 / +4 / 0,5 · рыба 230 / +3 / 1,5 (06-formuly.md §6.2) |
| `homes.options[]` | `price` (залог и первая неделя), `weekly_cost`, `energy_per_week`, `happiness_per_week`, `stage` | аренда: комната в деревне 0 / 250 · квартира в городе 1 200 / 400 / +1 / +4 · квартира в Москве 2 000 / 1 000 / +2 / +8; `growth.stage_by_rent: true` — стадия = снятое жильё |
| `pets.roster[]` | `price`, `food_per_week`, `happiness_per_week`, `perk`, `tier` | рыбка 400, хомяк 750, черепаха 900, котёнок 1 800, собака 3 200 (к демо); жабка, змея, аксолотль — резерв |
| `transport` | `price`, `effects[]`, `options[]` | 1 800; открывает курьера, смена дешевле на 0,5 ⚡; велосипед, самокат, скейт |
| `tech.options[]` | `price`, `unlocks[]` | ноутбук 3 000 → `computer` (программист: лёгкая, средняя); мощный ноутбук 6 000 → `computer`, `computer_pro` (и сложная); цели из ЦЕЛИ |
| `clothing.items[]` | `price`, `fade[3]` | кепка 300, шарф 350, толстовка 600, кроссовки 800 |
| `decor.items[]` | `price`, `group`; `happiness_once` | 9 предметов 200–750; +3 😊 один раз |
| `leisure.options[]` | `price`, `energy`, `happiness` | парк 0 / 1 / 6 · кафе 200 / 1 / 9 · кино 150 / 2 / 10 · игра с питомцем 0 / 1 / 4 (+1 за каждого питомца сверх первого) |
| `jobs` | `pay`, `energy` (или `tiers[]` с `unlocked_by` уровня), `unlocked`, `unlocked_by` | консультант 300 / 2 · помощник бухгалтера 280 / 2 · кассир 260 / 2 · садовник 180 / 1 — с первого дня · программист 280 / 400 / 480, ⚡ 2–4 (ноутбук; сложная — мощный) · курьер 300–520 / 2–4 (транспорт) · выгульщик 220 / 1 (собака) |
| `jobs_pay_growth` | `experience_mult_per_shift`, `good_score_min`, `good_shift_*`, `efficiency_bonus_max_share` | 1,01 (перепроверка 29.09; было 1,02 — P8); 0,75; +0,5 ⚡ и −1 😊; 20 % |
| `shortfall_rule.order[]` | шаги правила нехватки | корм первым → простое домашнее меню (каша) → копилка с согласия → «семья помогает» −6 😊 |
| `growth` | `points`, `saved_regularly_min_share`, `stages[]` | по 1 очку за 3 причины; 10 %; стадии 0 / 4 / 9, ступень оплаты ×1 / ×1,2 / ×1,35 |

Ключи с `_` — комментарии: игра и симулятор их пропускают.

## 4. Работа — `content/jobs.json`

Содержание мини-игр, уровень 1. Оплаты и ⚡ здесь нет — только ссылки на `economy.json → jobs`.

| Работа | Что в файле |
|---|---|
| `consultant` | `sets[]` — 4 набора по 3 товара (`items[]` с характеристиками), покупатель (`customer.line`, `budget`, `best_fit`, реплики `feedback_*`) |
| `accountant` | помощник бухгалтера студсовета — схема консультанта: `sets[]` — 3 набора (автобус, угощение, принтер), `customer` — староста со сметой; `texts` — подписи экрана вместо «товаров» и «сканера» (`sort_intro`, `check`, `check_wait`, `all_ok`, `pick`) |
| `lessons` (не работа) | урок после смены по id работы: `topic` (budget / savings / payments), `title`, `situation`, `understood` («что мы поняли»), `word` + `word_term` (Словарик), `choices[]` — 2–3: `label`, `effects` (`goal_share`, `need_share` — доля оплаты смены 0..1; `spend`; `happiness`), `finni` |
| `university` (не работа) | вуз Финни на доске «Требуется…»: `title`, `intro` (почему открыты финансовые работы), `cards[]` (`title`, `text`, `source` — настоящий источник, без ссылок), `adult_note` — адреса источников, только в разделе взрослого |
| `cashier` | `coins[]`, `bills[]`, `customers_per_shift` 2, `purchases[]` — 7 покупок (`item`, `price`, `paid_with`; `change` — для людей, сдачу считает код), `feedback` (`{diff}` — на сколько ошибся) |
| `gardener` | `beds` 6, `grid` [столбцы, строки], `max_dry_at_once`, пороги `great_share` / `ok_share`, строки итога, ходы `calm_turns` / `calm_wilt_turns` — игра только по ходам, часов нет (с 29.09) |
| `courier` | `orders[]` — 3 заказа (`tier`, `maze`, `map` — карта строками: `S` старт, `G` клиент, `.` дорога, буквы — стены; `order_card`, `parcels[]` с `why` у неверных), `walls` — буква → название стены, `wrong_turn_rule` |
| `programmer` | `tasks[]` — 3 задачи (`tier`, `device`, `goal`, `blocks[]` — палитра, `solution[]` — id блоков, могут повторяться, `hint_on_error`). Id задачи выбирает устройство в коде |

Игра читает эти поля при запуске (`WorldContent` → `JobGames`); ошибка в файле — сообщение с путём
до поля (`jobs.json → jobs.courier.orders[0].map: нужен ровно один S и один G`) до первого кадра.

## 5. Задания-события — `content/events.json`

| Поле | Что |
|---|---|
| `id`, `topic` | id и тема: `planning` или `savings` |
| `building` | Здание города, над которым горит «!» |
| `conditions` | Когда событие может появиться (неделя, ⚡, метка) |
| `title`, `situation` | Заголовок и ситуация для ребёнка |
| `options[]` | 2–3 варианта: `label`, `effects` (схема — `_effects_schema`), реплика Финни с объяснением |
| `_rules` | Частота (1–2 в неделю, одно событие не чаще раза в 4 недели), доступность вариантов |
| `_flags` | Метки, которые ставят события, и кто их читает |

Список всех событий с логикой и объяснениями — в
[07-obrazovatelnyy-kontent.md](07-obrazovatelnyy-kontent.md).

## 6. Прогресс

Прогресс — тоже свёртка журнала:

- **очки роста** — сумма `args.points` из записей `periodClosed` (закрытие недели);
- **стадия** — последний порог из `growth.stages[].min_points`, который набран;
- **опыт** — число записей `jobPayout` с `args.good = true`;
- **история недели** — записи журнала с этим `weekNo`: смены, покупки, события, счета.

Формулы — в [06-formuly.md](06-formuly.md).
