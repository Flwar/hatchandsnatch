--!strict
--[[
	BaseService
	Assigns each player a free base when their data loads and frees it when they
	leave. Handles spawning at the base, the owner sign, pedestal unlock visuals and
	the shield collision groups (the owner walks through their own shield; everyone
	else is blocked while it is closed).

	If every base is taken, the player waits in the lobby and gets the next free base.
]]

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local MapBuilder = require(script.Parent.Parent:WaitForChild("World"):WaitForChild("MapBuilder"))
local Net = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Net"))

local BaseService = {}

-- Fired as (player, base) when a player gets a base, and (player, base) when they lose it.
BaseService.Assigned = Signal.new()
BaseService.Released = Signal.new()

local ownerOf: { [number]: Player } = {} -- base index -> owner
local baseOf: { [Player]: number } = {} -- owner -> base index
local waiting: { Player } = {} -- players waiting for a free base, in join order
local handled: { [Player]: boolean } = {} -- players whose data-loaded step already ran
local characterConnections: { [Player]: { RBXScriptConnection } } = {}

local function shieldGroup(index: number): string
	return `Shield{index}`
end

local function ownerGroup(index: number): string
	return `BaseOwner{index}`
end

local function groupFor(player: Player): string
	local index = baseOf[player]
	return if index then ownerGroup(index) else "Default"
end

local function setupCollisionGroups()
	for index, base in MapService.getBases() do
		PhysicsService:RegisterCollisionGroup(shieldGroup(index))
		PhysicsService:RegisterCollisionGroup(ownerGroup(index))
		PhysicsService:CollisionGroupSetCollidable(shieldGroup(index), ownerGroup(index), false)
		local shield = base:FindFirstChild("Shield")
		if shield and shield:IsA("BasePart") then
			(shield :: BasePart).CollisionGroup = shieldGroup(index)
		end
	end
end

local function setCharacterGroup(character: Model, group: string)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			(descendant :: BasePart).CollisionGroup = group
		end
	end
end

function BaseService.getBaseIndex(player: Player): number?
	return baseOf[player]
end

function BaseService.getBase(player: Player): Model?
	local index = baseOf[player]
	return if index then MapService.getBase(index) else nil
end

function BaseService.getOwner(index: number): Player?
	return ownerOf[index]
end

local function spawnLocationFor(player: Player): SpawnLocation?
	local base = BaseService.getBase(player)
	local spawn = if base then base:FindFirstChild("Spawn") else MapService.getLobby():FindFirstChild("LobbySpawn")
	if spawn and spawn:IsA("SpawnLocation") then
		return spawn :: SpawnLocation
	end
	return nil
end

local function refreshPedestals(base: Model, unlockedCount: number)
	local folder = base:FindFirstChild("Pedestals")
	if not folder then
		return
	end
	for _, pedestal in folder:GetChildren() do
		local slot = pedestal:GetAttribute("Slot")
		if pedestal:IsA("Model") and typeof(slot) == "number" then
			MapBuilder.setPedestalUnlocked(pedestal :: Model, slot <= unlockedCount)
		end
	end
end

-- Re-applies pedestal visuals, e.g. after the owner buys more pedestals.
function BaseService.refresh(player: Player)
	local base = BaseService.getBase(player)
	local data = DataService.get(player)
	if base and data then
		refreshPedestals(base, data.pedestals)
	end
end

local function loadCharacter(player: Player)
	if player.Parent == Players then
		player:LoadCharacterAsync()
	end
end

local function onCharacterAdded(player: Player, character: Model)
	setCharacterGroup(character, groupFor(player))
	local connections = characterConnections[player]
	if not connections then
		connections = {}
		characterConnections[player] = connections
	end
	table.insert(
		connections,
		character.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("BasePart") then
				(descendant :: BasePart).CollisionGroup = groupFor(player)
			end
		end)
	)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		local h = humanoid :: Humanoid
		h.WalkSpeed = Config.DefaultWalkSpeed
		h.Died:Connect(function()
			task.delay(Config.RespawnDelaySec, function()
				if player.Character == character then
					loadCharacter(player)
				end
			end)
		end)
	end
end

local function assign(player: Player, index: number)
	local base = MapService.getBase(index)
	assert(base, `BaseService: base {index} does not exist`)
	ownerOf[index] = player
	baseOf[player] = index
	base:SetAttribute("OwnerUserId", player.UserId)
	player:SetAttribute("BaseIndex", index)
	MapBuilder.setSignText(base, `{player.DisplayName}'s Base`)
	local data = DataService.get(player)
	refreshPedestals(base, if data then data.pedestals else Config.StartingPedestals)
	local spawn = spawnLocationFor(player)
	if spawn then
		player.RespawnLocation = spawn
	end
	local character = player.Character
	if character and spawn then
		-- The player was waiting in the lobby: move them into their new base.
		setCharacterGroup(character, ownerGroup(index))
		character:PivotTo(spawn.CFrame * CFrame.new(0, 4, 0))
	end
	BaseService.Assigned:fire(player, base)
end

local function firstFreeIndex(): number?
	for index = 1, #MapService.getBases() do
		if not ownerOf[index] then
			return index
		end
	end
	return nil
end

local function onDataLoaded(player: Player, _data: Types.PlayerData)
	if player.Parent ~= Players or handled[player] then
		return
	end
	handled[player] = true
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	local index = firstFreeIndex()
	if index then
		assign(player, index)
	else
		table.insert(waiting, player)
		local lobbySpawn = spawnLocationFor(player)
		if lobbySpawn then
			player.RespawnLocation = lobbySpawn
		end
		Net.notify(player, "Every base is taken right now. You'll get the next free one!", "warning")
	end
	loadCharacter(player)
end

local function onPlayerRemoving(player: Player)
	handled[player] = nil
	local waitingIndex = table.find(waiting, player)
	if waitingIndex then
		table.remove(waiting, waitingIndex)
	end
	local connections = characterConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	characterConnections[player] = nil
	local index = baseOf[player]
	if not index then
		return
	end
	local base = MapService.getBase(index)
	baseOf[player] = nil
	ownerOf[index] = nil
	if base then
		base:SetAttribute("OwnerUserId", 0)
		MapBuilder.setSignText(base, "Empty Base")
		refreshPedestals(base, 0)
		BaseService.Released:fire(player, base)
	end
	local nextPlayer = table.remove(waiting, 1)
	if nextPlayer and nextPlayer.Parent == Players then
		assign(nextPlayer, index)
		Net.notify(nextPlayer, "A base just opened up. It's yours!", "success")
	end
end

function BaseService.init()
	Players.CharacterAutoLoads = false
	setupCollisionGroups()
end

function BaseService.start()
	DataService.Loaded:connect(onDataLoaded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Catch players whose data finished loading before this service started.
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data then
			task.spawn(onDataLoaded, player, data)
		end
	end
end

return BaseService
