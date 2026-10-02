--!strict
--[[
	CreatureData
	Definitions for every creature in the game: 21 originals, three per rarity tier.
	Balance fields (income, grow time, egg price) live here per creature; global
	multipliers and odds live in Config. Models are built by Models/CreatureModels
	using `modelName`.
]]

local Rarity = require(script.Parent.Rarity)

export type CreatureDef = {
	id: string,
	displayName: string,
	rarity: Rarity.RarityName,
	baseIncomePerSec: number,
	growTimeSec: number,
	eggPrice: number,
	modelName: string,
	fusionTags: { string },
	description: string,
}

local CreatureData = {}

local LIST: { CreatureDef } = {
	-- Common ------------------------------------------------------------------
	{
		id = "blobbit",
		displayName = "Blobbit",
		rarity = "Common",
		baseIncomePerSec = 1,
		growTimeSec = 30,
		eggPrice = 25,
		modelName = "Blobbit",
		fusionTags = { "slime", "cute" },
		description = "A wobbly jelly bunny. Leaves a sticky puddle wherever it sits.",
	},
	{
		id = "pebblepup",
		displayName = "Pebblepup",
		rarity = "Common",
		baseIncomePerSec = 1.6,
		growTimeSec = 45,
		eggPrice = 40,
		modelName = "Pebblepup",
		fusionTags = { "rock", "pup" },
		description = "A puppy made of rocks. Loves fetch, hates swimming.",
	},
	{
		id = "sproutle",
		displayName = "Sproutle",
		rarity = "Common",
		baseIncomePerSec = 2.4,
		growTimeSec = 60,
		eggPrice = 60,
		modelName = "Sproutle",
		fusionTags = { "plant", "shell" },
		description = "A tiny turtle growing a sprout. Water it and it grows... slowly.",
	},
	-- Uncommon ----------------------------------------------------------------
	{
		id = "bumblebun",
		displayName = "Bumblebun",
		rarity = "Uncommon",
		baseIncomePerSec = 6,
		growTimeSec = 90,
		eggPrice = 150,
		modelName = "Bumblebun",
		fusionTags = { "bug", "fluffy" },
		description = "Half bee, half bunny, fully fuzzy. Buzzes when happy.",
	},
	{
		id = "waddlecake",
		displayName = "Waddlecake",
		rarity = "Uncommon",
		baseIncomePerSec = 8.5,
		growTimeSec = 110,
		eggPrice = 220,
		modelName = "Waddlecake",
		fusionTags = { "sweet", "bird" },
		description = "A penguin cupcake. Smells like vanilla, waddles like a champion.",
	},
	{
		id = "fizzhopper",
		displayName = "Fizzhopper",
		rarity = "Uncommon",
		baseIncomePerSec = 11,
		growTimeSec = 130,
		eggPrice = 300,
		modelName = "Fizzhopper",
		fusionTags = { "water", "fizzy" },
		description = "A soda frog in a bottle-cap hat. Every hop ends in a burp.",
	},
	-- Rare --------------------------------------------------------------------
	{
		id = "snailmail",
		displayName = "Snailmail",
		rarity = "Rare",
		baseIncomePerSec = 26,
		growTimeSec = 180,
		eggPrice = 800,
		modelName = "Snailmail",
		fusionTags = { "shell", "paper" },
		description = "Delivers letters at 0.01 studs per second. Never late, never early.",
	},
	{
		id = "cactopus",
		displayName = "Cactopus",
		rarity = "Rare",
		baseIncomePerSec = 34,
		growTimeSec = 240,
		eggPrice = 1100,
		modelName = "Cactopus",
		fusionTags = { "plant", "water" },
		description = "An octopus that moved to the desert. Hugs are not recommended.",
	},
	{
		id = "gloomshroom",
		displayName = "Gloomshroom",
		rarity = "Rare",
		baseIncomePerSec = 45,
		growTimeSec = 300,
		eggPrice = 1500,
		modelName = "Gloomshroom",
		fusionTags = { "fungus", "glow" },
		description = "A sleepy mushroom that glows brighter the grumpier it gets.",
	},
	-- Epic --------------------------------------------------------------------
	{
		id = "thunderdumpling",
		displayName = "Thunderdumpling",
		rarity = "Epic",
		baseIncomePerSec = 120,
		growTimeSec = 480,
		eggPrice = 5000,
		modelName = "Thunderdumpling",
		fusionTags = { "food", "storm" },
		description = "A steamed bun with its own personal storm cloud. Always a little zapped.",
	},
	{
		id = "jellyknight",
		displayName = "Jellyknight",
		rarity = "Epic",
		baseIncomePerSec = 160,
		growTimeSec = 600,
		eggPrice = 7000,
		modelName = "Jellyknight",
		fusionTags = { "water", "armor" },
		description = "A brave jellyfish sworn to protect your base. The sword is mostly decorative.",
	},
	{
		id = "discododo",
		displayName = "Disco Dodo",
		rarity = "Epic",
		baseIncomePerSec = 200,
		growTimeSec = 720,
		eggPrice = 9000,
		modelName = "DiscoDodo",
		fusionTags = { "bird", "party" },
		description = "Not extinct, just busy dancing. Platform shoes sold separately.",
	},
	-- Legendary ---------------------------------------------------------------
	{
		id = "volcanowl",
		displayName = "Volcanowl",
		rarity = "Legendary",
		baseIncomePerSec = 650,
		growTimeSec = 1200,
		eggPrice = 30000,
		modelName = "Volcanowl",
		fusionTags = { "fire", "bird" },
		description = "An owl with a volcano for a hat. Hoots, then erupts.",
	},
	{
		id = "croissaur",
		displayName = "Crowned Croissaur",
		rarity = "Legendary",
		baseIncomePerSec = 820,
		growTimeSec = 1500,
		eggPrice = 40000,
		modelName = "Croissaur",
		fusionTags = { "food", "dino" },
		description = "The flaky king of the pastry age. Tiny arms, giant appetite.",
	},
	{
		id = "moonmoth",
		displayName = "Moonmoth",
		rarity = "Legendary",
		baseIncomePerSec = 1000,
		growTimeSec = 1800,
		eggPrice = 50000,
		modelName = "Moonmoth",
		fusionTags = { "bug", "glow" },
		description = "A fluffy moth with moons on its wings. Mistakes every lamp for the moon.",
	},
	-- Mythic ------------------------------------------------------------------
	{
		id = "toastshark",
		displayName = "Toastshark",
		rarity = "Mythic",
		baseIncomePerSec = 4000,
		growTimeSec = 2700,
		eggPrice = 200000,
		modelName = "Toastshark",
		fusionTags = { "food", "water" },
		description = "Swims through the air, crunchy on the outside. Comes pre-buttered.",
	},
	{
		id = "cosmigoose",
		displayName = "Cosmigoose",
		rarity = "Mythic",
		baseIncomePerSec = 5200,
		growTimeSec = 3300,
		eggPrice = 275000,
		modelName = "Cosmigoose",
		fusionTags = { "space", "bird" },
		description = "A goose made of night sky. Honks in every galaxy at once.",
	},
	{
		id = "dragonroll",
		displayName = "Dragonroll",
		rarity = "Mythic",
		baseIncomePerSec = 6500,
		growTimeSec = 3600,
		eggPrice = 350000,
		modelName = "Dragonroll",
		fusionTags = { "food", "dragon" },
		description = "A dragon made of sushi rolls. Breathes wasabi, very spicy.",
	},
	-- Secret ------------------------------------------------------------------
	{
		id = "burritoad",
		displayName = "Burritoad",
		rarity = "Secret",
		baseIncomePerSec = 30000,
		growTimeSec = 5400,
		eggPrice = 1500000,
		modelName = "Burritoad",
		fusionTags = { "food", "slime" },
		description = "A toad that wrapped itself in a burrito and refuses to come out.",
	},
	{
		id = "glitchling",
		displayName = "Glitchling",
		rarity = "Secret",
		baseIncomePerSec = 40000,
		growTimeSec = 6300,
		eggPrice = 2000000,
		modelName = "Glitchling",
		fusionTags = { "glitch", "space" },
		description = "It escaped from a broken video game. Please do not divide it by zero.",
	},
	{
		id = "sofasaurus",
		displayName = "Sofasaurus",
		rarity = "Secret",
		baseIncomePerSec = 50000,
		growTimeSec = 7200,
		eggPrice = 2500000,
		modelName = "Sofasaurus",
		fusionTags = { "dino", "furniture" },
		description = "A comfy prehistoric couch. Extremely relaxed, extremely rare.",
	},
}

local BY_ID: { [string]: CreatureDef } = {}
local BY_RARITY: { [string]: { CreatureDef } } = {}
for _, def in LIST do
	assert(BY_ID[def.id] == nil, `Duplicate creature id {def.id}`)
	assert(Rarity.isValid(def.rarity), `Creature {def.id} has an invalid rarity`)
	table.freeze(def.fusionTags)
	table.freeze(def)
	BY_ID[def.id] = def
	BY_RARITY[def.rarity] = BY_RARITY[def.rarity] or {}
	table.insert(BY_RARITY[def.rarity], def)
end

CreatureData.List = table.freeze(LIST)

function CreatureData.get(id: string): CreatureDef?
	return BY_ID[id]
end

function CreatureData.isValidId(id: any): boolean
	return type(id) == "string" and BY_ID[id] ~= nil
end

-- All creatures of one tier, in list order.
function CreatureData.ofRarity(rarity: string): { CreatureDef }
	return BY_RARITY[rarity] or {}
end

return table.freeze(CreatureData)
