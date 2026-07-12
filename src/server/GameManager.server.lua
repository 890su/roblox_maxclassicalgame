--[[
    GameManager — Центральный координатор игры
    ═══════════════════════════════════════════════════════════
    
    Это ГЛАВНЫЙ СЕРВЕРНЫЙ СКРИПТ (.server.lua) — запускается
    автоматически при старте сервера. Он координирует ВСЮ игру:
    
    • Инициализирует все модули (Remotes, DataManager, etc.)
    • Управляет стадиями игры (SPAWN → WOLF_HUNT → ... → CREDITS)
    • Обрабатывает завершение диалогов (какой NPC → что делать)
    • Реагирует на завершение квестов (переход к следующей стадии)
    • Управляет подключением/отключением игроков
    
    ПОТОК ИГРЫ:
    ──────────
    SPAWN → Говорим со Старейшиной → получаем меч
    → WOLF_HUNT → убиваем 8 волков
    → JOHN_RESCUE → возвращаемся к Старейшине → благодарность
    → Кат-сцена (волк нападает, JOHN DOU спасает)
    → Разговор с JOHN DOU
    → BAD_NEWS → узнаём о смерти деда → ...
    → SECRET_MAP → FOREST_JOURNEY → SWAMP_JOURNEY → MINI_BOSS (King Hydra Blaster)
    → TOMB_MAZE → BAN_HAMMER → FINALE → одна из 3 концовок → CREDITS
    
    СВЯЗЬ С ДРУГИМИ МОДУЛЯМИ:
    ────────────────────────
    GameManager вызывает:
      • WolfSpawner:SpawnWolves() — спавн волков
      • MiniBossSpawner:Spawn() — спавн King Hydra Blaster
      • CutsceneManager:PlayCutscene() — запуск кат-сцен
      • NPCController:ActivateNPC() — активация NPC
      • WeaponManager:GiveStarterSword() — выдача оружия
      • QuestManager:StartQuest() — запуск квестов
    
    GameManager слушает:
      • DialogueChoice (RemoteEvent) — завершение диалогов
      • QuestCompleted (через _G) — завершение квестов
      • PlayerAdded/Removing — подключение/отключение игроков
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Загружаем общие модули из ReplicatedStorage
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(ServerScriptService:WaitForChild("GameConfig"))
local EndingConfig = require(ServerScriptService:WaitForChild("EndingConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WorldMap = require(ServerScriptService:WaitForChild("WorldMap"))
local StageWorldConfig = require(ServerScriptService:WaitForChild("StageWorldConfig"))
local DialogueData = require(ServerScriptService:WaitForChild("DialogueData"))

-- Серверные модули (загружаются позже в init(), после Remotes:Init())
local DataManager
local QuestManager
local CutsceneManager
local NPCController
local WolfSpawner
local WeaponManager
local MiniBossSpawner
local TombLighting
local MapPickupSpawner
local SwampCrossing

-- ═══════════════════════════════════════════════════════════
-- СОСТОЯНИЕ ИГРОКОВ
-- Для каждого подключённого игрока хранится:
--   Stage          — текущая стадия сюжета ("SPAWN", "WOLF_HUNT" и т.д.)
--   Data           — сохраняемые данные игрока (из DataManager)
--   CurrentEnding  — какая концовка будет в этом прохождении
--   CutscenePlayed — был ли уже показан WOLF_AMBUSH (защита от повтора)
-- ═══════════════════════════════════════════════════════════
local playerStates = {} -- [Player] = { Stage, Data, CurrentEnding, CutscenePlayed }
local debugZoneCycleIndex = {} -- [Player] = number (DebugTools CycleZone)

-- Ожидание награды после кат-сцены DOU_DZOUH_REQUEST (телепорт + молот + квест)
local hammerCutsceneWaitsReward = {} -- [Player] = true

local function getCharacterRoot(player: Player): BasePart?
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local VILLAGE_GATE_NAMES = {
    VillageGate = true,
    SwampGate = true,
    GateToSwamp = true,
    ForestGate = true,
}

local function openVillageGates()
    local opened = 0
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if VILLAGE_GATE_NAMES[inst.Name] then
            if inst:IsA("BasePart") then
                inst.CanCollide = false
                inst.Transparency = math.max(inst.Transparency, 0.75)
                opened = opened + 1
            elseif inst:IsA("Model") or inst:IsA("Folder") then
                for _, desc in ipairs(inst:GetDescendants()) do
                    if desc:IsA("BasePart") then
                        desc.CanCollide = false
                        desc.Transparency = math.max(desc.Transparency, 0.75)
                        opened = opened + 1
                    end
                end
            end
        end
    end

    if opened > 0 then
        print("[GameManager] Открыты ворота к болоту | частей:", opened)
    end
end

local function handleMapPickupCollected(triggerPlayer: Player)
    local triggerState = playerStates[triggerPlayer]
    local activeQ = QuestManager:GetActiveQuest(triggerPlayer)
    print("[GameManager] Карта подобрана | Игрок:", triggerPlayer.Name,
        "| Стадия:", triggerState and triggerState.Stage or "nil",
        "| Активный квест:", activeQ and activeQ.QuestId or "нет")

    if DataManager:AddItem(triggerPlayer, "SecretMap") then
        Remotes:GetEvent("UpdateHUD"):FireClient(triggerPlayer, {
            Notification = "🗺 Карта деда добавлена в инвентарь",
        })
    end
    Remotes:GetEvent("ShowMap"):FireClient(triggerPlayer)
    openVillageGates()

    QuestManager:UpdateProgress(triggerPlayer, "INTERACT", "GrandfatherHouse")
    QuestManager:UpdateProgress(triggerPlayer, "INTERACT", "SecretLetter")

    MapPickupSpawner:RemovePickup()

    local stateAfter = playerStates[triggerPlayer]
    if stateAfter and stateAfter.Stage ~= "FOREST_JOURNEY" and stateAfter.Stage ~= "SWAMP_JOURNEY"
        and stateAfter.Stage ~= "MINI_BOSS" and stateAfter.Stage ~= "TOMB_MAZE"
        and stateAfter.Stage ~= "BAN_HAMMER" and stateAfter.Stage ~= "FINALE" then
        print("[GameManager] FIND_MAP не завершился через квест → принудительный переход в FOREST_JOURNEY")
        setStage(triggerPlayer, "FOREST_JOURNEY")
    end
end

-- ═══════════════════════════════════════════════════════════
-- ИНИЦИАЛИЗАЦИЯ
-- Запускается один раз при старте сервера.
-- Порядок важен: сначала Remotes (создаёт RemoteEvent),
-- затем остальные модули (они используют Remotes).
-- ═══════════════════════════════════════════════════════════
local function init()
    print("[GameManager] Инициализация...")

    -- 1. Создаём все RemoteEvent и RemoteFunction
    Remotes:Init()

    -- 2. Загружаем серверные модули через require()
    -- WaitForChild нужен, потому что Roblox загружает скрипты асинхронно
    DataManager = require(ServerScriptService:WaitForChild("DataManager"))
    QuestManager = require(ServerScriptService:WaitForChild("QuestManager"))
    CutsceneManager = require(ServerScriptService:WaitForChild("CutsceneManager"))
    NPCController = require(ServerScriptService:WaitForChild("NPCController"))
    WolfSpawner = require(ServerScriptService:WaitForChild("WolfSpawner"))
    WeaponManager = require(ServerScriptService:WaitForChild("WeaponManager"))
    MiniBossSpawner = require(ServerScriptService:WaitForChild("MiniBossSpawner"))
    TombLighting = require(ServerScriptService:WaitForChild("TombLighting"))
    MapPickupSpawner = require(ServerScriptService:WaitForChild("MapPickupSpawner"))
    SwampCrossing = require(ServerScriptService:WaitForChild("SwampCrossing"))
    TombLighting:InitAtmosphericLights()
    TombLighting:InitPlayerLightWatcher()
    TombLighting:InitGolemWatcher()

    -- Передаём NPCController в CutsceneManager (для NPC-действий в кат-сценах)
    CutsceneManager:SetNPCController(NPCController)
    _G.NPCController = NPCController

    Remotes:GetFunction("GetCurrentGameStage").OnServerInvoke = function(plr)
        local state = playerStates[plr]
        return (state and state.Stage) or GameConfig.GameStages[1]
    end

    -- ═══════════════════════════════════════
    -- ОБРАБОТЧИК ЗАВЕРШЕНИЯ ДИАЛОГОВ
    -- Когда игрок закрывает окно диалога, клиент отправляет
    -- DialogueChoice с action="DIALOGUE_FINISHED" и trackNPC=ID НПС.
    -- Здесь мы определяем, что делать дальше, на основе:
    --   • trackNPC — какой NPC говорил
    --   • state.Stage — на какой стадии сейчас игрок
    -- ═══════════════════════════════════════
    Remotes:GetEvent("DialogueChoice").OnServerEvent:Connect(function(player, action, trackNPC)
        if action == "DIALOGUE_FINISHED" then
            local state = playerStates[player]
            if not state then return end

            print("[GameManager] Диалог завершён, TrackNPC:", trackNPC, "Stage:", state.Stage)

            -- СЛУЧАЙ 1: Разговор со Старейшиной завершён
            -- MarkDialogueComplete вызывается ВСЕГДА когда Elder-диалог закончен
            -- (не только при SPAWN), чтобы dState.heard = true даже если стадия
            -- успела смениться во время диалога.
            -- Квест и меч выдаются только на стадии SPAWN.
            if trackNPC == "Elder" then
                NPCController:MarkDialogueComplete(player, "Elder")
                if state.Stage == "SPAWN" then
                    WeaponManager:GiveStarterSword(player)
                    task.wait(1)
                    QuestManager:StartQuest(player, "KILL_WOLVES")
                    setStage(player, "WOLF_HUNT")
                end

            -- СЛУЧАЙ 2: Старейшина говорит «спасибо» (стадия JOHN_RESCUE)
            -- → Запускаем кат-сцену WOLF_AMBUSH (только ОДИН раз!)
            elseif trackNPC == "Elder_Thanks" and state.Stage == "JOHN_RESCUE" then
                -- Всегда фиксируем: иначе при повторном E у Старейшины снова весь ELDER_THANKS
                NPCController:MarkElderThanksHeard(player)
                if not state.CutscenePlayed then
                    state.CutscenePlayed = true
                    print("[GameManager] Старейшина поблагодарил → запуск кат-сцены WOLF_AMBUSH")
                    CutsceneManager:PlayCutscene(player, "WOLF_AMBUSH")
                else
                    print("[GameManager] Кат-сцена уже была — пропускаем (благодарность засчитана)")
                end

            -- СЛУЧАЙ 3: Разговор с JOHN DOU после кат-сцены
            -- → Переходим к стадии BAD_NEWS
            elseif trackNPC == "DouDzouh" and state.Stage == "JOHN_RESCUE" then
                NPCController:MarkDialogueComplete(player, "DouDzouh")
                print("[GameManager] Разговор с JOHN DOU завершён → BAD_NEWS")
                task.wait(1)
                setStage(player, "BAD_NEWS")
            end
        end
    end)

    -- ═══════════════════════════════════════
    -- КОНЕЦ КАТ-СЦЕНЫ → авто-диалог
    -- После WOLF_AMBUSH клиент сигналит о завершении (CutsceneFinished).
    -- Мы сами запускаем диалог DOU_DZOUH_INTRO — игрок не должен
    -- искать ProximityPrompt руками, диалог начинается автоматически.
    -- ═══════════════════════════════════════
    Remotes:GetEvent("CutsceneFinished").OnServerEvent:Connect(function(player, cutsceneId)
        local state = playerStates[player]
        if not state then return end

        print("[GameManager] Кат-сцена завершена:", cutsceneId, "| Stage:", state.Stage)

        if cutsceneId == "WOLF_AMBUSH" and state.Stage == "JOHN_RESCUE" then
            print("[GameManager] WOLF_AMBUSH завершена → компаньон JOHN DOU + авто-диалог")
            NPCController:SetCompanion("DouDzouh", player)
            task.wait(0.5) -- пауза, чтобы камера вернулась к игроку
            Remotes:GetEvent("ShowDialogue"):FireClient(player, DialogueData.BuildShowPayload("DOU_DZOUH_INTRO", {
                NPCName   = "JOHN DOU",
                TrackNPC  = "DouDzouh",
            }))
        elseif cutsceneId == "DOU_DZOUH_REQUEST" and state.Stage == "BAN_HAMMER" and hammerCutsceneWaitsReward[player] then
            -- Пьедестал: после кат-сцены — телепорт в руины, выдача молота, завершение цели квеста
            local aq = QuestManager:GetActiveQuest(player)
            if not aq or aq.QuestId ~= "GET_BAN_HAMMER" then
                hammerCutsceneWaitsReward[player] = nil
                return
            end
            local stillIncomplete = false
            for _, o in ipairs(aq.Progress or {}) do
                if not o.Completed then
                    stillIncomplete = true
                    break
                end
            end
            if not stillIncomplete then
                hammerCutsceneWaitsReward[player] = nil
                return
            end

            task.wait(0.35)
            local destName = (WorldMap.Zones.TombLabyrinth and WorldMap.Zones.TombLabyrinth.TeleporterExitDestination)
                or "TeleporterA"
            local destInst = Workspace:FindFirstChild(destName, true)
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and destInst then
                local destCf
                if destInst:IsA("BasePart") then
                    destCf = destInst.CFrame
                elseif destInst:IsA("Model") then
                    destCf = destInst:GetPivot()
                end
                if destCf then
                    -- Смещение от центра A, чтобы сразу не сработал вход A→C в лабиринт
                    hrp.CFrame = destCf * CFrame.new(0, 3, 8)
                    print("[GameManager] После Ban Hammer → телепорт к", destName)
                end
            end

            WeaponManager:GiveBanHammer(player)
            task.wait(0.5)
            QuestManager:UpdateProgress(player, "INTERACT", "BanHammerPedestal")
            hammerCutsceneWaitsReward[player] = nil
        end
    end)

    print("[GameManager] Все модули загружены")

    -- Лабиринт / пьедестал Ban Hammer: касание триггера или пьедестала
    local function tryBeginHammerOrMazeProgress(player: Player)
        if hammerCutsceneWaitsReward[player] then
            return
        end

        local state = playerStates[player]
        if not state then
            return
        end

        local aq = QuestManager:GetActiveQuest(player)
        if aq and aq.QuestId == "SOLVE_MAZE" then
            QuestManager:UpdateProgress(player, "REACH_ZONE", "ArtifactHall")
            return
        end

        if state.Stage ~= "BAN_HAMMER" then
            return
        end
        if not aq or aq.QuestId ~= "GET_BAN_HAMMER" then
            return
        end

        local stillIncomplete = false
        for _, o in ipairs(aq.Progress or {}) do
            if not o.Completed then
                stillIncomplete = true
                break
            end
        end
        if not stillIncomplete then
            return
        end

        hammerCutsceneWaitsReward[player] = true
        CutsceneManager:PlayCutscene(player, "DOU_DZOUH_REQUEST")
    end

    task.spawn(function()
        local recentFires = {} -- [userId] = tick

        local function onBanHammerZoneHit(player: Player)
            local uid = player.UserId
            local now = tick()
            if recentFires[uid] and (now - recentFires[uid]) < 1.2 then
                return
            end
            recentFires[uid] = now
            tryBeginHammerOrMazeProgress(player)
        end

        local function bindPart(p: BasePart)
            p.Touched:Connect(function(hit)
                local character = hit.Parent
                local plr = Players:GetPlayerFromCharacter(character)
                if not plr then
                    return
                end
                onBanHammerZoneHit(plr)
            end)
        end

        for _ = 1, 120 do
            local trig = Workspace:FindFirstChild("BanHammer_Trigger", true)
            if trig and trig:IsA("BasePart") then
                bindPart(trig)
                print("[GameManager] Подключён BanHammer_Trigger (лабиринт / зал артефакта)")
                break
            end
            task.wait(0.5)
        end

        local ped = Workspace:FindFirstChild("BanHammerPedestal", true)
        if ped and ped:IsA("BasePart") then
            bindPart(ped)
            print("[GameManager] Подключён BanHammerPedestal (Part)")
        elseif ped and ped:IsA("Model") then
            local n = 0
            for _, d in ped:GetDescendants() do
                if d:IsA("BasePart") then
                    bindPart(d)
                    n += 1
                end
            end
            if n > 0 then
                print("[GameManager] Подключён BanHammerPedestal (Model, частей:", n, ")")
            end
        end
    end)

    -- ═══════════════════════════════════════
    -- ЗОНОВЫЕ ТРИГГЕРЫ
    -- Подключаем Touched к триггерам в Workspace.Triggers.
    -- Дедупликация: один срабатыватель на игрока раз в 3 секунды.
    -- ═══════════════════════════════════════
    task.spawn(function()
        local triggersFolder = Workspace:WaitForChild("Triggers", 30)
        if not triggersFolder then
            warn("[GameManager] Папка Triggers не найдена — зоновые триггеры не подключены")
            return
        end

        local recentFires = {} -- [userId .. "_" .. triggerName] = lastTickTime

        local function connectTrigger(triggerName, callback)
            local trigger = triggersFolder:WaitForChild(triggerName, 10)
            if not trigger then
                warn("[GameManager] Триггер не найден:", triggerName)
                return
            end
            trigger.Touched:Connect(function(hit)
                local character = hit.Parent
                local player = Players:GetPlayerFromCharacter(character)
                if not player then return end

                local key = tostring(player.UserId) .. "_" .. triggerName
                local now = tick()
                if recentFires[key] and (now - recentFires[key]) < 3 then return end
                recentFires[key] = now

                callback(player)
            end)
            print("[GameManager] Триггер подключён:", triggerName)
        end

        -- Возврат в деревню → завершить RETURN_TO_VILLAGE
        connectTrigger("ReturnToVillage", function(player)
            QuestManager:UpdateProgress(player, "REACH_ZONE", "Village")
        end)

        -- Вход в лес → прогресс TRAVERSE_FOREST
        connectTrigger("ForestEntrance_Trigger", function(player)
            QuestManager:UpdateProgress(player, "REACH_ZONE", "Forest")
        end)

        -- Вход в болото (конец леса) → завершить TRAVERSE_FOREST
        connectTrigger("SwampEntrance_Trigger", function(player)
            QuestManager:UpdateProgress(player, "REACH_ZONE", "Swamp")
        end)

        -- Резерв: выход из болота у руин гидры (если кочки не настроены)
        connectTrigger("SwampExit_Trigger", function(player)
            local state = playerStates[player]
            if state and state.Stage == "SWAMP_JOURNEY" then
                QuestManager:UpdateProgress(player, "REACH_ZONE", "HydraRuins")
                QuestManager:UpdateProgress(player, "SURVIVE", nil)
            end
        end)

        -- Вход в гробницу (после гидры) — для лабиринта
        connectTrigger("TombEntrance_Trigger", function(player)
            local state = playerStates[player]
            if state and state.Stage == "TOMB_MAZE" then
                QuestManager:UpdateProgress(player, "REACH_ZONE", "Tomb")
            end
        end)

        -- Вход в дом деда → прогресс квеста FIND_MAP + карта в доме
        connectTrigger("GrandfatherHouse_Enter", function(player)
            QuestManager:UpdateProgress(player, "INTERACT", "GrandfatherHouse")
            local state = playerStates[player]
            local activeQuest = QuestManager:GetActiveQuest(player)
            if state and (state.Stage == "BAD_NEWS" or state.Stage == "SECRET_MAP"
                or (activeQuest and activeQuest.QuestId == "FIND_MAP")) then
                if not DataManager:HasItem(player, "SecretMap") then
                    MapPickupSpawner:EnsurePickup(handleMapPickupCollected)
                end
            end
        end)
    end)

    local lastSwampBoundsCheck = 0
    RunService.Heartbeat:Connect(function()
        local now = tick()
        if now - lastSwampBoundsCheck < 0.5 then
            return
        end
        lastSwampBoundsCheck = now

        for player, state in pairs(playerStates) do
            if state.Stage == "FOREST_JOURNEY" then
                local root = getCharacterRoot(player)
                if root and StageWorldConfig.PointInLocation("Swamp", root.Position) then
                    QuestManager:UpdateProgress(player, "REACH_ZONE", "Swamp")
                    if state.Stage == "FOREST_JOURNEY" then
                        setStage(player, "SWAMP_JOURNEY")
                    end
                end
            end
        end
    end)

    -- ═══════════════════════════════════════
    -- ДЕБАГ: единая точка (клиент DebugTools.client.lua)
    -- УДАЛИТЬ ПЕРЕД РЕЛИЗОМ!
    -- ═══════════════════════════════════════
    Remotes:GetEvent("DebugTools").OnServerEvent:Connect(function(player, action)
        if type(action) ~= "string" then
            return
        end
        print("[DEBUG] DebugTools |", player.Name, "|", action)

        if action == "MapReady" then
            WeaponManager:GiveStarterSword(player)

            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local backpack = player:FindFirstChild("Backpack")
            local sword = (backpack and backpack:FindFirstChild("Старый Меч"))
                or (character and character:FindFirstChild("Старый Меч"))
            if humanoid and sword and sword:IsA("Tool") and sword.Parent ~= character then
                humanoid:EquipTool(sword)
            end

            DataManager:AddItem(player, "SecretMap")
            MapPickupSpawner:RemovePickup()
            openVillageGates()

            local wolvesFolder = Workspace:FindFirstChild("Wolves")
            if wolvesFolder then
                for _, wolf in ipairs(wolvesFolder:GetChildren()) do
                    local wolfHumanoid = wolf:FindFirstChildOfClass("Humanoid")
                    if wolfHumanoid and wolfHumanoid.Health > 0 then
                        wolfHumanoid.Health = 0
                    end
                end
            end

            NPCController:ActivateNPC("DouDzouh", player)
            setStage(player, "FOREST_JOURNEY")

            local activeQ = QuestManager:GetActiveQuest(player)
            if not activeQ or activeQ.QuestId ~= "TRAVERSE_FOREST" then
                QuestManager:StartQuest(player, "TRAVERSE_FOREST")
            end

            Remotes:GetEvent("UpdateHUD"):FireClient(player, {
                Notification = "DEBUG M: карта, меч, волки убиты",
            })
            print("[DEBUG] MapReady → FOREST_JOURNEY |", player.Name)
        elseif action == "KillWolves" then
            local wolvesFolder = Workspace:FindFirstChild("Wolves")
            if wolvesFolder then
                for _, wolf in ipairs(wolvesFolder:GetChildren()) do
                    local humanoid = wolf:FindFirstChildOfClass("Humanoid")
                    if humanoid and humanoid.Health > 0 then
                        humanoid.Health = 0
                    end
                end
            end
        elseif action == "CycleZone" then
            local zoneOrder = { "Village", "Outskirts", "Forest", "Tomb", "ArtifactHall" }
            local idx = (debugZoneCycleIndex[player] or 0) + 1
            if idx > #zoneOrder then
                idx = 1
            end
            debugZoneCycleIndex[player] = idx
            local zoneName = zoneOrder[idx]
            local zone = GameConfig.Zones[zoneName]
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and zone and zone.SpawnPoint then
                hrp.CFrame = CFrame.new(zone.SpawnPoint + Vector3.new(0, 5, 0))
            end
            print("[DEBUG] CycleZone →", zoneName, "|", player.Name)
        elseif action == "JumpMiniBoss" then
            setStage(player, "MINI_BOSS")
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local pt = GameConfig.Zones.MiniBossArena.SpawnPoint
            if hrp then
                hrp.CFrame = CFrame.new(pt + Vector3.new(0, 5, 0))
            end
        elseif action == "JumpSwamp" then
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")

            local tpPos: Vector3? = nil
            local zones = Workspace:FindFirstChild("Zones")
            local swamp = zones and zones:FindFirstChild("Swamp")
            if swamp then
                for _, desc in ipairs(swamp:GetDescendants()) do
                    if desc:IsA("BasePart") and desc.Name == "SwampKochka_1" then
                        tpPos = desc.Position + Vector3.new(0, desc.Size.Y / 2 + 5, 0)
                        break
                    end
                end
            end
            if not tpPos then
                local triggers = Workspace:FindFirstChild("Triggers")
                local trig = triggers and triggers:FindFirstChild("SwampEntrance_Trigger")
                if trig and trig:IsA("BasePart") then
                    tpPos = trig.Position + Vector3.new(0, 5, 0)
                end
            end
            if not tpPos and GameConfig.Zones.Forest then
                tpPos = GameConfig.Zones.Forest.SpawnPoint + Vector3.new(0, 5, 0)
            end

            if hrp and tpPos then
                hrp.CFrame = CFrame.new(tpPos)
            end

            NPCController:ActivateNPC("DouDzouh")
            setStage(player, "SWAMP_JOURNEY")
            print("[DEBUG] JumpSwamp → SWAMP_JOURNEY | TP:", tpPos, "|", player.Name)
        elseif action == "JumpTombMaze" then
            setStage(player, "TOMB_MAZE")

            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                return
            end

            -- Предпочтительно телепортироваться к точке TeleporterC (как в TombTeleporter),
            -- чтобы оказаться внутри лабиринта. Иначе — фолбэк на SpawnPoint зоны гробницы.
            local destInst = Workspace:FindFirstChild("TeleporterC", true)
            if destInst then
                local destCf
                if destInst:IsA("BasePart") then
                    destCf = destInst.CFrame
                elseif destInst:IsA("Model") then
                    destCf = destInst:GetPivot()
                end
                if destCf then
                    hrp.CFrame = destCf * CFrame.new(0, 3, 0)
                    return
                end
            end

            local pt = GameConfig.Zones.Tomb and GameConfig.Zones.Tomb.SpawnPoint
            if pt then
                hrp.CFrame = CFrame.new(pt + Vector3.new(0, 5, 0))
            end
        elseif action == "JumpMazeNearExit" then
            -- Стадия «после лабиринта» + квест на молот; TP относительно TeleporterD (K debug).
            -- Точка спавна была (-1965.784, -238.419, -60.705), телепортер (-1992.201, -235.608, -34.337).
            -- +8 по Y — не проваливаться под пол (коллизия/нижняя граница лабиринта).
            local banStage = StageWorldConfig.Stages.BAN_HAMMER
            local JUMP_MAZE_EXIT_OFFSET = (banStage and banStage.DebugMazeExitOffset)
                or Vector3.new(26.417, 5.189, -26.368)

            setStage(player, "BAN_HAMMER")
            QuestManager:StartQuest(player, "GET_BAN_HAMMER")

            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                return
            end

            local maze = WorldMap.Zones.TombLabyrinth
            local dName = (maze and maze.TeleporterExitSender) or "TeleporterD"
            local dInst = Workspace:FindFirstChild(dName, true)
            if dInst then
                local basePos
                if dInst:IsA("BasePart") then
                    basePos = dInst.Position
                elseif dInst:IsA("Model") then
                    basePos = dInst:GetPivot().Position
                else
                    basePos = hrp.Position
                end

                local spawnPos = basePos + JUMP_MAZE_EXIT_OFFSET
                hrp.CFrame = CFrame.new(spawnPos)
                print("[DEBUG] JumpMazeNearExit →", dName, spawnPos, "|", player.Name)
            else
                warn("[DEBUG] JumpMazeNearExit: не найден «" .. tostring(dName) .. "» в Workspace")
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
-- ПОДКЛЮЧЕНИЕ ИГРОКА
-- Вызывается автоматически при входе нового игрока на сервер.
-- Загружает данные, определяет концовку, настраивает респавн.
-- ═══════════════════════════════════════════════════════════
local function onPlayerAdded(player)
    print("[GameManager] Игрок подключился:", player.Name)

    -- Загружаем сохранённые данные (или создаём новые)
    local playerData = DataManager:LoadPlayerData(player)

    -- Создаём начальное состояние
    playerStates[player] = {
        Stage = GameConfig.GameStages[1],   -- "SPAWN"
        Data = playerData,
    }

    -- Определяем, какую концовку увидит игрок (по числу прохождений)
    local ending = EndingConfig.GetEndingForPlayer(
        playerData.EndingsCount or 0,
        playerData.HasSecretCode or false
    )
    playerStates[player].CurrentEnding = ending

    DataManager:SyncInventory(player)

    -- ═══════════════════════════════════════
    -- ОБРАБОТЧИК РЕСПАВНА
    -- Каждый раз, когда персонаж перерождается:
    -- • Восстанавливаем оружие (Tool уничтожается при смерти)
    -- • Если стадия WOLF_HUNT — респавним волков
    -- ═══════════════════════════════════════
    player.CharacterAdded:Connect(function(character)
        local state = playerStates[player]
        if not state then return end

        task.wait(1) -- ждём загрузку персонажа

        -- Восстанавливаем оружие
        WeaponManager:RestoreWeaponsOnRespawn(player)
        TombLighting:RestorePlayerLightIfNeeded(player)

        -- Если игрок на стадии охоты — волки должны быть на месте
        if state.Stage == "WOLF_HUNT" then
            WolfSpawner:SpawnWolves(player)
            Remotes:GetEvent("UpdateHUD"):FireClient(player, {
                Notification = "⚠️ Волки снова рыскают!"
            })
        end

        print("[GameManager] Респавн:", player.Name, "| Стадия:", state.Stage)
    end)

    -- Запускаем игру
    startGame(player)
end

-- ═══════════════════════════════════════════════════════════
-- НАЧАЛО ИГРЫ
-- Устанавливает начальную стадию и активирует Старейшину.
-- Игрок увидит ProximityPrompt около NPC и сможет начать диалог.
-- ═══════════════════════════════════════════════════════════
function startGame(player)
    local state = playerStates[player]
    if not state then return end

    print("[GameManager] Начинаем игру для", player.Name, "| Концовка #" .. state.CurrentEnding.Id)

    -- Устанавливаем начальную стадию
    setStage(player, "SPAWN")

    -- Активируем NPC Старейшины (создаёт ProximityPrompt)
    NPCController:ActivateNPC("Elder", player)

    print("[GameManager] Ожидаем разговор со Старейшиной...")
end

-- ═══════════════════════════════════════════════════════════
-- СМЕНА СТАДИИ ИГРЫ
-- Ключевая функция. Меняет state.Stage и выполняет
-- действия, специфичные для каждой стадии.
-- Также оповещает клиент через StageChanged RemoteEvent.
--
-- Параметр: stageName — строка из GameConfig.GameStages
-- ═══════════════════════════════════════════════════════════
function setStage(player, stageName)
    local state = playerStates[player]
    if not state then return end

    state.Stage = stageName
    print("[GameManager] Стадия:", stageName, "для", player.Name)

    -- Оповещаем клиент о смене стадии
    Remotes:GetEvent("StageChanged"):FireClient(player, stageName)

    -- ─── Действия по стадиям ───

    if stageName ~= "TOMB_MAZE" then
        TombLighting:RemovePlayerLight(player)
    end

    if stageName == "WOLF_HUNT" then
        -- Страховка: Elder-диалог отмечается завершённым при начале охоты.
        -- Гарантирует dState.heard = true даже если DIALOGUE_FINISHED не пришёл
        -- (отладка, быстрый клик, сетевой сбой).
        NPCController:MarkDialogueComplete(player, "Elder")
        -- Спавним волков в зоне Outskirts
        WolfSpawner:SpawnWolves(player)

    elseif stageName == "JOHN_RESCUE" then
        -- Волки убиты! Игроку нужно вернуться к Старейшине.
        -- Кат-сцена НЕ запускается автоматически — только после диалога.
        Remotes:GetEvent("UpdateHUD"):FireClient(player, {
            Notification = "🐺 Все волки уничтожены! Вернись к Старейшине."
        })

    elseif stageName == "BAD_NEWS" then
        -- Плохие новости о деде → кат-сцена
        CutsceneManager:PlayCutscene(player, "BAD_NEWS")

        local activeQ = QuestManager:GetActiveQuest(player)
        if not activeQ or activeQ.QuestId ~= "FIND_MAP" then
            QuestManager:StartQuest(player, "FIND_MAP")
        end

        Remotes:GetEvent("UpdateHUD"):FireClient(player, {
            Notification = "🏠 Старейшина советует заглянуть в дом деда",
        })

        if not DataManager:HasItem(player, "SecretMap") then
            MapPickupSpawner:EnsurePickupWhenReady(handleMapPickupCollected, function()
                return not player.Parent or DataManager:HasItem(player, "SecretMap")
            end)
        end

    elseif stageName == "SECRET_MAP" then
        -- Показываем найденную карту на экране
        Remotes:GetEvent("ShowMap"):FireClient(player)

    elseif stageName == "FOREST_JOURNEY" then
        Remotes:GetEvent("ShowMap"):FireClient(player)
        NPCController:SetCompanion("DouDzouh", player)
        Remotes:GetEvent("ShowDialogue"):FireClient(player, DialogueData.BuildShowPayload("DOU_DZOUH_FOREST", {
            NPCName = "JOHN DOU",
            TrackNPC = "DouDzouh",
        }))
        Remotes:GetEvent("UpdateHUD"):FireClient(player, {
            Notification = "🌲 Иди через лес — JOHN DOU ведёт к болоту",
        })

    elseif stageName == "SWAMP_JOURNEY" then
        NPCController:StopCompanion("DouDzouh")
        local activeQ = QuestManager:GetActiveQuest(player)
        if not activeQ or activeQ.QuestId ~= "CROSS_SWAMP" then
            QuestManager:StartQuest(player, "CROSS_SWAMP")
        end
        SwampCrossing:Start(player)

    elseif stageName == "MINI_BOSS" then
        print("[GameManager] Стадия MINI_BOSS → спавн гидры | игрок:", player.Name)
        -- JOHN DOU становится компаньоном (ShowMap уже выстрелен из обработчика письма)
        NPCController:SetCompanion("DouDzouh", player)
        -- Спавним King Hydra Blaster у ворот гробницы
        MiniBossSpawner:Spawn(player)

    elseif stageName == "FINALE" then
        -- Финал: запускаем кат-сцену концовки (зависит от номера прохождения)
        local ending = state.CurrentEnding
        CutsceneManager:PlayCutscene(player, ending.CutsceneId)

    elseif stageName == "CREDITS" then
        -- Титры: показываем финальный экран
        Remotes:GetEvent("ShowCredits"):FireClient(player, {
            Id = state.CurrentEnding.Id,
            Name = state.CurrentEnding.Name,
            CreditsText = state.CurrentEnding.CreditsText,
        })
        -- Увеличиваем счётчик прохождений и сохраняем
        state.Data.EndingsCount = (state.Data.EndingsCount or 0) + 1
        DataManager:SavePlayerData(player, state.Data)
    end
end

-- ═══════════════════════════════════════════════════════════
-- ОБРАБОТКА ЗАВЕРШЕНИЯ КВЕСТА
-- Вызывается из QuestManager через _G.GameManager.OnQuestCompleted.
-- Определяет следующую стадию на основе ID завершённого квеста.
-- ═══════════════════════════════════════════════════════════
function onQuestCompleted(player, questId)
    local state = playerStates[player]
    if not state then return end

    print("[GameManager] Квест завершён:", questId)

    -- Таблица маппинга: квест → следующая стадия
    -- RETURN_TO_VILLAGE здесь намеренно отсутствует:
    -- переход в BAD_NEWS происходит через диалог DouDzouh (DialogueChoice handler),
    -- а не через завершение квеста, иначе триггер ReturnToVillage перепрыгнет
    -- через Elder_Thanks-диалог и кат-сцену WOLF_AMBUSH.
    local stageMap = {
        KILL_WOLVES = "JOHN_RESCUE",
        FIND_MAP = "FOREST_JOURNEY",
        TRAVERSE_FOREST = "SWAMP_JOURNEY",
        CROSS_SWAMP = "MINI_BOSS",
        DEFEAT_MINI_BOSS = "TOMB_MAZE",
        SOLVE_MAZE = "BAN_HAMMER",
        GET_BAN_HAMMER = "FINALE",
    }

    local nextStage = stageMap[questId]
    if nextStage then
        setStage(player, nextStage)
    end

    if questId == "SOLVE_MAZE" then
        task.delay(2.4, function()
            if not player.Parent then
                return
            end
            if hammerCutsceneWaitsReward[player] then
                return
            end
            local st = playerStates[player]
            if not st or st.Stage ~= "BAN_HAMMER" then
                return
            end
            local aq = QuestManager:GetActiveQuest(player)
            if not aq or aq.QuestId ~= "GET_BAN_HAMMER" then
                return
            end
            local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then
                return
            end
            local pos = nil
            local ped = Workspace:FindFirstChild("BanHammerPedestal", true)
            if ped and ped:IsA("BasePart") then
                pos = ped.Position
            elseif ped and ped:IsA("Model") then
                pos = ped:GetPivot().Position
            end
            if not pos then
                local tr = Workspace:FindFirstChild("BanHammer_Trigger", true)
                if tr and tr:IsA("BasePart") then
                    pos = tr.Position
                end
            end
            if pos and (hrp.Position - pos).Magnitude < 34 then
                hammerCutsceneWaitsReward[player] = true
                CutsceneManager:PlayCutscene(player, "DOU_DZOUH_REQUEST")
            end
        end)
    end
end

-- ═══════════════════════════════════════════════════════════
-- ОТКЛЮЧЕНИЕ ИГРОКА
-- Сохраняем данные и очищаем все ресурсы, связанные с игроком.
-- ═══════════════════════════════════════════════════════════
local function onPlayerRemoving(player)
    local state = playerStates[player]
    if state then
        DataManager:SavePlayerData(player, state.Data)
        playerStates[player] = nil
    end
    hammerCutsceneWaitsReward[player] = nil
    -- Очищаем ресурсы во всех модулях
    NPCController:OnPlayerLeaving(player)
    CutsceneManager:ClearWolfAmbushSession(player)
    WeaponManager:OnPlayerLeaving(player)
    WolfSpawner:ClearWolves(player)
    MiniBossSpawner:Clear(player, "GameManager_onPlayerRemoving")
    print("[GameManager] Игрок отключился:", player.Name)
end

-- ═══════════════════════════════════════════════════════════
-- ЗАПУСК!
-- ═══════════════════════════════════════════════════════════
init()

-- Подключаем обработчики событий игроков
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- ═══════════════════════════════════════════════════════════
-- ГЛОБАЛЬНАЯ ТАБЛИЦА (_G)
-- Экспортируем ключевые функции в _G, чтобы QuestManager
-- и WolfSpawner могли вызвать GameManager без циклических require().
-- _G — глобальная таблица Lua, доступная из ВСЕХ серверных скриптов.
-- ═══════════════════════════════════════════════════════════
_G.GameManager = {
    SetStage = setStage,                    -- для WolfSpawner и CutsceneManager
    OnQuestCompleted = onQuestCompleted,    -- для QuestManager
    GetPlayerState = function(player)       -- для диагностики
        return playerStates[player]
    end,
}

_G.QuestManager = QuestManager             -- для MiniBossSpawner и др. без циклического require

print("[GameManager] Готов к работе")
