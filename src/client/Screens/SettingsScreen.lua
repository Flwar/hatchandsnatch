--!strict
--[[
	SettingsScreen
	Sound effects and creature labels on/off, saved to your profile.
]]

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))
local Window = require(UI:WaitForChild("Window"))
local Settings = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("Settings"))

local SettingsScreen = {}

local ROWS: { { key: "sfx" | "labels", label: string } } = {
	{ key = "sfx", label = "🔊 Sound effects" },
	{ key = "labels", label = "🏷️ Creature labels" },
}

local function build(content: Frame)
	local list = Widgets.list(content, 12)
	for index, row in ROWS do
		local card = Widgets.card(list, UDim2.new(1, 0, 0, 76))
		card.LayoutOrder = index
		local label = Theme.text("Label", row.label, card)
		label.Position = UDim2.fromOffset(16, 14)
		label.Size = UDim2.new(0.6, 0, 0, 46)
		label.TextXAlignment = Enum.TextXAlignment.Left
		local on = Settings.values[row.key]
		Widgets.button(card, {
			text = if on then "ON" else "OFF",
			color = if on then Theme.Colors.Success else Color3.fromRGB(150, 150, 170),
			size = UDim2.new(0.3, 0, 0, 58),
			position = UDim2.new(0.68, 0, 0, 9),
			callback = function()
				Settings.set(row.key, not Settings.values[row.key])
				SettingsScreen.open()
			end,
		})
	end
end

function SettingsScreen.open()
	Window.open("Settings", build)
end

return SettingsScreen
