--[[
    SwampCrossing — проводник JOHN DOU через болото с ядовитым туманом
    Workspace.Zones.Swamp: кочки SwampKochka_1 … N, туман, SwampFall, выход у гидры.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SwampConfig = require(ServerScriptService:WaitForChild("SwampConfig"))
local DialogueData = require(ServerScriptService:WaitForChild("DialogueData"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local SwampCrossing = {}

local activeCrossings = {} -- [Player] = { checkpoint, fogConn, fallConns, guideToken }
local stepStates = {} -- [BasePart] = { Started = boolean, Sunk = boolean }

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

local function getHitPlayer(hit: BasePart): Player?
    local model = hit:FindFirstAncestorOfClass("Model")
    if not model then
        return nil
    end
    return Players:GetPlayerFromCharacter(model)
end

local function getRouteRandom(): Random
    if SwampConfig.RouteSeed then
        return Random.new(SwampConfig.RouteSeed)
    end
    return Random.new()
end

local function getCorridorCenterSegment(corridor)
    local a = corridor.A
    local b = corridor.B
    local dx = math.abs(a.X - b.X)
    local dz = math.abs(a.Z - b.Z)
    local y = (a.Y + b.Y) / 2

    if dx >= dz then
        local z = (a.Z + b.Z) / 2
        return Vector3.new(a.X, y, z), Vector3.new(b.X, y, z)
    end

    local x = (a.X + b.X) / 2
    return Vector3.new(x, y, a.Z), Vector3.new(x, y, b.Z)
end

local function appendRouteLine(points: { Vector3 }, fromPos: Vector3, toPos: Vector3, rng: Random)
    local distance = flatDistanceXZ(fromPos, toPos)
    if distance <= 0.1 then
        return
    end

    local minStep = SwampConfig.RouteStepMinDistance or 14
    local maxStep = math.max(minStep, SwampConfig.RouteStepMaxDistance or 18)
    local sideJitter = SwampConfig.RouteSideJitter or 0
    local forwardJitter = SwampConfig.RouteForwardJitter or 0
    local dir = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z).Unit
    local side = Vector3.new(-dir.Z, 0, dir.X)

    local traveled = 0
    while distance - traveled > maxStep do
        traveled += rng:NextNumber(minStep, maxStep)
        local base = fromPos + dir * traveled
        local jittered = base
            + side * rng:NextNumber(-sideJitter, sideJitter)
            + dir * rng:NextNumber(-forwardJitter, forwardJitter)
        table.insert(points, Vector3.new(jittered.X, base.Y, jittered.Z))
    end

    table.insert(points, toPos)
end

local function buildCorridorRoute(): { Vector3 }
    local corridors = SwampConfig.PathCorridors or {}
    local points = {}
    local rng = getRouteRandom()

    for _, corridor in ipairs(corridors) do
        if corridor.A and corridor.B then
            local startPos, endPos = getCorridorCenterSegment(corridor)
            if #points == 0 then
                table.insert(points, startPos)
            else
                appendRouteLine(points, points[#points], startPos, rng)
            end
            appendRouteLine(points, points[#points], endPos, rng)
        end
    end

    return points
end

local function createRouteStep(parent: Instance, index: number, position: Vector3): BasePart
    local size = SwampConfig.StepSize or Vector3.new(10, 1.2, 10)
    local model = Instance.new("Model")
    model.Name = SwampConfig.StepPrefix .. tostring(index)
    model.Parent = parent

    local step = Instance.new("Part")
    step.Name = SwampConfig.StepPrefix .. tostring(index)
    step.Anchored = true
    step.CanCollide = true
    step.CanTouch = true
    step.CanQuery = true
    step.Material = Enum.Material.SmoothPlastic
    step.Color = Color3.fromRGB(70, 110, 55)
    step.Transparency = 0.25
    step.Size = size
    step.Position = Vector3.new(position.X, position.Y + size.Y / 2, position.Z)
    step:SetAttribute("SwampStepIndex", index)
    step:SetAttribute("GeneratedSwampStep", true)
    step.Parent = model
    model.PrimaryPart = step

    local blobCount = math.random(5, 8)
    for blobIndex = 1, blobCount do
        local blob = Instance.new("Part")
        blob.Name = "MossBlob_" .. tostring(blobIndex)
        blob.Shape = Enum.PartType.Ball
        blob.Anchored = true
        blob.CanCollide = false
        blob.CanTouch = false
        blob.CanQuery = false
        blob.Material = (blobIndex % 3 == 0) and Enum.Material.Mud or Enum.Material.Grass
        blob.Color = (blob.Material == Enum.Material.Mud)
            and Color3.fromRGB(74, 58, 36)
            or Color3.fromRGB(54 + math.random(0, 28), 105 + math.random(0, 35), 42)

        local angle = math.random() * math.pi * 2
        local radius = math.random() * size.X * 0.26
        local blobX = math.cos(angle) * radius
        local blobZ = math.sin(angle) * radius
        local blobSizeX = math.random(22, 42) / 10
        local blobSizeY = math.random(14, 24) / 10
        local blobSizeZ = math.random(22, 42) / 10
        blob.Size = Vector3.new(blobSizeX, blobSizeY, blobSizeZ)
        blob.Position = step.Position + Vector3.new(blobX, size.Y / 2 + blobSizeY * 0.15, blobZ)
        blob.Parent = model
    end

    return step
end

local function generateRouteSteps(swamp: Instance): Instance?
    local folderName = SwampConfig.GeneratedFolderName or "GeneratedSwampKochki"
    local existing = swamp:FindFirstChild(folderName)
    if existing and SwampConfig.RegenerateRouteSteps then
        existing:Destroy()
        existing = nil
    end
    if existing then
        return existing
    end

    local route = buildCorridorRoute()
    if #route == 0 then
        return nil
    end

    local folder = Instance.new("Folder")
    folder.Name = folderName
    folder.Parent = swamp

    for index, position in ipairs(route) do
        createRouteStep(folder, index, position)
    end

    print("[SwampCrossing] Сгенерирован маршрут кочек:", #route)
    return folder
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

local function collectStepEntries(root: Instance)
    local numbered = {}

    for _, desc in ipairs(root:GetDescendants()) do
        if desc:IsA("BasePart") then
            local index = string.match(desc.Name, "^" .. SwampConfig.StepPrefix .. "(%d+)$")
            if index then
                table.insert(numbered, {
                    Order = tonumber(index),
                    Part = desc,
                    Position = getStepPosition(desc),
                })
            end
        end
    end

    table.sort(numbered, function(a, b)
        return a.Order < b.Order
    end)

    return numbered
end

local function collectWaypoints(entries): { Vector3 }
    local waypoints = {}
    for _, entry in ipairs(entries or {}) do
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

local function getNearestActiveStepDistance(position: Vector3, data): number?
    local nearest: number? = nil
    for _, entry in ipairs(data.stepEntries or {}) do
        local state = entry.Part and stepStates[entry.Part]
        if not state or not state.Sunk then
            local distance = flatDistanceXZ(position, entry.Position)
            if not nearest or distance < nearest then
                nearest = distance
            end
        end
    end

    if not nearest then
        for _, pos in ipairs(data.waypoints or {}) do
            local distance = flatDistanceXZ(position, pos)
            if not nearest or distance < nearest then
                nearest = distance
            end
        end
    end

    return nearest
end

local function getSwampDanger(player: Player, data)
    local root = getCharacterRoot(player)
    if not root then
        return false, 0
    end

    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        local state = hum:GetState()
        if state == Enum.HumanoidStateType.Jumping
            or state == Enum.HumanoidStateType.Freefall
            or state == Enum.HumanoidStateType.FallingDown then
            return false, 0
        end
    end

    if math.abs(root.AssemblyLinearVelocity.Y) > 3 then
        return false, 0
    end

    if not isInsideBoundsXZ(root.Position, SwampConfig.Bounds) then
        return false, 0
    end

    if SwampConfig.ProtectNearGuide then
        local douRoot = getDouRoot()
        if douRoot and flatDistanceXZ(root.Position, douRoot.Position) <= (SwampConfig.GuideSafeRadius or 18) then
            return false, 0
        end
    end

    local nearest = getNearestActiveStepDistance(root.Position, data)
    if nearest and nearest <= (SwampConfig.StepSafeRadius or 5) then
        return false, nearest
    end

    return true, nearest or (SwampConfig.StepSafeRadius or 5)
end

local function calculateSwampDamage(distanceFromStep: number): number
    local base = SwampConfig.FogDamagePerTick or 5
    local radius = SwampConfig.StepSafeRadius or 5
    local scale = SwampConfig.FogDamageDistanceScale or 0.3
    local maxDamage = SwampConfig.FogDamageMaxPerTick or 22
    local extra = math.max(0, distanceFromStep - radius) * scale
    return math.clamp(math.floor(base + extra + 0.5), base, maxDamage)
end

local function startSinkingStep(entry)
    local part = entry.Part
    if not part then
        return
    end

    local state = stepStates[part]
    if state and state.Started then
        return
    end

    state = state or {}
    state.Started = true
    state.Sunk = false
    stepStates[part] = state

    local minSeconds = SwampConfig.StepSinkMinSeconds or 3
    local maxSeconds = math.max(minSeconds, SwampConfig.StepSinkMaxSeconds or 5)
    local duration = math.random(math.floor(minSeconds * 100), math.floor(maxSeconds * 100)) / 100
    local depth = SwampConfig.StepSinkDepth or 9
    part:SetAttribute("Sinking", true)

    local sinkRoot = part.Parent and part.Parent:IsA("Model") and part.Parent or part
    for _, inst in ipairs(sinkRoot:GetDescendants()) do
        if inst:IsA("BasePart") then
            local tween = TweenService:Create(inst, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = inst.Position - Vector3.new(0, depth, 0),
                Transparency = 1,
            })
            tween:Play()
        end
    end

    task.delay(duration, function()
        if part.Parent then
            state.Sunk = true
            for _, inst in ipairs(sinkRoot:GetDescendants()) do
                if inst:IsA("BasePart") then
                    inst.CanCollide = false
                    inst.CanTouch = false
                    inst.CanQuery = false
                end
            end
            part:SetAttribute("Sunk", true)
        end
    end)
end

local function connectStepSinking(player: Player, data)
    local conns = {}
    for _, entry in ipairs(data.stepEntries or {}) do
        local part = entry.Part
        if part then
            stepStates[part] = stepStates[part] or { Started = false, Sunk = false }
            table.insert(conns, part.Touched:Connect(function(hit)
                local plr = getHitPlayer(hit)
                if plr ~= player then
                    return
                end

                data.playerStepIndex = math.max(data.playerStepIndex or 0, entry.Order or 0)
                data.checkpoint = entry.Position
                startSinkingStep(entry)
            end))
        end
    end
    return conns
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
    for _, conn in ipairs(data.sinkingConns or {}) do
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

    local routeRoot = swamp
    if SwampConfig.GenerateRouteSteps then
        routeRoot = generateRouteSteps(swamp) or swamp
    end

    local stepEntries = collectStepEntries(routeRoot)
    local waypoints = collectWaypoints(stepEntries)
    if #waypoints == 0 and not SwampConfig.GenerateRouteSteps then
        waypoints = collectConfiguredWaypoints()
    end
    if #waypoints == 0 and not SwampConfig.GenerateRouteSteps and SwampConfig.GenerateFallbackSteps then
        createFallbackSteps(swamp)
        stepEntries = collectStepEntries(swamp)
        waypoints = collectWaypoints(stepEntries)
    end
    if #waypoints == 0 then
        warn("[SwampCrossing] Нет маршрута болота: проверьте PathCorridors, SwampKochka_1..N или RoutePoints")
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
        stepEntries = stepEntries,
        playerStepIndex = 0,
        fallConns = {},
        sinkingConns = {},
    }
    activeCrossings[player].sinkingConns = connectStepSinking(player, activeCrossings[player])

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
        waitEveryStep = false,
        maxLeadSteps = SwampConfig.MaxGuideLeadSteps,
        hurryInterval = SwampConfig.GuideHurryInterval,
        getPlayerStepIndex = function()
            local data = activeCrossings[player]
            return data and data.playerStepIndex or 0
        end,
        hurryMessage = function(ahead)
            return string.format("JOHN DOU: Не отставай. Я уже на %d кочки впереди.", ahead)
        end,
        onStepReached = function(stepIndex, pos)
            local data = activeCrossings[player]
            if data then
                data.guideStepIndex = stepIndex
            end
        end,
        onComplete = function()
            onCrossingComplete(player)
        end,
    })

    local fallConns = {}
    if SwampConfig.TeleportOnFallParts then
        for _, desc in ipairs(swamp:GetDescendants()) do
            if desc:IsA("BasePart") then
                for _, fallName in ipairs(SwampConfig.FallPartNames) do
                    if desc.Name == fallName or string.find(desc.Name, fallName, 1, true) then
                        table.insert(fallConns, desc.Touched:Connect(function(hit)
                            local plr = getHitPlayer(hit)
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
    end
    activeCrossings[player].fallConns = fallConns

    local lastFogDamage = 0
    local lastDamageNotice = 0
    activeCrossings[player].fogConn = RunService.Heartbeat:Connect(function()
        if getPlayerStage(player) ~= "SWAMP_JOURNEY" then
            stopCrossing(player)
            return
        end

        local data = activeCrossings[player]
        if not data then
            return
        end

        local dangerous, distanceFromStep = getSwampDanger(player, data)
        if not dangerous then
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
            local damage = calculateSwampDamage(distanceFromStep)
            hum:TakeDamage(damage)
            if now - lastDamageNotice >= 4 then
                lastDamageNotice = now
                Remotes:GetEvent("UpdateHUD"):FireClient(player, {
                    Notification = string.format("Болото бьёт сильнее вдали от кочек: -%d HP", damage),
                })
            end
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
