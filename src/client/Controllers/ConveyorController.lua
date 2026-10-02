--!strict
--[[
	ConveyorController
	Colors each conveyor egg's price: gold if you can afford it, red if you can't,
	so players can tell at a glance what they can buy right now.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ConveyorController = {}

local player = Players.LocalPlayer
local AFFORDABLE = Color3.fromRGB(255, 220, 80)
local TOO_EXPENSIVE = Color3.fromRGB(255, 96, 96)

local eggsFolder: Instance? = nil

local function colorEgg(egg: Instance)
	local price = egg:GetAttribute("Price")
	local root = egg:FindFirstChild("Root")
	local gui = if root then root:FindFirstChild("EggInfo") else nil
	local label = if gui then gui:FindFirstChild("Price") else nil
	if typeof(price) ~= "number" or not label or not label:IsA("TextLabel") then
		return
	end
	local priceLabel = label :: TextLabel
	local coins = player:GetAttribute("Coins")
	local canAfford = typeof(coins) == "number" and coins >= price
	priceLabel.TextColor3 = if canAfford then AFFORDABLE else TOO_EXPENSIVE
end

local function colorAll()
	if eggsFolder then
		for _, egg in eggsFolder:GetChildren() do
			colorEgg(egg)
		end
	end
end

function ConveyorController.init() end

function ConveyorController.start()
	local map = Workspace:WaitForChild("Map", 60)
	local lobby = if map then map:WaitForChild("Lobby", 30) else nil
	local conveyor = if lobby then lobby:WaitForChild("Conveyor", 30) else nil
	local folder = if conveyor then conveyor:WaitForChild("Eggs", 30) else nil
	if not folder then
		return
	end
	eggsFolder = folder
	folder.ChildAdded:Connect(function(egg: Instance)
		-- Let the egg's descendants (root, label) arrive first.
		task.defer(colorEgg, egg)
		local root = egg:WaitForChild("Root", 5)
		if root then
			root:WaitForChild("EggInfo", 5)
			colorEgg(egg)
		end
	end)
	player:GetAttributeChangedSignal("Coins"):Connect(colorAll)
	colorAll()
end

return ConveyorController
