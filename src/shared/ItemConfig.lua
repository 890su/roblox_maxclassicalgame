--[[
    ItemConfig — определения предметов инвентаря
]]

local ItemConfig = {}

ItemConfig.Items = {
    SecretMap = {
        Id = "SecretMap",
        Name = "Карта деда",
        Icon = "🗺",
        Description = "Секретная карта с маршрутом к гробнице",
        Usable = true,
        UseAction = "ShowMap",
        Unique = true,
    },
    WolfPelt = {
        Id = "WolfPelt",
        Name = "Шкура волка",
        Icon = "🐺",
        Description = "Добыча с волка",
        Usable = false,
        Unique = false,
    },
    WolfTeeth = {
        Id = "WolfTeeth",
        Name = "Зубы волка",
        Icon = "🦷",
        Description = "Добыча с волка",
        Usable = false,
        Unique = false,
    },
}

function ItemConfig.Get(itemId)
    return ItemConfig.Items[itemId]
end

return ItemConfig
