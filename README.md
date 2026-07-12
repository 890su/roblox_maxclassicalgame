# Тень Молота (Shadow of the Hammer)

**Roblox RPG / Adventure** с тремя концовками и прогрессирующей сюжетной петлёй.

Описание для игроков: [docs/game.html](docs/game.html) — откройте в браузере.

Имя проекта в Rojo: **ShadowOfTheHammer** (`default.project.json`).

## Быстрый старт

1. Установите [Rojo](https://rojo.space/) и [Aftman](https://github.com/LPGhatguy/aftman).
2. В каталоге `classical_game`: `aftman install` — подтянет Rojo (версия зафиксирована в `aftman.toml`).
3. **Сборка файла для Studio:**  
   `rojo build default.project.json -o game.rbxlx`  
   Откройте `game.rbxlx` в Roblox Studio и нажмите **Play**.
4. **Живая синхронизация с Studio:**  
   `rojo serve` — в Studio подключитесь к серверу через [плагин Rojo](https://rojo.space/docs/installation).

После **Play** используется карта, собранная в **Roblox Studio**. Процедурная генерация мира отключена: в `WorldGenerator.server.lua` закомментирован вызов `GenerateAll()`. Чтобы снова сгенерировать мир из кода, раскомментируйте эту строку или вызовите генератор вручную из консоли команд разработчика.

## Структура репозитория (Rojo → Studio)

Корневое дерево задаётся в `default.project.json`. Исходники — в `src/`.

```
src/
├── server/                    → ServerScriptService
│   ├── StageWorldConfig.lua   — ★ ЕДИНЫЙ конфиг (только сервер)
│   ├── GameConfig.lua         — фасад
│   ├── WorldMap.lua           — границы зон
│   ├── WolfConfig.lua / SwampConfig.lua
│   ├── GameManager.server.lua — …
│   ├── WorldGenerator.server.lua — Процедурная генерация мира (автозапуск выключен)
│   ├── TombTeleporter.server.lua — Телепорты лабиринта гробницы (A↔C, D↔A)
│   ├── TombWindTurbinePuzzle.server.lua — Головоломка: толкнуть ветряк на гидру
│   │
│   ├── DataManager.lua        — DataStore
│   ├── QuestManager.lua       — Квесты (data-driven)
│   ├── CutsceneManager.lua    — Кат-сцены на сервере
│   ├── NPCController.lua      — NPC: Старейшина, Dou Dzouh, торговец (заглушка)
│   ├── WolfSpawner.lua        — Волки, AI, уведомления о луте
│   ├── WeaponManager.lua      — Меч и Ban Hammer
│   ├── MiniBossSpawner.lua    — King Hydra Blaster
│   ├── SwampCrossing.lua      — Проводник Dou Dzouh через болото
│   ├── MapPickupSpawner.lua   — Физическая карта/письмо в доме деда
│   └── TombLighting.lua       — Освещение лабиринта, фонарь, голем
│
├── client/                    → StarterPlayerScripts
│   ├── CutsceneClient.client.lua
│   ├── DialogueUI.client.lua
│   ├── HUDController.client.lua
│   ├── MapViewer.client.lua
│   ├── InventoryUI.client.lua
│   ├── CreditsScreen.client.lua
│   ├── CameraAntiPeek.client.lua
│   └── DebugTools.client.lua  — Дебаг (убрать/отключить перед релизом)
│
├── character/                 → StarterCharacterScripts (пока только README.lua)
├── gui/                       → StarterGui (пока только README.lua; HUD в коде клиента)
├── loading/                   → ReplicatedFirst
│   └── LoadingScreen.client.lua
│
├── shared/                    → ReplicatedStorage/Shared (только Remotes + ItemConfig)
│   ├── Remotes.lua
│   └── ItemConfig.lua
│
│   Сюжет, квесты, зоны, диалоги — src/server/ (клиент не видит)
│
└── assets/                    → ServerStorage/Assets (модели для спавна)
```

**Замечание по именам файлов:** скрипты с суффиксом `.server.lua` / `.client.lua` — отдельные точки входа, которые Studio запускает сама. Остальные `*.lua` в `server/` — модули, подключаются через `require` из `GameManager` (и иногда друг из друга).

В **Workspace** Rojo создаёт пустые папки-заготовки (`Zones`, `NPCs`, `Triggers`, `SpawnPoints` и т.д.); фактическое наполнение — из карты в Studio либо из `WorldGenerator`, если включён автозапуск `GenerateAll()`.

## Стадии сюжета в коде

Последовательность в `GameConfig.GameStages`:

`SPAWN` → `WOLF_HUNT` → `JOHN_RESCUE` → `BAD_NEWS` → `SECRET_MAP` → `FOREST_JOURNEY` → `SWAMP_JOURNEY` → `MINI_BOSS` → `TOMB_MAZE` → `BAN_HAMMER` → `FINALE` → `CREDITS`

Имя стадии `JOHN_RESCUE` историческое; в игре персонаж-спаситель — **Dou Dzouh** (внутренний id `DouDzouh`).

## Цепочка квестов

`KILL_WOLVES` → `RETURN_TO_VILLAGE` → `FIND_MAP` → `TRAVERSE_FOREST` → `CROSS_SWAMP` → `DEFEAT_MINI_BOSS` → `SOLVE_MAZE` → `GET_BAN_HAMMER`

Описание целей — в `src/server/QuestConfig.lua`. Клиент видит только активный квест через `QuestStarted` / `QuestUpdated`.

## Сюжет (10 шагов)

1. **Деревня** — Старейшина даёт квест «убей волков», выдаёт меч.
2. **Окрестности** — Охота на волков (8 штук).
3. **Спасение** — Кат-сцена: Dou Dzouh спасает от волка, знакомство.
4. **Плохие новости** — Смерть деда, совет зайти в дом.
5. **Тайная карта** — Подбор карты в доме деда, UI карты.
6. **Лес** — Путь с Dou Dzouh к болоту.
7. **Болото** — Ядовитый туман; Dou Dzouh ведёт по кочкам `SwampKochka_1…N`.
8. **Мини-босс** — King Hydra Blaster; можно сбить ветряком или победить в бою.
9. **Лабиринт гробницы** — Studio-карта `Mazegame.MAZE`, телепорты, фонарь, голем → зал артефакта → **Ban Hammer**.
10. **Финал** — Одна из трёх концовок → титры.

## Три концовки

| # | Условие | Исход | Статус в коде |
|---|---------|-------|---------------|
| 1 | Первое прохождение (`EndingsCount = 0`) | Dou Dzouh предаёт | Кат-сцена → титры |
| 2 | После концовки 1 | Герой даёт отпор | Кат-сцена есть; **soft-lock** — бой TODO, титры не запускаются |
| 3 | После концовки 2 + код `SHADOW` | Правда раскрыта, зло ускользает | Логика выбора есть; **UI ввода кода и handler `SubmitSecretCode` отсутствуют** |

Код для третьей ветки: `GameConfig.Settings.SecretCode` (сейчас **`SHADOW`**).

## Статус реализации

Актуально по состоянию кода в репозитории. Символы: ✅ готово · ⚠️ частично · ❌ не начато / заглушка.

### Ядро и прогресс

| Система | Статус | Примечание |
|---------|--------|------------|
| GameManager, стадии, триггеры | ⚠️ | Полный happy path работает; стадия **не сохраняется** между сессиями |
| QuestManager (движок) | ✅ | Data-driven, цепочка, награды |
| Связь волков с квестом | ⚠️ | `WolfSpawner` меняет стадию на `JOHN_RESCUE`, но **не вызывает** `QuestManager:UpdateProgress("KILL","Wolf")` — HUD может показывать 0/8 |
| Стадия `SECRET_MAP` | ⚠️ | Обработчик есть, но стадия **нигде не выставляется** — переход BAD_NEWS → карта → FOREST_JOURNEY |
| DataStore | ⚠️ | `Money`, `EndingsCount`, `Inventory` сохраняются; **стадия/квест — нет**; `CurrentQuestId`, `WolvesKilled`, `FoundSecrets`, `TotalPlaytime` не используются |

### Персонажи и бой

| Система | Статус | Примечание |
|---------|--------|------------|
| Старейшина (Elder) | ✅ | Диалоги по стадиям, выдача квеста, благодарность |
| Dou Dzouh | ✅ | Кат-сцена, компаньон, проводник по болоту |
| Торговец (Trader) | ❌ | Определён в `NPCController`, **не активируется**; продажа лута не реализована |
| Волки + меч | ✅ | AI, урон, void-fallback; лут **не попадает в инвентарь** |
| King Hydra Blaster | ✅ | AI, фазы, огонь, HP-bar; убийство ветряком или мечом |
| Ban Hammer | ✅ | Выдача как Tool после кат-сцены |

### Локации и геймплей

| Система | Статус | Примечание |
|---------|--------|------------|
| Болото (`SwampCrossing`) | ✅ | Кочки, туман, провалы, проводник Dou; fallback skip если зоны нет |
| Карта в доме деда | ✅ | `MapPickupSpawner`, ProximityPrompt, инвентарь |
| Инвентарь + UI | ⚠️ | Панель и использование карты; в `ItemConfig` только 3 предмета |
| Лабиринт гробницы | ⚠️ | **Studio-карта**, не процедурный генератор; квест завершается по триггеру зала артефакта |
| Телепорты гробницы | ✅ | `TombTeleporter.server.lua` |
| Ветряк на гидру | ✅ | `TombWindTurbinePuzzle.server.lua` |
| Освещение + голем | ✅ | `TombLighting.lua` (при наличии моделей в Studio) |
| WorldGenerator | ⚠️ | Код есть, **автозапуск отключён** |

### UI, кат-сцены, финал

| Система | Статус | Примечание |
|---------|--------|------------|
| HUD, диалоги, карта, титры, загрузка | ✅ | |
| InventoryUI | ✅ | Минимальная панель |
| CameraAntiPeek | ✅ | Anti wall-peek в лабиринте |
| Кат-сцены (ранняя игра) | ✅ | WOLF_AMBUSH, BAD_NEWS, DOU_DZOUH_REQUEST |
| Кат-сцены финала | ⚠️ | Концовка 1 → титры; концовка 2 → **TODO бой**; диалоги `ENDING_*` не проигрываются автоматически |
| Секретный код SHADOW | ❌ | Remote зарегистрирован, handler и UI **отсутствуют** |
| DebugTools | ✅ (dev) | T/Y/U/G/B/L/K — **удалить перед релизом** |

### Зависимость от Studio-карты

Следующие системы ожидают объекты в Workspace (не создаются кодом при выключенном `WorldGenerator`):

- `Zones/Swamp` — кочки `SwampKochka_N`, туман, `SwampFall`
- `Triggers` — `ForestEntrance_Trigger`, `SwampEntrance_Trigger`, `SwampExit_Trigger`, `TombEntrance_Trigger`, `BanHammer_Trigger` и др.
- `GrandfatherHouse`, `SecretMapSpawn` — дом деда
- `Mazegame.MAZE` — лабиринт гробницы
- `WindTurbine` — головоломка у арены гидры
- NPC-модели в `ServerStorage/Assets` опциональны (`KingHydraBlaster`, `WolfTemplate` и т.д.); JOHN DOU сейчас создаётся кодом без внешней модели.

## Известные пробелы (сверено с кодом)

### Подтверждённые баги

| # | Проблема | Где в коде |
|---|----------|------------|
| 1 | **Квест `KILL_WOLVES` не завершается** — `WolfSpawner` меняет стадию на `JOHN_RESCUE`, но не вызывает `QuestManager:UpdateProgress("KILL","Wolf")`. В UI квеста остаётся 0/8; награды квеста не выдаются | `WolfSpawner.lua:252-258` |
| 2 | **Лут с волков не попадает в инвентарь** — только `WolfKilled` → уведомление на клиенте | `WolfSpawner.lua:219-232` |
| 3 | **Стадия `SECRET_MAP` не выставляется** — обработчик в `setStage` есть, но `setStage("SECRET_MAP")` нигде не вызывается; после карты сразу `FOREST_JOURNEY` | `GameManager.server.lua:699-701`, `78-103` |
| 4 | **Концовка 2 — soft-lock** — кат-сцена `CUTSCENE_BOSS_FIGHT` заканчивается `print("TODO")`, титры не запускаются | `CutsceneManager.lua:498-499` |
| 5 | **Секретный код `SHADOW`** — Remote `SubmitSecretCode` зарегистрирован, но нет handler на сервере и UI на клиенте; `HasSecretCode` только читается, никогда не записывается | `Remotes.lua:74`, `DataManager.lua:56`, `GameManager.server.lua:582-585` |
| 6 | **Диалоги финала не показываются** — `DialogueId` (`ENDING_*`) передаётся в `StartCutscene`, но `CutsceneClient` его не обрабатывает | `CutsceneManager.lua:473-477`, `CutsceneClient.client.lua:175-209` |
| 7 | **Награды с неизвестными предметами** — `HydraScale`, `BanHammer` в `QuestConfig`, но отсутствуют в `ItemConfig` → `DataManager:AddItem` пишет warn и не добавляет | `QuestConfig.lua:202,251`, `ItemConfig.lua`, `DataManager.lua:164-166` |
| 8 | **`TriggersCutscene` в квестах не работает** — только `print`, не вызывает `CutsceneManager` (кат-сцены WOLF_AMBUSH и DOU_DZOUH_REQUEST запускаются из `GameManager` вручную) | `QuestManager.lua:194-197` |
| 9 | **`TombEntrance_Trigger` обновляет `REACH_ZONE "Tomb"`**, а цель `SOLVE_MAZE` — `"ArtifactHall"`. Прогресс лабиринта идёт через `BanHammer_Trigger` | `GameManager.server.lua:415-419`, `276-278`, `QuestConfig.lua:219-222` |

### Не баги / намеренный обход

| Что | Пояснение |
|-----|-----------|
| **`RETURN_TO_VILLAGE` не активен** | Квест в конфиге есть, но не стартует: переход после волков идёт через `SetStage("JOHN_RESCUE")` + диалог `Elder_Thanks` → кат-сцена. Триггер `ReturnToVillage` вызывает `UpdateProgress`, но без активного квеста это no-op. Комментарий в `GameManager.server.lua:756-759` |
| **`RequiredStage` в QuestConfig** | Поле описано в конфиге, но **нигде не проверяется** в `QuestManager` — чисто документация |
| **Инвентарь между сессиями** | Механизм сохранения работает (`Inventory` в DataStore + autosave). Проблема в том, что предметы редко добавляются (кроме `SecretMap`) |

### Не реализовано (не баг, а scope)

- Торговец (`NPCController.lua:8,83-90`) — `InitialDialogue = nil`, `ActivateNPC("Trader")` нигде не вызывается
- Диалог `GRANDFATHER_LETTER` — определён в `DialogueData.lua`, не используется
- `FoundSecrets`, `WolvesKilled`, `CurrentQuestId`, `TotalPlaytime` — поля в DataStore, логики нет
- Сохранение стадии/квеста — каждый заход с `SPAWN` (`GameManager.server.lua:633`)
- `WorldGenerator:GenerateAll()` — отключён (`WorldGenerator.server.lua:1047`)

### Приоритет доработок

1. `WolfSpawner` → `QuestManager:UpdateProgress` (+ лут в инвентарь)
2. Handler `SubmitSecretCode` + UI; запись `HasSecretCode`
3. Концовка 2: бой или переход в `CREDITS`
4. Показ `DialogueId` в кат-сценах финала; `ItemConfig` для всех наград
5. Торговец; сохранение стадии/квеста
6. Отключить `DebugTools` и `DebugMiniBossVerbose` перед релизом

## Архитектура

- **Data-driven** — квесты, диалоги, волки, концовки в `src/shared`.
- **Модульность** — системы в отдельных модулях; координация в `GameManager`.
- **Client / Server** — состояние и прогресс на сервере; UI и камера на клиенте; обмен через `Remotes` → `ReplicatedStorage/GameRemotes`.
- **Прогресс** — в DataStore (`DataManager.lua`: `EndingsCount`, `Money`, `Inventory`, `HasSecretCode` и др.).

Подробное ТЗ и сюжетные детали: [`scenary_classic-game.md`](scenary_classic-game.md).

## Конфигурация мира (StageWorldConfig)

**Главный файл для правок карты и этапов:** [`src/server/StageWorldConfig.lua`](src/server/StageWorldConfig.lua).

**Важно:** конфиг лежит в `ServerScriptService`, не в `ReplicatedStorage`. В `Shared` остались только `Remotes` и `ItemConfig`. Квесты, концовки и все диалоги — на сервере; клиент получает только текущий шаг через Remote.

| Раздел | Что редактировать |
|--------|-------------------|
| `Settings` | WolvesToKill, SecretCode, автосейв |
| `StageOrder` | порядок стадий сюжета |
| `Locations` | границы Min/Max, Spawn, описание каждой локации |
| `NPCs` | позиции и параметры Старейшины, Dou Dzouh, торговца |
| `Stages.*` | квест, триггеры, враги, головоломки **по этапу** |

Примеры:

- **Волки** → `Stages.WOLF_HUNT.Wolves` (координаты `SpawnPoints`, статы, лут)
- **Болото** → `Stages.SWAMP_JOURNEY.Swamp` + `Triggers`
- **Гидра и ветряк** → `Stages.MINI_BOSS.MiniBoss` / `.WindTurbine`
- **Гробница** → `Locations.TombLabyrinth` (телепорты, границы)
- **Карта деда** → `Stages.BAD_NEWS.MapPickup`

`GameConfig`, `WorldMap`, `WolfConfig`, `SwampConfig` — серверные фасады в `src/server/`; клиент их не загружает.
