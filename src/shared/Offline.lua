--!strict
--[[
	Offline
	What a player earned while they were away. Growth needs no special handling
	(it is always computed from plantedAt), but income does: each creature only
	earns for the part of the absence after it became an adult, and the whole
	absence is capped at Config.OfflineIncomeCapHours.
]]

local Config = require(script.Parent.Config)
local CreatureData = require(script.Parent.CreatureData)
local Economy = require(script.Parent.Economy)
local Types = require(script.Parent.Types)

local Offline = {}

-- Returns (coins earned, seconds counted). `multiplier` covers income boosts such as passes.
function Offline.earnings(
	creatures: { Types.CreatureRecord },
	lastLogout: number,
	now: number,
	multiplier: number?
): (number, number)
	if lastLogout <= 0 or now <= lastLogout then
		return 0, 0
	end
	local capSec = Config.OfflineIncomeCapHours * 3600
	local windowEnd = math.min(now, lastLogout + capSec)
	local total = 0
	for _, record in creatures do
		local def = CreatureData.get(record.id)
		if def then
			local adultAt = record.plantedAt + def.growTimeSec * Config.AdultAtFraction
			local from = math.max(lastLogout, adultAt)
			if windowEnd > from then
				total += Economy.incomePerSec(record.id, record.mutation) * (windowEnd - from)
			end
		end
	end
	return math.floor(total * (multiplier or 1)), windowEnd - lastLogout
end

return table.freeze(Offline)
