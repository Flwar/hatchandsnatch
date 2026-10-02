--!strict
--[[
	PopupController
	Shows server-driven popups. Milestone 2: the "While you were away" offline
	earnings popup.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Popup = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Popup"))

local PopupController = {}

local function describeAway(seconds: number): string
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if hours > 0 then
		return `{hours}h {minutes}m`
	end
	return `{math.max(1, minutes)}m`
end

function PopupController.init() end

function PopupController.start()
	Remotes.event("OfflineEarnings").OnClientEvent:Connect(function(coins: any, seconds: any)
		if type(coins) ~= "number" or type(seconds) ~= "number" then
			return
		end
		local body = if coins > 0
			then `You were gone for {describeAway(seconds)}. Your creatures kept growing and earned you {Format.short(
				coins
			)} coins!`
			else `You were gone for {describeAway(seconds)}. Your creatures kept growing while you were away!`
		Popup.show({
			icon = "💰",
			title = if coins > 0 then `+{Format.short(coins)} coins!` else "Welcome back!",
			body = body,
			buttons = { { text = "Collect" } },
		})
	end)
end

return PopupController
