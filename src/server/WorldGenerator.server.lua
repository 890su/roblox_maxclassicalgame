--[[
    WorldGenerator — Процедурная генерация игрового мира
    ═══════════════════════════════════════════════════════════
    
    ИНСТРУКЦИЯ: Запустите этот скрипт ОДИН РАЗ в Roblox Studio
    для генерации всех зон. После генерации отключите/удалите скрипт.
    
    ЗОНЫ МИРА (расположены линейно по X, БЕЗ наложений):
    ─────────────────────────────────────────────────────
    1. Деревня   (Village)       — X: -100..100   (наземная)
    2. Окрестности (Outskirts)   — X:  150..450   (наземная)
    3. Лес        (Forest)       — X:  500..900   (наземная, туман)
    4. Гробница   (Tomb)         — X:  950..1200  (подземная, Y=-10)
    5. Зал артефакта (ArtifactHall) — X: 1250..1350 (глубокая, Y=-20)
    
    СТРУКТУРА WORKSPACE ПОСЛЕ ГЕНЕРАЦИИ:
    ─────────────────────────────────────
    Workspace
    ├── Zones (Folder)
    │   ├── Village (Folder)        — дома, колодец, деревья, заборы
    │   ├── Outskirts (Folder)      — скалы, кусты, деревья
    │   ├── Forest (Folder)         — плотный лес, тропинка, ловушки, туман
    │   ├── Tomb (Folder)           — лабиринт, факелы, крыша
    │   └── ArtifactHall (Folder)   — восьмиугольный зал, пьедестал, BanHammer
    ├── SpawnPoints (Folder)
    │   └── VillageSpawn (SpawnLocation)
    └── Triggers (Folder)
        ├── VillageExit_North
        ├── ReturnToVillage
        ├── TombEntrance_Trigger
        └── BanHammer_Trigger
    
    АЛГОРИТМ ЛАБИРИНТА:
    ────────────────────
    Recursive Backtracker (DFS) — классический алгоритм генерации
    идеального лабиринта (без циклов, единственный путь):
    1. Начинаем с ячейки [1][1], помечаем как visited
    2. Выбираем случайного непосещённого соседа
    3. Убираем стену между текущей и соседней ячейками
    4. Рекурсивно продолжаем из соседней
    5. Если нет непосещённых — backtrack (возвращаемся назад по стеку)
    6. Результат: лабиринт 10×10 с уникальным путём
    
    УТИЛИТЫ:
    ────────
    • createPart()   — универсальная фабрика Part-ов
    • createFolder()  — idempotent создание Folder
    • createTorch()   — факел на стене (палка + пламя Neon + PointLight)
    • createGround()  — земля для зоны
    • createTree()    — дерево (ствол + крона) с рандомным масштабом
    • createHouse()   — дом (пол + 4 стены + крыша + дверь)
    • createFence()   — забор между двумя точками
    • createTrigger() — невидимый триггер (Transparency=1, CanCollide=false)
    • createSpawn()   — SpawnLocation (точка спавна)
]]

local Workspace = game:GetService("Workspace")

local WorldGenerator = {}

-- ═══════════════════════════════════════════════════════════
-- УТИЛИТА: Создать Part
-- Универсальная фабрика: принимает таблицу props и создаёт Part.
-- Все Part-ы Anchored = true (статичные объекты мира).
-- ═══════════════════════════════════════════════════════════
local function createPart(props)
    local part = Instance.new("Part")
    part.Name = props.Name or "Part"
    part.Size = props.Size or Vector3.new(4, 4, 4)
    part.Position = props.Position or Vector3.new(0, 0, 0)
    part.Color = props.Color or Color3.fromRGB(128, 128, 128)
    part.Material = props.Material or Enum.Material.SmoothPlastic
    part.Anchored = true                          -- статичный мир
    part.CanCollide = props.CanCollide ~= false   -- по умолчанию true
    part.Transparency = props.Transparency or 0
    if props.Orientation then
        part.Orientation = props.Orientation
    end
    part.Parent = props.Parent or Workspace
    return part
end

-- ═══════════════════════════════════════════════════════════
-- УТИЛИТА: Создать или найти Folder (idempotent)
-- Если Folder с таким именем уже есть — не создаёт дубликат.
-- ═══════════════════════════════════════════════════════════
local function createFolder(name, parent)
    local folder = parent:FindFirstChild(name)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = name
        folder.Parent = parent
    end
    return folder
end

-- ═══════════════════════════════════════════════════════════
-- УТИЛИТА: Факел на стене
-- Состоит из трёх частей:
-- 1. Палка (Wood) — ручка факела
-- 2. Пламя (Neon) — светящаяся часть, видна издалека
-- 3. PointLight — освещает окружение (Range=24)
-- ═══════════════════════════════════════════════════════════
local function createTorch(position, parent)
    -- Палка (ручка факела)
    local torch = createPart({
        Name = "Torch",
        Size = Vector3.new(0.4, 2, 0.4),
        Position = position,
        Color = Color3.fromRGB(101, 67, 33),           -- коричневый
        Material = Enum.Material.Wood,
        Parent = parent,
    })

    -- Пламя (Neon — светится в темноте!)
    createPart({
        Name = "Flame",
        Size = Vector3.new(0.6, 0.8, 0.6),
        Position = position + Vector3.new(0, 1.3, 0),  -- над палкой
        Color = Color3.fromRGB(255, 130, 30),           -- оранжевый
        Material = Enum.Material.Neon,
        CanCollide = false,
        Parent = parent,
    })

    -- Источник света (тёплый)
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 150, 50)
    light.Brightness = 1.5
    light.Range = 24
    light.Parent = torch

    return torch
