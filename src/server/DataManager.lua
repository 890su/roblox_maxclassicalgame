--[[
    DataManager — Сохранение и загрузка данных игрока
    ═══════════════════════════════════════════════════════════
    
    Использует Roblox DataStoreService для ПЕРСИСТЕНТНОГО хранения
    данных (сохраняются между сессиями, даже после выхода из игры).
    
    КАК ЭТО РАБОТАЕТ:
    ─────────────────
    1. Игрок заходит → LoadPlayerData() грузит данные из DataStore
    2. Данные кэшируются в оперативной памяти (dataCache)
    3. Все изменения идут через кэш (UpdateField)
    4. Каждые 60 секунд — автосохранение в DataStore
    5. Игрок выходит → финальное сохранение, кэш очищается
    
    ВАЖНО:
    ──────
    • pcall() оборачивает обращения к DataStore, потому что он
      может упасть (лимиты, сеть). Без pcall() — ошибка убьёт скрипт.
    • DEFAULT_DATA содержит шаблон для нового игрока. Если мы добавим
      новое поле в шаблон — существующие игроки получат его при мёрдже.
    
    Используется в GameManager для инициализации игрока.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

local DataManager = {}

-- ═══════════════════════════════════════════════════════════
-- ХРАНИЛИЩЕ (DataStore)
-- Имя "ShadowOfHammer_PlayerData_v1" — версия в суффиксе.
-- Если нужно сбросить все данные — смените v1 на v2.
-- ═══════════════════════════════════════════════════════════
local playerDataStore = DataStoreService:GetDataStore("ShadowOfHammer_PlayerData_v1")

-- Кэш данных в оперативной памяти: [Player.UserId] = таблица данных
-- Все чтения идут из кэша (быстро), записи — в кэш + периодически в DataStore
local dataCache = {}

-- ═══════════════════════════════════════════════════════════
-- ШАБЛОН ДАННЫХ НОВОГО ИГРОКА
-- При первом заходе — эти значения копируются.
-- При повторном заходе — поля мёржатся (новые поля добавляются).
-- ═══════════════════════════════════════════════════════════
local DEFAULT_DATA = {
    Money = 0,              -- накопленные монеты
    EndingsCount = 0,       -- сколько раз игрок прошёл игру (0, 1, 2, 3)
    FoundSecrets = {},      -- массив найденных секретов
    HasSecretCode = false,  -- ввёл ли секретный код "SHADOW"
    CurrentQuestId = nil,   -- ID текущего квеста (или nil)
    WolvesKilled = 0,       -- счётчик убитых волков (для статистики)
    Inventory = {},         -- массив предметов в инвентаре
    TotalPlaytime = 0,      -- общее время игры в секундах
}

-- ═══════════════════════════════════════════════════════════
-- ЗАГРУЗКА ДАННЫХ ИГРОКА
-- Вызывается один раз при входе в игру из GameManager.
-- Загружает данные из DataStore, мёржит с шаблоном, кэширует.
-- Создаёт leaderstats (видны на таблице игроков).
--
-- Параметр: player (Player) — объект игрока
-- Возвращает: таблицу с данными игрока
-- ═══════════════════════════════════════════════════════════
function DataManager:LoadPlayerData(player)
    local userId = player.UserId

    -- pcall() защищает от ошибок DataStore (лимиты, сеть и т.д.)
    local success, data = pcall(function()
        return playerDataStore:GetAsync("Player_" .. userId)
    end)

    if success and data then
        print("[DataManager] Данные загружены для", player.Name)

        -- Мёрдж: если в DEFAULT_DATA появилось новое поле,
        -- а в сохранённых данных его нет — добавляем дефолтное значение.
        -- Это позволяет безопасно добавлять новые фичи.
        for key, defaultValue in pairs(DEFAULT_DATA) do
            if data[key] == nil then
                data[key] = defaultValue
            end
        end
    else
        -- Новый игрок — копируем дефолтные данные
        print("[DataManager] Новый игрок:", player.Name)
        data = table.clone(DEFAULT_DATA)
    end

    -- Помещаем в кэш для быстрого доступа
    dataCache[userId] = data

    -- Создаём leaderstats (отображаются в списке игроков)
    self:CreateLeaderstats(player, data)

    return data
end

-- ═══════════════════════════════════════════════════════════
-- СОХРАНЕНИЕ ДАННЫХ ИГРОКА В DataStore
-- Записывает данные из кэша в облачное хранилище.
-- Вызывается: автосохранением (каждые 60 сек), при выходе игрока.
--
-- Параметры:
--   player (Player) — игрок
--   data (table?)   — данные для сохранения (или nil → берёт из кэша)
-- ═══════════════════════════════════════════════════════════
function DataManager:SavePlayerData(player, data)
    local userId = player.UserId
    data = data or dataCache[userId]  -- если data не передали — берём из кэша
    if not data then return end

    local success, err = pcall(function()
        playerDataStore:SetAsync("Player_" .. userId, data)
    end)

    if success then
        print("[DataManager] Данные сохранены для", player.Name)
    else
        warn("[DataManager] Ошибка сохранения для", player.Name, ":", err)
    end
end

-- ═══════════════════════════════════════════════════════════
-- ПОЛУЧЕНИЕ КЭШИРОВАННЫХ ДАННЫХ (без обращения к DataStore)
-- Используется другими модулями для чтения данных игрока.
-- ═══════════════════════════════════════════════════════════
function DataManager:GetData(player)
    return dataCache[player.UserId]
end

-- ═══════════════════════════════════════════════════════════
-- ИНВЕНТАРЬ
-- Inventory = { { ItemId, Count }, ... }
-- ═══════════════════════════════════════════════════════════
local function findInventoryEntry(inventory, itemId)
    for _, entry in ipairs(inventory) do
        if entry.ItemId == itemId then
            return entry
        end
    end
    return nil
end

function DataManager:HasItem(player, itemId)
    local data = dataCache[player.UserId]
    if not data or not data.Inventory then
        return false
    end
    local entry = findInventoryEntry(data.Inventory, itemId)
    return entry ~= nil and (entry.Count or 0) > 0
end

function DataManager:AddItem(player, itemId, count)
    count = count or 1
    local def = ItemConfig.Get(itemId)
    if not def then
        warn("[DataManager] Неизвестный предмет:", itemId)
        return false
    end

    local data = dataCache[player.UserId]
    if not data then
        return false
    end

    if not data.Inventory then
        data.Inventory = {}
    end

    local entry = findInventoryEntry(data.Inventory, itemId)
    if def.Unique then
        if entry then
            return false
        end
        table.insert(data.Inventory, { ItemId = itemId, Count = 1 })
    else
        if entry then
            entry.Count = (entry.Count or 0) + count
        else
            table.insert(data.Inventory, { ItemId = itemId, Count = count })
        end
    end

    print("[DataManager] Предмет добавлен:", itemId, "для", player.Name)
    self:SyncInventory(player)
    return true
end

function DataManager:BuildInventoryPayload(player)
    local data = dataCache[player.UserId]
    local items = {}
    if data and data.Inventory then
        for _, entry in ipairs(data.Inventory) do
            local def = ItemConfig.Get(entry.ItemId)
            if def then
                table.insert(items, {
                    ItemId = entry.ItemId,
                    Name = def.Name,
                    Icon = def.Icon,
                    Description = def.Description,
                    Usable = def.Usable == true,
                    Count = entry.Count or 1,
                })
            end
        end
    end
    return { Items = items }
end

function DataManager:SyncInventory(player)
    Remotes:GetEvent("InventoryUpdated"):FireClient(player, self:BuildInventoryPayload(player))
end

function DataManager:UseItem(player, itemId)
    if not self:HasItem(player, itemId) then
        return false
    end

    local def = ItemConfig.Get(itemId)
    if not def or not def.Usable then
        return false
    end

    if def.UseAction == "ShowMap" then
        Remotes:GetEvent("ShowMap"):FireClient(player)
        return true
    end

    return false
end

-- ═══════════════════════════════════════════════════════════
-- ОБНОВЛЕНИЕ КОНКРЕТНОГО ПОЛЯ
-- Меняет значение в кэше и синхронизирует с leaderstats (если есть).
--
-- Пример: DataManager:UpdateField(player, "Money", 150)
-- ═══════════════════════════════════════════════════════════
function DataManager:UpdateField(player, field, value)
    local data = dataCache[player.UserId]
    if data then
        data[field] = value

        -- Если поле отображается в leaderstats — обновляем и там
        local leaderstats = player:FindFirstChild("leaderstats")
        if leaderstats then
            local stat = leaderstats:FindFirstChild(field)
            if stat then
                stat.Value = value
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- LEADERSTATS
-- Создаёт папку leaderstats в объекте Player.
-- Roblox автоматически показывает эти значения в таблице игроков (Tab).
-- Сюда добавляем то, что хотим показать всем на сервере.
-- ═══════════════════════════════════════════════════════════
function DataManager:CreateLeaderstats(player, data)
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"       -- именно "leaderstats" (регистр важен!)
    leaderstats.Parent = player

    -- Монеты игрока
    local money = Instance.new("IntValue")
    money.Name = "Money"
    money.Value = data.Money or 0
    money.Parent = leaderstats

    -- Количество пройденных концовок
    local endings = Instance.new("IntValue")
    endings.Name = "Endings"
    endings.Value = data.EndingsCount or 0
    endings.Parent = leaderstats
end

-- ═══════════════════════════════════════════════════════════
-- АВТОСОХРАНЕНИЕ
-- Фоновый цикл: каждые 60 секунд сохраняет данные ВСЕХ
-- онлайн-игроков в DataStore. Защита от потери прогресса
-- в случае краша сервера.
-- ═══════════════════════════════════════════════════════════
local AUTOSAVE_INTERVAL = 60 -- секунд между сохранениями

task.spawn(function()
    while true do
        task.wait(AUTOSAVE_INTERVAL)
        for _, player in ipairs(Players:GetPlayers()) do
            local data = dataCache[player.UserId]
            if data then
                DataManager:SavePlayerData(player, data)
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
-- REMOTE FUNCTION: Клиент запрашивает данные
-- Клиент может вызвать: Remotes:GetFunction("GetPlayerData"):InvokeServer()
-- Сервер вернёт таблицу с данными этого игрока.
-- ═══════════════════════════════════════════════════════════
local getPlayerDataRemote = Remotes:GetFunction("GetPlayerData")
getPlayerDataRemote.OnServerInvoke = function(player)
    return dataCache[player.UserId] or DEFAULT_DATA
end

Remotes:GetEvent("UseInventoryItem").OnServerEvent:Connect(function(player, itemId)
    if type(itemId) ~= "string" then
        return
    end
    DataManager:UseItem(player, itemId)
end)

-- ═══════════════════════════════════════════════════════════
-- ОЧИСТКА ПРИ ВЫХОДЕ ИГРОКА
-- Когда игрок покидает сервер — сохраняем его данные
-- в DataStore и очищаем кэш (освобождаем память).
-- ═══════════════════════════════════════════════════════════
Players.PlayerRemoving:Connect(function(player)
    local data = dataCache[player.UserId]
    if data then
        DataManager:SavePlayerData(player, data)
        dataCache[player.UserId] = nil  -- освобождаем память
    end
end)

return DataManager
