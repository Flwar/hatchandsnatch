--!strict
--[[
	Window
	One menu window at a time (Shop, Inventory, Index, Settings): a centered panel
	with a title, a big close button and a content area, plus an optional tab row.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))

export type Tab = { name: string, build: (body: Frame) -> () }

local Window = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local current: Frame? = nil
local currentTitle: string? = nil

local function getGui(): ScreenGui
	if gui then
		return gui
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "Windows"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	Theme.autoScale(screen)
	gui = screen
	return screen
end

function Window.close()
	if current then
		current:Destroy()
		current = nil
		currentTitle = nil
	end
end

function Window.isOpen(title: string): boolean
	return currentTitle == title
end

-- Opens a window (closing any other) and lets `build` fill its content frame.
function Window.open(title: string, build: (content: Frame) -> ())
	Window.close()
	local panel = Instance.new("Frame")
	panel.Name = title
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.52)
	panel.Size = UDim2.fromOffset(620, 400)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.Parent = getGui()
	Theme.corner(panel, 20)
	Theme.stroke(panel, 4)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Theme.Colors.PanelLight, Theme.Colors.Panel)
	gradient.Parent = panel
	local titleLabel = Theme.text("Title", title, panel)
	titleLabel.Position = UDim2.fromOffset(18, 10)
	titleLabel.Size = UDim2.new(1, -110, 0, 44)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = Theme.Colors.Coin
	Widgets.button(panel, {
		text = "X",
		color = Color3.fromRGB(230, 70, 80),
		size = UDim2.fromOffset(56, 56),
		position = UDim2.new(1, -66, 0, 8),
		callback = Window.close,
	})
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(16, 70)
	content.Size = UDim2.new(1, -32, 1, -86)
	content.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Scale = 0.8
	scale.Parent = panel
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	current = panel
	currentTitle = title
	build(content)
end

-- Fills `content` with a row of tab buttons and a body that shows the selected tab
-- (`initial`, or the first one).
function Window.tabs(content: Frame, tabs: { Tab }, initial: number?)
	local row = Instance.new("Frame")
	row.Name = "Tabs"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 56)
	row.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(0, 66)
	body.Size = UDim2.new(1, 0, 1, -66)
	body.Parent = content
	local buttons: { TextButton } = {}
	local function showTab(index: number)
		body:ClearAllChildren()
		for i, button in buttons do
			button.BackgroundColor3 = if i == index then Theme.Colors.Info else Theme.Colors.PanelLight
		end
		tabs[index].build(body)
	end
	for index, tab in tabs do
		local button = Widgets.button(row, {
			text = tab.name,
			color = Theme.Colors.PanelLight,
			size = UDim2.new(1 / #tabs, -8, 1, 0),
			layoutOrder = index,
			callback = function()
				showTab(index)
			end,
		})
		table.insert(buttons, button)
	end
	showTab(if initial and tabs[initial] then initial else 1)
end

return Window
