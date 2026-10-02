--!strict
--[[
	CycleService
	The server's single day/night cycle: Day for Config.DayLengthSec, then Night for
	Config.NightLengthSec, forever. The current phase and when it ends (server time)
	are published as Workspace attributes "CyclePhase" and "CyclePhaseEndsAt", so
	every client shows the same "Night in 2:31" timer and tweens its own lighting.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Ticker = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ticker"))

export type Phase = "Day" | "Night"

local CycleService = {}

-- Fired as (phase) whenever the phase flips.
CycleService.PhaseChanged = Signal.new()

local phase: Phase = "Day"
local endsAt = 0

local function setPhase(newPhase: Phase)
	phase = newPhase
	local length = if newPhase == "Night" then Config.NightLengthSec else Config.DayLengthSec
	endsAt = Workspace:GetServerTimeNow() + length
	Workspace:SetAttribute("CyclePhase", phase)
	Workspace:SetAttribute("CyclePhaseEndsAt", endsAt)
	CycleService.PhaseChanged:fire(phase)
end

function CycleService.phase(): Phase
	return phase
end

function CycleService.isNight(): boolean
	return phase == "Night"
end

function CycleService.secondsLeft(): number
	return math.max(0, endsAt - Workspace:GetServerTimeNow())
end

function CycleService.init()
	phase = if Config.Debug.StartAtNight then "Night" else "Day"
	local length = if phase == "Night" then Config.NightLengthSec else Config.DayLengthSec
	endsAt = Workspace:GetServerTimeNow() + length
	Workspace:SetAttribute("CyclePhase", phase)
	Workspace:SetAttribute("CyclePhaseEndsAt", endsAt)
end

function CycleService.start()
	Ticker.every("Cycle", 0.25, function()
		if Workspace:GetServerTimeNow() >= endsAt then
			setPhase(if phase == "Day" then "Night" else "Day")
		end
	end)
end

return CycleService
