--[[
    WorldMap — границы зон и утилиты (данные из StageWorldConfig)

    Редактируйте координаты в StageWorldConfig.Locations.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local StageWorldConfig = require(ServerScriptService:WaitForChild("StageWorldConfig"))

local WorldMap = {}

WorldMap.GroundY = StageWorldConfig.World.GroundY
WorldMap.WorldBounds = StageWorldConfig.World.WorldBounds
WorldMap.Zones = StageWorldConfig.GetWorldMapZones()

local function centerXZ(minV: Vector3, maxV: Vector3): Vector3
    return Vector3.new(
        (minV.X + maxV.X) / 2,
        (minV.Y + maxV.Y) / 2,
        (minV.Z + maxV.Z) / 2
    )
end

local function sizeXZ(minV: Vector3, maxV: Vector3): Vector3
    return Vector3.new(maxV.X - minV.X, 0, maxV.Z - minV.Z)
end

function WorldMap.GetZoneRegionBox(zoneKey: string)
    local z = WorldMap.Zones[zoneKey]
    if not z then return nil end
    local c = centerXZ(z.Min, z.Max)
    local s = sizeXZ(z.Min, z.Max)
    return {
        Center = c,
        Size = Vector3.new(s.X, 40, s.Z),
        Min = z.Min,
        Max = z.Max,
    }
end

function WorldMap.GetZoneCenter(zoneKey: string): Vector3?
    local z = WorldMap.Zones[zoneKey]
    if not z then return nil end
    return centerXZ(z.Min, z.Max)
end

function WorldMap.PointInZone(zoneKey: string, position: Vector3): boolean
    return StageWorldConfig.PointInLocation(zoneKey, position)
end

function WorldMap.PointInWorldBounds(position: Vector3): boolean
    return StageWorldConfig.PointInWorldBounds(position)
end

function WorldMap.FormatZone(zoneKey: string): string
    local z = WorldMap.Zones[zoneKey]
    if not z then return "WorldMap: неизвестная зона " .. tostring(zoneKey) end
    return string.format(
        "%s | Min (%.3f, %.3f, %.3f) Max (%.3f, %.3f, %.3f)",
        z.Label,
        z.Min.X, z.Min.Y, z.Min.Z,
        z.Max.X, z.Max.Y, z.Max.Z
    )
end

return WorldMap
