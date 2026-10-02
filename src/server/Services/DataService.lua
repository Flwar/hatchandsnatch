--!strict
--[[
	DataService
	Owns every player's PlayerData for the session: creates it from the template,
	migrates old schema versions, exposes safe coin helpers and mirrors the values
	the client needs (Coins attribute + leaderstats).

	Milestone 0 keeps data in memory only. Milestone 2 swaps the load/release
	internals for ProfileStore (session-locked saves) without changing this API.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

type PlayerData = Types.PlayerData

local DataService = {}

-- Fired as (player, data) once a player's data is ready. Other services start from here.
DataService.Loaded = Signal.new()
-- Fired as (player, data) just before a player's data is released.
DataService.Releasing = Signal.new()

local sessions: { [Player]: PlayerData } = {}
local joinedAt: { [Player]: number } = {}

function DataService.template(): PlayerData
	return {
		version = Config.DataSchemaVersion,
		coins = Config.StartingCoins,
		padCoins = 0,
		pedestals = Config.StartingPedestals,
		creatures = {},
		traps = {},
		discoveries = {},
		trophies = 0,
		totalPlaytime = 0,
		lastLogout = 0,
		receipts = {},
		funnel = {},
	}
end

-- Brings saved data of any older version up to Config.DataSchemaVersion and fills
-- in fields added since it was saved. Add a step here whenever the schema changes.
function DataService.migrate(raw: { [string]: any }): PlayerData
	local template = DataService.template() :: any
	for key, value in template do
		if raw[key] == nil then
			raw[key] = value
		end
	end
	local version = tonumber(raw.version) or 0
	-- Example for the future:
	-- if version < 2 then raw.newField = ...; version = 2 end
	raw.version = math.max(version, Config.DataSchemaVersion)
	raw.coins = math.max(0, tonumber(raw.coins) or 0)
	raw.padCoins = math.max(0, tonumber(raw.padCoins) or 0)
	raw.pedestals = math.clamp(
		math.floor(tonumber(raw.pedestals) or Config.StartingPedestals),
		Config.StartingPedestals,
		Config.MaxPedestals
	)
	return raw :: PlayerData
end

function DataService.get(player: Player): PlayerData?
	return sessions[player]
end

local function mirror(player: Player, data: PlayerData)
	player:SetAttribute("Coins", data.coins)
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = if leaderstats then leaderstats:FindFirstChild("Coins") else nil
	if coins and coins:IsA("StringValue") then
		(coins :: StringValue).Value = Format.short(data.coins)
	end
end

function DataService.getCoins(player: Player): number
	local data = sessions[player]
	return if data then data.coins else 0
end

-- Adds (or removes, with a negative amount) coins. Returns the new balance.
function DataService.addCoins(player: Player, amount: number): number
	local data = sessions[player]
	assert(data, "DataService.addCoins: player has no data")
	assert(amount == amount and math.abs(amount) ~= math.huge, "DataService.addCoins: invalid amount")
	data.coins = math.max(0, data.coins + amount)
	mirror(player, data)
	return data.coins
end

-- Spends coins only if the player can afford it. Returns true on success.
function DataService.trySpend(player: Player, cost: number): boolean
	local data = sessions[player]
	if not data or cost < 0 or cost ~= cost or data.coins < cost then
		return false
	end
	data.coins -= cost
	mirror(player, data)
	return true
end

local function createLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("StringValue")
	coins.Name = "Coins"
	coins.Value = "0"
	coins.Parent = leaderstats
	leaderstats.Parent = player
end

local function load(player: Player)
	-- Milestone 2: replace with ProfileStore:StartSessionAsync + migrate(profile.Data).
	local data = DataService.migrate(DataService.template() :: any)
	if player.Parent ~= Players then
		return
	end
	sessions[player] = data
	joinedAt[player] = os.time()
	createLeaderstats(player)
	mirror(player, data)
	DataService.Loaded:fire(player, data)
end

local function release(player: Player)
	local data = sessions[player]
	if not data then
		return
	end
	DataService.Releasing:fire(player, data)
	data.totalPlaytime += os.time() - (joinedAt[player] or os.time())
	data.lastLogout = os.time()
	-- Milestone 2: profile:EndSession() saves and releases the session lock here.
	sessions[player] = nil
	joinedAt[player] = nil
end

-- Total playtime including the current session, in seconds.
function DataService.playtime(player: Player): number
	local data = sessions[player]
	if not data then
		return 0
	end
	return data.totalPlaytime + (os.time() - (joinedAt[player] or os.time()))
end

function DataService.init() end

function DataService.start()
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
end

return DataService
