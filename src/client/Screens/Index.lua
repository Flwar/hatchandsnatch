--!strict
--[[
	Index
	The discovery book: every creature in the game. Ones you have owned show in full
	color; the rest are black silhouettes until you discover them. Hybrids you have
	fused appear in their own section (Milestone 5).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))
local Window = require(UI:WaitForChild("Window"))
local Profile = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("Profile"))

local Index = {}

-- Extra entries other modules can list after the base creatures (hybrids).
Index.extraEntries = {} :: { () -> { { id: string, name: string, rarity: string, discovered: boolean } } }

local function cell(grid: Instance, order: number, id: string, name: string, rarityName: string, discovered: boolean)
	local rarity = Rarity.get(rarityName)
	local card = Widgets.card(grid, UDim2.new(), if discovered then Theme.Colors.PanelLight else Theme.Colors.Panel)
	card.LayoutOrder = order
	Widgets.creatureViewport(card, id, not discovered, UDim2.new(1, -8, 1, -40)).Position = UDim2.fromOffset(4, 4)
	local label = Theme.text("Name", if discovered then name else "???", card)
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, 4, 1, -4)
	label.Size = UDim2.new(1, -8, 0, 30)
	label.TextColor3 = if discovered then rarity.color else Color3.fromRGB(150, 150, 170)
end

local function build(content: Frame)
	local summary = Profile.fetch()
	local discovered: { [string]: boolean } = {}
	if summary then
		for _, id in summary.discoveries do
			discovered[id] = true
		end
	end
	local count = 0
	for _, def in CreatureData.List do
		if discovered[def.id] then
			count += 1
		end
	end
	local header = Theme.text("Header", `Discovered {count} / {#CreatureData.List}`, content)
	header.Size = UDim2.new(1, 0, 0, 32)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(0, 40)
	holder.Size = UDim2.new(1, 0, 1, -40)
	holder.Parent = content
	local grid = Widgets.grid(holder, UDim2.fromOffset(132, 150))
	local order = 0
	for _, def in CreatureData.List do
		order += 1
		cell(grid, order, def.id, def.displayName, def.rarity, discovered[def.id] == true)
	end
	for _, provider in Index.extraEntries do
		for _, entry in provider() do
			order += 1
			cell(grid, order, entry.id, entry.name, entry.rarity, entry.discovered)
		end
	end
end

function Index.open()
	Window.open("Index", build)
end

return Index
