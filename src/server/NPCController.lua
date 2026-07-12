--[[
    NPCController — Управление NPC (создание, диалоги, AI следования)
    ═══════════════════════════════════════════════════════════
    
    Этот модуль управляет ВСЕМИ NPC в игре:
    • Старейшина (Elder) — стоит на месте, выдаёт квесты
    • JOHN DOU — может следовать за игроком (компаньон)
    • Торговец (Trader) — стоит на месте (пока не реализован)
    
    ФУНКЦИОНАЛЬНОСТЬ:
    ─────────────────
    1. Создание моделей NPC из Part-ов (тело + голова + имя BillboardGui)
    2. ProximityPrompt для взаимодействия (нажатие E рядом с NPC)
    3. Логика диалогов: начальный, продолжение, idle-фразы
    4. Отслеживание состояния диалога: heard/interrupted/lastStep
    5. AI следования (для компаньонов, как JOHN DOU)
    
    СИСТЕМА ДИАЛОГОВ:
    ─────────────────
    Для каждого игрока и NPC хранится dialogueState:
    • heard = false → покажем InitialDialogue (основной сюжетный диалог)
    • heard = true  → покажем idle-реплику (рандомная фраза)
    • interrupted   → покажем «вернулся? так вот...» + оставшиеся шаги
    
    Контент диалогов хранится в DialogueData.lua (общий модуль).
    
    ВАЖНО: Это ModuleScript (.lua), вызывается из GameManager.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ServerScriptService = game:GetService("ServerScriptService")
local DialogueData = require(ServerScriptService:WaitForChild("DialogueData"))
local StageWorldConfig = require(ServerScriptService:WaitForChild("StageWorldConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local NPCController = {}

-- ═══════════════════════════════════════════════════════════
-- АКТИВНЫЕ NPC
-- Все NPC, которые сейчас существуют в мире.
-- Формат: activeNPCs[npcId] = { Model, Definition, State }
-- State: "IDLE" — стоит на месте, "FOLLOWING" — следует за игроком
-- ═══════════════════════════════════════════════════════════
local activeNPCs = {}

-- ═══════════════════════════════════════════════════════════
-- СОСТОЯНИЕ ДИАЛОГОВ
-- Для каждого игрока (UserId) и каждого NPC хранится:
--   heard       — прослушал ли основной диалог полностью
--   lastStep    — на каком шаге остановился (если был прерван)
--   interrupted — был ли диалог прерван (отошёл во время разговора)
--
-- Формат: dialogueStates[userId][npcId] = { heard, lastStep, interrupted, thanksHeard }
-- thanksHeard (только Elder) — ELDER_THANKS уже пройден; не показывать блок снова на JOHN_RESCUE
-- ═══════════════════════════════════════════════════════════
local dialogueStates = {}

-- ═══════════════════════════════════════════════════════════
-- ОПРЕДЕЛЕНИЯ NPC
-- Статические данные о каждом NPC: имя, позиция, внешний вид,
-- поведение и начальный диалог.
-- ═══════════════════════════════════════════════════════════
-- Определения NPC — из StageWorldConfig.NPCs (редактируйте там)
local NPC_DEFINITIONS = StageWorldConfig.NPCs

-- ═══════════════════════════════════════════════════════════
-- СОЗДАНИЕ МОДЕЛИ NPC
-- Строит NPC из Part-ов: тело, голова, имя (BillboardGui),
-- Humanoid (для HP) и ProximityPrompt (для взаимодействия).
-- Если в definition указан ModelName, пытается загрузить
-- готовую модель из ServerStorage.
--
-- Параметр: definition — таблица из NPC_DEFINITIONS
-- Возвращает: Model с ProximityPrompt внутри
-- ═══════════════════════════════════════════════════════════
local function setModelAnchored(model: Model, anchored: boolean)
    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("BasePart") then
            inst.Anchored = anchored
        end
    end
end

local function createNPCModel(npcId, definition)
    local model
    
    -- Пробуем загрузить готовую модель из ServerStorage
    if definition.ModelName then
        local ServerStorage = game:GetService("ServerStorage")
        local template = ServerStorage:FindFirstChild(definition.ModelName)
        print("[NPCController] Ищем кастомную модель в ServerStorage:", definition.ModelName, "Найдена:", template ~= nil)
        if template then
            model = template:Clone()
            model.Name = npcId
            
            -- Размещаем модель в стартовой позиции
            if model.PrimaryPart then
                model:PivotTo(CFrame.new(definition.Position))
            else
                -- Fallback если PrimaryPart не задан
                local hrp = model:FindFirstChild("HumanoidRootPart")
                if hrp then
                    model.PrimaryPart = hrp
                    model:PivotTo(CFrame.new(definition.Position))
                end
            end
        end
    end

    -- Если модель не найдена или не указана, генерируем базовую из Part-ов
    if not model then
        model = Instance.new("Model")
        model.Name = npcId

        -- ─── ТЕЛО ───
        local body = Instance.new("Part")
        body.Name = "HumanoidRootPart"            -- стандартное имя для Humanoid
        body.Size = definition.Size
        body.Color = definition.BodyColor
        body.Position = definition.Position
        body.Anchored = true                      -- NPC стоит на месте (не падает)
        body.CanCollide = true
        body.Parent = model

        -- ─── ГОЛОВА ───
        local head = Instance.new("Part")
        head.Name = "Head"
        head.Shape = Enum.PartType.Ball           -- круглая голова
        head.Size = Vector3.new(1.8, 1.8, 1.8)
        head.Color = Color3.fromRGB(220, 190, 160) -- кожный цвет
        head.Position = definition.Position + Vector3.new(0, definition.Size.Y / 2 + 1, 0)
        head.Anchored = true
        head.Parent = model

        -- Скрепляем голову с телом, чтобы при движении они не разлетались
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = body
        weld.Part1 = head
        weld.Parent = body

        model.PrimaryPart = body
    end

    -- ─── ИМЯ НАД ГОЛОВОЙ (BillboardGui) ───
    local head = model:FindFirstChild("Head")
    if not head then
        -- Если у скачанной модели нет Head, привязываем к PrimaryPart с отступом выше
        head = model.PrimaryPart
    end
    
    if head and not head:FindFirstChild("NameTag") then
        local billboardGui = Instance.new("BillboardGui")
        billboardGui.Name = "NameTag"
        billboardGui.Size = UDim2.new(4, 0, 1, 0)        -- 4 стада шириной
        
        -- Если привязали к телу, а не к голове, смещаем выше
        if head.Name == "HumanoidRootPart" then
            billboardGui.StudsOffset = Vector3.new(0, 4, 0)
        else
            billboardGui.StudsOffset = Vector3.new(0, 3, 0)   -- 3 стада над головой
        end
        
        billboardGui.Adornee = head                        -- привязываем
        billboardGui.Parent = head

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "NameLabel"
        nameLabel.Size = UDim2.new(1, 0, 1, 0)
        nameLabel.BackgroundTransparency = 1               -- прозрачный фон
        nameLabel.Text = definition.Name
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255) -- белый текст
        nameLabel.TextStrokeTransparency = 0               -- чёрная обводка (читабельность)
        nameLabel.TextScaled = true
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Parent = billboardGui
    end

    -- ─── HUMANOID ───
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        humanoid = Instance.new("Humanoid")
        humanoid.Parent = model
    end
    humanoid.MaxHealth = 1000
    humanoid.Health = 1000

    -- ─── PROXIMITYPROMPT (кнопка E для разговора) ───
    local body = model.PrimaryPart
    if body and not body:FindFirstChild("TalkPrompt") then
        local prompt = Instance.new("ProximityPrompt")
        prompt.Name = "TalkPrompt"
        prompt.ActionText = "Говорить"              -- текст на кнопке
        prompt.ObjectText = definition.Name         -- название объекта
        prompt.MaxActivationDistance = 10            -- дальность активации (стады)
        prompt.HoldDuration = 0                     -- не нужно зажимать
        prompt.Parent = body
    end

    return model
end

-- ═══════════════════════════════════════════════════════════
-- ПОЛУЧИТЬ СОСТОЯНИЕ ДИАЛОГА
-- Возвращает (или создаёт) состояние диалога для пары игрок+NPC.
-- Это позволяет отслеживать, слушал ли игрок диалог ранее.
-- ═══════════════════════════════════════════════════════════
local function getDialogueState(player, npcId)
    local userId = tostring(player.UserId)
    if not dialogueStates[userId] then
        dialogueStates[userId] = {}
    end
    if not dialogueStates[userId][npcId] then
        dialogueStates[userId][npcId] = {
            heard = false,          -- основной диалог ещё не прослушан
            lastStep = 0,           -- на каком шаге остановились
            interrupted = false,    -- был ли прерван
            thanksHeard = false,    -- Elder: сцена благодарности после волков уже сыграна
        }
    end
    return dialogueStates[userId][npcId]
end

-- ═══════════════════════════════════════════════════════════
-- ПОЛУЧИТЬ СТАДИЮ ИГРОКА
-- Обращается к GameManager через _G для определения текущей стадии.
-- ═══════════════════════════════════════════════════════════
local function getPlayerStage(player)
    if _G.GameManager and _G.GameManager.GetPlayerState then
        local state = _G.GameManager.GetPlayerState(player)
        if state then return state.Stage end
    end
    return "SPAWN"  -- по умолчанию
end

-- ═══════════════════════════════════════════════════════════
-- РАНДОМНАЯ РЕПЛИКА ИЗ СПИСКА
-- Выбирает случайную строку из массива. Используется для idle-реплик.
-- ═══════════════════════════════════════════════════════════
local function getRandomLine(lines)
    if not lines or #lines == 0 then return nil end
    return lines[math.random(1, #lines)]
end

-- ═══════════════════════════════════════════════════════════
-- АКТИВАЦИЯ NPC
-- Создаёт модель NPC в мире (если ещё не создана)
-- и подключает ProximityPrompt для взаимодействия.
--
-- Параметры:
--   npcId (string)  — ID из NPC_DEFINITIONS ("Elder", "DouDzouh", "Trader")
--   player (Player) — игрок, для которого активируется NPC
-- ═══════════════════════════════════════════════════════════
function NPCController:ActivateNPC(npcId, player)
    local definition = NPC_DEFINITIONS[npcId]
    if not definition then
        warn("[NPCController] NPC не найден:", npcId)
        return
    end

    -- Если NPC уже создан — не создаём дубликат
    if not activeNPCs[npcId] then
        local model = createNPCModel(npcId, definition)

        -- Создаём папку NPCs в Workspace (если нет)
        local npcsFolder = Workspace:FindFirstChild("NPCs")
        if not npcsFolder then
            npcsFolder = Instance.new("Folder")
            npcsFolder.Name = "NPCs"
            npcsFolder.Parent = Workspace
        end
        model.Parent = npcsFolder

        activeNPCs[npcId] = {
            Model = model,
            Definition = definition,
            State = "IDLE",              -- начальное состояние
        }

        -- Подключаем ProximityPrompt
        local body = model.PrimaryPart
        if body then
            local prompt = body:FindFirstChild("TalkPrompt")
            if prompt then
                prompt.Triggered:Connect(function(triggerPlayer)
                    self:OnNPCInteract(npcId, triggerPlayer)
                end)
            end
        end

        print("[NPCController] NPC активирован:", definition.Name)
    end
end

-- ═══════════════════════════════════════════════════════════
-- ОБРАБОТКА ВЗАИМОДЕЙСТВИЯ С NPC
-- Вызывается при нажатии ProximityPrompt (кнопка E).
-- Определяет, какой диалог показать, на основе:
--   1. Какой NPC (Elder/DouDzouh/Trader)
--   2. Текущая стадия игры (SPAWN/WOLF_HUNT/JOHN_RESCUE...)
--   3. Был ли основной диалог уже прослушан (heard)
--   4. Был ли прерван (interrupted)
-- ═══════════════════════════════════════════════════════════
function NPCController:OnNPCInteract(npcId, player)
    local npc = activeNPCs[npcId]
    if not npc then return end

    local dState = getDialogueState(player, npcId)
    local definition = npc.Definition

    print("[NPCController] Взаимодействие:", definition.Name, "с", player.Name,
        "| Heard:", dState.heard, "| LastStep:", dState.lastStep)

    -- ═══════════════════════════════════════
    -- ЛОГИКА СТАРЕЙШИНЫ (Elder)
    -- Стадия проверяется ПЕРВОЙ — это ключевое правило.
    -- heard/interrupted используются только внутри стадий SPAWN/WOLF_HUNT.
    -- ═══════════════════════════════════════
    if npcId == "Elder" then
        local stage = getPlayerStage(player)

        -- Приоритет 1: JOHN_RESCUE — всегда ELDER_THANKS, независимо от heard.
        -- Без этого условия Elder показывал бы ELDER_QUEST_START снова и снова,
        -- если dState.heard = false по любой причине (баг, сброс, тест-сессия).
        if stage == "JOHN_RESCUE" then
            -- Один раз: блок благодарности → кат-сцена. Повторный клик без этого дал бы
            -- тот же ELDER_THANKS с репликой «Мне нужно кое-что сказать—» по кругу.
            if dState.thanksHeard then
                local line = getRandomLine(DialogueData.ElderIdleLines.AfterWolves)
                    or getRandomLine(DialogueData.ElderIdleLines.Default)
                if line then
                    Remotes:GetEvent("ShowDialogue"):FireClient(player, {
                        DialogueId = "ELDER_IDLE_POST_THANKS",
                        Steps = { line },
                        NPCName = definition.Name,
                    })
                end
            else
                Remotes:GetEvent("ShowDialogue"):FireClient(player, DialogueData.BuildShowPayload("ELDER_THANKS", {
                    NPCName = definition.Name,
                    TrackNPC = "Elder_Thanks",
                }))
            end

        -- Приоритет 2: начальный диалог (SPAWN / первый запуск)
        elseif not dState.heard then
            local dialogueId = definition.InitialDialogue
            local steps = DialogueData.Dialogues[dialogueId]

            if dState.lastStep > 0 and dState.interrupted then
                -- Прерванный диалог: «вернулся?» + оставшиеся шаги
                local resumeLine = getRandomLine(DialogueData.ElderResumeLines)
                local remainingSteps = {}
                if resumeLine then
                    table.insert(remainingSteps, resumeLine)
                end
                for i = dState.lastStep, #steps do
                    table.insert(remainingSteps, steps[i])
                end
                Remotes:GetEvent("ShowDialogue"):FireClient(player, {
                    DialogueId = dialogueId .. "_RESUME",
                    Steps = remainingSteps,
                    NPCName = definition.Name,
                    TrackNPC = npcId,
                    TotalSteps = #remainingSteps,
                })
            else
                -- Первый разговор
                Remotes:GetEvent("ShowDialogue"):FireClient(player, DialogueData.BuildShowPayload(dialogueId, {
                    NPCName = definition.Name,
                    TrackNPC = npcId,
                }))
            end

        -- Приоритет 3: idle-реплики на остальных стадиях
        else
            local idleLines
            if stage == "WOLF_HUNT" then
                idleLines = DialogueData.ElderIdleLines.WolfHunt
            elseif stage == "BAD_NEWS" or stage == "SECRET_MAP" or stage == "FOREST_JOURNEY"
                or stage == "SWAMP_JOURNEY" then
                idleLines = DialogueData.ElderIdleLines.AfterWolves
            else
                idleLines = DialogueData.ElderIdleLines.Default
            end

            local line = getRandomLine(idleLines)
            if line then
                Remotes:GetEvent("ShowDialogue"):FireClient(player, {
                    DialogueId = "ELDER_IDLE",
                    Steps = { line },
                    NPCName = definition.Name,
                })
            end
        end
        return
    end

    -- ═══════════════════════════════════════
    -- ЛОГИКА DOU DZOUH
    -- Стадия проверяется первой.
    -- JOHN_RESCUE: вводный диалог (даже если heard = true — на случай повтора).
    -- Остальные стадии: idle или ничего.
    -- ═══════════════════════════════════════
    if npcId == "DouDzouh" then
        local stage = getPlayerStage(player)

        if stage == "JOHN_RESCUE" then
            -- После WOLF_AMBUSH: всегда показываем вводный диалог,
            -- пока heard = false. Как только heard = true — idle.
            if not dState.heard then
                Remotes:GetEvent("ShowDialogue"):FireClient(player, DialogueData.BuildShowPayload(definition.InitialDialogue, {
                    NPCName = definition.Name,
                    TrackNPC = npcId,
                }))
            else
                -- Уже поговорили — повторный подход, ждём BAD_NEWS
                local line = getRandomLine(DialogueData.DouDzouhIdleLines)
                if line then
                    Remotes:GetEvent("ShowDialogue"):FireClient(player, {
                        DialogueId = "DOU_DZOUH_IDLE",
                        Steps = { line },
                        NPCName = definition.Name,
                    })
                end
            end
        else
            -- Все остальные стадии: idle-реплики
            local line = getRandomLine(DialogueData.DouDzouhIdleLines)
            if line then
                Remotes:GetEvent("ShowDialogue"):FireClient(player, {
                    DialogueId = "DOU_DZOUH_IDLE",
                    Steps = { line },
                    NPCName = definition.Name,
                })
            end
        end
        return
    end

    -- ═══════════════════════════════════════
    -- ЛОГИКА ОСТАЛЬНЫХ NPC (Торговец и т.д.)
    -- Если есть InitialDialogue → показываем или idle
    -- ═══════════════════════════════════════
    local dialogueId = definition.InitialDialogue
    if dialogueId then
        if dState.heard then
            -- Уже поговорили
            local defaultLine = {
                { Speaker = definition.Name, Text = "Мы уже обо всём поговорили." }
            }
            Remotes:GetEvent("ShowDialogue"):FireClient(player, {
                DialogueId = npcId .. "_IDLE",
                Steps = defaultLine,
                NPCName = definition.Name,
            })
        else
            -- Первый разговор
            Remotes:GetEvent("ShowDialogue"):FireClient(player, DialogueData.BuildShowPayload(definition.InitialDialogue, {
                NPCName = definition.Name,
                TrackNPC = npcId,
            }))
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- ОТМЕТИТЬ ДИАЛОГ КАК ЗАВЕРШЁННЫЙ
-- Вызывается из GameManager после получения "DIALOGUE_FINISHED".
-- После этого NPC будет говорить только idle-реплики.
-- ═══════════════════════════════════════════════════════════
function NPCController:MarkDialogueComplete(player, npcId)
    local dState = getDialogueState(player, npcId)
    dState.heard = true
    dState.interrupted = false
    dState.lastStep = 0
    print("[NPCController] Диалог завершён:", npcId, "для", player.Name)
end

--- После ELDER_THANKS (игрок услышал благодарность до кат-сцены) — не показывать блок повторно.
function NPCController:MarkElderThanksHeard(player)
    local dState = getDialogueState(player, "Elder")
    dState.thanksHeard = true
    print("[NPCController] ELDER_THANKS отмечен для", player.Name)
end

-- ═══════════════════════════════════════════════════════════
-- ОТМЕТИТЬ ПРЕРВАННЫЙ ДИАЛОГ
-- Если игрок отошёл во время разговора — запоминаем, на каком шаге остановился.
-- При следующем взаимодействии — покажем «вернулся?» + оставшиеся шаги.
-- ═══════════════════════════════════════════════════════════
function NPCController:MarkDialogueInterrupted(player, npcId, stepIndex)
    local dState = getDialogueState(player, npcId)
    dState.interrupted = true
    dState.lastStep = stepIndex
    print("[NPCController] Диалог прерван на шаге", stepIndex, ":", npcId)
end

local INTEREST_NAME_PATTERNS = {
    "map",
    "letter",
    "note",
    "book",
    "chest",
    "loot",
    "item",
    "pickup",
    "artifact",
    "hammer",
    "pedestal",
    "well",
    "house",
    "door",
    "trap",
    "torch",
    "entrance",
    "portal",
    "rock",
    "bush",
    "tree",
}

local function flatUnit(vector, fallback)
    local flat = Vector3.new(vector.X, 0, vector.Z)
    if flat.Magnitude <= 0.001 then
        return fallback or Vector3.new(0, 0, -1)
    end
    return flat.Unit
end

local function flatDistanceXZ(a, b)
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function isCompanionInterest(instance)
    if not instance:IsA("BasePart") then
        return false
    end

    local name = string.lower(instance.Name)
    for _, pattern in ipairs(INTEREST_NAME_PATTERNS) do
        if string.find(name, pattern, 1, true) then
            return true
        end
    end

    return instance:FindFirstChild("ProximityPrompt") ~= nil
        or instance:FindFirstChild("ClickDetector") ~= nil
end

local function findNearbyInterestPoint(playerPosition, npcPosition, radius)
    local bestPart = nil
    local bestScore = math.huge

    for _, instance in ipairs(Workspace:GetDescendants()) do
        if isCompanionInterest(instance) then
            local fromPlayer = (instance.Position - playerPosition).Magnitude
            local fromNpc = (instance.Position - npcPosition).Magnitude
            if fromPlayer <= radius and fromNpc >= 7 then
                local score = fromPlayer + math.random(0, 10)
                if score < bestScore then
                    bestScore = score
                    bestPart = instance
                end
            end
        end
    end

    if bestPart then
        return bestPart.Position + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
    end

    return nil
end

local function chooseCompanionPatrolPoint(rootPart, definition)
    local playerPos = rootPart.Position
    local lookVec = flatUnit(rootPart.CFrame.LookVector, Vector3.new(0, 0, -1))
    local rightVec = flatUnit(rootPart.CFrame.RightVector, Vector3.new(1, 0, 0))

    local side = (math.random(0, 1) == 0 and -1 or 1) * math.random(5, 13)
    local back = math.random(definition.MinFollowDistance or 5, (definition.FollowDistance or 8) + 9)
    local ahead = math.random(-5, 8)

    return playerPos - lookVec * back + rightVec * side + lookVec * ahead
end

-- ═══════════════════════════════════════════════════════════
-- УСТАНОВИТЬ NPC КАК КОМПАНЬОНА (AI следования)
-- NPC начинает следовать за игроком. Каждые 0.5 сек проверяет
-- расстояние и если оно > FollowDistance — двигается к игроку.
--
-- Работает только для NPC с Behavior = "FOLLOWER" и FollowDistance.
-- Для начала следования: body.Anchored → false (иначе не сдвинется).
-- ═══════════════════════════════════════════════════════════
function NPCController:SetCompanion(npcId, player)
    local npc = activeNPCs[npcId]
    if not npc then
        self:ActivateNPC(npcId, player)
        npc = activeNPCs[npcId]
    end
    if not npc then return end
    if not npc.Definition.FollowDistance then return end

    npc.State = "FOLLOWING"
    npc.CompanionToken = {}
    local model = npc.Model
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local body = model.PrimaryPart

    if not humanoid or not body then return end

    -- Снимаем якорь со всех частей: у сгенерированной модели Head тоже welded к телу.
    setModelAnchored(model, false)
    print("[NPCController] Компаньон установлен:", npc.Definition.Name)

    local companionToken = npc.CompanionToken
    local currentTarget = nil
    local nextDecisionAt = 0
    local definition = npc.Definition
    local followDistance = definition.FollowDistance or 8
    local minDistance = definition.MinFollowDistance or math.max(4, followDistance - 3)
    local maxDistance = definition.MaxFollowDistance or followDistance * 2.5
    local inspectRadius = definition.InspectRadius or 30
    local inspectChance = definition.InspectChance or 0.35

    -- Компаньон держится рядом, но не копирует след игрока: иногда осматривает окружение.
    task.spawn(function()
        while npc.State == "FOLLOWING" and npc.CompanionToken == companionToken do
            local character = player.Character
            if character and character:FindFirstChild("HumanoidRootPart") then
                local rootPart = character.HumanoidRootPart
                local playerPos = rootPart.Position
                local distance = (body.Position - playerPos).Magnitude
                local now = tick()

                if distance > maxDistance then
                    local lookVec = flatUnit(rootPart.CFrame.LookVector, Vector3.new(0, 0, -1))
                    local rightVec = flatUnit(rootPart.CFrame.RightVector, Vector3.new(1, 0, 0))
                    currentTarget = playerPos - lookVec * followDistance + rightVec * math.random(-8, 8)
                    nextDecisionAt = now + 1
                    humanoid.WalkSpeed = math.max(humanoid.WalkSpeed, 18)
                elseif not currentTarget
                    or (body.Position - currentTarget).Magnitude <= minDistance
                    or now >= nextDecisionAt then

                    local shouldInspect = math.random() < inspectChance
                    if shouldInspect then
                        currentTarget = findNearbyInterestPoint(playerPos, body.Position, inspectRadius)
                    end

                    if not currentTarget then
                        currentTarget = chooseCompanionPatrolPoint(rootPart, definition)
                    end

                    nextDecisionAt = now + math.random(2, 5)
                end

                if currentTarget and (body.Position - currentTarget).Magnitude > 3 then
                    humanoid:MoveTo(currentTarget)
                end
            end
            task.wait(0.65)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
-- ОСТАНОВИТЬ СЛЕДОВАНИЕ
-- Переводит NPC из состояния FOLLOWING обратно в IDLE.
-- Цикл AI в SetCompanion остановится сам (проверяет npc.State).
-- ═══════════════════════════════════════════════════════════
function NPCController:StopCompanion(npcId)
    local npc = activeNPCs[npcId]
    if npc then
        npc.CompanionToken = nil
        npc.State = "IDLE"
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПРОВОДНИК ПО МАРШРУТУ (болото: кочки)
-- Dou идёт впереди по waypoints и ждёт игрока на каждой кочке.
-- ═══════════════════════════════════════════════════════════
function NPCController:SetGuide(npcId, player, waypoints, options)
    options = options or {}
    local npc = activeNPCs[npcId]
    if not npc then
        self:ActivateNPC(npcId, player)
        npc = activeNPCs[npcId]
    end
    if not npc or not waypoints or #waypoints == 0 then
        return
    end

    self:StopCompanion(npcId)
    npc.State = "GUIDING"

    local model = npc.Model
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local body = model.PrimaryPart
    if not humanoid or not body then
        return
    end

    setModelAnchored(model, false)
    local waitRadius = options.waitRadius or 14
    local moveTimeout = options.moveTimeout or 25
    local guideToken = {}
    npc.GuideToken = guideToken

    task.spawn(function()
        for index, targetPos in ipairs(waypoints) do
            if npc.State ~= "GUIDING" or npc.GuideToken ~= guideToken then
                return
            end

            humanoid:MoveTo(targetPos)
            local reached = false
            local conn = humanoid.MoveToFinished:Connect(function(ok)
                reached = ok
            end)

            local deadline = tick() + moveTimeout
            while tick() < deadline do
                if npc.State ~= "GUIDING" or npc.GuideToken ~= guideToken then
                    conn:Disconnect()
                    return
                end
                if (body.Position - targetPos).Magnitude <= 4 then
                    reached = true
                    break
                end
                task.wait(0.15)
            end
            conn:Disconnect()

            if options.onStepReached then
                options.onStepReached(index, targetPos)
            end

            Remotes:GetEvent("UpdateHUD"):FireClient(player, {
                Notification = string.format("🌿 Кочка %d/%d — прыгай сюда!", index, #waypoints),
            })

            while npc.State == "GUIDING" and npc.GuideToken == guideToken do
                local character = player.Character
                local hrp = character and character:FindFirstChild("HumanoidRootPart")
                if hrp and flatDistanceXZ(hrp.Position, targetPos) <= waitRadius then
                    break
                end
                task.wait(0.25)
            end
        end

        if npc.State == "GUIDING" and npc.GuideToken == guideToken then
            npc.State = "IDLE"
            if options.onComplete then
                options.onComplete()
            end
        end
    end)

    print("[NPCController] Проводник:", npc.Definition.Name, "| точек:", #waypoints)
end

function NPCController:StopGuide(npcId)
    local npc = activeNPCs[npcId]
    if npc then
        npc.GuideToken = nil
        npc.State = "IDLE"
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПОЛУЧИТЬ МОДЕЛЬ NPC
-- Возвращает Model или nil. Используется CutsceneManager.
-- ═══════════════════════════════════════════════════════════
function NPCController:GetNPCModel(npcId)
    local npc = activeNPCs[npcId]
    return npc and npc.Model or nil
end

-- ═══════════════════════════════════════════════════════════
-- ПЕРЕМЕСТИТЬ NPC В ПОЗИЦИЮ (ПЕШКОМ)
-- Заставляет NPC идти к указанной точке с помощью Humanoid:MoveTo.
-- ═══════════════════════════════════════════════════════════
function NPCController:MoveNPCTo(npcId, position)
    local npc = activeNPCs[npcId]
    if not npc then return end
    
    local model = npc.Model
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local body = model.PrimaryPart
    
    if humanoid and body then
        -- Снимаем якорь только с PrimaryPart — остальные части скреплены Weld-ами
        -- и последуют за ним автоматически
        setModelAnchored(model, false)
        print("[NPCController] Двигаем NPC", npcId, "с помощью MoveTo к", position)
        humanoid:MoveTo(position)
    else
        warn("[NPCController] Нет humanoid или body у", npcId, "для MoveTo")
    end
end

-- ═══════════════════════════════════════════════════════════
-- ТЕЛЕПОРТИРОВАТЬ NPC В ПОЗИЦИЮ (МГНОВЕННО)
-- Мгновенно телепортирует NPC.
-- ═══════════════════════════════════════════════════════════
function NPCController:TeleportNPCTo(npcId, position)
    local npc = activeNPCs[npcId]
    if not npc then return end

    local model = npc.Model
    local body = model.PrimaryPart
    if not body then return end

    -- Якорим перед телепортом — физика не будет бороться с перемещением.
    -- PivotTo корректно сдвигает всю модель целиком (благодаря WeldConstraint-ам).
    -- Якорь снимет MoveNPCTo при следующем вызове.
    setModelAnchored(model, true)
    model:PivotTo(CFrame.new(position))
end

-- ═══════════════════════════════════════════════════════════
-- ОЧИСТКА ПРИ ОТКЛЮЧЕНИИ ИГРОКА
-- Удаляем состояние диалогов этого игрока (освобождаем память).
-- Модели NPC НЕ удаляются — они общие для всех игроков.
-- ═══════════════════════════════════════════════════════════
function NPCController:OnPlayerLeaving(player)
    local userId = tostring(player.UserId)
    dialogueStates[userId] = nil
end

return NPCController
