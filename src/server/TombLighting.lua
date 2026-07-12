--[[
    TombLighting — атмосферный свет гробницы и временный фонарь игрока.

    Модуль работает поверх готовой карты из Studio: ищет Workspace.Mazegame.MAZE,
    ставит приглушённые тёплые источники света под потолком модели и даёт игроку
    временный свет, пока он находится внутри лабиринта.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local TombLighting = {}

local ATMOSPHERE_FOLDER_NAME = "TombAtmosphereLights"
local ATMOSPHERE_SOURCE = "Mazegame.MAZE"
local PLAYER_LIGHT_NAME = "Фонарь гробницы"
local CHARACTER_LIGHT_NAME = "TombPlayerLight"

local LIGHT_COUNT = 22
local LIGHT_SEED = 1812
local PLAYER_BOUNDS_MARGIN = 8
local LANTERN_RANGE = 48
local LANTERN_ANGLE = 34

local GOLEM_NAME = "Parallel Brute"
local GOLEM_WAKE_DISTANCE = 14
local GOLEM_ATTACK_RANGE = 6
local GOLEM_RUN_SPEED = 13
local GOLEM_DAMAGE = 18
local GOLEM_ATTACK_COOLDOWN = 1.2

local watcherStarted = false
local golemWatcherStarted = false

local function getOrCreateFolder(parent: Instance, name: string): Folder
    local folder = parent:FindFirstChild(name)
    if folder and folder:IsA("Folder") then
        return folder
    end

    folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

local function findMazeModel(): Model?
    local mazeGame = Workspace:FindFirstChild("Mazegame") or Workspace:FindFirstChild("MazeGame")
    local maze = mazeGame and mazeGame:FindFirstChild("MAZE")
    if maze and maze:IsA("Model") then
        return maze
    end

    maze = Workspace:FindFirstChild("MAZE", true)
    if maze and maze:IsA("Model") then
        return maze
    end

    return nil
end

local function findMazeContainer(): Instance?
    return Workspace:FindFirstChild("Mazegame") or Workspace:FindFirstChild("MazeGame")
end

local function getMazeBounds(): (CFrame?, Vector3?)
    local maze = findMazeModel()
    if not maze then
        return nil, nil
    end

    local cf, size = maze:GetBoundingBox()
    return cf, size
end

local function isInsideMaze(position: Vector3): boolean
    local cf, size = getMazeBounds()
    if not cf or not size then
        return false
    end

    local localPos = cf:PointToObjectSpace(position)
    local half = (size / 2) + Vector3.new(PLAYER_BOUNDS_MARGIN, PLAYER_BOUNDS_MARGIN, PLAYER_BOUNDS_MARGIN)
    return math.abs(localPos.X) <= half.X
        and math.abs(localPos.Y) <= half.Y
        and math.abs(localPos.Z) <= half.Z
end

local function getModelRoot(model: Model): BasePart?
    local root = model:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        return root
    end
    if model.PrimaryPart then
        return model.PrimaryPart
    end
    return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getPlayerRoot(player: Player): BasePart?
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        return root
    end
    return nil
end

local function getModelProbePoints(model: Model, root: BasePart): { Vector3 }
    local cf, size = model:GetBoundingBox()
    return {
        root.Position,
        cf.Position,
        (cf * CFrame.new(0, size.Y * 0.25, 0)).Position,
        (cf * CFrame.new(0, size.Y * 0.4, 0)).Position,
    }
end

local function collectNamedCeilingParts(maze: Model): { BasePart }
    local parts = {}
    for _, inst in ipairs(maze:GetDescendants()) do
        if inst:IsA("BasePart") then
            local name = string.lower(inst.Name)
            if string.find(name, "ceiling") or string.find(name, "roof") then
                table.insert(parts, inst)
            end
        end
    end
    return parts
end

local function hasTool(player: Player, toolName: string): boolean
    local backpack = player:FindFirstChild("Backpack")
    if backpack and backpack:FindFirstChild(toolName) then
        return true
    end
    return player.Character ~= nil and player.Character:FindFirstChild(toolName) ~= nil
end

local function hasLantern(player: Player): boolean
    return player:GetAttribute("HasTombPlayerLight") == true or hasTool(player, PLAYER_LIGHT_NAME)
end

local function getEquippedLantern(player: Player): Tool?
    local character = player.Character
    local tool = character and character:FindFirstChild(PLAYER_LIGHT_NAME)
    if tool and tool:IsA("Tool") then
        return tool
    end
    return nil
end

local function removeTool(container: Instance?, toolName: string)
    if not container then
        return
    end

    local tool = container:FindFirstChild(toolName)
    if tool then
        tool:Destroy()
    end
end

local function isLanternEnabled(player: Player): boolean
    return player:GetAttribute("TombLanternEnabled") == true
end

local function isLightInstance(inst: Instance): boolean
    return inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight")
end

local function applyLightEnabled(inst: Instance, enabled: boolean)
    if not isLightInstance(inst) then
        return
    end

    local light = inst :: PointLight
    light.Enabled = enabled
    light.Brightness = enabled and 3.2 or 0
end

local function hasActiveEquippedLanternBeam(player: Player): boolean
    local tool = getEquippedLantern(player)
    if not tool then
        return false
    end

    for _, inst in ipairs(tool:GetDescendants()) do
        if isLightInstance(inst) and inst.Name == "LanternBeam" then
            local light = inst :: PointLight
            if light.Enabled and light.Brightness > 0 then
                return true
            end
        end
    end

    return false
end

local function removeCharacterLight(player: Player)
    local hrp = getPlayerRoot(player)
    if not hrp then
        return
    end

    for _, child in ipairs(hrp:GetChildren()) do
        if child.Name == CHARACTER_LIGHT_NAME and isLightInstance(child) then
            child:Destroy()
        end
    end
end

local function isLanternLightName(name: string): boolean
    return name == CHARACTER_LIGHT_NAME or name == "LanternBeam" or name == "LanternLight"
end

local function cleanupLegacyLanternLights(player: Player, keepToolLights: boolean)
    for _, container in ipairs({ player.Character, player:FindFirstChild("Backpack") }) do
        if not container then
            continue
        end

        for _, inst in ipairs(container:GetDescendants()) do
            if isLightInstance(inst) and isLanternLightName(inst.Name) then
                local tool = inst:FindFirstAncestorOfClass("Tool")
                if keepToolLights and tool and tool.Name == PLAYER_LIGHT_NAME then
                    continue
                end
                inst:Destroy()
            end
        end
    end
end

local function setLanternEnabled(player: Player, enabled: boolean)
    player:SetAttribute("TombLanternEnabled", enabled)

    cleanupLegacyLanternLights(player, true)

    for _, container in ipairs({ player.Character, player:FindFirstChild("Backpack") }) do
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Tool") and child.Name == PLAYER_LIGHT_NAME then
                    for _, inst in ipairs(child:GetDescendants()) do
                        if isLightInstance(inst) then
                            applyLightEnabled(inst, enabled)
                        end
                    end
                end
            end
        end
    end
end

local function createPlayerLightTool(): Tool
    local tool = Instance.new("Tool")
    tool.Name = PLAYER_LIGHT_NAME
    tool.CanBeDropped = false
    tool.RequiresHandle = true
    tool.GripPos = Vector3.new(0, -0.2, -0.25)
    tool.GripForward = Vector3.new(0, 0, -1)
    tool.GripRight = Vector3.new(1, 0, 0)
    tool.GripUp = Vector3.new(0, 1, 0)

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.45, 0.65, 0.45)
    handle.Color = Color3.fromRGB(110, 82, 45)
    handle.Material = Enum.Material.Metal
    handle.CanCollide = false
    handle.Massless = true
    handle.Parent = tool

    local glow = Instance.new("Part")
    glow.Name = "Lens"
    glow.Shape = Enum.PartType.Ball
    glow.Size = Vector3.new(0.35, 0.35, 0.35)
    glow.Color = Color3.fromRGB(255, 205, 115)
    glow.Material = Enum.Material.Neon
    glow.CanCollide = false
    glow.Massless = true
    glow.CFrame = handle.CFrame * CFrame.new(0, 0.1, -0.45)
    glow.Parent = tool

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = handle
    weld.Part1 = glow
    weld.Parent = glow

    local spotLight = Instance.new("SpotLight")
    spotLight.Name = "LanternBeam"
    spotLight.Color = Color3.fromRGB(255, 214, 145)
    spotLight.Brightness = 3.2
    spotLight.Range = LANTERN_RANGE
    spotLight.Angle = LANTERN_ANGLE
    spotLight.Face = Enum.NormalId.Front
    spotLight.Shadows = true
    spotLight.Parent = handle

    tool.Activated:Connect(function()
        local player = Players:GetPlayerFromCharacter(tool.Parent)
        if not player then
            return
        end
        local enabled = not isLanternEnabled(player)
        setLanternEnabled(player, enabled)
        print(
            "[TombLighting] Фонарь",
            enabled and "включён" or "выключен",
            "|",
            player.Name,
            "| activeBeam:",
            hasActiveEquippedLanternBeam(player)
        )
    end)

    return tool
end

function TombLighting:InitAtmosphericLights()
    local existing = Workspace:FindFirstChild(ATMOSPHERE_FOLDER_NAME)
    if existing and existing:GetAttribute("Source") == ATMOSPHERE_SOURCE then
        return
    end
    if existing then
        existing:Destroy()
    end

    task.spawn(function()
        task.wait(2)

        local existingAfterWait = Workspace:FindFirstChild(ATMOSPHERE_FOLDER_NAME)
        if existingAfterWait and existingAfterWait:GetAttribute("Source") == ATMOSPHERE_SOURCE then
            return
        end
        if existingAfterWait then
            existingAfterWait:Destroy()
        end

        local maze = findMazeModel()
        if not maze then
            warn("[TombLighting] Не найдена модель Workspace.Mazegame.MAZE — атмосферный свет не создан")
            return
        end

        local folder = getOrCreateFolder(Workspace, ATMOSPHERE_FOLDER_NAME)
        folder:SetAttribute("Source", ATMOSPHERE_SOURCE)
        local rng = Random.new(LIGHT_SEED)
        local created = 0

        local mazeCf, mazeSize = maze:GetBoundingBox()
        local ceilingParts = collectNamedCeilingParts(maze)

        for i = 1, LIGHT_COUNT do
            if created >= LIGHT_COUNT then
                break
            end

            local position
            if #ceilingParts > 0 then
                local part = ceilingParts[rng:NextInteger(1, #ceilingParts)]
                local localX = rng:NextNumber(-part.Size.X * 0.42, part.Size.X * 0.42)
                local localZ = rng:NextNumber(-part.Size.Z * 0.42, part.Size.Z * 0.42)
                position = (part.CFrame * CFrame.new(localX, -part.Size.Y / 2 - 0.8, localZ)).Position
            else
                local localX = rng:NextNumber(-mazeSize.X * 0.42, mazeSize.X * 0.42)
                local localZ = rng:NextNumber(-mazeSize.Z * 0.42, mazeSize.Z * 0.42)
                local localY = mazeSize.Y / 2 - 4 - (i % 3)
                position = (mazeCf * CFrame.new(localX, localY, localZ)).Position
            end

            created += 1

            local holder = Instance.new("Part")
            holder.Name = "TombCeilingGlow_" .. created
            holder.Size = Vector3.new(0.35, 0.35, 0.35)
            holder.Position = position
            holder.Anchored = true
            holder.CanCollide = false
            holder.CanTouch = false
            holder.Transparency = 1
            holder.Parent = folder

            local light = Instance.new("PointLight")
            light.Name = "WarmAtmosphereLight"
            light.Color = Color3.fromRGB(255, 213, 145)
            light.Brightness = rng:NextNumber(0.35, 0.65)
            light.Range = rng:NextNumber(18, 28)
            light.Shadows = false
            light.Parent = holder
        end

        print("[TombLighting] Атмосферные огни MAZE:", created, "| центр:", mazeCf.Position)
    end)
end

function TombLighting:GivePlayerLight(player: Player)
    if player:GetAttribute("TombLanternEnabled") == nil then
        player:SetAttribute("TombLanternEnabled", true)
    end

    cleanupLegacyLanternLights(player, true)

    if hasTool(player, PLAYER_LIGHT_NAME) then
        setLanternEnabled(player, isLanternEnabled(player))
        player:SetAttribute("HasTombPlayerLight", true)
        return
    end

    local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 10)
    if not backpack then
        return
    end

    local tool = createPlayerLightTool()
    tool.Parent = backpack
    setLanternEnabled(player, isLanternEnabled(player))
    player:SetAttribute("HasTombPlayerLight", true)

    local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid:EquipTool(tool)
    end

    local updateEvent = Remotes:GetEvent("UpdateHUD")
    if updateEvent then
        updateEvent:FireClient(player, {
            Notification = "Получен фонарь гробницы",
        })
    end
end

function TombLighting:RemovePlayerLight(player: Player)
    removeTool(player:FindFirstChild("Backpack"), PLAYER_LIGHT_NAME)
    removeTool(player.Character, PLAYER_LIGHT_NAME)
    removeCharacterLight(player)
    cleanupLegacyLanternLights(player, false)
    player:SetAttribute("HasTombPlayerLight", false)
    player:SetAttribute("TombLanternEnabled", nil)
end

function TombLighting:RestorePlayerLightIfNeeded(player: Player)
    if player:GetAttribute("HasTombPlayerLight") then
        self:GivePlayerLight(player)
    end
end

function TombLighting:IsLanternEnabled(player: Player): boolean
    return hasLantern(player)
        and isLanternEnabled(player)
        and hasActiveEquippedLanternBeam(player)
end

function TombLighting:IsPointInLanternBeam(player: Player, point: Vector3, target: Instance?): boolean
    if not self:IsLanternEnabled(player) then
        return false
    end

    local hrp = getPlayerRoot(player)
    if not hrp then
        return false
    end

    local origin = hrp.Position + Vector3.new(0, 1.2, 0)
    local toPoint = point - origin
    local distance = toPoint.Magnitude
    if distance <= 0.1 or distance > LANTERN_RANGE then
        return false
    end

    local direction = toPoint.Unit
    local halfAngle = math.rad(LANTERN_ANGLE / 2)
    if hrp.CFrame.LookVector:Dot(direction) < math.cos(halfAngle) then
        return false
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { player.Character }
    rayParams.IgnoreWater = true

    local result = Workspace:Raycast(origin, direction * distance, rayParams)
    if not result then
        return true
    end
    if target and result.Instance:IsDescendantOf(target) then
        return true
    end

    return (result.Position - point).Magnitude <= 3
end

local function findGolems(): { Model }
    local golems = {}
    local seen = {}
    local containers = {}
    local mazeContainer = findMazeContainer()
    if mazeContainer then
        table.insert(containers, mazeContainer)
    end
    table.insert(containers, Workspace)

    for _, container in ipairs(containers) do
        for _, inst in ipairs(container:GetDescendants()) do
            if inst:IsA("Model") then
                local name = string.lower(inst.Name)
                if string.find(name, "parallel", 1, true) and string.find(name, "brute", 1, true) then
                    if seen[inst] then
                        continue
                    end
                    if not inst:FindFirstChildWhichIsA("Humanoid", true) or not getModelRoot(inst) then
                        continue
                    end
                    seen[inst] = true
                    table.insert(golems, inst)
                end
            end
        end
    end

    return golems
end

local function getTriggeringPlayerForGolem(golem: Model, root: BasePart): Player?
    local closestLitPlayer = nil
    local closestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if not TombLighting:IsLanternEnabled(player) then
            continue
        end

        local playerRoot = getPlayerRoot(player)
        local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if not playerRoot or not humanoid or humanoid.Health <= 0 then
            continue
        end

        local distance = (root.Position - playerRoot.Position).Magnitude
        if distance <= GOLEM_WAKE_DISTANCE then
            return player
        end

        if distance < closestDistance then
            for _, point in ipairs(getModelProbePoints(golem, root)) do
                if TombLighting:IsPointInLanternBeam(player, point, golem) then
                    closestLitPlayer = player
                    closestDistance = distance
                    break
                end
            end
        end
    end

    return closestLitPlayer
end

local function setGolemAnchored(golem: Model, anchored: boolean)
    for _, inst in ipairs(golem:GetDescendants()) do
        if inst:IsA("BasePart") then
            inst.Anchored = anchored
        end
    end
end

local function startGolemAI(golem: Model)
    if golem:GetAttribute("TombGolemAIStarted") then
        return
    end
    golem:SetAttribute("TombGolemAIStarted", true)
    golem:SetAttribute("Awake", false)

    local humanoid = golem:FindFirstChildOfClass("Humanoid") or golem:FindFirstChildWhichIsA("Humanoid", true)
    local root = getModelRoot(golem)
    if not humanoid or not root then
        warn("[TombLighting] Parallel Brute без Humanoid/Root:", golem:GetFullName())
        return
    end

    golem.PrimaryPart = root

    local spawnCFrame = root.CFrame
    local targetPlayer: Player? = nil
    local lastAttack = 0

    setGolemAnchored(golem, true)
    humanoid.WalkSpeed = 0
    humanoid.AutoRotate = false
    humanoid:MoveTo(root.Position)

    task.spawn(function()
        while golem.Parent and humanoid.Parent and humanoid.Health > 0 do
            if not golem:GetAttribute("Awake") then
                root.AssemblyLinearVelocity = Vector3.zero
                humanoid.WalkSpeed = 0
                humanoid.AutoRotate = false
                humanoid:MoveTo(spawnCFrame.Position)

                local triggerPlayer = getTriggeringPlayerForGolem(golem, root)
                if triggerPlayer then
                    targetPlayer = triggerPlayer
                    golem:SetAttribute("Awake", true)
                    setGolemAnchored(golem, false)
                    humanoid.AutoRotate = true
                    humanoid.WalkSpeed = GOLEM_RUN_SPEED
                    print("[TombLighting] Parallel Brute проснулся:", golem:GetFullName(), "| цель:", triggerPlayer.Name)
                end

                task.wait(0.2)
                continue
            end

            local targetRoot = targetPlayer and getPlayerRoot(targetPlayer)
            local targetHumanoid = targetPlayer
                and targetPlayer.Character
                and targetPlayer.Character:FindFirstChildOfClass("Humanoid")

            if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
                targetPlayer = nil
                golem:SetAttribute("Awake", false)
                setGolemAnchored(golem, true)
                task.wait(0.5)
                continue
            end

            local distance = (root.Position - targetRoot.Position).Magnitude
            if distance <= GOLEM_ATTACK_RANGE then
                humanoid.WalkSpeed = 0
                humanoid:MoveTo(root.Position)

                local now = tick()
                if now - lastAttack >= GOLEM_ATTACK_COOLDOWN then
                    lastAttack = now
                    targetHumanoid:TakeDamage(GOLEM_DAMAGE)
                end
            else
                humanoid.WalkSpeed = GOLEM_RUN_SPEED
                humanoid:MoveTo(targetRoot.Position)
            end

            task.wait(0.25)
        end
    end)
end

function TombLighting:InitGolemWatcher()
    if golemWatcherStarted then
        return
    end
    golemWatcherStarted = true

    task.spawn(function()
        local lastKnownCount = -1
        while true do
            local golems = findGolems()
            if #golems ~= lastKnownCount then
                lastKnownCount = #golems
                print("[TombLighting] Найдено Parallel Brute:", #golems)
            end
            for _, golem in ipairs(golems) do
                startGolemAI(golem)
            end

            task.wait(2)
        end
    end)
end

function TombLighting:InitPlayerLightWatcher()
    if watcherStarted then
        return
    end
    watcherStarted = true

    task.spawn(function()
        while true do
            for _, player in ipairs(Players:GetPlayers()) do
                local character = player.Character
                local hrp = character and character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    if isInsideMaze(hrp.Position) then
                        self:GivePlayerLight(player)
                    elseif player:GetAttribute("HasTombPlayerLight") then
                        self:RemovePlayerLight(player)
                    end
                end
            end

            task.wait(0.75)
        end
    end)
end

return TombLighting
