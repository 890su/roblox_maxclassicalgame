--[[
    StageWorldConfig — ЕДИНЫЙ конфиг мира по этапам игры
    ═══════════════════════════════════════════════════════════

    ⚠️ ТОЛЬКО СЕРВЕР (ServerScriptService) — клиент не видит этот модуль.

    Редактируйте ЭТОТ файл, чтобы менять:
    • порядок и названия этапов (стадий);
    • границы зон (Min/Max из Studio), точки спавна игрока;
    • координаты NPC, волков, мини-босса;
    • имена триггеров, телепортов, объектов болота/гробницы;
    • параметры врагов и головоломок на каждом этапе.

    Остальные модули (GameConfig, WorldMap, WolfConfig, SwampConfig)
    читают данные отсюда — для совместимости со старым кодом.

    Как пользоваться (только на сервере):
      local SW = require(ServerScriptService.StageWorldConfig)
      SW.StageOrder                    — список стадий
      SW.Stages.WOLF_HUNT              — всё про охоту на волков
      SW.GetLocation("Village")        — границы и спавн локации
      SW.GetLegacyGameConfigZones()    — таблица GameConfig.Zones
]]

local StageWorldConfig = {}

-- ═══════════════════════════════════════════════════════════
-- ОБЩИЕ НАСТРОЙКИ ИГРЫ
-- ═══════════════════════════════════════════════════════════
StageWorldConfig.Settings = {
    MaxPlayers = 1,
    AutosaveInterval = 60,
    WolvesToKill = 8,
    SecretCode = "SHADOW",
}

StageWorldConfig.World = {
    GroundY = -206.234,
    WorldBounds = {
        Min = Vector3.new(-2249, -236.645, -1319),
        Max = Vector3.new(67, -206.234, 353),
        Description = "AABB всего мира (Studio)",
    },
}

-- ═══════════════════════════════════════════════════════════
-- ПОРЯДОК ЭТАПОВ (единственный источник для GameConfig.GameStages)
-- ═══════════════════════════════════════════════════════════
StageWorldConfig.StageOrder = {
    "SPAWN",
    "WOLF_HUNT",
    "JOHN_RESCUE",
    "BAD_NEWS",
    "SECRET_MAP",
    "FOREST_JOURNEY",
    "SWAMP_JOURNEY",
    "MINI_BOSS",
    "TOMB_MAZE",
    "BAN_HAMMER",
    "FINALE",
    "CREDITS",
}

-- ═══════════════════════════════════════════════════════════
-- ЛОКАЦИИ НА КАРТЕ (физические зоны Studio)
-- Bounds.Min / Bounds.Max — два противоположных угла (X, Y, Z).
-- Spawn — типичная точка появления / телепорта игрока в зоне.
-- LegacyZoneKey — имя в старом GameConfig.Zones (если отличается).
-- ═══════════════════════════════════════════════════════════
StageWorldConfig.Locations = {
    Village = {
        Label = "Деревня",
        LegacyZoneKey = "Village",
        Bounds = {
            Min = Vector3.new(-842, -206.234, -75),
            Max = Vector3.new(-436, -206.234, 110),
        },
        Spawn = Vector3.new(-544, -206, -28),
        Description = "Стартовая деревня",
    },

    WolfForest = {
        Label = "Окрестности — лес волков",
        LegacyZoneKey = "Outskirts",
        Bounds = {
            Min = Vector3.new(-949, -206.234, 110),
            Max = Vector3.new(-486, -206.234, 335),
        },
        Spawn = Vector3.new(-894.341, -162.597, 176.422),
        Description = "Территория волков",
    },

    Forest = {
        Label = "Тёмный лес",
        LegacyZoneKey = "Forest",
        Bounds = nil, -- задайте Min/Max в Studio, когда разметите лес
        Spawn = Vector3.new(700, 5, 200),
        Size = Vector3.new(400, 80, 400),
        Description = "Путь к болоту с JOHN DOU",
    },

    Swamp = {
        Label = "Ядовитое болото",
        LegacyZoneKey = "Swamp",
        WorkspaceFolder = "Zones/Swamp",
        Bounds = {
            Min = Vector3.new(-606.912, -182.043, -570.965),
            Max = Vector3.new(-307.135, -163.013, -112.298),
        },
        Spawn = Vector3.new(-307.135, -163.013, -570.965), -- вход у первой кочки / ворот
        Description = "Болото после леса",
    },

    HydraArena = {
        Label = "Арена King Hydra Blaster",
        LegacyZoneKey = "MiniBossArena",
        Bounds = {
            Min = Vector3.new(-1363, -206.234, -103),
            Max = Vector3.new(-984, -206.234, 167),
        },
        Spawn = Vector3.new(-1361.386, -118.999, -144.242),
        Size = Vector3.new(120, 40, 120),
        Description = "Руины гидры, ветряк",
    },

    TombLabyrinth = {
        Label = "Лабиринт гробницы",
        LegacyZoneKey = "Tomb",
        Bounds = {
            Min = Vector3.new(-2249, -236.645, -214.316),
            Max = Vector3.new(-1744, -236.645, 283.684),
        },
        Spawn = Vector3.new(1075, -10, 200),
        Size = Vector3.new(250, 60, 250),
        Description = "Mazegame.MAZE, телепорты A↔C, D↔A",
        Teleporters = {
            EntrySender = "TeleporterA",
            EntryDestination = "TeleporterC",
            ExitSender = "TeleporterD",
            ExitDestination = "TeleporterA",
        },
        MazeFolder = "Mazegame.MAZE",
    },

    ArtifactHall = {
        Label = "Зал артефакта",
        LegacyZoneKey = "ArtifactHall",
        Bounds = nil,
        Spawn = Vector3.new(1300, -20, 200),
        Size = Vector3.new(100, 40, 100),
        Description = "Ban Hammer, финал",
        BanHammerPedestal = "BanHammerPedestal",
        BanHammerTrigger = "BanHammer_Trigger",
    },
}

