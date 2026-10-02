--!strict
--[[
	FusionRecipes
	Named fusion recipes: pairs of original creatures that fuse into a hand-made hybrid
	with its own name, model and better income (Config.FusionRecipeBonus). Any other
	pair of two different originals makes a fallback hybrid generated from both parents
	(see CreatureData.fuse).

	The first time anyone on any server fuses a named recipe, it becomes a global
	"FIRST DISCOVERY!" (see FusionService).

	This module is plain data so CreatureData can build full definitions from it.
	Stats are derived from the parents there, so balancing the parents also balances
	their hybrids.
]]

export type Recipe = {
	parents: { string }, -- two original creature ids; order does not matter
	id: string,
	displayName: string,
	rarity: string,
	modelName: string, -- art in Models/CreatureModels
	description: string,
}

local FusionRecipes = {}

local LIST: { Recipe } = {
	{
		parents = { "blobbit", "waddlecake" },
		id = "jellydonut",
		displayName = "Jelly Donut",
		rarity = "Rare",
		modelName = "JellyDonut",
		description = "A sugar-dusted donut with a jelly bunny living inside. Squeeze gently.",
	},
	{
		parents = { "sproutle", "cactopus" },
		id = "cactortoise",
		displayName = "Cactortoise",
		rarity = "Epic",
		modelName = "Cactortoise",
		description = "Grows a whole cactus garden on its shell. Very slow, very spiky, do not hug.",
	},
	{
		parents = { "jellyknight", "discododo" },
		id = "boogieknight",
		displayName = "Boogie Knight",
		rarity = "Legendary",
		modelName = "BoogieKnight",
		description = "Sworn to defend the dance floor. Its helmet is a disco ball.",
	},
	{
		parents = { "blobbit", "moonmoth" },
		id = "mothball",
		displayName = "Mothball",
		rarity = "Mythic",
		modelName = "Mothball",
		description = "A perfectly round, extremely fluffy moth. Rolls more than it flies.",
	},
	{
		parents = { "pebblepup", "volcanowl" },
		id = "magmutt",
		displayName = "Magmutt",
		rarity = "Mythic",
		modelName = "Magmutt",
		description = "A good boy made of cooling lava. Fetches, but the stick catches fire.",
	},
	{
		parents = { "toastshark", "croissaur" },
		id = "brunchasaurus",
		displayName = "Brunchasaurus",
		rarity = "Secret",
		modelName = "Brunchasaurus",
		description = "The most important meal of the Jurassic. Comes with a fried egg on top.",
	},
	{
		parents = { "cosmigoose", "glitchling" },
		id = "gooseexe",
		displayName = "Goose.exe",
		rarity = "Secret",
		modelName = "GooseExe",
		description = "A cosmic goose that clipped through reality. Has stopped responding.",
	},
	{
		parents = { "dragonroll", "burritoad" },
		id = "sushirrito",
		displayName = "Sushirrito",
		rarity = "Secret",
		modelName = "Sushirrito",
		description = "Half sushi, half burrito, all toad. Hold it with both hands.",
	},
}

local function pairKey(a: string, b: string): string
	return if a < b then `{a}+{b}` else `{b}+{a}`
end

local BY_PAIR: { [string]: Recipe } = {}
for _, recipe in LIST do
	assert(#recipe.parents == 2 and recipe.parents[1] ~= recipe.parents[2], `Recipe {recipe.id} needs two parents`)
	local key = pairKey(recipe.parents[1], recipe.parents[2])
	assert(BY_PAIR[key] == nil, `Two recipes for {key}`)
	BY_PAIR[key] = recipe
	table.freeze(recipe.parents)
	table.freeze(recipe)
end

FusionRecipes.List = table.freeze(LIST)

-- The named recipe for two creature ids (in either order), if there is one.
function FusionRecipes.find(a: string, b: string): Recipe?
	return BY_PAIR[pairKey(a, b)]
end

return table.freeze(FusionRecipes)
