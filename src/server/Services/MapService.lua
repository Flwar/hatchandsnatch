--!strict
--[[
	MapService
	Makes sure the world exists and gives other services typed access to it.
	If Workspace already contains a hand-built "Map" (same structure as MapBuilder
	produces), it is used as-is; otherwise the procedural placeholder map is built.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MapBuilder = require(script.Parent.Parent:WaitForChild("World"):WaitForChild("MapBuilder"))

local MapService = {}

local map: Model? = nil
local bases: { Model } = {}

function MapService.init()
	local existing = Workspace:FindFirstChild("Map")
	local world: Model = if existing and existing:IsA("Model") then existing :: Model else MapBuilder.build(Workspace)
	map = world
	for _, child in world:WaitForChild("Bases"):GetChildren() do
		local index = child:GetAttribute("BaseIndex")
		if child:IsA("Model") and typeof(index) == "number" then
			bases[index] = child :: Model
		end
	end
	assert(#bases > 0, "MapService: the map has no bases")
end

function MapService.start() end

function MapService.getMap(): Model
	assert(map, "MapService not initialised")
	return map
end

function MapService.getBases(): { Model }
	return bases
end

function MapService.getBase(index: number): Model?
	return bases[index]
end

function MapService.getLobby(): Model
	return MapService.getMap():WaitForChild("Lobby") :: Model
end

-- The base's frame: origin on the floor centre, -Z facing the lobby.
function MapService.baseCFrame(base: Model): CFrame
	local cf = base:GetAttribute("BaseCFrame")
	assert(typeof(cf) == "CFrame", "Base is missing its BaseCFrame attribute")
	return cf
end

local ZONE_HEIGHT = 60

-- True if `position` is inside the walls of `base`.
function MapService.isInBase(base: Model, position: Vector3): boolean
	local localPos = MapService.baseCFrame(base):PointToObjectSpace(position)
	local half = Config.Map.BaseSize / 2 - 0.5
	return math.abs(localPos.X) < half and math.abs(localPos.Z) < half and localPos.Y > -5 and localPos.Y < ZONE_HEIGHT
end

-- The base (and its index) containing `position`, if any.
function MapService.baseAt(position: Vector3): (Model?, number?)
	for index, base in bases do
		if MapService.isInBase(base, position) then
			return base, index
		end
	end
	return nil, nil
end

-- A spot just outside the base entrance, facing away from the base (for teleporting raiders out).
function MapService.outsideEntrance(base: Model): CFrame
	local cf = MapService.baseCFrame(base)
	return cf * CFrame.new(0, 3, -Config.Map.BaseSize / 2 - 7) * CFrame.Angles(0, math.pi, 0)
end

-- A point just inside the entrance, on the floor (a waypoint for walking creatures).
function MapService.insideEntrance(base: Model): Vector3
	return (MapService.baseCFrame(base) * CFrame.new(0, MapBuilder.FloorHeight, -Config.Map.BaseSize / 2 + 5)).Position
end

return MapService
