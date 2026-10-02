--!strict
--[[
	Inventory
	Every creature in your base: lock one so it can't be stolen, or sell any of
	them (with a confirmation). Built from your creature models' attributes, so it
	always matches what is standing on your pedestals.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Economy = require(Shared:WaitForChild("Economy"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Popup = require(UI:WaitForChild("Popup"))
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))
local Window = require(UI:WaitForChild("Window"))
local MyCreatures = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("MyCreatures"))

local Inventory = {}

local function refreshSoon()
	task.delay(0.5, function()
		if Window.isOpen("Inventory") then
			Inventory.open()
		end
	end)
end

local function build(content: Frame)
	local rows = MyCreatures.list()
	if #rows == 0 then
		local empty = Theme.text("Empty", "No creatures yet! Buy an egg from the conveyor in the lobby.", content)
		empty.Size = UDim2.new(1, 0, 0, 60)
		empty.TextWrapped = true
		return
	end
	local list = Widgets.list(content)
	for index, row in rows do
		local def = CreatureData.get(row.id)
		if not def then
			continue
		end
		local rarity = Rarity.get(def.rarity)
		local card = Widgets.card(list, UDim2.new(1, 0, 0, 80))
		card.LayoutOrder = index
		Widgets.creatureViewport(card, row.id, false, UDim2.fromOffset(72, 72)).Position = UDim2.fromOffset(4, 4)
		local name = Theme.text("Name", `{def.displayName}{if row.mutation then ` ({row.mutation})` else ""}`, card)
		name.Position = UDim2.fromOffset(82, 6)
		name.Size = UDim2.new(0.42, 0, 0, 34)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = rarity.color
		local detail = if row.stage == "Adult"
			then `#{row.slot} · 💰 +{Format.short(Economy.incomePerSec(row.id, row.mutation))}/s`
			else `#{row.slot} · {row.stage} (growing)`
		local info = Theme.text("Info", detail, card)
		info.Position = UDim2.fromOffset(82, 42)
		info.Size = UDim2.new(0.42, 0, 0, 28)
		info.TextXAlignment = Enum.TextXAlignment.Left
		if row.stage == "Adult" then
			Widgets.button(card, {
				text = if row.locked then "🔒 Locked" else "Lock",
				color = if row.locked then Theme.Colors.Info else Theme.Colors.PanelLight,
				size = UDim2.new(0.2, 0, 0, 58),
				position = UDim2.new(0.56, 0, 0, 11),
				callback = function()
					Remotes.event("SetLocked"):FireServer(row.uid, not row.locked)
					refreshSoon()
				end,
			})
		end
		Widgets.button(card, {
			text = `Sell {Format.short(Economy.sellValue(row.id, row.mutation))}`,
			color = Theme.Colors.Warning,
			size = UDim2.new(0.21, 0, 0, 58),
			position = UDim2.new(0.78, 0, 0, 11),
			callback = function()
				Popup.show({
					icon = "💰",
					title = `Sell {def.displayName}?`,
					body = `You'll get {Format.short(Economy.sellValue(row.id, row.mutation))} coins. This can't be undone.`,
					buttons = {
						{ text = "Cancel", color = Theme.Colors.PanelLight },
						{
							text = "Sell",
							color = Theme.Colors.Warning,
							callback = function()
								Remotes.event("SellCreature"):FireServer(row.uid)
								refreshSoon()
							end,
						},
					},
				})
			end,
		})
	end
end

function Inventory.open()
	Window.open("Inventory", build)
end

return Inventory
