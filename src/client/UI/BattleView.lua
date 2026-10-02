--!strict
--[[
	BattleView
	Plays back an arena battle the server already decided (ArenaBattle.Report):
	your team on the left, the opponent's on the right, each fighter a card with its
	3D model and a health bar. Attackers lunge, targets shake, numbers pop (crits,
	misses, heals, burns), abilities are called out, and knocked-out fighters grey
	out. Skip jumps straight to the result. Losing never costs trophies.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local ArenaBattle = require(Shared:WaitForChild("ArenaBattle"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local BattleView = {}

type Card = {
	frame: Frame,
	holder: Frame,
	bar: Frame,
	hpText: TextLabel,
	viewport: ViewportFrame,
	info: ArenaBattle.FighterInfo,
	hp: number,
	direction: number, -- +1 lunges right (your side), -1 lunges left
}

local player = Players.LocalPlayer
local playing = false

local CARD_W, CARD_H = 210, 104
local RED = Color3.fromRGB(255, 90, 90)
local GREEN = Color3.fromRGB(96, 214, 120)
local ORANGE = Color3.fromRGB(255, 160, 60)
local YELLOW = Color3.fromRGB(255, 226, 90)

local function makeCard(parent: Instance, fighter: ArenaBattle.FighterInfo, index: number, mine: boolean): Card
	-- `holder` keeps the layout slot; `frame` moves inside it for lunges and shakes.
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(CARD_W, CARD_H)
	holder.LayoutOrder = index
	holder.Parent = parent
	local def = CreatureData.get(fighter.id)
	local rarity = Rarity.get(if def then def.rarity else "Common")
	local frame = Widgets.card(holder, UDim2.fromScale(1, 1), Theme.Colors.PanelLight)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rarity.color
	end
	local viewport =
		Widgets.creatureViewport(frame, fighter.id, false, UDim2.fromOffset(CARD_H - 8, CARD_H - 8), fighter.mutation)
	viewport.Position = if mine then UDim2.fromOffset(4, 4) else UDim2.new(1, -(CARD_H - 4), 0, 4)
	local textX = if mine then CARD_H else 8
	local name = Theme.text("Name", fighter.name, frame)
	name.Position = UDim2.fromOffset(textX, 6)
	name.Size = UDim2.new(1, -(CARD_H + 8), 0, 26)
	name.TextColor3 = rarity.color
	name.TextXAlignment = if mine then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
	local back = Instance.new("Frame")
	back.Name = "HealthBack"
	back.Position = UDim2.fromOffset(textX, 38)
	back.Size = UDim2.new(1, -(CARD_H + 8), 0, 18)
	back.BackgroundColor3 = Theme.Colors.Outline
	back.Parent = frame
	Theme.corner(back, 8)
	local bar = Instance.new("Frame")
	bar.Name = "Health"
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = GREEN
	bar.Parent = back
	Theme.corner(bar, 8)
	local hpText = Theme.text("HP", `{fighter.maxHp}`, back)
	hpText.Size = UDim2.fromScale(1, 1)
	hpText.ZIndex = 3
	local abilities = Theme.text("Abilities", table.concat(fighter.abilities, " · "), frame)
	abilities.Position = UDim2.fromOffset(textX, 62)
	abilities.Size = UDim2.new(1, -(CARD_H + 8), 0, 34)
	abilities.TextWrapped = true
	abilities.TextColor3 = Color3.fromRGB(210, 206, 235)
	abilities.TextXAlignment = name.TextXAlignment
	return {
		frame = frame,
		holder = holder,
		bar = bar,
		hpText = hpText,
		viewport = viewport,
		info = fighter,
		hp = fighter.maxHp,
		direction = if mine then 1 else -1,
	}
end

local function setHealth(card: Card, hp: number, instant: boolean?)
	card.hp = math.max(0, hp)
	local share = card.hp / math.max(card.info.maxHp, 1)
	local color = if share > 0.5 then GREEN elseif share > 0.25 then YELLOW else RED
	if instant then
		card.bar.Size = UDim2.fromScale(share, 1)
		card.bar.BackgroundColor3 = color
	else
		TweenService
			:Create(card.bar, TweenInfo.new(0.25), { Size = UDim2.fromScale(share, 1), BackgroundColor3 = color })
			:Play()
	end
	card.hpText.Text = `{card.hp}/{card.info.maxHp}`
end

local function knockOut(card: Card)
	card.viewport.ImageColor3 = Color3.fromRGB(70, 70, 80)
	card.frame.BackgroundColor3 = Theme.Colors.Panel
	if not card.frame:FindFirstChild("KO") then
		local stamp = Theme.text("KO", "KO!", card.frame)
		stamp.AnchorPoint = Vector2.new(0.5, 0.5)
		stamp.Position = UDim2.fromScale(0.5, 0.5)
		stamp.Size = UDim2.fromOffset(110, 56)
		stamp.Rotation = -12
		stamp.TextColor3 = RED
		stamp.ZIndex = 5
	end
end

local function popText(card: Card, text: string, color: Color3, big: boolean?)
	local label = Theme.text("Pop", text, card.holder)
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 0, 10)
	label.Size = UDim2.fromOffset(if big then 170 else 130, if big then 46 else 34)
	label.TextColor3 = color
	label.ZIndex = 8
	TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, -36),
		TextTransparency = 1,
	}):Play()
	task.delay(0.95, function()
		label:Destroy()
	end)
