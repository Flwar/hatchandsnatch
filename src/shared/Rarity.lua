--!strict
--[[
	Rarity
	Ordered rarity tiers with their display colors, plus helpers to compare tiers
	and roll a weighted random tier using Config.RarityWeights.
]]

local Config = require(script.Parent.Config)

export type RarityName = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret"

export type RarityInfo = {
	name: RarityName,
	rank: number,
	color: Color3, -- main UI / glow color
	dark: Color3, -- darker shade for outlines and gradients
}

local Rarity = {}

local ORDER: { RarityName } = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
Rarity.Order = table.freeze(ORDER)

local INFO: { [string]: RarityInfo } = {
	Common = { name = "Common", rank = 1, color = Color3.fromRGB(196, 204, 214), dark = Color3.fromRGB(112, 122, 136) },
	Uncommon = {
		name = "Uncommon",
		rank = 2,
		color = Color3.fromRGB(104, 222, 110),
		dark = Color3.fromRGB(38, 140, 62),
	},
	Rare = { name = "Rare", rank = 3, color = Color3.fromRGB(78, 168, 255), dark = Color3.fromRGB(30, 92, 196) },
	Epic = { name = "Epic", rank = 4, color = Color3.fromRGB(184, 104, 255), dark = Color3.fromRGB(108, 46, 186) },
	Legendary = {
		name = "Legendary",
		rank = 5,
		color = Color3.fromRGB(255, 196, 46),
		dark = Color3.fromRGB(196, 120, 16),
	},
	Mythic = { name = "Mythic", rank = 6, color = Color3.fromRGB(255, 82, 126), dark = Color3.fromRGB(176, 24, 70) },
	Secret = { name = "Secret", rank = 7, color = Color3.fromRGB(64, 255, 226), dark = Color3.fromRGB(20, 22, 40) },
}
for _, info in INFO do
	table.freeze(info)
end
table.freeze(INFO)

function Rarity.get(name: string): RarityInfo
	local info = INFO[name]
	assert(info, `Unknown rarity "{name}"`)
	return info
end

function Rarity.isValid(name: any): boolean
	return type(name) == "string" and INFO[name] ~= nil
end

function Rarity.rank(name: string): number
	return Rarity.get(name).rank
end

-- Returns the tier `steps` above `name`, clamped to the highest tier.
function Rarity.step(name: string, steps: number): RarityName
	local index = math.clamp(Rarity.rank(name) + steps, 1, #ORDER)
	return ORDER[index]
end

-- Rolls a rarity using Config.RarityWeights. `rng` lets callers pass a seeded Random.
function Rarity.roll(rng: Random?): RarityName
	local random = rng or Random.new()
	local total = 0
	for _, name in ORDER do
		total += (Config.RarityWeights :: { [string]: number })[name] or 0
	end
	local pick = random:NextNumber() * total
	for _, name in ORDER do
		pick -= (Config.RarityWeights :: { [string]: number })[name] or 0
		if pick <= 0 then
			return name :: RarityName
		end
	end
	return "Common"
end

return table.freeze(Rarity)
