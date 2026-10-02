--!strict
--[[
	Theme
	Shared look for all UI: colors, fonts, corner radius and helpers that build the
	common pieces (rounded panels with outline, outlined text). Mobile first: every
	size here is designed for a 560 px tall reference screen and scaled by UIScale.
]]

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.Colors = table.freeze({
	Panel = Color3.fromRGB(40, 34, 64),
	PanelLight = Color3.fromRGB(66, 56, 102),
	Outline = Color3.fromRGB(22, 18, 36),
	Text = Color3.fromRGB(255, 255, 255),
	Coin = Color3.fromRGB(255, 214, 72),
	Success = Color3.fromRGB(96, 214, 120),
	Warning = Color3.fromRGB(255, 176, 64),
	Info = Color3.fromRGB(110, 170, 255),
})
Theme.ReferenceHeight = 560
Theme.MinScale = 0.75
Theme.MaxScale = 1.5
Theme.MinTouchSize = 44

function Theme.corner(parent: Instance, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 14)
	corner.Parent = parent
end

function Theme.stroke(parent: Instance, thickness: number?, color: Color3?)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 3
	stroke.Color = color or Theme.Colors.Outline
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

function Theme.text(name: string, text: string, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Theme.Font
	label.Text = text
	label.TextColor3 = Theme.Colors.Text
	label.TextScaled = true
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Theme.Colors.Outline
	stroke.Parent = label
	label.Parent = parent
	return label
end

-- Keeps a ScreenGui readable from phones to monitors.
function Theme.autoScale(gui: ScreenGui)
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local camera = workspace.CurrentCamera
	local function update()
		local height = camera.ViewportSize.Y
		scale.Scale = math.clamp(height / Theme.ReferenceHeight, Theme.MinScale, Theme.MaxScale)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	update()
end

return table.freeze(Theme)
