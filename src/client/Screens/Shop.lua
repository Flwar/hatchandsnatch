--!strict
--[[
	Shop
	Egg odds (eggs themselves are bought on the conveyor, always with their contents
	shown), pedestal unlocks and traps. Monetization tabs are added in Milestone 8.
	Every purchase is a request; the server checks the price and the coins.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Economy = require(Shared:WaitForChild("Economy"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))
local Window = require(UI:WaitForChild("Window"))
local Profile = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("Profile"))

local Shop = {}

-- Extra tabs other modules can add (Milestone 8 adds passes and coin packs).
Shop.extraTabs = {} :: { Window.Tab }

local TRAPS = {
	{ id = "BananaPeel", name = "🍌 Banana Peel", text = "Raiders slip and drop what they carry." },
	{ id = "StickyFloor", name = "🩷 Sticky Floor", text = "Slows raiders down for a few seconds." },
	{ id = "HonkEgg", name = "🦢 Honk Egg", text = "A decoy egg that honks and reveals raiders." },
}

local function eggsTab(body: Frame)
	local list = Widgets.list(body)
	local intro = Theme.text(
		"Intro",
		"Eggs roll down the conveyor in the lobby. You always see what's inside before you buy!",
		list
	)
	intro.Size = UDim2.new(1, 0, 0, 48)
	intro.TextWrapped = true
	intro.LayoutOrder = 0
	local total = 0
	for _, weight in Config.RarityWeights :: { [string]: number } do
		total += weight
	end
	for index, rarityName in Rarity.Order do
		local info = Rarity.get(rarityName)
		local weight = (Config.RarityWeights :: { [string]: number })[rarityName] or 0
		local row = Widgets.card(list, UDim2.new(1, 0, 0, 52), Theme.Colors.PanelLight)
		row.LayoutOrder = index
		local chip = Instance.new("Frame")
		chip.Size = UDim2.fromOffset(16, 36)
		chip.Position = UDim2.fromOffset(10, 8)
		chip.BackgroundColor3 = info.color
		chip.Parent = row
		Theme.corner(chip, 6)
		local name = Theme.text("Rarity", rarityName, row)
		name.Position = UDim2.fromOffset(36, 8)
		name.Size = UDim2.new(0.3, 0, 0, 36)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = info.color
		local names = {}
		for _, def in CreatureData.ofRarity(rarityName) do
			table.insert(names, def.displayName)
		end
		local examples = Theme.text("Examples", table.concat(names, ", "), row)
		examples.Position = UDim2.new(0.3, 40, 0, 12)
		examples.Size = UDim2.new(0.5, -40, 0, 28)
		examples.TextXAlignment = Enum.TextXAlignment.Left
		local percent = weight / total * 100
		local odds = Theme.text(
			"Odds",
			if percent >= 1
				then `{math.floor(percent * 10 + 0.5) / 10}%`
				else `{math.floor(percent * 100 + 0.5) / 100}%`,
			row
		)
		odds.Position = UDim2.new(0.8, 0, 0, 8)
		odds.Size = UDim2.new(0.2, -10, 0, 36)
		odds.TextXAlignment = Enum.TextXAlignment.Right
	end
end

local function baseTab(body: Frame)
	local summary = Profile.fetch()
	local owned = if summary then summary.pedestals else Config.StartingPedestals
	local card = Widgets.card(body, UDim2.new(1, 0, 0, 150))
	local title = Theme.text("Title", `Pedestals: {owned} / {Config.MaxPedestals}`, card)
	title.Position = UDim2.fromOffset(16, 12)
	title.Size = UDim2.new(1, -32, 0, 40)
	title.TextXAlignment = Enum.TextXAlignment.Left
	if owned >= Config.MaxPedestals then
		local done = Theme.text("Done", "Every pedestal is unlocked. Nice base!", card)
		done.Position = UDim2.fromOffset(16, 70)
		done.Size = UDim2.new(1, -32, 0, 36)
		return
	end
	local cost = Economy.pedestalCost(owned)
	local note = Theme.text("Note", "More pedestals = more creatures earning coins.", card)
	note.Position = UDim2.fromOffset(16, 52)
	note.Size = UDim2.new(1, -32, 0, 28)
	note.TextXAlignment = Enum.TextXAlignment.Left
	Widgets.button(card, {
		text = `Unlock next for 💰 {Format.short(cost)}`,
		size = UDim2.new(1, -32, 0, 56),
		position = UDim2.fromOffset(16, 84),
		callback = function()
			Remotes.event("BuyPedestal"):FireServer()
			task.delay(0.4, function()
				if Window.isOpen("Shop") then
					Shop.open(2)
				end
			end)
		end,
	})
end

local function trapsTab(body: Frame)
	local summary = Profile.fetch()
	local placed = if summary then #summary.traps else 0
	local list = Widgets.list(body)
	local header =
		Theme.text("Header", `Traps in your base: {placed} / {Config.MaxTraps}. They trigger on raiders only.`, list)
	header.Size = UDim2.new(1, 0, 0, 32)
	header.LayoutOrder = 0
	for index, trap in TRAPS do
		local price = (Config.TrapPrices :: { [string]: number })[trap.id] or 0
		local card = Widgets.card(list, UDim2.new(1, 0, 0, 76))
		card.LayoutOrder = index
		local name = Theme.text("Name", trap.name, card)
		name.Position = UDim2.fromOffset(14, 6)
		name.Size = UDim2.new(0.6, 0, 0, 32)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local text = Theme.text("Text", trap.text, card)
		text.Position = UDim2.fromOffset(14, 40)
		text.Size = UDim2.new(0.62, 0, 0, 26)
		text.TextXAlignment = Enum.TextXAlignment.Left
		Widgets.button(card, {
			text = `💰 {Format.short(price)}`,
			size = UDim2.new(0.32, 0, 0, 56),
			position = UDim2.new(0.66, 0, 0, 10),
			callback = function()
				Remotes.event("BuyTrap"):FireServer(trap.id)
				task.delay(0.4, function()
					if Window.isOpen("Shop") then
						Shop.open(3)
					end
				end)
			end,
		})
	end
end

function Shop.open(tabIndex: number?)
	local tabs: { Window.Tab } = {
		{ name = "Eggs", build = eggsTab },
		{ name = "Base", build = baseTab },
		{ name = "Traps", build = trapsTab },
	}
	for _, tab in Shop.extraTabs do
		table.insert(tabs, tab)
	end
	Window.open("Shop", function(content: Frame)
		Window.tabs(content, tabs, tabIndex)
	end)
end

return Shop
