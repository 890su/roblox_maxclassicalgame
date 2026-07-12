--[[
    TombWindTurbinePuzzle — ветряк у гробницы убивает гидру
    ═══════════════════════════════════════════════════════════

    Workspace.Zones.Tomb.WindTurbine:
      • Стоя у основания — ProximityPrompt «Толкнуть» (без лазания наверх)
      • Ветряк падает в сторону King Hydra Blaster
      • При попадании — MiniBossSpawner:KillByTurbine

    Маркер в Studio (опционально): Part «WindTurbinePush» у основания модели.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(ServerScriptService:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ZONES_FOLDER_NAME = "Zones"
local TOMB_FOLDER_NAME = "Tomb"
local TURBINE_NAME = "WindTurbine"
local PUSH_PART_NAME = "WindTurbinePush"
local CLOUD_NAME = "PoisonCloudTrap"
local HYDRA_NAME = "KingHydraBlaster"

local SEARCH_TIMEOUT = 60

local cfg = GameConfig.WindTurbine or {}

local pushed = false

local function waitForTombFolder(): Instance?
    local zones = Workspace:WaitForChild(ZONES_FOLDER_NAME, SEARCH_TIMEOUT)
    if not zones then
        warn("[TombWindTurbinePuzzle] Workspace." .. ZONES_FOLDER_NAME .. " не найден")
        return nil
    end

    local tomb = zones:WaitForChild(TOMB_FOLDER_NAME, SEARCH_TIMEOUT)
    if not tomb then
        warn("[TombWindTurbinePuzzle] Workspace.Zones." .. TOMB_FOLDER_NAME .. " не найден")
        return nil
    end

    return tomb
end

local function getPivot(inst: Instance): CFrame?
    if inst:IsA("Model") then
        return inst:GetPivot()
    end
    if inst:IsA("BasePart") then
        return inst.CFrame
    end
    return nil
end

local function pivotTo(inst: Instance, cf: CFrame)
    if inst:IsA("Model") then
        inst:PivotTo(cf)
    elseif inst:IsA("BasePart") then
        inst.CFrame = cf
    end
end

local function ensurePushPart(turbine: Instance): BasePart
    local marker = turbine:FindFirstChild(PUSH_PART_NAME, true)
    if marker and marker:IsA("BasePart") then
        marker.CanCollide = false
        return marker
    end

    local bbCf, bbSize
    if turbine:IsA("Model") then
        bbCf, bbSize = turbine:GetBoundingBox()
    else
        local part = turbine :: BasePart
        bbCf, bbSize = part.CFrame, part.Size
    end

    local pushSize = cfg.PushPartSize or Vector3.new(5, 2.5, 5)
    local groundY = bbCf.Position.Y - bbSize.Y / 2

    local pushPart = Instance.new("Part")
    pushPart.Name = PUSH_PART_NAME
    pushPart.Size = pushSize
    pushPart.CFrame = CFrame.new(bbCf.Position.X, groundY + pushSize.Y / 2, bbCf.Position.Z)
    pushPart.Transparency = 1
    pushPart.CanCollide = false
    pushPart.Anchored = true
    pushPart.CanQuery = false
    pushPart.Parent = turbine

    return pushPart
end

local function anchorTurbine(turbine: Instance, anchored: boolean)
    for _, part in ipairs(turbine:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = anchored
            if anchored then
                part.AssemblyLinearVelocity = Vector3.zero
                part.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end
    if turbine:IsA("BasePart") then
        turbine.Anchored = anchored
    end
end

local function findPoisonClouds(tomb: Instance): { Instance }
    local clouds = {}
    for _, child in ipairs(tomb:GetChildren()) do
        if child.Name == CLOUD_NAME and (child:IsA("Model") or child:IsA("BasePart")) then
            table.insert(clouds, child)
        end
    end
    return clouds
end

local function getPlayerStage(player: Player): string?
    if _G.GameManager and _G.GameManager.GetPlayerState then
        local state = _G.GameManager.GetPlayerState(player)
        return state and state.Stage or nil
    end
    return nil
end

local function findHydra(player: Player): Model?
    if _G.MiniBossSpawner and _G.MiniBossSpawner.GetActiveBoss then
        local boss = _G.MiniBossSpawner:GetActiveBoss(player)
        if boss then
            return boss
        end
    end

    local found = Workspace:FindFirstChild(HYDRA_NAME, true)
    if found and found:IsA("Model") then
        return found
    end
    return nil
end

local function getHydraRoot(hydra: Model): BasePart?
    return hydra:FindFirstChild("HumanoidRootPart")
        or hydra.PrimaryPart
        or hydra:FindFirstChildWhichIsA("BasePart", true)
end

local function canPushTurbine(player: Player): boolean
    if pushed then
        return false
    end
    if getPlayerStage(player) ~= "MINI_BOSS" then
        return false
    end

    local hydra = findHydra(player)
    if not hydra then
        return false
    end

    local hum = hydra:FindFirstChildWhichIsA("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function tweenPivot(inst: Instance, targetCf: CFrame, duration: number)
    local startCf = getPivot(inst)
    if not startCf then
        return
    end

    local cfValue = Instance.new("CFrameValue")
    cfValue.Value = startCf
    cfValue:GetPropertyChangedSignal("Value"):Connect(function()
        if inst.Parent then
            pivotTo(inst, cfValue.Value)
        end
    end)

    local tween = TweenService:Create(
        cfValue,
        TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { Value = targetCf }
    )

    tween:Play()
    tween.Completed:Wait()
    cfValue:Destroy()
end

local function computeFallTargetCf(turbine: Instance, hydraPos: Vector3): CFrame?
    local startCf = getPivot(turbine)
    if not startCf then
        return nil
    end

    local bbCf, bbSize
    if turbine:IsA("Model") then
        bbCf, bbSize = turbine:GetBoundingBox()
    else
        bbCf, bbSize = startCf, turbine.Size
    end

    local basePoint = bbCf.Position - bbCf.UpVector * (bbSize.Y / 2)

    local flatDir = Vector3.new(hydraPos.X - basePoint.X, 0, hydraPos.Z - basePoint.Z)
    if flatDir.Magnitude < 1 then
        flatDir = Vector3.new(startCf.LookVector.X, 0, startCf.LookVector.Z)
    end
    if flatDir.Magnitude < 0.1 then
        flatDir = Vector3.new(0, 0, -1)
    end
    flatDir = flatDir.Unit

    local tipAxis = flatDir:Cross(Vector3.yAxis)
    if tipAxis.Magnitude < 0.01 then
        tipAxis = Vector3.xAxis
    end
    tipAxis = tipAxis.Unit

    local angle = math.rad(cfg.FallAngleDeg or 88)
    local rotation = CFrame.fromAxisAngle(tipAxis, -angle)

    return CFrame.new(basePoint) * rotation * CFrame.new(-basePoint) * startCf
end

local function fadeCloudParts(cloud: Instance)
    for _, part in ipairs(cloud:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanTouch = false
            part.CanCollide = false
            TweenService:Create(
                part,
                TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { Transparency = 1 }
            ):Play()
        elseif part:IsA("ParticleEmitter") then
            part.Enabled = false
        end
    end
end

local function blowCloudsAway(turbine: Instance, clouds: { Instance })
    local turbineCf = getPivot(turbine)
    if not turbineCf then
        return
    end

    for _, cloud in ipairs(clouds) do
        if not cloud.Parent then
            continue
        end
        local cloudCf = getPivot(cloud)
        if not cloudCf then
            continue
        end

        local away = Vector3.new(
            cloudCf.Position.X - turbineCf.Position.X,
            0,
            cloudCf.Position.Z - turbineCf.Position.Z
        )
        if away.Magnitude < 0.1 then
            away = Vector3.new(1, 0, 0)
        end

        fadeCloudParts(cloud)
        local targetCf = cloudCf + away.Unit * 60 + Vector3.new(0, 6, 0)
        task.spawn(function()
            tweenPivot(cloud, targetCf, 2.5)
            task.wait(3)
            if cloud.Parent then
                cloud:Destroy()
            end
        end)
    end
end

local function killHydraWithTurbine(player: Player): boolean
    if _G.MiniBossSpawner and _G.MiniBossSpawner.KillByTurbine then
        return _G.MiniBossSpawner:KillByTurbine(player)
    end

    local hydra = findHydra(player)
    if not hydra then
        return false
    end
    local hum = hydra:FindFirstChildWhichIsA("Humanoid")
    if hum and hum.Health > 0 then
        hum.Health = 0
        return true
    end
    return false
end

local function pushTurbine(player: Player, turbine: Instance, tomb: Instance, prompt: ProximityPrompt)
    if not canPushTurbine(player) then
        return
    end

    local hydra = findHydra(player)
    local hydraRoot = hydra and getHydraRoot(hydra)
    if not hydraRoot then
        warn("[TombWindTurbinePuzzle] Гидра не найдена для падения ветряка")
        return
    end

    pushed = true
    prompt.Enabled = false

    print("[TombWindTurbinePuzzle] Толчок:", player.Name, "→ гидра в", tostring(hydraRoot.Position))

    Remotes:GetEvent("UpdateHUD"):FireClient(player, {
        Notification = "💨 Ветряк падает на гидру!",
    })

    if cfg.ClearCloudsOnPush ~= false then
        local clouds = findPoisonClouds(tomb)
        if #clouds > 0 then
            blowCloudsAway(turbine, clouds)
        end
    end

    anchorTurbine(turbine, true)

    local targetCf = computeFallTargetCf(turbine, hydraRoot.Position)
    if not targetCf then
        warn("[TombWindTurbinePuzzle] Не удалось вычислить траекторию падения")
        return
    end

    local fallDuration = cfg.FallDuration or 1.8
    local killRadius = cfg.KillRadius or 22
    local hydraKilled = false

    local function tryKill()
        if hydraKilled then
            return
        end
        if killHydraWithTurbine(player) then
            hydraKilled = true
            Remotes:GetEvent("UpdateHUD"):FireClient(player, {
                Notification = "✅ Ветряк раздавил King Hydra Blaster!",
            })
        end
    end

    local monitorConn
    monitorConn = RunService.Heartbeat:Connect(function()
        if hydraKilled or not hydraRoot.Parent then
            if monitorConn then
                monitorConn:Disconnect()
            end
            return
        end

        local turbinePos = getPivot(turbine)
        if not turbinePos then
            return
        end

        if (turbinePos.Position - hydraRoot.Position).Magnitude <= killRadius then
            if monitorConn then
                monitorConn:Disconnect()
            end
            tryKill()
        end
    end)

    task.spawn(function()
        tweenPivot(turbine, targetCf, fallDuration)
        anchorTurbine(turbine, true)

        if monitorConn then
            monitorConn:Disconnect()
        end
        if not hydraKilled then
            tryKill()
        end
    end)
end

local function hookPuzzle()
    local tomb = waitForTombFolder()
    if not tomb then
        return
    end

    local turbine = tomb:WaitForChild(TURBINE_NAME, SEARCH_TIMEOUT)
    if not turbine then
        warn("[TombWindTurbinePuzzle] WindTurbine не найден в Workspace.Zones.Tomb")
        return
    end

    local host = ensurePushPart(turbine)
    if not host then
        warn("[TombWindTurbinePuzzle] Не удалось создать зону толчка у основания WindTurbine")
        return
    end

    anchorTurbine(turbine, true)

    local prompt = host:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        prompt = Instance.new("ProximityPrompt")
        prompt.Parent = host
    end

    prompt.ObjectText = "Ветряк"
    prompt.ActionText = "Толкнуть"
    prompt.HoldDuration = cfg.PushHoldDuration or 0.6
    prompt.MaxActivationDistance = cfg.PushMaxDistance or 10
    prompt.RequiresLineOfSight = false
    prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
    prompt.UIOffset = Vector3.new(0, 1.5, 0)

    prompt.Triggered:Connect(function(player)
        pushTurbine(player, turbine, tomb, prompt)
    end)

    print("[TombWindTurbinePuzzle] Готово: толчок у основания WindTurbine → падение на гидру")
end

task.spawn(hookPuzzle)
