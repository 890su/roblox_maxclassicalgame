--[[
    CutsceneManager — Серверная часть кат-сцен
    ═══════════════════════════════════════════════════════════
    
    Управляет кат-сценами: камера, NPC-действия, диалоги.
    
    КАК РАБОТАЕТ КАТ-СЦЕНА:
    ───────────────────────
    1. GameManager вызывает CutsceneManager:PlayCutscene(player, "WOLF_AMBUSH")
    2. Сервер отправляет клиенту данные камеры через StartCutscene RemoteEvent
    3. Клиент (CutsceneController) перехватывает камеру и интерполирует
    4. Сервер параллельно двигает NPC и запускает NPC-действия
    5. После Duration секунд — кат-сцена завершена
    
    РАЗДЕЛЕНИЕ СЕРВЕР/КЛИЕНТ:
    ─────────────────────────
    • СЕРВЕР: NPC-действия, спавн волка, перемещение JOHN DOU (этот файл)
    • КЛИЕНТ: камера, затемнение экрана, диалоги (CutsceneController.client.lua)
    
    ОПРЕДЕЛЕНИЯ КАТ-СЦЕН:
    ──────────────────────
    Каждая кат-сцена описана в cutsceneDefinitions:
    • Duration      — длительность в секундах
    • CameraPoints  — массив {Position, LookAt, Time} для интерполяции камеры
    • NPCActions    — массив {NPC, Action, Time} для действий NPC
    • DialogueId    — ID диалога из DialogueData (опционально)
    • DialogueAfter — диалог ПОСЛЕ кат-сцены (опционально)
    • OnComplete    — стадия, к которой перейти после завершения
    
    WOLF_AMBUSH — уникальная кат-сцена с кастомной логикой:
    → Спавн волка-вожака → волк бежит на игрока → JOHN DOU убивает
    → JOHN DOU перемещается к игроку → можно поговорить
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DialogueData = require(ServerScriptService:WaitForChild("DialogueData"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WolfConfig = require(ServerScriptService:WaitForChild("WolfConfig"))

local CutsceneManager = {}

-- WOLF_AMBUSH: один полный прогон на игрока за сессию + защита от двойного task.spawn
local wolfAmbushDoneForPlayer = {} -- [userId] = true только после полного прохода PlayWolfAmbush
local wolfAmbushRunning = {}      -- [userId] = true пока выполняется PlayWolfAmbush

function CutsceneManager:ClearWolfAmbushSession(player)
    local id = player.UserId
    wolfAmbushDoneForPlayer[id] = nil
    wolfAmbushRunning[id] = nil
end

-- Ссылка на NPCController (устанавливается через SetNPCController из GameManager)
-- Нельзя require напрямую — будет циклическая зависимость.
local NPCController = nil

-- ═══════════════════════════════════════════════════════════
-- УСТАНОВКА ССЫЛКИ НА NPCController
-- Вызывается из GameManager после загрузки всех модулей.
-- ═══════════════════════════════════════════════════════════
function CutsceneManager:SetNPCController(controller)
    NPCController = controller
end

-- ═══════════════════════════════════════════════════════════
-- СОЗДАНИЕ ВОЛКА-ВОЖАКА ДЛЯ КАТ-СЦЕНЫ WOLF_AMBUSH
-- Крупнее обычного (x1.3), темнее (почти чёрный), быстрее (WalkSpeed = 30).
-- Это специальный волк, который появляется только в кат-сцене.
-- ═══════════════════════════════════════════════════════════
local function createAmbushWolf(position)
    local config = WolfConfig.Model

    local wolfModel = Instance.new("Model")
    wolfModel.Name = "AmbushWolf"

    -- Тело: увеличенное на 30% и темнее обычного
    local body = Instance.new("Part")
    body.Name = "HumanoidRootPart"
    body.Size = config.BodySize * 1.3              -- крупнее обычного
    body.Color = Color3.fromRGB(40, 40, 40)        -- почти чёрный (вожак!)
    body.Material = Enum.Material.SmoothPlastic
    body.Position = position
    body.Anchored = false
    body.CanCollide = true
    body.Parent = wolfModel

    -- Голова
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = config.HeadSize * 1.3
    head.Color = Color3.fromRGB(40, 40, 40)
    head.Material = Enum.Material.SmoothPlastic
    head.Position = position + Vector3.new(0, 0.3, -2.5)
    head.Anchored = false
    head.CanCollide = false
    head.Parent = wolfModel

    -- Красные глаза (Neon — светятся!)
    local eyeL = Instance.new("Part")
    eyeL.Name = "EyeLeft"
    eyeL.Size = Vector3.new(0.3, 0.3, 0.3)
    eyeL.Color = Color3.fromRGB(255, 0, 0)
    eyeL.Material = Enum.Material.Neon
    eyeL.Position = head.Position + Vector3.new(-0.3, 0.3, -0.5)
    eyeL.Anchored = false
    eyeL.CanCollide = false
    eyeL.Parent = wolfModel

    local eyeR = eyeL:Clone()
    eyeR.Name = "EyeRight"
    eyeR.Position = head.Position + Vector3.new(0.3, 0.3, -0.5)
    eyeR.Parent = wolfModel

    -- Привариваем все части к телу
    for _, part in ipairs({head, eyeL, eyeR}) do
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = body
        weld.Part1 = part
        weld.Parent = part
    end

    -- Humanoid: 50 HP, скорость 30 (быстрый!)
    local humanoid = Instance.new("Humanoid")
    humanoid.MaxHealth = 50
    humanoid.Health = 50
    humanoid.WalkSpeed = 30                        -- очень быстрый
    humanoid.Parent = wolfModel

    wolfModel.PrimaryPart = body

    return wolfModel
end

-- ═══════════════════════════════════════════════════════════
-- ОПРЕДЕЛЕНИЯ КАТ-СЦЕН
-- Каждая кат-сцена — таблица с параметрами камеры и NPC.
-- CameraPoints описывают ОТНОСИТЕЛЬНЫЕ позиции камеры:
--   Position — откуда смотрит камера
--   LookAt   — куда смотрит камера
--   Time     — на какой секунде камера должна быть в этой позиции
-- Между точками камера плавно интерполируется на клиенте.
-- ═══════════════════════════════════════════════════════════
local cutsceneDefinitions = {

    -- ═══════════════════════════════════════
    -- WOLF_AMBUSH: Волк-вожак нападает, JOHN DOU спасает
    -- Длительность: 10 секунд
    -- Камера: 5 точек, облетает сцену
    -- ═══════════════════════════════════════
    WOLF_AMBUSH = {
        Duration = 10,
        DialogueAfter = "DOU_DZOUH_INTRO",          -- диалог ПОСЛЕ кат-сцены
        CameraPoints = {
            { Position = Vector3.new(25, 25, 25), LookAt = Vector3.new(0, 3, 0), Time = 0 },
            { Position = Vector3.new(25, 25, 25), LookAt = Vector3.new(0, 3, 0), Time = 1.5 },
            { Position = Vector3.new(25, 25, 25), LookAt = Vector3.new(0, 3, 0), Time = 4 },
            { Position = Vector3.new(25, 25, 25), LookAt = Vector3.new(0, 3, 0), Time = 6 },
            { Position = Vector3.new(25, 25, 25), LookAt = Vector3.new(0, 3, 0), Time = 8 },
        },
    },

    -- ═══════════════════════════════════════
    -- BAD_NEWS: Старейшина сообщает о смерти деда
    -- ═══════════════════════════════════════
    BAD_NEWS = {
        Duration = 10,
        DialogueId = "ELDER_BAD_NEWS",               -- диалог ВО ВРЕМЯ кат-сцены
        CameraPoints = {
            { Position = Vector3.new(0, 5, -8), LookAt = Vector3.new(0, 4, 0), Time = 0 },
            { Position = Vector3.new(3, 4, -6), LookAt = Vector3.new(-2, 4, 2), Time = 4 },
        },
        NPCActions = {
            { NPC = "Elder", Action = "FACE_PLAYER", Time = 0 },
        },
    },

    -- ═══════════════════════════════════════
    -- DOU_DZOUH_REQUEST: JOHN DOU просит молот
    -- ═══════════════════════════════════════
    DOU_DZOUH_REQUEST = {
        Duration = 6,
        DialogueId = "DOU_DZOUH_REQUEST_HAMMER",
        CameraPoints = {
            { Position = Vector3.new(0, 6, -10), LookAt = Vector3.new(0, 3, 0), Time = 0 },
        },
        NPCActions = {
            { NPC = "DouDzouh", Action = "FACE_PLAYER", Time = 0 },
        },
    },

    -- ═══════════════════════════════════════
    -- КОНЦОВКА 1: Предательство
    -- JOHN DOU забирает Ban Hammer → титры
    -- ═══════════════════════════════════════
    CUTSCENE_BETRAYAL = {
        Duration = 12,
        DialogueId = "ENDING_1_BETRAYAL",
        CameraPoints = {
            { Position = Vector3.new(25, 25, 25), LookAt = Vector3.new(0, 0, 0), Time = 0 },
            { Position = Vector3.new(25, 25, 25), LookAt = Vector3.new(0, 0, 0), Time = 4 },
            { Position = Vector3.new(25, 25, 25), LookAt = Vector3.new(0, 0, 0), Time = 8 },
        },
        NPCActions = {
            { NPC = "DouDzouh", Action = "TAKE_HAMMER", Time = 2 },
        },
        OnComplete = "CREDITS",                      -- после кат-сцены → титры
    },

    -- ═══════════════════════════════════════
    -- КОНЦОВКА 2: Босс-файт
    -- ═══════════════════════════════════════
    CUTSCENE_BOSS_FIGHT = {
        Duration = 8,
        DialogueId = "ENDING_2_FIGHT",
        CameraPoints = {
            { Position = Vector3.new(0, 6, -12), LookAt = Vector3.new(0, 3, 0), Time = 0 },
            { Position = Vector3.new(-5, 5, -8), LookAt = Vector3.new(0, 3, 3), Time = 3 },
        },
        OnComplete = "BOSS_FIGHT",                   -- после кат-сцены → бой (TODO)
    },

    -- ═══════════════════════════════════════
    -- КОНЦОВКА 3: Побег (секретная)
    -- ═══════════════════════════════════════
    CUTSCENE_ESCAPE = {
        Duration = 15,
        DialogueId = "ENDING_3_TRUTH",
        CameraPoints = {
            { Position = Vector3.new(0, 6, -10), LookAt = Vector3.new(0, 3, 0), Time = 0 },
            { Position = Vector3.new(8, 10, -5), LookAt = Vector3.new(0, 5, 5), Time = 5 },
            { Position = Vector3.new(0, 15, 0), LookAt = Vector3.new(0, 0, 10), Time = 10 },
        },
        OnComplete = "CREDITS",
    },
}

-- ═══════════════════════════════════════════════════════════
-- КАСТОМНАЯ ЛОГИКА: WOLF_AMBUSH
-- Эта кат-сцена требует особого обращения, поскольку в ней:
-- 1. Спавнится новый NPC (волк-вожак)
-- 2. Волк бежит на игрока
-- 3. JOHN DOU активируется и перемещается к волку
-- 4. JOHN DOU «убивает» волка (Health = 0)
-- 5. Тело волка удаляется, JOHN DOU перемещается к игроку
--
-- ТАЙМЛАЙН:
-- 0.0s — камера отправлена на клиент
-- 0.5s — волк заспавнен и бежит на игрока
-- 2.5s — JOHN DOU появляется за домом
-- 3.5s — JOHN DOU «убивает» волка (вспышка)
-- 5.0s — тело волка удаляется
-- 5.0s — JOHN DOU перемещается к игроку
-- 8.0s — кат-сцена завершается на клиенте
-- ═══════════════════════════════════════════════════════════
-- WOLF_AMBUSH — таймлайн:
-- 0.0s — камера на клиент
-- 0.5s — волк спавнится ВПЕРЕДИ игрока (по LookVector), бежит на него
-- 1.2s — JOHN DOU телепортируется СЗАДИ/СБОКУ (по -LookVector)
-- 1.3s — JOHN DOU бежит к игроку (там будет волк) со скоростью 26
-- 3.3s — JOHN DOU добегает, убивает волка
-- 4.8s — JOHN DOU встаёт рядом с игроком для диалога
-- 8.0s — кат-сцена завершена
function CutsceneManager:PlayWolfAmbush(player)
    print("[CutsceneManager] === WOLF_AMBUSH ===")

    local character = player.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end

    local hrp         = character.HumanoidRootPart
    local playerPos   = hrp.Position
    local lookVec     = hrp.CFrame.LookVector          -- куда смотрит игрок
    local rightVec    = hrp.CFrame.RightVector          -- вправо от игрока

    -- 1. Отправляем данные камеры на клиент
    local def = cutsceneDefinitions.WOLF_AMBUSH
    Remotes:GetEvent("StartCutscene"):FireClient(player, {
        Id = "WOLF_AMBUSH",
        Duration = def.Duration,
        CameraPoints = def.CameraPoints,
    })

    -- 2. Волк появляется за спиной игрока и бросается к нему.
    local wolfSpawnPos = Vector3.new(
        (playerPos - lookVec * 24 - rightVec * 3).X,
        playerPos.Y,
        (playerPos - lookVec * 24 - rightVec * 3).Z
    )
    local intercept = Vector3.new(
        (playerPos - lookVec * 6).X,
        playerPos.Y,
        (playerPos - lookVec * 6).Z
    )

    local ambushWolf
    local ServerStorage = game:GetService("ServerStorage")
    local alphaWolfTemplate = ServerStorage:FindFirstChild("AlphaWolfModel")

    if alphaWolfTemplate then
        ambushWolf = alphaWolfTemplate:Clone()
        ambushWolf:PivotTo(CFrame.lookAt(wolfSpawnPos, intercept))
        local hum = ambushWolf:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.WalkSpeed = 28
            hum.MaxHealth = 50
            hum.Health    = 50
        end
    else
        ambushWolf = createAmbushWolf(wolfSpawnPos)
        ambushWolf:PivotTo(CFrame.lookAt(wolfSpawnPos, intercept))
    end

    local npcsFolder = Workspace:FindFirstChild("NPCs")
    if not npcsFolder then
        npcsFolder = Instance.new("Folder")
        npcsFolder.Name = "NPCs"
        npcsFolder.Parent = Workspace
    end
    ambushWolf.Parent = npcsFolder

    task.wait(0.25)

    -- 3. Волк бежит по линии атаки к игроку, но точка удара — за спиной игрока.
    print("[CutsceneManager] Волк бежит на игрока!")
    local wolfHumanoid = ambushWolf:FindFirstChildOfClass("Humanoid")
    local wolfRoot = ambushWolf.PrimaryPart
        or ambushWolf:FindFirstChild("HumanoidRootPart")
        or ambushWolf:FindFirstChildWhichIsA("BasePart")
    if wolfHumanoid then
        wolfHumanoid:MoveTo(intercept)
        wolfHumanoid.Jump = true
    end

    task.wait(0.2)  -- волк уже стартовал, JOHN DOU ещё успевает войти на перехват

    -- 4. JOHN DOU появляется сбоку от линии атаки и бежит на перехват.
    print("[CutsceneManager] JOHN DOU появляется!")
    local douDzouhSpawnPos = Vector3.new(
        (playerPos - lookVec * 10 + rightVec * 14).X,
        playerPos.Y,
        (playerPos - lookVec * 10 + rightVec * 14).Z
    )

    local douModel = nil
    if NPCController then
        NPCController:ActivateNPC("DouDzouh", player)

        -- Ускоряем JOHN DOU для драматичного рывка
        douModel = NPCController:GetNPCModel("DouDzouh")
        if douModel then
            local douHum = douModel:FindFirstChildOfClass("Humanoid")
            if douHum then douHum.WalkSpeed = 34 end
        end

        NPCController:TeleportNPCTo("DouDzouh", douDzouhSpawnPos)
        task.wait(0.1)
        NPCController:MoveNPCTo("DouDzouh", intercept)
    end

    local startedWait = tick()
    while tick() - startedWait < 1.6 do
        wolfRoot = wolfRoot or ambushWolf.PrimaryPart or ambushWolf:FindFirstChildWhichIsA("BasePart")
        local douRoot = douModel and (douModel.PrimaryPart or douModel:FindFirstChild("HumanoidRootPart"))
        if douRoot then
            local wolfPos = wolfRoot and wolfRoot.Position or intercept
            local douAtIntercept = (douRoot.Position - intercept).Magnitude <= 5
            local wolfAtIntercept = (wolfPos - intercept).Magnitude <= 7
            local douNearWolf = (douRoot.Position - wolfPos).Magnitude <= 8
            if douNearWolf or (douAtIntercept and wolfAtIntercept) then
                break
            end
        end
        task.wait(0.1)
    end

    -- 5. JOHN DOU «убивает» волка только после входа в точку перехвата.
    print("[CutsceneManager] JOHN DOU убивает волка!")
    if wolfHumanoid and wolfRoot then
        wolfHumanoid:MoveTo(wolfRoot.Position)
    end
    if wolfHumanoid then
        wolfHumanoid.Health = 0
    end

    -- Золотая вспышка удара
    wolfRoot = wolfRoot or ambushWolf.PrimaryPart
    if wolfRoot then
        local flash = Instance.new("PointLight")
        flash.Color      = Color3.fromRGB(255, 200, 50)
        flash.Brightness = 5
        flash.Range      = 15
        flash.Parent     = wolfRoot
        task.delay(0.4, function() flash:Destroy() end)
    end

    task.wait(1.5)

    -- 6. Удаляем тушу волка (async)
    task.delay(1.5, function()
        if ambushWolf and ambushWolf.Parent then
            ambushWolf:Destroy()
        end
    end)

    -- 7. JOHN DOU подходит к игроку для разговора
    if NPCController then
        local talkPos = Vector3.new(
            (playerPos - lookVec * 4 + rightVec * 2).X,
            playerPos.Y,
            (playerPos - lookVec * 4 + rightVec * 2).Z
        )
        NPCController:MoveNPCTo("DouDzouh", talkPos)
    end

    Remotes:GetEvent("UpdateHUD"):FireClient(player, {
        Notification = "JOHN DOU спас тебя!"
    })

    task.wait(3)

    -- 8. Кат-сцена завершена
    Remotes:GetEvent("CutsceneFinished"):FireClient(player, "WOLF_AMBUSH")
    print("[CutsceneManager] WOLF_AMBUSH завершена")
    wolfAmbushDoneForPlayer[player.UserId] = true
end

-- ═══════════════════════════════════════════════════════════
-- УНИВЕРСАЛЬНЫЙ ЗАПУСК КАТ-СЦЕНЫ
-- Для WOLF_AMBUSH — используется кастомная логика (PlayWolfAmbush).
-- Для остальных — стандартная обработка:
-- 1. Отправляем камеру на клиент
-- 2. Выполняем NPC-действия по таймеру
-- 3. По завершении Duration — переход к следующей стадии
-- ═══════════════════════════════════════════════════════════
function CutsceneManager:PlayCutscene(player, cutsceneId)
    -- WOLF_AMBUSH имеет уникальную логику
    if cutsceneId == "WOLF_AMBUSH" then
        local uid = player.UserId
        if wolfAmbushDoneForPlayer[uid] then
            print("[CutsceneManager] WOLF_AMBUSH уже проиграна — повтор отклонён")
            return
        end
        if wolfAmbushRunning[uid] then
            print("[CutsceneManager] WOLF_AMBUSH уже выполняется — дубликат отклонён")
            return
        end
        wolfAmbushRunning[uid] = true
        task.spawn(function()
            local ok, err = pcall(function()
                self:PlayWolfAmbush(player)
            end)
            wolfAmbushRunning[uid] = nil
            if not ok then
                warn("[CutsceneManager] PlayWolfAmbush ошибка:", err)
            end
        end)
        return
    end

    -- Ищем определение кат-сцены
    local definition = cutsceneDefinitions[cutsceneId]
    if not definition then
        warn("[CutsceneManager] Кат-сцена не найдена:", cutsceneId)
        return
    end

    print("[CutsceneManager] Запуск кат-сцены:", cutsceneId)

    -- Отправляем данные камеры на клиент
    Remotes:GetEvent("StartCutscene"):FireClient(player, {
        Id = cutsceneId,
        Duration = definition.Duration,
        CameraPoints = definition.CameraPoints,
        DialogueId = definition.DialogueId,
    })

    -- Выполняем NPC-действия по расписанию
    task.spawn(function()
        for _, action in ipairs(definition.NPCActions or {}) do
            task.delay(action.Time, function()
                self:ExecuteNPCAction(action.NPC, action.Action, player)
            end)
        end
    end)

    -- Обработка завершения (через Duration секунд)
    task.delay(definition.Duration, function()
        print("[CutsceneManager] Кат-сцена завершена:", cutsceneId)

        -- Переход к следующей стадии (если указана)
        if definition.OnComplete == "CREDITS" then
            if _G.GameManager then
                _G.GameManager.SetStage(player, "CREDITS")
            end
        elseif definition.OnComplete == "BOSS_FIGHT" then
            print("[CutsceneManager] TODO: Начать бой с боссом")
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
-- ВЫПОЛНЕНИЕ NPC-ДЕЙСТВИЯ
-- Обрабатывает команды из NPCActions:
-- • FACE_PLAYER — повернуть NPC к игроку
-- • TAKE_HAMMER — забрать молот (TODO)
-- ═══════════════════════════════════════════════════════════
function CutsceneManager:ExecuteNPCAction(npcName, actionName, player)
    print("[CutsceneManager] NPC Action:", npcName, "→", actionName)

    if not NPCController then return end

    if actionName == "FACE_PLAYER" then
        -- Поворот NPC лицом к игроку
        local model = NPCController:GetNPCModel(npcName)
        if model and model.PrimaryPart then
            local character = player.Character
            if character and character:FindFirstChild("HumanoidRootPart") then
                local lookDir = (character.HumanoidRootPart.Position - model.PrimaryPart.Position)
                lookDir = Vector3.new(lookDir.X, 0, lookDir.Z).Unit
                -- Для anchored NPC — только логируем (CFrame поворот для anchored требует доработки)
                print("[CutsceneManager]", npcName, "смотрит на игрока")
            end
        end
    end
end

return CutsceneManager
