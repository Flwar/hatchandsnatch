--!strict
--[[
	RaidState
	Client-side raid facts shared by controllers: who you currently have revenge on,
	and a helper that answers "may I raid this player right now?" using the same
	RaidRules as the server (the server still decides; this only drives UI).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RaidRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RaidRules"))

local RaidState = {}

local player = Players.LocalPlayer

-- revengeUntil[thiefUserId] = server time when the revenge window closes
RaidState.revengeUntil = {} :: { [number]: number }

function RaidState.isNight(): boolean
	return Workspace:GetAttribute("CyclePhase") == "Night"
end

function RaidState.hasRevenge(ownerUserId: number): boolean
	local untilTime = RaidState.revengeUntil[ownerUserId]
	return untilTime ~= nil and untilTime > Workspace:GetServerTimeNow()
end

local function numberAttribute(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

-- True if the local player may raid the base owned by `ownerUserId` right now.
function RaidState.canRaid(ownerUserId: number): boolean
	if ownerUserId == 0 or ownerUserId == player.UserId then
		return false
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	if not owner then
		return false
	end
	local allowed = RaidRules.canRaid({
		isNight = RaidState.isNight(),
		attackerValue = numberAttribute(player, "BaseValue"),
		victimValue = numberAttribute(owner, "BaseValue"),
		victimProtected = owner:GetAttribute("RaidProtected") == true,
		hasRevenge = RaidState.hasRevenge(ownerUserId),
	})
	return allowed
end

return RaidState
