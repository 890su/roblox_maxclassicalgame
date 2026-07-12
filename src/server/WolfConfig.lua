--[[
    WolfConfig — фасад (данные этапа WOLF_HUNT в StageWorldConfig)
]]

local ServerScriptService = game:GetService("ServerScriptService")
local StageWorldConfig = require(ServerScriptService:WaitForChild("StageWorldConfig"))

local WolfConfig = StageWorldConfig.GetWolfConfig()

return WolfConfig
