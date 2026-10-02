--!strict
--[[
	Products
	Helpers around Config.GamePasses and Config.DevProducts shared by the Shop and
	the server, so both always agree on what a purchase gives:

	  * coin packs give `minutes` of your current income (at least `minimum`)
	  * bat skins are cosmetic recolors of the bonk bat (BatSkins below)

	Nothing here is random: every product gives exactly what the Shop shows.
]]

local Config = require(script.Parent.Config)

export type SkinPart = { color: Color3, material: Enum.Material?, reflectance: number? }
export type BatSkin = { name: string, parts: { [string]: SkinPart } }

local Products = {}

-- Display order in the Shop.
Products.PassOrder = table.freeze({ "DoubleIncome", "ExtraPedestals", "FastFusion", "VipBase" })
Products.CoinOrder = table.freeze({ "CoinsSmall", "CoinsMedium", "CoinsLarge", "GrowToken" })
Products.BatOrder = table.freeze({ "Classic", "Golden", "Candy", "Galaxy" })

local GOLD = Color3.fromRGB(255, 200, 60)
local function part(color: Color3, material: Enum.Material?, reflectance: number?): SkinPart
	return { color = color, material = material, reflectance = reflectance }
end

-- How each skin paints the bat's parts (see CombatService).
Products.BatSkins = table.freeze({
	Classic = {
		name = "Classic Bat",
		parts = {
			Handle = part(Color3.fromRGB(200, 60, 70)),
			Knob = part(Color3.fromRGB(60, 40, 30)),
			Barrel = part(Color3.fromRGB(214, 160, 96), Enum.Material.Wood),
			Tip = part(Color3.fromRGB(214, 160, 96), Enum.Material.Wood),
			Band = part(Color3.fromRGB(255, 210, 70)),
		},
	},
	Golden = {
		name = "Golden Bat",
		parts = {
			Handle = part(Color3.fromRGB(150, 96, 20), nil, 0.2),
			Knob = part(GOLD, nil, 0.35),
			Barrel = part(GOLD, Enum.Material.SmoothPlastic, 0.35),
			Tip = part(GOLD, Enum.Material.SmoothPlastic, 0.35),
			Band = part(Color3.fromRGB(255, 255, 255), Enum.Material.Neon),
		},
	},
	Candy = {
		name = "Candy Bat",
		parts = {
			Handle = part(Color3.fromRGB(255, 255, 255)),
			Knob = part(Color3.fromRGB(255, 110, 170)),
			Barrel = part(Color3.fromRGB(255, 130, 180), Enum.Material.SmoothPlastic, 0.1),
			Tip = part(Color3.fromRGB(255, 130, 180), Enum.Material.SmoothPlastic, 0.1),
			Band = part(Color3.fromRGB(255, 255, 255)),
		},
	},
	Galaxy = {
		name = "Galaxy Bat",
		parts = {
			Handle = part(Color3.fromRGB(30, 24, 70)),
			Knob = part(Color3.fromRGB(150, 76, 226)),
			Barrel = part(Color3.fromRGB(56, 36, 128), Enum.Material.SmoothPlastic, 0.15),
			Tip = part(Color3.fromRGB(150, 76, 226), Enum.Material.SmoothPlastic, 0.15),
			Band = part(Color3.fromRGB(110, 236, 255), Enum.Material.Neon),
		},
	},
} :: { [string]: BatSkin })

-- Coins a coin pack gives a player who earns `incomePerSec` right now.
function Products.coinPackAmount(key: string, incomePerSec: number): number
	local product = (Config.DevProducts :: any)[key]
	if not product or product.kind ~= "coins" then
		return 0
	end
	local fromIncome = math.max(0, incomePerSec) * product.minutes * 60
	return math.floor(math.max(product.minimum, fromIncome))
end

-- The product key for a developer product id (nil for unknown or unset ids).
function Products.productKey(productId: number): string?
	if productId == 0 then
		return nil
	end
	for key, product in Config.DevProducts :: any do
		if product.id == productId then
			return key
		end
	end
	return nil
end

-- The dev product that sells a bat skin.
function Products.skinProduct(skin: string): string?
	for key, product in Config.DevProducts :: any do
		if product.kind == "batSkin" and product.skin == skin then
			return key
		end
	end
	return nil
end

return table.freeze(Products)
