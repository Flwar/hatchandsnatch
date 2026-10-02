--!strict
--[[
	WeatherController
	Shows the server's weather event (Workspace attributes Weather / WeatherEndsAt):

	  * a banner and sound when it starts, and a HUD chip with a countdown
	  * a screen tint (its own ColorCorrection under the camera, so it layers on top
	    of the day/night look without fighting CycleController)
	  * falling particles around the camera: rain, golden sparkles, snow or glitter
	  * lightning flashes and thunder during a storm
	  * a huge rainbow in the sky during Rainbow, always in the same direction
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local Weather = require(Shared:WaitForChild("Weather"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local ModelKit = require(Shared:WaitForChild("Models"):WaitForChild("ModelKit"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Banner = require(UI:WaitForChild("Banner"))
local Sounds = require(UI:WaitForChild("Sounds"))
local Theme = require(UI:WaitForChild("Theme"))

local WeatherController = {}

local player = Players.LocalPlayer

type Style = {
	texture: string,
	colors: ColorSequence,
	rate: number,
	speed: number,
	size: number,
	lifetime: number,
	squash: number,
	brightness: number,
	saturation: number,
}

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local SOFT = "rbxasset://textures/particles/smoke_main.dds"

local STYLES: { [string]: Style } = {
	GoldenRain = {
		texture = SPARKLES,
		colors = ColorSequence.new(Color3.fromRGB(255, 226, 110), Color3.fromRGB(255, 186, 40)),
		rate = 70,
		speed = 16,
		size = 0.7,
		lifetime = 4,
		squash = 0,
		brightness = 0.04,
		saturation = 0.1,
	},
	LightningStorm = {
		texture = SOFT,
		colors = ColorSequence.new(Color3.fromRGB(196, 214, 255)),
		rate = 450,
		speed = 95,
		size = 0.18,
		lifetime = 1.1,
		squash = -2.6,
		brightness = -0.1,
		saturation = -0.15,
	},
	Frost = {
		texture = SOFT,
		colors = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
		rate = 160,
		speed = 6,
		size = 0.35,
		lifetime = 9,
		squash = 0,
		brightness = 0.03,
		saturation = -0.25,
	},
	Rainbow = {
		texture = SPARKLES,
		colors = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 96, 96)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 226, 80)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(96, 230, 140)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 160, 255)),
		}),
		rate = 50,
		speed = 7,
		size = 0.5,
		lifetime = 6,
		squash = 0,
		brightness = 0.04,
		saturation = 0.25,
	},
}

local RAINBOW_DIRECTION = Vector3.new(0.8, 0, 0.6).Unit
local RAINBOW_DISTANCE = 420

local chip: Frame
local chipLabel: TextLabel
local tint: ColorCorrectionEffect
local emitterPart: Part
local emitter: ParticleEmitter
local rainbow: Model? = nil
local active: string = ""
local flashToken = 0

local function buildHud()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Weather"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	Theme.autoScale(gui)
	chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.AnchorPoint = Vector2.new(1, 0)
	chip.Position = UDim2.new(1, -12, 0, 62)
	chip.Size = UDim2.fromOffset(250, 40)
	chip.BackgroundColor3 = Theme.Colors.Panel
	chip.Visible = false
	chip.Parent = gui
	Theme.corner(chip, 12)
	Theme.stroke(chip, 2)
	chipLabel = Theme.text("Label", "", chip)
	chipLabel.Position = UDim2.fromOffset(10, 5)
	chipLabel.Size = UDim2.new(1, -20, 1, -10)
end

local function buildEffects()
	local camera = Workspace.CurrentCamera
	tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "WeatherTint"
	tint.Parent = camera
	emitterPart = Instance.new("Part")
	emitterPart.Name = "WeatherEmitter"
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(150, 1, 150)
	emitterPart.Parent = camera
	emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.LightEmission = 0.4
	emitter.SpreadAngle = Vector2.new(6, 6)
	emitter.Parent = emitterPart
end

