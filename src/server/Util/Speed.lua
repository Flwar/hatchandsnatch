--!strict
--[[
	Speed
	Several systems slow players down at once (carrying a creature, sticky floor).
	Each sets a named modifier; the player's WalkSpeed is always the slowest active
	one, so effects never fight each other or forget to restore speed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Speed = {}

local modifiers: { [Player]: { [string]: number? } } = {}

function Speed.apply(player: Player)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid then
		return
	end
	local speed = Config.DefaultWalkSpeed
	local perPlayer = modifiers[player]
	if perPlayer then
		for _, value in perPlayer do
			if value then
				speed = math.min(speed, value)
			end
		end
	end
	humanoid.WalkSpeed = speed
end

-- Sets (or clears, with nil) one named speed limit for a player.
function Speed.set(player: Player, key: string, walkSpeed: number?)
	local perPlayer = modifiers[player]
	if not perPlayer then
		perPlayer = {}
		modifiers[player] = perPlayer
	end
	perPlayer[key] = walkSpeed
	Speed.apply(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	modifiers[player] = nil
end)

return table.freeze(Speed)
