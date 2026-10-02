--!strict
--[[
	Popup
	Centered modal dialogs (offline earnings, confirmations, info). Mobile first:
	big rounded panel, big buttons (well above the 44 px touch minimum), and only
	one popup at a time; extra popups wait in a queue.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))

export type Button = {
	text: string,
	color: Color3?,
	callback: (() -> ())?,
}

export type Options = {
	title: string,
	body: string,
	icon: string?,
	buttons: { Button }?,
}

local Popup = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local queue: { Options } = {}
local showing = false

local function getGui(): ScreenGui
	if gui then
		return gui
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "Popups"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 20
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	Theme.autoScale(screen)
	gui = screen
	return screen
end

local showNext: () -> ()

local function render(options: Options)
	local screen = getGui()
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.Parent = screen

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(420, 280)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.Parent = shade
	Theme.corner(panel, 22)
	Theme.stroke(panel, 4)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Theme.Colors.PanelLight, Theme.Colors.Panel)
	gradient.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Scale = 0.7
	scale.Parent = panel

	local icon = Theme.text("Icon", options.icon or "", panel)
	icon.Position = UDim2.fromOffset(0, 14)
	icon.Size = UDim2.new(1, 0, 0, 52)
	local title = Theme.text("Title", options.title, panel)
	title.Position = UDim2.fromOffset(20, 68)
	title.Size = UDim2.new(1, -40, 0, 38)
	title.TextColor3 = Theme.Colors.Coin
	local body = Theme.text("Body", options.body, panel)
	body.Position = UDim2.fromOffset(24, 110)
	body.Size = UDim2.new(1, -48, 0, 70)
	body.TextWrapped = true

	local buttons: { Button } = options.buttons or { { text = "OK" } :: Button }
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -18)
	row.Size = UDim2.new(1, -40, 0, 64)
	row.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = row

	local function close()
		local tween = TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 0.7 })
		tween:Play()
		tween.Completed:Wait()
		shade:Destroy()
		showing = false
		showNext()
	end

	for _, spec in buttons do
		local button = Instance.new("TextButton")
		button.Name = spec.text
		button.Size = UDim2.fromOffset(math.min(170, 360 / #buttons), 60)
		button.BackgroundColor3 = spec.color or Theme.Colors.Success
		button.AutoButtonColor = true
		button.Font = Theme.Font
		button.Text = spec.text
		button.TextScaled = true
		button.TextColor3 = Theme.Colors.Text
		button.Parent = row
		Theme.corner(button, 16)
		Theme.stroke(button, 3)
		local textStroke = Instance.new("UIStroke")
		textStroke.Thickness = 2
		textStroke.Color = Theme.Colors.Outline
		textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		textStroke.Parent = button
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 10)
		padding.PaddingBottom = UDim.new(0, 10)
		padding.Parent = button
		button.Activated:Connect(function()
			if spec.callback then
				task.spawn(spec.callback)
			end
			close()
		end)
	end

	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

showNext = function()
	if showing then
		return
	end
	local nextOptions = table.remove(queue, 1)
	if nextOptions then
		showing = true
		render(nextOptions)
	end
end

function Popup.show(options: Options)
	table.insert(queue, options)
	showNext()
end

return table.freeze(Popup)
