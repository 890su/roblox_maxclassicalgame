--[[
    MapPickupSpawner — физическая карта/письмо в доме деда

    Ищет GrandfatherHouse в Workspace (в т.ч. вложенный в Studio-карту),
    ставит SecretMapPickup внутри дома или на маркер SecretMapSpawn.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StageWorldConfig = require(ServerScriptService:WaitForChild("StageWorldConfig"))

local MapPickupSpawner = {}

local mapCfg = StageWorldConfig.Stages.BAD_NEWS.MapPickup
local PICKUP_NAME = mapCfg.PickupName
local LEGACY_NAMES = mapCfg.LegacyNames
local HOUSE_NAME = mapCfg.HouseName
local SPAWN_MARKER_NAMES = mapCfg.SpawnMarkerNames
local FALLBACK_CFRAME = mapCfg.FallbackCFrame

local boundPrompts = {} -- [BasePart] = true

local function findInWorkspace(name: string)
    return Workspace:FindFirstChild(name, true)
end

local function findGrandfatherHouse()
    return findInWorkspace(HOUSE_NAME)
end

local function getPromptHost(instance: Instance): BasePart?
    if instance:IsA("BasePart") then
        return instance
    end
    if instance:IsA("Model") then
        return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function getSpawnCFrame(house: Instance?): CFrame
    for _, markerName in ipairs(SPAWN_MARKER_NAMES) do
        local marker = house and house:FindFirstChild(markerName, true) or findInWorkspace(markerName)
        if marker then
            if marker:IsA("BasePart") then
                return marker.CFrame * CFrame.new(0, marker.Size.Y / 2 + 0.15, 0)
            end
            if marker:IsA("Attachment") then
                return marker.WorldCFrame
            end
            if marker:IsA("Model") then
                return marker:GetPivot()
            end
        end
    end

    if house and house:IsA("Model") then
        local cf, size = house:GetBoundingBox()
        return CFrame.new(cf.Position.X, cf.Position.Y - size.Y / 2 + 1.5, cf.Position.Z)
    end

    return FALLBACK_CFRAME
end

local function isMisplacedRootPickup(instance: Instance, house: Instance?): boolean
    if not house then
        return false
    end
    if instance.Parent == Workspace then
        return true
    end
    return not instance:IsDescendantOf(house)
end

local function findExistingPickup(house: Instance?)
    local pickup = findInWorkspace(PICKUP_NAME)
    if pickup then
        return pickup
    end

    for _, legacyName in ipairs(LEGACY_NAMES) do
        local legacy = findInWorkspace(legacyName)
        if legacy and (legacy:IsA("BasePart") or legacy:IsA("Model")) then
            if house and isMisplacedRootPickup(legacy, house) and legacy.Parent == Workspace then
                legacy:Destroy()
            else
                return legacy
            end
        end
    end

    return nil
end

local function createPickup(spawnCf: CFrame, parent: Instance): BasePart
    local part = Instance.new("Part")
    part.Name = PICKUP_NAME
    part.Size = Vector3.new(2.5, 0.15, 1.8)
    part.CFrame = spawnCf
    part.Color = Color3.fromRGB(210, 190, 140)
    part.Material = Enum.Material.Fabric
    part.Anchored = true
    part.CanCollide = false
    part.Parent = parent

    local decal = Instance.new("Decal")
    decal.Name = "MapIcon"
    decal.Face = Enum.NormalId.Top
    decal.Color3 = Color3.fromRGB(120, 90, 50)
    decal.Transparency = 0.15
    decal.Parent = part

    return part
end

function MapPickupSpawner:BindPrompt(pickup: Instance, onTriggered: (Player) -> ())
    local host = getPromptHost(pickup)
    if not host then
        warn("[MapPickupSpawner] Нет BasePart для ProximityPrompt у", pickup:GetFullName())
        return false
    end

    local prompt = host:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        prompt = Instance.new("ProximityPrompt")
        prompt.ObjectText = "Карта деда"
        prompt.ActionText = "Прочитать"
        prompt.HoldDuration = 0.5
        prompt.MaxActivationDistance = 12
        prompt.RequiresLineOfSight = false
        prompt.Parent = host
    end

    if not boundPrompts[host] then
        boundPrompts[host] = true
        prompt.Triggered:Connect(onTriggered)
    end

    return true
end

function MapPickupSpawner:EnsurePickup(onTriggered: (Player) -> ()): Instance?
    local house = findGrandfatherHouse()
    local existing = findExistingPickup(house)

    if existing then
        if house and existing:IsA("BasePart") and existing.Parent == Workspace then
            existing.Parent = house
        end
        self:BindPrompt(existing, onTriggered)
        print("[MapPickupSpawner] Используем существующий объект:", existing:GetFullName())
        return existing
    end

    local parent = house or Workspace
    local spawnCf = getSpawnCFrame(house)
    local pickup = createPickup(spawnCf, parent)
    self:BindPrompt(pickup, onTriggered)

    print(
        "[MapPickupSpawner] Создана карта в",
        house and house:GetFullName() or "Workspace (дом не найден)",
        "| позиция:", tostring(spawnCf.Position)
    )

    return pickup
end

function MapPickupSpawner:EnsurePickupWhenReady(onTriggered: (Player) -> (), shouldSkip: (() -> boolean)?)
    task.spawn(function()
        for _ = 1, 30 do
            if shouldSkip and shouldSkip() then
                return
            end
            if findGrandfatherHouse() then
                self:EnsurePickup(onTriggered)
                return
            end
            task.wait(0.25)
        end
        if shouldSkip and shouldSkip() then
            return
        end
        self:EnsurePickup(onTriggered)
        warn("[MapPickupSpawner] GrandfatherHouse не найден — карта на фолбэк-координатах")
    end)
end

function MapPickupSpawner:RemovePickup()
    for _, name in ipairs({ PICKUP_NAME, table.unpack(LEGACY_NAMES) }) do
        local inst = findInWorkspace(name)
        if inst and (inst:IsA("BasePart") or inst:IsA("Model")) then
            inst:Destroy()
        end
    end
end

return MapPickupSpawner
