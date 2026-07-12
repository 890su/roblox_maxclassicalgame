--[[
    SwampCrossing — проводник JOHN DOU через болото с ядовитым туманом
    Workspace.Zones.Swamp: кочки SwampKochka_1 … N, туман, SwampFall, выход у гидры.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SwampConfig = require(ServerScriptService:WaitForChild("SwampConfig"))
local DialogueData = require(ServerScriptService:WaitForChild("DialogueData"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local SwampCrossing = {}

local activeCrossings = {} -- [Player] = { checkpoint, fogConn, fallConns, guideToken }

local function getNPCController()
    return _G.NPCController
end

local function getPlayerStage(player: Player): string?
    if _G.GameManager and _G.GameManager.GetPlayerState then
        local st = _G.GameManager.GetPlayerState(player)
        return st and st.Stage or nil
    end
    return nil
end

local function findSwampFolder(): Instance?
    local zones = Workspace:FindFirstChild(SwampConfig.ZonesFolder)
    if not zones then
        return nil
    end
    return zones:FindFirstChild(SwampConfig.SwampFolder)
end

local function getStepPosition(part: BasePart): Vector3
    return part.Position + Vector3.new(0, part.Size.Y / 2 + 2, 0)
end

local function flatDistanceXZ(a: Vector3, b: Vector3): number
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function isInsideBoundsXZ(position: Vector3, bounds): boolean
    if not bounds then
        return true
    end

    local minX = math.min(bounds.Min.X, bounds.Max.X)
    local maxX = math.max(bounds.Min.X, bounds.Max.X)
    local minZ = math.min(bounds.Min.Z, bounds.Max.Z)
    local maxZ = math.max(bounds.Min.Z, bounds.Max.Z)

    return position.X >= minX
        and position.X <= maxX
        and position.Z >= minZ
        and position.Z <= maxZ
end

local function ensurePoisonFog(swamp: Instance)
    local fogCfg = SwampConfig.FogVisual
    local bounds = SwampConfig.Bounds
    if not fogCfg or not bounds then
        return
    end

    local fogName = fogCfg.Name or "PoisonFog"
    if swamp:FindFirstChild(fogName) then
        return
    end

    local minX = math.min(bounds.Min.X, bounds.Max.X)
    local maxX = math.max(bounds.Min.X, bounds.Max.X)
    local minY = math.min(bounds.Min.Y, bounds.Max.Y)
    local maxY = math.max(bounds.Min.Y, bounds.Max.Y)
    local minZ = math.min(bounds.Min.Z, bounds.Max.Z)
    local maxZ = math.max(bounds.Min.Z, bounds.Max.Z)
    local height = fogCfg.Height or 28

    local fog = Instance.new("Part")
    fog.Name = fogName
    fog.Anchored = true
    fog.CanCollide = false
    fog.CanTouch = false
    fog.CanQuery = false
    fog.Material = Enum.Material.SmoothPlastic
    fog.Color = fogCfg.Color or Color3.fromRGB(120, 170, 120)
    fog.Transparency = fogCfg.Transparency or 0.75
    fog.Size = Vector3.new(maxX - minX, height, maxZ - minZ)
    fog.Position = Vector3.new((minX + maxX) / 2, math.max(minY, maxY) + height / 2, (minZ + maxZ) / 2)
    fog.Parent = swamp

    local particles = Instance.new("ParticleEmitter")
    particles.Name = "PoisonFogParticles"
    particles.Color = ColorSequence.new(fog.Color)
    particles.LightInfluence = 0
    particles.Rate = 35
    particles.Lifetime = NumberRange.new(5, 9)
    particles.Speed = NumberRange.new(0.4, 1.5)
    particles.SpreadAngle = Vector2.new(180, 180)
    particles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.65),
        NumberSequenceKeypoint.new(0.5, 0.82),
        NumberSequenceKeypoint.new(1, 1),
    })
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 8),
        NumberSequenceKeypoint.new(1, 18),
    })
    particles.Parent = fog
end

