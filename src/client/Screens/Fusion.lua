--!strict
--[[
	Fusion
	The Fusion Machine's window. Pick two of your adult creatures (originals only,
	standing on their pedestals), see what they make (a mystery until you have
	discovered it), and send them into the machine. While the machine is busy the
	window shows its progress instead.

	The server re-checks everything when the request arrives (ownership, distance to
	the machine, adults, the machine being free).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Economy = require(Shared:WaitForChild("Economy"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Popup = require(UI:WaitForChild("Popup"))
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))
local Window = require(UI:WaitForChild("Window"))
local State = script.Parent.Parent:WaitForChild("State")
local MyCreatures = require(State:WaitForChild("MyCreatures"))
local Profile = require(State:WaitForChild("Profile"))

local Fusion = {}

local player = Players.LocalPlayer

local SLOT = 104

-- The local player's Fusion Machine, if they have a base.
function Fusion.machine(): Model?
	local map = Workspace:FindFirstChild("Map")
	local bases = if map then map:FindFirstChild("Bases") else nil
	if not bases then
		return nil
	end
	for _, base in bases:GetChildren() do
		if base:GetAttribute("OwnerUserId") == player.UserId then
			local machine = base:FindFirstChild("FusionMachine")
			return if machine and machine:IsA("Model") then machine :: Model else nil
		end
	end
	return nil
end

local function slotCard(parent: Instance, x: number): Frame
	local card = Widgets.card(parent, UDim2.fromOffset(SLOT, SLOT), Theme.Colors.Panel)
	card.Position = UDim2.fromOffset(x, 0)
	return card
end

local function sign(parent: Instance, text: string, x: number)
	local label = Theme.text("Sign", text, parent)
	label.Position = UDim2.fromOffset(x, 30)
	label.Size = UDim2.fromOffset(30, 44)
end

local function fill(card: Frame, creatureId: string?, caption: string, color: Color3?)
	card:ClearAllChildren()
	Theme.corner(card, 14)
	Theme.stroke(card, 2)
	if creatureId then
		Widgets.creatureViewport(card, creatureId, false, UDim2.new(1, -8, 1, -30)).Position = UDim2.fromOffset(4, 2)
	end
	local label = Theme.text("Caption", caption, card)
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, 4, 1, -4)
	label.Size = UDim2.new(1, -8, 0, if creatureId then 24 else SLOT - 8)
	label.TextWrapped = true
	label.TextColor3 = color or Theme.Colors.Text
end

-- The machine is busy: show what's inside and the countdown.
local function buildBusy(content: Frame, machine: Model)
	local inside: { string } = {}
	for _, child in machine:GetChildren() do
		local id = child:GetAttribute("CreatureId")
		if child:GetAttribute("FusionVisual") and typeof(id) == "string" and CreatureData.isOriginal(id) then
			table.insert(inside, id)
		end
	end
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, 20)
	row.Size = UDim2.fromOffset(SLOT * 3 + 60, SLOT)
	row.Parent = content
	for i = 1, 2 do
		local id = inside[i]
		local def = if id then CreatureData.get(id) else nil
		fill(slotCard(row, (i - 1) * (SLOT + 30)), id, if def then def.displayName else "?")
	end
	sign(row, "+", SLOT)
	sign(row, "=", SLOT * 2 + 30)
	local ready = machine:GetAttribute("State") == "Ready"
	local resultName = machine:GetAttribute("ResultName")
	fill(
		slotCard(row, SLOT * 2 + 60),
		nil,
		if ready and typeof(resultName) == "string" and resultName ~= "" then `✨ {resultName}` else "❔",
		Theme.Colors.Coin
	)
	local status = Theme.text("Status", "", content)
	status.Position = UDim2.fromOffset(0, SLOT + 50)
	status.Size = UDim2.new(1, 0, 0, 44)
	status.TextColor3 = Theme.Colors.Coin
	local note = Theme.text("Note", "", content)
	note.Position = UDim2.fromOffset(0, SLOT + 100)
	note.Size = UDim2.new(1, 0, 0, 56)
	note.TextWrapped = true
	task.spawn(function()
		while status.Parent do
			local endsAt = machine:GetAttribute("FusionEndsAt")
			local left = if typeof(endsAt) == "number" then endsAt - Workspace:GetServerTimeNow() else 0
			if machine:GetAttribute("State") == "Ready" then
				status.Text = "Ready!"
				note.Text = "Free up a pedestal and your hybrid comes out on its own."
			else
				status.Text = `Fusing... {Format.clock(math.max(0, left))}`
				note.Text = "You can leave: fusing keeps going even while you're offline."
			end
			task.wait(0.25)
		end
	end)
end

