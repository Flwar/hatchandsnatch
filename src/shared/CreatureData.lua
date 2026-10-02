--!strict
--[[
	CreatureData
	Definitions for every creature in the game: 21 originals, three per rarity tier,
	plus the hybrids made in the Fusion Machine. Balance fields (income, grow time, egg
	price) live here per creature; global multipliers and odds live in Config. Models
	are built by Models/CreatureModels using `modelName`.

	Hybrids:
	  * Named recipes (FusionRecipes) have their own name, model and rarity.
	  * Every other pair of two different originals makes a fallback hybrid with the id
	    "fusion:<lead>+<donor>". The lead is the rarer parent (then the pricier one): it
	    gives the body and the start of the name, the donor its signature piece and the
	    end of the name ("Toast" + "bit" = Toastbit). Rarity is the lead's tier plus one
	    (never into Secret unless a parent is Secret).
	  * Hybrids earn (a + b) x Config.FusionBonus (named: x Config.FusionRecipeBonus) and
	    are worth a + b, so fusing never creates coins out of selling.
	  * Hybrids can't be fused again.
]]

local Config = require(script.Parent.Config)
local FusionRecipes = require(script.Parent.FusionRecipes)
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
	namePrefix: string?, -- originals: how fallback hybrid names start ("Blob" + ...)
	nameSuffix: string?, -- originals: how fallback hybrid names end (... + "pup")
	hybrid: boolean?, -- true for every fused creature
	recipe: boolean?, -- true for named recipes
	parents: { string }?, -- hybrids: the two originals (lead first for fallback hybrids)
}

local CreatureData = {}