local function createFallbackSteps(swamp: Instance)
    local bounds = SwampConfig.Bounds
    if not bounds then
        return
    end

    local minX = math.min(bounds.Min.X, bounds.Max.X)
    local maxX = math.max(bounds.Min.X, bounds.Max.X)
    local minY = math.min(bounds.Min.Y, bounds.Max.Y)
    local maxY = math.max(bounds.Min.Y, bounds.Max.Y)
    local minZ = math.min(bounds.Min.Z, bounds.Max.Z)
    local maxZ = math.max(bounds.Min.Z, bounds.Max.Z)
    local startPos = Vector3.new(maxX - 10, maxY + 1.5, minZ + 12)
    local endPos = Vector3.new(minX + 12, maxY + 1.5, maxZ - 12)
    local count = SwampConfig.FallbackStepCount or 10

    for i = 1, count do
        local t = (i - 1) / math.max(1, count - 1)
        local base = startPos:Lerp(endPos, t)
        local wobble = math.sin(t * math.pi * 3) * 18
        local pos = base + Vector3.new(wobble, 0, -wobble * 0.35)

        local step = Instance.new("Part")
        step.Name = SwampConfig.StepPrefix .. tostring(i)
        step.Anchored = true
        step.CanCollide = true
        step.Material = Enum.Material.Grass
        step.Color = Color3.fromRGB(70, 120, 55)
        step.Size = Vector3.new(11, 1, 11)
        step.Position = Vector3.new(pos.X, math.max(minY, math.min(maxY + 2, pos.Y)), pos.Z)
        step.Parent = swamp
    end

    print("[SwampCrossing] Созданы fallback-кочки:", count)
end

local function collectWaypoints(swamp: Instance): { Vector3 }
    local numbered = {}

    for _, desc in ipairs(swamp:GetDescendants()) do
        if desc:IsA("BasePart") then
            local index = string.match(desc.Name, "^" .. SwampConfig.StepPrefix .. "(%d+)$")
            if index then
                table.insert(numbered, {
                    Order = tonumber(index),
                    Position = getStepPosition(desc),
                })
            end
        end
    end

    table.sort(numbered, function(a, b)
        return a.Order < b.Order
    end)

    local waypoints = {}
    for _, entry in ipairs(numbered) do
        table.insert(waypoints, entry.Position)
    end

    return waypoints
end

local function collectConfiguredWaypoints(): { Vector3 }
    local waypoints = {}
    for _, point in ipairs(SwampConfig.RoutePoints or {}) do
        if typeof(point) == "Vector3" then
            table.insert(waypoints, point)
        end
    end
    return waypoints
end

local function getCharacterRoot(player: Player): BasePart?
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getDouRoot(): BasePart?
    local ctrl = getNPCController()
    if not ctrl then
        return nil
    end
    local model = ctrl:GetNPCModel(SwampConfig.GuideNpcId)
    if not model then
        return nil
    end
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function isNearStep(player: Player, waypoints: { Vector3 }): boolean
    local root = getCharacterRoot(player)
    if not root then
        return false
    end
    local r = SwampConfig.StepSafeRadius or 5
    for _, pos in ipairs(waypoints) do
        if flatDistanceXZ(root.Position, pos) <= r then
            return true
        end
    end
    return false
end

local function isSafeFromSwampDamage(player: Player, waypoints: { Vector3 }): boolean
    local root = getCharacterRoot(player)
    if not root then
        return true
    end

    if not isInsideBoundsXZ(root.Position, SwampConfig.Bounds) then
        return true
    end

    if SwampConfig.ProtectNearGuide then
        local douRoot = getDouRoot()
        if douRoot and flatDistanceXZ(root.Position, douRoot.Position) <= (SwampConfig.GuideSafeRadius or 18) then
            return true
        end
    end

    return isNearStep(player, waypoints)
end

local function teleportToCheckpoint(player: Player, position: Vector3)
    local root = getCharacterRoot(player)
    if root then
        root.CFrame = CFrame.new(position)
    end
    Remotes:GetEvent("UpdateHUD"):FireClient(player, {
        Notification = "💧 Ты провалился! Следуй за JOHN DOU по кочкам.",
    })
end

local function stopCrossing(player: Player)
    local data = activeCrossings[player]
    if not data then
        return
    end

    if data.fogConn then
        data.fogConn:Disconnect()
    end
    for _, conn in ipairs(data.fallConns or {}) do
        conn:Disconnect()
    end

    local ctrl = getNPCController()
    if ctrl and ctrl.StopGuide then
        ctrl:StopGuide(SwampConfig.GuideNpcId)
    end

    activeCrossings[player] = nil
end

