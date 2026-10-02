--!strict
--[[
	ArenaBots
	When nobody else is queueing, a bot steps into the arena. Its team mirrors yours:
	for each of your creatures it picks a random original of the same rarity tier
	(sometimes mutated), then scales its stats so bots get a bit tougher as your
	trophies grow (Config.ArenaBotStrength). That keeps wins close to a coin flip.
]]

local Config = require(script.Parent.Config)
local CreatureData = require(script.Parent.CreatureData)
local Rarity = require(script.Parent.Rarity)

type FighterSpec = { id: string, mutation: string?, scale: number? }

local ArenaBots = {}

local NAMES = {
	"Bot Bonkers",
	"Robo Ranger",
	"Sir Clanks",
	"Gearbox Gus",
	"Beep Boop",
	"Captain Cogs",
	"Tinny Tim",
	"Byte Buddy",
	"Rusty Rex",
	"Widget Wendy",
}

local MUTATIONS = { "Golden", "Electric", "Frozen", "Rainbow" }

-- How strong bots are for a player with `trophies` (before the random jitter).
function ArenaBots.strength(trophies: number): number
	local s = Config.ArenaBotStrength
	return math.clamp(s.min + trophies * s.perTrophy, s.min, s.max)
end

-- A bot team mirroring `team` and a bot name.
function ArenaBots.team(team: { FighterSpec }, trophies: number, rng: Random): ({ FighterSpec }, string)
	local bot: { FighterSpec } = {}
	local s = Config.ArenaBotStrength
	for _, spec in team do
		local def = CreatureData.get(spec.id)
		local rarity = if def then def.rarity else "Common"
		local pool = CreatureData.ofRarity(rarity)
		if #pool == 0 then
			pool = CreatureData.ofRarity(Rarity.Order[1])
		end
		local pick = pool[rng:NextInteger(1, #pool)]
		local mutation = if rng:NextNumber() < 0.15 then MUTATIONS[rng:NextInteger(1, #MUTATIONS)] else nil
		local scale = ArenaBots.strength(trophies) * (1 + (rng:NextNumber() * 2 - 1) * s.jitter)
		-- A hybrid on your side earns the bot a little extra muscle to match its extra tags.
		if def and def.hybrid then
			scale *= 1.1
		end
		table.insert(bot, { id = pick.id, mutation = mutation, scale = scale })
	end
	return bot, NAMES[rng:NextInteger(1, #NAMES)]
end

return table.freeze(ArenaBots)