-- ═══════════════════════════════════════════════════════════
-- NPC (позиции и параметры; этап первого появления)
-- ═══════════════════════════════════════════════════════════
StageWorldConfig.NPCs = {
    Elder = {
        Stage = "SPAWN",
        Location = "Village",
        Name = "Старейшина",
        Position = Vector3.new(-544, -203, -28),
        BodyColor = Color3.fromRGB(180, 140, 100),
        Size = Vector3.new(2, 4.5, 1.5),
        Behavior = "STATIONARY",
        InitialDialogue = "ELDER_QUEST_START",
    },
    DouDzouh = {
        Stage = "JOHN_RESCUE",
        Location = "Village",
        Name = "JOHN DOU",
        Position = Vector3.new(-560, -203, -50),
        BodyColor = Color3.fromRGB(50, 50, 60),
        Size = Vector3.new(2, 5, 1.5),
        Behavior = "FOLLOWER",
        InitialDialogue = "DOU_DZOUH_INTRO",
        FollowDistance = 7,
        MinFollowDistance = 4,
        MaxFollowDistance = 18,
        InspectRadius = 16,
        InspectChance = 0.25,
        ModelName = nil,
    },
    Trader = {
        Stage = "SPAWN",
        Location = "Village",
        Name = "Торговец",
        Position = Vector3.new(-530, -203, -15),
        BodyColor = Color3.fromRGB(120, 80, 40),
        Size = Vector3.new(2, 4.5, 1.5),
        Behavior = "STATIONARY",
        InitialDialogue = nil,
    },
}

