--[[
    Remotes — Централизованное управление сетевыми событиями
    ═══════════════════════════════════════════════════════════
    
    В Roblox сервер и клиент НЕ МОГУТ вызывать функции друг друга напрямую.
    Для общения между ними используются объекты RemoteEvent и RemoteFunction,
    которые лежат в ReplicatedStorage (доступно обоим).
    
    Этот модуль — «единый реестр» всех сетевых событий в игре.
    
    КАК ЭТО РАБОТАЕТ:
    ─────────────────
    1. СЕРВЕР вызывает Remotes:Init() → создаёт ВСЕ RemoteEvent в папке GameRemotes
    2. КЛИЕНТ вызывает Remotes:GetEvent("имя") → ждёт (WaitForChild) пока сервер создаст
    3. Оба используют одни и те же объекты для общения
    
    ПОЧЕМУ ТАК:
    ───────────
    • Все события описаны в одном месте (легко найти и добавить новые)
    • Клиент НИКОГДА не создаёт Remote-объекты (защита от читеров)
    • Сервер гарантированно создаёт их первым (Init вызывается в GameManager)
    
    НАПРАВЛЕНИЯ СОБЫТИЙ:
    ────────────────────
    • FireServer()  — клиент → сервер (например, «диалог завершён»)
    • FireClient()  — сервер → клиент (например, «показать уведомление»)
    • OnServerEvent — сервер слушает клиента
    • OnClientEvent — клиент слушает сервер
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

-- Определяем: мы на сервере или на клиенте?
-- RunService:IsServer() возвращает true только на сервере.
local isServer = RunService:IsServer()

-- ═══════════════════════════════════════════════════════════
-- РЕЕСТР ВСЕХ REMOTE-СОБЫТИЙ
-- Каждая строка — имя RemoteEvent, который будет создан в папке GameRemotes.
-- Добавляя новое событие, достаточно дописать его сюда,
-- и оно автоматически создастся при запуске сервера.
-- ═══════════════════════════════════════════════════════════
local REMOTE_EVENTS = {
    -- Кат-сцены (сервер → клиент)
    "StartCutscene",       -- отправляет данные камеры и длительность клиенту
    "CutsceneFinished",    -- сообщает клиенту, что кат-сцена окончена

    -- Диалоги
    "ShowDialogue",        -- сервер → клиент: показать окно диалога с текстом
    "DialogueChoice",      -- клиент → сервер: игрок ответил / диалог завершён
    "HideDialogue",        -- сервер → клиент: принудительно закрыть диалог

    -- Квесты (сервер → клиент)
    "QuestStarted",        -- новый квест начат (показать UI)
    "QuestUpdated",        -- прогресс квеста обновлён (обновить счётчик)
    "QuestCompleted",      -- квест завершён (показать награду)

    -- HUD и интерфейс (сервер → клиент)
    "UpdateHUD",           -- обновить HUD (уведомления, прогресс)
    "ShowMap",             -- показать найденную карту сокровищ
    "InventoryUpdated",    -- синхронизация инвентаря (сервер → клиент)
    "UseInventoryItem",    -- использовать предмет (клиент → сервер)
    "ShowCredits",         -- показать финальные титры

    -- Игровой процесс (сервер → клиент)
    "WolfKilled",          -- волк убит (показать лут)
    "StageChanged",        -- стадия игры изменилась
    "PlayerDied",          -- игрок погиб

    -- Код для 3-й концовки (клиент → сервер)
    "SubmitSecretCode",    -- игрок ввёл секретный код

    -- Дебаг-инструменты (клиент → сервер, action — строка) — УДАЛИТЬ ПЕРЕД РЕЛИЗОМ!
    "DebugTools",            -- см. DebugTools.client.lua (T/Y/U/G/L/K)
}

-- ═══════════════════════════════════════════════════════════
-- РЕЕСТР REMOTE-ФУНКЦИЙ
-- RemoteFunction отличается от RemoteEvent тем, что ВОЗВРАЩАЕТ ответ.
-- Клиент вызывает → ждёт ответа от сервера → получает данные.
-- ═══════════════════════════════════════════════════════════
local REMOTE_FUNCTIONS = {
    "GetPlayerData",       -- клиент запрашивает данные игрока у сервера
    "GetCurrentGameStage", -- текущая стадия сюжета (для HUD при поздней загрузке клиента)
}

-- Кэш папки для Remote-объектов (создаётся один раз)
local remotesFolder = nil

-- ═══════════════════════════════════════════════════════════
-- ПОЛУЧЕНИЕ ПАПКИ GameRemotes
-- На сервере: создаёт папку, если её нет.
-- На клиенте: ЖДЁТ появления папки (WaitForChild с таймаутом 10 сек).
-- ═══════════════════════════════════════════════════════════
local function getFolder()
    -- Если папка уже найдена — возвращаем из кэша
    if remotesFolder then return remotesFolder end

    if isServer then
        -- Сервер: создаём папку GameRemotes в ReplicatedStorage
        remotesFolder = ReplicatedStorage:FindFirstChild("GameRemotes")
        if not remotesFolder then
            remotesFolder = Instance.new("Folder")
            remotesFolder.Name = "GameRemotes"
            remotesFolder.Parent = ReplicatedStorage
        end
    else
        -- Клиент: ЖДЁМ папку от сервера (максимум 10 секунд)
        remotesFolder = ReplicatedStorage:WaitForChild("GameRemotes", 10)
        if not remotesFolder then
            warn("[Remotes] Папка GameRemotes не найдена! Сервер не инициализирован?")
        end
    end

    return remotesFolder
end

-- ═══════════════════════════════════════════════════════════
-- ПОЛУЧЕНИЕ RemoteEvent ПО ИМЕНИ
-- На сервере: создаёт RemoteEvent если его нет (lazy creation).
-- На клиенте: ждёт RemoteEvent от сервера (WaitForChild, 10 сек).
--
-- Использование:
--   Сервер: Remotes:GetEvent("WolfKilled"):FireClient(player, lootData)
--   Клиент: Remotes:GetEvent("WolfKilled").OnClientEvent:Connect(handler)
-- ═══════════════════════════════════════════════════════════
function Remotes:GetEvent(name)
    local folder = getFolder()
    if not folder then
        warn("[Remotes] Нет папки, не могу получить:", name)
        return nil
    end

    if isServer then
        -- Сервер: ищем существующий или создаём новый
        local remote = folder:FindFirstChild(name)
        if not remote then
            remote = Instance.new("RemoteEvent")
            remote.Name = name
            remote.Parent = folder
        end
        return remote
    else
        -- Клиент: НЕ создаём — только ждём от сервера
        local remote = folder:WaitForChild(name, 10)
        if not remote then
            warn("[Remotes] RemoteEvent не найден на клиенте:", name)
        end
        return remote
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПОЛУЧЕНИЕ RemoteFunction ПО ИМЕНИ
-- Работает аналогично GetEvent, но для вызовов с возвратом данных.
--
-- Использование:
--   Сервер: Remotes:GetFunction("GetPlayerData").OnServerInvoke = function(player) return data end
--   Клиент: local data = Remotes:GetFunction("GetPlayerData"):InvokeServer()
-- ═══════════════════════════════════════════════════════════
function Remotes:GetFunction(name)
    local folder = getFolder()
    if not folder then return nil end

    if isServer then
        local remote = folder:FindFirstChild(name)
        if not remote then
            remote = Instance.new("RemoteFunction")
            remote.Name = name
            remote.Parent = folder
        end
        return remote
    else
        local remote = folder:WaitForChild(name, 10)
        if not remote then
            warn("[Remotes] RemoteFunction не найден на клиенте:", name)
        end
        return remote
    end
end

-- ═══════════════════════════════════════════════════════════
-- ИНИЦИАЛИЗАЦИЯ (вызывается ТОЛЬКО на сервере из GameManager)
-- Создаёт все RemoteEvent и RemoteFunction заранее,
-- чтобы клиенты могли найти их через WaitForChild.
-- ═══════════════════════════════════════════════════════════
function Remotes:Init()
    if not isServer then
        warn("[Remotes] Init() вызван на клиенте — пропускаем")
        return
    end

    print("[Remotes] Инициализация Remote-событий...")

    -- Создаём все RemoteEvent из реестра
    for _, eventName in ipairs(REMOTE_EVENTS) do
        self:GetEvent(eventName)
    end

    -- Создаём все RemoteFunction из реестра
    for _, funcName in ipairs(REMOTE_FUNCTIONS) do
        self:GetFunction(funcName)
    end

    print("[Remotes] Создано событий:", #REMOTE_EVENTS, "функций:", #REMOTE_FUNCTIONS)
end

return Remotes
