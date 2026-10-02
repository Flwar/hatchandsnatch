--!strict
--[[
	BaseController
	Client-side touches for the player's own base: a floating "YOUR BASE" marker
	above its entrance so new players can always find home. Only this client sees it.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local BaseController = {}

local player = Players.LocalPlayer
local marker: BillboardGui? = nil

local function findBase(index: number): Model?
	local map = Workspace:WaitForChild("Map", 30)
	local bases = if map then map:WaitForChild("Bases", 30) else nil
	local base = if bases then bases:WaitForChild(`Base{index}`, 30) else nil
	return if base and base:IsA("Model") then base :: Model else nil
end

local function updateMarker()
	if marker then
		marker:Destroy()
		marker = nil
	end
	local index = player:GetAttribute("BaseIndex")
	if typeof(index) ~= "number" then
		return
	end
	local base = findBase(index)
	if not base then
		return
	end
	local sign = base:FindFirstChild("Sign")
	if not sign or not sign:IsA("BasePart") then
		return
	end
	local color = base:GetAttribute("Color")
	local gui = Instance.new("BillboardGui")
	gui.Name = "YourBaseMarker"
	gui.Adornee = sign
	gui.Size = UDim2.fromOffset(220, 56)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 1000
	local label = Theme.text("Title", "⭐ YOUR BASE ⭐", gui)
	label.Size = UDim2.fromScale(1, 1)
	label.TextColor3 = if typeof(color) == "Color3" then color else Theme.Colors.Coin
	gui.Parent = player:WaitForChild("PlayerGui")
	marker = gui
end

function BaseController.init() end

function BaseController.start()
	player:GetAttributeChangedSignal("BaseIndex"):Connect(updateMarker)
	task.spawn(updateMarker)
end

return BaseController
