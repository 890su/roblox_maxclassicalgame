--[[
    DialogueUI — Клиентский UI для диалогов с NPC
    ═══════════════════════════════════════════════════════════
    
    Отвечает за ОТОБРАЖЕНИЕ диалогов на экране:
    • Окно диалога в нижней части экрана (фиксированный размер)
    • Анимация печатной машинки (typewriter effect)
    • Пропуск анимации (клик/Space/Enter → мгновенно показать текст)
    • Переход к следующему шагу (клик/Space/Enter)
    • Оповещение сервера о завершении диалога (DIALOGUE_FINISHED)
    
    СТРУКТУРА UI (ScreenGui "DialogueGui"):
    ───────────────────────────────────────
    DialogueGui (ScreenGui, DisplayOrder=50)
    └── DialogueFrame (Frame, фиксированная высота 160px)
        ├── SpeakerLabel (TextLabel)     — имя говорящего, над рамкой
        ├── TextLabel (TextLabel)        — текст реплики (TextSize=20, НЕ TextScaled!)
        ├── NextButton (TextButton)      — кнопка "Далее ▶"
        └── ContinueHint (TextLabel)     — подсказка "Нажмите для продолжения..."
    
    ПОТОК ДИАЛОГА:
    ──────────────
    1. Сервер → ShowDialogue (RemoteEvent) → showDialogue()
    2. Клиент показывает шаги один за другим (typewriter)
    3. Игрок кликает → advanceDialogue() → следующий шаг или завершение
    4. Если есть step.Action → отправляем на сервер (DialogueChoice)
    5. Все шаги пройдены → hideDialogue() → DIALOGUE_FINISHED на сервер
    
    ДВОЙНОЙ КЛИК:
    ─────────────
    Первый клик во время анимации → показать весь текст мгновенно.
    Второй клик → перейти к следующему шагу.
    
    ФИКС: TextScaled = false (фиксированный размер шрифта 20px).
    Без этого окно «прыгало» при печатании, потому что TextScaled
    пересчитывал размер шрифта при каждой букве.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local DialogueUI = {}

-- ═══════════════════════════════════════════════════════════
-- СОСТОЯНИЕ ДИАЛОГА
-- ═══════════════════════════════════════════════════════════
local isDialogueActive = false       -- активен ли диалог сейчас
local isTyping = false               -- идёт ли анимация печатной машинки
local currentDialogueIndex = 0       -- индекс текущего шага (1-based)
local currentDialogueSteps = nil     -- массив шагов текущего диалога
local currentFullText = ""           -- полный текст текущего шага (для пропуска анимации)
local nextButtonConnection = nil     -- подключение кнопки "Далее" (отключаем при перезапуске)
local currentTrackNPC = nil          -- ID NPC для отправки на сервер при завершении

-- ═══════════════════════════════════════════════════════════
-- СОЗДАНИЕ UI ДИАЛОГА
-- Строит окно диалога: рамка, имя говорящего, текст, кнопка «Далее».
-- Idempotent: не создаёт дубликат (проверяет наличие).
-- ═══════════════════════════════════════════════════════════
local function createDialogueGui()
    local existing = playerGui:FindFirstChild("DialogueGui")
    if existing then return existing end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "DialogueGui"
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 50       -- выше HUD (10), ниже кат-сцен (100)
    screenGui.Enabled = false         -- скрыт по умолчанию
    screenGui.Parent = playerGui

    -- ─── РАМКА ДИАЛОГА (низ экрана, фиксированная высота) ───
    local dialogueFrame = Instance.new("Frame")
    dialogueFrame.Name = "DialogueFrame"
    dialogueFrame.Size = UDim2.new(0.8, 0, 0, 160)       -- 80% ширины, 160px высота
    dialogueFrame.Position = UDim2.new(0.1, 0, 1, -180)  -- 180px от низа
    dialogueFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    dialogueFrame.BackgroundTransparency = 0.1
    dialogueFrame.BorderSizePixel = 0
    dialogueFrame.Parent = screenGui

    -- Скруглённые углы
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = dialogueFrame

    -- Фиолетовая обводка (стиль игры)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(100, 80, 150)
    stroke.Thickness = 2
    stroke.Parent = dialogueFrame

    -- ─── ИМЯ ГОВОРЯЩЕГО (над рамкой) ───
    local speakerLabel = Instance.new("TextLabel")
    speakerLabel.Name = "SpeakerLabel"
    speakerLabel.Size = UDim2.new(0, 200, 0, 30)
    speakerLabel.Position = UDim2.new(0, 15, 0, -35)     -- выше рамки
    speakerLabel.BackgroundColor3 = Color3.fromRGB(60, 40, 100)
    speakerLabel.BackgroundTransparency = 0.1
    speakerLabel.TextColor3 = Color3.fromRGB(255, 220, 100) -- жёлтый
    speakerLabel.TextSize = 18                             -- фиксированный размер
    speakerLabel.Font = Enum.Font.GothamBold
    speakerLabel.Text = ""
    speakerLabel.TextXAlignment = Enum.TextXAlignment.Center
    speakerLabel.Parent = dialogueFrame

    local speakerCorner = Instance.new("UICorner")
    speakerCorner.CornerRadius = UDim.new(0, 8)
    speakerCorner.Parent = speakerLabel

    -- ─── ТЕКСТ РЕПЛИКИ ───
    -- ВАЖНО: TextScaled = false! Фиксированный TextSize = 20.
    -- Если бы TextScaled = true, текст «прыгал» бы при печатании.
    local textLabel = Instance.new("TextLabel")
    textLabel.Name = "TextLabel"
    textLabel.Size = UDim2.new(1, -30, 1, -50)
    textLabel.Position = UDim2.new(0, 15, 0, 10)
    textLabel.BackgroundTransparency = 1
    textLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
    textLabel.TextSize = 20                               -- фиксированный размер!
    textLabel.TextScaled = false                          -- НЕ масштабировать
    textLabel.TextWrapped = true                          -- перенос длинных строк
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.TextYAlignment = Enum.TextYAlignment.Top
    textLabel.Font = Enum.Font.Gotham
    textLabel.Text = ""
    textLabel.Parent = dialogueFrame

    -- ─── КНОПКА «ДАЛЕЕ» (правый нижний угол рамки) ───
    local nextButton = Instance.new("TextButton")
    nextButton.Name = "NextButton"
    nextButton.Size = UDim2.new(0, 120, 0, 35)
    nextButton.Position = UDim2.new(1, -135, 1, -45)
    nextButton.BackgroundColor3 = Color3.fromRGB(80, 60, 130)
    nextButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    nextButton.TextSize = 16
    nextButton.Font = Enum.Font.GothamBold
    nextButton.Text = "Далее ▶"
    nextButton.Parent = dialogueFrame

    local nextCorner = Instance.new("UICorner")
    nextCorner.CornerRadius = UDim.new(0, 8)
    nextCorner.Parent = nextButton

    -- ─── ПОДСКАЗКА (левый нижний угол) ───
    local continueHint = Instance.new("TextLabel")
    continueHint.Name = "ContinueHint"
    continueHint.Size = UDim2.new(0, 200, 0, 20)
    continueHint.Position = UDim2.new(0, 15, 1, -30)
    continueHint.BackgroundTransparency = 1
    continueHint.TextColor3 = Color3.fromRGB(150, 150, 170)
    continueHint.TextSize = 12
    continueHint.Font = Enum.Font.Gotham
    continueHint.Text = "Нажмите для продолжения..."
    continueHint.TextXAlignment = Enum.TextXAlignment.Left
    continueHint.Parent = dialogueFrame

    return screenGui
end

-- ═══════════════════════════════════════════════════════════
-- АНИМАЦИЯ ПЕЧАТНОЙ МАШИНКИ (TYPEWRITER)
-- Показывает текст побуквенно с задержкой `speed` между символами.
-- Можно прервать: isTyping = false → покажет полный текст.
-- ═══════════════════════════════════════════════════════════
local function typewriteText(label, text, speed)
    speed = speed or 0.03  -- 30мс между символами
    isTyping = true
    currentFullText = text
    label.Text = ""
    for i = 1, #text do
        if not isTyping then
            -- Анимация прервана (игрок кликнул) — показываем всё сразу
            label.Text = text
            return
        end
        label.Text = string.sub(text, 1, i)
        task.wait(speed)
    end
    isTyping = false
end

-- ═══════════════════════════════════════════════════════════
-- ПОКАЗАТЬ ОДИН ШАГ ДИАЛОГА
-- Обновляет имя говорящего и запускает typewriter для текста.
-- ═══════════════════════════════════════════════════════════
local function showDialogueStep(step)
    local gui = playerGui:FindFirstChild("DialogueGui")
    if not gui then return end

    local frame = gui:FindFirstChild("DialogueFrame")
    if not frame then return end

    local speakerLabel = frame:FindFirstChild("SpeakerLabel")
    local textLabel = frame:FindFirstChild("TextLabel")

    if speakerLabel then
        speakerLabel.Text = step.Speaker
    end

    if textLabel then
        typewriteText(textLabel, step.Text)
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПРОДВИНУТЬ ДИАЛОГ (СЛЕДУЮЩИЙ ШАГ / ПРОПУСК АНИМАЦИИ)
-- Двойная функция:
-- 1. Если идёт анимация → показать полный текст мгновенно
-- 2. Если анимация завершена → перейти к следующему шагу
-- 3. Если шаги закончились → скрыть диалог
-- ═══════════════════════════════════════════════════════════
local function advanceDialogue()
    if not isDialogueActive or not currentDialogueSteps then return end

    -- Случай 1: анимация идёт → пропускаем (показываем полный текст)
    if isTyping then
        isTyping = false
        local gui = playerGui:FindFirstChild("DialogueGui")
        if gui then
            local frame = gui:FindFirstChild("DialogueFrame")
            if frame then
                local textLabel = frame:FindFirstChild("TextLabel")
                if textLabel then
                    textLabel.Text = currentFullText
                end
            end
        end
        return
    end

    -- Случай 2: переходим к следующему шагу
    currentDialogueIndex = currentDialogueIndex + 1

    -- Случай 3: все шаги пройдены → скрываем диалог
    if currentDialogueIndex > #currentDialogueSteps then
        hideDialogue()
        return
    end

    local step = currentDialogueSteps[currentDialogueIndex]
    showDialogueStep(step)

    -- Если у шага есть Action → отправляем на сервер (например, выбор концовки)
    if step.Action then
        Remotes:GetEvent("DialogueChoice"):FireServer(step.Action)
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПОКАЗАТЬ ДИАЛОГ
-- Получает данные от сервера: DialogueId или прямые Steps.
-- Создаёт/показывает UI и запускает первый шаг.
-- ═══════════════════════════════════════════════════════════
local function showDialogue(data)
    local steps = data.Steps
    if not steps or #steps == 0 then
        warn("[DialogueUI] Сервер не передал Steps — диалог отклонён:", data.DialogueId)
        return
    end

    -- Не перезапускаем уже активный диалог
    if isDialogueActive then return end

    local gui = createDialogueGui()
    gui.Enabled = true
    isDialogueActive = true
    currentDialogueIndex = 0
    currentDialogueSteps = steps
    currentTrackNPC = data.TrackNPC or nil  -- запоминаем NPC для сервера

    -- Подключаем кнопку «Далее» (отключаем старое подключение)
    local frame = gui:FindFirstChild("DialogueFrame")
    local nextButton = frame and frame:FindFirstChild("NextButton")
    if nextButton then
        if nextButtonConnection then
            nextButtonConnection:Disconnect()
        end
        nextButtonConnection = nextButton.MouseButton1Click:Connect(advanceDialogue)
    end

    -- Показываем первый шаг
    advanceDialogue()
end

-- ═══════════════════════════════════════════════════════════
-- СКРЫТЬ ДИАЛОГ
-- Сбрасывает все флаги, скрывает UI, оповещает сервер.
-- Сервер получит "DIALOGUE_FINISHED" + ID NPC через DialogueChoice.
-- ═══════════════════════════════════════════════════════════
function hideDialogue()
    isDialogueActive = false
    isTyping = false
    currentDialogueSteps = nil
    currentDialogueIndex = 0
    currentFullText = ""

    -- Запоминаем NPC перед сбросом (нужен для сервера)
    local trackNPC = currentTrackNPC
    currentTrackNPC = nil

    local gui = playerGui:FindFirstChild("DialogueGui")
    if gui then
        gui.Enabled = false
    end

    -- Оповещаем сервер: GameManager обработает завершение диалога
    Remotes:GetEvent("DialogueChoice"):FireServer("DIALOGUE_FINISHED", trackNPC)
end

-- ═══════════════════════════════════════════════════════════
-- ПОДПИСКИ НА REMOTE EVENTS
-- ═══════════════════════════════════════════════════════════
Remotes:GetEvent("ShowDialogue").OnClientEvent:Connect(showDialogue)
Remotes:GetEvent("HideDialogue").OnClientEvent:Connect(hideDialogue)

-- ═══════════════════════════════════════════════════════════
-- ОБРАБОТКА ВВОДА (клик/тап/Space/Enter для продолжения)
-- Позволяет продвигать диалог без нажатия кнопки «Далее».
-- ═══════════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(input, processed)
    if not isDialogueActive then return end

    local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    local isKey = input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return
    if not isMouse and not isKey then return end

    -- Мышь/тач: не дублируем обработку, если другой GUI уже съел клик
    if isMouse and processed then return end

    -- Space/Enter: НЕ требуем not processed — иначе HUD/оверлеи могут навсегда блокировать «Далее»
    advanceDialogue()
end)

return DialogueUI
