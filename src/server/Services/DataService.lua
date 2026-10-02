--!strict
--[[
	DataService
	Owns every player's PlayerData for the session. Data is stored with ProfileStore
	(session-locked, so the same profile can never be open on two servers at once):

	  * load on join (StartSessionAsync), fill missing fields, then run migrate()
	  * auto-save every Config.AutoSaveSec on the shared Ticker
	  * save and release on leave; ProfileStore also saves every session on shutdown

	On load it also pays out offline earnings (capped at Config.OfflineIncomeCapHours)
	and shows the "While you were away" popup once the client is ready.

	In Studio without API access ProfileStore falls back to a mock store, so data
	only survives a Studio restart when "Enable Studio Access to API Services" is on.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Offline = require(Shared:WaitForChild("Offline"))
local Types = require(Shared:WaitForChild("Types"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Net = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Net"))
local Ticker = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ticker"))
local DataSchema = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("DataSchema"))
local Guard = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Guard"))
local ProfileStore = require(script.Parent.Parent:WaitForChild("Packages"):WaitForChild("ProfileStore")) :: any

type PlayerData = Types.PlayerData

local DataService = {}

-- Fired as (player, data) once a player's data is ready. Other services start from here.
DataService.Loaded = Signal.new()
-- Fired as (player, data) just before a player's data is saved and released.
DataService.Releasing = Signal.new()
-- Hooks other services can set to add multipliers to offline income (passes etc).
DataService.offlineMultiplier = function(_player: Player): number
	return 1
end
-- Hook FusionService fills in: named recipe id -> who discovered it first.
DataService.firsts = function(): { [string]: string }
	return {}
end

local playerStore: any = nil
local sessions: { [Player]: PlayerData } = {}
local profiles: { [Player]: any } = {}
local joinedAt: { [Player]: number } = {}
local clientReady: { [Player]: boolean } = {}
local pendingOffline: { [Player]: { coins: number, seconds: number } } = {}

DataService.template = DataSchema.template
DataService.migrate = DataSchema.migrate

function DataService.get(player: Player): PlayerData?
	return sessions[player]
end

-- The ProfileStore profile behind a player's data (receipt handling needs it).
function DataService.getProfile(player: Player): any
	return profiles[player]
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

-- Re-sends coin attributes after another service changed data.coins directly.
function DataService.refresh(player: Player)
	local data = sessions[player]
	if data then
		mirror(player, data)
	end
end

-- Total playtime including the current session, in seconds.
function DataService.playtime(player: Player): number
	local data = sessions[player]
	if not data then
		return 0
	end
	return data.totalPlaytime + (os.time() - (joinedAt[player] or os.time()))
end

-- Asks ProfileStore to save soon (it batches and rate-limits writes itself).
function DataService.save(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile:Save()
	end
end

local function createLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("StringValue")
	coins.Name = "Coins"
	coins.Value = "0"
	coins.Parent = leaderstats
	leaderstats.Parent = player
end

local function sendOfflinePopup(player: Player)
	local pending = pendingOffline[player]
	if pending and clientReady[player] then
		pendingOffline[player] = nil
		Net.fire(player, "OfflineEarnings", pending.coins, pending.seconds)
	end
end

local function load(player: Player)
	local profile = playerStore:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function(): boolean
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		if player.Parent == Players then
			player:Kick("Your data couldn't be loaded right now. Please rejoin in a moment!")
		end
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		sessions[player] = nil
		if player.Parent == Players then
			player:Kick("Your data was opened on another server. Please rejoin!")
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	local data = DataService.migrate(profile.Data)
	profiles[player] = profile
	sessions[player] = data
	joinedAt[player] = os.time()

	-- Offline earnings go straight into the balance; growth needs nothing (timestamps).
	local coins, seconds =
		Offline.earnings(data.creatures, data.lastLogout, os.time(), DataService.offlineMultiplier(player))
	if coins > 0 then
		data.coins += coins
	end
	if data.lastLogout > 0 and seconds >= Config.OfflinePopupMinSec then
		pendingOffline[player] = { coins = coins, seconds = seconds }
	end

	createLeaderstats(player)
	mirror(player, data)
	DataService.Loaded:fire(player, data)
	sendOfflinePopup(player)
end

local function release(player: Player)
	clientReady[player] = nil
	pendingOffline[player] = nil
	local data = sessions[player]
	local profile = profiles[player]
	if data then
		DataService.Releasing:fire(player, data)
		data.totalPlaytime += os.time() - (joinedAt[player] or os.time())
		data.lastLogout = os.time()
	end
	sessions[player] = nil
	profiles[player] = nil
	joinedAt[player] = nil
	if profile and profile:IsActive() then
		profile:EndSession()
	end
end

function DataService.init()
	playerStore = ProfileStore.New(Config.DataStoreName, DataService.template())
end

function DataService.start()
	Net.onInvoke("GetProfile", {}, function(player: Player): any
		local data = sessions[player]
		if not data then
			return nil
		end
		local discoveries = {}
		for id in data.discoveries do
			table.insert(discoveries, id)
		end
		local summary: Types.ProfileSummary = {
			discoveries = discoveries,
			trophies = data.trophies,
			settings = table.clone(data.settings),
			pedestals = data.pedestals,
			traps = table.clone(data.traps),
			firsts = DataService.firsts(),
			arenaWins = data.arenaWins,
			arenaBattles = data.arenaBattles,
			bonusPedestals = data.bonusPedestals,
		}
		return summary
	end)
	Net.onEvent(
		"SaveSettings",
		{ Guard.boolean(), Guard.boolean() },
		function(player: Player, sfx: boolean, labels: boolean)
			local data = sessions[player]
			if data then
				data.settings.sfx = sfx
				data.settings.labels = labels
			end
		end
	)
	Net.onEvent("ClientReady", {}, function(player: Player)
		if clientReady[player] then
			return
		end
		clientReady[player] = true
		Net.notify(player, `Welcome to Hatch & Snatch, {player.DisplayName}!`, "success")
		sendOfflinePopup(player)
	end)
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Ticker.every("AutoSave", Config.AutoSaveSec, function()
		for player in profiles do
			DataService.save(player)
		end
	end)
	game:BindToClose(function()
		-- PlayerRemoving does not always run before shutdown; record logout times now.
		-- ProfileStore's own BindToClose then waits for every session to save.
		for player in table.clone(sessions) do
			release(player)
		end
	end)
end

return DataService
