--[[
    QuestManager — Data-driven квестовый движок
    ═══════════════════════════════════════════════════════════
    
    Этот модуль УПРАВЛЯЕТ квестами, а НЕ ХРАНИТ их определения.
    Определения квестов лежат в QuestConfig.lua.
    
    КАК ЭТО РАБОТАЕТ:
    ─────────────────
    1. GameManager вызывает QuestManager:StartQuest(player, "KILL_WOLVES")
    2. QuestManager создаёт запись с прогрессом и оповещает клиент
    3. Другие системы (WolfSpawner) вызывают UpdateProgress("KILL", "Wolf", 1)
    4. Когда все цели выполнены — CompleteQuest() выдаёт награды
    5. Уведомляет GameManager (через _G) → смена стадии
    6. Автоматически запускает следующий квест (NextQuest)
    
    ЦЕПОЧКА ВЫЗОВОВ:
    ────────────────
    WolfSpawner: волк убит
      → QuestManager:UpdateProgress(player, "KILL", "Wolf", 1)
        → QuestManager:CompleteQuest(player)
          → _G.GameManager.OnQuestCompleted(player, "KILL_WOLVES")
            → GameManager: setStage(player, "JOHN_RESCUE")
    
    ПРИМЕЧАНИЕ: _G (глобальная таблица) используется для связи
    QuestManager → GameManager, чтобы избежать циклических зависимостей.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuestConfig = require(ServerScriptService:WaitForChild("QuestConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local DataManager = require(ServerScriptService:WaitForChild("DataManager"))

local QuestManager = {}

-- ═══════════════════════════════════════════════════════════
-- ХРАНИЛИЩЕ АКТИВНЫХ КВЕСТОВ
-- Для каждого игрока хранится: ID квеста, определение, прогресс по целям.
-- Формат: activeQuests[Player] = { QuestId, Definition, Progress[], StartTime }
-- ═══════════════════════════════════════════════════════════
local activeQuests = {} -- [Player] = { questId, progress }

-- ═══════════════════════════════════════════════════════════
-- НАЧАТЬ КВЕСТ
-- Создаёт новую запись с прогрессом и оповещает клиент.
--
-- Параметры:
--   player (Player) — игрок
--   questId (string) — ID квеста из QuestConfig.Quests
-- ═══════════════════════════════════════════════════════════
function QuestManager:StartQuest(player, questId)
    -- Берём определение квеста из конфига
    local questDef = QuestConfig.Quests[questId]
    if not questDef then
        warn("[QuestManager] Квест не найден:", questId)
        return
    end

    -- Инициализируем прогресс: для каждой цели создаём счётчик
    -- Пример: цель "KILL Wolf 8" → { Current = 0, Required = 8, Completed = false }
    local progress = {}
    for i, objective in ipairs(questDef.Objectives) do
        progress[i] = {
            Type = objective.Type,         -- тип цели (KILL, REACH_ZONE, INTERACT...)
            Target = objective.Target,     -- цель (Wolf, Village, SecretLetter...)
            Required = objective.Count or 1, -- сколько нужно (по умолчанию 1)
            Current = 0,                   -- текущий прогресс
            Completed = false,             -- выполнена ли цель
        }
    end

    -- Сохраняем активный квест для этого игрока
    activeQuests[player] = {
        QuestId = questId,
        Definition = questDef,
        Progress = progress,
        StartTime = tick(),  -- время начала (для статистики)
    }

    -- Оповещаем клиент: показать UI нового квеста
    Remotes:GetEvent("QuestStarted"):FireClient(player, {
        QuestId = questId,
        Title = questDef.Title,
        Description = questDef.Description,
        Objectives = questDef.Objectives,
    })

    print("[QuestManager] Квест начат:", questDef.Title, "для", player.Name)
end

-- ═══════════════════════════════════════════════════════════
-- ОБНОВИТЬ ПРОГРЕСС КВЕСТА
-- Вызывается ВНЕШНИМИ системами при игровых событиях.
-- Находит подходящую цель и увеличивает счётчик.
-- Если все цели выполнены — автоматически завершает квест.
--
-- Параметры:
--   player (Player)        — игрок
--   objectiveType (string) — тип действия ("KILL", "REACH_ZONE", "INTERACT")
--   target (string)        — что/кого ("Wolf", "Village", "SecretLetter")
--   amount (number?)       — количество (по умолчанию 1)
--
-- Пример вызова из WolfSpawner:
--   QuestManager:UpdateProgress(player, "KILL", "Wolf", 1)
-- ═══════════════════════════════════════════════════════════
function QuestManager:UpdateProgress(player, objectiveType, target, amount)
    local quest = activeQuests[player]
    if not quest then return end  -- нет активного квеста — игнорируем

    amount = amount or 1

    -- Ищем подходящую цель среди целей текущего квеста
    for i, obj in ipairs(quest.Progress) do
        -- Совпадает тип, совпадает цель (или цель = nil, т.е. любая), и ещё не выполнена
        if obj.Type == objectiveType and (obj.Target == target or obj.Target == nil) and not obj.Completed then
            -- Увеличиваем прогресс (но не больше Required)
            obj.Current = math.min(obj.Current + amount, obj.Required)

            -- Проверяем: достигнута ли цель?
            if obj.Current >= obj.Required then
                obj.Completed = true
            end

            -- Оповещаем клиент: обновить UI прогресса
            Remotes:GetEvent("QuestUpdated"):FireClient(player, {
                QuestId = quest.QuestId,
                ObjectiveIndex = i,
                Current = obj.Current,
                Required = obj.Required,
                Completed = obj.Completed,
            })

            break -- обновляем только первую подходящую цель
        end
    end

    -- Проверяем: все ли цели квеста выполнены?
    local allCompleted = true
    for _, obj in ipairs(quest.Progress) do
        if not obj.Completed then
            allCompleted = false
            break
        end
    end

    -- Если все цели выполнены — завершаем квест
    if allCompleted then
        self:CompleteQuest(player)
    end
end

-- ═══════════════════════════════════════════════════════════
-- ЗАВЕРШИТЬ КВЕСТ
-- Выдаёт награды, оповещает клиент, уведомляет GameManager,
-- и автоматически запускает следующий квест в цепочке.
-- ═══════════════════════════════════════════════════════════
function QuestManager:CompleteQuest(player)
    local quest = activeQuests[player]
    if not quest then return end

    local questDef = quest.Definition
    print("[QuestManager] Квест завершён:", questDef.Title)

    -- Выдаём награды
    if questDef.Rewards then
        -- Денежная награда
        if questDef.Rewards.Money and questDef.Rewards.Money > 0 then
            local data = DataManager:GetData(player)
            if data then
                local newMoney = (data.Money or 0) + questDef.Rewards.Money
                DataManager:UpdateField(player, "Money", newMoney)
                Remotes:GetEvent("UpdateHUD"):FireClient(player, { Money = newMoney })
            end
        end
        if questDef.Rewards.Items then
            for _, itemId in ipairs(questDef.Rewards.Items) do
                DataManager:AddItem(player, itemId)
            end
        end
    end

    -- Оповещаем клиент: показать UI завершения квеста с наградами
    Remotes:GetEvent("QuestCompleted"):FireClient(player, {
        QuestId = quest.QuestId,
        Title = questDef.Title,
        Rewards = questDef.Rewards,
    })

    -- Запускаем кат-сцену, если квест её предусматривает
    if questDef.TriggersCutscene then
        -- TODO: Вызвать CutsceneManager:PlayCutscene()
        print("[QuestManager] Trigger cutscene:", questDef.TriggersCutscene)
    end

    -- Запоминаем ID завершённого квеста перед очисткой
    local completedQuestId = quest.QuestId
    activeQuests[player] = nil  -- очищаем активный квест

    -- Уведомляем GameManager о завершении квеста
    -- Используем _G (глобальную таблицу), потому что GameManager
    -- зависит от QuestManager, а обратная зависимость создала бы цикл.
    if _G.GameManager then
        _G.GameManager.OnQuestCompleted(player, completedQuestId)
    end

    -- Запускаем следующий квест в цепочке (если есть и это не финал)
    -- TRAVERSE_FOREST → CROSS_SWAMP стартует в GameManager при входе в болото
    if questDef.NextQuest and questDef.NextQuest ~= "FINALE" then
        if completedQuestId ~= "TRAVERSE_FOREST" then
            task.wait(2)
            self:StartQuest(player, questDef.NextQuest)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПОЛУЧИТЬ ТЕКУЩИЙ КВЕСТ ИГРОКА
-- Возвращает таблицу { QuestId, Definition, Progress } или nil.
-- Используется другими модулями для проверки наличия квеста.
-- ═══════════════════════════════════════════════════════════
function QuestManager:GetActiveQuest(player)
    return activeQuests[player]
end

return QuestManager
