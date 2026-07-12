--[[
    MiniBossSpawner — спаун и AI King Hydra Blaster
    ═══════════════════════════════════════════════════════════

    Жизненный цикл:
    1. GameManager переключает стадию MINI_BOSS
       → вызывается MiniBossSpawner:Spawn(player)
    2. Босс клонируется из ServerStorage.Assets.KingHydraBlaster
       и размещается на MiniBossArena.SpawnPoint
    3. Квест DEFEAT_MINI_BOSS запускается автоматически
    4. AI: патруль → chase → атака
    5. Смерть: QuestManager:UpdateProgress → SetStage(TOMB_MAZE)
    6. MiniBossSpawner:Clear(player) — очистка при любом выходе
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local ServerStorage    = game:GetService("ServerStorage")
local ContentProvider  = game:GetService("ContentProvider")

local Shared        = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig    = require(ServerScriptService:WaitForChild("GameConfig"))

local MiniBossSpawner = {}

-- активные боссы: [userId] = { model, connection, patrolTarget }
local activeBosses = {}

-- ─────────────────────────────────────────────────────────────
-- Вспомогательные функции
-- ─────────────────────────────────────────────────────────────

local function getRootPart(model)
    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
end

local function getHumanoidRootPart(character)
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function distanceTo(from, to)
    return (from - to).Magnitude
end

local function randomPatrolPoint(center, radius)
    local angle = math.random() * 2 * math.pi
    local r     = math.random() * radius
    return Vector3.new(
        center.X + math.cos(angle) * r,
        center.Y,
        center.Z + math.sin(angle) * r
    )
end

--- Часть уже в скелете Motor6D — не дублируем WeldConstraint к корню (конфликт с физикой).
local function isPartInAnyMotor6D(boss, part)
    for _, d in ipairs(boss:GetDescendants()) do
        if d:IsA("Motor6D") and (d.Part0 == part or d.Part1 == part) then
            return true
        end
    end
    return false
end

-- ─────────────────────────────────────────────────────────────
-- Подсистема Fire (ДО createBossModel: иначе prepareFireInitially ещё nil при вызове createBossModel)
-- ─────────────────────────────────────────────────────────────

local function getFireRoot(boss)
    local direct = boss:FindFirstChild("Fire")
    if direct then return direct end
    return boss:FindFirstChild("Fire", true)
end

local function setFireVisual(fireRoot, enabled)
    if not fireRoot then return end
    local function visit(inst)
        if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") then
            inst.Enabled = enabled
        elseif inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
            inst.Enabled = enabled
        end
    end
    visit(fireRoot)
    for _, d in ipairs(fireRoot:GetDescendants()) do
        visit(d)
    end
end

local function getFireDamageAnchor(fireRoot)
    if not fireRoot then return nil end
    if fireRoot:IsA("BasePart") then
        return fireRoot
    end
    return fireRoot:FindFirstChildWhichIsA("BasePart", true)
end

local function prepareFireInitially(boss)
    local fireRoot = getFireRoot(boss)
    if fireRoot then
        setFireVisual(fireRoot, false)
        print("[MiniBossSpawner] Fire найден, старт выключен:", fireRoot:GetFullName())
    else
        print("[MiniBossSpawner] Дочерний Fire не найден — огонь отключён.")
    end
    return fireRoot
end

-- ─────────────────────────────────────────────────────────────
-- Создание модели
-- ─────────────────────────────────────────────────────────────

local function createBossModel(spawnPosition)
    local cfg      = GameConfig.MiniBoss
    local assets   = ServerStorage:WaitForChild("Assets", 10)
    local template = assets and assets:FindFirstChild(cfg.ModelName)

    print("[MiniBossSpawner] Ищем модель '" .. cfg.ModelName .. "' в ServerStorage.Assets:", template ~= nil and "НАЙДЕНА" or "НЕ НАЙДЕНА")

    local boss
    if template then
        boss = template:Clone()
        print("[MiniBossSpawner] Модель клонирована из Assets")
    else
        -- Fallback: простая заглушка, если модель ещё не добавлена в Studio
        warn("[MiniBossSpawner] Модель '" .. cfg.ModelName .. "' не найдена в ServerStorage.Assets — используется заглушка")
        boss = Instance.new("Model")
        boss.Name = cfg.ModelName

        local body = Instance.new("Part")
        body.Name     = "HumanoidRootPart"
        body.Size     = Vector3.new(5, 8, 5)
        body.Anchored = false
        body.BrickColor = BrickColor.new("Dark green")
        body.Parent   = boss
        boss.PrimaryPart = body

        local humanoid = Instance.new("Humanoid")
        humanoid.Parent = boss
    end

    -- Humanoid: сначала прямой потомок модели (не чужой Humanoid во вложенной модели)
    local humanoid = boss:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        humanoid = boss:FindFirstChildWhichIsA("Humanoid")
    end
    if not humanoid then
        humanoid = Instance.new("Humanoid")
        humanoid.Parent = boss
    end

    local nHum = 0
    for _, d in ipairs(boss:GetDescendants()) do
        if d:IsA("Humanoid") then
            nHum += 1
        end
    end
    if nHum > 1 then
        warn("[MiniBossSpawner] В модели несколько Humanoid (", nHum, ") — используется:", humanoid:GetFullName())
    end

    humanoid.MaxHealth  = cfg.MaxHealth
    humanoid.Health     = cfg.MaxHealth
    humanoid.WalkSpeed  = cfg.WalkSpeed
    humanoid.Name       = "Humanoid"
    humanoid.PlatformStand = false
    humanoid.Sit = false
    humanoid.AutoRotate = true
    -- Кастомные существа без шеи R15 часто мгновенно умирают, если RequiresNeck = true
    pcall(function()
        humanoid.RequiresNeck = false
    end)
    -- Падение с высоты / урон от падения у крупных NPC
    pcall(function()
        humanoid:SetAttribute("FallDamageEnabled", false)
    end)
    pcall(function()
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Walking, true)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
    end)

    boss.Name = "KingHydraBlaster"

    -- Humanoid:MoveTo требует часть с именем HumanoidRootPart (см. доку Roblox / поведение рига).
    local rootPart = boss:FindFirstChild("HumanoidRootPart")
    if rootPart and rootPart:IsA("BasePart") then
        boss.PrimaryPart = rootPart
    else
        rootPart = boss.PrimaryPart
        if not rootPart or not rootPart:IsA("BasePart") then
            rootPart = boss:FindFirstChildWhichIsA("BasePart")
        end
        if rootPart then
            local oldName = rootPart.Name
            rootPart.Name = "HumanoidRootPart"
            boss.PrimaryPart = rootPart
            if oldName ~= "HumanoidRootPart" then
                print("[MiniBossSpawner] Корень переименован в HumanoidRootPart (было:", oldName .. ")")
            end
        end
    end

    -- Привариваем «рваные» части к корню. Пропускаем: уже Weld к корню, или часть в Motor6D (иначе конфликт с суставами).
    local weldCount = 0
    for _, part in ipairs(boss:GetDescendants()) do
        if part:IsA("BasePart") and part ~= rootPart and rootPart then
            if isPartInAnyMotor6D(boss, part) then
                continue
            end
            local alreadyWeldToRoot = false
            for _, c in ipairs(boss:GetDescendants()) do
                if (c:IsA("WeldConstraint") or c:IsA("Weld")) and (c.Part0 == rootPart or c.Part1 == rootPart) then
                    if c.Part0 == part or c.Part1 == part then
                        alreadyWeldToRoot = true
                        break
                    end
                end
            end
            if not alreadyWeldToRoot then
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = rootPart
                weld.Part1 = part
                weld.Parent = rootPart
                weldCount += 1
            end
        end
    end
    if weldCount > 0 then
        print("[MiniBossSpawner] Приварено к корню частей:", weldCount)
    end

    -- Разанкориваем все части — сварка держит их вместе.
    for _, part in ipairs(boss:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = false
        end
    end

    -- Разместить модель
    if boss.PrimaryPart then
        boss:SetPrimaryPartCFrame(CFrame.new(spawnPosition))
    else
        local root = getRootPart(boss)
        if root then root.CFrame = CFrame.new(spawnPosition) end
    end

    boss.Parent = workspace

    print(
        "[MiniBossSpawner] PrimaryPart:",
        boss.PrimaryPart and boss.PrimaryPart.Name or "nil",
        "| HumanoidRootPart:",
        boss:FindFirstChild("HumanoidRootPart") and "ok" or "MISSING"
    )

    prepareFireInitially(boss)

    return boss, humanoid
end

-- ─────────────────────────────────────────────────────────────
-- Вспомогательные эффекты
-- ─────────────────────────────────────────────────────────────

-- Кольцевая волна на земле (визуал удара об землю)
local function spawnShockwave(position, color, radius)
    local ring = Instance.new("Part")
    ring.Shape       = Enum.PartType.Cylinder
    ring.Size        = Vector3.new(0.25, 0.5, 0.5)
    ring.Anchored    = true
    ring.CanCollide  = false
    ring.CFrame      = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
    ring.Color       = color
    ring.Material    = Enum.Material.Neon
    ring.Transparency = 0.2
    ring.Parent      = workspace

    local tween = TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size          = Vector3.new(0.1, radius * 2, radius * 2),
        Transparency  = 1,
    })
    tween:Play()
    tween.Completed:Connect(function() ring:Destroy() end)