local function buildPicker(content: Frame)
	local summary = Profile.fetch()
	local known: { [string]: boolean } = {}
	if summary then
		for _, id in summary.discoveries do
			known[id] = true
		end
	end
	local rows = {}
	for _, row in MyCreatures.list() do
		if row.home and row.stage == "Adult" and CreatureData.isOriginal(row.id) then
			table.insert(rows, row)
		end
	end
	local picked: { MyCreatures.Row } = {}

	-- Top strip: A + B = result, and the Fuse button.
	local strip = Instance.new("Frame")
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.new(1, 0, 0, SLOT)
	strip.Parent = content
	local cardA = slotCard(strip, 0)
	sign(strip, "+", SLOT)
	local cardB = slotCard(strip, SLOT + 30)
	sign(strip, "=", SLOT * 2 + 30)
	local cardResult = slotCard(strip, SLOT * 2 + 60)
	local info = Theme.text("Info", "", strip)
	info.Position = UDim2.fromOffset(SLOT * 3 + 72, 0)
	info.Size = UDim2.new(1, -(SLOT * 3 + 72), 0, 40)
	info.TextWrapped = true
	local fuse: TextButton

	local cells: { [string]: Frame } = {}

	local function refresh()
		for uid, cell in cells do
			local selected = false
			for _, row in picked do
				if row.uid == uid then
					selected = true
				end
			end
			cell.BackgroundColor3 = if selected then Theme.Colors.Info else Theme.Colors.PanelLight
		end
		local a, b = picked[1], picked[2]
		local defA = if a then CreatureData.get(a.id) else nil
		local defB = if b then CreatureData.get(b.id) else nil
		fill(cardA, if a then a.id else nil, if defA then defA.displayName else "Pick one")
		fill(cardB, if b then b.id else nil, if defB then defB.displayName else "Pick one")
		local resultId = if a and b then CreatureData.fuse(a.id, b.id) else nil
		local ready = resultId ~= nil
		fuse.Visible = ready
		if not (a and b) then
			fill(cardResult, nil, "?")
			info.Text = "Pick two different adults."
		elseif not resultId then
			fill(cardResult, nil, "✖")
			info.Text = "Pick two different creatures!"
		else
			local def = CreatureData.get(resultId)
			if def and known[resultId] then
				local rarity = Rarity.get(def.rarity)
				fill(cardResult, resultId, def.displayName, rarity.color)
				info.Text = `{def.rarity} · 💰 {Format.short(Economy.incomePerSec(resultId, nil))}/s`
			else
				fill(cardResult, nil, "❔\nMystery!", Theme.Colors.Coin)
				info.Text = "A new hybrid! Recipes stay secret until you fuse them."
			end
		end
	end

	fuse = Widgets.button(strip, {
		text = `Fuse! ({Format.clock(Config.FusionTimeSec)})`,
		color = Theme.Colors.Success,
		size = UDim2.new(1, -(SLOT * 3 + 72), 0, 56),
		position = UDim2.fromOffset(SLOT * 3 + 72, 46),
		callback = function()
			local a, b = picked[1], picked[2]
			if not a or not b then
				return
			end
			local defA, defB = CreatureData.get(a.id), CreatureData.get(b.id)
			if not defA or not defB then
				return
			end
			Popup.show({
				icon = "🧪",
				title = `Fuse {defA.displayName} + {defB.displayName}?`,
				body = "Both go into the machine and come out as one hybrid. This can't be undone!",
				buttons = {
					{ text = "Cancel", color = Theme.Colors.PanelLight },
					{
						text = "Fuse!",
						color = Theme.Colors.Success,
						callback = function()
							Remotes.event("StartFusion"):FireServer(a.uid, b.uid)
							Window.close()
						end,
					},
				},
			})
		end,
	})

	-- Pickable creatures.
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(0, SLOT + 12)
	holder.Size = UDim2.new(1, 0, 1, -(SLOT + 12))
	holder.Parent = content
	if #rows < 2 then
		local empty = Theme.text(
			"Empty",
			"You need two adult creatures on your pedestals to fuse. Hybrids can't be fused again.",
			holder
		)
		empty.Size = UDim2.new(1, 0, 0, 70)
		empty.TextWrapped = true
		refresh()
		return
	end
	local grid = Widgets.grid(holder, UDim2.fromOffset(96, 112))
	for index, row in rows do
		local def = CreatureData.get(row.id)
		if not def then
			continue
		end
		local cell = Widgets.card(grid, UDim2.new())
		cell.LayoutOrder = index
		cells[row.uid] = cell
		Widgets.creatureViewport(cell, row.id, false, UDim2.new(1, -8, 1, -32)).Position = UDim2.fromOffset(4, 2)
		local name = Theme.text("Name", def.displayName, cell)
		name.AnchorPoint = Vector2.new(0, 1)
		name.Position = UDim2.new(0, 4, 1, -4)
		name.Size = UDim2.new(1, -8, 0, 26)
		name.TextColor3 = Rarity.get(def.rarity).color
		local button = Instance.new("TextButton")
		button.BackgroundTransparency = 1
		button.Text = ""
		button.Size = UDim2.fromScale(1, 1)
		button.ZIndex = 5
		button.Parent = cell
		button.Activated:Connect(function()
			for i, chosen in picked do
				if chosen.uid == row.uid then
					table.remove(picked, i)
					refresh()
					return
				end
			end
			if #picked >= 2 then
				table.remove(picked, 1)
			end
			table.insert(picked, row)
			refresh()
		end)
	end
	refresh()
end

local function build(content: Frame)
	local machine = Fusion.machine()
	if not machine then
		local empty = Theme.text("Empty", "You need a base to use the Fusion Machine.", content)
		empty.Size = UDim2.new(1, 0, 0, 60)
		return
	end
	if machine:GetAttribute("State") ~= "Idle" then
		buildBusy(content, machine)
	else
		buildPicker(content)
	end
end

function Fusion.open()
	Window.open("Fusion", build)
end

return Fusion
