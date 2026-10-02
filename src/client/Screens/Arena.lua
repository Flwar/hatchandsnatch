--!strict
--[[
	Arena
	The Arena window, in three tabs:
	  * Battle: pick up to Config.ArenaTeamSize adults (front fighter first), see each
	    one's arena stats and abilities, and find a match. A real opponent is used
	    when one is waiting; otherwise a bot steps in after a few seconds.
	  * Leaderboard: the top trophy counts across every server.
	  * Ranks: the trophy ranks and the arena-only cosmetics they unlock.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ArenaStats = require(Shared:WaitForChild("ArenaStats"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))
local Window = require(UI:WaitForChild("Window"))
local MyCreatures = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("MyCreatures"))

local Arena = {}

local player = Players.LocalPlayer
local queuedUntil = 0 -- os.clock() while waiting for a match

local SLOT = 92

local function trophies(): number
	local value = player:GetAttribute("Trophies")
	return if typeof(value) == "number" then value else 0
end

local function statLine(id: string, mutation: string?): string
	local stats = ArenaStats.forCreature(id, mutation)
	if not stats then
		return ""
	end
	return `❤️{stats.hp} ⚔️{stats.attack} 💨{stats.speed}`
end

local function battleTab(body: Frame)
	local rank = ArenaStats.rank(trophies())
	local tier = Config.ArenaRanks[rank]
	local nextTier = Config.ArenaRanks[rank + 1]
	local header = Theme.text(
		"Header",
		`🏆 {trophies()}  ·  {if tier then `{tier.icon} {tier.name}` else "Unranked"}{if nextTier
			then `  ·  next: {nextTier.name} at {nextTier.trophies}`
			else ""}`,
		body
	)
	header.Size = UDim2.new(1, 0, 0, 28)
	header.TextXAlignment = Enum.TextXAlignment.Left

	local rows = {}
	for _, row in MyCreatures.list() do
		if row.home and row.stage == "Adult" then
			table.insert(rows, row)
		end
	end
	local picked: { MyCreatures.Row } = {}

	local strip = Instance.new("Frame")
	strip.BackgroundTransparency = 1
	strip.Position = UDim2.fromOffset(0, 34)
	strip.Size = UDim2.new(1, 0, 0, SLOT)
	strip.Parent = body
	local slots: { Frame } = {}
	for i = 1, Config.ArenaTeamSize do
		local card = Widgets.card(strip, UDim2.fromOffset(SLOT, SLOT), Theme.Colors.Panel)
		card.Position = UDim2.fromOffset((i - 1) * (SLOT + 8), 0)
		slots[i] = card
	end
	local info = Theme.text("Info", "", strip)
	info.Position = UDim2.fromOffset(Config.ArenaTeamSize * (SLOT + 8) + 4, 0)
	info.Size = UDim2.new(1, -(Config.ArenaTeamSize * (SLOT + 8) + 4), 0, 30)
	info.TextWrapped = true
	local actionRow = Instance.new("Frame")
	actionRow.BackgroundTransparency = 1
	actionRow.Position = UDim2.fromOffset(Config.ArenaTeamSize * (SLOT + 8) + 4, 34)
	actionRow.Size = UDim2.new(1, -(Config.ArenaTeamSize * (SLOT + 8) + 4), 0, 56)
	actionRow.Parent = strip
	local cells: { [string]: Frame } = {}

	local refresh: () -> ()

	local function renderAction()
		actionRow:ClearAllChildren()
		if os.clock() < queuedUntil then
			info.Text = "Finding an opponent..."
			Widgets.button(actionRow, {
				text = "Cancel",
				color = Theme.Colors.Warning,
				size = UDim2.fromScale(1, 1),
				callback = function()
					queuedUntil = 0
					Remotes.event("CancelMatch"):FireServer()
					refresh()
				end,
			})
			return
		end
		Widgets.button(actionRow, {
			text = "⚔️ Find match!",
			color = if #picked > 0 then Theme.Colors.Success else Theme.Colors.PanelLight,
			size = UDim2.fromScale(1, 1),
			callback = function()
				if #picked == 0 then
					return
				end
				local uids = {}
				for _, row in picked do
					table.insert(uids, row.uid)
				end
				Remotes.event("FindMatch"):FireServer(uids)
			end,
		})
	end

	refresh = function()
		for uid, cell in cells do
			local selected = false
			for _, row in picked do
				if row.uid == uid then
					selected = true
				end
			end
			cell.BackgroundColor3 = if selected then Theme.Colors.Info else Theme.Colors.PanelLight
		end
		for i, card in slots do
			card:ClearAllChildren()
			Theme.corner(card, 14)
			Theme.stroke(card, 2)
			local row = picked[i]
			if row then
				Widgets.creatureViewport(card, row.id, false, UDim2.new(1, -8, 1, -8), row.mutation).Position =
					UDim2.fromOffset(4, 4)
			else
				local label = Theme.text("Empty", if i == 1 then "Front" else `#{i}`, card)
				label.Size = UDim2.fromScale(1, 1)
				label.TextColor3 = Color3.fromRGB(150, 150, 170)
			end
		end
		if #picked > 0 then
			local names = {}
			for _, row in picked do
				local stats = ArenaStats.forCreature(row.id, row.mutation)
				if stats and #stats.abilities > 0 then
					local abilityNames = {}
					for _, ability in stats.abilities do
						table.insert(abilityNames, ability.name)
					end
					table.insert(names, table.concat(abilityNames, ", "))
				end
			end
			info.Text = if #names > 0 then table.concat(names, " | ") else ""
		else
			info.Text = "Pick up to 3 adults. Losing costs nothing!"
		end
		renderAction()
	end

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(0, 34 + SLOT + 8)
	holder.Size = UDim2.new(1, 0, 1, -(34 + SLOT + 8))
	holder.Parent = body
	if #rows == 0 then
		local empty = Theme.text("Empty", "You need adult creatures on your pedestals to battle.", holder)
		empty.Size = UDim2.new(1, 0, 0, 50)
		empty.TextWrapped = true
		refresh()
		return
	end
	-- Strongest first, so a good team is one tap away.
	table.sort(rows, function(a, b)
		local sa, sb = ArenaStats.forCreature(a.id, a.mutation), ArenaStats.forCreature(b.id, b.mutation)
		return (if sa then ArenaStats.power(sa) else 0) > (if sb then ArenaStats.power(sb) else 0)
	end)
	local grid = Widgets.grid(holder, UDim2.fromOffset(104, 128))
	for index, row in rows do
		local def = CreatureData.get(row.id)
		if not def then
			continue
		end
		local cell = Widgets.card(grid, UDim2.new())
		cell.LayoutOrder = index
		cells[row.uid] = cell
		Widgets.creatureViewport(cell, row.id, false, UDim2.new(1, -8, 1, -52), row.mutation).Position =
			UDim2.fromOffset(4, 2)
		local name = Theme.text("Name", def.displayName, cell)
		name.AnchorPoint = Vector2.new(0, 1)
		name.Position = UDim2.new(0, 4, 1, -24)
		name.Size = UDim2.new(1, -8, 0, 24)
		name.TextColor3 = Rarity.get(def.rarity).color
		local stats = Theme.text("Stats", statLine(row.id, row.mutation), cell)
		stats.AnchorPoint = Vector2.new(0, 1)
		stats.Position = UDim2.new(0, 4, 1, -4)
		stats.Size = UDim2.new(1, -8, 0, 18)
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
			if #picked < Config.ArenaTeamSize then
				table.insert(picked, row)
				refresh()
			end
		end)
	end
	refresh()