end

-- Нанести урон по области вокруг позиции
local function areaDamage(position, radius, damage, targetCharacter)
    local hrp = getHumanoidRootPart(targetCharacter)
    if not hrp then return end
    if distanceTo(hrp.Position, position) <= radius then
        local h = targetCharacter:FindFirstChildWhichIsA("Humanoid")
        if h and h.Health > 0 then
            h:TakeDamage(damage)
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Анимация из AnimSaves / Animation в модели
-- KeyframeSequence из редактора без AnimationId не проигрывается — нужен опубликованный Animation.
-- ─────────────────────────────────────────────────────────────

local function animationHasValidId(anim)
    return anim:IsA("Animation")
        and anim.AnimationId ~= ""
        and anim.AnimationId ~= "rbxassetid://0"
end

--- Нормализация id: "123" → "rbxassetid://123"
local function normalizeAnimationAssetId(raw)
    if type(raw) ~= "string" then
        return nil
    end
    local s = raw:match("^%s*(.-)%s*$") or ""
    if s == "" or s == "rbxassetid://0" then
        return nil
    end
    if s:match("^rbxassetid://") then
        return s
    end
    if s:match("^%d+$") then
        return "rbxassetid://" .. s
    end
    return nil
end

--- Анимация из GameConfig.LoopAnimationAssetId (приоритетнее поиска в модели).
local function animationFromConfig(cfg)
    local id = normalizeAnimationAssetId(cfg.LoopAnimationAssetId)
    if not id then
        return nil
    end
    local a = Instance.new("Animation")
    a.Name = "LoopBoss_Config"
    a.AnimationId = id
    return a
