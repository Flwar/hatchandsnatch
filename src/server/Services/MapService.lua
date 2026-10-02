--!strict
--[[
	MapService
	Makes sure the world exists and gives other services typed access to it.
	If Workspace already contains a hand-built "Map" (same structure as MapBuilder
	produces), it is used as-is; otherwise the procedural placeholder map is built.
]]

local Workspace = game:GetService("Workspace")

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

return MapService
