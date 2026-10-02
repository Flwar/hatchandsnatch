--!strict
--[[
	VipDecor
	The VIP Base pass look (cosmetic only): a golden crown on the base's entrance
	sign, a red carpet with gold edges down the entrance, and two golden torches by
	the gate. Built into a "VipDecor" model inside the base, so removing that model
	undoes it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ModelKit = require(Shared:WaitForChild("Models"):WaitForChild("ModelKit"))

local VipDecor = {}

local v3 = Vector3.new
local GOLD = Color3.fromRGB(255, 200, 60)
local RED = Color3.fromRGB(196, 30, 52)
local GEM = Color3.fromRGB(80, 200, 255)

local function upright(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.rad(90))
end

-- Decorates `base` (a Base model from MapBuilder). Does nothing if it is already done.
function VipDecor.apply(base: Model)
	if base:FindFirstChild("VipDecor") then
		return
	end
	local model = Instance.new("Model")
	model.Name = "VipDecor"
	local shiny = { reflectance = 0.25 }
	-- Crown on top of the entrance sign.
	local signInstance = base:FindFirstChild("Sign")
	if signInstance and signInstance:IsA("BasePart") then
		local sign = signInstance :: BasePart
		local top = sign.CFrame * CFrame.new(0, sign.Size.Y / 2 + 0.55, 0)
		ModelKit.part("CrownBand", "Cylinder", v3(1.1, 2.6, 2.6), upright(top), GOLD, model, shiny)
		for i = 0, 4 do
			local a = math.rad(i * 72)
			local tip = top * CFrame.new(math.cos(a) * 1.15, 0.95, math.sin(a) * 1.15)
			ModelKit.part("CrownPoint", "Ball", v3(0.55, 0.55, 0.55), tip, GOLD, model, shiny)
		end
		ModelKit.part("CrownGem", "Ball", v3(0.6, 0.6, 0.6), top * CFrame.new(0, 0.1, -1.3), GEM, model, {
			reflectance = 0.2,
		})
		ModelKit.part(
			"VipPlate",
			"Block",
			v3(3.2, 0.9, 0.3),
			sign.CFrame * CFrame.new(0, -sign.Size.Y / 2 - 0.6, -0.1),
			GOLD,
			model,
			shiny
		)
	end
	-- Red carpet with gold edges down the entrance.
	local carpetInstance = base:FindFirstChild("Carpet")
	if carpetInstance and carpetInstance:IsA("BasePart") then
		local carpet = carpetInstance :: BasePart
		local cf, size = carpet.CFrame, carpet.Size
		ModelKit.part("RedCarpet", "Block", v3(size.X - 1.6, 0.08, size.Z), cf * CFrame.new(0, 0.05, 0), RED, model, {
			material = Enum.Material.Fabric,
		})
		for side = -1, 1, 2 do
			ModelKit.part(
				"CarpetEdge",
				"Block",
				v3(0.4, 0.1, size.Z),
				cf * CFrame.new(side * (size.X / 2 - 0.6), 0.06, 0),
				GOLD,
				model,
				shiny
			)
		end
		-- Golden torches at the gate end of the carpet.
		local gateEnd = cf * CFrame.new(0, 0, -size.Z / 2 + 1.5)
		for side = -1, 1, 2 do
			local foot = gateEnd * CFrame.new(side * (size.X / 2 + 1.4), 0, 0)
			ModelKit.part(
				"TorchPost",
				"Cylinder",
				v3(3.6, 0.45, 0.45),
				upright(foot * CFrame.new(0, 1.8, 0)),
				GOLD,
				model,
				shiny
			)
			ModelKit.part(
				"TorchBowl",
				"Cylinder",
				v3(0.5, 1.2, 1.2),
				upright(foot * CFrame.new(0, 3.7, 0)),
				GOLD,
				model,
				shiny
			)
			ModelKit.part(
				"TorchFlame",
				"Ball",
				v3(0.9, 0.9, 0.9),
				foot * CFrame.new(0, 4.2, 0),
				Color3.fromRGB(255, 170, 60),
				model,
				{
					material = Enum.Material.Neon,
					castShadow = false,
				}
			)
		end
	end
	model.Parent = base
end

function VipDecor.remove(base: Model)
	local decor = base:FindFirstChild("VipDecor")
	if decor then
		decor:Destroy()
	end
end

return table.freeze(VipDecor)