end

local function findPlayableAnimation(boss)
    local cfg = GameConfig.MiniBoss
    local name = cfg.LoopAnimationName
    if type(name) == "string" and name ~= "" then
        local pref = boss:FindFirstChild(name, true)
        if pref and animationHasValidId(pref) then
            return pref
        end
        for _, d in ipairs(boss:GetDescendants()) do
            if d:IsA("Animation") and d.Name:lower() == name:lower() and animationHasValidId(d) then
                return d
            end
        end
    end

    local animSaves = boss:FindFirstChild("AnimSaves", true)
    if animSaves then
        for _, d in ipairs(animSaves:GetDescendants()) do
            if animationHasValidId(d) then
                return d
            end
        end
    end
    for _, d in ipairs(boss:GetDescendants()) do
        if animationHasValidId(d) then
            return d
        end
    end
    return nil
end

--- Почему не нашли трек: KeyframeSequence ≠ Animation, пустой AnimationId и т.д.
local function printAnimationDiagnostics(boss, _cfg)
    local hum = boss:FindFirstChildOfClass("Humanoid")
    if hum then
        print("[MiniBossSpawner][anim] Humanoid.RigType =", hum.RigType, "| HRP =", boss:FindFirstChild("HumanoidRootPart") and "ok" or "MISSING")
    end
    print(
        "[MiniBossSpawner][anim] AnimationController на модели =",
        boss:FindFirstChildOfClass("AnimationController") ~= nil,
        "| (скин/кастом: трек часто нужно вешать сюда, см. LoopAnimationAnimatorTarget)"
    )
    local animSaves = boss:FindFirstChild("AnimSaves", true)
    if animSaves then
        for _, d in ipairs(animSaves:GetDescendants()) do
            if d:IsA("KeyframeSequence") then
                print(
                    "[MiniBossSpawner][anim] KeyframeSequence «"
                        .. d.Name
                        .. "» — только после Publish → rbxassetid в LoopAnimationAssetId или в объект Animation."
                )
            end
        end
    end
    for _, d in ipairs(boss:GetDescendants()) do
        if d:IsA("Animation") then
            local ok = animationHasValidId(d)
            print(
                "[MiniBossSpawner][anim] Animation «"
                    .. d.Name
                    .. "» id="
                    .. tostring(d.AnimationId)
                    .. (ok and " (ok)" or " (пусто/0)")
            )
        end
    end
end

local ANIM_PRIORITY_BY_NAME = {
    Idle = Enum.AnimationPriority.Idle,
    Movement = Enum.AnimationPriority.Movement,
    Action = Enum.AnimationPriority.Action,
    Core = Enum.AnimationPriority.Core,
}

local function resolveLoopAnimationPriority(cfg)
    local name = cfg.LoopAnimationPriority
    if type(name) == "string" then
        local p = ANIM_PRIORITY_BY_NAME[name]
        if p then
            return p
        end
    end
    return Enum.AnimationPriority.Action
end

--- Humanoid или AnimationController (скин-меши / кастом часто требуют AC на модели).
local function resolveAnimatorForBoss(boss, humanoid, cfg)
    local mode = cfg.LoopAnimationAnimatorTarget
    if type(mode) ~= "string" then
        mode = "Auto"
    end
    mode = mode:lower()

    local function acAnimator()
        local ac = boss:FindFirstChildOfClass("AnimationController")
        if not ac then
            return nil
        end
        local anim = ac:FindFirstChildOfClass("Animator")
        if not anim then
            anim = Instance.new("Animator")
            anim.Parent = ac
        end
        return anim, "AnimationController"
    end

    local function humAnimator()
        local anim = humanoid:FindFirstChildOfClass("Animator")
        if not anim then
            anim = Instance.new("Animator")
            anim.Parent = humanoid
        end
        return anim, "Humanoid"
    end

    if mode == "animationcontroller" then
        local a, tag = acAnimator()
        if a then
            return a, tag
        end
        warn("[MiniBossSpawner] LoopAnimationAnimatorTarget=AnimationController, но AnimationController не найден — Humanoid")
        return humAnimator()
    elseif mode == "humanoid" then
        return humAnimator()
    end

    -- Auto: сначала AnimationController (если есть), иначе Humanoid
    local a, tag = acAnimator()
    if a then
        return a, tag
    end
    return humAnimator()
