--[[
    MapViewer — Отображение тайной карты деда
    ═══════════════════════════════════════════════════════════
    
    Полноэкранный UI с анимацией раскрытия карты.
    Показывается во время стадии SECRET_MAP.
    
    UI (ScreenGui "MapGui"):
    ────────────────────────
    MapGui (ScreenGui, DisplayOrder=80)
    ├── Backdrop (Frame)              — полупрозрачный чёрный фон
    └── MapFrame (Frame)              — «пергамент» карты
        ├── Title (TextLabel)         — "Карта Деда"
        ├── MapContent (TextLabel)    — маршрут (emoji + текст)
        ├── Signature (TextLabel)     — "— Твой дед"
        └── CloseButton (TextButton)  — кнопка закрытия "✕"
    
    АНИМАЦИЯ:
    ─────────
    Открытие: Size (0,0) → (0.5, 0.7) через TweenService (Back, Out)
    Закрытие: Size (0.5, 0.7) → (0,0) через TweenService (Back, In)
    
    СОДЕРЖИМОЕ КАРТЫ:
    ─────────────────
    🏘 Деревня → 🌲 Тёмный Лес → ⛩ Вход в гробницу
    → 🔄 Лабиринт → 🔨 Зал Ban Hammer
    
    ВЫЗОВ:
    ──────
    Сервер → ShowMap (RemoteEvent) → showMap()
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local MapViewer = {}

-- ═══════════════════════════════════════════════════════════
-- СОЗДАНИЕ UI КАРТЫ
-- Idempotent: не создаёт дубликат.
-- Карта скрыта по умолчанию (Enabled = false).
-- ═══════════════════════════════════════════════════════════
local function createMapGui()
    local existing = playerGui:FindFirstChild("MapGui")
    if existing then return existing end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MapGui"
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 80       -- выше HUD, ниже титров
    screenGui.Enabled = false
    screenGui.Parent = playerGui

    -- ─── ЗАТЕМНЕНИЕ ФОНА ───
    local backdrop = Instance.new("Frame")
    backdrop.Name = "Backdrop"
    backdrop.Size = UDim2.new(1, 0, 1, 0)
    backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
    backdrop.BackgroundTransparency = 0.5            -- полупрозрачный
    backdrop.BorderSizePixel = 0
    backdrop.Parent = screenGui

    -- ─── РАМКА КАРТЫ (пергамент) ───
    -- Начинает с Size = (0,0) для анимации раскрытия
    local mapFrame = Instance.new("Frame")
    mapFrame.Name = "MapFrame"
    mapFrame.Size = UDim2.new(0, 0, 0, 0)           -- анимация от нуля
    mapFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mapFrame.AnchorPoint = Vector2.new(0.5, 0.5)    -- центрируем
    mapFrame.BackgroundColor3 = Color3.fromRGB(210, 190, 140) -- цвет пергамента
    mapFrame.BorderSizePixel = 0
    mapFrame.Parent = screenGui

    local mapCorner = Instance.new("UICorner")
    mapCorner.CornerRadius = UDim.new(0, 8)
    mapCorner.Parent = mapFrame

    -- ─── ЗАГОЛОВОК ───
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(0.8, 0, 0.1, 0)
    titleLabel.Position = UDim2.new(0.1, 0, 0.02, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextColor3 = Color3.fromRGB(60, 40, 20)  -- тёмно-коричневый
    titleLabel.TextScaled = true
    titleLabel.Font = Enum.Font.Antique                  -- «старинный» шрифт
    titleLabel.Text = "Карта Деда"
    titleLabel.Parent = mapFrame

    -- ─── СОДЕРЖИМОЕ КАРТЫ (маршрут с emoji) ───
    local mapContent = Instance.new("TextLabel")
    mapContent.Name = "MapContent"
    mapContent.Size = UDim2.new(0.85, 0, 0.65, 0)
    mapContent.Position = UDim2.new(0.075, 0, 0.15, 0)
    mapContent.BackgroundTransparency = 1
    mapContent.TextColor3 = Color3.fromRGB(80, 50, 20)
    mapContent.TextScaled = true
    mapContent.TextWrapped = true
    mapContent.Font = Enum.Font.Antique
    mapContent.Text = table.concat({
        "🏘 Деревня",
        "     │",
        "     ▼",
        "🌲 Тёмный Лес (следуй по тропе)",
        "     │",
        "     ▼",
        "⛩ Вход в гробницу (каменная арка)",
        "     │",
        "     ▼",
        "🔄 Лабиринт (правило правой руки)",
        "     │",
        "     ▼",
        "🔨 Зал Ban Hammer",
    }, "\n")
    mapContent.Parent = mapFrame

    -- ─── ПОДПИСЬ ДЕДА ───
    local signatureLabel = Instance.new("TextLabel")
    signatureLabel.Name = "Signature"
    signatureLabel.Size = UDim2.new(0.5, 0, 0.08, 0)
    signatureLabel.Position = UDim2.new(0.45, 0, 0.85, 0)
    signatureLabel.BackgroundTransparency = 1
    signatureLabel.TextColor3 = Color3.fromRGB(100, 60, 30)
    signatureLabel.TextScaled = true
    signatureLabel.Font = Enum.Font.Antique
    signatureLabel.Text = "— Твой дед"
    signatureLabel.Parent = mapFrame

    -- ─── КНОПКА ЗАКРЫТИЯ "✕" ───
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0.08, 0, 0.06, 0)
    closeButton.Position = UDim2.new(0.9, 0, 0.02, 0)
    closeButton.BackgroundColor3 = Color3.fromRGB(150, 60, 60)
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.TextScaled = true
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Text = "✕"
    closeButton.Parent = mapFrame

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 6)
    closeCorner.Parent = closeButton

    closeButton.MouseButton1Click:Connect(function()
        local closeTween = TweenService:Create(
            mapFrame,
            TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In),
            { Size = UDim2.new(0, 0, 0, 0) }
        )
        closeTween:Play()
        closeTween.Completed:Connect(function()
            screenGui.Enabled = false
        end)
    end)

    return screenGui
end

-- ═══════════════════════════════════════════════════════════
-- ПОКАЗАТЬ КАРТУ С АНИМАЦИЕЙ
-- 1. Включаем GUI
-- 2. Анимируем раскрытие (0,0) → (0.5, 0.7)
-- 3. Подключаем кнопку закрытия (анимация сворачивания)
-- ═══════════════════════════════════════════════════════════
local function showMap()
    local gui = createMapGui()
    gui.Enabled = true

    local mapFrame = gui:FindFirstChild("MapFrame")
    if mapFrame then
        -- Анимация раскрытия: Back + Out = «выпрыгивает»
        mapFrame.Size = UDim2.new(0, 0, 0, 0)
        local openTween = TweenService:Create(
            mapFrame,
            TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Size = UDim2.new(0.5, 0, 0.7, 0) }
        )
        openTween:Play()
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПОДПИСКА НА REMOTE EVENT
-- Сервер отправляет ShowMap → показываем карту
-- ═══════════════════════════════════════════════════════════
Remotes:GetEvent("ShowMap").OnClientEvent:Connect(showMap)

return MapViewer
