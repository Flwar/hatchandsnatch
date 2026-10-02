--!strict
--[[
	ArenaProps
	World pieces for the creature arena:

	  * ArenaProps.board: the "ARENA CHAMPIONS" leaderboard in the lobby, with crossed
	    swords and a trophy on top, and the arena desk in front of it. The server fills
	    the board's rows (SurfaceGui "LeaderboardGui" > Frame "Rows" > Row1..RowN) and
	    puts the arena prompt on the desk's "Desk" part.
	  * ArenaProps.trophy: the trophy statue a player's arena rank puts in their base
	    (bronze, silver, gold or diamond).

	`cf` is a floor point; the board faces along cf.LookVector.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ModelKit = require(Shared:WaitForChild("Models"):WaitForChild("ModelKit"))
local Props = require(script.Parent.Props)

local ArenaProps = {}

local v3 = Vector3.new
local GOLD = Color3.fromRGB(255, 200, 60)
local NAVY = Color3.fromRGB(30, 30, 60)
local STONE = Color3.fromRGB(206, 210, 220)
local STEEL = Color3.fromRGB(196, 204, 220)

-- Colors of the four arena ranks (Bronze, Silver, Gold, Diamond).
ArenaProps.RankColors = table.freeze({
	Color3.fromRGB(214, 140, 80),
	Color3.fromRGB(206, 214, 228),
	Color3.fromRGB(255, 204, 60),
	Color3.fromRGB(120, 230, 255),
})

local function newModel(name: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

local function upright(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.rad(90))
end

-- A gold cup on a stepped base, `height` studs tall, standing at `cf`.
local function cup(name: string, cf: CFrame, height: number, color: Color3, parent: Instance)
	local k = height / 4
	local model = newModel(name, parent)
	local shiny = { reflectance = 0.25 }
	ModelKit.part("Base", "Block", v3(1.8, 0.5, 1.8) * k, cf * CFrame.new(0, 0.25 * k, 0), NAVY, model)
	ModelKit.part(
		"Stem",
		"Cylinder",
		v3(1.2, 0.5, 0.5) * k,
		upright(cf * CFrame.new(0, 1.05 * k, 0)),
		color,
		model,
		shiny
	)
	ModelKit.part(
		"Foot",
		"Cylinder",
		v3(0.25, 1.2, 1.2) * k,
		upright(cf * CFrame.new(0, 0.62 * k, 0)),
		color,
		model,
		shiny
	)
	ModelKit.part("Bowl", "Ellipsoid", v3(2.1, 2.0, 2.1) * k, cf * CFrame.new(0, 2.45 * k, 0), color, model, shiny)
	ModelKit.part(
		"Rim",
		"Cylinder",
		v3(0.22, 2.2, 2.2) * k,
		upright(cf * CFrame.new(0, 3.35 * k, 0)),
		color,
		model,
		shiny
	)
	for side = -1, 1, 2 do
		ModelKit.part(
			"Handle",
			"Cylinder",
			v3(0.18, 1.0, 1.0) * k,
			cf * CFrame.new(side * 1.12 * k, 2.6 * k, 0) * CFrame.Angles(0, math.rad(90), 0),
			color,
			model,
			shiny
		)
	end
	ModelKit.part(
		"Emblem",
		"Block",
		v3(0.5, 0.5, 0.12) * k,
		cf * CFrame.new(0, 2.35 * k, -1.02 * k) * CFrame.Angles(0, 0, math.rad(45)),
		Color3.fromRGB(255, 255, 255),
		model,
		{ material = Enum.Material.Neon }
	)
end

function ArenaProps.board(cf: CFrame, parent: Instance): Model
	local model = newModel("ArenaBoard", parent)
	local solid = { collide = true }
	-- Pillars with gold caps.
	for side = -1, 1, 2 do
		ModelKit.part("Pillar", "Block", v3(1.6, 11, 1.6), cf * CFrame.new(side * 8.2, 5.5, 0), STONE, model, solid)
		ModelKit.part("PillarCap", "Ball", v3(2.1, 2.1, 2.1), cf * CFrame.new(side * 8.2, 11.4, 0), GOLD, model, {
			reflectance = 0.2,
		})
	end
	-- The board itself: a gold frame around a navy panel with the leaderboard on it.
	ModelKit.part("Frame", "Block", v3(15.2, 9.6, 0.5), cf * CFrame.new(0, 6.2, 0.05), GOLD, model, solid)
	local board = ModelKit.part("Board", "Block", v3(14.4, 8.8, 0.6), cf * CFrame.new(0, 6.2, 0), NAVY, model, solid)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	-- The board faces along cf.LookVector, which is the part's -Z: its Front face.
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 36
	gui.LightInfluence = 0
	gui.Parent = board
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.03, 0.02)
	title.Size = UDim2.fromScale(0.94, 0.14)
	title.Font = Enum.Font.FredokaOne
	title.Text = "🏆 ARENA CHAMPIONS 🏆"
	title.TextColor3 = GOLD
	title.TextScaled = true
	title.Parent = gui
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromScale(0.05, 0.18)
	rows.Size = UDim2.fromScale(0.9, 0.8)
	rows.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.01, 0)
	layout.Parent = rows
	for i = 1, Config.LeaderboardSize do
		local row = Instance.new("TextLabel")
		row.Name = `Row{i}`
		row.LayoutOrder = i
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromScale(1, 0.09)
		row.Font = Enum.Font.FredokaOne
		row.Text = if i == 1 then "Win arena battles to get on the board!" else ""
		row.TextColor3 = if i <= 3 then ArenaProps.RankColors[4 - i] else Color3.fromRGB(230, 230, 245)
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Parent = rows
	end
	-- Crossed swords and a trophy on top.
	for side = -1, 1, 2 do
		local sword = cf * CFrame.new(side * 2.6, 12.2, 0) * CFrame.Angles(0, 0, math.rad(side * 35))
		ModelKit.part("Blade", "Block", v3(0.5, 4.6, 0.2), sword * CFrame.new(0, 0.8, 0), STEEL, model, {
			material = Enum.Material.Metal,
		})
		ModelKit.part("Guard", "Block", v3(1.6, 0.3, 0.4), sword * CFrame.new(0, -1.6, 0), GOLD, model)
		ModelKit.part("Grip", "Block", v3(0.35, 1.1, 0.35), sword * CFrame.new(0, -2.3, 0), NAVY, model)
	end
	cup("Trophy", cf * CFrame.new(0, 10.9, 0), 3.6, GOLD, model)
	-- The arena desk in front of the board.
	local desk = ModelKit.part("Desk", "Block", v3(5, 2.4, 1.8), cf * CFrame.new(0, 1.2, -5.5), NAVY, model, solid)
	desk.CanQuery = true
	ModelKit.part("DeskTop", "Block", v3(5.4, 0.3, 2.2), cf * CFrame.new(0, 2.55, -5.5), GOLD, model, solid)
	Props.sign(
		"DeskSign",
		v3(4.4, 1.1, 0.2),
		cf * CFrame.new(0, 1.3, -6.45),
		model,
		"⚔️ BATTLE!",
		NAVY,
		GOLD,
		false
	)
	return model
end

-- The trophy statue for arena rank `rank` (1..4) in a player's base.
function ArenaProps.trophy(cf: CFrame, rank: number, parent: Instance): Model
	local color = ArenaProps.RankColors[math.clamp(rank, 1, #ArenaProps.RankColors)]
	local model = newModel("ArenaTrophy", parent)
	ModelKit.part("Plinth", "Block", v3(2.6, 1.2, 2.6), cf * CFrame.new(0, 0.6, 0), STONE, model, { collide = true })
	cup("Cup", cf * CFrame.new(0, 1.2, 0), 3.4, color, model)
	model:SetAttribute("Rank", rank)
	return model
end

return table.freeze(ArenaProps)
