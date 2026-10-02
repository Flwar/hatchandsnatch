--!strict
--[[
	Settings
	The player's settings on this client (sound effects, creature labels). Loaded
	from the server profile, saved back through the validated SaveSettings remote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Sounds = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Sounds"))

local Settings = {}

Settings.values = { sfx = true, labels = true }
-- Fired as (key, value) when a setting changes.
Settings.Changed = Signal.new()

local function apply()
	Sounds.enabled = Settings.values.sfx
end

function Settings.load(values: { sfx: boolean, labels: boolean })
	Settings.values.sfx = values.sfx
	Settings.values.labels = values.labels
	apply()
	Settings.Changed:fire("sfx", values.sfx)
	Settings.Changed:fire("labels", values.labels)
end

function Settings.set(key: "sfx" | "labels", value: boolean)
	Settings.values[key] = value
	apply()
	Settings.Changed:fire(key, value)
	Remotes.event("SaveSettings"):FireServer(Settings.values.sfx, Settings.values.labels)
end

return Settings
