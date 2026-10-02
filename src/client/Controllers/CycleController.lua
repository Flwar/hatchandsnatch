--!strict
--[[
	CycleController
	Shows the day/night timer ("Night in 2:31" / "Sunrise in 0:45") and smoothly
	tweens this client's Lighting between the day and night presets whenever the
	server's phase (Workspace attribute "CyclePhase") changes.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local CycleController = {}

local player = Players.LocalPlayer

type Preset = {
	clock: number,
	lighting: { [string]: any },
	atmosphere: { [string]: any },
	color: { [string]: any },
}

local PRESETS: { [string]: Preset } = {
	Day = {
		clock = 14.2,
		lighting = {
			Brightness = 2.6,
			Ambient = Color3.new(0.36, 0.36, 0.42),
			OutdoorAmbient = Color3.new(0.52, 0.52, 0.58),
			ExposureCompensation = 0.1,
		},
		atmosphere = { Density = 0.28, Color = Color3.new(0.78, 0.86, 1), Decay = Color3.new(0.55, 0.62, 0.78) },
		color = { TintColor = Color3.new(1, 1, 1), Saturation = 0.16, Contrast = 0.08 },
	},
	Night = {
		clock = 22.6,
		lighting = {
			Brightness = 1.2,
			Ambient = Color3.new(0.17, 0.18, 0.32),
			OutdoorAmbient = Color3.new(0.24, 0.26, 0.44),
			ExposureCompensation = -0.05,
		},
		atmosphere = { Density = 0.36, Color = Color3.new(0.3, 0.34, 0.56), Decay = Color3.new(0.18, 0.2, 0.36) },
		color = { TintColor = Color3.new(0.86, 0.9, 1), Saturation = 0.05, Contrast = 0.12 },
	},
}

local label: TextLabel
local pill: Frame
local clockValue = Instance.new("NumberValue")

local function applyPreset(phase: string, instant: boolean)
	local preset = PRESETS[phase] or PRESETS.Day
	local info = TweenInfo.new(if instant then 0 else Config.LightingTweenSec, Enum.EasingStyle.Sine)
	-- ClockTime always moves forward, wrapping past midnight.
	local target = preset.clock
	while target <= clockValue.Value do
		target += 24
	end
	if instant then
		clockValue.Value = preset.clock
	else
		TweenService:Create(clockValue, info, { Value = target }):Play()
	end
	TweenService:Create(Lighting, info, preset.lighting):Play()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, info, preset.atmosphere):Play()
	end
	local correction = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if correction then
		TweenService:Create(correction, info, preset.color):Play()
	end
end

local function updateTimer()
	local phase = Workspace:GetAttribute("CyclePhase")
	local endsAt = Workspace:GetAttribute("CyclePhaseEndsAt")
	if typeof(endsAt) ~= "number" then
		return
	end
	local remaining = Format.clock(math.ceil(endsAt - Workspace:GetServerTimeNow()))
	if phase == "Night" then
		label.Text = `☀️ Sunrise in {remaining}`
		pill.BackgroundColor3 = Color3.fromRGB(30, 34, 80)
	else
		label.Text = `🌙 Night in {remaining}`
		pill.BackgroundColor3 = Theme.Colors.Panel
	end
end

function CycleController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CycleHud"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	Theme.autoScale(gui)
	pill = Instance.new("Frame")
	pill.Name = "Timer"
	pill.AnchorPoint = Vector2.new(1, 0)
	pill.Position = UDim2.new(1, -12, 0, 10)
	pill.Size = UDim2.fromOffset(210, 44)
	pill.BackgroundColor3 = Theme.Colors.Panel
	pill.Parent = gui
	Theme.corner(pill, 22)
	Theme.stroke(pill, 3)
	label = Theme.text("Label", "", pill)
	label.Position = UDim2.fromOffset(10, 6)
	label.Size = UDim2.new(1, -20, 1, -12)
	clockValue.Value = Lighting.ClockTime
	clockValue.Changed:Connect(function(value: number)
		Lighting.ClockTime = value % 24
	end)
end

function CycleController.start()
	local phase = Workspace:GetAttribute("CyclePhase")
	applyPreset(if typeof(phase) == "string" then phase else "Day", true)
	Workspace:GetAttributeChangedSignal("CyclePhase"):Connect(function()
		local newPhase = Workspace:GetAttribute("CyclePhase")
		applyPreset(if typeof(newPhase) == "string" then newPhase else "Day", false)
	end)
	while true do
		updateTimer()
		task.wait(0.25)
	end
end

return CycleController
