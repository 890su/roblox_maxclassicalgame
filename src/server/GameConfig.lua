--[[
    GameConfig — серверный фасад над StageWorldConfig
]]

local ServerScriptService = game:GetService("ServerScriptService")
local StageWorldConfig = require(ServerScriptService:WaitForChild("StageWorldConfig"))

local GameConfig = {}

GameConfig.Zones = StageWorldConfig.GetLegacyGameConfigZones()
GameConfig.Settings = StageWorldConfig.Settings
GameConfig.GameStages = StageWorldConfig.StageOrder

local miniBossStage = StageWorldConfig.Stages.MINI_BOSS
GameConfig.MiniBoss = miniBossStage and miniBossStage.MiniBoss or {}
GameConfig.WindTurbine = miniBossStage and miniBossStage.WindTurbine or {}

return GameConfig