-- ═══════════════════════════════════════════════════════════
-- ЭТАПЫ — всё, что относится к конкретной стадии сюжета
-- ═══════════════════════════════════════════════════════════
StageWorldConfig.Stages = {

    SPAWN = {
        Label = "Появление в деревне",
        Location = "Village",
        QuestId = nil,
        Triggers = {},
        Notes = "Диалог со Старейшиной → меч → WOLF_HUNT",
    },

    WOLF_HUNT = {
        Label = "Охота на волков",
        Location = "WolfForest",
        QuestId = "KILL_WOLVES",
        Triggers = {},
        Wolves = {
            Count = 8,
            TemplateName = "WolfTemplate",
            -- "Absolute" — координаты мира; "Relative" — смещение от Locations[WolfForest].Spawn
            SpawnMode = "Absolute",
            SpawnPoints = {
                Vector3.new(-914.341, -162.597, 156.422),
                Vector3.new(-874.341, -162.597, 196.422),
                Vector3.new(-924.341, -162.597, 206.422),
                Vector3.new(-864.341, -162.597, 146.422),
                Vector3.new(-884.341, -162.597, 216.422),
                Vector3.new(-919.341, -162.597, 166.422),
                Vector3.new(-859.341, -162.597, 191.422),
                Vector3.new(-904.341, -162.597, 136.422),
            },
            RelativeSpawnPoints = {
                Vector3.new(-20, 0, -20),
                Vector3.new(20, 0, 20),
                Vector3.new(-30, 0, 30),
                Vector3.new(30, 0, -30),
                Vector3.new(10, 0, 40),
                Vector3.new(-25, 0, -10),
                Vector3.new(35, 0, 15),
                Vector3.new(-10, 0, -40),
            },
            Stats = {
                Health = 100,
                Damage = 8.4,
                AttackRange = 5,
                AttackCooldown = 1.5,
                DetectionRange = 30,
                WalkSpeed = 10.24,
                RunSpeed = 15.36,
            },
            LootTable = {
                { ItemId = "WolfPelt", Name = "Шкура волка", DropChance = 0.8, SellPrice = 10 },
                { ItemId = "WolfTeeth", Name = "Зубы волка", DropChance = 0.5, SellPrice = 5 },
                { ItemId = "WolfClaw", Name = "Коготь волка", DropChance = 0.2, SellPrice = 25 },
            },
            Model = {
                BodyColor = Color3.fromRGB(80, 80, 80),
                BodySize = Vector3.new(2, 2.5, 4),
                HeadSize = Vector3.new(1.5, 1.5, 2),
                EyeColor = Color3.fromRGB(255, 50, 50),
            },
            VoidKillY = -500,
        },
    },

    JOHN_RESCUE = {
        Label = "Возвращение — спасение JOHN DOU",
        Location = "Village",
        QuestId = "RETURN_TO_VILLAGE",
        Triggers = {
            ReturnToVillage = "ReturnToVillage",
        },
        Cutscene = "WOLF_AMBUSH",
        Notes = "Квест RETURN_TO_VILLAGE обходится через стадию; триггер ReturnToVillage — опционально",
    },

    BAD_NEWS = {
        Label = "Смерть деда",
        Location = "Village",
        QuestId = "FIND_MAP",
        Cutscene = "BAD_NEWS",
        MapPickup = {
            HouseName = "GrandfatherHouse",
            PickupName = "SecretMapPickup",
            LegacyNames = { "SecretLetter", "SecretMap" },
            SpawnMarkerNames = { "SecretMapSpawn", "MapSpawn", "SecretLetterSpawn" },
            FallbackCFrame = CFrame.new(-785.18, -201.774, -38.81),
        },
        Triggers = {
            HouseEnter = "GrandfatherHouse_Enter",
        },
    },

    SECRET_MAP = {
        Label = "Карта деда",
        Location = "Village",
        QuestId = "FIND_MAP",
        Notes = "Стадия в коде пока не выставляется — переход сразу в FOREST_JOURNEY после подбора карты",
    },

    FOREST_JOURNEY = {
        Label = "Через лес",
        Location = "Forest",
        QuestId = "TRAVERSE_FOREST",
        CompanionNpc = "DouDzouh",
        Triggers = {
            Entrance = "ForestEntrance_Trigger",
        },
        QuestZones = { "Forest", "Swamp" },
    },

    SWAMP_JOURNEY = {
        Label = "Ядовитое болото",
        Location = "Swamp",
        QuestId = "CROSS_SWAMP",
        CompanionNpc = "DouDzouh",
        Triggers = {
            Entrance = "SwampEntrance_Trigger",
            Exit = "SwampExit_Trigger",
        },
        QuestZones = { "HydraRuins" },
        Swamp = {
            ZonesFolder = "Zones",
            SwampFolder = "Swamp",
            StepPrefix = "SwampKochka_",
            GenerateFallbackSteps = false,
            FallbackStepCount = 0,
            GenerateFogVisual = false,
            RoutePoints = {},
            FogPartNames = { "PoisonFog", "PoisonCloudTrap", "SwampFog" },
            FallPartNames = { "SwampFall", "SwampVoid" },
            GuideNpcId = "DouDzouh",
            GuideWaitRadius = 8,
            GuideSafeRadius = 12,
            ProtectNearGuide = false,
            StepSafeRadius = 7,
            FogDamagePerTick = 8,
            FogDamageInterval = 1,
            FogCheckInterval = 0.35,
            MoveTimeout = 25,
            FogVisual = nil, -- туман размещаем вручную в Studio, если нужен визуальный слой
            --[[
            FogVisual = {
                Name = "PoisonFog",
                Height = 28,
                Transparency = 0.72,
                Color = Color3.fromRGB(120, 170, 120),
            },
            ]]
        },
        DebugTeleportFallback = "Forest",
    },

    MINI_BOSS = {
        Label = "King Hydra Blaster",
        Location = "HydraArena",
        QuestId = "DEFEAT_MINI_BOSS",
        CompanionNpc = "DouDzouh",
        MiniBoss = {
            ModelName = "KingHydraBlaster",
            MaxHealth = 300,
            Damage = 25,
            DetectionRange = 60,
            AttackRange = 8,
            WalkSpeed = 8,
            RunSpeed = 14,
            AttackCooldown = 1.5,
            PatrolRadius = 20,
            LoopBossAnimation = true,
            LoopAnimationAssetId = "rbxassetid://114359835269910",
            LoopAnimationName = "seeanim",
            LoopAnimationPriority = "Action",
            LoopAnimationWeight = 1,
            LoopAnimationAnimatorTarget = "Auto",
            FireActivationDelay = 2.5,
            FireDamagePerTick = 12,
            FireDamageInterval = 0.45,
            FireDamageRadius = 16,
            DebugAILogInterval = 2,
            DebugMiniBossVerbose = true,
            Rewards = { Money = 100, Items = { "HydraScale" } },
        },
        WindTurbine = {
            WorkspacePath = "Zones/Tomb/WindTurbine",
            FallDuration = 1.8,
            FallAngleDeg = 88,
            KillRadius = 22,
            PushHoldDuration = 0.6,
            PushMaxDistance = 10,
            PushPartSize = Vector3.new(5, 2.5, 5),
            ClearCloudsOnPush = true,
        },
    },

    TOMB_MAZE = {
        Label = "Лабиринт гробницы",
        Location = "TombLabyrinth",
        QuestId = "SOLVE_MAZE",
        CompanionNpc = "DouDzouh",
        Triggers = {
            TombEntrance = "TombEntrance_Trigger",
            BanHammer = "BanHammer_Trigger",
        },
        QuestReachZone = "ArtifactHall",
        TeleporterCooldown = 2.5,
        DebugTeleportDestination = "TeleporterC",
    },

    BAN_HAMMER = {
        Label = "Ban Hammer",
        Location = "ArtifactHall",
        QuestId = "GET_BAN_HAMMER",
        Cutscene = "DOU_DZOUH_REQUEST",
        TeleportAfterCutscene = "TeleporterA",
        DebugMazeExitOffset = Vector3.new(26.417, 5.189, -26.368),
    },

    FINALE = {
        Label = "Финал",
        Location = "ArtifactHall",
        QuestId = "FINALE",
        Cutscenes = { "CUTSCENE_BETRAYAL", "CUTSCENE_BOSS_FIGHT", "CUTSCENE_ESCAPE" },
    },

    CREDITS = {
        Label = "Титры",
        Location = nil,
        QuestId = nil,
    },
}

