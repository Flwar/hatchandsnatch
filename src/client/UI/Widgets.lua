--!strict
--[[
	Widgets
	Building blocks for menus, all sized for touch (buttons at least 56 px on the
	560 px reference screen, so never under 44 px once scaled for phones).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureModels = require(Shared:WaitForChild("Models"):WaitForChild("CreatureModels"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Widgets = {}

export type ButtonSpec = {
	text: string,
	color: Color3?,
	size: UDim2?,
	position: UDim2?,
	layoutOrder: number?,
	callback: () -> (),
}

function Widgets.button(parent: Instance, spec: ButtonSpec): TextButton
	local button = Instance.new("TextButton")
	button.Name = spec.text
	button.Size = spec.size or UDim2.fromOffset(160, 56)
	if spec.position then
		button.Position = spec.position
	end
	button.LayoutOrder = spec.layoutOrder or 0
	button.BackgroundColor3 = spec.color or Theme.Colors.Success
	button.AutoButtonColor = true
	button.Font = Theme.Font
	button.Text = spec.text
	button.TextScaled = true
	button.TextColor3 = Theme.Colors.Text
	button.Parent = parent
	Theme.corner(button, 14)
	Theme.stroke(button, 3)
	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 2
	textStroke.Color = Theme.Colors.Outline
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = button
	button.Activated:Connect(function()
		Sounds.play("Click")
		spec.callback()
	end)
	return button
end

function Widgets.card(parent: Instance, size: UDim2, color: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.BackgroundColor3 = color or Theme.Colors.PanelLight
	frame.Parent = parent
	Theme.corner(frame, 14)
	Theme.stroke(frame, 2)
	return frame
end

-- A vertical scrolling list that grows with its content.
function Widgets.list(parent: Instance, padding: number?): ScrollingFrame
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "List"
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 8
	scroller.CanvasSize = UDim2.new()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding or 8)
	layout.Parent = scroller
	local inset = Instance.new("UIPadding")
	inset.PaddingRight = UDim.new(0, 12)
	inset.Parent = scroller
	return scroller
end

-- A scrolling grid of equal cells.
function Widgets.grid(parent: Instance, cellSize: UDim2): ScrollingFrame
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Grid"
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 8
	scroller.CanvasSize = UDim2.new()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.Parent = parent
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = cellSize
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroller
	return scroller
end

-- A 3D preview of a creature. `silhouette` renders it as a black shape (undiscovered).
function Widgets.creatureViewport(
	parent: Instance,
	creatureId: string,
	silhouette: boolean,
	size: UDim2,
	mutation: string?
): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.Size = size
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(170, 170, 180)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-1, -1.5, -0.8)
	viewport.Parent = parent
	local options: CreatureModels.BuildOptions = { stage = "Adult", origin = CFrame.new(), mutation = mutation :: any }
	local ok, model = pcall(CreatureModels.build, creatureId, options)
	if not ok or not model then
		return viewport
	end
	model.Parent = viewport
	local root = model.PrimaryPart
	local height = if root then root.Size.Y else 5
	local width = if root then math.max(root.Size.X, root.Size.Z) else 5
	local center = if root then root.Position else Vector3.new(0, 2.5, 0)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local distance = math.max(height, width) / math.tan(math.rad(15)) * 0.62
	camera.CFrame = CFrame.lookAt(center + Vector3.new(-0.45, 0.35, -1).Unit * distance, center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	if silhouette then
		viewport.ImageColor3 = Color3.new(0, 0, 0)
		viewport.ImageTransparency = 0.15
	end
	return viewport
end

return table.freeze(Widgets)