end

local function leaderboardTab(body: Frame)
	local ok, result = pcall(function()
		return Remotes.func("GetLeaderboard"):InvokeServer()
	end)
	local summary: Types.LeaderboardSummary? = if ok and type(result) == "table" then result else nil
	local list = Widgets.list(body, 6)
	local header = Theme.text(
		"Header",
		if summary
			then `Your trophies: {summary.trophies}{if summary.rank then `  ·  #{summary.rank}` else ""}`
			else "Couldn't load the leaderboard. Try again soon!",
		list
	)
	header.Size = UDim2.new(1, 0, 0, 30)
	header.LayoutOrder = 0
	if not summary then
		return
	end
	if #summary.top == 0 then
		local empty = Theme.text("Empty", "Nobody on the board yet. Win a battle to be first!", list)
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.LayoutOrder = 1
	end
	for _, entry in summary.top do
		local me = entry.userId == player.UserId
		local card =
			Widgets.card(list, UDim2.new(1, 0, 0, 44), if me then Theme.Colors.Info else Theme.Colors.PanelLight)
		card.LayoutOrder = entry.rank
		local medal = if entry.rank == 1
			then "🥇"
			elseif entry.rank == 2 then "🥈"
			elseif entry.rank == 3 then "🥉"
			else `#{entry.rank}`
		local label = Theme.text("Row", `{medal}  {entry.name}`, card)
		label.Position = UDim2.fromOffset(12, 6)
		label.Size = UDim2.new(0.7, -12, 1, -12)
		label.TextXAlignment = Enum.TextXAlignment.Left
		local score = Theme.text("Score", `🏆 {entry.trophies}`, card)
		score.Position = UDim2.new(0.7, 0, 0, 6)
		score.Size = UDim2.new(0.3, -12, 1, -12)
		score.TextXAlignment = Enum.TextXAlignment.Right
		score.TextColor3 = Theme.Colors.Coin
	end