-- ═══════════════════════════════════════════════════════════
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ═══════════════════════════════════════════════════════════

local function centerFromBounds(minV: Vector3, maxV: Vector3): Vector3
    return Vector3.new(
        (minV.X + maxV.X) / 2,
        (minV.Y + maxV.Y) / 2,
        (minV.Z + maxV.Z) / 2
    )
end

local function sizeFromBounds(minV: Vector3, maxV: Vector3, height: number?): Vector3
    height = height or math.max(40, maxV.Y - minV.Y)
    return Vector3.new(maxV.X - minV.X, height, maxV.Z - minV.Z)
end

function StageWorldConfig.GetLocation(locationKey: string)
    return StageWorldConfig.Locations[locationKey]
end

function StageWorldConfig.GetStage(stageId: string)
    return StageWorldConfig.Stages[stageId]
end

function StageWorldConfig.GetStageIndex(stageId: string): number?
    for i, id in ipairs(StageWorldConfig.StageOrder) do
        if id == stageId then
            return i
        end
    end
    return nil
end

function StageWorldConfig.GetNPC(npcId: string)
    return StageWorldConfig.NPCs[npcId]
end

--- Точка внутри локации по XZ (границы Min/Max)
function StageWorldConfig.PointInLocation(locationKey: string, position: Vector3): boolean
    local loc = StageWorldConfig.Locations[locationKey]
    if not loc or not loc.Bounds then
        return false
    end
    local b = loc.Bounds
    return position.X >= b.Min.X and position.X <= b.Max.X
        and position.Z >= b.Min.Z and position.Z <= b.Max.Z
end

function StageWorldConfig.PointInWorldBounds(position: Vector3): boolean
    local w = StageWorldConfig.World.WorldBounds
    return position.X >= w.Min.X and position.X <= w.Max.X
        and position.Z >= w.Min.Z and position.Z <= w.Max.Z
end

