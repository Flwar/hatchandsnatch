--!strict
--[[
	PromptController
	Some ProximityPrompts are only for one player (selling your creature, unlocking
	your next pedestal). The server tags them "OwnerOnlyPrompt" with an OwnerUserId
	attribute; this hides them locally for everyone else. The server still checks
	ownership when a prompt fires, so hiding is only about a clean screen.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Tags"))

local PromptController = {}

local player = Players.LocalPlayer

local function apply(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		local prompt = instance :: ProximityPrompt
		prompt.Enabled = prompt:GetAttribute("OwnerUserId") == player.UserId
	end
end

local function watch(instance: Instance)
	apply(instance)
	instance:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		apply(instance)
	end)
end

function PromptController.init() end

function PromptController.start()
	CollectionService:GetInstanceAddedSignal(Tags.OwnerOnlyPrompt):Connect(watch)
	for _, instance in CollectionService:GetTagged(Tags.OwnerOnlyPrompt) do
		watch(instance)
	end
end

return PromptController