end

local RANK_COLORS = {
	Color3.fromRGB(214, 140, 80),
	Color3.fromRGB(206, 214, 228),
	Color3.fromRGB(255, 204, 60),
	Color3.fromRGB(120, 230, 255),
}

local function ranksTab(body: Frame)
	local list = Widgets.list(body, 8)
	local current = ArenaStats.rank(trophies())
	local intro = Theme.text(
		"Intro",
		"Arena ranks unlock arena-only cosmetics: a title over your head and a trophy statue in your base.",
		list
	)
	intro.Size = UDim2.new(1, 0, 0, 44)
	intro.TextWrapped = true
	intro.LayoutOrder = 0
	for index, tier in Config.ArenaRanks do
		local unlocked = current >= index
		local card =
			Widgets.card(list, UDim2.new(1, 0, 0, 56), if unlocked then Theme.Colors.PanelLight else Theme.Colors.Panel)
		card.LayoutOrder = index
		local label = Theme.text("Rank", `{tier.icon} {tier.title}`, card)
		label.Position = UDim2.fromOffset(12, 8)
		label.Size = UDim2.new(0.65, -12, 1, -16)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = RANK_COLORS[index] or Theme.Colors.Text
		local need = Theme.text("Need", if unlocked then "✅ Unlocked" else `🏆 {tier.trophies}`, card)
		need.Position = UDim2.new(0.65, 0, 0, 8)
		need.Size = UDim2.new(0.35, -12, 1, -16)
		need.TextXAlignment = Enum.TextXAlignment.Right
	end
end

function Arena.open(tabIndex: number?)
	Window.open("Arena", function(content: Frame)
		Window.tabs(content, {
			{ name = "Battle", build = battleTab },
			{ name = "Leaderboard", build = leaderboardTab },
			{ name = "Ranks", build = ranksTab },
		}, tabIndex)
	end)
end

-- Called when the server put us in the queue; a bot steps in after `waitSec`.
function Arena.setQueued(waitSec: number)
	queuedUntil = os.clock() + waitSec + 3
	if Window.isOpen("Arena") then
		Arena.open(1)
	end
end

function Arena.clearQueue()
	queuedUntil = 0
end

return Arena