function StageWorldConfig.GetLocationCenter(locationKey: string): Vector3?
    local loc = StageWorldConfig.Locations[locationKey]
    if not loc then
        return nil
    end
    if loc.Bounds then
        return centerFromBounds(loc.Bounds.Min, loc.Bounds.Max)
    end
    return loc.Spawn
end

--- Совместимость с GameConfig.Zones (ключи Village, Outskirts, Forest, …)
function StageWorldConfig.GetLegacyGameConfigZones()
    local zones = {}
    for _, loc in pairs(StageWorldConfig.Locations) do
        local key = loc.LegacyZoneKey
        if key then
            local size = loc.Size
            if not size and loc.Bounds then
                size = sizeFromBounds(loc.Bounds.Min, loc.Bounds.Max)
            end
            local spawn = loc.Spawn
            if not spawn and loc.Bounds then
                spawn = centerFromBounds(loc.Bounds.Min, loc.Bounds.Max)
            end
            zones[key] = {
                Name = loc.Label,
                SpawnPoint = spawn or Vector3.zero,
                Size = size or Vector3.new(200, 50, 200),
                Description = loc.Description or loc.Label,
            }
        end
    end
    return zones
end

--- Совместимость с WorldMap.Zones
function StageWorldConfig.GetWorldMapZones()
    local map = {}
    for key, loc in pairs(StageWorldConfig.Locations) do
        if loc.Bounds then
            map[key] = {
                Id = key,
                Label = loc.Label,
                Min = loc.Bounds.Min,
                Max = loc.Bounds.Max,
                TeleporterSender = loc.Teleporters and loc.Teleporters.EntrySender or nil,
                TeleporterDestination = loc.Teleporters and loc.Teleporters.EntryDestination or nil,
                TeleporterExitSender = loc.Teleporters and loc.Teleporters.ExitSender or nil,
                TeleporterExitDestination = loc.Teleporters and loc.Teleporters.ExitDestination or nil,
            }
        end
    end
    return map
end

--- Волки: список мировых позиций спавна
function StageWorldConfig.GetWolfSpawnPoints(): { Vector3 }
    local stage = StageWorldConfig.Stages.WOLF_HUNT
    local wolves = stage and stage.Wolves
    if not wolves then
        return {}
    end
    if wolves.SpawnMode == "Relative" then
        local loc = StageWorldConfig.Locations.WolfForest
        local base = loc and loc.Spawn or Vector3.zero
        local out = {}
        for _, offset in ipairs(wolves.RelativeSpawnPoints or {}) do
            table.insert(out, base + offset)
        end
        return out
    end
    return wolves.SpawnPoints or {}
end

function StageWorldConfig.GetWolfConfig()
    local w = StageWorldConfig.Stages.WOLF_HUNT.Wolves
    return {
        Stats = w.Stats,
        LootTable = w.LootTable,
        Model = w.Model,
        SpawnZone = "Outskirts",
        SpawnPoints = w.RelativeSpawnPoints,
        SpawnMode = w.SpawnMode,
        AbsoluteSpawnPoints = w.SpawnPoints,
        Count = w.Count,
        TemplateName = w.TemplateName,
        VoidKillY = w.VoidKillY,
    }
end

function StageWorldConfig.GetSwampConfig()
    local s = StageWorldConfig.Stages.SWAMP_JOURNEY.Swamp
    local loc = StageWorldConfig.Locations.Swamp
    return {
        ZonesFolder = s.ZonesFolder,
        SwampFolder = s.SwampFolder,
        Bounds = loc and loc.Bounds or nil,
        StepPrefix = s.StepPrefix,
        GenerateFallbackSteps = s.GenerateFallbackSteps,
        FallbackStepCount = s.FallbackStepCount,
        GenerateFogVisual = s.GenerateFogVisual,
        RoutePoints = s.RoutePoints,
        FogPartNames = s.FogPartNames,
        FallPartNames = s.FallPartNames,
        GuideNpcId = s.GuideNpcId,
        GuideWaitRadius = s.GuideWaitRadius,
        GuideSafeRadius = s.GuideSafeRadius,
        ProtectNearGuide = s.ProtectNearGuide,
        StepSafeRadius = s.StepSafeRadius,
        FogDamagePerTick = s.FogDamagePerTick,
        FogDamageInterval = s.FogDamageInterval,
        FogCheckInterval = s.FogCheckInterval,
        MoveTimeout = s.MoveTimeout,
        FogVisual = s.FogVisual,
        Triggers = StageWorldConfig.Stages.SWAMP_JOURNEY.Triggers,
    }
end

return StageWorldConfig
