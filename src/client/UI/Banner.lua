--!strict
--[[
	Banner
	Big announcement banners that slide in at the top of the screen: thefts,
	first discoveries, weather events. One at a time; extras wait in a queue.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))

local Banner = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local queue: { { text: string, subtext: string?, color: Color3, seconds: number } } = {}
local showing = false

local function getGui(): ScreenGui
	if gui then
		return gui
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "Banners"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 15
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	Theme.autoScale(screen)
	gui = screen
	return screen
end

local function showNext()
	if showing then
		return
	end
	local item = table.remove(queue, 1)
	if not item then
		return
	end
	showing = true
	local frame = Instance.new("Frame")
	frame.Name = "Banner"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, -120)
	frame.Size = UDim2.fromOffset(560, if item.subtext then 92 else 64)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.Parent = getGui()
	Theme.corner(frame, 18)
	Theme.stroke(frame, 4, item.color)
	local title = Theme.text("Title", item.text, frame)
	title.Position = UDim2.fromOffset(16, 8)
	title.Size = UDim2.new(1, -32, 0, 46)
	title.TextColor3 = item.color
	if item.subtext then
		local sub = Theme.text("Subtitle", item.subtext, frame)
		sub.Position = UDim2.fromOffset(16, 54)
		sub.Size = UDim2.new(1, -32, 0, 28)
	end
	local slideIn = TweenService:Create(
		frame,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 150) }
	)
	slideIn:Play()
	task.delay(item.seconds, function()
		local slideOut = TweenService:Create(frame, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -120) })
		slideOut:Play()
		slideOut.Completed:Wait()
		frame:Destroy()
		showing = false
		showNext()
	end)
end

function Banner.show(text: string, subtext: string?, color: Color3?, seconds: number?)
	table.insert(queue, { text = text, subtext = subtext, color = color or Theme.Colors.Coin, seconds = seconds or 4 })
	showNext()
end

return table.freeze(Banner)
