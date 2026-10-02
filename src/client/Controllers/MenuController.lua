--!strict
--[[
	MenuController
	The HUD menu buttons (Shop, Inventory, Index, Arena, Settings) down the left side of the
	screen, big enough for thumbs, and loading the player's saved settings.
]]

local Players = game:GetService("Players")

local Screens = script.Parent.Parent:WaitForChild("Screens")
local Shop = require(Screens:WaitForChild("Shop"))
local Inventory = require(Screens:WaitForChild("Inventory"))
local Index = require(Screens:WaitForChild("Index"))
local SettingsScreen = require(Screens:WaitForChild("SettingsScreen"))
local Arena = require(Screens:WaitForChild("Arena"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))
local Window = require(UI:WaitForChild("Window"))
local State = script.Parent.Parent:WaitForChild("State")
local Profile = require(State:WaitForChild("Profile"))
local Settings = require(State:WaitForChild("Settings"))

local MenuController = {}

local player = Players.LocalPlayer

local BUTTONS = {
	{ text = "🛒", label = "Shop", color = Color3.fromRGB(255, 176, 64), open = Shop.open },
	{ text = "🎒", label = "Inventory", color = Color3.fromRGB(96, 200, 120), open = Inventory.open },
	{ text = "📖", label = "Index", color = Color3.fromRGB(110, 170, 255), open = Index.open },
	{ text = "⚔️", label = "Arena", color = Color3.fromRGB(240, 96, 110), open = Arena.open },
	{ text = "⚙️", label = "Settings", color = Color3.fromRGB(150, 150, 180), open = SettingsScreen.open },
}

function MenuController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Menu"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	Theme.autoScale(gui)
	local column = Instance.new("Frame")
	column.Name = "Buttons"
	column.AnchorPoint = Vector2.new(0, 0.5)
	column.Position = UDim2.new(0, 10, 0.5, 0)
	column.Size = UDim2.fromOffset(76, #BUTTONS * 84)
	column.BackgroundTransparency = 1
	column.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = column
	for index, spec in BUTTONS do
		local holder = Instance.new("Frame")
		holder.Name = spec.label
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromOffset(76, 76)
		holder.LayoutOrder = index
		holder.Parent = column
		Widgets.button(holder, {
			text = spec.text,
			color = spec.color,
			size = UDim2.fromOffset(64, 64),
			position = UDim2.fromOffset(6, 0),
			callback = function()
				if Window.isOpen(spec.label) then
					Window.close()
				else
					spec.open()
				end
			end,
		})
		local caption = Theme.text("Caption", spec.label, holder)
		caption.Position = UDim2.fromOffset(0, 58)
		caption.Size = UDim2.fromOffset(76, 18)
		caption.ZIndex = 2
	end
end

function MenuController.start()
	local summary = Profile.fetch()
	if summary then
		Settings.load(summary.settings)
	end
end

return MenuController
