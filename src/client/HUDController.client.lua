--[[
    HUDController — Игровой HUD (Head-Up Display)
    ═══════════════════════════════════════════════════════════
    
    Клиентский скрипт, отображающий игровую информацию на экране:
    • Квестовый трекер (правый верхний угол) — название и цель квеста
    • Счётчик монет (левый верхний угол) — количество золота
    • Уведомления (центр верха) — временные сообщения с fade-out
    • Смена стадии — отображение названия новой локации
    
    СТРУКТУРА UI (ScreenGui "GameHUD"):
    ────────────────────────────────────
    GameHUD (ScreenGui, DisplayOrder=10)
    ├── QuestTracker (Frame, верхний правый)
    │   ├── QuestTitle (TextLabel)      — "📜 Найти Старейшину"
    │   └── QuestObjective (TextLabel)  — "Поговорите со Старейшиной"
    ├── MoneyDisplay (Frame, верхний левый)
    │   └── MoneyLabel (TextLabel)      — "🪙 150"
    ├── StageDisplay (Frame, верх центр) — постоянная фаза сюжета
    │   ├── StageTitle (TextLabel)       — читаемое имя
    │   └── StageId (TextLabel)          — идентификатор стадии
    └── Notification (TextLabel, центр) — временное сообщение
    
    ПОДПИСКИ НА REMOTE EVENTS:
    ──────────────────────────
    • QuestStarted  → показать новый квест в трекере
    • QuestUpdated   → обновить прогресс (X/Y)
    • QuestCompleted → уведомление «✅ Квест завершён: ...»
    • UpdateHUD      → обновить монеты и/или показать уведомление
    • WolfKilled     → показать лут убитого волка
    • StageChanged   → показать название новой локации
    
    ВАЖНО: Это LocalScript (.client.lua), работает ТОЛЬКО на клиенте.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local HUDController = {}

-- Читаемые названия фаз (синхронизировано с GameConfig.GameStages)
local STAGE_DISPLAY_NAMES = {
    SPAWN = "Деревня",
    WOLF_HUNT = "Окрестности — охота",
    JOHN_RESCUE = "Встреча с JOHN DOU",
    BAD_NEWS = "Плохие новости",
    SECRET_MAP = "Тайна деда",
    FOREST_JOURNEY = "Тёмный лес",
    SWAMP_JOURNEY = "Ядовитое болото",
    MINI_BOSS = "Гидра — арена",
    TOMB_MAZE = "Гробница",
    BAN_HAMMER = "Зал артефакта",
    FINALE = "Финал",
    CREDITS = "Титры",
}

-- ═══════════════════════════════════════════════════════════
-- СОЗДАНИЕ HUD
-- Строит всю UI-иерархию из Instance.new() вызовов.
-- Проверяет, нет ли уже созданного HUD (idempotent).
-- ═══════════════════════════════════════════════════════════
local function createHUD()
    -- Не создаём дубликат
    local existing = playerGui:FindFirstChild("GameHUD")
    if existing then return existing end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "GameHUD"
    screenGui.IgnoreGuiInset = true   -- игнорирует TopBar Roblox
    screenGui.DisplayOrder = 10       -- ниже диалогов (50) и кат-сцен (100)
    screenGui.Parent = playerGui

    -- ═══════════════════════════════════════
    -- КВЕСТОВЫЙ ТРЕКЕР (верхний правый угол)
    -- Полупрозрачный фрейм с фиолетовой обводкой
    -- ═══════════════════════════════════════
    local questFrame = Instance.new("Frame")
    questFrame.Name = "QuestTracker"
    questFrame.Size = UDim2.new(0.25, 0, 0.15, 0)       -- 25% ширины, 15% высоты
    questFrame.Position = UDim2.new(0.73, 0, 0.02, 0)   -- верхний правый
    questFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    questFrame.BackgroundTransparency = 0.3
    questFrame.BorderSizePixel = 0
    questFrame.Parent = screenGui

    local questCorner = Instance.new("UICorner")
    questCorner.CornerRadius = UDim.new(0, 10)
    questCorner.Parent = questFrame

    local questStroke = Instance.new("UIStroke")
    questStroke.Color = Color3.fromRGB(100, 80, 150)     -- фиолетовая обводка
    questStroke.Thickness = 1
    questStroke.Parent = questFrame

    -- Заголовок квеста (жёлтый, жирный)
    local questTitle = Instance.new("TextLabel")
    questTitle.Name = "QuestTitle"
    questTitle.Size = UDim2.new(0.9, 0, 0.35, 0)
    questTitle.Position = UDim2.new(0.05, 0, 0.05, 0)
    questTitle.BackgroundTransparency = 1
    questTitle.TextColor3 = Color3.fromRGB(255, 220, 100)
    questTitle.TextScaled = true
    questTitle.TextXAlignment = Enum.TextXAlignment.Left
    questTitle.Font = Enum.Font.GothamBold
    questTitle.Text = "📜 Квест"
    questTitle.Parent = questFrame

    -- Описание цели квеста (серый)
    local questObjective = Instance.new("TextLabel")
    questObjective.Name = "QuestObjective"
    questObjective.Size = UDim2.new(0.9, 0, 0.5, 0)
    questObjective.Position = UDim2.new(0.05, 0, 0.4, 0)
    questObjective.BackgroundTransparency = 1
    questObjective.TextColor3 = Color3.fromRGB(200, 200, 210)
    questObjective.TextScaled = true
    questObjective.TextWrapped = true
    questObjective.TextXAlignment = Enum.TextXAlignment.Left
    questObjective.Font = Enum.Font.Gotham
    questObjective.Text = "Ожидание..."
    questObjective.Parent = questFrame

    -- ═══════════════════════════════════════
    -- СЧЁТЧИК МОНЕТ (верхний левый угол)
    -- ═══════════════════════════════════════
    local moneyFrame = Instance.new("Frame")
    moneyFrame.Name = "MoneyDisplay"
    moneyFrame.Size = UDim2.new(0.12, 0, 0.04, 0)
    moneyFrame.Position = UDim2.new(0.02, 0, 0.02, 0)
    moneyFrame.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
    moneyFrame.BackgroundTransparency = 0.3
    moneyFrame.BorderSizePixel = 0
    moneyFrame.Parent = screenGui

    local moneyCorner = Instance.new("UICorner")
    moneyCorner.CornerRadius = UDim.new(0, 8)
    moneyCorner.Parent = moneyFrame

    local moneyLabel = Instance.new("TextLabel")
    moneyLabel.Name = "MoneyLabel"
    moneyLabel.Size = UDim2.new(0.9, 0, 0.9, 0)
    moneyLabel.Position = UDim2.new(0.05, 0, 0.05, 0)
    moneyLabel.BackgroundTransparency = 1
    moneyLabel.TextColor3 = Color3.fromRGB(255, 200, 50) -- золотой
    moneyLabel.TextScaled = true
    moneyLabel.Font = Enum.Font.GothamBold
    moneyLabel.Text = "🪙 0"
    moneyLabel.Parent = moneyFrame

    -- ═══════════════════════════════════════
    -- ФАЗА СЮЖЕТА (верх по центру, всегда видна)
    -- ═══════════════════════════════════════
    local stageFrame = Instance.new("Frame")
    stageFrame.Name = "StageDisplay"
    stageFrame.Size = UDim2.new(0.34, 0, 0.06, 0)
    stageFrame.Position = UDim2.new(0.33, 0, 0.02, 0)
    stageFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 35)
    stageFrame.BackgroundTransparency = 0.15
    stageFrame.BorderSizePixel = 0
    stageFrame.Parent = screenGui

    local stageCorner = Instance.new("UICorner")
    stageCorner.CornerRadius = UDim.new(0, 10)
    stageCorner.Parent = stageFrame

    local stageStroke = Instance.new("UIStroke")
    stageStroke.Color = Color3.fromRGB(70, 120, 180)
    stageStroke.Thickness = 1
    stageStroke.Parent = stageFrame

    local stageTitle = Instance.new("TextLabel")
    stageTitle.Name = "StageTitle"
    stageTitle.Size = UDim2.new(0.92, 0, 0.52, 0)
    stageTitle.Position = UDim2.new(0.04, 0, 0.08, 0)
    stageTitle.BackgroundTransparency = 1
    stageTitle.TextColor3 = Color3.fromRGB(220, 235, 255)
    stageTitle.TextScaled = true
    stageTitle.Font = Enum.Font.GothamBold
    stageTitle.TextXAlignment = Enum.TextXAlignment.Center
    stageTitle.Text = "Фаза: …"
    stageTitle.Parent = stageFrame

    local stageId = Instance.new("TextLabel")
    stageId.Name = "StageId"
    stageId.Size = UDim2.new(0.92, 0, 0.32, 0)
    stageId.Position = UDim2.new(0.04, 0, 0.58, 0)
    stageId.BackgroundTransparency = 1
    stageId.TextColor3 = Color3.fromRGB(140, 155, 185)
    stageId.TextScaled = true
    stageId.Font = Enum.Font.Gotham
    stageId.TextXAlignment = Enum.TextXAlignment.Center
    stageId.Text = ""
    stageId.Parent = stageFrame

    -- ═══════════════════════════════════════
    -- УВЕДОМЛЕНИЕ (центр экрана, скрыто по умолчанию)
    -- Показывается временно: появляется → 3 сек → fade-out
    -- ═══════════════════════════════════════
    local notificationLabel = Instance.new("TextLabel")
    notificationLabel.Name = "Notification"
    notificationLabel.Size = UDim2.new(0.6, 0, 0.08, 0)
    notificationLabel.Position = UDim2.new(0.2, 0, 0.15, 0)
    notificationLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    notificationLabel.BackgroundTransparency = 0.2
    notificationLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    notificationLabel.TextScaled = true
    notificationLabel.Font = Enum.Font.GothamBold
    notificationLabel.Text = ""
    notificationLabel.Visible = false                    -- скрыт по умолчанию
    notificationLabel.Parent = screenGui

    local notifCorner = Instance.new("UICorner")
    notifCorner.CornerRadius = UDim.new(0, 10)
    notifCorner.Parent = notificationLabel

    return screenGui
end

-- ═══════════════════════════════════════════════════════════
-- ОБНОВЛЕНИЕ КВЕСТОВОГО ТРЕКЕРА
-- Вызывается при QuestStarted: обновляет заголовок и цель.
-- ═══════════════════════════════════════════════════════════
local function updateQuestDisplay(data)
    local hud = playerGui:FindFirstChild("GameHUD")
    if not hud then return end

    local questFrame = hud:FindFirstChild("QuestTracker")
    if not questFrame then return end

    local title = questFrame:FindFirstChild("QuestTitle")
    local objective = questFrame:FindFirstChild("QuestObjective")

    if title then
        title.Text = "📜 " .. (data.Title or "Квест")
    end
    if objective and data.Objectives and #data.Objectives > 0 then
        objective.Text = data.Objectives[1].Description or ""
    end
end

-- ═══════════════════════════════════════════════════════════
-- ОБНОВЛЕНИЕ ПРОГРЕССА КВЕСТА
-- Вызывается при QuestUpdated: обновляет текст цели с числами (X/Y).
-- ═══════════════════════════════════════════════════════════
local function updateQuestProgress(data)
    local hud = playerGui:FindFirstChild("GameHUD")
    if not hud then return end

    local questFrame = hud:FindFirstChild("QuestTracker")
    if not questFrame then return end

    local objective = questFrame:FindFirstChild("QuestObjective")
    if objective and data.Description then
        objective.Text = string.format(
            data.Description or "%d/%d",
            data.Current or 0,
            data.Required or 0
        )
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПОКАЗАТЬ УВЕДОМЛЕНИЕ
-- Временное сообщение по центру экрана.
-- Появляется → ждёт `duration` секунд → плавно исчезает (fade-out через Tween).
-- ═══════════════════════════════════════════════════════════
local function showNotification(text, duration)
    duration = duration or 3
    local hud = playerGui:FindFirstChild("GameHUD")
    if not hud then return end

    local notif = hud:FindFirstChild("Notification")
    if not notif then return end

    -- Показываем уведомление
    notif.Text = text
    notif.Visible = true
    notif.TextTransparency = 0
    notif.BackgroundTransparency = 0.2

    -- Через `duration` секунд — плавно скрываем
    task.delay(duration, function()
        local fadeOut = TweenService:Create(
            notif,
            TweenInfo.new(0.5),
            { TextTransparency = 1, BackgroundTransparency = 1 }
        )
        fadeOut:Play()
        fadeOut.Completed:Connect(function()
            notif.Visible = false
        end)
    end)
end

-- ═══════════════════════════════════════════════════════════
-- ОБНОВИТЬ HUD (монеты + уведомление)
-- Универсальный обработчик: данные приходят как таблица с полями.
-- data.Money → обновить счётчик монет
-- data.Notification → показать уведомление
-- ═══════════════════════════════════════════════════════════
local function updateHUD(data)
    local hud = playerGui:FindFirstChild("GameHUD")
    if not hud then return end

    if data.Money then
        local moneyFrame = hud:FindFirstChild("MoneyDisplay")
        if moneyFrame then
            local label = moneyFrame:FindFirstChild("MoneyLabel")
            if label then
                label.Text = "🪙 " .. tostring(data.Money)
            end
        end
    end

    if data.Notification then
        showNotification(data.Notification)
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПОСТОЯННОЕ ОТОБРАЖЕНИЕ ФАЗЫ СЮЖЕТА
-- ═══════════════════════════════════════════════════════════
local function updateStageDisplay(stageName)
    if type(stageName) ~= "string" or stageName == "" then
        return
    end
    local hud = playerGui:FindFirstChild("GameHUD")
    if not hud then return end

    local panel = hud:FindFirstChild("StageDisplay")
    if not panel then return end

    local title = panel:FindFirstChild("StageTitle")
    local idLabel = panel:FindFirstChild("StageId")
    local displayName = STAGE_DISPLAY_NAMES[stageName] or stageName

    if title then
        title.Text = "Фаза: " .. displayName
    end
    if idLabel then
        idLabel.Text = stageName
    end
end

-- ═══════════════════════════════════════════════════════════
-- ИНИЦИАЛИЗАЦИЯ: создаём HUD при запуске клиента
-- ═══════════════════════════════════════════════════════════
createHUD()

-- ═══════════════════════════════════════════════════════════
-- ПОДПИСКИ НА REMOTE EVENTS
-- Каждое событие привязано к обработчику выше.
-- ═══════════════════════════════════════════════════════════

-- Новый квест получен — обновляем трекер
Remotes:GetEvent("QuestStarted").OnClientEvent:Connect(updateQuestDisplay)

-- Прогресс квеста изменился — обновляем цифры
Remotes:GetEvent("QuestUpdated").OnClientEvent:Connect(updateQuestProgress)

-- Квест завершён — показываем уведомление
Remotes:GetEvent("QuestCompleted").OnClientEvent:Connect(function(data)
    showNotification("✅ Квест завершён: " .. (data.Title or ""))
end)

-- Обновление HUD (монеты, уведомления)
Remotes:GetEvent("UpdateHUD").OnClientEvent:Connect(updateHUD)

-- Волк убит — показываем лут
Remotes:GetEvent("WolfKilled").OnClientEvent:Connect(function(loot)
    local lootText = "🐺 Волк убит!"
    if loot and #loot > 0 then
        for _, item in ipairs(loot) do
            lootText = lootText .. "\n+" .. item.Name
        end
    end
    showNotification(lootText, 2)
end)

-- Смена стадии — постоянная плашка + краткое уведомление
Remotes:GetEvent("StageChanged").OnClientEvent:Connect(function(stageName)
    updateStageDisplay(stageName)
    local displayName = STAGE_DISPLAY_NAMES[stageName] or stageName
    showNotification("📍 " .. displayName, 4)
end)

-- Подтянуть фазу с сервера, если StageChanged ушёл до загрузки HUD
task.spawn(function()
    local fn = Remotes:GetFunction("GetCurrentGameStage")
    for _ = 1, 8 do
        local ok, stage = pcall(function()
            return fn:InvokeServer()
        end)
        if ok and type(stage) == "string" and stage ~= "" then
            updateStageDisplay(stage)
            return
        end
        task.wait(0.35)
    end
end)

return HUDController
