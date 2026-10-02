--!strict
--[[
	ArenaController
	  * the lobby arena desk's prompt opens the Arena window
	  * queue updates and battle reports from the server (the battle plays back in
	    UI/BattleView)
	  * arena rank titles over every player's head ("🥈 Silver Slugger"), from the
	    ArenaRank player attribute the server sets
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tags = require(Shared:WaitForChild("Tags"))
local UI = script.Parent.Parent:WaitForChild("UI")
local BattleView = require(UI:WaitForChild("BattleView"))
local Theme = require(UI:WaitForChild("Theme"))
local Window = require(UI:WaitForChild("Window"))
local Arena = require(script.Parent.Parent:WaitForChild("Screens"):WaitForChild("Arena"))

local ArenaController = {}

local RANK_COLORS = {
	Color3.fromRGB(214, 140, 80),
	Color3.fromRGB(206, 214, 228),
	Color3.fromRGB(255, 204, 60),
	Color3.fromRGB(120, 230, 255),
}

local function updateTitle(target: Player)
	local character = target.Character
	local head = if character then character:FindFirstChild("Head") else nil
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = head:FindFirstChild("ArenaTitle")
	if old then
		old:Destroy()
	end
	local rank = target:GetAttribute("ArenaRank")
	local tier = if typeof(rank) == "number" then Config.ArenaRanks[rank] else nil
	if not tier then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "ArenaTitle"
	gui.Size = UDim2.fromOffset(200, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = head
	local label = Theme.text("Title", `{tier.icon} {tier.title}`, gui)
	label.Size = UDim2.fromScale(1, 1)
	label.TextColor3 = RANK_COLORS[rank :: number] or Theme.Colors.Text
end

local function watchPlayer(target: Player)
	target.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Head", 10)
		updateTitle(target)
	end)
	target:GetAttributeChangedSignal("ArenaRank"):Connect(function()
		updateTitle(target)
	end)
	if target.Character then
		task.spawn(updateTitle, target)
	end
end

function ArenaController.init() end

function ArenaController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if CollectionService:HasTag(prompt, Tags.ArenaPrompt) then
			Arena.open()
		end
	end)
	Remotes.event("ArenaQueued").OnClientEvent:Connect(function(waitSec: any)
		if type(waitSec) == "number" then
			Arena.setQueued(waitSec)
		end
	end)
	Remotes.event("BattleStarted").OnClientEvent:Connect(function(report: any)
		if type(report) ~= "table" or type(report.events) ~= "table" or type(report.fighters) ~= "table" then
			return
		end
		Arena.clearQueue()
		if Window.isOpen("Arena") then
			Window.close()
		end
		BattleView.play(report)
	end)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
end

return ArenaController
