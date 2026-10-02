--!strict
--[[
	Index
	The discovery book, in three sections:
	  * Creatures: all 21 originals. Ones you have owned are in full color; the
	    rest are black silhouettes until you discover them.
	  * Secret recipes: the named fusion recipes, silhouettes until you fuse them,
	    with whoever discovered each one first (across every server).
	  * Your hybrids: every fallback hybrid you have made.
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

local CELL = UDim2.fromOffset(128, 164)

local function section(list: Instance, order: number, title: string): Frame
	local header = Theme.text("Header", title, list)
	header.LayoutOrder = order
	header.Size = UDim2.new(1, 0, 0, 34)
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = Theme.Colors.Coin
	local grid = Instance.new("Frame")
	grid.Name = "Section"
	grid.LayoutOrder = order + 1
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromScale(1, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.Parent = list
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = CELL
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	return grid
end

local function cell(grid: Instance, order: number, id: string, discovered: boolean, subtitle: string?)
	local def = CreatureData.get(id)
	if not def then
		return
	end
	local rarity = Rarity.get(def.rarity)
	local card = Widgets.card(grid, UDim2.new(), if discovered then Theme.Colors.PanelLight else Theme.Colors.Panel)
	card.LayoutOrder = order
	Widgets.creatureViewport(card, id, not discovered, UDim2.new(1, -8, 1, -56)).Position = UDim2.fromOffset(4, 4)
	local label = Theme.text("Name", if discovered then def.displayName else "???", card)
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, 4, 1, -24)
	label.Size = UDim2.new(1, -8, 0, 28)
	label.TextColor3 = if discovered then rarity.color else Color3.fromRGB(150, 150, 170)
	local small = Theme.text("Subtitle", subtitle or def.rarity, card)
	small.AnchorPoint = Vector2.new(0, 1)
	small.Position = UDim2.new(0, 4, 1, -4)
	small.Size = UDim2.new(1, -8, 0, 20)
	small.TextColor3 = Color3.fromRGB(200, 196, 220)
end

local function build(content: Frame)
	local summary = Profile.fetch()
	local discovered: { [string]: boolean } = {}
	local firsts: { [string]: string } = {}
	if summary then
		for _, id in summary.discoveries do
			discovered[id] = true
		end
		firsts = summary.firsts or {}
	end
	local list = Widgets.list(content, 8)

	local originals = 0
	for _, def in CreatureData.List do
		if discovered[def.id] then
			originals += 1
		end
	end
	local grid = section(list, 1, `Creatures  {originals} / {#CreatureData.List}`)
	for order, def in CreatureData.List do
		cell(grid, order, def.id, discovered[def.id] == true)
	end

	local recipes = 0
	for _, def in CreatureData.Hybrids do
		if discovered[def.id] then
			recipes += 1
		end
	end
	grid = section(list, 3, `Secret recipes  {recipes} / {#CreatureData.Hybrids}`)
	for order, def in CreatureData.Hybrids do
		local first = firsts[def.id]
		cell(grid, order, def.id, discovered[def.id] == true, if first then `1st: {first}` else "Undiscovered!")
	end

	local made: { CreatureData.CreatureDef } = {}
	for id in discovered do
		local def = CreatureData.get(id)
		if def and def.hybrid and not def.recipe then
			table.insert(made, def)
		end
	end
	table.sort(made, function(a, b)
		local rankA, rankB = Rarity.rank(a.rarity), Rarity.rank(b.rarity)
		if rankA ~= rankB then
			return rankA > rankB
		end
		return a.displayName < b.displayName
	end)
	grid = section(list, 5, `Your hybrids  {#made}`)
	if #made == 0 then
		local hint = Theme.text("Hint", "Fuse two adults in your Fusion Machine to make one!", grid)
		hint.TextWrapped = true
	end
	for order, def in made do
		cell(grid, order, def.id, true)
	end
end

function Index.open()
	Window.open("Index", build)
end

return Index