end

-- ═══════════════════════════════════════════════════════════
-- УТИЛИТА: Приглушённый потолочный свет гробницы
-- Невидимый носитель с тёплым PointLight создаёт мягкую пятнистую подсветку.
-- ═══════════════════════════════════════════════════════════
-- ═══════════════════════════════════════════════════════════
-- УТИЛИТА: Земля (пол) для зоны
-- Плоская Part (высота 2), материал по умолчанию Grass.
-- center — центр зоны, sizeXZ — размер по X и Z (Vector2).
-- ═══════════════════════════════════════════════════════════
local function createGround(name, center, sizeXZ, color, material, parent)
    return createPart({
        Name = name .. "_Ground",
        Size = Vector3.new(sizeXZ.X, 2, sizeXZ.Y),
        Position = Vector3.new(center.X, center.Y - 1, center.Z),
        Color = color or Color3.fromRGB(80, 120, 50),
        Material = material or Enum.Material.Grass,
        Parent = parent,
    })
end

-- ═══════════════════════════════════════════════════════════
-- УТИЛИТА: Дерево (ствол + крона)
-- scaleVariation — множитель размера (0.8..1.4 по умолчанию).
-- PrimaryPart = ствол (для перемещения всей модели).
-- ═══════════════════════════════════════════════════════════
local function createTree(position, parent, scaleVariation)
    local scale = scaleVariation or (0.8 + math.random() * 0.6)
    local tree = Instance.new("Model")
    tree.Name = "Tree"

    -- Ствол (коричневый, Wood)
    local trunk = createPart({
        Name = "Trunk",
        Size = Vector3.new(2 * scale, 10 * scale, 2 * scale),
        Position = position + Vector3.new(0, 5 * scale, 0),
        Color = Color3.fromRGB(101, 67, 33),
        Material = Enum.Material.Wood,
        Parent = tree,
    })

    -- Крона (зелёная, Grass)
    createPart({
        Name = "Foliage",
        Size = Vector3.new(8 * scale, 8 * scale, 8 * scale),
        Position = position + Vector3.new(0, 10 * scale + 2 * scale, 0),
        Color = Color3.fromRGB(34, 100, 34),
        Material = Enum.Material.Grass,
        Parent = tree,
    })

    tree.PrimaryPart = trunk
    tree.Parent = parent
    return tree
end

-- ═══════════════════════════════════════════════════════════
-- УТИЛИТА: Дом
-- Состоит из: пол, 4 стены (передняя с дверным проёмом), крыша.
-- Передняя стена разделена на 3 части: левая, правая, перемычка.
-- Дверь: пустое пространство шириной 4 studs.
-- ═══════════════════════════════════════════════════════════
local function createHouse(name, position, size, parent)
    local house = Instance.new("Model")
    house.Name = name

    local wallHeight = size.Y or 8
    local wallThickness = 1

    -- Пол (деревянный)
    createPart({
        Name = "Floor",
        Size = Vector3.new(size.X, 1, size.Z),
        Position = position + Vector3.new(0, 0.5, 0),
        Color = Color3.fromRGB(139, 90, 43),
        Material = Enum.Material.Wood,
        Parent = house,
    })

    -- Задняя стена (цельная)
    createPart({
        Name = "WallBack",
        Size = Vector3.new(size.X, wallHeight, wallThickness),
        Position = position + Vector3.new(0, wallHeight / 2 + 1, -size.Z / 2),
        Color = Color3.fromRGB(180, 150, 100),
        Material = Enum.Material.Wood,
        Parent = house,
    })

    -- Передняя стена (с дверным проёмом шириной 4)
    local doorWidth = 4
    local sideWidth = (size.X - doorWidth) / 2

    -- Левая часть передней стены
    createPart({
        Name = "WallFrontLeft",
        Size = Vector3.new(sideWidth, wallHeight, wallThickness),
        Position = position + Vector3.new(-doorWidth / 2 - sideWidth / 2, wallHeight / 2 + 1, size.Z / 2),
        Color = Color3.fromRGB(180, 150, 100),
        Material = Enum.Material.Wood,
        Parent = house,
    })

    -- Правая часть передней стены
    createPart({
        Name = "WallFrontRight",
        Size = Vector3.new(sideWidth, wallHeight, wallThickness),
        Position = position + Vector3.new(doorWidth / 2 + sideWidth / 2, wallHeight / 2 + 1, size.Z / 2),
        Color = Color3.fromRGB(180, 150, 100),
        Material = Enum.Material.Wood,
        Parent = house,
    })

    -- Перемычка над дверью
    createPart({
        Name = "WallFrontTop",
        Size = Vector3.new(doorWidth, wallHeight - 6, wallThickness),
        Position = position + Vector3.new(0, wallHeight - (wallHeight - 6) / 2 + 1, size.Z / 2),
        Color = Color3.fromRGB(180, 150, 100),
        Material = Enum.Material.Wood,
        Parent = house,
    })

    -- Боковые стены
    createPart({
        Name = "WallLeft",
        Size = Vector3.new(wallThickness, wallHeight, size.Z),
        Position = position + Vector3.new(-size.X / 2, wallHeight / 2 + 1, 0),
        Color = Color3.fromRGB(180, 150, 100),
        Material = Enum.Material.Wood,
        Parent = house,
    })
    createPart({
        Name = "WallRight",
        Size = Vector3.new(wallThickness, wallHeight, size.Z),
        Position = position + Vector3.new(size.X / 2, wallHeight / 2 + 1, 0),
        Color = Color3.fromRGB(180, 150, 100),
        Material = Enum.Material.Wood,
        Parent = house,
    })

    -- Крыша (чуть шире дома — свес 1 stud с каждой стороны)
    createPart({
        Name = "Roof",
        Size = Vector3.new(size.X + 2, 1.5, size.Z + 2),
        Position = position + Vector3.new(0, wallHeight + 1.75, 0),
        Color = Color3.fromRGB(139, 69, 19),
        Material = Enum.Material.Slate,
        Parent = house,
    })

    house.Parent = parent
    return house