end

local function startLoopingBossAnimation(humanoid, boss)
    local cfg = GameConfig.MiniBoss
    if cfg.LoopBossAnimation == false then
        print("[MiniBossSpawner] LoopBossAnimation выключен в GameConfig")
        return nil
    end
    local animInstance = animationFromConfig(cfg) or findPlayableAnimation(boss)
    local configOwnedAnim = animInstance and animInstance.Name == "LoopBoss_Config"
    if not animInstance then
        printAnimationDiagnostics(boss, cfg)
        warn(
            "[MiniBossSpawner] Нет рабочего AnimationId: задайте GameConfig.MiniBoss.LoopAnimationAssetId после Publish,"
                .. " либо в модели объект Animation «"
                .. tostring(cfg.LoopAnimationName)
                .. "» с rbxassetid://… (KeyframeSequence в AnimSaves сам по себе не проигрывается)."
        )
        return nil
    end
    if configOwnedAnim then
        animInstance.Parent = boss
    end
    pcall(function()
        ContentProvider:PreloadAsync({ animInstance })
    end)

    local animator, animatorTag = resolveAnimatorForBoss(boss, humanoid, cfg)
    local ok, track = pcall(function()
        return animator:LoadAnimation(animInstance)
    end)
    if not ok or not track then
        if configOwnedAnim then
            animInstance:Destroy()
        end
        warn("[MiniBossSpawner] LoadAnimation не удался:", animInstance:GetFullName(), "| animator=", animatorTag)
        return nil
    end
    track.Looped = true
    track.Priority = resolveLoopAnimationPriority(cfg)
    local w = cfg.LoopAnimationWeight
    if type(w) ~= "number" or w < 0 or w > 1 then
        w = 1
    end
    track:Play(0.15, w, 1)
    task.defer(function()
        task.wait(0.25)
        local len = 0
        local playing = false
        pcall(function()
            len = track.Length
            playing = track.IsPlaying
        end)
        print(
            "[MiniBossSpawner][anim] после загрузки: animator=",
            animatorTag,
            "| Length=",
            len,
            "| IsPlaying=",
            tostring(playing)
        )
        if len <= 0 then
            warn(
                "[MiniBossSpawner] Length трека 0. Частая причина в Studio: «The experience doesn't have access permission to use asset id …»"
                    .. " → Creator Dashboard → вкладка ассета (Animation) → разрешите использование этому experience / группе владельца места,"
                    .. " либо опубликуйте анимацию с того же аккаунта, что и игра."
                    .. " Иначе: риг не совпадает — попробуйте LoopAnimationAnimatorTarget Humanoid/AnimationController; ключи под Motor6D/Bone модели."
            )
        end
        if not playing then
            warn(
                "[MiniBossSpawner] Трек не IsPlaying — проверьте AnimationId и разрешения ассета:",
                animInstance.AnimationId
            )
        end
    end)
    print(
        "[MiniBossSpawner] Зациклена анимация:",
        animInstance.Name,
        animInstance.AnimationId,
        "animator=",
        animatorTag,
        "priority=",
        tostring(track.Priority),
        "weight=",
        w,
        "| source=",
        configOwnedAnim and "GameConfig.LoopAnimationAssetId" or "model"
    )
    return track
end

-- ─────────────────────────────────────────────────────────────
-- Полоса HP над боссом
-- ─────────────────────────────────────────────────────────────

