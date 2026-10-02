--!strict
--[[
	SoundController
	Hooks game events to sounds (all local): buying, hatching, growing up, collecting,
	bonks, traps, thefts, night falling and sunrise.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tags = require(Shared:WaitForChild("Tags"))
local Sounds = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Sounds"))

local SoundController = {}

local player = Players.LocalPlayer
local lastCoins = 0

function SoundController.init() end

function SoundController.start()
	local coins = player:GetAttribute("Coins")
	lastCoins = if typeof(coins) == "number" then coins else 0
	player:GetAttributeChangedSignal("Coins"):Connect(function()
		local value = player:GetAttribute("Coins")
		if typeof(value) == "number" then
			if value > lastCoins then
				Sounds.play("Collect")
			end
			lastCoins = value
		end
	end)
	CollectionService:GetInstanceAddedSignal(Tags.Creature):Connect(function(model: Instance)
		if model:GetAttribute("OwnerUserId") ~= player.UserId then
			return
		end
		local changedAt = model:GetAttribute("StageChangedAt")
		if typeof(changedAt) ~= "number" or Workspace:GetServerTimeNow() - changedAt > 2 then
			return
		end
		local stage = model:GetAttribute("Stage")
		Sounds.play(if stage == "Egg" then "Buy" elseif stage == "Baby" then "Hatch" else "GrowUp")
	end)
	Remotes.event("BatHit").OnClientEvent:Connect(function(position: any)
		if typeof(position) == "Vector3" then
			Sounds.playAt("Bonk", position)
		end
	end)
	Remotes.event("TrapSprung").OnClientEvent:Connect(function(trapType: any, position: any)
		if typeof(position) == "Vector3" then
			Sounds.playAt(if trapType == "HonkEgg" then "Honk" else "Slip", position)
		end
	end)
	Remotes.event("TheftAnnounced").OnClientEvent:Connect(function()
		Sounds.play("Theft")
	end)
	Remotes.event("HonkAlert").OnClientEvent:Connect(function()
		Sounds.play("Honk")
	end)
	Remotes.event("Notify").OnClientEvent:Connect(function(_message: any, kind: any)
		if kind == "warning" then
			Sounds.play("Warning")
		end
	end)
	player:GetAttributeChangedSignal("Carrying"):Connect(function()
		if player:GetAttribute("Carrying") ~= nil then
			Sounds.play("Steal")
		end
	end)
	Workspace:GetAttributeChangedSignal("CyclePhase"):Connect(function()
		Sounds.play(if Workspace:GetAttribute("CyclePhase") == "Night" then "Night" else "Day")
	end)
end

return SoundController
