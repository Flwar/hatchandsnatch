--!strict
--[[
	HudController
	The always-on HUD: coin counter (short formatted, pops when it changes), the
	player's base number, and toast notifications sent by the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local HudController = {}

local player = Players.LocalPlayer
local MAX_TOASTS = 3
local TOAST_SECONDS = 3.5

local gui: ScreenGui
local coinLabel: TextLabel
local coinPill: Frame
local coinScale: UIScale
local baseLabel: TextLabel
local toastList: Frame

local function buildCoinPill(parent: Instance)
	coinPill = Instance.new("Frame")
	coinPill.Name = "Coins"
	coinPill.AnchorPoint = Vector2.new(0.5, 0)
	coinPill.Position = UDim2.new(0.5, 0, 0, 10)
	coinPill.Size = UDim2.fromOffset(220, 52)
	coinPill.BackgroundColor3 = Theme.Colors.Panel
	coinPill.Parent = parent
	coinScale = Instance.new("UIScale")
	coinScale.Parent = coinPill
	Theme.corner(coinPill, 26)
	Theme.stroke(coinPill, 3)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Theme.Colors.PanelLight, Theme.Colors.Panel)
	gradient.Parent = coinPill

	local coin = Instance.new("Frame")
	coin.Name = "CoinIcon"
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, 8, 0.5, 0)
	coin.Size = UDim2.fromOffset(38, 38)
	coin.BackgroundColor3 = Theme.Colors.Coin
	coin.Parent = coinPill
	Theme.corner(coin, 19)
	Theme.stroke(coin, 3, Color3.fromRGB(176, 120, 20))
	local mark = Theme.text("Mark", "$", coin)
	mark.Size = UDim2.fromScale(1, 1)
	mark.TextColor3 = Color3.fromRGB(255, 246, 200)

	coinLabel = Theme.text("Amount", "0", coinPill)
	coinLabel.Position = UDim2.fromOffset(54, 6)
	coinLabel.Size = UDim2.new(1, -66, 1, -12)
	coinLabel.TextXAlignment = Enum.TextXAlignment.Left
	coinLabel.TextColor3 = Theme.Colors.Coin

	baseLabel = Theme.text("Base", "", parent)
	baseLabel.AnchorPoint = Vector2.new(0.5, 0)
	baseLabel.Position = UDim2.new(0.5, 0, 0, 66)
	baseLabel.Size = UDim2.fromOffset(200, 24)
end

local function updateCoins(animate: boolean)
	local coins = player:GetAttribute("Coins")
	coinLabel.Text = Format.short(if typeof(coins) == "number" then coins else 0)
	if animate then
		coinScale.Scale = 1.12
		TweenService
			:Create(coinScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end
end

local function updateBase()
	local index = player:GetAttribute("BaseIndex")
	baseLabel.Text = if typeof(index) == "number" then `Your base: #{index}` else "Waiting for a free base..."
end

local function toastColor(kind: string): Color3
	if kind == "success" then
		return Theme.Colors.Success
	elseif kind == "warning" then
		return Theme.Colors.Warning
	end
	return Theme.Colors.Info
end

function HudController.toast(message: string, kind: string?)
	local toasts = toastList:GetChildren()
	local frames = {}
	for _, child in toasts do
		if child:IsA("Frame") then
			table.insert(frames, child)
		end
	end
	if #frames >= MAX_TOASTS then
		frames[1]:Destroy()
	end
	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.Size = UDim2.fromOffset(360, 44)
	toast.BackgroundColor3 = Theme.Colors.Panel
	toast.BackgroundTransparency = 0.05
	toast.LayoutOrder = math.floor(os.clock() * 1000)
	toast.Parent = toastList
	Theme.corner(toast, 12)
	Theme.stroke(toast, 3, toastColor(kind or "info"))
	local label = Theme.text("Message", message, toast)
	label.Position = UDim2.fromOffset(12, 6)
	label.Size = UDim2.new(1, -24, 1, -12)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = toast
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	task.delay(TOAST_SECONDS, function()
		if toast.Parent then
			local fade = TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0 })
			fade:Play()
			fade.Completed:Wait()
			toast:Destroy()
		end
	end)
end

function HudController.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	Theme.autoScale(gui)
	buildCoinPill(gui)

	toastList = Instance.new("Frame")
	toastList.Name = "Toasts"
	toastList.AnchorPoint = Vector2.new(0.5, 0)
	toastList.Position = UDim2.new(0.5, 0, 0, 98)
	toastList.Size = UDim2.fromOffset(360, 160)
	toastList.BackgroundTransparency = 1
	toastList.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = toastList
end

function HudController.start()
	updateCoins(false)
	updateBase()
	player:GetAttributeChangedSignal("Coins"):Connect(function()
		updateCoins(true)
	end)
	player:GetAttributeChangedSignal("BaseIndex"):Connect(updateBase)
	Remotes.event("Notify").OnClientEvent:Connect(function(message: any, kind: any)
		if type(message) == "string" then
			HudController.toast(message, if type(kind) == "string" then kind else nil)
		end
	end)
end

return HudController
