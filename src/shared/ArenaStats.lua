--!strict
--[[
	ArenaStats
	A creature's arena stats, derived only from things it already has:

	  * rarity: every tier above Common multiplies HP and attack by
	    Config.ArenaTierGrowth and adds Config.ArenaSpeedPerTier speed
	  * mutation: Config.ArenaMutationBonus (Golden tankier, Electric faster, ...)
	  * fusion tags: one special ability per tag (Config.ArenaAbilities), so
	    hybrids, with the tags of both parents, bring more tricks

	Shared so the Arena window shows exactly what the server will use.
]]

local Config = require(script.Parent.Config)
local CreatureData = require(script.Parent.CreatureData)
local Rarity = require(script.Parent.Rarity)

export type Ability = {
	tag: string,
	name: string,
	kind: string,
	value: number,
	every: number?,
}

export type Stats = {
	id: string,
	name: string,
	rarity: string,
	mutation: string?,
	hp: number,
	attack: number,
	speed: number,
	abilities: { Ability },
}

local ArenaStats = {}

-- The ability a fusion tag gives, if it has one.
function ArenaStats.ability(tag: string): Ability?
	local spec = (Config.ArenaAbilities :: any)[tag]
	if not spec then
		return nil
	end
	return {
		tag = tag,
		name = spec.name,
		kind = spec.kind,
		value = spec.value,
		every = spec.every,
	}
end

-- Stats for one creature (nil for unknown ids). `scale` multiplies HP and attack (bots).
function ArenaStats.forCreature(id: string, mutation: string?, scale: number?): Stats?
	local def = CreatureData.get(id)
	if not def then
		return nil
	end
	local base = Config.ArenaBaseStats
	local tier = Rarity.rank(def.rarity) - 1
	local growth = Config.ArenaTierGrowth ^ tier
	local bonus = if mutation then (Config.ArenaMutationBonus :: any)[mutation] else nil
	local hpBonus = if bonus then bonus.hp else 1
	local attackBonus = if bonus then bonus.attack else 1
	local speedBonus = if bonus then bonus.speed else 1
	local factor = scale or 1
	local abilities: { Ability } = {}
	for _, tag in def.fusionTags do
		local ability = ArenaStats.ability(tag)
		if ability then
			table.insert(abilities, ability)
		end
	end
	return {
		id = def.id,
		name = if mutation then `{mutation} {def.displayName}` else def.displayName,
		rarity = def.rarity :: string,
		mutation = mutation,
		hp = math.floor(base.hp * growth * hpBonus * factor + 0.5),
		attack = math.floor(base.attack * growth * attackBonus * factor + 0.5),
		speed = math.floor((base.speed + tier * Config.ArenaSpeedPerTier) * speedBonus * 10 + 0.5) / 10,
		abilities = abilities,
	}
end

-- One number to compare teams with (used to sort teams and to sanity-check bots).
function ArenaStats.power(stats: Stats): number
	return stats.hp * stats.attack * (1 + 0.15 * #stats.abilities)
end

-- The arena rank for a trophy count: 0 = unranked, 1 = Bronze ... #Config.ArenaRanks.
function ArenaStats.rank(trophies: number): number
	local rank = 0
	for index, tier in Config.ArenaRanks do
		if trophies >= tier.trophies then
			rank = index
		end
	end
	return rank
end

return table.freeze(ArenaStats)
