--[[
    SwampConfig — фасад (данные этапа SWAMP_JOURNEY в StageWorldConfig)
]]

local ServerScriptService = game:GetService("ServerScriptService")
local StageWorldConfig = require(ServerScriptService:WaitForChild("StageWorldConfig"))

local SwampConfig = StageWorldConfig.GetSwampConfig()

return SwampConfig
