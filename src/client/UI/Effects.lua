--!strict
--[[
	Effects
	Little local-only juice: comic pop-up words ("BONK!", "HONK!") and sparkle
	bursts at a world position. Nothing here replicates.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent:WaitForChild("Theme"))

local Effects = {}

local function anchorAt(position: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	return attachment
end

function Effects.burst(position: Vector3, color: Color3, count: number?)
	local attachment = anchorAt(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.8, 0)
	emitter.Speed = NumberRange.new(8, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Drag = 4
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count or 24)
	Debris:AddItem(attachment, 2)
end

-- A comic-book word that pops up and floats away.
function Effects.popText(position: Vector3, text: string, color: Color3)
	local attachment = anchorAt(position + Vector3.new(0, 2, 0))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 70)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Adornee = attachment
	gui.Parent = attachment
	local label = Theme.text("Word", text, gui)
	label.Size = UDim2.fromScale(1, 1)
	label.TextColor3 = color
	label.Rotation = math.random(-12, 12)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	TweenService:Create(gui, TweenInfo.new(0.9), { StudsOffsetWorldSpace = Vector3.new(0, 3, 0) }):Play()
	task.delay(0.6, function()
		TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	end)
	Debris:AddItem(attachment, 1.2)
end

return table.freeze(Effects)
