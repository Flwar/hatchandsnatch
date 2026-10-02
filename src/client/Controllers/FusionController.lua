--!strict
--[[
	FusionController
	Everything about Fusion Machines on this client:

	  * every machine's floating status ("Fusing... 0:42") and its reactor core,
	    which pulses and shifts color while fusing and glows steadily when ready
	  * opening the Fusion window when you press your own machine's prompt
	  * the reveal popup when your hybrid is born ("NEW DISCOVERY!" the first time)
	  * the server-wide "FIRST DISCOVERY!" banner when anyone finds a named recipe
]]

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Economy = require(Shared:WaitForChild("Economy"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tags = require(Shared:WaitForChild("Tags"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Banner = require(UI:WaitForChild("Banner"))
local Effects = require(UI:WaitForChild("Effects"))
local Popup = require(UI:WaitForChild("Popup"))
local Sounds = require(UI:WaitForChild("Sounds"))
local Window = require(UI:WaitForChild("Window"))
local Fusion = require(script.Parent.Parent:WaitForChild("Screens"):WaitForChild("Fusion"))

local FusionController = {}

type Tracked = {
	machine: Model,
	core: BasePart?,
	beacon: BasePart?,
	status: TextLabel?,
	coreSize: Vector3,
}

local tracked: { [Model]: Tracked } = {}

local PINK = Color3.fromRGB(255, 92, 220)
local CYAN = Color3.fromRGB(110, 236, 255)
local GOLD = Color3.fromRGB(255, 214, 72)

local function find(machine: Model, path: { string }): Instance?
	local node: Instance? = machine
	for _, name in path do
		node = if node then node:FindFirstChild(name) else nil
	end
	return node
end

local function track(machine: Model)
	if tracked[machine] then
		return
	end
	local core = find(machine, { "Reactor", "Core" })
	local beacon = find(machine, { "Reactor", "Beacon" })
	local status = find(machine, { "Reactor", "Beacon", "StatusGui", "Status" })
	local corePart = if core and core:IsA("BasePart") then core :: BasePart else nil
	tracked[machine] = {
		machine = machine,
		core = corePart,
		beacon = if beacon and beacon:IsA("BasePart") then beacon :: BasePart else nil,
		status = if status and status:IsA("TextLabel") then status :: TextLabel else nil,
		coreSize = if corePart then corePart.Size else Vector3.one,
	}
	machine.Destroying:Connect(function()
		tracked[machine] = nil
	end)
	-- The owner's result pops out with a burst of sparkles.
	machine:GetAttributeChangedSignal("State"):Connect(function()
		local entry = tracked[machine]
		if entry and entry.core and machine:GetAttribute("State") == "Ready" then
			Effects.burst(entry.core.Position, GOLD)
		end
		if Window.isOpen("Fusion") and machine == Fusion.machine() then
			Fusion.open()
		end
	end)
end

local function scan()
	local map = Workspace:FindFirstChild("Map")
	local bases = if map then map:FindFirstChild("Bases") else nil
	if not bases then
		return
	end
	for _, base in bases:GetChildren() do
		local machine = base:FindFirstChild("FusionMachine")
		if machine and machine:IsA("Model") then
			track(machine :: Model)
		end
	end
end

local function animate()
	local now = Workspace:GetServerTimeNow()
	local t = os.clock()
	for machine, entry in tracked do
		local state = machine:GetAttribute("State")
		local core = entry.core
		if core then
			if state == "Fusing" then
				local pulse = 1 + math.sin(t * 6) * 0.18
				core.Size = entry.coreSize * pulse
				core.Color = PINK:Lerp(CYAN, (math.sin(t * 2.5) + 1) / 2)
			elseif state == "Ready" then
				core.Size = entry.coreSize * 0.7
				core.Color = GOLD
			else
				core.Size = entry.coreSize * (0.85 + math.sin(t * 1.5) * 0.05)
				core.Color = PINK
			end
		end
		if entry.beacon then
			entry.beacon.Transparency = if state == "Fusing" and math.floor(t * 3) % 2 == 0 then 0.6 else 0
		end
		local status = entry.status
		if status then
			if state == "Fusing" then
				local endsAt = machine:GetAttribute("FusionEndsAt")
				local left = if typeof(endsAt) == "number" then math.max(0, endsAt - now) else 0
				status.Text = `🧪 Fusing... {Format.clock(left)}`
			elseif state == "Ready" then
				local name = machine:GetAttribute("ResultName")
				status.Text = `✨ {if typeof(name) == "string" and name ~= "" then name else "Hybrid"} is ready!`
			else
				status.Text = "Fuse two adults!"
			end
		end
	end
end

local function onFusionDone(hybridId: any, isNew: any)
	if type(hybridId) ~= "string" then
		return
	end
	local def = CreatureData.get(hybridId)
	if not def then
		return
	end
	local rarity = Rarity.get(def.rarity)
	Sounds.play("Discovery")
	Popup.show({
		creatureId = hybridId,
		title = if isNew == true then `NEW: {def.displayName}!` else `{def.displayName}!`,
		titleColor = rarity.color,
		body = `{def.rarity} hybrid · 💰 {Format.short(Economy.incomePerSec(hybridId, nil))}/s\n{def.description}`,
		buttons = { { text = "Awesome!" } },
	})
end

local function onFirstDiscovery(hybridId: any, discoverer: any)
	if type(hybridId) ~= "string" or type(discoverer) ~= "string" then
		return
	end
	local def = CreatureData.get(hybridId)
	if not def then
		return
	end
	Sounds.play("Discovery")
	Banner.show(
		"🌟 FIRST DISCOVERY! 🌟",
		`{discoverer} is the first ever to make {def.displayName}!`,
		Rarity.get(def.rarity).color,
		6
	)
end

function FusionController.init() end

function FusionController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == "FusePrompt" and CollectionService:HasTag(prompt, Tags.OwnerOnlyPrompt) then
			Fusion.open()
		end
	end)
	Remotes.event("FusionDone").OnClientEvent:Connect(onFusionDone)
	Remotes.event("FirstDiscovery").OnClientEvent:Connect(onFirstDiscovery)
	RunService.RenderStepped:Connect(animate)
	local map = Workspace:WaitForChild("Map", 30)
	local bases = if map then map:WaitForChild("Bases", 30) else nil
	if bases then
		bases.DescendantAdded:Connect(function(instance: Instance)
			if instance.Name == "FusionMachine" and instance:IsA("Model") then
				track(instance :: Model)
			end
		end)
	end
	scan()
end

return FusionController
