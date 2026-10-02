--!strict
--[[
	CreatureController
	Client-side life for every creature on a pedestal (models tagged "Creature"):
	  * a floating label with its name and status (hatch / grow timers, income),
	  * a gentle idle bob and sway, and an egg wobble right before hatching,
	  * a sparkle burst and a little hop when it is placed, hatches or grows up.
	All of this is local to this client and never replicates. Timers use the
	server clock so every player sees the same countdown.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Economy = require(Shared:WaitForChild("Economy"))
local Growth = require(Shared:WaitForChild("Growth"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Tags = require(Shared:WaitForChild("Tags"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type Tracked = {
	model: Model,
	root: BasePart,
	homePivot: CFrame,
	pivotOffset: CFrame,
	phase: number,
	gui: BillboardGui,
	status: TextLabel,
	creatureId: string,
	hopUntil: number,
}

local CreatureController = {}

local player = Players.LocalPlayer
local ANIMATE_DISTANCE = 80
local HOP_SECONDS = 0.45
local LABEL_REFRESH_SEC = 0.25

local tracked: { [Model]: Tracked } = {}
local labelFolder: Folder

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function statusText(model: Model, creatureId: string): string
	local stage = model:GetAttribute("Stage")
	local plantedAt = model:GetAttribute("PlantedAt")
	local growTime = model:GetAttribute("GrowTimeSec")
	if stage == "Adult" then
		local mutation = model:GetAttribute("Mutation")
		return `💰 +{Format.short(
			Economy.incomePerSec(creatureId, if typeof(mutation) == "string" then mutation else nil)
		)}/s`
	end
	if typeof(plantedAt) ~= "number" or typeof(growTime) ~= "number" then
		return ""
	end
	local remaining = Growth.secondsToNextStage(growTime, plantedAt, serverNow()) or 0
	if stage == "Egg" then
		return `🥚 Hatches in {Format.clock(math.ceil(remaining))}`
	end
	return `🌱 Grows up in {Format.clock(math.ceil(remaining))}`
end

local function burst(root: BasePart, color: Color3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.7, 0)
	emitter.Speed = NumberRange.new(6, 11)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Drag = 3
	emitter.Rate = 0
	emitter.Parent = root
	emitter:Emit(30)
	Debris:AddItem(emitter, 2)
end

local function makeLabel(root: BasePart, name: string, color: Color3, dark: Color3): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CreatureLabel"
	gui.Adornee = root
	gui.Size = UDim2.fromOffset(170, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, root.Size.Y / 2 + 1.3, 0)
	gui.MaxDistance = 45
	gui.LightInfluence = 0
	gui.Parent = labelFolder
	local title = Theme.text("CreatureName", name, gui)
	title.Size = UDim2.fromScale(1, 0.5)
	title.TextColor3 = color
	local titleStroke = title:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Color = dark
	end
	local status = Theme.text("Status", "", gui)
	status.Position = UDim2.fromScale(0, 0.5)
	status.Size = UDim2.fromScale(1, 0.5)
	return gui, status
end

local function track(instance: Instance)
	if not instance:IsA("Model") or tracked[instance :: Model] then
		return
	end
	local model = instance :: Model
	local root = model.PrimaryPart or model:WaitForChild("Root", 5)
	if not root or not root:IsA("BasePart") or not model.Parent then
		return
	end
	local rootPart = root :: BasePart
	local creatureId = model:GetAttribute("CreatureId")
	local def = if typeof(creatureId) == "string" then CreatureData.get(creatureId) else nil
	if not def then
		return
	end
	local rarity = Rarity.get(def.rarity)
	local gui, status = makeLabel(rootPart, def.displayName, rarity.color, rarity.dark)
	local entry: Tracked = {
		model = model,
		root = rootPart,
		homePivot = rootPart.CFrame * rootPart.PivotOffset,
		pivotOffset = rootPart.PivotOffset,
		phase = math.random() * math.pi * 2,
		gui = gui,
		status = status,
		creatureId = def.id,
		hopUntil = 0,
	}
	tracked[model] = entry
	status.Text = statusText(model, def.id)
	local changedAt = model:GetAttribute("StageChangedAt")
	if typeof(changedAt) == "number" and serverNow() - changedAt < 2 then
		burst(rootPart, rarity.color)
		entry.hopUntil = os.clock() + HOP_SECONDS
	end
end

local function untrack(instance: Instance)
	local entry = tracked[instance :: Model]
	if entry then
		entry.gui:Destroy()
		tracked[instance :: Model] = nil
	end
end

local function animate()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPos = camera.CFrame.Position
	local clock = os.clock()
	local now = serverNow()
	for _, entry in tracked do
		local root = entry.root
		-- Carried or otherwise unanchored creatures are moved by physics, not by us.
		if not root.Anchored or (entry.homePivot.Position - cameraPos).Magnitude > ANIMATE_DISTANCE then
			continue
		end
		local stage = entry.model:GetAttribute("Stage")
		local offset = CFrame.identity
		if entry.hopUntil > clock then
			local t = 1 - (entry.hopUntil - clock) / HOP_SECONDS
			offset = CFrame.new(0, math.sin(t * math.pi) * 1.2, 0)
		elseif stage == "Egg" then
			local plantedAt = entry.model:GetAttribute("PlantedAt")
			local growTime = entry.model:GetAttribute("GrowTimeSec")
			local remaining = if typeof(plantedAt) == "number" and typeof(growTime) == "number"
				then Growth.secondsToNextStage(growTime, plantedAt, now) or 0
				else 99
			-- Eggs rock harder the closer they are to hatching.
			local intensity = if remaining < 6 then 0.12 else 0.025
			local speed = if remaining < 6 then 16 else 2
			offset = CFrame.Angles(0, 0, math.sin(clock * speed + entry.phase) * intensity)
		else
			local bob = math.abs(math.sin(clock * 2.4 + entry.phase)) * 0.22
			local sway = math.sin(clock * 0.9 + entry.phase) * 0.12
			offset = CFrame.new(0, bob, 0) * CFrame.Angles(0, sway, 0)
		end
		root.CFrame = entry.homePivot * offset * entry.pivotOffset:Inverse()
	end
end

function CreatureController.init()
	labelFolder = Instance.new("Folder")
	labelFolder.Name = "CreatureLabels"
	labelFolder.Parent = player:WaitForChild("PlayerGui")
end

function CreatureController.start()
	CollectionService:GetInstanceAddedSignal(Tags.Creature):Connect(function(instance: Instance)
		task.spawn(track, instance)
	end)
	CollectionService:GetInstanceRemovedSignal(Tags.Creature):Connect(untrack)
	for _, instance in CollectionService:GetTagged(Tags.Creature) do
		task.spawn(track, instance)
	end
	RunService.RenderStepped:Connect(animate)
	while true do
		task.wait(LABEL_REFRESH_SEC)
		for model, entry in tracked do
			if model.Parent then
				entry.status.Text = statusText(model, entry.creatureId)
			end
		end
	end
end

return CreatureController
