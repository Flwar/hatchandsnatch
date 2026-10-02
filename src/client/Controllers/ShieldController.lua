--!strict
--[[
	ShieldController
	Shields are solid only on each player's own machine. For every base this client
	decides: can I walk through? (my base, an empty base, an open shield on a base I
	may raid, or a revenge target). If not, the shield is solid and looks closed for
	me. The server separately teleports out anyone who sneaks past (exploits).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RaidState = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("RaidState"))

local ShieldController = {}

local player = Players.LocalPlayer
local CLOSED_TRANSPARENCY = 0.15

local function update(base: Instance)
	local shield = base:FindFirstChild("Shield")
	if not shield or not shield:IsA("BasePart") then
		return
	end
	local part = shield :: BasePart
	local ownerId = base:GetAttribute("OwnerUserId")
	local owner = if typeof(ownerId) == "number" then ownerId else 0
	local passable = owner == 0 or owner == player.UserId or RaidState.canRaid(owner)
	part.CanCollide = not passable
	local open = base:GetAttribute("ShieldOpen") == true
	if passable and open then
		part.Transparency = Config.ShieldOpenTransparency
	elseif not passable then
		part.Transparency = CLOSED_TRANSPARENCY
	end
end

function ShieldController.init() end

function ShieldController.start()
	local map = Workspace:WaitForChild("Map", 60)
	local bases = if map then map:WaitForChild("Bases", 30) else nil
	if not bases then
		return
	end
	while true do
		for _, base in bases:GetChildren() do
			update(base)
		end
		task.wait(0.3)
	end
end

return ShieldController
