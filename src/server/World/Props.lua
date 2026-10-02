--!strict
--[[
	Props
	Small reusable scenery pieces for the procedural map: trees, lamp posts, benches,
	bushes, flag poles and signs. Every function takes a world CFrame (ground point,
	facing -Z) and a parent, and returns the Model it built.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models"):WaitForChild("ModelKit"))

local Props = {}

local v3 = Vector3.new
local part = ModelKit.part

local TRUNK = Color3.fromRGB(122, 86, 58)
local LEAVES = {
	Color3.fromRGB(96, 186, 82),
	Color3.fromRGB(80, 168, 74),
	Color3.fromRGB(118, 200, 92),
}
local METAL_DARK = Color3.fromRGB(58, 62, 74)
local LAMP_GLOW = Color3.fromRGB(255, 226, 160)

local function newModel(name: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

-- A round cartoon tree. `variant` (1..3) changes the canopy shape a little.
function Props.tree(cf: CFrame, parent: Instance, scale: number?, variant: number?): Model
	local s = scale or 1
	local v = variant or 1
	local model = newModel("Tree", parent)
	local trunkHeight = 7 * s
	part(
		"Trunk",
		"Cylinder",
		v3(trunkHeight, 1.6 * s, 1.6 * s),
		cf * CFrame.new(0, trunkHeight / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		TRUNK,
		model,
		{
			material = Enum.Material.Wood,
			collide = true,
		}
	)
	local leaf = LEAVES[(v - 1) % #LEAVES + 1]
	local top = trunkHeight + 1.5 * s
	part("CanopyA", "Ball", v3(7, 7, 7) * s, cf * CFrame.new(0, top, 0), leaf, model, { collide = true })
	part(
		"CanopyB",
		"Ball",
		v3(5.2, 5.2, 5.2) * s,
		cf * CFrame.new(2.4 * s, top - 1.2 * s, 0.6 * s),
		LEAVES[v % #LEAVES + 1],
		model
	)
	part("CanopyC", "Ball", v3(4.8, 4.8, 4.8) * s, cf * CFrame.new(-2.0 * s, top - 0.6 * s, -1.4 * s), leaf, model)
	if v == 2 then
		part(
			"CanopyTop",
			"Ball",
			v3(4.2, 4.2, 4.2) * s,
			cf * CFrame.new(0.4 * s, top + 3 * s, 0.2 * s),
			LEAVES[(v + 1) % #LEAVES + 1],
			model
		)
	end
	return model
end

-- A lamp post with a warm PointLight that matters at night.
function Props.lamp(cf: CFrame, parent: Instance, height: number?): Model
	local h = height or 10
	local model = newModel("Lamp", parent)
	part(
		"Foot",
		"Cylinder",
		v3(0.6, 1.6, 1.6),
		cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		METAL_DARK,
		model,
		{
			collide = true,
		}
	)
	part(
		"Pole",
		"Cylinder",
		v3(h, 0.55, 0.55),
		cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		METAL_DARK,
		model,
		{
			collide = true,
		}
	)
	part(
		"Cap",
		"Cylinder",
		v3(0.3, 2.0, 2.0),
		cf * CFrame.new(0, h + 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		METAL_DARK,
		model
	)
	local bulb = part("Bulb", "Ball", v3(1.7, 1.7, 1.7), cf * CFrame.new(0, h + 0.55, 0), LAMP_GLOW, model, {
		material = Enum.Material.Neon,
		castShadow = false,
	})
	local light = Instance.new("PointLight")
	light.Color = LAMP_GLOW
	light.Range = 22
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = bulb
	return model
end

function Props.bench(cf: CFrame, parent: Instance): Model
	local model = newModel("Bench", parent)
	local wood = Color3.fromRGB(176, 120, 72)
	local opts = { material = Enum.Material.WoodPlanks, collide = true }
	part("Seat", "Block", v3(6, 0.4, 1.8), cf * CFrame.new(0, 1.6, 0), wood, model, opts)
	part(
		"Back",
		"Block",
		v3(6, 1.4, 0.35),
		cf * CFrame.new(0, 2.65, 0.85) * CFrame.Angles(math.rad(-12), 0, 0),
		wood,
		model,
		opts
	)
	for _, x in { -2.5, 2.5 } do
		part("Leg", "Block", v3(0.4, 1.4, 1.6), cf * CFrame.new(x, 0.7, 0), METAL_DARK, model, { collide = true })
	end
	return model
end

function Props.bush(cf: CFrame, parent: Instance, scale: number?): Model
	local s = scale or 1
	local model = newModel("Bush", parent)
	part("BushA", "Ball", v3(3.2, 3.2, 3.2) * s, cf * CFrame.new(0, 1.0 * s, 0), LEAVES[2], model)
	part("BushB", "Ball", v3(2.6, 2.6, 2.6) * s, cf * CFrame.new(1.5 * s, 0.8 * s, 0.4 * s), LEAVES[1], model)
	part("BushC", "Ball", v3(2.2, 2.2, 2.2) * s, cf * CFrame.new(-1.3 * s, 0.7 * s, -0.3 * s), LEAVES[3], model)
	return model
end

-- Flower clump: a few colorful balls on short stems, purely decorative.
function Props.flowers(cf: CFrame, parent: Instance, color: Color3): Model
	local model = newModel("Flowers", parent)
	local offsets = { v3(0, 0, 0), v3(1.0, 0, 0.5), v3(-0.8, 0, 0.7), v3(0.3, 0, -0.9) }
	for i, offset in offsets do
		local height = 0.9 + (i % 2) * 0.35
		part(
			"Stem",
			"Cylinder",
			v3(height, 0.18, 0.18),
			cf * CFrame.new(offset + v3(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			LEAVES[1],
			model
		)
		part(
			"Bloom",
			"Ball",
			v3(0.7, 0.7, 0.7),
			cf * CFrame.new(offset + v3(0, height + 0.2, 0)),
			if i == 2 then Color3.fromRGB(255, 240, 120) else color,
			model
		)
	end
	return model
end

function Props.flag(cf: CFrame, parent: Instance, color: Color3): Model
	local model = newModel("Flag", parent)
	local h = 15
	part(
		"Pole",
		"Cylinder",
		v3(h, 0.45, 0.45),
		cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(230, 232, 238),
		model,
		{
			collide = true,
		}
	)
	part("Knob", "Ball", v3(0.9, 0.9, 0.9), cf * CFrame.new(0, h + 0.3, 0), Color3.fromRGB(255, 206, 64), model, {
		reflectance = 0.15,
	})
	part(
		"Cloth",
		"Block",
		v3(4.4, 2.6, 0.18),
		cf * CFrame.new(2.4, h - 1.6, 0),
		color,
		model,
		{ material = Enum.Material.Fabric }
	)
	part(
		"Stripe",
		"Block",
		v3(4.42, 0.5, 0.2),
		cf * CFrame.new(2.4, h - 1.6, 0),
		Color3.fromRGB(255, 255, 255),
		model,
		{
			material = Enum.Material.Fabric,
		}
	)
	return model
end

-- A sign board with text on its front (-Z) face and optionally its back face.
function Props.sign(
	name: string,
	size: Vector3,
	cf: CFrame,
	parent: Instance,
	text: string,
	boardColor: Color3,
	textColor: Color3,
	bothSides: boolean?
): BasePart
	local board = part(name, "Block", size, cf, boardColor, parent, { collide = true })
	local faces = { Enum.NormalId.Front }
	if bothSides then
		table.insert(faces, Enum.NormalId.Back)
	end
	for _, face in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Name = if face == Enum.NormalId.Front then "FrontGui" else "BackGui"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Name = "Title"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.Text = text
		label.TextColor3 = textColor
		label.TextScaled = true
		label.Parent = gui
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0.04, 0)
		padding.PaddingRight = UDim.new(0.04, 0)
		padding.PaddingTop = UDim.new(0.08, 0)
		padding.PaddingBottom = UDim.new(0.08, 0)
		padding.Parent = label
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(40, 30, 50)
		stroke.Parent = label
	end
	return board
end

-- Updates every text label of a sign made by Props.sign.
function Props.setSignText(board: Instance, text: string)
	for _, gui in board:GetChildren() do
		if gui:IsA("SurfaceGui") then
			local label = gui:FindFirstChild("Title")
			if label and label:IsA("TextLabel") then
				(label :: TextLabel).Text = text
			end
		end
	end
end

return table.freeze(Props)