-- A rainbow made of glowing bands, built once and shown only during Rainbow.
local function getRainbow(): Model
	if rainbow then
		return rainbow
	end
	local model = Instance.new("Model")
	model.Name = "Rainbow"
	local bands = {
		Color3.fromRGB(255, 80, 80),
		Color3.fromRGB(255, 160, 60),
		Color3.fromRGB(255, 230, 80),
		Color3.fromRGB(90, 220, 110),
		Color3.fromRGB(80, 160, 255),
		Color3.fromRGB(170, 100, 255),
	}
	local segments = 18
	for band, color in bands do
		local radius = 260 - (band - 1) * 9
		for i = 0, segments - 1 do
			local a0, a1 = i * math.pi / segments, (i + 1) * math.pi / segments
			local p0 = Vector3.new(math.cos(a0) * radius, math.sin(a0) * radius, 0)
			local p1 = Vector3.new(math.cos(a1) * radius, math.sin(a1) * radius, 0)
			local cf, length = ModelKit.between(p0, p1)
			ModelKit.part("Band", "Cylinder", Vector3.new(length + 1, 9, 9), cf, color, model, {
				material = Enum.Material.Neon,
				transparency = 0.45,
				castShadow = false,
			})
		end
	end
	model.WorldPivot = CFrame.identity -- the middle of the arc, on the ground
	rainbow = model
	return model
end

local function flashes(token: number)
	while flashToken == token and active == "LightningStorm" do
		task.wait(math.random(30, 80) / 10)
		if flashToken ~= token or active ~= "LightningStorm" then
			break
		end
		local base = tint.Brightness
		tint.Brightness = base + 0.55
		TweenService:Create(tint, TweenInfo.new(0.35), { Brightness = base }):Play()
		task.delay(0.25 + math.random() * 0.6, Sounds.play, "Thunder")
	end
end

local function apply(id: string)
	if id == active then
		return
	end
	active = id
	flashToken += 1
	local event = Weather.get(id)
	local style = STYLES[id]
	local info = TweenInfo.new(2.5, Enum.EasingStyle.Sine)
	if not event or not style then
		emitter.Enabled = false
		chip.Visible = false
		TweenService:Create(tint, info, {
			TintColor = Color3.new(1, 1, 1),
			Brightness = 0,
			Saturation = 0,
		}):Play()
		if rainbow then
			rainbow.Parent = nil
		end
		return
	end
	TweenService:Create(tint, info, {
		TintColor = event.tint,
		Brightness = style.brightness,
		Saturation = style.saturation,
	}):Play()
	emitter.Texture = style.texture
	emitter.Color = style.colors
	emitter.Rate = style.rate
	emitter.Speed = NumberRange.new(style.speed * 0.8, style.speed * 1.2)
	emitter.Size = NumberSequence.new(style.size)
	emitter.Lifetime = NumberRange.new(style.lifetime * 0.8, style.lifetime)
	emitter.Squash = NumberSequence.new(style.squash)
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.Enabled = true
	chip.Visible = true
	local stroke = chip:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = event.color
	end
	chipLabel.TextColor3 = event.color
	if id == "Rainbow" then
		getRainbow().Parent = Workspace.CurrentCamera
	elseif rainbow then
		rainbow.Parent = nil
	end
	if id == "LightningStorm" then
		task.spawn(flashes, flashToken)
	end
	Sounds.play("Weather")
	Banner.show(
		`{event.icon} {string.upper(event.name)}!`,
		`Growing creatures can turn {event.mutation} for x{Economy.mutationMultiplier(event.mutation)} income!`,
		event.color,
		5
	)
end

local function update()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local position = camera.CFrame.Position
	if emitter.Enabled then
		emitterPart.CFrame = CFrame.new(position + Vector3.new(0, 45, 0))
	end
	local model = rainbow
	if model and model.Parent then
		local center = Vector3.new(position.X, -30, position.Z) + RAINBOW_DIRECTION * RAINBOW_DISTANCE
		model:PivotTo(CFrame.lookAt(center, Vector3.new(position.X, -30, position.Z)))
	end
	if chip.Visible then
		local event = Weather.get(active)
		local endsAt = Workspace:GetAttribute("WeatherEndsAt")
		local left = if typeof(endsAt) == "number" then math.max(0, endsAt - Workspace:GetServerTimeNow()) else 0
		if event then
			chipLabel.Text = `{event.icon} {event.name} {Format.clock(left)}`
		end
	end
end

function WeatherController.init()
	buildHud()
	buildEffects()
end

function WeatherController.start()
	local function refresh()
		local id = Workspace:GetAttribute("Weather")
		apply(if typeof(id) == "string" then id else "")
	end
	Workspace:GetAttributeChangedSignal("Weather"):Connect(refresh)
	refresh()
	RunService.RenderStepped:Connect(update)
end

return WeatherController
