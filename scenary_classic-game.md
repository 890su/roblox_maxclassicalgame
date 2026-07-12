# Техническое задание: проект «Тень Молота» (Roblox)

**Жанр:** Однопользовательская RPG / Adventure.

**Сеттинг:** Деревня, окрестности, лес, болото, гробница / лабиринт, зал артефакта.

**Ключевая особенность:** Прогрессирующая сюжетная петля с тремя концовками.

**Репозиторий:** исходники синхронизируются с Roblox Studio через [Rojo](https://rojo.space/); дерево инстансов — `default.project.json`, код — `src/`.

---

## 1. Игра в одном абзаце

Игрок попадает в мир, где таинственный помощник **Dou Dzouh** сопровождает его к артефакту — Ban Hammer. В зависимости от предыдущих прохождений Dou Dzouh либо предаёт игрока, либо сталкивается с сопротивлением героя, либо ускользает вместе с истинным злом, оставляя мир под угрозой.

---

## 2. Основная сюжетная линия

### Шаг 1 — Появление в деревне

Игрок появляется в деревне. Первый контакт — **Старейшина**: задание избавиться от волков в округе, выдача стартового меча.

**Реализация:** ✅ диалог Elder, `WeaponManager:GiveStarterSword`, квест `KILL_WOLVES`.

### Шаг 2 — Охота на волков

Игрок убивает 8 волков в окрестностях.

**Реализация:** ✅ AI волков (`WolfSpawner`), уведомления о прогрессе в HUD. ⚠️ Квест `KILL_WOLVES` не обновляется через `QuestManager` — стадия переключается напрямую. ❌ Лут не добавляется в инвентарь; торговец не реализован.

### Шаг 3 — Спасение и знакомство с Dou Dzouh

Когда волки убиты, игрок возвращается к деревне. Кат-сцена: волк нападает сзади, героя спасает **Dou Dzouh**. Знакомство и разговор об угрозе.

**Реализация:** ✅ кат-сцена `WOLF_AMBUSH` (`CutsceneManager`), диалог `DOU_DZOUH_INTRO`, переход в `BAD_NEWS`.

### Шаг 4 — Плохие новости

Старейшина сообщает о смерти деда. Игрок направляется в дом деда.

> **Секрет 3-й концовки:** деда убил Dou Dzouh. Это раскрывается в третьей концовке.

**Реализация:** ✅ кат-сцена `BAD_NEWS`, квест `FIND_MAP`. ⚠️ Отдельный диалог `GRANDFATHER_LETTER` в `DialogueData` не показывается.

### Шаг 5 — Тайная карта

В доме деда — физический пикап карты. Игрок смотрит карту (клиентский UI `MapViewer`).

**Реализация:** ✅ `MapPickupSpawner`, `InventoryUI`, `ShowMap`. ⚠️ Стадия `SECRET_MAP` в коде не выставляется — после подбора карты переход сразу в `FOREST_JOURNEY`.

### Шаг 6 — Путь через лес

Dou Dzouh сопровождает игрока через лес к болоту.

**Реализация:** ✅ компаньон (`NPCController:SetCompanion`), триггер `ForestEntrance_Trigger`, квест `TRAVERSE_FOREST`. ❌ Ловушки в лесу не реализованы.

### Шаг 7 — Ядовитое болото

Dou Dzouh ведёт по кочкам через ядовитый туман к руинам гидры. Без проводника туман наносит урон; провал — respawn на checkpoint.

**Реализация:** ✅ `SwampCrossing.lua`, `SwampConfig.lua`, квест `CROSS_SWAMP`. Требует Studio-ассеты: `Zones/Swamp`, `SwampKochka_1…N`, туман, триггеры.

### Шаг 8 — Мини-босс и лабиринт

Перед входом в гробницу — арена **King Hydra Blaster**. Головоломка с ветряком: толкнуть основание → ветряк падает на гидру. Альтернатива — прямой бой мечом.

Внутри гробницы — **лабиринт из Studio-карты** (`Mazegame.MAZE`), телепорты (`TombTeleporter`), освещение и голем (`TombLighting`).

**Реализация:** ✅ мини-босс (`MiniBossSpawner`), ветряк (`TombWindTurbinePuzzle`), телепорты, фонарь/голем. ⚠️ Процедурный генератор лабиринта (`WorldGenerator`) отключён; квест `SOLVE_MAZE` завершается по триггеру зала артефакта, а не по прохождению всего MAZE.

### Шаг 9 — Ban Hammer

В зале артефакта игрок находит **Ban Hammer**. Dou Dzouh просит передать молот ему (кат-сцена `DOU_DZOUH_REQUEST`).

**Реализация:** ✅ кат-сцена, телепорт, выдача Tool (`WeaponManager`), квест `GET_BAN_HAMMER`.

### Шаг 10 — Финал и титры

Финальная кат-сцена (зависит от концовки), затем титры и учёт `EndingsCount`.

**Реализация:** ⚠️ см. раздел «Концовки» ниже.

---

## 3. Сюжетная структура и концовки

| Финал | Название | Условие открытия | Сюжетный исход | Статус |
|--------|-----------|------------------|----------------|--------|
| №1 | Цена доверия | Первое прохождение | Dou Dzouh предаёт, забирает Ban Hammer | ✅ Кат-сцена → титры |
| №2 | Прозрение | Пройдена концовка №1 | Герой даёт отпор, сражение с антагонистом | ⚠️ Кат-сцена есть; **бой TODO** |
| №3 | Ускользающее зло | Пройдена №2 + код **`SHADOW`** | Раскрывается правда об убийстве деда | ⚠️ Выбор концовки есть; **ввод кода не реализован** |

Логика выбора: `EndingConfig.lua` (`EndingsCount`, `HasSecretCode`). Счётчик увеличивается при стадии `CREDITS` (`GameManager`).

---

## 4. Ключевые персонажи

### NPC: Старейшина

- В деревне; выдаёт стартовый квест и позже — новости о деде.
- **Статус:** ✅ полностью (`NPCController`, диалоги по стадиям).

### NPC: Dou Dzouh (помощник / предатель)

- Появляется после охоты на волков (кат-сцена спасения).
- Сопровождает через лес и болото к гробнице; в финале просит Ban Hammer.
- В коде: id `DouDzouh`; отображаемое имя — **`JOHN DOU`**. Внешняя модель не обязательна: если `ModelName = nil`, NPC создаётся кодом.
- **Статус:** ✅ сюжет, компаньон, проводник по болоту.

### NPC: Торговец

- По ТЗ: скупка лута, снаряжение за монеты.
- **Статус:** ❌ заглушка в `NPCController` — не активируется, диалогов нет.

---

## 5. Механика кат-сцен

- Клиент: камера, затемнение, блокировка управления — `CutsceneClient.client.lua`.
- Сервер: NPC, спавн волка, перемещения — `CutsceneManager.lua`.
- Обмен через `Remotes` (`StartCutscene`, `CutsceneFinished`).

| Кат-сцена | Статус |
|-----------|--------|
| WOLF_AMBUSH | ✅ |
| BAD_NEWS | ✅ (камера; диалог внутри кат-сцены не автоматический) |
| DOU_DZOUH_REQUEST | ✅ |
| CUTSCENE_BETRAYAL (концовка 1) | ✅ |
| CUTSCENE_BOSS_FIGHT (концовка 2) | ⚠️ OnComplete → TODO бой |
| CUTSCENE_ESCAPE (концовка 3) | ✅ → титры |

Действия диалогов (`START_BOSS_FIGHT`, `TAKE_HAMMER`, `KILL_PLAYER`) на сервере **не обрабатываются**.

---

## 6. Техническая архитектура

### Сохранения (DataStore)

Реализация: `src/server/DataManager.lua`, хранилище `ShadowOfHammer_PlayerData_v1`.

| Поле | Используется |
|------|--------------|
| `Money` | ✅ leaderstats, награды квестов |
| `EndingsCount` | ✅ выбор концовки, титры |
| `Inventory` | ⚠️ сохраняется; пополняется в основном картой |
| `HasSecretCode` | ⚠️ читается при старте; запись не реализована |
| `FoundSecrets` | ❌ не используется |
| `CurrentQuestId` | ❌ не сохраняется/не восстанавливается |
| `WolvesKilled` | ❌ не используется |
| `TotalPlaytime` | ❌ не используется |

Стадия сюжета и активный квест **не персистятся** — каждый заход начинается с `SPAWN`.

### Карта проекта (Rojo)

| Папка в репозитории | Сервис / путь в DataModel |
|---------------------|---------------------------|
| `src/server` | `ServerScriptService` |
| `src/client` | `StarterPlayer.StarterPlayerScripts` |
| `src/character` | `StarterPlayer.StarterCharacterScripts` |
| `src/gui` | `StarterGui` |
| `src/loading` | `ReplicatedFirst` |
| `src/shared` | `ReplicatedStorage.Shared` |
| `src/assets` | `ServerStorage.Assets` |

**Точка входа сервера:** `GameManager.server.lua` — инициализирует `Remotes`, подключает модули (`DataManager`, `QuestManager`, `CutsceneManager`, `NPCController`, `WolfSpawner`, `WeaponManager`, `MiniBossSpawner`, `SwampCrossing`, `MapPickupSpawner`, `TombLighting`).

**Отдельные серверные скрипты** (не только `require` из GameManager): `WorldGenerator.server.lua` (автовызов `GenerateAll()` **отключён**), `TombTeleporter.server.lua`, `TombWindTurbinePuzzle.server.lua`.

**Клиент:** HUD, диалоги, карта, инвентарь, титры, кат-сцены; `CameraAntiPeek`, `DebugTools` (удалить перед релизом).

**Общие модули:** `GameConfig`, `QuestConfig`, `DialogueData`, `ItemConfig`, `SwampConfig`, `WolfConfig`, `EndingConfig`, `WorldMap`, `Remotes`.

**Сетевой слой:** после `Remotes:Init()` события лежат в `ReplicatedStorage/GameRemotes`.

Полная структура файлов, статус систем и команды сборки — в [`README.md`](README.md).

---

## 7. Геймплейный цикл (актуальный)

1. Деревня — квест у Старейшины, меч.  
2. Окрестности — 8 волков.  
3. Возвращение — кат-сцена с Dou Dzouh, плохие новости.  
4. Дом деда — карта в инвентарь.  
5. Лес — сопровождение Dou Dzouh.  
6. Болото — кочки, ядовитый туман, руины гидры.  
7. Арена — King Hydra Blaster (ветряк или бой).  
8. Лабиринт гробницы — телепорты, фонарь, голем.  
9. Зал артефакта — Ban Hammer.  
10. Финал — одна из трёх концовок.  
11. Титры.

### Стадии (`GameConfig.GameStages`)

`SPAWN` → `WOLF_HUNT` → `JOHN_RESCUE` → `BAD_NEWS` → `SECRET_MAP` → `FOREST_JOURNEY` → `SWAMP_JOURNEY` → `MINI_BOSS` → `TOMB_MAZE` → `BAN_HAMMER` → `FINALE` → `CREDITS`

### Квесты (`QuestConfig.QuestOrder`)

`KILL_WOLVES` → `RETURN_TO_VILLAGE` → `FIND_MAP` → `TRAVERSE_FOREST` → `CROSS_SWAMP` → `DEFEAT_MINI_BOSS` → `SOLVE_MAZE` → `GET_BAN_HAMMER`

---

## 8. Карта: Studio vs код

**Production-путь:** карта собрана в Roblox Studio, синхронизация через Rojo. Координаты зон в `GameConfig.Zones` и справочник `WorldMap.lua` могут расходиться — ориентир для триггеров и спавна: фактические позиции в Studio.

**WorldGenerator:** полный процедурный мир (деревня, лес, гробница, лабиринт) — код сохранён, но `GenerateAll()` закомментирован в конце `WorldGenerator.server.lua`.

**Обязательные объекты Studio** (при выключенном генераторе):

| Объект | Назначение |
|--------|------------|
| `Zones/Swamp`, `SwampKochka_N` | Болото |
| `GrandfatherHouse`, `SecretMapSpawn` | Квест карты |
| `Triggers/*` | Переходы между зонами |
| `Mazegame.MAZE` | Лабиринт |
| `WindTurbine` | Головоломка у гидры |
| Модели в `ServerStorage/Assets` | NPC, волки, босс |

---

## 9. Оценка рисков

| За | Против |
|----|--------|
| Сюжет с твистом и повторным прохождением | Сложность синхронизации NPC и камеры в кат-сценах |
| Понятная прогрессия и флаги концовок | Лимиты и отказы DataStore при частых сохранениях |
| Data-driven конфиги | Объём контента для трёх веток финала |
| Рабочий прототип полного прохождения | Разрывы квест/стадия, незавершённые концовки 2–3 |

---

## 10. Сверка багов с кодом (актуально)

### Подтверждено в исходниках

| Проблема | Статус | Файлы |
|----------|--------|-------|
| Квест `KILL_WOLVES` не обновляется при убийстве волка | **Баг** | `WolfSpawner.lua:252-258` — только `SetStage("JOHN_RESCUE")` |
| Лут волков не в инвентарь | **Баг** | `WolfSpawner.lua:219-232` — `FireClient`, без `AddItem` |
| Стадия `SECRET_MAP` не выставляется | **Баг** | handler есть (`GameManager:699`), вызова `setStage` нет |
| Концовка 2 без титров/боя | **Баг (soft-lock)** | `CutsceneManager.lua:498-499` — `TODO: Начать бой` |
| Код `SHADOW` | **Не реализовано** | `SubmitSecretCode` без handler; `HasSecretCode` не пишется |
| Диалоги `ENDING_*` в финале | **Баг** | `DialogueId` в `StartCutscene`, `CutsceneClient` игнорирует |
| `HydraScale` / `BanHammer` в наградах | **Баг** | нет в `ItemConfig` → `AddItem` fail |
| `TriggersCutscene` в квестах | **Баг** | `QuestManager.lua:195` — TODO print |
| `TombEntrance` vs `ArtifactHall` | **Minor** | триггер Tomb не закрывает `SOLVE_MAZE`; работает `BanHammer_Trigger` |

### Не баг / by design

| Пункт | Пояснение |
|-------|-----------|
| `RETURN_TO_VILLAGE` | Обход через стадию + `Elder_Thanks`; квест намеренно не в `stageMap` |
| `RequiredStage` | Не проверяется в `QuestManager` |
| Happy path до титров | Работает при Studio-карте и триггерах |

### Бэклог (по приоритету)

1. Синхронизация `WolfSpawner` с `QuestManager` + лут в инвентарь.
2. UI и handler для секретного кода `SHADOW`.
3. Концовка 2: бой или переход в `CREDITS` (сейчас soft-lock).
4. `DialogueId` в кат-сценах; `ItemConfig` для всех наград.
5. Торговец; сохранение стадии/квеста.
6. Отключение `DebugTools` и verbose-логов перед релизом.
