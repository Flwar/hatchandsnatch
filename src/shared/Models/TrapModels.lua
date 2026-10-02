--!strict
--[[
	TrapModels
	Small procedural models for the three base traps. Pivot on the ground, facing -Z.
	  BananaPeel   makes raiders slip and drop what they carry
	  StickyFloor  a pink goo puddle that slows raiders down
	  HonkEgg      a decoy egg that honks and reveals the raider to the owner
]]

local ModelKit = require(script.Parent.ModelKit)

local TrapModels = {}

local v3 = Vector3.new
local at = ModelKit.at

local BUILDERS: { [string]: (r: ModelKit.Rig) -> () } = {
	BananaPeel = function(r)
		r.ellipsoid("Fruit", v3(0.9, 0.55, 1.6), at(0, 0.3, 0, 0, 20, 0), "Yellow")
		for i, angle in { 0, 120, 240 } do
			r.ellipsoid(
				`Peel{i}`,
				v3(0.6, 0.14, 1.5),
				at(0, 0.1, 0, 0, angle, 0) * CFrame.new(0, 0, 0.75) * CFrame.Angles(math.rad(-12), 0, 0),
				"Yellow"
			)
		end
		r.ball("Stem", 0.3, v3(0.25, 0.42, -0.72), "Brown")
	end,
	StickyFloor = function(r)
		r.ellipsoid("Puddle", v3(4.2, 0.22, 3.8), at(0, 0.08, 0), "Goo", { reflectance = 0.15 })
		r.ellipsoid("BlobA", v3(1.4, 0.4, 1.2), at(-0.9, 0.18, 0.5), "Goo", { reflectance = 0.15 })
		r.ellipsoid("BlobB", v3(1.0, 0.35, 1.1), at(1.1, 0.16, -0.6), "Goo", { reflectance = 0.15 })
		r.ball("BubbleA", 0.35, v3(0.4, 0.3, 0.9), "Bubble", { transparency = 0.3 })
		r.ball("BubbleB", 0.25, v3(-0.4, 0.28, -0.8), "Bubble", { transparency = 0.3 })
	end,
	HonkEgg = function(r)
		local equator = 1.2
		r.ellipsoid("EggBottom", v3(2.0, 2.0, 2.0), at(0, equator, 0), "Shell")
		r.ellipsoid("EggTop", v3(2.0, 2.8, 2.0), at(0, equator, 0), "Shell")
		r.patch("SpotA", v3(0, equator, 0), v3(2.0, 2.8, 2.0), v3(0.6, 0.5, -0.6), v3(0.6, 0.5, 0.18), "Spot")
		r.patch("SpotB", v3(0, equator, 0), v3(2.0, 2.8, 2.0), v3(-0.7, 0.1, -0.5), v3(0.5, 0.42, 0.18), "Spot")
		r.patch("SpotC", v3(0, equator, 0), v3(2.0, 2.0, 2.0), v3(0.3, -0.4, 0.9), v3(0.5, 0.4, 0.18), "Spot")
		r.disc("Nest", 2.4, 0.4, v3(0, 0.2, 0), "Straw")
	end,
}

local PALETTE: ModelKit.Palette = {
	Yellow = Color3.fromRGB(255, 220, 70),
	Brown = Color3.fromRGB(110, 80, 40),
	Goo = Color3.fromRGB(255, 120, 200),
	Bubble = Color3.fromRGB(255, 200, 236),
	Shell = Color3.fromRGB(255, 244, 214),
	Spot = Color3.fromRGB(255, 196, 80),
	Straw = Color3.fromRGB(214, 176, 100),
}

function TrapModels.has(trapType: string): boolean
	return BUILDERS[trapType] ~= nil
end

function TrapModels.build(trapType: string, origin: CFrame): Model
	local builder = BUILDERS[trapType]
	assert(builder, `Unknown trap type {trapType}`)
	local model = Instance.new("Model")
	model.Name = trapType
	model:SetAttribute("TrapType", trapType)
	local rig = ModelKit.newRig(model, origin, 1, PALETTE)
	builder(rig)
	ModelKit.finishModel(model, rig.parts, origin)
	return model
end

return table.freeze(TrapModels)
