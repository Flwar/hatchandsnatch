--!strict
--[[
	MapBuilder
	Builds the placeholder world from code: grass ground, a lobby plaza with the egg
	conveyor and egg machine, eight player bases in a ring around it, paths and scenery.
	All layout numbers come from Config.Map.

	The map is a Model named "Map" with this shape (other services rely on these names):

	  Map
	    Ground
	    Lobby (Model)
	      Conveyor (Model)  BeltStart / BeltEnd parts mark the egg path, Eggs (Folder)
	      LobbySpawn (SpawnLocation)
	      ArenaBoard (Model, see World/ArenaProps)
	      GalleryAnchor (Part)
	    Bases (Folder)
	      Base1..BaseN (Model)  attributes: BaseIndex, BaseCFrame, OwnerUserId
	        Spawn (SpawnLocation), Shield, Sign, CollectPad (Model, Pad part), Creatures (Folder)
	        Pedestals (Folder) Pedestal1..PedestalN (Model, attribute Slot, Socket attachment)
	        FusionMachine (Model, see World/FusionMachine)
	    Paths, Scenery (Models), Boundary (Folder of invisible walls)

	Like the creature builders, this module only creates Instances, so tools/preview
	can render it outside Roblox.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ModelKit = require(Shared:WaitForChild("Models"):WaitForChild("ModelKit"))
local Props = require(script.Parent.Props)
local FusionMachine = require(script.Parent.FusionMachine)
local ArenaProps = require(script.Parent.ArenaProps)

local MapBuilder = {}

local v3 = Vector3.new
local part = ModelKit.part
local M = Config.Map

-- One accent color per base, in base order.
MapBuilder.BaseColors = table.freeze({
	Color3.fromRGB(255, 104, 104),
	Color3.fromRGB(255, 166, 72),
	Color3.fromRGB(255, 212, 76),
	Color3.fromRGB(104, 210, 112),
	Color3.fromRGB(70, 204, 200),
	Color3.fromRGB(88, 156, 255),
	Color3.fromRGB(168, 116, 255),
	Color3.fromRGB(255, 124, 196),
})

local GRASS = Color3.fromRGB(110, 192, 86)
local PLAZA = Color3.fromRGB(236, 226, 204)
local PLAZA_INNER = Color3.fromRGB(222, 208, 182)
local CURB = Color3.fromRGB(196, 182, 156)
local PATH = Color3.fromRGB(226, 202, 156)
local WALL = Color3.fromRGB(246, 240, 228)
local STONE = Color3.fromRGB(206, 210, 220)
local FLOOR = Color3.fromRGB(204, 160, 110)
local STEEL = Color3.fromRGB(84, 98, 130)
local RAIL = Color3.fromRGB(255, 200, 60)
local BELT = Color3.fromRGB(46, 46, 54)

local BASE_FLOOR_TOP = 0.4 -- base floors sit slightly above the grass
MapBuilder.FloorHeight = BASE_FLOOR_TOP

-- Where traps go, in base-local studs (x, z). One spot per Config.MaxTraps.
MapBuilder.TrapSpotOffsets = table.freeze({
	Vector3.new(-2.5, 0, -30),
	Vector3.new(2.5, 0, -27),
	Vector3.new(-2.5, 0, -23.5),
	Vector3.new(2.5, 0, -20),
	Vector3.new(0, 0, -16),
})
local PLAZA_TOP = 0.5

-- Base-local Z of the Fusion Machine's center (it faces the entrance).
MapBuilder.FusionMachineZ = 28

local function newModel(name: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

local function vertical(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.rad(90))
end

local function invisibleWall(name: string, size: Vector3, cf: CFrame, parent: Instance): BasePart
	local wall = part(
		name,
		"Block",
		size,
		cf,
		Color3.new(1, 1, 1),
		parent,
		{ transparency = 1, collide = true, castShadow = false }
	)
	wall.CanTouch = false
	return wall
end

-- World CFrame of base `index`: on the ring, facing the lobby (local -Z points at the center).
function MapBuilder.baseCFrame(index: number): CFrame
	local angle = math.rad((index - 1) * (360 / Config.BaseCount) + 180 / Config.BaseCount)
	local position = v3(math.cos(angle) * M.BaseRingRadius, 0, math.sin(angle) * M.BaseRingRadius)
	return ModelKit.facing(position, -position)
end

-- Local position (base frame) of pedestal `slot`. Slots fill the front row first.
function MapBuilder.pedestalOffset(slot: number): Vector3
	local column = (slot - 1) % M.PedestalColumns
	local row = (slot - 1) // M.PedestalColumns
	local x = (column - (M.PedestalColumns - 1) / 2) * M.PedestalSpacing
	local z = -10 + row * M.PedestalSpacing
	return v3(x, BASE_FLOOR_TOP, z)
end

---------------------------------------------------------------------------
-- Pedestals
---------------------------------------------------------------------------

local function buildPedestal(slot: number, cf: CFrame, color: Color3, parent: Instance): Model
	local model = newModel(`Pedestal{slot}`, parent)
	model:SetAttribute("Slot", slot)
	local d = M.PedestalDiameter
	local glow =
		part("Glow", "Cylinder", v3(0.16, d + 0.5, d + 0.5), vertical(cf * CFrame.new(0, 0.08, 0)), color, model, {
			material = Enum.Material.Neon,
			castShadow = false,
		})
	local base =
		part("Base", "Cylinder", v3(1.0, d, d), vertical(cf * CFrame.new(0, 0.5, 0)), STONE, model, { collide = true })
	local top =
		part("Top", "Cylinder", v3(0.35, d - 0.7, d - 0.7), vertical(cf * CFrame.new(0, 1.17, 0)), color, model, {
			collide = true,
		})
	top.CanQuery = true
	local socket = Instance.new("Attachment")
	socket.Name = "Socket"
	socket.CFrame = top.CFrame:Inverse() * (cf * CFrame.new(0, 1.35, 0))
	socket.Parent = top
	local locked = part(
		"LockedPad",
		"Cylinder",
		v3(0.2, d - 0.4, d - 0.4),
		vertical(cf * CFrame.new(0, 0.1, 0)),
		Color3.fromRGB(150, 156, 170),
		model,
		{
			transparency = 0.35,
			castShadow = false,
		}
	)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LockGui"
	gui.Face = Enum.NormalId.Right -- the cylinder's flat top after rotating it upright
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = locked
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.Text = "🔒"
	icon.TextScaled = true
	icon.Font = Enum.Font.FredokaOne
	icon.TextTransparency = 0.2
	icon.Parent = gui
	for _, p in { glow, base, top } do
		p:SetAttribute("UnlockedTransparency", p.Transparency)
	end
	locked:SetAttribute("UnlockedTransparency", 1)
	MapBuilder.setPedestalUnlocked(model, false)
	return model
end

-- Shows the full pedestal when unlocked, or a faint locked pad otherwise.
function MapBuilder.setPedestalUnlocked(pedestal: Model, unlocked: boolean)
	pedestal:SetAttribute("Unlocked", unlocked)
	for _, child in pedestal:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end
		local p = child :: BasePart
		local isLockedPad = p.Name == "LockedPad"
		local visible = if isLockedPad then not unlocked else unlocked
		local unlockedTransparency = p:GetAttribute("UnlockedTransparency")
		if isLockedPad then
			p.Transparency = if visible then 0.35 else 1
		else
			p.Transparency = if visible
				then (if typeof(unlockedTransparency) == "number" then unlockedTransparency else 0)
				else 1
		end
		if p.Name ~= "Glow" and not isLockedPad then
			p.CanCollide = visible
		end
		local gui = p:FindFirstChildOfClass("SurfaceGui")
		if gui then
			gui.Enabled = visible
		end
	end
end

---------------------------------------------------------------------------
-- Bases
---------------------------------------------------------------------------

local function buildCollectPad(cf: CFrame, color: Color3, parent: Instance): Model
	local model = newModel("CollectPad", parent)
	local gold = Color3.fromRGB(255, 200, 60)
	part(
		"Rim",
		"Block",
		v3(7.4, 0.5, 7.4),
		cf * CFrame.new(0, 0.25, 0),
		gold,
		model,
		{ collide = true, reflectance = 0.1 }
	)
	local pad =
		part("Pad", "Block", v3(6.2, 0.6, 6.2), cf * CFrame.new(0, 0.3, 0), Color3.fromRGB(96, 220, 120), model, {
			collide = true,
		})
	pad.CanTouch = true
	part("Glow", "Block", v3(6.7, 0.54, 6.7), cf * CFrame.new(0, 0.27, 0), Color3.fromRGB(150, 255, 160), model, {
		material = Enum.Material.Neon,
		castShadow = false,
	})
	for i = 0, 2 do
		part(
			"Coin",
			"Cylinder",
			v3(0.28, 1.3, 1.3),
			vertical(cf * CFrame.new(2.2, 0.74 + i * 0.3, 2.2) * CFrame.Angles(0, i * 0.4, 0)),
			gold,
			model,
			{
				reflectance = 0.15,
			}
		)
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CoinsGui"
	billboard.Size = UDim2.fromScale(7, 2.2)
	billboard.StudsOffsetWorldSpace = v3(0, 4, 0)
	billboard.MaxDistance = 90
	billboard.LightInfluence = 0
	billboard.Parent = pad
	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = "💰 0"
	label.TextColor3 = Color3.fromRGB(255, 226, 90)
	label.TextScaled = true
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(70, 46, 20)
	stroke.Parent = label
	model:SetAttribute("Color", color)
	return model
end

local function buildBase(index: number, parent: Instance): Model
	local color = MapBuilder.BaseColors[(index - 1) % #MapBuilder.BaseColors + 1]
	local trim = ModelKit.shade(color, 0.82)
	local cf = MapBuilder.baseCFrame(index)
	local S = M.BaseSize
	local half = S / 2
	local base = newModel(`Base{index}`, parent)
	base:SetAttribute("BaseIndex", index)
	base:SetAttribute("BaseCFrame", cf)
	base:SetAttribute("OwnerUserId", 0)
	base:SetAttribute("Color", color)

	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- Ground slab, plank floor and a colored border.
	part("Slab", "Block", v3(S, 1.4, S), at(0, BASE_FLOOR_TOP - 0.74, 0), Color3.fromRGB(150, 210, 120), base, {
		collide = true,
		material = Enum.Material.Grass,
	})
	part("Floor", "Block", v3(S - 8, 0.2, S - 8), at(0, BASE_FLOOR_TOP - 0.1, 1), FLOOR, base, {
		collide = true,
		material = Enum.Material.WoodPlanks,
	})
	part("Border", "Block", v3(S - 6.6, 0.16, S - 6.6), at(0, BASE_FLOOR_TOP - 0.1, 1), trim, base, { collide = true })

	-- Walls with colored caps; the front wall leaves a gap for the entrance.
	local wallH = M.BaseWallHeight
	local thick = 1.6
	local entrance = M.EntranceWidth
	local frontLen = (S - entrance) / 2
	local walls = {
		{ name = "WallBack", size = v3(S, wallH, thick), offset = v3(0, 0, half - thick / 2) },
		{ name = "WallLeft", size = v3(thick, wallH, S), offset = v3(-half + thick / 2, 0, 0) },
		{ name = "WallRight", size = v3(thick, wallH, S), offset = v3(half - thick / 2, 0, 0) },
		{
			name = "WallFrontLeft",
			size = v3(frontLen, wallH, thick),
			offset = v3(-(entrance / 2 + frontLen / 2), 0, -half + thick / 2),
		},
		{
			name = "WallFrontRight",
			size = v3(frontLen, wallH, thick),
			offset = v3(entrance / 2 + frontLen / 2, 0, -half + thick / 2),
		},
	}
	local wallModel = newModel("Walls", base)
	-- A wall's footprint made `extra` studs thicker (only across its thin side) and `height` tall.
	local function band(size: Vector3, extra: number, height: number): Vector3
		if size.X > size.Z then
			return v3(size.X, height, size.Z + extra)
		end
		return v3(size.X + extra, height, size.Z)
	end
	for _, w in walls do
		local name, size, offset = w.name, w.size, w.offset
		part(name, "Block", size, at(offset.X, BASE_FLOOR_TOP + wallH / 2, offset.Z), WALL, wallModel, {
			collide = true,
			material = Enum.Material.Plaster,
		})
		part(
			`{name}Cap`,
			"Block",
			band(size, 0.5, 0.6),
			at(offset.X, BASE_FLOOR_TOP + wallH + 0.3, offset.Z),
			color,
			wallModel,
			{
				collide = true,
			}
		)
		part(
			`{name}Base`,
			"Block",
			band(size, 0.3, 1.2),
			at(offset.X, BASE_FLOOR_TOP + 0.6, offset.Z),
			trim,
			wallModel,
			{
				collide = true,
			}
		)
	end
	-- Corner posts with ball caps.
	for _, corner in { v3(-half, 0, -half), v3(half, 0, -half), v3(-half, 0, half), v3(half, 0, half) } do
		local x = corner.X - math.sign(corner.X) * 1.1
		local z = corner.Z - math.sign(corner.Z) * 1.1
		part(
			"Post",
			"Block",
			v3(2.6, wallH + 1.6, 2.6),
			at(x, BASE_FLOOR_TOP + (wallH + 1.6) / 2, z),
			WALL,
			wallModel,
			{
				collide = true,
				material = Enum.Material.Plaster,
			}
		)
		part("PostCap", "Ball", v3(2.4, 2.4, 2.4), at(x, BASE_FLOOR_TOP + wallH + 2.2, z), color, wallModel)
	end

	-- Invisible barriers stop anyone from jumping over the walls.
	local barriers = Instance.new("Folder")
	barriers.Name = "Barriers"
	barriers.Parent = base
	local barrierH = M.BaseBarrierHeight
	for _, w in walls do
		local size, offset = w.size, w.offset
		invisibleWall(
			"Barrier",
			v3(size.X, barrierH, size.Z),
			at(offset.X, BASE_FLOOR_TOP + barrierH / 2, offset.Z),
			barriers
		)
	end
	local overEntranceH = barrierH - M.EntranceHeight
	invisibleWall(
		"BarrierOverEntrance",
		v3(entrance, overEntranceH, thick),
		at(0, BASE_FLOOR_TOP + M.EntranceHeight + overEntranceH / 2, -half + thick / 2),
		barriers
	)

	-- Entrance arch with the owner sign.
	local archModel = newModel("Arch", base)
	local pillarX = entrance / 2 + 1.3
	local archH = M.EntranceHeight + 1
	for _, side in { -1, 1 } do
		part(
			"Pillar",
			"Block",
			v3(2.6, archH, 2.6),
			at(side * pillarX, BASE_FLOOR_TOP + archH / 2, -half + thick / 2),
			WALL,
			archModel,
			{
				collide = true,
				material = Enum.Material.Plaster,
			}
		)
		part(
			"PillarCap",
			"Ball",
			v3(2.6, 2.6, 2.6),
			at(side * pillarX, BASE_FLOOR_TOP + archH + 2.6, -half + thick / 2),
			color,
			archModel
		)
	end
	part(
		"Beam",
		"Block",
		v3(entrance + 5.2, 2.4, 2.8),
		at(0, BASE_FLOOR_TOP + archH + 1.2, -half + thick / 2),
		color,
		archModel,
		{
			collide = true,
		}
	)
	local sign = Props.sign(
		"Sign",
		v3(entrance + 2, 3.4, 0.4),
		at(0, BASE_FLOOR_TOP + archH + 1.2, -half + thick / 2 - 1.6),
		base,
		"Empty Base",
		Color3.fromRGB(255, 252, 240),
		Color3.fromRGB(255, 255, 255),
		false
	)
	sign:SetAttribute("BaseIndex", index)
	local frontGui = sign:FindFirstChild("FrontGui")
	local label = if frontGui then frontGui:FindFirstChild("Title") else nil
	if label and label:IsA("TextLabel") then
		(label :: TextLabel).TextColor3 = color
	end

	-- The shield: a force field across the entrance. Closed during the day.
	local shield = part(
		"Shield",
		"Block",
		v3(entrance, M.EntranceHeight, 0.6),
		at(0, BASE_FLOOR_TOP + M.EntranceHeight / 2, -half + thick / 2),
		color,
		base,
		{
			material = Enum.Material.ForceField,
			transparency = 0.15,
			collide = true,
			castShadow = false,
		}
	)
	shield.CanTouch = false

	-- Spawn point near the entrance, facing the lobby.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = v3(5, 0.4, 5)
	spawn.CFrame = at(-14, BASE_FLOOR_TOP + 0.2, -24)
	spawn.Anchored = true
	spawn.Color = ModelKit.shade(color, 1.35)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	spawn.Enabled = true
	spawn.Parent = base

	buildCollectPad(at(14, BASE_FLOOR_TOP, -24), color, base)
	part("Carpet", "Block", v3(8, 0.06, 20), at(0, BASE_FLOOR_TOP + 0.03, -23.5), ModelKit.shade(color, 1.3), base, {
		material = Enum.Material.Fabric,
	})

	local creatures = Instance.new("Folder")
	creatures.Name = "Creatures"
	creatures.Parent = base

	-- Trap spots along the entrance carpet, where raiders walk in.
	local trapSpots = Instance.new("Folder")
	trapSpots.Name = "TrapSpots"
	trapSpots.Parent = base
	for spot, offset in MapBuilder.TrapSpotOffsets do
		local marker = part(
			`TrapSpot{spot}`,
			"Block",
			v3(1, 1, 1),
			at(offset.X, BASE_FLOOR_TOP, offset.Z),
			Color3.new(1, 1, 1),
			trapSpots,
			{
				transparency = 1,
				castShadow = false,
			}
		)
		marker:SetAttribute("Spot", spot)
	end

	local pedestals = Instance.new("Folder")
	pedestals.Name = "Pedestals"
	pedestals.Parent = base
	for slot = 1, Config.MaxPedestals do
		local offset = MapBuilder.pedestalOffset(slot)
		buildPedestal(slot, cf * CFrame.new(offset), color, pedestals)
	end

	-- The Fusion Machine stands against the back wall, behind the last pedestal row.
	FusionMachine.build(at(0, BASE_FLOOR_TOP, MapBuilder.FusionMachineZ), color, base)

	-- Scenery inside the base.
	local decor = newModel("Decor", base)
	Props.flag(at(half - 4.5, BASE_FLOOR_TOP, half - 4.5), decor, color)
	Props.lamp(at(-half + 4.5, BASE_FLOOR_TOP, -half + 4.5), decor, 9)
	Props.lamp(at(half - 4.5, BASE_FLOOR_TOP, -half + 4.5), decor, 9)
	Props.bush(at(-half + 4, BASE_FLOOR_TOP, 4), decor, 1.1)
	Props.bush(at(half - 4, BASE_FLOOR_TOP, 12), decor, 1.0)
	Props.bush(at(-half + 4.5, BASE_FLOOR_TOP, half - 5), decor, 1.2)
	Props.flowers(at(-6, BASE_FLOOR_TOP, -half + 3.6), decor, color)
	Props.flowers(at(6, BASE_FLOOR_TOP, -half + 3.6), decor, color)
	return base
end

---------------------------------------------------------------------------
-- Lobby & conveyor
---------------------------------------------------------------------------

local function buildConveyor(parent: Instance): Model
	local model = newModel("Conveyor", parent)
	local L, W, H = M.ConveyorLength, M.ConveyorWidth, M.ConveyorHeight
	local top = PLAZA_TOP + H
	part("Frame", "Block", v3(L, H - 0.4, W + 1.2), CFrame.new(0, PLAZA_TOP + (H - 0.4) / 2, 0), STEEL, model, {
		collide = true,
		material = Enum.Material.Metal,
	})
	part(
		"Skirt",
		"Block",
		v3(L + 0.4, 0.5, W + 1.6),
		CFrame.new(0, PLAZA_TOP + 0.25, 0),
		Color3.fromRGB(56, 64, 86),
		model,
		{
			collide = true,
		}
	)
	local belt = part("Belt", "Block", v3(L, 0.4, W), CFrame.new(0, top - 0.2, 0), BELT, model, {
		collide = true,
		material = Enum.Material.Rubber,
	})
	belt.CanTouch = true
	for _, side in { -1, 1 } do
		part(
			"Rail",
			"Block",
			v3(L, 0.7, 0.6),
			CFrame.new(0, top + 0.35, side * (W / 2 + 0.3)),
			RAIL,
			model,
			{ collide = true }
		)
		-- Hazard stripes along the side of the frame.
		for i = 0, 7 do
			local x = -L / 2 + 4 + i * ((L - 8) / 7)
			part(
				"Stripe",
				"Block",
				v3(1.4, H - 1.4, 0.1),
				CFrame.new(x, PLAZA_TOP + (H - 0.4) / 2, side * (W / 2 + 0.62)) * CFrame.Angles(0, 0, math.rad(30)),
				RAIL,
				model
			)
		end
	end
	for _, side in { -1, 1 } do
		part(
			"Roller",
			"Cylinder",
			v3(W + 0.4, H - 0.2, H - 0.2),
			CFrame.new(side * L / 2, PLAZA_TOP + (H - 0.2) / 2, 0) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(150, 160, 180),
			model,
			{
				collide = true,
				material = Enum.Material.Metal,
			}
		)
	end
	-- Direction chevrons painted on the belt.
	for i = 0, 6 do
		local x = -L / 2 + 6 + i * ((L - 12) / 6)
		for _, side in { -1, 1 } do
			part(
				"Chevron",
				"Block",
				v3(0.35, 0.06, 2.6),
				CFrame.new(x, top + 0.02, side * 0.9) * CFrame.Angles(0, math.rad(-side * 40), 0),
				Color3.fromRGB(110, 110, 124),
				model
			)
		end
	end
	-- Markers the conveyor service uses for the egg path (invisible).
	local markerOpts = { transparency = 1, castShadow = false }
	part("BeltStart", "Block", v3(1, 1, 1), CFrame.new(-L / 2 + 2, top, 0), Color3.new(1, 1, 1), model, markerOpts)
	-- Eggs travel past the end of the belt and drop into the egg hole.
	part("BeltEnd", "Block", v3(1, 1, 1), CFrame.new(L / 2 + 4.2, top, 0), Color3.new(1, 1, 1), model, markerOpts)
	local eggs = Instance.new("Folder")
	eggs.Name = "Eggs"
	eggs.Parent = model

	-- Egg machine at the start of the belt.
	local machine = newModel("EggMachine", model)
	local mx = -L / 2 - 6.5
	local pink = Color3.fromRGB(255, 120, 150)
	part(
		"Body",
		"Cylinder",
		v3(11, 12, 12),
		vertical(CFrame.new(mx, PLAZA_TOP + 5.5, 0)),
		pink,
		machine,
		{ collide = true }
	)
	part(
		"Band",
		"Cylinder",
		v3(1.2, 12.4, 12.4),
		vertical(CFrame.new(mx, PLAZA_TOP + 9.4, 0)),
		Color3.fromRGB(255, 230, 120),
		machine,
		{
			collide = true,
		}
	)
	part(
		"Lights",
		"Cylinder",
		v3(0.5, 12.5, 12.5),
		vertical(CFrame.new(mx, PLAZA_TOP + 1.2, 0)),
		Color3.fromRGB(255, 240, 160),
		machine,
		{
			material = Enum.Material.Neon,
			castShadow = false,
		}
	)
	part("Dome", "Ball", v3(11, 11, 11), CFrame.new(mx, PLAZA_TOP + 11, 0), Color3.fromRGB(200, 236, 255), machine, {
		material = Enum.Material.Glass,
		transparency = 0.55,
		collide = true,
		castShadow = false,
	})
	local eggColors = {
		Color3.fromRGB(255, 220, 120),
		Color3.fromRGB(150, 220, 255),
		Color3.fromRGB(200, 160, 255),
		Color3.fromRGB(160, 236, 140),
		Color3.fromRGB(255, 170, 200),
	}
	for i, eggColor in eggColors do
		local a = math.rad(i * 72)
		part(
			"DomeEgg",
			"Ellipsoid",
			v3(2.2, 2.9, 2.2),
			CFrame.new(mx + math.cos(a) * 2.4, PLAZA_TOP + 12.4 + (i % 2) * 0.7, math.sin(a) * 2.4)
				* CFrame.Angles(0, 0, math.rad(i * 9 - 20)),
			eggColor,
			machine
		)
	end
	part(
		"Topper",
		"Ball",
		v3(2.2, 2.2, 2.2),
		CFrame.new(mx, PLAZA_TOP + 16.8, 0),
		Color3.fromRGB(255, 80, 120),
		machine,
		{
			reflectance = 0.1,
		}
	)
	part(
		"Chute",
		"Block",
		v3(4, 2.4, W - 0.6),
		CFrame.new(mx + 6.2, top + 1.0, 0),
		Color3.fromRGB(255, 200, 70),
		machine,
		{
			collide = true,
		}
	)
	part(
		"ChuteHole",
		"Block",
		v3(0.2, 1.8, W - 1.6),
		CFrame.new(mx + 8.15, top + 0.9, 0),
		Color3.fromRGB(40, 30, 40),
		machine
	)
	Props.sign(
		"MachineSign",
		v3(9, 2.6, 0.4),
		CFrame.new(mx + 6.05, PLAZA_TOP + 7.4, 0) * CFrame.Angles(0, math.rad(-90), 0),
		machine,
		"EGGS!",
		Color3.fromRGB(255, 252, 240),
		Color3.fromRGB(255, 96, 140),
		false
	)

	-- Egg hole at the end of the belt.
	local bin = newModel("EggHole", model)
	local bx = L / 2 + 4.2
	part(
		"Bin",
		"Cylinder",
		v3(H, 7.4, 7.4),
		vertical(CFrame.new(bx, PLAZA_TOP + H / 2, 0)),
		Color3.fromRGB(90, 180, 120),
		bin,
		{
			collide = true,
		}
	)
	part(
		"Rim",
		"Cylinder",
		v3(0.5, 8.0, 8.0),
		vertical(CFrame.new(bx, PLAZA_TOP + H + 0.05, 0)),
		Color3.fromRGB(70, 150, 100),
		bin,
		{
			collide = true,
		}
	)
	part(
		"Hole",
		"Cylinder",
		v3(0.1, 6.2, 6.2),
		vertical(CFrame.new(bx, PLAZA_TOP + H + 0.32, 0)),
		Color3.fromRGB(24, 28, 30),
		bin
	)
	return model
end

local function buildLobby(parent: Instance): Model
	local lobby = newModel("Lobby", parent)
	local R = M.LobbyRadius
	part(
		"Curb",
		"Cylinder",
		v3(PLAZA_TOP - 0.1, R * 2 + 2, R * 2 + 2),
		vertical(CFrame.new(0, (PLAZA_TOP - 0.1) / 2, 0)),
		CURB,
		lobby,
		{
			collide = true,
		}
	)
	part("Plaza", "Cylinder", v3(PLAZA_TOP, R * 2, R * 2), vertical(CFrame.new(0, PLAZA_TOP / 2, 0)), PLAZA, lobby, {
		collide = true,
	})
	part(
		"PlazaRing",
		"Cylinder",
		v3(0.06, R * 1.36, R * 1.36),
		vertical(CFrame.new(0, PLAZA_TOP, 0)),
		Color3.fromRGB(255, 176, 196),
		lobby,
		{
			collide = true,
		}
	)
	part(
		"PlazaInner",
		"Cylinder",
		v3(0.08, R * 1.28, R * 1.28),
		vertical(CFrame.new(0, PLAZA_TOP, 0)),
		PLAZA_INNER,
		lobby,
		{
			collide = true,
		}
	)
	buildConveyor(lobby)

	-- Title arch over the middle of the belt.
	local arch = newModel("TitleArch", lobby)
	for _, side in { -1, 1 } do
		part(
			"Pillar",
			"Cylinder",
			v3(16, 2.2, 2.2),
			vertical(CFrame.new(0, PLAZA_TOP + 8, side * 11)),
			Color3.fromRGB(255, 120, 150),
			arch,
			{
				collide = true,
			}
		)
		part(
			"PillarTop",
			"Ball",
			v3(3, 3, 3),
			CFrame.new(0, PLAZA_TOP + 16.4, side * 11),
			Color3.fromRGB(255, 214, 80),
			arch
		)
	end
	Props.sign(
		"TitleSign",
		v3(25, 5.5, 1),
		CFrame.new(0, PLAZA_TOP + 13.5, 0) * CFrame.Angles(0, math.rad(90), 0),
		arch,
		"HATCH & SNATCH",
		Color3.fromRGB(255, 252, 240),
		Color3.fromRGB(255, 104, 150),
		true
	)

	-- Overflow spawn for players who join when every base is taken.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = v3(8, 0.4, 8)
	spawn.CFrame = CFrame.new(0, PLAZA_TOP + 0.2, -22)
	spawn.Anchored = true
	spawn.Color = Color3.fromRGB(255, 236, 170)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = lobby

	-- The arena leaderboard and desk, across from the spawn so new players see it.
	ArenaProps.board(CFrame.lookAt(v3(0, PLAZA_TOP, -43), v3(0, PLAZA_TOP, 0)), lobby)

	-- Where the creature showroom is laid out (dev gallery), facing the conveyor.
	part("GalleryAnchor", "Block", v3(1, 1, 1), CFrame.new(0, PLAZA_TOP, 16), Color3.new(1, 1, 1), lobby, {
		transparency = 1,
		castShadow = false,
	})

	local decor = newModel("Decor", lobby)
	for i = 0, 7 do
		-- The lamp at 270 degrees would stand right behind the arena board.
		if i ~= 6 then
			local a = math.rad(i * 45)
			Props.lamp(CFrame.new(math.cos(a) * (R - 4), PLAZA_TOP, math.sin(a) * (R - 4)), decor, 11)
		end
	end
	local planterColors = {
		Color3.fromRGB(255, 120, 160),
		Color3.fromRGB(255, 200, 80),
		Color3.fromRGB(150, 130, 255),
		Color3.fromRGB(255, 150, 90),
	}
	for i, deg in { 112.5, 202.5, 292.5, 22.5 } do
		local a = math.rad(deg)
		local pos = v3(math.cos(a) * (R - 7), PLAZA_TOP, math.sin(a) * (R - 7))
		local planter = newModel("Planter", decor)
		part(
			"Pot",
			"Cylinder",
			v3(1.6, 6, 6),
			vertical(CFrame.new(pos + v3(0, 0.8, 0))),
			Color3.fromRGB(214, 150, 110),
			planter,
			{
				collide = true,
			}
		)
		part(
			"Soil",
			"Cylinder",
			v3(0.1, 5.2, 5.2),
			vertical(CFrame.new(pos + v3(0, 1.62, 0))),
			Color3.fromRGB(110, 76, 52),
			planter
		)
		Props.flowers(CFrame.new(pos + v3(-0.4, 1.6, 0.2)), planter, planterColors[i])
		Props.bush(CFrame.new(pos + v3(0.9, 1.4, -0.8)), planter, 0.55)
	end
	for i, deg in { 135, 225, 315, 45 } do
		local a = math.rad(deg)
		Props.tree(CFrame.new(math.cos(a) * (R - 12), PLAZA_TOP, math.sin(a) * (R - 12)), decor, 1.1, i % 3 + 1)
	end
	-- Benches sit on the spawn side (-Z); the +Z half is kept clear for the creature showroom.
	for _, deg in { 200, 250, 290, 340 } do
		local a = math.rad(deg)
		local benchPos = v3(math.cos(a) * (R - 15), PLAZA_TOP, math.sin(a) * (R - 15))
		Props.bench(ModelKit.facing(benchPos, -benchPos), decor)
	end
	return lobby
end

---------------------------------------------------------------------------
-- Paths, scenery, boundary
---------------------------------------------------------------------------

local function buildPaths(parent: Instance): Model
	local paths = newModel("Paths", parent)
	local startR = M.LobbyRadius - 1
	local endR = M.BaseRingRadius - M.BaseSize / 2 + 1
	local length = endR - startR
	for index = 1, Config.BaseCount do
		local baseCf = MapBuilder.baseCFrame(index)
		local dir = -baseCf.LookVector
		local mid = dir * (startR + length / 2)
		local cf = ModelKit.facing(v3(mid.X, 0.1, mid.Z), dir)
		part(
			"Path",
			"Block",
			v3(M.EntranceWidth, 0.2, length),
			cf,
			PATH,
			paths,
			{ collide = true, material = Enum.Material.Sand }
		)
		part(
			"PathEdgeL",
			"Block",
			v3(0.6, 0.24, length),
			cf * CFrame.new(-M.EntranceWidth / 2 - 0.3, 0, 0),
			CURB,
			paths,
			{
				collide = true,
			}
		)
		part(
			"PathEdgeR",
			"Block",
			v3(0.6, 0.24, length),
			cf * CFrame.new(M.EntranceWidth / 2 + 0.3, 0, 0),
			CURB,
			paths,
			{
				collide = true,
			}
		)
	end
	return paths
end

local function buildScenery(parent: Instance): Model
	local scenery = newModel("Scenery", parent)
	local rng = Random.new(42)
	-- Trees between the bases and along the outer edge.
	for index = 1, Config.BaseCount do
		local a = math.rad((index - 1) * (360 / Config.BaseCount))
		local r = M.BaseRingRadius - 4
		Props.tree(CFrame.new(math.cos(a) * r, 0, math.sin(a) * r), scenery, 1.3, index % 3 + 1)
		Props.bush(CFrame.new(math.cos(a) * (r - 12), 0, math.sin(a) * (r - 12)), scenery, 1.3)
	end
	local outer = M.BaseRingRadius + M.BaseSize / 2 + 18
	for i = 0, 27 do
		local a = math.rad(i * (360 / 28) + rng:NextNumber(-4, 4))
		local r = outer + rng:NextNumber(0, 40)
		Props.tree(
			CFrame.new(math.cos(a) * r, 0, math.sin(a) * r) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			scenery,
			rng:NextNumber(1.2, 1.8),
			i % 3 + 1
		)
	end
	-- Rolling hills at the edge of the world.
	for i = 0, 11 do
		local a = math.rad(i * 30 + 15)
		local r = M.GroundSize / 2 - 10
		local size = v3(rng:NextNumber(50, 80), rng:NextNumber(18, 30), rng:NextNumber(40, 60))
		part(
			"Hill",
			"Ellipsoid",
			size,
			ModelKit.facing(v3(math.cos(a) * r, 0, math.sin(a) * r), v3(-math.cos(a), 0, -math.sin(a))),
			ModelKit.shade(GRASS, 0.92 + (i % 3) * 0.05),
			scenery,
			{
				collide = true,
				material = Enum.Material.Grass,
			}
		)
	end
	return scenery
end

local function buildBoundary(parent: Instance)
	local boundary = Instance.new("Folder")
	boundary.Name = "Boundary"
	boundary.Parent = parent
	local half = M.GroundSize / 2
	local h = 80
	invisibleWall("North", v3(M.GroundSize, h, 2), CFrame.new(0, h / 2, -half), boundary)
	invisibleWall("South", v3(M.GroundSize, h, 2), CFrame.new(0, h / 2, half), boundary)
	invisibleWall("West", v3(2, h, M.GroundSize), CFrame.new(-half, h / 2, 0), boundary)
	invisibleWall("East", v3(2, h, M.GroundSize), CFrame.new(half, h / 2, 0), boundary)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function MapBuilder.build(parent: Instance): Model
	local map = Instance.new("Model")
	map.Name = "Map"
	part("Ground", "Block", v3(M.GroundSize, 4, M.GroundSize), CFrame.new(0, -2, 0), GRASS, map, {
		collide = true,
		material = Enum.Material.Grass,
	})
	buildLobby(map)
	local bases = Instance.new("Folder")
	bases.Name = "Bases"
	bases.Parent = map
	for index = 1, Config.BaseCount do
		buildBase(index, bases)
	end
	buildPaths(map)
	buildScenery(map)
	buildBoundary(map)
	map.Parent = parent
	return map
end

function MapBuilder.setSignText(base: Model, text: string)
	local sign = base:FindFirstChild("Sign")
	if sign then
		Props.setSignText(sign, text)
	end
end

return table.freeze(MapBuilder)
