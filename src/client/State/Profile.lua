--!strict
--[[
	Profile
	Fetches the summary of the player's saved data that menus need (discoveries,
	pedestals, traps, settings) through the rate-limited GetProfile remote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))

local Profile = {}

local cached: Types.ProfileSummary? = nil

-- Asks the server for a fresh summary. Returns the cached one if the call fails.
function Profile.fetch(): Types.ProfileSummary?
	local ok, result = pcall(function()
		return Remotes.func("GetProfile"):InvokeServer()
	end)
	if ok and type(result) == "table" then
		cached = result :: Types.ProfileSummary
	end
	return cached
end

function Profile.cached(): Types.ProfileSummary?
	return cached
end

return Profile
