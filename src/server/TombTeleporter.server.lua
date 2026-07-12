--[[
    TombTeleporter — телепорты гробницы по касанию Part (вход и выход).

    В Studio имена по умолчанию из WorldMap.Zones.TombLabyrinth:
      • TeleporterA → TeleporterC — вход из руин в лабиринт
      • TeleporterD → TeleporterA — выход из лабиринта обратно в руины (MazeGame и т.п.)

    Скрипт лежит в ServerScriptService, на части не вешается.
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local WorldMap = require(ServerScriptService:WaitForChild("WorldMap"))
local TombLighting = require(ServerScriptService:WaitForChild("TombLighting"))

local zone = WorldMap.Zones.TombLabyrinth

local COOLDOWN = 2.5
local ARRIVAL_OFFSET = Vector3.new(0, 3, 0)

local lastTeleport = {}

-- После выхода D→A не тянуть сразу обратно в лабиринт с той же площадки TeleporterA
local lastMazeExitAt = {} -- [userId] = tick()

local hookedEntry = false
local hookedExit = false

TombLighting:InitAtmosphericLights()

local function findNamed(instName: string): Instance?
    if not instName or instName == "" then
        return nil
    end
    return Workspace:FindFirstChild(instName, true)
end

local function getTouchPart(inst: Instance): BasePart?
    if inst:IsA("BasePart") then
        return inst
    end
    if inst:IsA("Model") then
        if inst.PrimaryPart then
            return inst.PrimaryPart
        end
        return inst:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function getDestinationCFrame(inst: Instance): CFrame?
    if inst:IsA("BasePart") then
        return inst.CFrame
    end
    if inst:IsA("Model") then
        return inst:GetPivot()
    end
    return nil
end

local function hookPair(senderName: string, destName: string): boolean
    local senderInst = findNamed(senderName)
    local destInst = findNamed(destName)

    if not senderInst or not destInst then
        return false
    end

    local touchPart = getTouchPart(senderInst)
    if not touchPart then
        warn("[TombTeleporter] У «" .. senderName .. "» нет BasePart для Touched")
        return false
    end

    local destCf = getDestinationCFrame(destInst)
    if not destCf then
        warn("[TombTeleporter] Не удалось получить CFrame у «" .. destName .. "»")
        return false
    end

    if touchPart:GetAttribute("TombTeleporterHooked") then
        return true
    end
    touchPart:SetAttribute("TombTeleporterHooked", true)

    touchPart.Touched:Connect(function(hit)
        local character = hit.Parent
        if not character then
            return
        end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then
            return
        end
        local hum = character:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then
            return
        end
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then
            return
        end

        local uid = player.UserId
        local now = tick()

        -- Вход A→C: игрок только что вышел из лабиринта на A — не телепортировать обратно в C несколько секунд
        if senderName == zone.TeleporterSender and destName == zone.TeleporterDestination then
            local le = lastMazeExitAt[uid]
            if le and (now - le) < 6 then
                return
            end
        end

        local key = uid .. "_" .. senderName
        if lastTeleport[key] and (now - lastTeleport[key]) < COOLDOWN then
            return
        end
        lastTeleport[key] = now

        local target = destCf * CFrame.new(ARRIVAL_OFFSET)
        hrp.CFrame = target
        print("[TombTeleporter]", player.Name, senderName, "→", destName)

        if senderName == zone.TeleporterSender and destName == zone.TeleporterDestination then
            TombLighting:GivePlayerLight(player)
        end

        if
            zone.TeleporterExitSender
            and zone.TeleporterExitDestination
            and senderName == zone.TeleporterExitSender
            and destName == zone.TeleporterExitDestination
        then
            lastMazeExitAt[uid] = tick()
            TombLighting:RemovePlayerLight(player)
        end
    end)

    print("[TombTeleporter] Готово:", senderName, "→", destName)
    return true
end

task.spawn(function()
    local exitSender = zone.TeleporterExitSender
    local exitDest = zone.TeleporterExitDestination
    local exitConfigured = exitSender
        and exitDest
        and exitSender ~= ""
        and exitDest ~= ""

    local tries = 0
    while tries < 240 do
        if not hookedEntry and findNamed(zone.TeleporterSender) and findNamed(zone.TeleporterDestination) then
            hookedEntry = hookPair(zone.TeleporterSender, zone.TeleporterDestination)
        end

        if exitConfigured and not hookedExit and findNamed(exitSender) and findNamed(exitDest) then
            hookedExit = hookPair(exitSender, exitDest)
        end

        if hookedEntry and (not exitConfigured or hookedExit) then
            break
        end

        tries += 1
        task.wait(0.5)
    end

    if not hookedEntry then
        warn(
            "[TombTeleporter] Не найдены объекты входа «"
                .. tostring(zone.TeleporterSender)
                .. "» / «"
                .. tostring(zone.TeleporterDestination)
                .. "» — телепорт входа не подключён"
        )
    end

    if exitConfigured and not hookedExit then
        warn(
            "[TombTeleporter] Выход лабиринта не подключён (ожидались «"
                .. exitSender
                .. "» → «"
                .. exitDest
                .. "»). Имена должны быть уникальны в Workspace (поиск рекурсивный)."
        )
    end
end)
