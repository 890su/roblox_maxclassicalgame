--[[
    QuestConfig — Data-driven описание всех квестов (ТОЛЬКО СЕРВЕР)
    Клиент видит только активный квест через Remotes QuestStarted/Updated/Completed.

    Поля квеста: Id, Title, Description, GiverNPC, Objectives, Rewards,
    NextQuest, RequiredStage, TriggersCutscene, CompanionNPC, ActivateNPC.
]]

local QuestConfig = {}

-- ═══════════════════════════════════════════════════════════
-- ОПРЕДЕЛЕНИЯ КВЕСТОВ
-- ═══════════════════════════════════════════════════════════
QuestConfig.Quests = {

    -- ═══════════════════════════════════════
    -- КВЕСТ 1: Убить волков
    -- Выдаётся Старейшиной при первом разговоре.
    -- Игрок должен убить 8 волков в зоне Outskirts.
    -- После завершения → переход к RETURN_TO_VILLAGE.
    -- ═══════════════════════════════════════
    KILL_WOLVES = {
        Id = "KILL_WOLVES",
        Title = "Избавиться от волков",
        Description = "Старейшина просит убить всех волков в округе",
        GiverNPC = "Elder",                        -- кто выдал квест
        Objectives = {
            {
                Type = "KILL",                     -- тип цели: убить
                Target = "Wolf",                   -- кого убить
                Count = 8,                         -- сколько штук
                Description = "Убить волков: %d/%d", -- формат отображения (current/total)
            },
        },
        Rewards = {
            Money = 50,                            -- монеты за выполнение
            Items = { "WolfTeeth", "WolfPelt" },   -- предметы-награды
        },
        NextQuest = "RETURN_TO_VILLAGE",            -- следующий квест в цепочке
        RequiredStage = "WOLF_HUNT",                -- квест активен на стадии WOLF_HUNT
    },

    -- ═══════════════════════════════════════
    -- КВЕСТ 2: Вернуться в деревню
    -- После убийства волков — игрок должен вернуться к Старейшине.
    -- При входе в деревню: благодарность Старейшины → кат-сцена WOLF_AMBUSH.
    -- JOHN DOU активируется как NPC.
    -- ═══════════════════════════════════════
    RETURN_TO_VILLAGE = {
        Id = "RETURN_TO_VILLAGE",
        Title = "Вернуться в деревню",
        Description = "Вернуться к Старейшине с добычей",
        GiverNPC = "Elder",
        Objectives = {
            {
                Type = "REACH_ZONE",               -- тип: дойти до зоны
                Target = "Village",                -- целевая зона
                Description = "Вернуться в деревню",
            },
        },
        Rewards = {
            Money = 0,                             -- без денежной награды
        },
        NextQuest = "FIND_MAP",
        RequiredStage = "JOHN_RESCUE",
        TriggersCutscene = "WOLF_AMBUSH",          -- кат-сцена при завершении
        ActivateNPC = "DouDzouh",                  -- активировать NPC JOHN DOU
    },

    -- ═══════════════════════════════════════
    -- КВЕСТ 3: Найти карту
    -- После потери деда — игрок ищет его дом и находит секретное письмо.
    -- Два шага: войти в дом → изучить письмо.
    -- ═══════════════════════════════════════
    FIND_MAP = {
        Id = "FIND_MAP",
        Title = "Тайна деда",
        Description = "Изучить письмо деда и найти секретную карту",
        GiverNPC = "Elder",
        Objectives = {
            {
                Type = "INTERACT",                 -- тип: взаимодействовать
                Target = "GrandfatherHouse",       -- с чем
                Description = "Войти в дом деда",
            },
            {
                Type = "INTERACT",
                Target = "SecretLetter",
                Description = "Изучить письмо",
            },
        },
        Rewards = {
            Items = { "SecretMap" },                -- получаем карту сокровищ
        },
        NextQuest = "TRAVERSE_FOREST",
        RequiredStage = "SECRET_MAP",
    },

    -- ═══════════════════════════════════════
    -- КВЕСТ 4: Пройти через лес
    -- Игрок идёт через тёмный лес вместе с JOHN DOU.
    -- JOHN DOU следует за игроком как компаньон.
    -- ═══════════════════════════════════════
    TRAVERSE_FOREST = {
        Id = "TRAVERSE_FOREST",
        Title = "Через тёмный лес",
        Description = "Пройти лес с JOHN DOU до болота",
        GiverNPC = "DouDzouh",
        Objectives = {
            {
                Type = "REACH_ZONE",
                Target = "Forest",
                Description = "Войти в лес",
            },
            {
                Type = "REACH_ZONE",
                Target = "Swamp",
                Description = "Дойти до болота",
            },
        },
        Rewards = {
            Money = 30,
        },
        NextQuest = "CROSS_SWAMP",
        RequiredStage = "FOREST_JOURNEY",
        CompanionNPC = "DouDzouh",
    },

    -- ═══════════════════════════════════════
    -- КВЕСТ 4b: Перейти болото
    -- Ядовитый туман — без JOHN DOU не пройти.
    -- Следовать за ним по кочкам к руинам гидры.
    -- ═══════════════════════════════════════
    CROSS_SWAMP = {
        Id = "CROSS_SWAMP",
        Title = "Ядовитое болото",
        Description = "Следуй за JOHN DOU по кочкам — туман убьёт одного",
        GiverNPC = "DouDzouh",
        Objectives = {
            {
                Type = "REACH_ZONE",
                Target = "HydraRuins",
                Description = "Дойти до руин гидры",
            },
            {
                Type = "SURVIVE",
                Description = "Не провалиться в болото",
            },
        },
        Rewards = {
            Money = 40,
        },
        NextQuest = "DEFEAT_MINI_BOSS",
        RequiredStage = "SWAMP_JOURNEY",
        CompanionNPC = "DouDzouh",
    },

    -- ═══════════════════════════════════════
    -- КВЕСТ 5: Победить мини-босса
    -- King Hydra Blaster стережёт ворота гробницы.
    -- Автозапуск при достижении MiniBossArena.
    -- ═══════════════════════════════════════
    DEFEAT_MINI_BOSS = {
        Id = "DEFEAT_MINI_BOSS",
        Title = "Страж ворот",
        Description = "Подойди к ветряку снизу и обруши его на King Hydra Blaster",
        GiverNPC = nil,                            -- автозапуск через MiniBossSpawner
        Objectives = {
            {
                Type = "KILL",
                Target = "MiniBoss",               -- засчитывается через MiniBossSpawner
                Count = 1,
                Description = "Толкни ветряк снизу на гидру: %d/%d",
            },
        },
        Rewards = {
            Money = 100,
            Items = { "HydraScale" },              -- чешуя гидры
        },
        NextQuest = "SOLVE_MAZE",
        RequiredStage = "MINI_BOSS",
        CompanionNPC = "DouDzouh",
    },

    -- ═══════════════════════════════════════
    -- КВЕСТ 6: Лабиринт в гробнице
    -- Процедурно-сгенерированный лабиринт.
    -- Игрок с JOHN DOU ищет выход к залу артефакта.
    -- ═══════════════════════════════════════
    SOLVE_MAZE = {
        Id = "SOLVE_MAZE",
        Title = "Древний лабиринт",
        Description = "Пройти лабиринт внутри гробницы",
        Objectives = {
            {
                Type = "REACH_ZONE",
                Target = "ArtifactHall",           -- цель: найти зал артефакта
                Description = "Найти выход из лабиринта",
            },
        },
        Rewards = {
            Money = 50,
        },
        NextQuest = "GET_BAN_HAMMER",
        RequiredStage = "TOMB_MAZE",
        CompanionNPC = "DouDzouh",                 -- JOHN DOU всё ещё с нами
    },

    -- ═══════════════════════════════════════
    -- КВЕСТ 6: Получить Ban Hammer
    -- Финальный квест — забрать артефакт с пьедестала.
    -- После этого запускается кат-сцена с JOHN DOU,
    -- которая ведёт к одной из трёх концовок.
    -- ═══════════════════════════════════════
    GET_BAN_HAMMER = {
        Id = "GET_BAN_HAMMER",
        Title = "Ban Hammer",
        Description = "Забрать древний артефакт",
        Objectives = {
            {
                Type = "INTERACT",
                Target = "BanHammerPedestal",      -- пьедестал с артефактом
                Description = "Взять Ban Hammer",
            },
        },
        Rewards = {
            Items = { "BanHammer" },               -- артефакт в инвентарь
        },
        NextQuest = "FINALE",                      -- после этого — финал
        RequiredStage = "BAN_HAMMER",
        TriggersCutscene = "DOU_DZOUH_REQUEST",    -- JOHN DOU просит молот
    },
}

-- ═══════════════════════════════════════════════════════════
-- ПОРЯДОК КВЕСТОВ
-- Массив ID в порядке прохождения.
-- Используется для итерации и определения прогресса.
-- ═══════════════════════════════════════════════════════════
QuestConfig.QuestOrder = {
    "KILL_WOLVES",         -- 1. Убить волков
    "RETURN_TO_VILLAGE",   -- 2. Вернуться к Старейшине
    "FIND_MAP",            -- 3. Найти карту
    "TRAVERSE_FOREST",     -- 4. Пройти через лес
    "CROSS_SWAMP",         -- 5. Перейти болото с JOHN DOU
    "DEFEAT_MINI_BOSS",    -- 6. Победить King Hydra Blaster
    "SOLVE_MAZE",          -- 7. Пройти лабиринт
    "GET_BAN_HAMMER",      -- 8. Забрать артефакт
}

return QuestConfig