local LIST: { CreatureDef } = {
	-- Common ------------------------------------------------------------------
	{
		id = "blobbit",
		displayName = "Blobbit",
		namePrefix = "Blob",
		nameSuffix = "bit",
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
		namePrefix = "Pebble",
		nameSuffix = "pup",
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
		namePrefix = "Sprout",
		nameSuffix = "sprout",
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
		namePrefix = "Bumble",
		nameSuffix = "bun",
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
		namePrefix = "Waddle",
		nameSuffix = "cake",
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
		namePrefix = "Fizz",
		nameSuffix = "hopper",
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
		namePrefix = "Snail",
		nameSuffix = "mail",
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
		namePrefix = "Cacto",
		nameSuffix = "topus",
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
		namePrefix = "Gloom",
		nameSuffix = "shroom",
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
		namePrefix = "Thunder",
		nameSuffix = "dumpling",
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
		namePrefix = "Jelly",
		nameSuffix = "knight",
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
		namePrefix = "Disco",
		nameSuffix = "dodo",
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
		namePrefix = "Volca",
		nameSuffix = "owl",
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
		namePrefix = "Croiss",
		nameSuffix = "saur",
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
		namePrefix = "Moon",
		nameSuffix = "moth",
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
		namePrefix = "Toast",
		nameSuffix = "shark",
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
		namePrefix = "Cosmi",
		nameSuffix = "goose",
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
		namePrefix = "Dragon",
		nameSuffix = "roll",
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
		namePrefix = "Burri",
		nameSuffix = "toad",
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
		namePrefix = "Glitch",
		nameSuffix = "ling",
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
		namePrefix = "Sofa",
		nameSuffix = "saurus",
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
	assert(def.namePrefix and def.nameSuffix, `Creature {def.id} needs fusion name parts`)
	table.freeze(def.fusionTags)
	table.freeze(def)
	BY_ID[def.id] = def
	BY_RARITY[def.rarity] = BY_RARITY[def.rarity] or {}
	table.insert(BY_RARITY[def.rarity], def)
end

-- The original creatures only (what the conveyor sells and the Index lists first).
CreatureData.List = table.freeze(LIST)

---------------------------------------------------------------------------
-- Hybrids
---------------------------------------------------------------------------

local FALLBACK_PREFIX = "fusion:"

local function mergedTags(a: CreatureDef, b: CreatureDef): { string }
	local tags = table.clone(a.fusionTags)
	for _, tag in b.fusionTags do
		if not table.find(tags, tag) then
			table.insert(tags, tag)
		end
	end
	return table.freeze(tags)
end

-- Returns (lead, donor): the rarer parent leads, then the pricier one, then the id.
function CreatureData.leadOf(a: string, b: string): (string, string)
	local defA, defB = BY_ID[a], BY_ID[b]
	assert(defA and defB, "CreatureData.leadOf: both ids must be original creatures")
	local rankA, rankB = Rarity.rank(defA.rarity), Rarity.rank(defB.rarity)
	if rankA ~= rankB then
		return if rankA > rankB then a else b, if rankA > rankB then b else a
	end
	if defA.eggPrice ~= defB.eggPrice then
		return if defA.eggPrice > defB.eggPrice then a else b, if defA.eggPrice > defB.eggPrice then b else a
	end
	return if a < b then a else b, if a < b then b else a
end

local HYBRIDS: { CreatureDef } = {}
local HYBRID_BY_ID: { [string]: CreatureDef } = {}
for _, recipe in FusionRecipes.List do
	local a, b = BY_ID[recipe.parents[1]], BY_ID[recipe.parents[2]]
	assert(a and b, `Recipe {recipe.id} uses an unknown creature`)
	assert(BY_ID[recipe.id] == nil and HYBRID_BY_ID[recipe.id] == nil, `Duplicate creature id {recipe.id}`)
	assert(Rarity.isValid(recipe.rarity), `Recipe {recipe.id} has an invalid rarity`)
	local def: CreatureDef = {
		id = recipe.id,
		displayName = recipe.displayName,
		rarity = recipe.rarity :: Rarity.RarityName,
		baseIncomePerSec = (a.baseIncomePerSec + b.baseIncomePerSec) * Config.FusionRecipeBonus,
		growTimeSec = math.max(a.growTimeSec, b.growTimeSec),
		eggPrice = a.eggPrice + b.eggPrice,
		modelName = recipe.modelName,
		fusionTags = mergedTags(a, b),
		description = recipe.description,
		hybrid = true,
		recipe = true,
		parents = table.freeze({ a.id, b.id }),
	}
	table.freeze(def)
	HYBRID_BY_ID[def.id] = def
	table.insert(HYBRIDS, def)
end

-- The named recipe hybrids, in recipe order.
CreatureData.Hybrids = table.freeze(HYBRIDS)

local fallbackCache: { [string]: CreatureDef } = {}

-- "Croiss" + "shroom" = "Croisshroom": a letter shared by both halves is written once.
local function joinName(prefix: string, suffix: string): string
	if string.lower(string.sub(prefix, -1)) == string.lower(string.sub(suffix, 1, 1)) then
		return prefix .. string.sub(suffix, 2)
	end
	return prefix .. suffix
end

local function fallbackDef(lead: CreatureDef, donor: CreatureDef): CreatureDef
	local id = `{FALLBACK_PREFIX}{lead.id}+{donor.id}`
	local cached = fallbackCache[id]
	if cached then
		return cached
	end
	local rarity: Rarity.RarityName = Rarity.step(lead.rarity, 1)
	if rarity == "Secret" and lead.rarity ~= "Secret" and donor.rarity ~= "Secret" then
		rarity = lead.rarity
	end
	local def: CreatureDef = {
		id = id,
		displayName = joinName(lead.namePrefix :: string, donor.nameSuffix :: string),
		rarity = rarity,
		baseIncomePerSec = (lead.baseIncomePerSec + donor.baseIncomePerSec) * Config.FusionBonus,
		growTimeSec = math.max(lead.growTimeSec, donor.growTimeSec),
		eggPrice = lead.eggPrice + donor.eggPrice,
		modelName = "Hybrid",
		fusionTags = mergedTags(lead, donor),
		description = `Part {lead.displayName}, part {donor.displayName}. Made in a Fusion Machine.`,
		hybrid = true,
		recipe = false,
		parents = table.freeze({ lead.id, donor.id }),
	}
	table.freeze(def)
	fallbackCache[id] = def
	return def
end

-- What fusing two creatures makes: a named recipe id, a fallback hybrid id, or nil when
-- the pair can't be fused (unknown ids, hybrids, or the same creature twice).
function CreatureData.fuse(a: string, b: string): string?
	if a == b or BY_ID[a] == nil or BY_ID[b] == nil then
		return nil
	end
	local recipe = FusionRecipes.find(a, b)
	if recipe then
		return recipe.id
	end
	local lead, donor = CreatureData.leadOf(a, b)
	return `{FALLBACK_PREFIX}{lead}+{donor}`
end

local function resolveFallback(id: string): CreatureDef?
	local lead, donor = string.match(id, "^fusion:(%w+)%+(%w+)$")
	if not lead or not donor then
		return nil
	end
	-- Only the canonical id of a pair without a named recipe is valid.
	if CreatureData.fuse(lead, donor) ~= id then
		return nil
	end
	return fallbackDef(BY_ID[lead], BY_ID[donor])
end

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------

function CreatureData.get(id: string): CreatureDef?
	if type(id) ~= "string" then
		return nil
	end
	return BY_ID[id] or HYBRID_BY_ID[id] or resolveFallback(id)
end

function CreatureData.isValidId(id: any): boolean
	return type(id) == "string" and CreatureData.get(id) ~= nil
end

-- True for the 21 originals: the only creatures that can go into the Fusion Machine.
function CreatureData.isOriginal(id: string): boolean
	return BY_ID[id] ~= nil
end

function CreatureData.isHybrid(id: string): boolean
	local def = CreatureData.get(id)
	return def ~= nil and def.hybrid == true
end

-- All original creatures of one tier, in list order.
function CreatureData.ofRarity(rarity: string): { CreatureDef }
	return BY_RARITY[rarity] or {}
end

return table.freeze(CreatureData)
