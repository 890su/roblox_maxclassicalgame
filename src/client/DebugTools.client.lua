--[[
    DebugTools — все отладочные горячие клавиши (DEV ONLY)
    ═══════════════════════════════════════════════════════════

    ⚠️ УДАЛИТЬ ПЕРЕД РЕЛИЗОМ!

    КЛАВИШИ (сервер: Remotes.DebugTools → GameManager):
    ───────────────────────────────────────────────────────────
    T = переключить скорость бега ×5 (локально)
    Y = убить всех волков (Workspace.Wolves)
    U = телепорт по зонам по кругу (Village → … → ArtifactHall)
    G = стадия MINI_BOSS + телепорт к арене гидры + спавн гидры
    B = стадия SWAMP_JOURNEY + TP к болоту + проводник JOHN DOU
    L = стадия TOMB_MAZE + телепорт в лабиринт гробницы
    K = стадия BAN_HAMMER + квест на молот + TP рядом с TeleporterD (у выхода из лабиринта)

    HUD: зелёная подсказка справа сверху; 3 с — сброс текста.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local HINT_DEFAULT = "[DEBUG] M=MapReady T=Speed Y=Wolves U=Zone G=Hydra B=Swamp L=Maze K=MazeExit"

-- ═══════════════════════════════════════════════════════════
-- DEBUG HUD
-- ═══════════════════════════════════════════════════════════
local playerGui = player:WaitForChild("PlayerGui")
local debugGui = Instance.new("ScreenGui")
debugGui.Name = "DebugGui"
debugGui.IgnoreGuiInset = true
debugGui.DisplayOrder = 200
debugGui.Parent = playerGui

local debugLabel = Instance.new("TextLabel")
debugLabel.Name = "DebugLabel"
debugLabel.Size = UDim2.new(0, 320, 0, 22)
debugLabel.Position = UDim2.new(1, -330, 0, 5)
debugLabel.BackgroundTransparency = 0.5
debugLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
debugLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
debugLabel.TextSize = 12
debugLabel.Font = Enum.Font.RobotoMono
debugLabel.Text = HINT_DEFAULT
debugLabel.TextXAlignment = Enum.TextXAlignment.Right
debugLabel.Parent = debugGui

local function debugNotify(text)
    debugLabel.Text = "[DEBUG] " .. text
    task.delay(3, function()
        debugLabel.Text = HINT_DEFAULT
    end)
end

local function fireDebug(action)
    local ev = Remotes:GetEvent("DebugTools")
    if ev then
        ev:FireServer(action)
    else
        warn("[DebugTools] Remote DebugTools не найден")
    end
end

-- ═══════════════════════════════════════════════════════════
-- T: скорость ×5
-- ═══════════════════════════════════════════════════════════
local isBoosted = false
local normalSpeed = 16

-- ═══════════════════════════════════════════════════════════
-- U: зоны по кругу (телепорт на сервере — координаты не на клиенте)
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then
        return
    end

    if input.KeyCode == Enum.KeyCode.T then
        local character = player.Character
        if not character then
            return
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            return
        end

        if isBoosted then
            humanoid.WalkSpeed = normalSpeed
            isBoosted = false
            debugNotify("Speed: NORMAL (" .. normalSpeed .. ")")
        else
            normalSpeed = humanoid.WalkSpeed
            humanoid.WalkSpeed = normalSpeed * 5
            isBoosted = true
            debugNotify("Speed: x5 (" .. humanoid.WalkSpeed .. ")")
        end
    elseif input.KeyCode == Enum.KeyCode.M then
        debugNotify("Map ready: sword + map + wolves killed...")
        fireDebug("MapReady")
    elseif input.KeyCode == Enum.KeyCode.Y then
        debugNotify("Killing all wolves…")
        fireDebug("KillWolves")
    elseif input.KeyCode == Enum.KeyCode.G then
        debugNotify("Стадия гидры + TP к арене…")
        fireDebug("JumpMiniBoss")
    elseif input.KeyCode == Enum.KeyCode.B then
        debugNotify("Стадия болота + TP к кочкам…")
        fireDebug("JumpSwamp")
    elseif input.KeyCode == Enum.KeyCode.L then
        debugNotify("Стадия лабиринта + TP в гробницу…")
        fireDebug("JumpTombMaze")
    elseif input.KeyCode == Enum.KeyCode.K then
        debugNotify("Стадия выхода из лабиринта + TP у TeleporterD…")
        fireDebug("JumpMazeNearExit")
    elseif input.KeyCode == Enum.KeyCode.U then
        debugNotify("TP → следующая зона (сервер)…")
        fireDebug("CycleZone")
    end
end)

print("[DebugTools]", HINT_DEFAULT)
