--!strict
--[[
	Gallery
	Lays out a showroom of every creature on podiums: one column per rarity tier,
	one row per creature. Used by the client's dev gallery (Config.Debug) and by
	the preview tooling. Returns the entries so callers can animate them.
]]

local ModelKit = require(script.Parent.ModelKit)
local CreatureModels = require(script.Parent.CreatureModels)
local CreatureData = require(script.Parent.Parent.CreatureData)
local Rarity = require(script.Parent.Parent.Rarity)

export type Entry = {
	def: CreatureData.CreatureDef,
	model: Model,
	home: CFrame, -- the creature's resting pivot
}

local Gallery = {}

local COLUMN_SPACING = 7.5
local ROW_SPACING = 9
local PODIUM_TOP = 1.35

local function addLabel(model: Model, def: CreatureData.CreatureDef)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local rarity = Rarity.get(def.rarity)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(180, 54)
	gui.StudsOffsetWorldSpace = Vector3.new(0, root.Size.Y / 2 + 1.4, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Adornee = root
	gui.Parent = root
	local name = Instance.new("TextLabel")
	name.Name = "CreatureName"
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 0.58)
	name.Font = Enum.Font.FredokaOne
	name.Text = def.displayName
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextScaled = true
	name.Parent = gui
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Thickness = 2
	nameStroke.Color = Color3.fromRGB(30, 26, 40)
	nameStroke.Parent = name
	local tier = Instance.new("TextLabel")
	tier.Name = "Rarity"
	tier.BackgroundTransparency = 1
	tier.Position = UDim2.fromScale(0, 0.58)
	tier.Size = UDim2.fromScale(1, 0.42)
	tier.Font = Enum.Font.FredokaOne
	tier.Text = def.rarity
	tier.TextColor3 = rarity.color
	tier.TextScaled = true
	tier.Parent = gui
	local tierStroke = Instance.new("UIStroke")
	tierStroke.Thickness = 2
	tierStroke.Color = rarity.dark
	tierStroke.Parent = tier
end

local function addPodium(cf: CFrame, rarityName: string, parent: Instance): Model
	local rarity = Rarity.get(rarityName)
	local podium = Instance.new("Model")
	podium.Name = "Podium"
	local up = CFrame.Angles(0, 0, math.rad(90))
	ModelKit.part(
		"Glow",
		"Cylinder",
		Vector3.new(0.16, 6.6, 6.6),
		cf * CFrame.new(0, 0.08, 0) * up,
		rarity.color,
		podium,
		{
			material = Enum.Material.Neon,
			castShadow = false,
		}
	)
	ModelKit.part(
		"Base",
		"Cylinder",
		Vector3.new(1, 6.1, 6.1),
		cf * CFrame.new(0, 0.5, 0) * up,
		Color3.fromRGB(214, 218, 228),
		podium,
		{
			collide = true,
		}
	)
	ModelKit.part(
		"Top",
		"Cylinder",
		Vector3.new(0.35, 5.4, 5.4),
		cf * CFrame.new(0, 1.17, 0) * up,
		rarity.dark,
		podium,
		{
			collide = true,
		}
	)
	podium.Parent = parent
	return podium
end

-- Builds the showroom in front of `anchor` (creatures face the anchor's -Z).
function Gallery.build(anchor: CFrame, parent: Instance): { Entry }
	local entries: { Entry } = {}
	local columns = #Rarity.Order
	for column, rarityName in Rarity.Order do
		for row, def in CreatureData.ofRarity(rarityName) do
			local x = (column - (columns + 1) / 2) * COLUMN_SPACING
			local z = (row - 1) * ROW_SPACING
			local base = anchor * CFrame.new(x, 0, z)
			addPodium(base, rarityName, parent)
			local home = base * CFrame.new(0, PODIUM_TOP, 0)
			local model = CreatureModels.build(def.id, { stage = "Adult", origin = home })
			addLabel(model, def)
			model.Parent = parent
			table.insert(entries, { def = def, model = model, home = home })
		end
	end
	return entries
end

return table.freeze(Gallery)