local function onCrossingComplete(player: Player)
    stopCrossing(player)

    if _G.QuestManager then
        _G.QuestManager:UpdateProgress(player, "REACH_ZONE", "HydraRuins")
        _G.QuestManager:UpdateProgress(player, "SURVIVE", nil)
    end

    Remotes:GetEvent("UpdateHUD"):FireClient(player, {
        Notification = "🏛 JOHN DOU вывел тебя к руинам гидры!",
    })

    print("[SwampCrossing] Пройдено:", player.Name)
end

function SwampCrossing:Start(player: Player)
    if activeCrossings[player] then
        return
    end

    local swamp = findSwampFolder()
    if not swamp then
        warn("[SwampCrossing] Workspace.Zones.Swamp не найден — болото пропущено")
        if _G.GameManager then
            _G.GameManager.SetStage(player, "MINI_BOSS")
        end
        return
    end

    if SwampConfig.GenerateFogVisual then
        ensurePoisonFog(swamp)
    end

    local waypoints = collectWaypoints(swamp)
    if #waypoints == 0 then
        waypoints = collectConfiguredWaypoints()
    end
    if #waypoints == 0 and SwampConfig.GenerateFallbackSteps then
        createFallbackSteps(swamp)
        waypoints = collectWaypoints(swamp)
    end
    if #waypoints == 0 then
        warn("[SwampCrossing] Нет ручного маршрута: добавьте SwampKochka_1..N в Workspace.Zones.Swamp или RoutePoints в StageWorldConfig")
        if _G.GameManager then
            _G.GameManager.SetStage(player, "MINI_BOSS")
        end
        return
    end

    local ctrl = getNPCController()
    if not ctrl or not ctrl.SetGuide then
        warn("[SwampCrossing] NPCController.SetGuide недоступен")
        return
    end

    local checkpoint = waypoints[1]
    activeCrossings[player] = {
        checkpoint = checkpoint,
        waypoints = waypoints,
        fallConns = {},
    }

    Remotes:GetEvent("ShowDialogue"):FireClient(player, DialogueData.BuildShowPayload("DOU_DZOUH_SWAMP", {
        NPCName = "JOHN DOU",
        TrackNPC = "DouDzouh",
    }))

    Remotes:GetEvent("UpdateHUD"):FireClient(player, {
        Notification = "🌫 Следуй за JOHN DOU! Прыгай только по кочкам.",
    })

    ctrl:SetGuide(SwampConfig.GuideNpcId, player, waypoints, {
        waitRadius = SwampConfig.GuideWaitRadius,
        moveTimeout = SwampConfig.MoveTimeout,
        onStepReached = function(stepIndex, pos)
            local data = activeCrossings[player]
            if data then
                data.checkpoint = pos
            end
        end,
        onComplete = function()
            onCrossingComplete(player)
        end,
    })

    local fallConns = {}
    for _, desc in ipairs(swamp:GetDescendants()) do
        if desc:IsA("BasePart") then
            for _, fallName in ipairs(SwampConfig.FallPartNames) do
                if desc.Name == fallName or string.find(desc.Name, fallName, 1, true) then
                    table.insert(fallConns, desc.Touched:Connect(function(hit)
                        local plr = Players:GetPlayerFromCharacter(hit.Parent)
                        if plr == player then
                            local data = activeCrossings[player]
                            if data and data.checkpoint then
                                teleportToCheckpoint(player, data.checkpoint)
                            end
                        end
                    end))
                end
            end
        end
    end
    activeCrossings[player].fallConns = fallConns

    local lastFogDamage = 0
    activeCrossings[player].fogConn = RunService.Heartbeat:Connect(function()
        if getPlayerStage(player) ~= "SWAMP_JOURNEY" then
            stopCrossing(player)
            return
        end

        local data = activeCrossings[player]
        if not data then
            return
        end

        if isSafeFromSwampDamage(player, data.waypoints) then
            return
        end

        local now = tick()
        if now - lastFogDamage < (SwampConfig.FogDamageInterval or 1) then
            return
        end
        lastFogDamage = now

        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            hum:TakeDamage(SwampConfig.FogDamagePerTick or 8)
        end
    end)

    print("[SwampCrossing] Старт для", player.Name, "| кочек:", #waypoints)
end

function SwampCrossing:Stop(player: Player)
    stopCrossing(player)
end

Players.PlayerRemoving:Connect(function(player)
    SwampCrossing:Stop(player)
end)

return SwampCrossing
