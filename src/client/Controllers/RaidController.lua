--!strict
--[[
	RaidController
	Client side of night raids:
	  * shows "Steal" prompts only when the server would allow the steal,
	  * shows a revenge marker over your thief's head while the window is open,
	  * announces every theft in the server with a banner,
	  * highlights a raider for a few seconds when your Honk Egg goes off,
	  * reminds you to run home while carrying a creature.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tags = require(Shared:WaitForChild("Tags"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Banner = require(UI:WaitForChild("Banner"))
local Theme = require(UI:WaitForChild("Theme"))
local RaidState = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("RaidState"))

local RaidController = {}

local player = Players.LocalPlayer
local markers: { [number]: BillboardGui } = {}

local function updateStealPrompts()
	local carrying = player:GetAttribute("Carrying") ~= nil
	for _, instance in CollectionService:GetTagged(Tags.StealPrompt) do
		if instance:IsA("ProximityPrompt") then
			local prompt = instance :: ProximityPrompt
			local ownerId = prompt:GetAttribute("OwnerUserId")
			local model = prompt.Parent and prompt.Parent.Parent
			local locked = model ~= nil and model:GetAttribute("Locked") == true
			prompt.Enabled = typeof(ownerId) == "number" and not carrying and not locked and RaidState.canRaid(ownerId)
		end
	end
end

local function refreshMarker(thiefId: number)
	local existing = markers[thiefId]
	if existing then
		existing:Destroy()
		markers[thiefId] = nil
	end
	if not RaidState.hasRevenge(thiefId) then
		return
	end
	local thief = Players:GetPlayerByUserId(thiefId)
	local character = if thief then thief.Character else nil
	local head = if character then character:FindFirstChild("Head") else nil
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "RevengeMarker"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(190, 48)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 2000
	gui.Parent = player:WaitForChild("PlayerGui")
	local label = Theme.text("Label", "🎯 REVENGE", gui)
	label.Size = UDim2.fromScale(1, 1)
	label.TextColor3 = Color3.fromRGB(255, 90, 90)
	markers[thiefId] = gui
end

local function tickMarkers()
	local now = Workspace:GetServerTimeNow()
	for thiefId, untilTime in RaidState.revengeUntil do
		local gui = markers[thiefId]
		if untilTime <= now then
			RaidState.revengeUntil[thiefId] = nil
			if gui then
				gui:Destroy()
				markers[thiefId] = nil
			end
		else
			if not gui or not gui.Adornee or not gui.Adornee.Parent then
				refreshMarker(thiefId)
				gui = markers[thiefId]
			end
			local label = if gui then gui:FindFirstChild("Label") else nil
			if label and label:IsA("TextLabel") then
				(label :: TextLabel).Text = `🎯 REVENGE {Format.clock(math.ceil(untilTime - now))}`
			end
		end
	end
end

local function highlight(raiderId: number)
	local raider = Players:GetPlayerByUserId(raiderId)
	local character = if raider then raider.Character else nil
	if not character then
		return
	end
	local glow = Instance.new("Highlight")
	glow.FillColor = Color3.fromRGB(255, 80, 80)
	glow.OutlineColor = Color3.fromRGB(255, 255, 255)
	glow.FillTransparency = 0.4
	glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	glow.Adornee = character
	glow.Parent = player:WaitForChild("PlayerGui")
	task.delay(Config.HonkHighlightSec, function()
		glow:Destroy()
	end)
end

function RaidController.init() end

function RaidController.start()
	Remotes.event("TheftAnnounced").OnClientEvent:Connect(function(thief: any, victim: any, rarity: any, creature: any)
		if type(thief) ~= "string" or type(victim) ~= "string" or type(creature) ~= "string" then
			return
		end
		local tier = if Rarity.isValid(rarity) then rarity :: string else ""
		local color = if tier ~= "" then Rarity.get(tier).color else Theme.Colors.Warning
		Banner.show(`{thief} stole a {tier} {creature}!`, `from {victim}`, color, 4)
	end)
	Remotes.event("RevengeStarted").OnClientEvent:Connect(function(thiefId: any, expiresAt: any)
		if type(thiefId) == "number" and type(expiresAt) == "number" then
			RaidState.revengeUntil[thiefId] = expiresAt
			refreshMarker(thiefId)
			local thief = Players:GetPlayerByUserId(thiefId)
			Banner.show(
				"🎯 Revenge time!",
				`Raid {if thief then thief.DisplayName else "the thief"} within {Format.clock(Config.RevengeWindowSec)}, even by day!`,
				Color3.fromRGB(255, 90, 90),
				5
			)
		end
	end)
	Remotes.event("HonkAlert").OnClientEvent:Connect(function(raiderId: any)
		if type(raiderId) == "number" then
			highlight(raiderId)
		end
	end)
	player:GetAttributeChangedSignal("Carrying"):Connect(function()
		if player:GetAttribute("Carrying") ~= nil then
			Banner.show(
				"🏃 Run home!",
				"Get it to a free pedestal in your base before you get bonked!",
				Theme.Colors.Coin,
				3
			)
		end
	end)
	while true do
		updateStealPrompts()
		tickMarkers()
		task.wait(0.3)
	end
end

return RaidController