local function attachHealthBar(boss, humanoid)
    local root = getRootPart(boss)
    if not root then return end

    local gui = Instance.new("BillboardGui")
    gui.Name          = "BossHP"
    gui.Size          = UDim2.new(0, 200, 0, 22)
    gui.StudsOffset   = Vector3.new(0, 5, 0)
    gui.AlwaysOnTop   = false
    gui.Parent        = root

    local bg = Instance.new("Frame")
    bg.Size                 = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3     = Color3.fromRGB(20, 20, 20)
    bg.BorderSizePixel      = 0
    bg.Parent               = gui

    local bar = Instance.new("Frame")
    bar.Name                = "Bar"
    bar.Size                = UDim2.new(1, 0, 0.6, 0)
    bar.Position            = UDim2.new(0, 0, 0.2, 0)
    bar.BackgroundColor3    = Color3.fromRGB(30, 200, 60)
    bar.BorderSizePixel     = 0
    bar.Parent              = bg

    local label = Instance.new("TextLabel")
    label.Size               = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text               = "👑 KING HYDRA BLASTER"
    label.TextColor3         = Color3.new(1, 1, 1)
    label.TextScaled         = true
    label.Font               = Enum.Font.GothamBold
    label.Parent             = bg

    -- Обновляем полосу при изменении HP
    humanoid.HealthChanged:Connect(function(hp)
        local pct = math.clamp(hp / humanoid.MaxHealth, 0, 1)
        bar.Size = UDim2.new(pct, 0, 0.6, 0)
        if pct < 0.3 then
            bar.BackgroundColor3 = Color3.fromRGB(220, 40, 40)
        elseif pct < 0.55 then
            bar.BackgroundColor3 = Color3.fromRGB(220, 140, 40)
        else
            bar.BackgroundColor3 = Color3.fromRGB(30, 200, 60)
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
-- AI — машина состояний
-- ─────────────────────────────────────────────────────────────
--[[
  Состояния:
    PATROL  — медленное патрулирование вокруг спавна
    CHASE   — бежит к игроку
    ATTACK  — базовый удар (ближний)
    CHARGE  — рывок: замах → спринт → удар (×1.5 урона)
    STOMP   — удар об землю: пауза → AoE-урон + кольцо (×1.2)

  Фаза 2 (HP < 50%):
    • скорость ×1.4, урон ×1.5, cooldown'ы -30%
    • PointLight красный, уведомление игроку
    • Stomp превращается в двойной удар
]]

local function startAI(boss, humanoid, player, spawnPos)
    local cfg = GameConfig.MiniBoss

    -- Локальные параметры (не трогаем shared cfg)
    local damage    = cfg.Damage
    local runSpeed  = cfg.RunSpeed
    local walkSpeed = cfg.WalkSpeed

    -- AutoRotate уже выставлен в createBossModel

    -- Кулдауны спецатак (секунды)
    local CHARGE_CD     = 9
    local STOMP_CD      = 6
    local CHARGE_DIST_MIN = 14
    local CHARGE_DIST_MAX = 46

    local lastBasicAttack = 0
    local lastCharge      = 0
    local lastStomp       = 0
    local lastFireDamage  = 0

    -- Состояние
    local running        = true   -- флаг остановки AI
    local busySpecial    = false  -- идёт спецатака — не мешаем
    local phase2Done     = false
    local patrolTarget   = randomPatrolPoint(spawnPos, cfg.PatrolRadius)

    -- Огонь: видит игрока в DetectionRange → через FireActivationDelay сек включается Fire
    local fireRoot     = getFireRoot(boss)
    local fireActive   = false
    local playerSightStart = nil -- tick() когда игрок впервые в зоне видимости

    local fireDelay   = cfg.FireActivationDelay or 2.5
    local fireDmg     = cfg.FireDamagePerTick or 12
    local fireInt     = cfg.FireDamageInterval or 0.45
    local fireRadius  = cfg.FireDamageRadius or 16

    local diagInterval = cfg.DebugAILogInterval or 0
    local lastDiagPrint = 0

    humanoid.MoveToFinished:Connect(function(reached)
        if reached then return end
        local br = getRootPart(boss)
        local vel = br and br.AssemblyLinearVelocity.Magnitude or -1
        warn(
            "[MiniBossSpawner][diag] MoveTo не завершился (blocked/stuck). WalkSpeed=",
            humanoid.WalkSpeed,
            "|AssemblyVel=",
            string.format("%.2f", vel)
        )
    end)

    -- Световой индикатор на теле
    local bossRoot = getRootPart(boss)
    local light = Instance.new("PointLight")
    light.Color      = Color3.fromRGB(0, 220, 80)
    light.Brightness = 1.5
    light.Range      = 18
    light.Parent     = bossRoot or boss

    attachHealthBar(boss, humanoid)

    local animTrack = startLoopingBossAnimation(humanoid, boss)

    -- Нотификации
    local Remotes = require(Shared:WaitForChild("Remotes"))

    -- ── ФАЗА 2 ────────────────────────────────────────────────
    local function enterPhase2()
        if phase2Done then return end
        phase2Done  = true
        damage      = damage * 1.5
        runSpeed    = runSpeed * 1.4
        CHARGE_CD   = CHARGE_CD  * 0.7
        STOMP_CD    = STOMP_CD   * 0.7

        light.Color      = Color3.fromRGB(255, 30, 30)
        light.Brightness = 3
        light.Range      = 24

        humanoid.WalkSpeed = runSpeed

        Remotes:GetEvent("UpdateHUD"):FireClient(player, {
            Notification = "💀 Гидра ВЗБЕСИЛАСЬ!",
        })
        print("[MiniBossSpawner] Фаза 2 активирована")
    end

    -- ── УДАР (CHARGE) ─────────────────────────────────────────
    local function doCharge(targetPos)
        busySpecial = true
        local ok, err = pcall(function()
            humanoid.WalkSpeed = 0
            humanoid:MoveTo(bossRoot and bossRoot.Position or spawnPos)

            light.Color      = Color3.fromRGB(255, 140, 0)
            light.Brightness = 5
            task.wait(0.7)

            if not running or humanoid.Health <= 0 then return end

            humanoid.WalkSpeed = runSpeed * 2.8
            light.Color = Color3.fromRGB(255, 40, 0)
            humanoid:MoveTo(targetPos)
            task.wait(1.0)

            if not running or humanoid.Health <= 0 then return end

            local br = getRootPart(boss)
            if br then
                spawnShockwave(br.Position, Color3.fromRGB(255, 100, 0), 10)
                areaDamage(br.Position, 9, damage * 1.5, player.Character)
            end

            task.wait(0.4)
        end)
        if not ok then
            warn("[MiniBossSpawner] doCharge error:", err)
        end
        humanoid.WalkSpeed = runSpeed
        light.Color      = phase2Done and Color3.fromRGB(255, 30, 30) or Color3.fromRGB(0, 220, 80)
        light.Brightness = phase2Done and 3 or 1.5
        busySpecial = false
    end

    -- ── ТОПОТ (STOMP) ─────────────────────────────────────────
    local function doStomp()
        busySpecial = true
        local ok, err = pcall(function()
            humanoid.WalkSpeed = 0
            humanoid:MoveTo(bossRoot and bossRoot.Position or spawnPos)

            light.Color      = Color3.fromRGB(240, 240, 0)
            light.Brightness = 6
            task.wait(0.5)

            if not running or humanoid.Health <= 0 then return end

            local br = getRootPart(boss)
            if br then
                spawnShockwave(br.Position, Color3.fromRGB(180, 220, 50), 14)
                areaDamage(br.Position, 12, damage * 1.2, player.Character)
            end

            if phase2Done then
                task.wait(0.35)
                if not running or humanoid.Health <= 0 then return end
                local br2 = getRootPart(boss)
                if br2 then
                    spawnShockwave(br2.Position, Color3.fromRGB(255, 80, 80), 16)
                    areaDamage(br2.Position, 14, damage * 0.9, player.Character)
                end
            end

            task.wait(0.3)
        end)
        if not ok then
            warn("[MiniBossSpawner] doStomp error:", err)
        end
        humanoid.WalkSpeed = runSpeed
        light.Color      = phase2Done and Color3.fromRGB(255, 30, 30) or Color3.fromRGB(0, 220, 80)
        light.Brightness = phase2Done and 3 or 1.5
        busySpecial = false
    end

    -- ── ГЛАВНЫЙ ЦИКЛ ──────────────────────────────────────────
    task.spawn(function()
        while running and boss and boss.Parent and humanoid.Health > 0 do
            -- Фаза 2?
            if humanoid.Health / humanoid.MaxHealth <= 0.5 then
                enterPhase2()
            end

            -- Спецатака в работе — ждём
            if busySpecial then
                task.wait(0.1)
                continue
            end

            local br   = getRootPart(boss)
            local char = player and player.Character
            local hrp  = getHumanoidRootPart(char)
            local now  = tick()

            if not br then task.wait(0.1) continue end

            -- Обнаружение игрока → таймер → «огненный» урон (визуал Fire — если есть дочерний Fire)
            if hrp then
                local distSight = distanceTo(br.Position, hrp.Position)
                if distSight <= cfg.DetectionRange then
                    if not playerSightStart then
                        playerSightStart = now
                    end
                    if (now - playerSightStart) >= fireDelay then
                        if not fireActive then
                            fireActive = true
                            if fireRoot then
                                setFireVisual(fireRoot, true)
                            end
                            print(
                                "[MiniBossSpawner][diag] Огонь ВКЛ: distSight=",
                                string.format("%.1f", distSight),
                                "<=",
                                cfg.DetectionRange,
                                "| fireDelay",
                                fireDelay,
                                "s"
                            )
                        end
                    end
                else
                    playerSightStart = nil
                    if fireActive then
                        fireActive = false
                        if fireRoot then
                            setFireVisual(fireRoot, false)
                        end
                        print(
                            "[MiniBossSpawner][diag] Огонь ВЫКЛ: игрок вне DetectionRange, distSight=",
                            string.format("%.1f", distSight),
                            ">",
                            cfg.DetectionRange
                        )
                    end
                end
                if fireActive and (now - lastFireDamage) >= fireInt then
                    lastFireDamage = now
                    local anchor = getFireDamageAnchor(fireRoot) or br
                    if anchor and char then
                        areaDamage(anchor.Position, fireRadius, fireDmg, char)
                    end
                end
            else
                playerSightStart = nil
                if fireActive then
                    fireActive = false
                    if fireRoot then
                        setFireVisual(fireRoot, false)
                    end
                    print("[MiniBossSpawner][diag] Огонь ВЫКЛ: нет персонажа игрока (Character/HRP)")
                end
            end

            if hrp then
                local dist = distanceTo(br.Position, hrp.Position)

                if dist <= cfg.AttackRange then
                    -- Стоим и бьём
                    humanoid.WalkSpeed = 0
                    humanoid:MoveTo(br.Position)

                    if now - lastBasicAttack >= cfg.AttackCooldown then
                        lastBasicAttack = now
                        local h = char:FindFirstChildWhichIsA("Humanoid")
                        if h and h.Health > 0 then
                            h:TakeDamage(damage)
                        end
                    end

                    -- Топот когда рядом
                    if now - lastStomp >= STOMP_CD then
                        lastStomp = now
                        task.spawn(doStomp)
                    end

                elseif dist <= cfg.DetectionRange then
                    -- Преследование
                    humanoid.WalkSpeed = runSpeed
                    humanoid:MoveTo(hrp.Position)

                    -- Рывок в диапазоне дистанций
                    if dist >= CHARGE_DIST_MIN and dist <= CHARGE_DIST_MAX
                        and now - lastCharge >= CHARGE_CD then
                        lastCharge = now
                        local snapTarget = hrp.Position
                        task.spawn(function() doCharge(snapTarget) end)
                    end

                else
                    -- Патруль
                    humanoid.WalkSpeed = walkSpeed
                    if distanceTo(br.Position, patrolTarget) < 3 then
                        patrolTarget = randomPatrolPoint(spawnPos, cfg.PatrolRadius)
                    end
                    humanoid:MoveTo(patrolTarget)
                end

            else
                -- Игрок недоступен — патруль
                humanoid.WalkSpeed = walkSpeed
                if distanceTo(br.Position, patrolTarget) < 3 then
                    patrolTarget = randomPatrolPoint(spawnPos, cfg.PatrolRadius)
                end
                humanoid:MoveTo(patrolTarget)
            end

            if diagInterval > 0 and (now - lastDiagPrint) >= diagInterval then
                lastDiagPrint = now
                local distSightForLog = -1
                local aiMode = "NO_PLAYER"
                if hrp then
                    distSightForLog = distanceTo(br.Position, hrp.Position)
                    if distSightForLog <= cfg.AttackRange then
                        aiMode = "ATTACK"
                    elseif distSightForLog <= cfg.DetectionRange then
                        aiMode = "CHASE"
                    else
                        aiMode = "PATROL_farPlayer"
                    end
                else
                    aiMode = "PATROL_noHRP"
                end
                local fireEta = "n/a"
                if playerSightStart and hrp and distSightForLog >= 0 and distSightForLog <= cfg.DetectionRange then
                    fireEta = string.format("%.1fs", math.max(0, fireDelay - (now - playerSightStart)))
                end
                local vel = br.AssemblyLinearVelocity.Magnitude
                print(string.format(
                    "[MiniBossSpawner][diag] mode=%s | dist=%.1f distSight=%.1f | fire=%s fireEta=%s | WalkSpeed=%s | rootVel=%.2f | busySpecial=%s | HRP=%s",
                    aiMode,
                    hrp and distanceTo(br.Position, hrp.Position) or -1,
                    distSightForLog,
                    tostring(fireActive),
                    fireEta,
                    tostring(humanoid.WalkSpeed),
                    vel,
                    tostring(busySpecial),
                    hrp and "ok" or "nil"
                ))
            end

            task.wait(0.1)
        end

        local exitWhy = "unknown"
        if humanoid.Health <= 0 then
            exitWhy = "humanoid_dead"
        elseif not boss.Parent then
            exitWhy = "model_no_parent"
        elseif not running then
            exitWhy = "ai_disconnect"
        end
        print("[MiniBossSpawner] AI цикл завершён |", player.Name, "| причина:", exitWhy)

        running = false
        if fireRoot and fireActive then
            setFireVisual(fireRoot, false)
        end
        if animTrack then
            pcall(function() animTrack:Stop() end)
        end
    end)

    -- Возвращаем объект совместимый с :Disconnect()
    return {
        Disconnect = function()
            running = false
            if fireRoot then
                setFireVisual(fireRoot, false)
            end
            if animTrack then
                pcall(function() animTrack:Stop() end)
            end
        end,
    }
end

-- ─────────────────────────────────────────────────────────────
-- Обработка смерти
-- ─────────────────────────────────────────────────────────────

local function onBossDied(player, boss)
    local userId = player.UserId
    print("[MiniBossSpawner] onBossDied → квест + SetStage(TOMB_MAZE) |", player.Name)

    -- Остановить AI
    local data = activeBosses[userId]
    if data and data.connection then
        data.connection:Disconnect()
    end
    activeBosses[userId] = nil

    -- Убрать модель через секунду (дать время упасть)
    task.delay(1, function()
        if boss and boss.Parent then
            boss:Destroy()
        end
    end)

    -- Засчитать квест
    if _G.QuestManager then
        _G.QuestManager:UpdateProgress(player, "KILL", "MiniBoss", 1)
    end

    -- Переключить стадию
    if _G.GameManager then
        _G.GameManager.SetStage(player, "TOMB_MAZE")
    end
end

-- ─────────────────────────────────────────────────────────────
-- Публичный API
-- ─────────────────────────────────────────────────────────────

function MiniBossSpawner:Spawn(player)
    local userId = player.UserId

    print("[MiniBossSpawner] Запрос спавна гидры для игрока:", player.Name)

    -- Не дублировать
    if activeBosses[userId] then
        print("[MiniBossSpawner] Уже активен — очищаем старого босса")
        self:Clear(player, "duplicate_spawn")
    end

    local spawnPos = GameConfig.Zones.MiniBossArena.SpawnPoint
    print("[MiniBossSpawner] Позиция спавна:", spawnPos)

    local boss, humanoid = createBossModel(spawnPos)

    if boss then
        print("[MiniBossSpawner] Модель создана:", boss.Name, "| Health:", humanoid.Health, "/", humanoid.MaxHealth)
    else
        warn("[MiniBossSpawner] Не удалось создать модель босса!")
        return
    end

    -- Запустить квест
    if _G.QuestManager then
        _G.QuestManager:StartQuest(player, "DEFEAT_MINI_BOSS")
        print("[MiniBossSpawner] Квест DEFEAT_MINI_BOSS запущен")
    else
        warn("[MiniBossSpawner] _G.QuestManager недоступен — квест не запущен")
    end

    -- Запустить AI
    local aiConnection = startAI(boss, humanoid, player, spawnPos)
    print("[MiniBossSpawner] AI запущен")

    activeBosses[userId] = {
        model      = boss,
        connection = aiConnection,
    }

    local lastHp = humanoid.Health
    local cfgMb = GameConfig.MiniBoss
    humanoid.HealthChanged:Connect(function(newHp)
        local delta = newHp - lastHp
        if cfgMb.DebugMiniBossVerbose and delta < 0 then
            print(
                "[MiniBossSpawner][HP]",
                player.Name,
                string.format("%.0f→%.0f", lastHp, newHp),
                "Δ=" .. string.format("%.1f", delta)
            )
        end
        if newHp < lastHp and (lastHp - newHp) >= 50 then
            warn(
                "[MiniBossSpawner] Резкое снижение HP гидры:",
                lastHp,
                "→",
                newHp,
                "(падение, среда или урон)"
            )
        end
        lastHp = newHp
    end)

    boss.AncestryChanged:Connect(function()
        if boss.Parent == nil and humanoid.Health > 0 then
            warn(
                "[MiniBossSpawner] Модель гидры снята с дерева при HP>0 (",
                humanoid.Health,
                ") — ожидайте Died или внешнее Destroy |",
                player.Name
            )
        end
    end)

    -- Подписаться на смерть
    humanoid.Died:Connect(function()
        print(
            "[MiniBossSpawner] Гидра мертва | HP до смерти лог выше | игрок:",
            player.Name,
            "| Parent модели:",
            boss.Parent and boss.Parent:GetFullName() or "nil"
        )
        onBossDied(player, boss)
    end)

    print("[MiniBossSpawner] King Hydra Blaster успешно заспавнен для", player.Name)

    task.defer(function()
        local r = boss and boss.Parent and boss:FindFirstChild("HumanoidRootPart")
        if r and r:IsA("BasePart") then
            print("[MiniBossSpawner][diag] Позиция HRP после 1 кадра:", r.Position, "| Health:", humanoid.Health)
        end
    end)

    local Remotes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Remotes"))
    Remotes:GetEvent("UpdateHUD"):FireClient(player, {
        Notification = "⚠ Гидра у ворот! Подойди к ветряку снизу и толкни его на неё!",
    })
end

function MiniBossSpawner:GetActiveBoss(player)
    local data = activeBosses[player.UserId]
    return data and data.model or nil
end

function MiniBossSpawner:KillByTurbine(player)
    local data = activeBosses[player.UserId]
    if not data or not data.model then
        return false
    end

    local boss = data.model
    local humanoid = boss:FindFirstChildWhichIsA("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    print("[MiniBossSpawner] Гидра убита ветряком |", player.Name)
    humanoid.Health = 0
    return true
end

function MiniBossSpawner:Clear(player, reason)
    reason = reason or "unknown"
    local userId = player.UserId
    local data   = activeBosses[userId]
    if not data then
        if GameConfig.MiniBoss.DebugMiniBossVerbose then
            print("[MiniBossSpawner] Clear пропущен (нет активного босса) |", player.Name, "|", reason)
        end
        return
    end

    print("[MiniBossSpawner] Clear |", player.Name, "| причина:", reason)

    if data.connection then
        data.connection:Disconnect()
    end
    if data.model and data.model.Parent then
        data.model:Destroy()
    end

    activeBosses[userId] = nil
end

-- ─────────────────────────────────────────────────────────────
-- Авто-очистка при выходе игрока
-- ─────────────────────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player)
    MiniBossSpawner:Clear(player, "Players.PlayerRemoving")
end)

-- Регистрация в глобальном пространстве
_G.MiniBossSpawner = MiniBossSpawner

return MiniBossSpawner
