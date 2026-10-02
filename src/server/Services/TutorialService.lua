--!strict
--[[
	TutorialService
	Server side of the 4-step onboarding. The current step lives in the player's data
	(tutorialStep) and is mirrored to the "TutorialStep" player attribute, which the
	client turns into an arrow and a hint. Steps advance on real actions:

	  1  buy an egg from the conveyor   -> advances when a creature is added
	  2  watch it on your pedestal       -> advances when one hatches
	  3  collect coins from your pad     -> advances on the first collect
	  4  a note about night raids        -> advances when the client says "Got it"
	  5  done
]]

local Players = game:GetService("Players")

local DataService = require(script.Parent:WaitForChild("DataService"))
local CreatureService = require(script.Parent:WaitForChild("CreatureService"))
local IncomeService = require(script.Parent:WaitForChild("IncomeService"))
local Net = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Net"))

local TutorialService = {}

local DONE = 5

local function setStep(player: Player, step: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.tutorialStep = step
	player:SetAttribute("TutorialStep", step)
end

-- Moves the player from `fromStep` to the next one (ignored if they are elsewhere).
local function advance(player: Player, fromStep: number)
	local data = DataService.get(player)
	if data and data.tutorialStep == fromStep then
		setStep(player, fromStep + 1)
	end
end

function TutorialService.init() end

function TutorialService.start()
	DataService.Loaded:connect(function(player: Player, data: any)
		-- Returning players who already own creatures skip the basics.
		if data.tutorialStep < 3 and #data.creatures > 0 then
			data.tutorialStep = 3
		end
		player:SetAttribute("TutorialStep", data.tutorialStep)
	end)
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data then
			player:SetAttribute("TutorialStep", data.tutorialStep)
		end
	end
	CreatureService.Added:connect(function(player: Player)
		advance(player, 1)
	end)
	CreatureService.StageChanged:connect(function(player: Player, _record: any, stage: string)
		if stage == "Baby" then
			advance(player, 2)
		end
	end)
	IncomeService.Collected:connect(function(player: Player)
		advance(player, 3)
	end)
	Net.onEvent("TutorialAck", {}, function(player: Player)
		local data = DataService.get(player)
		if data and data.tutorialStep == 4 then
			setStep(player, DONE)
		end
	end)
end

return TutorialService
