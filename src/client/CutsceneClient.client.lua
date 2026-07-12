--[[
    CutsceneClient — Клиентская часть кат-сцен
    ═══════════════════════════════════════════════════════════
    
    Управляет камерой, блокировкой управления и fade-эффектами
    во время кат-сцен.
    
    РАЗДЕЛЕНИЕ СЕРВЕР/КЛИЕНТ:
    ─────────────────────────
    • СЕРВЕР (CutsceneManager): NPC-действия, спавн, логика
    • КЛИЕНТ (этот файл): камера, fade, блокировка управления
    
    ПОТОК КАТ-СЦЕНЫ:
    ─────────────────
    1. Сервер → StartCutscene (RemoteEvent) → cutsceneData
    2. Клиент: fade-out → блокировка управления → fade-in
    3. Камера: Scriptable mode → интерполяция по CameraPoints
    4. Завершение: fade-out → восстановить камеру → fade-in
    5. Клиент → CutsceneFinished (RemoteEvent) → сервер
    
    КАМЕРА:
    ───────
    CameraPoints — массив точек {Position, LookAt, Time}.
    • Position и LookAt — ОТНОСИТЕЛЬНО позиции игрока (basePos)
    • Между точками камера плавно движется через TweenService
    • EasingStyle = Sine, InOut (плавное ускорение/замедление)
    
    FADE-ЭФФЕКТ:
    ────────────
    Полноэкранный чёрный Frame с анимацией Transparency:
    • fadeScreen(true)  → экран затемняется (0 → 1 прозрачность)
    • fadeScreen(false) → экран проявляется (1 → 0 прозрачность)
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local CutsceneClient = {}

local isInCutscene = false          -- флаг: идёт ли кат-сцена
local originalCameraType = nil      -- сохраняем тип камеры для восстановления

-- ═══════════════════════════════════════════════════════════
-- БЛОКИРОВКА УПРАВЛЕНИЯ
-- Отключает WASD/стик через PlayerModule.
-- PlayerModule — стандартный Roblox модуль управления персонажем.
-- ═══════════════════════════════════════════════════════════
local function lockControls()
    local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
    local controls = playerModule:GetControls()
    controls:Disable()
end

-- Разблокировка с pcall (на случай если PlayerModule ещё не загрузился)
local function unlockControls()
    local success, playerModule = pcall(function()
        return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
    end)
    if success then
        local controls = playerModule:GetControls()
        controls:Enable()
    end
end

-- ═══════════════════════════════════════════════════════════
-- АНИМАЦИЯ КАМЕРЫ ПО ТОЧКАМ
-- Переводит камеру в Scriptable mode и интерполирует между точками.
--
-- CameraPoints — массив точек:
--   { Position = Vector3, LookAt = Vector3, Time = number }
--
-- Position/LookAt — ОТНОСИТЕЛЬНЫЕ координаты (прибавляем к позиции игрока).
-- Time — секунда на временной шкале кат-сцены (0, 1.5, 4, ...).
-- TweenTime = Time[i+1] - Time[i] (сколько секунд лететь до следующей точки).
-- ═══════════════════════════════════════════════════════════
local function animateCamera(cameraPoints, duration)
    -- Сохраняем текущий тип камеры для восстановления
    originalCameraType = camera.CameraType
    camera.CameraType = Enum.CameraType.Scriptable  -- ручное управление

    -- Базовая позиция — позиция игрока (камера движется относительно неё)
    local character = player.Character
    local basePos = Vector3.new(0, 0, 0)
    if character and character:FindFirstChild("HumanoidRootPart") then
        basePos = character.HumanoidRootPart.Position
    end

    for i, point in ipairs(cameraPoints) do
        -- CFrame.lookAt(позиция_камеры, куда_смотрит)
        local targetCF = CFrame.lookAt(
            basePos + point.Position,
            basePos + point.LookAt
        )

        -- Вычисляем время перелёта до следующей точки
        local tweenTime = 0
        if i < #cameraPoints then
            tweenTime = (cameraPoints[i + 1].Time - point.Time)
        else
            tweenTime = duration - point.Time
        end
        tweenTime = math.max(tweenTime, 0.5)  -- минимум 0.5 сек

        -- Tween с плавным ускорением/замедлением
        local tween = TweenService:Create(
            camera,
            TweenInfo.new(tweenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
            { CFrame = targetCF }
        )

        -- Первая точка — мгновенно, остальные — через Tween
        camera.CFrame = targetCF
        if i > 1 then
            tween:Play()
            tween.Completed:Wait()  -- ждём завершения анимации
        else
            task.wait(math.max(0, tweenTime))
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- FADE-ЭФФЕКТ (затемнение/проявление экрана)
-- Создаёт полноэкранный чёрный Frame (DisplayOrder=100)
-- и анимирует его прозрачность через TweenService.
--
-- fadeIn = true  → экран затемняется (прозрачность 1 → 0)
-- fadeIn = false → экран проявляется (прозрачность 0 → 1)
-- duration — длительность анимации (по умолчанию 1 сек)
-- ═══════════════════════════════════════════════════════════
local function fadeScreen(fadeIn, duration)
    local screenGui = player:WaitForChild("PlayerGui"):FindFirstChild("CutsceneFade")
    if not screenGui then
        -- Создаём GUI для fade-эффекта
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = "CutsceneFade"
        screenGui.IgnoreGuiInset = true
        screenGui.DisplayOrder = 100         -- поверх всего
        screenGui.Parent = player:WaitForChild("PlayerGui")

        local frame = Instance.new("Frame")
        frame.Name = "FadeFrame"
        frame.Size = UDim2.new(1, 0, 1, 0)
        frame.BackgroundColor3 = Color3.new(0, 0, 0)    -- полностью чёрный
        frame.BackgroundTransparency = fadeIn and 1 or 0
        frame.BorderSizePixel = 0
        frame.Parent = screenGui
    end

    local frame = screenGui:FindFirstChild("FadeFrame")
    if frame then
        local tween = TweenService:Create(
            frame,
            TweenInfo.new(duration or 1),
            { BackgroundTransparency = fadeIn and 0 or 1 }
        )
        tween:Play()
        tween.Completed:Wait()
    end
end

-- ═══════════════════════════════════════════════════════════
-- ЗАПУСК КАТ-СЦЕНЫ
-- Полный цикл: fade → блокировка → камера → восстановление
-- ═══════════════════════════════════════════════════════════
local function playCutscene(cutsceneData)
    if isInCutscene then return end   -- защита от двойного запуска
    isInCutscene = true

    print("[CutsceneClient] Запуск:", cutsceneData.Id)

    -- 1. Затемнение
    fadeScreen(true, 0.5)

    -- 2. Блокируем управление (WASD)
    lockControls()

    -- 3. Проявление
    fadeScreen(false, 0.5)

    -- 4. Анимация камеры по точкам
    if cutsceneData.CameraPoints and #cutsceneData.CameraPoints > 0 then
        animateCamera(cutsceneData.CameraPoints, cutsceneData.Duration)
    else
        task.wait(cutsceneData.Duration)
    end

    -- 5. Затемнение для перехода
    fadeScreen(true, 0.5)

    -- 6. Восстанавливаем тип камеры (Custom — следит за персонажем)
    if originalCameraType then
        camera.CameraType = originalCameraType
    end

    -- 7. Разблокируем управление
    unlockControls()

    -- 8. Проявление (возврат к игре)
    fadeScreen(false, 0.5)

    isInCutscene = false

    -- 9. Оповещаем сервер
    Remotes:GetEvent("CutsceneFinished"):FireServer(cutsceneData.Id)

    print("[CutsceneClient] Завершено:", cutsceneData.Id)
end

-- ═══════════════════════════════════════════════════════════
-- ПОДПИСКА НА REMOTE EVENT
-- Сервер отправляет StartCutscene → запускаем кат-сцену на клиенте
-- ═══════════════════════════════════════════════════════════
Remotes:GetEvent("StartCutscene").OnClientEvent:Connect(playCutscene)

return CutsceneClient