end

-- ═══════════════════════════════════════════════════════════
-- УТИЛИТА: Забор
-- Создаёт горизонтальную или вертикальную планку между двумя точками.
-- Если direction.X ≈ 0 → поворачиваем на 90° (вертикальный забор).
-- ═══════════════════════════════════════════════════════════
local function createFence(startPos, endPos, parent)
    local direction = (endPos - startPos)
    local length = direction.Magnitude
    local midPoint = startPos + direction / 2

    local fence = createPart({
        Name = "Fence",
        Size = Vector3.new(length, 3, 0.5),
        Position = midPoint + Vector3.new(0, 1.5, 0),
        Color = Color3.fromRGB(139, 90, 43),
        Material = Enum.Material.Wood,
        Parent = parent,
    })

    -- Если забор идёт по Z (а не по X) — поворачиваем
    if math.abs(direction.X) < 0.1 then
        fence.Orientation = Vector3.new(0, 90, 0)
        fence.Size = Vector3.new(length, 3, 0.5)
    end

    return fence
end

-- ═══════════════════════════════════════════════════════════
-- УТИЛИТА: Невидимый триггер
-- Transparency=1, CanCollide=false.
-- Содержит BoolValue "IsTrigger" = true для идентификации.
-- GameManager обрабатывает касание триггеров через Touched.
-- ═══════════════════════════════════════════════════════════
local function createTrigger(name, position, size, parent)
    local trigger = createPart({
        Name = name,
        Size = size,
        Position = position,
        Transparency = 1,
        CanCollide = false,
        Parent = parent,
    })
    -- Маркер для скриптов: это триггер, а не обычная Part
    local tag = Instance.new("BoolValue")
    tag.Name = "IsTrigger"
    tag.Value = true
    tag.Parent = trigger
    return trigger
end

-- ═══════════════════════════════════════════════════════════
-- УТИЛИТА: SpawnLocation (точка появления игрока)
-- ═══════════════════════════════════════════════════════════
local function createSpawn(name, position, parent)
    local spawn = Instance.new("SpawnLocation")
    spawn.Name = name
    spawn.Size = Vector3.new(6, 1, 6)
    spawn.Position = position
    spawn.Anchored = true
    spawn.CanCollide = true
    spawn.Material = Enum.Material.SmoothPlastic
    spawn.Color = Color3.fromRGB(100, 200, 100)
    spawn.Transparency = 0.5                              -- полупрозрачный
    spawn.Parent = parent
    return spawn
end


