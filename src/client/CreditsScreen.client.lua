--[[
    CreditsScreen — Экран титров (финальные титры после концовки)
    ═══════════════════════════════════════════════════════════
    
    Показывает прокручивающиеся титры после завершения игры.
    
    КОМПОНЕНТЫ:
    ───────────
    • Чёрный фон (backdrop)
    • Прокручивающийся контент (UIListLayout + Tween)
    • Кнопка «Пропустить»
    
    СОДЕРЖИМОЕ ТИТРОВ:
    ──────────────────
    1. Название игры: "ТЕНЬ МОЛОТА"
    2. Текст концовки (из endingData.CreditsText)
    3. Название концовки (из endingData.Name)
    4. Команда создателей
    5. Счётчик открытых концовок (X из 3)
    6. Подсказка для следующей концовки
    
    АНИМАЦИЯ:
    ─────────
    ScrollContent начинает за экраном (Y = 1) и поднимается
    вверх через TweenService (Linear). Скорость = 50px/сек.
    
    ВЫЗОВ:
    ──────
    Сервер → ShowCredits (RemoteEvent) → { endingData }
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local CreditsScreen = {}

-- ═══════════════════════════════════════════════════════════
-- СОЗДАНИЕ UI ТИТРОВ
-- Уничтожает старый GUI (в отличие от других скриптов),
-- потому что каждый показ титров уникален (разные концовки).
-- ═══════════════════════════════════════════════════════════
local function createCreditsGui()
    -- Уничтожаем старый (не переиспользуем)
    local existing = playerGui:FindFirstChild("CreditsGui")
    if existing then existing:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "CreditsGui"
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 90       -- выше диалогов, ниже fade
    screenGui.Parent = playerGui

    -- Чёрный фон на весь экран
    local backdrop = Instance.new("Frame")
    backdrop.Name = "Backdrop"
    backdrop.Size = UDim2.new(1, 0, 1, 0)
    backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
    backdrop.BackgroundTransparency = 0
    backdrop.BorderSizePixel = 0
    backdrop.Parent = screenGui

    -- Контейнер прокрутки: высокий (3x экрана), начинает ЗА нижним краем
    local scrollFrame = Instance.new("Frame")
    scrollFrame.Name = "ScrollContent"
    scrollFrame.Size = UDim2.new(0.6, 0, 3, 0)   -- 60% ширины, 300% высоты
    scrollFrame.Position = UDim2.new(0.2, 0, 1, 0) -- начинает под экраном
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.Parent = backdrop

    -- UIListLayout: элементы располагаются вертикально по центру
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Padding = UDim.new(0, 10)
    layout.Parent = scrollFrame

    return screenGui, scrollFrame
end

-- ═══════════════════════════════════════════════════════════
-- ДОБАВИТЬ СТРОКУ ТИТРОВ
-- Утилита для создания TextLabel с кастомными параметрами.
-- options: { Height, Color, Font }
-- ═══════════════════════════════════════════════════════════
local function addCreditLine(parent, text, options)
    options = options or {}

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, options.Height or 40)
    label.BackgroundTransparency = 1
    label.TextColor3 = options.Color or Color3.fromRGB(220, 220, 230)
    label.TextScaled = true
    label.TextWrapped = true
    label.Font = options.Font or Enum.Font.Gotham
    label.Text = text
    label.Parent = parent

    return label
end

-- ═══════════════════════════════════════════════════════════
-- ПОКАЗАТЬ ТИТРЫ
-- Получает endingData от сервера, строит содержимое и запускает прокрутку.
-- ═══════════════════════════════════════════════════════════
local function showCredits(endingData)
    local gui, scrollFrame = createCreditsGui()

    -- ─── ЗАГОЛОВОК ИГРЫ ───
    addCreditLine(scrollFrame, "", { Height = 60 })    -- отступ
    addCreditLine(scrollFrame, "ТЕНЬ МОЛОТА", {
        Font = Enum.Font.GothamBold,
        Color = Color3.fromRGB(255, 220, 100),         -- золотой
        Height = 80,
    })

    addCreditLine(scrollFrame, "", { Height = 40 })

    -- ─── ТЕКСТ КОНЦОВКИ (из EndingConfig) ───
    if endingData and endingData.CreditsText then
        for _, line in ipairs(endingData.CreditsText) do
            if line == "" then
                addCreditLine(scrollFrame, "", { Height = 20 })
            else
                addCreditLine(scrollFrame, line, {
                    Color = Color3.fromRGB(200, 180, 140),
                    Font = Enum.Font.Antique,           -- стиль пергамента
                    Height = 50,
                })
            end
        end
    end

    addCreditLine(scrollFrame, "", { Height = 60 })

    -- ─── НАЗВАНИЕ КОНЦОВКИ ───
    if endingData then
        addCreditLine(scrollFrame, "— " .. (endingData.Name or "Конец") .. " —", {
            Font = Enum.Font.GothamBold,
            Color = Color3.fromRGB(180, 100, 255),      -- фиолетовый
            Height = 60,
        })
    end

    addCreditLine(scrollFrame, "", { Height = 80 })

    -- ─── КОМАНДА СОЗДАТЕЛЕЙ ───
    addCreditLine(scrollFrame, "СОЗДАТЕЛИ", {
        Font = Enum.Font.GothamBold,
        Color = Color3.fromRGB(255, 220, 100),
        Height = 50,
    })
    addCreditLine(scrollFrame, "", { Height = 20 })
    addCreditLine(scrollFrame, "Геймдизайн и сценарий")
    addCreditLine(scrollFrame, "[Ваше имя]", { Color = Color3.fromRGB(180, 180, 255) })
    addCreditLine(scrollFrame, "", { Height = 20 })
    addCreditLine(scrollFrame, "Программирование")
    addCreditLine(scrollFrame, "[Ваше имя]", { Color = Color3.fromRGB(180, 180, 255) })
    addCreditLine(scrollFrame, "", { Height = 20 })
    addCreditLine(scrollFrame, "Левел-дизайн")
    addCreditLine(scrollFrame, "[Ваше имя]", { Color = Color3.fromRGB(180, 180, 255) })

    addCreditLine(scrollFrame, "", { Height = 100 })

    -- ─── СЧЁТЧИК КОНЦОВОК ───
    local endingsCount = (endingData and endingData.Id) or 0
    addCreditLine(scrollFrame, string.format("Концовок открыто: %d из 3", endingsCount), {
        Font = Enum.Font.GothamBold,
        Color = Color3.fromRGB(100, 255, 100),          -- зелёный
        Height = 50,
    })

    addCreditLine(scrollFrame, "", { Height = 40 })

    -- Подсказка для следующей концовки
    if endingsCount < 3 then
        addCreditLine(scrollFrame, "Пройдите снова, чтобы раскрыть новую судьбу...", {
            Color = Color3.fromRGB(150, 150, 180),
            Font = Enum.Font.GothamMedium,
        })
    else
        addCreditLine(scrollFrame, "Все тайны раскрыты. Спасибо за игру!", {
            Color = Color3.fromRGB(255, 200, 100),
            Font = Enum.Font.GothamBold,
        })
    end

    addCreditLine(scrollFrame, "", { Height = 200 })

    -- ─── АНИМАЦИЯ ПРОКРУТКИ ───
    -- Считаем общую высоту контента
    local totalHeight = 0
    for _, child in ipairs(scrollFrame:GetChildren()) do
        if child:IsA("TextLabel") then
            totalHeight = totalHeight + child.Size.Y.Offset + 10  -- +10 = Padding
        end
    end

    -- Скорость: 50 пикселей в секунду, лимит 10–60 сек
    local scrollDuration = totalHeight / 50
    scrollDuration = math.clamp(scrollDuration, 10, 60)

    -- Tween: контент поднимается снизу вверх (Y: 1 → -2.5)
    local scrollTween = TweenService:Create(
        scrollFrame,
        TweenInfo.new(scrollDuration, Enum.EasingStyle.Linear),
        { Position = UDim2.new(0.2, 0, -2.5, 0) }
    )
    scrollTween:Play()

    -- После завершения прокрутки — удаляем GUI через 3 сек
    scrollTween.Completed:Connect(function()
        task.wait(3)
        if gui and gui.Parent then
            gui:Destroy()
        end
    end)

    -- ─── КНОПКА «ПРОПУСТИТЬ» (правый нижний угол) ───
    local skipButton = Instance.new("TextButton")
    skipButton.Name = "SkipButton"
    skipButton.Size = UDim2.new(0.1, 0, 0.04, 0)
    skipButton.Position = UDim2.new(0.88, 0, 0.94, 0)
    skipButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    skipButton.BackgroundTransparency = 0.5
    skipButton.TextColor3 = Color3.fromRGB(180, 180, 180)
    skipButton.TextScaled = true
    skipButton.Font = Enum.Font.Gotham
    skipButton.Text = "Пропустить"
    skipButton.Parent = gui:FindFirstChild("Backdrop")

    skipButton.MouseButton1Click:Connect(function()
        scrollTween:Cancel()
        if gui and gui.Parent then
            gui:Destroy()
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
-- ПОДПИСКА НА REMOTE EVENT
-- Сервер отправляет ShowCredits → запускаем титры
-- ═══════════════════════════════════════════════════════════
Remotes:GetEvent("ShowCredits").OnClientEvent:Connect(showCredits)

return CreditsScreen
