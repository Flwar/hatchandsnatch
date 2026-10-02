--!strict
--[[
	GrowthService
	Once a second (on the shared Ticker) checks every placed creature's growth stage,
	computed from its plantedAt timestamp, and swaps its model when it hatches
	(Egg -> Baby) or grows up (Baby -> Adult). Owners get a toast for each.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Economy = require(Shared:WaitForChild("Economy"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local CreatureService = require(script.Parent:WaitForChild("CreatureService"))
local Net = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Net"))
local Ticker = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ticker"))

local GrowthService = {}

local GROWTH_CHECK_SEC = 1

local function onStageChanged(player: Player, record: any, stage: string)
	local def = CreatureData.get(record.id)
	local name = if def then def.displayName else "creature"
	if stage == "Baby" then
		Net.notify(player, `Your {name} hatched!`, "success")
	elseif stage == "Adult" then
		local income = Format.short(Economy.incomePerSec(record.id, record.mutation))
		Net.notify(player, `Your {name} is all grown up! +{income}/s`, "success")
	end
end

function GrowthService.init() end

function GrowthService.start()
	CreatureService.StageChanged:connect(onStageChanged)
	Ticker.every("Growth", GROWTH_CHECK_SEC, function()
		-- Collect ids first: refreshStage replaces models while we iterate.
		local uids = {}
		for uid, entry in CreatureService.all() do
			if entry.stage ~= "Adult" then
				table.insert(uids, uid)
			end
		end
		for _, uid in uids do
			CreatureService.refreshStage(uid)
		end
	end)
end

return GrowthService
