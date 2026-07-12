--[[
    LoadingScreen — Экран загрузки
    ═══════════════════════════════════════════════════════════
    
    Показывает пользовательский экран загрузки ВМЕСТО стандартного Roblox.
    
    ПОЧЕМУ ReplicatedFirst:
    ───────────────────────
    Скрипты из ReplicatedFirst загружаются на клиенте ПЕРВЫМИ,
    до всех скриптов из StarterPlayerScripts.
    Это позволяет показать экран загрузки раньше всего остального.
    
    ПОТОК:
    ──────
    1. Убираем стандартный экран загрузки Roblox
    2. Создаём свой GUI: название игры + анимированный прогресс-бар
    3. Ждём game.Loaded (все ассеты загружены)
    4. Анимируем прогресс-бар (10 шагов по 15%)
    5. Показываем "Готово!" и удаляем GUI
    
    СТРУКТУРА UI:
    ─────────────
    LoadingScreen (ScreenGui, DisplayOrder=999)
    └── Background (Frame, чёрный)
        ├── Title (TextLabel)     — "Shadow of the Hammer"
        ├── Subtitle (TextLabel)  — "Загрузка... 70%"
        └── BarBg (Frame)         — фон прогресс-бара
            └── Fill (Frame)      — заполнение (фиолетовый)
    
    МОЖНО ДОБАВИТЬ:
    ────────────────
    - Анимированный логотип
    - Подсказки во время загрузки
    - ContentProvider:PreloadAsync() для предзагрузки конкретных ассетов
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════
-- Убираем стандартный экран загрузки Roblox
-- (вызывается ТОЛЬКО из ReplicatedFirst, иначе будет ошибка)
-- ═══════════════════════════════════════════════════════════
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- ═══════════════════════════════════════════════════════════
-- СОЗДАЁМ ПОЛЬЗОВАТЕЛЬСКИЙ ЭКРАН ЗАГРУЗКИ
-- DisplayOrder = 999 — поверх ВСЕГО остального
-- ═══════════════════════════════════════════════════════════
local loadingGui = Instance.new("ScreenGui")
loadingGui.Name = "LoadingScreen"
loadingGui.IgnoreGuiInset = true
loadingGui.DisplayOrder = 999
loadingGui.Parent = playerGui

-- ─── ФОН (тёмный) ───
local bg = Instance.new("Frame")
bg.Name = "Background"
bg.Size = UDim2.new(1, 0, 1, 0)
bg.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
bg.BorderSizePixel = 0
bg.Parent = loadingGui

-- ─── НАЗВАНИЕ ИГРЫ ───
local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(0.6, 0, 0.1, 0)
title.Position = UDim2.new(0.2, 0, 0.35, 0)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(255, 220, 100)     -- золотой
title.TextSize = 48
title.Font = Enum.Font.GothamBold
title.Text = "Shadow of the Hammer"
title.Parent = bg

-- ─── ПОДЗАГОЛОВОК (текст прогресса) ───
local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Size = UDim2.new(0.6, 0, 0.05, 0)
subtitle.Position = UDim2.new(0.2, 0, 0.46, 0)
subtitle.BackgroundTransparency = 1
subtitle.TextColor3 = Color3.fromRGB(180, 180, 200)
subtitle.TextSize = 20
subtitle.Font = Enum.Font.Gotham
subtitle.Text = "Загрузка..."
subtitle.Parent = bg

-- ─── ПРОГРЕСС-БАР ───
local barBg = Instance.new("Frame")
barBg.Name = "BarBg"
barBg.Size = UDim2.new(0.4, 0, 0, 6)                -- узкая полоса
barBg.Position = UDim2.new(0.3, 0, 0.55, 0)
barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)  -- серый фон
barBg.BorderSizePixel = 0
barBg.Parent = bg

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 3)
barCorner.Parent = barBg

-- Заполнение прогресс-бара (фиолетовый, начинает с 0 ширины)
local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.new(0, 0, 1, 0)                 -- 0% заполнения
barFill.BackgroundColor3 = Color3.fromRGB(100, 80, 200) -- фиолетовый
barFill.BorderSizePixel = 0
barFill.Parent = barBg

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 3)
fillCorner.Parent = barFill

-- ═══════════════════════════════════════════════════════════
-- ОЖИДАНИЕ ЗАГРУЗКИ ИГРЫ
-- ═══════════════════════════════════════════════════════════
task.wait(1)  -- минимальная задержка (чтобы экран точно появился)

-- Ждём, пока Roblox загрузит все ассеты
if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- Анимация прогресс-бара: 10 шагов по 10%
for i = 1, 10 do
    barFill.Size = UDim2.new(i / 10, 0, 1, 0)
    subtitle.Text = string.format("Загрузка... %d%%", i * 10)
    task.wait(0.15)
end

subtitle.Text = "Готово!"
task.wait(0.5)

-- Удаляем экран загрузки (вернётся стандартный вид игры)
loadingGui:Destroy()
