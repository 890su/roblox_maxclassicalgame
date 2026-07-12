--[[
    WeaponManager — Создание и выдача оружия игрокам
    ═══════════════════════════════════════════════════════════
    
    Этот модуль отвечает за ВСЕ, что связано с оружием:
    • Создание модели меча из отдельных Part-ов (рукоять, лезвие, гарда, навершие)
    • Привязка анимации удара и звуков
    • Обработка попаданий (Hit Detection через Touched)
    • Выдачу стартового оружия
    • Восстановление оружия при респавне
    • Выдачу улучшенного оружия (для будущих фич)
    
    ВАЖНО: Это ModuleScript (.lua), НЕ запускается сам.
    Вызывается из GameManager:
      WeaponManager:GiveStarterSword(player)
      WeaponManager:RestoreWeaponsOnRespawn(player)
    
    АРХИТЕКТУРА МЕЧА:
    ────────────────
    Tool (контейнер оружия в Roblox)
    ├── Handle (Part) — рукоять (обязательный для Tool!)
    │   ├── WeldConstraint → Guard
    │   ├── WeldConstraint → Blade
    │   └── WeldConstraint → Pommel
    ├── Blade (Part) — лезвие
    ├── Guard (Part) — гарда (перекрестье)
    └── Pommel (Part) — навершие (шарик внизу рукояти)
    
    КАК РАБОТАЕТ АТАКА:
    ───────────────────
    1. Игрок нажимает ЛКМ → tool.Activated → isAttacking = true
    2. Запускается анимация удара (rbxassetid://522635514)
    3. Играется звук удара (swordslash.wav)
    4. Если Handle или Blade касается врага → humanoid:TakeDamage(damage)
    5. Debounce (0.5 сек) не даёт наносить урон слишком часто
    6. Красная вспышка (PointLight) как визуальный отклик попадания
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local WeaponManager = {}

-- ═══════════════════════════════════════════════════════════
-- КЭШ ОРУЖИЯ ИГРОКОВ
-- Запоминаем, какое оружие было у игрока, чтобы восстановить
-- после потери (смерть/респавн). Tool уничтожается при смерти,
-- поэтому нужно пересоздавать его.
-- Формат: playerWeapons[Player] = { name, damage, color }
-- ═══════════════════════════════════════════════════════════
local playerWeapons = {}

-- ═══════════════════════════════════════════════════════════
-- СОЗДАНИЕ МОДЕЛИ МЕЧА
-- Строит меч из отдельных Part-ов и привязывает логику атаки.
-- Все части слтыеются через WeldConstraint к Handle.
--
-- Параметры:
--   swordName (string) — имя оружия (отображается в инвентаре)
--   damage (number)    — урон за удар (по умолчанию 25)
--   color (Color3?)    — цвет лезвия (по умолчанию серебристый)
--
-- Возвращает: объект Tool, готовый к размещению в Backpack
-- ═══════════════════════════════════════════════════════════
local function createSword(swordName, damage, color)
    damage = damage or 25

    -- Tool — специальный контейнер Roblox для экипируемых предметов.
    -- Игрок может экипировать Tool из Backpack нажатием на цифру (1-9).
    local tool = Instance.new("Tool")
    tool.Name = swordName or "Старый Меч"
    tool.RequiresHandle = true      -- Tool обязан иметь Part с именем "Handle"
    tool.CanBeDropped = false       -- запрещаем выкидывать (нажатие Backspace)

    -- Grip: точка хвата на Handle (локальные координаты рукояти).
    -- Рукоять 1.2 по Y — ладонь на нижней части → отрицательный Y.
    -- (0, 0, -1.5) уводил меч вдоль предплечья к локтю.
    tool.GripPos = Vector3.new(0, -0.55, 0.05)
    tool.GripForward = Vector3.new(0, 0, -1)
    tool.GripRight = Vector3.new(1, 0, 0)
    tool.GripUp = Vector3.new(0, 1, 0)

    -- ─── РУКОЯТЬ (Handle) ───
    -- "Handle" — обязательное имя! Без него Tool не работает.
    -- Roblox автоматически привязывает эту часть к руке персонажа.
    local handle = Instance.new("Part")
    handle.Name = "Handle"                        -- ОБЯЗАТЕЛЬНО "Handle"!
    handle.Size = Vector3.new(0.3, 1.2, 0.3)     -- тонкий вертикальный цилиндр
    handle.Color = Color3.fromRGB(101, 67, 33)   -- коричневый (дерево)
    handle.Material = Enum.Material.Wood
    handle.CanCollide = false                     -- не сталкивается с миром
    handle.Massless = true                        -- не влияет на физику персонажа
    handle.Parent = tool

    -- ─── ЛЕЗВИЕ (Blade) ───
    local blade = Instance.new("Part")
    blade.Name = "Blade"
    blade.Size = Vector3.new(0.15, 3.5, 0.6)     -- длинное и тонкое
    blade.Color = color or Color3.fromRGB(200, 200, 215)  -- серебристый
    blade.Material = Enum.Material.Metal
    blade.Reflectance = 0.3                       -- лёгкий блеск
    -- CanCollide true: иначе Touched не срабатывает при касании с NPC с CanCollide false
    blade.CanCollide = true
    blade.Massless = true
    blade.Parent = tool

    -- Привариваем лезвие к рукоятке (WeldConstraint жёстко связывает Part-ы)
    blade.CFrame = handle.CFrame * CFrame.new(0, 2.3, 0) -- выше рукоятки
    local bladeWeld = Instance.new("WeldConstraint")
    bladeWeld.Part0 = handle
    bladeWeld.Part1 = blade
    bladeWeld.Parent = blade

    -- ─── ГАРДА (Guard — перекрестье) ───
    local guard = Instance.new("Part")
    guard.Name = "Guard"
    guard.Size = Vector3.new(1.0, 0.2, 0.4)      -- горизонтальная перекладина
    guard.Color = Color3.fromRGB(170, 140, 50)    -- золотистый
    guard.Material = Enum.Material.Metal
    guard.CanCollide = false
    guard.Massless = true
    guard.Parent = tool

    -- Позиционируем: чуть выше рукоятки (между рукоятью и лезвием)
    guard.CFrame = handle.CFrame * CFrame.new(0, 0.6, 0)
    local guardWeld = Instance.new("WeldConstraint")
    guardWeld.Part0 = handle
    guardWeld.Part1 = guard
    guardWeld.Parent = guard

    -- ─── НАВЕРШИЕ (Pommel — шарик внизу рукояти) ───
    local pommel = Instance.new("Part")
    pommel.Name = "Pommel"
    pommel.Shape = Enum.PartType.Ball             -- сферическая форма
    pommel.Size = Vector3.new(0.5, 0.5, 0.5)
    pommel.Color = Color3.fromRGB(170, 140, 50)   -- золотистый
    pommel.Material = Enum.Material.Metal
    pommel.CanCollide = false
    pommel.Massless = true
    pommel.Parent = tool

    -- Позиционируем: под рукояткой
    pommel.CFrame = handle.CFrame * CFrame.new(0, -0.6, 0)
    local pommelWeld = Instance.new("WeldConstraint")
    pommelWeld.Part0 = handle
    pommelWeld.Part1 = pommel
    pommelWeld.Parent = pommel

    -- ═══════════════════════════════════════
    -- ЛОГИКА АТАКИ
    -- isAttacking — флаг: активна ли анимация удара. 
    --   Урон наносится ТОЛЬКО когда true.
    -- debounce — защита от множественных попаданий за один взмах.
    --   После удара 0.5 секунды урон не наносится повторно.
    -- ═══════════════════════════════════════
    local isAttacking = false
    local debounce = false

    -- Activated вызывается при ЛКМ (левый клик мыши) или тапе на мобильном
    tool.Activated:Connect(function()
        if isAttacking then return end   -- защита от спама кликами
        isAttacking = true

        -- Запускаем анимацию удара мечом
        local character = tool.Parent   -- когда Tool экипирован, его Parent = Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                -- Создаём объект Animation с ID стандартного удара Roblox
                local slashAnim = Instance.new("Animation")
                slashAnim.AnimationId = "rbxassetid://522635514" -- анимация slash

                -- Animator — компонент, который проигрывает анимации
                local animator = humanoid:FindFirstChildOfClass("Animator")
                if not animator then
                    animator = Instance.new("Animator")
                    animator.Parent = humanoid
                end

                -- Загружаем и проигрываем
                local track = animator:LoadAnimation(slashAnim)
                track.Priority = Enum.AnimationPriority.Action  -- приоритет выше ходьбы
                track:Play()

                -- Очистка (удаляем объект Animation после проигрывания)
                track.Stopped:Connect(function()
                    slashAnim:Destroy()
                end)
            end
        end

        -- Звук удара
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxasset://sounds/swordslash.wav"    -- встроенный звук Roblox
        sound.Volume = 0.5
        sound.PlaybackSpeed = 0.9 + math.random() * 0.2       -- случайный питч (разнообразие)
        sound.Parent = handle
        sound:Play()
        sound.Ended:Connect(function() sound:Destroy() end)   -- самоуничтожение после проигрывания

        -- Окно нанесения урона: 0.4 сек после нажатия
        task.wait(0.4)
        isAttacking = false
    end)

    -- ═══════════════════════════════════════
    -- ОБРАБОТКА ПОПАДАНИЙ (Hit Detection)
    -- Когда рукоять или лезвие касается Part-а другой модели,
    -- проверяем: есть ли у неё Humanoid? Если да — наносим урон.
    -- ═══════════════════════════════════════

    -- Обработчик попадания (общий для Handle и Blade)
    local function onHit(hit)
        if not isAttacking then return end   -- нет активной атаки — игнорируем
        if debounce then return end          -- кулдаун ещё не прошёл

        -- Находим Model, к которой принадлежит задетый Part
        local hitModel = hit:FindFirstAncestorOfClass("Model")
        if not hitModel then return end

        -- Проверяем: есть ли у модели Humanoid (NPC или игрок)?
        local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        if humanoid.Health <= 0 then return end  -- уже мёртв

        -- Защита: не бить самого себя
        local toolParent = tool.Parent
        if toolParent and hitModel == toolParent then return end

        -- Дополнительная защита: не бить владельца меча
        local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
        local owner = Players:GetPlayerFromCharacter(toolParent)
        if hitPlayer and hitPlayer == owner then return end

        -- НАНОСИМ УРОН!
        debounce = true
        humanoid:TakeDamage(damage)

        -- Визуальный отклик: красная вспышка PointLight на 0.15 сек
        local hitPart = hitModel:FindFirstChild("HumanoidRootPart") or hit
        local flash = Instance.new("PointLight")
        flash.Color = Color3.fromRGB(255, 50, 50)   -- красный
        flash.Brightness = 3
        flash.Range = 8
        flash.Parent = hitPart
        task.delay(0.15, function()
            flash:Destroy()
        end)

        -- Кулдаун 0.5 сек перед следующим нанесением урона
        task.wait(0.5)
        debounce = false
    end

    -- Регистрируем попадания для рукоятки И лезвия
    handle.Touched:Connect(onHit)
    blade.Touched:Connect(onHit)

    return tool
end

-- ═══════════════════════════════════════════════════════════
-- ВЫДАЧА СТАРТОВОГО МЕЧА
-- Вызывается из GameManager после первого диалога со Старейшиной.
-- Проверяет, нет ли уже меча (защита от дублирования).
-- ═══════════════════════════════════════════════════════════
function WeaponManager:GiveStarterSword(player)
    local character = player.Character
    if not character then
        character = player.CharacterAdded:Wait()  -- ждём, если персонаж ещё не загружен
    end

    -- Проверяем: меч уже есть в Backpack или в руках?
    local backpack = player:FindFirstChild("Backpack")
    if backpack and backpack:FindFirstChild("Старый Меч") then
        return   -- уже есть в рюкзаке
    end
    if character:FindFirstChild("Старый Меч") then
        return   -- уже экипирован
    end

    -- Создаём и выдаём
    local sword = createSword("Старый Меч", 25, Color3.fromRGB(200, 200, 215))
    sword.Parent = backpack or character

    -- Запоминаем для восстановления при респавне
    playerWeapons[player] = { name = "Старый Меч", damage = 25, color = Color3.fromRGB(200, 200, 215) }

    print("[WeaponManager] Выдан Старый Меч для", player.Name)

    -- Уведомление в HUD
    local updateEvent = Remotes:GetEvent("UpdateHUD")
    if updateEvent then
        updateEvent:FireClient(player, {
            Notification = "⚔️ Получен: Старый Меч"
        })
    end
end

-- ═══════════════════════════════════════════════════════════
-- ВОССТАНОВЛЕНИЕ ОРУЖИЯ ПРИ РЕСПАВНЕ
-- При смерти персонажа все Tool уничтожаются. Нужно пересоздать.
-- Вызывается из GameManager в обработчике CharacterAdded.
-- ═══════════════════════════════════════════════════════════
function WeaponManager:RestoreWeaponsOnRespawn(player)
    local weaponInfo = playerWeapons[player]
    if not weaponInfo then return end  -- у игрока не было оружия

    local character = player.Character
    if not character then return end

    -- Ждём полную загрузку персонажа
    task.wait(0.5)

    -- Проверяем: может быть меч уже восстановился?
    local backpack = player:FindFirstChild("Backpack")
    if backpack and backpack:FindFirstChild(weaponInfo.name) then return end
    if character:FindFirstChild(weaponInfo.name) then return end

    -- Пересоздаём меч
    local sword = createSword(weaponInfo.name, weaponInfo.damage, weaponInfo.color)
    sword.Parent = backpack or character

    print("[WeaponManager] Восстановлен меч при респавне для", player.Name)
end

-- ═══════════════════════════════════════════════════════════
-- ОЧИСТКА ПРИ ВЫХОДЕ ИГРОКА
-- Удаляем запись из кэша, чтобы не утекала память.
-- ═══════════════════════════════════════════════════════════
function WeaponManager:OnPlayerLeaving(player)
    playerWeapons[player] = nil
end

-- ═══════════════════════════════════════════════════════════
-- ВЫДАЧА УЛУЧШЕННОГО ОРУЖИЯ (для будущих фич)
-- Можно вызвать для выдачи любого оружия с кастомными параметрами.
--
-- Пример: WeaponManager:GiveWeapon(player, "Огненный Меч", 50, Color3.fromRGB(255, 100, 0))
-- ═══════════════════════════════════════════════════════════
local function createBanHammerTool(): Tool
    local tool = Instance.new("Tool")
    tool.Name = "Ban Hammer"
    tool.CanBeDropped = false
    tool.RequiresHandle = true
    tool.GripPos = Vector3.new(0, -0.35, 0.15)
    tool.GripForward = Vector3.new(0, 0, -1)
    tool.GripRight = Vector3.new(1, 0, 0)
    tool.GripUp = Vector3.new(0, 1, 0)

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.35, 1.1, 0.35)
    handle.Color = Color3.fromRGB(55, 45, 75)
    handle.Material = Enum.Material.Metal
    handle.CanCollide = false
    handle.Massless = true
    handle.Parent = tool

    local head = Instance.new("Part")
    head.Name = "HammerHead"
    head.Size = Vector3.new(1.4, 0.55, 1.0)
    head.Color = Color3.fromRGB(120, 90, 200)
    head.Material = Enum.Material.Neon
    head.CanCollide = false
    head.Massless = true
    head.Parent = tool
    head.CFrame = handle.CFrame * CFrame.new(0, 1.0, 0)
    local w = Instance.new("WeldConstraint")
    w.Part0 = handle
    w.Part1 = head
    w.Parent = head

    return tool
end

function WeaponManager:GiveBanHammer(player)
    local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 10)
    if not backpack then
        return
    end
    if backpack:FindFirstChild("Ban Hammer") or (player.Character and player.Character:FindFirstChild("Ban Hammer")) then
        return
    end

    local tool = createBanHammerTool()
    tool.Parent = backpack

    local updateEvent = Remotes:GetEvent("UpdateHUD")
    if updateEvent then
        updateEvent:FireClient(player, {
            Notification = "🔨 Получен Ban Hammer",
        })
    end
    print("[WeaponManager] Выдан Ban Hammer для", player.Name)
end

function WeaponManager:GiveWeapon(player, weaponName, damage, color)
    local character = player.Character
    if not character then return end

    local backpack = player:FindFirstChild("Backpack")
    local sword = createSword(weaponName, damage, color)
    sword.Parent = backpack or character

    -- Обновляем кэш (будет восстановлен при респавне)
    playerWeapons[player] = { name = weaponName, damage = damage, color = color }

    -- Уведомление в HUD
    local updateEvent = Remotes:GetEvent("UpdateHUD")
    if updateEvent then
        updateEvent:FireClient(player, {
            Notification = "⚔️ Получен: " .. weaponName
        })
    end
end

return WeaponManager
