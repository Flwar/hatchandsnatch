--!strict
--[[
	CombatController
	Sends a swing request whenever the bonk bat is activated (click or tap) and
	plays local effects for bonks and traps. The server picks the target and
	validates everything; the client only asks to swing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Effects = require(UI:WaitForChild("Effects"))

local CombatController = {}

local player = Players.LocalPlayer
local BAT_NAME = "BonkBat"
local LOCAL_COOLDOWN = 0.25
local lastSwing = 0
local hooked: { [Tool]: boolean } = {}

local function hookTool(instance: Instance)
	if not instance:IsA("Tool") or instance.Name ~= BAT_NAME then
		return
	end
	local tool = instance :: Tool
	if hooked[tool] then
		return
	end
	hooked[tool] = true
	tool.Activated:Connect(function()
		local now = os.clock()
		if now - lastSwing >= LOCAL_COOLDOWN then
			lastSwing = now
			Remotes.event("BatSwing"):FireServer()
		end
	end)
	tool.Destroying:Connect(function()
		hooked[tool] = nil
	end)
end

local TRAP_WORDS: { [string]: { text: string, color: Color3 } } = {
	BananaPeel = { text = "SLIP!", color = Color3.fromRGB(255, 220, 70) },
	StickyFloor = { text = "SPLAT!", color = Color3.fromRGB(255, 120, 200) },
	HonkEgg = { text = "HONK!", color = Color3.fromRGB(255, 255, 255) },
}

function CombatController.init() end

function CombatController.start()
	local function watch(container: Instance)
		for _, child in container:GetChildren() do
			hookTool(child)
		end
		container.ChildAdded:Connect(hookTool)
	end
	watch(player:WaitForChild("Backpack"))
	player.CharacterAdded:Connect(function(character: Model)
		watch(character)
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			watch(backpack)
		end
	end)
	if player.Character then
		watch(player.Character)
	end
	Remotes.event("BatHit").OnClientEvent:Connect(function(position: any)
		if typeof(position) == "Vector3" then
			Effects.burst(position, Color3.fromRGB(255, 230, 90))
			Effects.popText(position, "BONK!", Color3.fromRGB(255, 230, 90))
		end
	end)
	Remotes.event("TrapSprung").OnClientEvent:Connect(function(trapType: any, position: any)
		local word = if type(trapType) == "string" then TRAP_WORDS[trapType] else nil
		if word and typeof(position) == "Vector3" then
			Effects.burst(position, word.color)
			Effects.popText(position, word.text, word.color)
		end
	end)
end

return CombatController
