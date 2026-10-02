--!strict
--[[
	Economy
	Price and income formulas shared by server and client, so the UI always shows
	exactly what the server will charge or pay. All inputs come from Config and
	CreatureData; the server never accepts a price from the client.
]]

local Config = require(script.Parent.Config)
local CreatureData = require(script.Parent.CreatureData)

local Economy = {}

-- Price of the next pedestal for a player who currently owns `owned` pedestals.
function Economy.pedestalCost(owned: number): number
	local extra = math.max(0, owned - Config.StartingPedestals)
	return math.floor(Config.PedestalBaseCost * Config.PedestalCostGrowth ^ extra)
end

function Economy.mutationMultiplier(mutation: string?): number
	if mutation == nil then
		return 1
	end
	return (Config.MutationMultipliers :: { [string]: number })[mutation] or 1
end

-- Coins per second an adult creature earns.
function Economy.incomePerSec(creatureId: string, mutation: string?): number
	local def = CreatureData.get(creatureId)
	if not def then
		return 0
	end
	return def.baseIncomePerSec * Economy.mutationMultiplier(mutation)
end

-- Coins refunded when a creature is sold.
function Economy.sellValue(creatureId: string, mutation: string?): number
	local def = CreatureData.get(creatureId)
	if not def then
		return 0
	end
	return math.floor(def.eggPrice * Config.SellRefundFraction * Economy.mutationMultiplier(mutation))
end

-- A creature's worth for base-value comparisons (raid brackets, new-player shield).
function Economy.creatureValue(creatureId: string, mutation: string?): number
	local def = CreatureData.get(creatureId)
	if not def then
		return 0
	end
	return def.eggPrice * Economy.mutationMultiplier(mutation)
end

return table.freeze(Economy)