-- ════════════════════════════════════════════════════════════════
-- ЗОНА 1: ДЕРЕВНЯ  (X: -100..100, Z: -100..100)
-- Центр мира на (0, 0, 0). Содержит:
-- • Дороги (булыжник)
-- • 5 домов (ElderHouse, GrandfatherHouse, TraderShop, House1, House2)
-- • Колодец с водой
-- • 8 деревьев по краям
-- • Заборы (северный и южный)
-- • SpawnLocation (VillageSpawn)
-- • Триггеры: VillageExit_North, GrandfatherHouse_Enter
-- ════════════════════════════════════════════════════════════════
function WorldGenerator:GenerateVillage()
    print("[WorldGenerator] Генерация деревни...")
    local zonesFolder = createFolder("Zones", Workspace)
    local villageFolder = createFolder("Village", zonesFolder)

    -- Земля деревни (200×200 studs, зелёная трава)
    createGround("Village", Vector3.new(0, 0, 0), Vector2.new(200, 200),
        Color3.fromRGB(100, 140, 60), Enum.Material.Grass, villageFolder)

    -- ─── ДОРОЖКИ (булыжник по центру) ───
    createPart({
        Name = "MainRoad",
        Size = Vector3.new(6, 0.5, 100),
        Position = Vector3.new(0, 0.25, 0),
        Color = Color3.fromRGB(150, 140, 130),
        Material = Enum.Material.Cobblestone,
        Parent = villageFolder,
    })

    -- ─── ДОМА ───
    -- ElderHouse — дом Старейшины (самый большой, X=-30)
    createHouse("ElderHouse", Vector3.new(-30, 0, -20), Vector3.new(14, 10, 12), villageFolder)
    -- GrandfatherHouse — дом деда героя (X=30)
    createHouse("GrandfatherHouse", Vector3.new(30, 0, -30), Vector3.new(12, 8, 10), villageFolder)
    -- TraderShop — лавка торговца (X=20, Z=20)
    createHouse("TraderShop", Vector3.new(20, 0, 20), Vector3.new(10, 8, 8), villageFolder)
    -- Жилые дома
    createHouse("House1", Vector3.new(-25, 0, 25), Vector3.new(10, 7, 10), villageFolder)
    createHouse("House2", Vector3.new(-40, 0, 10), Vector3.new(8, 7, 8), villageFolder)

    -- ─── КОЛОДЕЦ (центр деревни) ───
    local well = Instance.new("Model")
    well.Name = "Well"
    createPart({
        Name = "WellBase", Size = Vector3.new(5, 3, 5),
        Position = Vector3.new(0, 1.5, 10),
        Color = Color3.fromRGB(120, 120, 120),
        Material = Enum.Material.Brick, Parent = well,
    })
    createPart({
        Name = "WellWater", Size = Vector3.new(3.5, 0.5, 3.5),
        Position = Vector3.new(0, 2.5, 10),
        Color = Color3.fromRGB(50, 100, 200),            -- голубая вода
        Material = Enum.Material.Glass, Parent = well,
    })
    well.Parent = villageFolder

    -- ─── ДЕРЕВЬЯ (по краям деревни) ───
    local treePositions = {
        Vector3.new(-60, 0, -40), Vector3.new(-70, 0, 10), Vector3.new(-50, 0, 50),
        Vector3.new(50, 0, 50), Vector3.new(65, 0, -10), Vector3.new(55, 0, -50),
        Vector3.new(-80, 0, -20), Vector3.new(75, 0, 30),
    }
    for _, pos in ipairs(treePositions) do
        createTree(pos, villageFolder)
    end

    -- ─── ЗАБОРЫ (северный и южный край) ───
    createFence(Vector3.new(-90, 0, -90), Vector3.new(90, 0, -90), villageFolder)
    createFence(Vector3.new(-90, 0, 90), Vector3.new(90, 0, 90), villageFolder)

    -- ─── СПАВН ИГРОКА ───
    local spawnsFolder = createFolder("SpawnPoints", Workspace)
    createSpawn("VillageSpawn", Vector3.new(0, 1, 50), spawnsFolder)

    -- ─── ТРИГГЕРЫ ───
    local triggersFolder = createFolder("Triggers", Workspace)
    -- Выход из деревни на север (стадия WOLF_HUNT)
    createTrigger("VillageExit_North", Vector3.new(0, 5, -95), Vector3.new(30, 10, 5), triggersFolder)
    -- Вход в дом деда (стадия SECRET_MAP)
    createTrigger("GrandfatherHouse_Enter", Vector3.new(30, 5, -25), Vector3.new(6, 8, 4), triggersFolder)

    print("[WorldGenerator] Деревня готова!")
end


-- ════════════════════════════════════════════════════════════════
-- ЗОНА 2: ОКРЕСТНОСТИ  (центр X=300, Z=0)
-- Открытая местность со скалами и кустарником. Здесь спавнятся волки.
-- • 5 скал разного размера
-- • 5 разреженных деревьев
-- • 12 случайных кустов
-- • Триггер возврата в деревню (западный край)
-- ════════════════════════════════════════════════════════════════
function WorldGenerator:GenerateOutskirts()
    print("[WorldGenerator] Генерация окрестностей...")
    local zonesFolder = createFolder("Zones", Workspace)
    local outskirtsFolder = createFolder("Outskirts", zonesFolder)

    local center = Vector3.new(300, 0, 0)

    -- Земля (300×300, чуть темнее деревни)
    createGround("Outskirts", center, Vector2.new(300, 300),
        Color3.fromRGB(90, 130, 50), Enum.Material.Grass, outskirtsFolder)

    -- ─── СКАЛЫ (Slate, разного размера) ───
    local rocks = {
        { off = Vector3.new(-50, 0, -50), size = Vector3.new(8, 6, 10) },
        { off = Vector3.new(50, 0, 40), size = Vector3.new(12, 8, 8) },
        { off = Vector3.new(-20, 0, 80), size = Vector3.new(6, 4, 6) },
        { off = Vector3.new(30, 0, -70), size = Vector3.new(10, 10, 12) },
        { off = Vector3.new(70, 0, -30), size = Vector3.new(7, 5, 7) },
    }
    for _, rock in ipairs(rocks) do
        createPart({
            Name = "Rock",
            Size = rock.size,
            Position = center + rock.off + Vector3.new(0, rock.size.Y / 2, 0),
            Color = Color3.fromRGB(100, 95, 85),         -- серый камень
            Material = Enum.Material.Slate,
            Parent = outskirtsFolder,
        })
    end

    -- ─── ДЕРЕВЬЯ (разреженные — мало тени) ───
    local trees = {
        Vector3.new(-70, 0, 30), Vector3.new(0, 0, -90), Vector3.new(60, 0, 60),
        Vector3.new(-40, 0, 100), Vector3.new(90, 0, -60),
    }
    for _, off in ipairs(trees) do
        createTree(center + off, outskirtsFolder)
    end

    -- ─── КУСТАРНИКИ (12 штук, случайные позиции) ───
    for i = 1, 12 do
        createPart({
            Name = "Bush_" .. i,
            Size = Vector3.new(3, 2, 3),
            Position = center + Vector3.new(math.random(-100, 100), 1, math.random(-100, 100)),
            Color = Color3.fromRGB(50, 100, 40),         -- тёмно-зелёный
            Material = Enum.Material.Grass,
            Parent = outskirtsFolder,
        })
    end

    -- ─── ТРИГГЕР возврата в деревню (западный край зоны) ───
    local triggersFolder = createFolder("Triggers", Workspace)
    createTrigger("ReturnToVillage", center + Vector3.new(-140, 5, 0), Vector3.new(5, 10, 50), triggersFolder)

    print("[WorldGenerator] Окрестности готовы!")
