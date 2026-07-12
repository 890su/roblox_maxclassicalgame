--[[
    WolfSpawner — Спавн, AI и уничтожение волков
    ═══════════════════════════════════════════════════════════
    
    Отвечает за ПОЛНЫЙ жизненный цикл волков:
    • Создание моделей из Part-ов (тело, голова, ноги, хвост, глаза)
    • Простой AI (патруль → обнаружение → погоня → атака)
    • Отслеживание убийств и отображение прогресса
    • Генерация лута при смерти
    • Защита от edge cases (падение в пропасть, двойной подсчёт)
    
    ВАЖНО: Это ModuleScript (.lua), вызывается из GameManager.
    
    ПОТОК ЖИЗНИ ВОЛКА:
    ──────────────────
    SpawnWolves() создаёт волков → wolfAI() управляет поведением
    → Игрок убивает волка → humanoid.Died → onWolfDied()
    → Считаем убийство, генерируем лут, обновляем HUD
    → Если все убиты → _G.GameManager.SetStage("JOHN_RESCUE")
    
    АРХИТЕКТУРА МОДЕЛИ ВОЛКА:
    ────────────────────────
    Model "Wolf_1"
    ├── HumanoidRootPart (тело, PrimaryPart для MoveTo)
    ├── Head
    ├── LeftEye / RightEye (Neon, светятся в темноте)
    ├── Leg1..Leg4 (привариваются WeldConstraint к телу)
    ├── Tail
    └── Humanoid (HP, скорость, AI управление через MoveTo)
    
    AI СХЕМА:
    ─────────
    Каждые 0.3 сек проверяем расстояние до игрока:
    • > DetectionRange (50)  → бродим рандомно (WalkSpeed = 10)
    • < DetectionRange (50)  → бежим к игроку (RunSpeed = 18)
    • < AttackRange (5)      → наносим урон (10) с кулдауном 1 сек
    
    БАГИ КОТОРЫЕ БЫЛИ ИСПРАВЛЕНЫ:
    ─────────────────────────────
    1. Двойной подсчёт убийств → Attribute "Counted" + флаг
    2. Волк падает в пропасть (Y < -50) → monitorWolfVoid считает как убийство
    3. HUD не обновлялся → добавлен UpdateHUD при каждом kill
    4. Волки бегали задом наперёд → модель была ориентирована головой в +Z,
       а в Roblox «вперёд» это -Z. Исправлено: голова/глаза теперь в -Z,
       хвост в +Z, ноги переставлены.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ServerScriptService = game:GetService("ServerScriptService")
local WolfConfig = require(ServerScriptService:WaitForChild("WolfConfig"))
local GameConfig = require(ServerScriptService:WaitForChild("GameConfig"))
local StageWorldConfig = require(ServerScriptService:WaitForChild("StageWorldConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local WolfSpawner = {}

-- ═══════════════════════════════════════════════════════════
-- ХРАНИЛИЩЕ АКТИВНЫХ ВОЛКОВ
-- Для каждого игрока: массив волков, счётчик убийств, общее количество.
-- Формат: activeWolves[Player] = { wolves = {Model}, killCount, totalCount }
-- ═══════════════════════════════════════════════════════════
local activeWolves = {}

-- Единая точка применения статов из WolfConfig (шаблон Studio и fallback-модель).
local function applyWolfStats(humanoid)
    if not humanoid then
        return
    end
    humanoid.MaxHealth = WolfConfig.Stats.Health
    humanoid.Health = WolfConfig.Stats.Health
    humanoid.WalkSpeed = WolfConfig.Stats.WalkSpeed
end

-- WolfTemplate из Studio может содержать свои Script/LocalScript и Humanoid с жёсткими статами.
local function prepareWolfModel(wolfModel)
    for _, desc in ipairs(wolfModel:GetDescendants()) do
        if desc:IsA("Script") or desc:IsA("LocalScript") then
            desc:Destroy()
        end
    end
    applyWolfStats(wolfModel:FindFirstChildOfClass("Humanoid"))
end

-- ═══════════════════════════════════════════════════════════
-- СОЗДАНИЕ МОДЕЛИ ВОЛКА
-- Строит волка из Part-ов. Все части привариваются к телу (HumanoidRootPart)
-- через WeldConstraint, чтобы двигались вместе.
--
-- Параметр: position (Vector3) — мировая позиция для спавна
-- Возвращает: Model с Humanoid внутри
-- ═══════════════════════════════════════════════════════════
local function createWolfModel(position)
    local assetsFolder = ServerStorage:FindFirstChild("Assets")
    local template = assetsFolder and assetsFolder:FindFirstChild("WolfTemplate")

    if template then
        local wolfModel = template:Clone()
        wolfModel.Name = "Wolf"

        local rootPart = wolfModel:FindFirstChild("HumanoidRootPart") or wolfModel.PrimaryPart
        if rootPart then
            wolfModel:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
        end

        prepareWolfModel(wolfModel)
        return wolfModel
    end

    -- Fallback: создаём простую модель из Part-ов если шаблона нет
    local config = WolfConfig.Model

    local wolfModel = Instance.new("Model")
    wolfModel.Name = "Wolf"

    local body = Instance.new("Part")
    body.Name = "HumanoidRootPart"
    body.Size = config.BodySize
    body.Color = config.BodyColor
    body.Position = position + Vector3.new(0, config.BodySize.Y / 2 + 1, 0)
    body.Anchored = false
    body.CanCollide = true
    body.Parent = wolfModel

    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = config.HeadSize
    head.Color = config.BodyColor
    head.Anchored = false
    head.CanCollide = false
    head.Parent = wolfModel
    head.CFrame = body.CFrame * CFrame.new(0, 0.3, -(config.BodySize.Z / 2 + config.HeadSize.Z / 2 - 0.5))

    local headWeld = Instance.new("WeldConstraint")
    headWeld.Part0 = body
    headWeld.Part1 = head
    headWeld.Parent = head

    wolfModel.PrimaryPart = body

    local humanoid = Instance.new("Humanoid")
    humanoid.HipHeight = 1
    humanoid.Parent = wolfModel
    applyWolfStats(humanoid)

    return wolfModel
end

-- ═══════════════════════════════════════════════════════════
-- AI ВОЛКА
-- Простой поведенческий цикл, работающий в отдельном потоке (task.spawn).
-- Проверяет расстояние до игрока и решает: бродить, бежать или атаковать.
--
-- Параметры:
--   wolf (Model)   — модель волка
--   player (Player) — целевой игрок
-- ═══════════════════════════════════════════════════════════
local function wolfAI(wolf, player)
    local humanoid = wolf:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    task.spawn(function()
        task.wait(1) -- даём волку «встать на ноги»

        -- Цикл AI: работает пока волк жив
        while humanoid and humanoid.Parent and humanoid.Health > 0 do
            local rootPart = wolf:FindFirstChild("HumanoidRootPart")
            if not rootPart then break end

            local character = player.Character
            if character and character:FindFirstChild("HumanoidRootPart") then
                local distance = (rootPart.Position - character.HumanoidRootPart.Position).Magnitude

                if distance <= WolfConfig.Stats.DetectionRange then
                    -- РЕЖИМ ПОГОНИ: волк обнаружил игрока
                    humanoid.WalkSpeed = WolfConfig.Stats.RunSpeed   -- ускоряемся (18)
                    humanoid:MoveTo(character.HumanoidRootPart.Position)

                    if distance <= WolfConfig.Stats.AttackRange then
                        -- РЕЖИМ АТАКИ: достаточно близко для удара
                        local targetHumanoid = character:FindFirstChildOfClass("Humanoid")
                        if targetHumanoid and targetHumanoid.Health > 0 then
                            targetHumanoid:TakeDamage(WolfConfig.Stats.Damage) -- 10 урона
                        end
                        task.wait(WolfConfig.Stats.AttackCooldown) -- 1 сек кулдаун
                    end
                else
                    -- РЕЖИМ ПАТРУЛЯ: бродим рандомно
                    humanoid.WalkSpeed = WolfConfig.Stats.WalkSpeed -- нормальная скорость (10)
                    local randomOffset = Vector3.new(
                        math.random(-15, 15), 0, math.random(-15, 15)
                    )
                    humanoid:MoveTo(rootPart.Position + randomOffset)
                    task.wait(math.random(2, 4)) -- ждём 2-4 секунды перед следующим шагом
                end
            else
                task.wait(1) -- игрок мёртв/отсутствует — ждём
            end
            task.wait(0.3) -- базовый интервал проверки AI
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
-- ОБРАБОТКА СМЕРТИ ВОЛКА
-- Вызывается при: humanoid.Died или падении в пропасть.
-- Считает убийство, генерирует лут, обновляет HUD.
-- Если все волки убиты → переход к стадии JOHN_RESCUE.
--
-- ЗАЩИТА ОТ ДВОЙНОГО ПОДСЧЁТА:
-- Attribute "Counted" устанавливается один раз. Повторный вызов игнорируется.
-- ═══════════════════════════════════════════════════════════
local function onWolfDied(wolf, player, data)
    -- Защита от двойного срабатывания (Died + monitorVoid могут оба сработать)
    if wolf:GetAttribute("Counted") then return end
    wolf:SetAttribute("Counted", true)

    -- Генерируем лут: для каждого предмета бросаем «монетку» (DropChance)
    local droppedLoot = {}
    for _, lootEntry in ipairs(WolfConfig.LootTable) do
        if math.random() <= lootEntry.DropChance then
            table.insert(droppedLoot, {
                ItemId = lootEntry.ItemId,
                Name = lootEntry.Name,
                SellPrice = lootEntry.SellPrice,
            })
        end
    end

    -- Оповещаем клиент: показать лут на экране
    Remotes:GetEvent("WolfKilled"):FireClient(player, droppedLoot)

    -- Обновляем счётчик убийств
    data.killCount = data.killCount + 1
    local remaining = data.totalCount - data.killCount

    print("[WolfSpawner] Волков убито:", data.killCount, "/", data.totalCount, "| Осталось:", remaining)

    -- HUD: показываем прогресс «Волков убито: X/Y»
    Remotes:GetEvent("UpdateHUD"):FireClient(player, {
        Notification = string.format("🐺 Волков убито: %d/%d", data.killCount, data.totalCount)
    })

    -- Удаляем модель волка через 3 секунды (чтобы лут успел показаться)
    task.delay(3, function()
        if wolf and wolf.Parent then
            wolf:Destroy()
        end
    end)

    -- Проверяем: все ли волки убиты?
    if data.killCount >= data.totalCount then
        print("[WolfSpawner] ВСЕ ВОЛКИ УБИТЫ!")
        task.wait(1) -- небольшая пауза для эффекта
        if _G.GameManager then
            _G.GameManager.SetStage(player, "JOHN_RESCUE")
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- МОНИТОРИНГ: ВОЛК УПАЛ В ПРОПАСТЬ?
-- Каждые 2 секунды проверяем позицию Y волка.
-- Если Y < -50 → волк упал за карту → считаем убитым.
-- Это edge case: физика Roblox может столкнуть волка за край.
-- ═══════════════════════════════════════════════════════════
local function monitorWolfVoid(wolf, player, data)
    task.spawn(function()
        while wolf and wolf.Parent do
            local root = wolf:FindFirstChild("HumanoidRootPart")
            if root and root.Position.Y < (WolfConfig.VoidKillY or -500) then
                print("[WolfSpawner] Волк", wolf.Name, "упал в пропасть! Считаем убитым.")
                local humanoid = wolf:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    humanoid.Health = 0  -- убиваем (вызовет Died)
                end
                -- На случай если Died не сработал — вызываем напрямую
                onWolfDied(wolf, player, data)
                task.delay(0.5, function()
                    if wolf and wolf.Parent then
                        wolf:Destroy()
                    end
                end)
                return  -- выходим из цикла мониторинга
            end
            task.wait(2) -- проверяем каждые 2 секунды
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
-- СПАВН ВОЛКОВ ДЛЯ ИГРОКА
-- Вызывается из GameManager при переходе к стадии WOLF_HUNT
-- и при респавне игрока (если стадия уже WOLF_HUNT).
--
-- Алгоритм:
-- 1. Очищаем старых волков (если были)
-- 2. Определяем центр зоны спавна из GameConfig
-- 3. Создаём каждого волка на позиции: zoneCenter + spawnOffset
-- 4. Подключаем AI, обработчик смерти и мониторинг пропасти
-- ═══════════════════════════════════════════════════════════
function WolfSpawner:SpawnWolves(player)
    print("[WolfSpawner] Спавн волков для", player.Name)

    -- Удаляем старых волков (если игрок респавнился)
    self:ClearWolves(player)

    -- Точки спавна — из StageWorldConfig (этап WOLF_HUNT)
    local spawnPositions = StageWorldConfig.GetWolfSpawnPoints()
    if #spawnPositions == 0 then
        local zoneName = WolfConfig.SpawnZone or "Outskirts"
        local zoneConfig = GameConfig.Zones[zoneName]
        local zoneCenter = zoneConfig and zoneConfig.SpawnPoint or Vector3.new(-1096.38, -206.234, -45.12)
        for _, spawnOffset in ipairs(WolfConfig.SpawnPoints or {}) do
            table.insert(spawnPositions, zoneCenter + spawnOffset)
        end
    end
    print("[WolfSpawner] Зона:", WolfConfig.SpawnZone or "Outskirts", "| точек:", #spawnPositions)

    -- Папка Wolves: убираем и карту из Studio, и старый спавн — иначе остаются волки без WolfConfig.
    local wolvesFolder = Workspace:FindFirstChild("Wolves")
    if wolvesFolder then
        wolvesFolder:ClearAllChildren()
    else
        wolvesFolder = Instance.new("Folder")
        wolvesFolder.Name = "Wolves"
        wolvesFolder.Parent = Workspace
    end

    -- Данные отслеживания: счётчик убийств и массив волков
    local data = {
        wolves = {},
        killCount = 0,
        totalCount = WolfConfig.Count or #spawnPositions,
    }

    -- Создаём волка на каждой точке спавна
    for i, absolutePos in ipairs(spawnPositions) do
        local wolf = createWolfModel(absolutePos)
        wolf.Name = "Wolf_" .. i
        wolf.Parent = wolvesFolder

        -- Подключаем обработчик смерти
        local humanoid = wolf:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.Died:Connect(function()
                onWolfDied(wolf, player, data)
            end)
        end

        -- Запускаем мониторинг пропасти
        monitorWolfVoid(wolf, player, data)

        -- Запускаем AI
        wolfAI(wolf, player)
        table.insert(data.wolves, wolf)
    end

    -- Сохраняем данные для этого игрока
    activeWolves[player] = data
    print(
        "[WolfSpawner] Заспавнено волков:", data.totalCount,
        "| damage:", WolfConfig.Stats.Damage,
        "| walk:", WolfConfig.Stats.WalkSpeed,
        "| run:", WolfConfig.Stats.RunSpeed
    )

    -- Показываем начальный прогресс в HUD
    Remotes:GetEvent("UpdateHUD"):FireClient(player, {
        Notification = string.format("🐺 Убей всех волков! (0/%d)", data.totalCount)
    })
end

-- ═══════════════════════════════════════════════════════════
-- ОЧИСТКА ВОЛКОВ
-- Уничтожает всех волков игрока и очищает данные.
-- Вызывается при респавне, смене стадии или выходе игрока.
-- ═══════════════════════════════════════════════════════════
function WolfSpawner:ClearWolves(player)
    local data = activeWolves[player]
    if data then
        for _, wolf in ipairs(data.wolves) do
            if wolf and wolf.Parent then
                wolf:Destroy()
            end
        end
        activeWolves[player] = nil
    end
end

return WolfSpawner