end

local function lunge(card: Card)
	local out = TweenService:Create(
		card.frame,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(card.direction * 38, 0) }
	)
	out:Play()
	out.Completed:Wait()
	TweenService:Create(card.frame, TweenInfo.new(0.18), { Position = UDim2.fromOffset(0, 0) }):Play()
end

local function shake(card: Card)
	task.spawn(function()
		for _, x in { -8, 7, -5, 3, 0 } do
			card.frame.Position = UDim2.fromOffset(x, 0)
			task.wait(0.03)
		end
	end)
end

-- Plays `report` back. Yields until the player closes the result screen.
function BattleView.play(report: ArenaBattle.Report)
	if playing then
		return
	end
	playing = true
	local gui = Instance.new("ScreenGui")
	gui.Name = "Battle"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 25
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	Theme.autoScale(gui)
	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.fromRGB(16, 12, 30)
	shade.BackgroundTransparency = 0.12
	shade.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(60, 40, 110), Color3.fromRGB(16, 12, 30))
	gradient.Parent = shade

	local title = Theme.text("Title", `⚔️ You vs {report.opponent}{if report.bot then " 🤖" else ""}`, shade)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 20)
	title.Size = UDim2.fromOffset(560, 46)
	title.TextColor3 = Theme.Colors.Coin
	local skipped = false
	local skip = Widgets.button(shade, {
		text = "Skip ▶▶",
		color = Theme.Colors.PanelLight,
		size = UDim2.fromOffset(130, 52),
		position = UDim2.new(1, -150, 0, 18),
		callback = function()
			skipped = true
		end,
	})

	local function column(xScale: number, anchor: number): Frame
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.AnchorPoint = Vector2.new(anchor, 0.5)
		frame.Position = UDim2.fromScale(xScale, 0.53)
		frame.Size = UDim2.fromOffset(CARD_W, CARD_H * 3 + 24)
		frame.Parent = shade
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 12)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Parent = frame
		return frame
	end
	local left, right = column(0.27, 0.5), column(0.73, 0.5)
	local vs = Theme.text("VS", "VS", shade)
	vs.AnchorPoint = Vector2.new(0.5, 0.5)
	vs.Position = UDim2.fromScale(0.5, 0.53)
	vs.Size = UDim2.fromOffset(90, 60)
	vs.TextColor3 = RED

	local cards: { [string]: Card } = {}
	for _, fighter in report.fighters do
		local mine = fighter.side == report.side
		cards[fighter.key] = makeCard(if mine then left else right, fighter, fighter.slot, mine)
	end

	-- Play the log.
	for _, event in report.events do
		if skipped then
			break
		end
		local actor = cards[event.actor]
		local target = if event.target then cards[event.target] else nil
		if not actor then
			continue
		end
		local wait = 0.35
		if event.kind == "attack" and target then
			lunge(actor)
			if event.dodged then
				popText(target, "MISS!", Color3.fromRGB(200, 220, 255))
			else
				shake(target)
				Sounds.play("Bonk")
				popText(target, if event.crit then `CRIT! -{event.amount}` else `-{event.amount}`, RED, event.crit)
				setHealth(target, event.hp or target.hp)
			end
			if event.ability then
				popText(if event.dodged then target else actor, `{event.ability}!`, YELLOW)
			end
			wait = 0.55
		elseif event.kind == "thorns" and target then
			popText(target, `-{event.amount} 🌵`, ORANGE)
			setHealth(target, event.hp or target.hp)
		elseif event.kind == "heal" then
			popText(actor, `+{event.amount}`, GREEN)
			setHealth(actor, event.hp or actor.hp)
		elseif event.kind == "burn" then
			popText(actor, `-{event.amount} 🔥`, ORANGE)
			setHealth(actor, event.hp or actor.hp)
		elseif event.kind == "stunned" then
			popText(actor, "💫 Stunned", YELLOW)
		elseif event.kind == "revive" then
			popText(actor, `{event.ability or "Revive"}! 1 HP`, GREEN, true)
			setHealth(actor, 1)
		elseif event.kind == "buff" then
			popText(actor, `{event.ability or "Buff"}!`, YELLOW, true)
		elseif event.kind == "faint" then
			setHealth(actor, 0)
			knockOut(actor)
			wait = 0.45
		end
		task.wait(wait)
	end
	-- After a skip (or the last event) show everyone's final health.
	if skipped then
		local final: { [string]: number } = {}
		for _, event in report.events do
			if event.kind == "faint" then
				final[event.actor] = 0
			elseif event.hp then
				local who = if event.kind == "attack" or event.kind == "thorns" then event.target else event.actor
				if who then
					final[who] = event.hp
				end
			end
		end
		for key, hp in final do
			local card = cards[key]
			if card then
				setHealth(card, hp, true)
				if hp <= 0 then
					knockOut(card)
				end
			end
		end
	end
	skip:Destroy()

	-- Result.
	local won = report.winner == report.side
	Sounds.play(if won then "Discovery" else "Warning")
	local panel = Widgets.card(shade, UDim2.fromOffset(440, 220), Theme.Colors.Panel)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.53)
	panel.ZIndex = 10
	local headline = Theme.text("Result", if won then "🏆 VICTORY!" else "DEFEAT", panel)
	headline.Position = UDim2.fromOffset(20, 16)
	headline.Size = UDim2.new(1, -40, 0, 56)
	headline.TextColor3 = if won then Theme.Colors.Coin else RED
	local line = if won
		then `+{report.gained} 🏆  (total {report.trophies})`
		else "No trophies lost. Try another team!"
	if report.rankUp then
		local rank = 0
		for index, tier in Config.ArenaRanks do
			if report.trophies >= tier.trophies then
				rank = index
			end
		end
		local tier = Config.ArenaRanks[rank]
		if tier then
			line ..= `\n{tier.icon} New rank: {tier.title}!`
		end
	end
	local body = Theme.text("Body", line, panel)
	body.Position = UDim2.fromOffset(20, 78)
	body.Size = UDim2.new(1, -40, 0, 64)
	body.TextWrapped = true
	local closed = false
	Widgets.button(panel, {
		text = "Continue",
		size = UDim2.fromOffset(180, 56),
		position = UDim2.new(0.5, -90, 1, -70),
		callback = function()
			closed = true
		end,
	})
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = panel
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	while not closed and gui.Parent do
		task.wait(0.1)
	end
	gui:Destroy()
	playing = false
end

function BattleView.isPlaying(): boolean
	return playing
end

return BattleView