end


-- ════════════════════════════════════════════════════════════════
-- ЗОНА 3: ЛЕС  (центр X=700, Z=200)
-- Тёмный густой лес. Содержит:
-- • Извилистая тропинка (синусоида по X)
-- • 60 деревьев (не ставятся на тропинку)
-- • 3 шипастых ловушки (SpikeTrap)
-- • 5 облаков тумана (полупрозрачные Part-ы)
-- • Арка входа в гробницу (камень, 3 Part-а)
-- • Триггер TombEntrance_Trigger
-- ════════════════════════════════════════════════════════════════
function WorldGenerator:GenerateForest()
    print("[WorldGenerator] Генерация леса...")
    local zonesFolder = createFolder("Zones", Workspace)
    local forestFolder = createFolder("Forest", zonesFolder)

    local center = Vector3.new(700, 0, 200)

    -- Земля (400×400, тёмно-зелёная)
    createGround("Forest", center, Vector2.new(400, 400),
        Color3.fromRGB(50, 80, 30), Enum.Material.Grass, forestFolder)

    -- ─── ТРОПИНКА (синусоида через лес) ───
    -- 21 сегмент по X, каждый смещён по Z = sin(i*0.5)*15
    for i = 0, 20 do
        local offset = math.sin(i * 0.5) * 15
        createPart({
            Name = "ForestPath_" .. i,
            Size = Vector3.new(5, 0.3, 20),
            Position = center + Vector3.new(-100 + i * 15, 0.15, offset),
            Color = Color3.fromRGB(110, 90, 60),         -- песочный
            Material = Enum.Material.Sand,
            Parent = forestFolder,
        })
    end

    -- ─── ДЕРЕВЬЯ (60 штук, не на тропинке) ───
    for i = 1, 60 do
        local pos = center + Vector3.new(
            math.random(-180, 180),
            0,
            math.random(-180, 180)
        )
        -- Проверяем, не попадает ли позиция на тропинку
        local onPath = false
        for j = 0, 20 do
            local pathX = center.X - 100 + j * 15
            if math.abs(pos.X - pathX) < 8 and math.abs(pos.Z - center.Z) < 15 then
                onPath = true
                break
            end
        end
        if not onPath then
            createTree(pos, forestFolder)
        end
    end

    -- ─── ЛОВУШКИ (шипастые платформы) ───
    -- StringValue "TrapType" = "Spike" для обработки в GameManager
    local trapOffsets = {
        Vector3.new(-50, 0, 10),
        Vector3.new(20, 0, -10),
        Vector3.new(80, 0, 15),
    }
    for _, off in ipairs(trapOffsets) do
        local trap = createPart({
            Name = "SpikeTrap",
            Size = Vector3.new(6, 0.5, 6),
            Position = center + off + Vector3.new(0, 0.25, 0),
            Color = Color3.fromRGB(80, 60, 30),
            Material = Enum.Material.WoodPlanks,
            Parent = forestFolder,
        })
        local tag = Instance.new("StringValue")
        tag.Name = "TrapType"
        tag.Value = "Spike"
        tag.Parent = trap
    end

    -- ─── ТУМАН (полупрозрачные облака) ───
    -- Transparency = 0.85 (почти невидимые, но создают атмосферу)
    for i = 1, 5 do
        createPart({
            Name = "FogCloud_" .. i,
            Size = Vector3.new(40, 15, 40),
            Position = center + Vector3.new(math.random(-100, 100), 8, math.random(-100, 100)),
            Color = Color3.fromRGB(200, 200, 210),
            Material = Enum.Material.SmoothPlastic,
            Transparency = 0.85,
            CanCollide = false,
            Parent = forestFolder,
        })
    end

    -- ─── АРКА ВХОДА В ГРОБНИЦУ (восточный конец леса) ───
    -- Три каменных Part-а: левый столб, правый столб, перемычка
    local archPos = center + Vector3.new(190, 0, 0)
    local tombEntrance = Instance.new("Model")
    tombEntrance.Name = "TombEntrance"
    createPart({
        Name = "EntranceArch_Left",
        Size = Vector3.new(3, 12, 3),
        Position = archPos + Vector3.new(0, 6, -5),
        Color = Color3.fromRGB(60, 60, 70),
        Material = Enum.Material.Slate,
        Parent = tombEntrance,
    })
    createPart({
        Name = "EntranceArch_Right",
        Size = Vector3.new(3, 12, 3),
        Position = archPos + Vector3.new(0, 6, 5),
        Color = Color3.fromRGB(60, 60, 70),
        Material = Enum.Material.Slate,
        Parent = tombEntrance,
    })
    createPart({
        Name = "EntranceArch_Top",
        Size = Vector3.new(3, 3, 13),
        Position = archPos + Vector3.new(0, 13, 0),
        Color = Color3.fromRGB(60, 60, 70),
        Material = Enum.Material.Slate,
        Parent = tombEntrance,
    })
    tombEntrance.Parent = forestFolder

    -- Триггер входа в гробницу
    local triggersFolder = createFolder("Triggers", Workspace)
    createTrigger("TombEntrance_Trigger", archPos + Vector3.new(2, 5, 0), Vector3.new(4, 10, 12), triggersFolder)

    print("[WorldGenerator] Лес готов!")
end


-- ════════════════════════════════════════════════════════════════
-- ЗОНА 4: ГРОБНИЦА / ЛАБИРИНТ  (центр X=1075, Z=200, Y=-10)
-- ════════════════════════════════════════════════════════════════
--
-- АЛГОРИТМ: Recursive Backtracker (DFS)
--
-- Шаги:
-- 1. Создаём сетку gridW × gridH (10×10 по умолчанию)
-- 2. Каждая ячейка имеет 4 стены: N, S, E, W
-- 3. Начинаем с [1][1], помечаем visited
-- 4. Ищем непосещённых соседей → выбираем случайного
-- 5. Убираем стену между текущей и соседней ячейками
-- 6. Переходим в соседнюю ячейку → повторяем с п.4
-- 7. Если соседей нет → backtrack (возврат по стеку)
-- 8. Когда стек пуст → лабиринт готов
-- 9. Открываем вход (W у [1][1]) и выход (E у [10][10])
--
-- Результат: идеальный лабиринт (единственный путь, без циклов)
--
-- ВИЗУАЛ:
-- • Пол (Slate, тёмный)
-- • Крыша (Slate, ещё темнее — нет неба)
-- • Стены высотой 12 studs
-- • Факелы на ~30% стен (случайные)
-- ════════════════════════════════════════════════════════════════
function WorldGenerator:GenerateTomb()
    print("[WorldGenerator] Генерация гробницы (лабиринт)...")
    local zonesFolder = createFolder("Zones", Workspace)
    local tombFolder = createFolder("Tomb", zonesFolder)

    local basePos = Vector3.new(1075, -10, 200)   -- под землёй (Y = -10)
    local wallHeight = 12
    local wallThickness = 2
    local cellSize = 12  -- размер одной ячейки лабиринта (studs)
    local gridW = 10     -- ячеек по X
    local gridH = 10     -- ячеек по Z
    local totalW = gridW * cellSize
    local totalH = gridH * cellSize
    local wallColor = Color3.fromRGB(50, 45, 40)   -- тёмный камень
    local floorColor = Color3.fromRGB(40, 38, 35)

    -- ─── ПОЛ ГРОБНИЦЫ ───
    createPart({
        Name = "TombFloor",
        Size = Vector3.new(totalW + wallThickness * 2, 2, totalH + wallThickness * 2),
        Position = basePos + Vector3.new(0, -1, 0),
        Color = floorColor,
        Material = Enum.Material.Slate,
        Parent = tombFolder,
    })

    -- ─── КРЫША ГРОБНИЦЫ (закрывает небо) ───
    createPart({
        Name = "TombCeiling",
        Size = Vector3.new(totalW + wallThickness * 2, 2, totalH + wallThickness * 2),
        Position = basePos + Vector3.new(0, wallHeight + 1, 0),
        Color = Color3.fromRGB(30, 28, 25),
        Material = Enum.Material.Slate,
        Parent = tombFolder,
    })

    -- ═══════════════════════════════════════════════════════
    -- ГЕНЕРАЦИЯ ЛАБИРИНТА — Recursive Backtracker (DFS)
    -- ═══════════════════════════════════════════════════════

    -- Сетка: grid[row][col] = { visited, walls = {N, S, E, W} }
    local grid = {}
    for r = 1, gridH do
        grid[r] = {}
        for c = 1, gridW do
            grid[r][c] = {
                visited = false,
                walls = { N = true, S = true, E = true, W = true },
            }
        end
    end

    -- Направления для поиска соседей
    local directions = {
        { name = "N", dr = -1, dc = 0, opposite = "S" },  -- север
        { name = "S", dr = 1,  dc = 0, opposite = "N" },  -- юг
        { name = "E", dr = 0,  dc = 1, opposite = "W" },  -- восток
        { name = "W", dr = 0,  dc = -1, opposite = "E" }, -- запад
    }

    -- Перемешивание массива (Fisher-Yates shuffle)
    local function shuffle(t)
        for i = #t, 2, -1 do
            local j = math.random(1, i)
            t[i], t[j] = t[j], t[i]
        end
    end

    -- DFS с backtracking
    local stack = {}
    local startR, startC = 1, 1
    grid[startR][startC].visited = true
    table.insert(stack, { startR, startC })

    while #stack > 0 do
        local current = stack[#stack]
        local r, c = current[1], current[2]

        -- Ищем непосещённых соседей
        local neighbors = {}
        for _, dir in ipairs(directions) do
            local nr = r + dir.dr
            local nc = c + dir.dc
            if nr >= 1 and nr <= gridH and nc >= 1 and nc <= gridW then
                if not grid[nr][nc].visited then
                    table.insert(neighbors, { nr, nc, dir })
                end
            end
        end

        if #neighbors > 0 then
            -- Есть соседи → выбираем случайного
            shuffle(neighbors)
            local chosen = neighbors[1]
            local nr, nc, dir = chosen[1], chosen[2], chosen[3]

            -- Убираем стену между текущей и соседней ячейками
            grid[r][c].walls[dir.name] = false
            grid[nr][nc].walls[dir.opposite] = false

            grid[nr][nc].visited = true
            table.insert(stack, { nr, nc })
        else
            -- Тупик → backtrack (возвращаемся назад)
            table.remove(stack)
        end
    end

    -- Вход: открываем западную стену ячейки [1][1]
    grid[1][1].walls.W = false

    -- Выход: открываем восточную стену ячейки [gridH][gridW]
    grid[gridH][gridW].walls.E = false

    -- ═══════════════════════════════════════════════════════
    -- ПОСТРОЕНИЕ 3D-СТЕН ПО СЕТКЕ
    -- Каждая ячейка строит СВОИ северную и западную стены.
    -- Южные стены строит только последний ряд.
    -- Восточные стены строит только последний столбец.
    -- ═══════════════════════════════════════════════════════
    local gridOrigin = basePos + Vector3.new(-totalW / 2, 0, -totalH / 2)

    local wallIndex = 0    -- счётчик стен (для уникальных имён)
    local torchCount = 0   -- счётчик факелов (для логирования)

    for r = 1, gridH do
        for c = 1, gridW do
            local cell = grid[r][c]
            -- Центр текущей ячейки в мировых координатах
            local cellX = gridOrigin.X + (c - 1) * cellSize + cellSize / 2
            local cellZ = gridOrigin.Z + (r - 1) * cellSize + cellSize / 2
            local cellCenter = Vector3.new(cellX, basePos.Y, cellZ)

            -- Северная стена (у всех ячеек, если есть)
            if cell.walls.N then
                wallIndex = wallIndex + 1
                createPart({
                    Name = "MazeWall_" .. wallIndex,
                    Size = Vector3.new(cellSize + wallThickness, wallHeight, wallThickness),
                    Position = cellCenter + Vector3.new(0, wallHeight / 2, -cellSize / 2),
                    Color = wallColor,
                    Material = Enum.Material.Slate,
                    Parent = tombFolder,
                })
            end

            -- Западная стена
            if cell.walls.W then
                wallIndex = wallIndex + 1
                createPart({
                    Name = "MazeWall_" .. wallIndex,
                    Size = Vector3.new(wallThickness, wallHeight, cellSize + wallThickness),
                    Position = cellCenter + Vector3.new(-cellSize / 2, wallHeight / 2, 0),
                    Color = wallColor,
                    Material = Enum.Material.Slate,
                    Parent = tombFolder,
                })
            end

            -- Южная стена (ТОЛЬКО для последнего ряда)
            if r == gridH and cell.walls.S then
                wallIndex = wallIndex + 1
                createPart({
                    Name = "MazeWall_" .. wallIndex,
                    Size = Vector3.new(cellSize + wallThickness, wallHeight, wallThickness),
                    Position = cellCenter + Vector3.new(0, wallHeight / 2, cellSize / 2),
                    Color = wallColor,
                    Material = Enum.Material.Slate,
                    Parent = tombFolder,
                })
            end

            -- Восточная стена (ТОЛЬКО для последнего столбца)
            if c == gridW and cell.walls.E then
                wallIndex = wallIndex + 1
                createPart({
                    Name = "MazeWall_" .. wallIndex,
                    Size = Vector3.new(wallThickness, wallHeight, cellSize + wallThickness),
                    Position = cellCenter + Vector3.new(cellSize / 2, wallHeight / 2, 0),
                    Color = wallColor,
                    Material = Enum.Material.Slate,
                    Parent = tombFolder,
                })
            end

            -- ─── ФАКЕЛЫ (~30% стен, случайные) ───
            if cell.walls.N and math.random() < 0.3 then
                torchCount = torchCount + 1
                createTorch(
                    cellCenter + Vector3.new(0, wallHeight - 3, -cellSize / 2 + 1),
                    tombFolder
                )
            end
            if cell.walls.W and math.random() < 0.3 then
                torchCount = torchCount + 1
                createTorch(
                    cellCenter + Vector3.new(-cellSize / 2 + 1, wallHeight - 3, 0),
                    tombFolder
                )
            end
        end
    end

    print("[WorldGenerator] Лабиринт:", gridW, "x", gridH, "| Стен:", wallIndex, "| Факелов:", torchCount)
    print("[WorldGenerator] Гробница готова!")
end


-- ════════════════════════════════════════════════════════════════
-- ЗОНА 5: ЗАЛ АРТЕФАКТА  (центр X=1300, Z=200, Y=-20)
-- Восьмиугольный зал с пьедесталом в центре. Содержит:
-- • Мраморный пол
-- • 8 стен (восьмиугольник, расставлены по углу)
-- • Купол (крыша)
-- • Пьедестал с Ban Hammer (с Neon-свечением)
-- • 6 колонн с фиолетовым светом
-- • Триггер BanHammer_Trigger
-- ════════════════════════════════════════════════════════════════
function WorldGenerator:GenerateArtifactHall()
    print("[WorldGenerator] Генерация зала артефакта...")
    local zonesFolder = createFolder("Zones", Workspace)
    local hallFolder = createFolder("ArtifactHall", zonesFolder)

    local basePos = Vector3.new(1300, -20, 200)   -- глубоко под землёй
    local wallHeight = 20

    -- ─── ПОЛ (мрамор) ───
    createPart({
        Name = "HallFloor",
        Size = Vector3.new(100, 2, 100),
        Position = basePos + Vector3.new(0, -1, 0),
        Color = Color3.fromRGB(30, 25, 35),           -- тёмный мрамор
        Material = Enum.Material.Marble,
        Parent = hallFolder,
    })

    -- ─── СТЕНЫ (восьмиугольник) ───
    -- 8 стен расставлены по кругу, каждая повёрнута на angle+90°
    local wallCount = 8
    local radius = 48
    for i = 1, wallCount do
        local angle = (i / wallCount) * math.pi * 2
        local x = math.cos(angle) * radius
        local z = math.sin(angle) * radius
        -- Длина каждой стены = 2 * R * sin(π/N) (формула стороны правильного N-угольника)
        local wallLength = 2 * radius * math.sin(math.pi / wallCount)

        local wall = createPart({
            Name = "HallWall_" .. i,
            Size = Vector3.new(wallLength, wallHeight, 3),
            Position = basePos + Vector3.new(x, wallHeight / 2, z),
            Color = Color3.fromRGB(40, 35, 50),
            Material = Enum.Material.Marble,
            Parent = hallFolder,
        })
        -- Поворачиваем стену: перпендикулярно радиусу
        wall.Orientation = Vector3.new(0, math.deg(angle) + 90, 0)
    end

    -- ─── КУПОЛ (крыша) ───
    createPart({
        Name = "HallCeiling",
        Size = Vector3.new(100, 3, 100),
        Position = basePos + Vector3.new(0, wallHeight + 1.5, 0),
        Color = Color3.fromRGB(20, 18, 25),
        Material = Enum.Material.Marble,
        Parent = hallFolder,
    })

    -- ─── ПЬЕДЕСТАЛ (основание + колонна) ───
    local pedestal = Instance.new("Model")
    pedestal.Name = "BanHammerPedestal"
    createPart({
        Name = "PedestalBase",
        Size = Vector3.new(8, 1, 8),
        Position = basePos + Vector3.new(0, 0.5, 0),
        Color = Color3.fromRGB(200, 180, 120),         -- золотистый мрамор
        Material = Enum.Material.Marble,
        Parent = pedestal,
    })
    createPart({
        Name = "PedestalColumn",
        Size = Vector3.new(4, 5, 4),
        Position = basePos + Vector3.new(0, 3.5, 0),
        Color = Color3.fromRGB(200, 180, 120),
        Material = Enum.Material.Marble,
        Parent = pedestal,
    })

    -- ─── BAN HAMMER (светящийся молот!) ───
    local hammer = Instance.new("Model")
    hammer.Name = "BanHammer"
    -- Ручка (деревянная)
    createPart({
        Name = "Handle",
        Size = Vector3.new(0.8, 5, 0.8),
        Position = basePos + Vector3.new(0, 8.5, 0),
        Color = Color3.fromRGB(139, 90, 43),
        Material = Enum.Material.Wood,
        Parent = hammer,
    })
    -- Головка молота (Neon — СВЕТИТСЯ!)
    createPart({
        Name = "HammerHead",
        Size = Vector3.new(3, 2.5, 2),
        Position = basePos + Vector3.new(0, 11.5, 0),
        Color = Color3.fromRGB(180, 50, 50),            -- красный
        Material = Enum.Material.Neon,
        Parent = hammer,
    })
    -- Свечение вокруг молота
    local glow = Instance.new("PointLight")
    glow.Color = Color3.fromRGB(255, 80, 80)
    glow.Brightness = 2
    glow.Range = 30
    glow.Parent = hammer:FindFirstChild("HammerHead")

    hammer.Parent = pedestal
    pedestal.Parent = hallFolder

    -- ─── КОЛОННЫ (6 штук по кругу, с фиолетовым светом) ───
    for i = 1, 6 do
        local angle = (i / 6) * math.pi * 2
        local x = math.cos(angle) * 30
        local z = math.sin(angle) * 30

        local col = createPart({
            Name = "Column_" .. i,
            Size = Vector3.new(4, wallHeight, 4),
            Position = basePos + Vector3.new(x, wallHeight / 2, z),
            Color = Color3.fromRGB(60, 55, 70),
            Material = Enum.Material.Marble,
            Parent = hallFolder,
        })

        -- Фиолетовый свет на колонне
        local colLight = Instance.new("PointLight")
        colLight.Color = Color3.fromRGB(100, 80, 200)
        colLight.Brightness = 0.5
        colLight.Range = 15
        colLight.Parent = col
    end

    -- ─── ТРИГГЕР МОЛОТА ───
    local triggersFolder = createFolder("Triggers", Workspace)
    createTrigger("BanHammer_Trigger", basePos + Vector3.new(0, 3, 0), Vector3.new(10, 8, 10), triggersFolder)

    print("[WorldGenerator] Зал артефакта готов!")
end


-- ════════════════════════════════════════════════════════════════
-- ГЕНЕРАЦИЯ ВСЕГО МИРА
-- Вызывает все зоны последовательно.
-- Порядок не критичен — зоны не зависят друг от друга.
-- ════════════════════════════════════════════════════════════════
function WorldGenerator:GenerateAll()
    print("==========================================")
    print("[WorldGenerator] НАЧАЛО ГЕНЕРАЦИИ МИРА")
    print("==========================================")

    self:GenerateVillage()       -- Зона 1
    self:GenerateOutskirts()     -- Зона 2
    self:GenerateForest()        -- Зона 3
    self:GenerateTomb()          -- Зона 4
    self:GenerateArtifactHall()  -- Зона 5

    print("==========================================")
    print("[WorldGenerator] МИР ГОТОВ!")
    print("Зоны: Деревня → Окрестности → Лес → Гробница → Зал")
    print("==========================================")
end

-- ═══════════════════════════════════════════════════════════
-- АВТОЗАПУСК ОТКЛЮЧЁН: карта уже построена в Studio.
-- Раскомментируйте строку ниже, если нужна процедурная генерация.
-- ═══════════════════════════════════════════════════════════
-- WorldGenerator:GenerateAll()

return WorldGenerator
