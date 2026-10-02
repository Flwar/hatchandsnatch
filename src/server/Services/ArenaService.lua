--!strict
--[[
	ArenaService
	1v1 creature battles. A player picks up to Config.ArenaTeamSize of their adult
	creatures and asks for a match (FindMatch):

	  * if another player with a similar trophy count is waiting, they fight each other
	  * otherwise the player waits up to Config.ArenaQueueWaitSec, then a bot steps in
	    with a team that mirrors theirs (shared/ArenaBots)

	The battle is simulated on the server in one go (shared/ArenaBattle) and the event
	log is sent to the players to play back. Winners get trophies right away; losing
	costs nothing. Creatures never leave their pedestals: the arena uses copies.

	Trophies go to an OrderedDataStore leaderboard (top Config.LeaderboardSize shown
	on the lobby board and in the Arena window). Without DataStore access (Studio) the
	board ranks the players on this server.

	Arena ranks (Config.ArenaRanks) unlock arena-only cosmetics: the "ArenaRank"
	player attribute (overhead title, drawn by the client) and a trophy statue in the
	player's base.
]]

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ArenaBattle = require(Shared:WaitForChild("ArenaBattle"))
local ArenaBots = require(Shared:WaitForChild("ArenaBots"))
local ArenaStats = require(Shared:WaitForChild("ArenaStats"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Growth = require(Shared:WaitForChild("Growth"))
local Tags = require(Shared:WaitForChild("Tags"))
local Types = require(Shared:WaitForChild("Types"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Util = script.Parent.Parent:WaitForChild("Util")
local Net = require(Util:WaitForChild("Net"))
local Guard = require(Util:WaitForChild("Guard"))
local Ticker = require(Util:WaitForChild("Ticker"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CreatureService = require(script.Parent:WaitForChild("CreatureService"))
local MapService = require(script.Parent:WaitForChild("MapService"))

local World = script.Parent.Parent:WaitForChild("World")
local ArenaProps = require(World:WaitForChild("ArenaProps"))
local MapBuilder = require(World:WaitForChild("MapBuilder"))

type FighterSpec = ArenaBattle.FighterSpec

type Ticket = {
	player: Player,
	team: { FighterSpec },
	trophies: number,
	since: number, -- os.clock()
}

local ArenaService = {}

-- Fired as (player, won: boolean, gained: number) after every battle.
ArenaService.Finished = Signal.new()

local rng = Random.new()
local queue: { Ticket } = {}
local cooldownUntil: { [Player]: number } = {}
local lastWrite: { [Player]: number } = {}
local dirty: { [Player]: boolean } = {}

local trophyStore: OrderedDataStore? = nil
local storeWorks = false -- the last leaderboard read succeeded
local warnedRead = false
local top: { Types.LeaderboardEntry } = {}
local nameCache: { [number]: string } = {}

---------------------------------------------------------------------------
-- Ranks and cosmetics
---------------------------------------------------------------------------

local TROPHY_OFFSET = Vector3.new(-21, MapBuilder.FloorHeight, -29) -- base-local, by the entrance

local function refreshCosmetics(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local rank = ArenaStats.rank(data.trophies)
	player:SetAttribute("Trophies", data.trophies)
	player:SetAttribute("ArenaRank", rank)
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = if leaderstats then leaderstats:FindFirstChild("Trophies") else nil
	if value and value:IsA("IntValue") then
		(value :: IntValue).Value = data.trophies
	end
	local base = BaseService.getBase(player)
	if not base then
		return
	end
	local existing = base:FindFirstChild("ArenaTrophy")
	if existing and existing:GetAttribute("Rank") == rank then
		return
	end
	if existing then
		existing:Destroy()
	end
	if rank > 0 then
		local frame = base:GetAttribute("BaseCFrame")
		if typeof(frame) == "CFrame" then
			ArenaProps.trophy(frame * CFrame.new(TROPHY_OFFSET), rank, base)
		end
	end
end

---------------------------------------------------------------------------
-- Leaderboard
---------------------------------------------------------------------------

local function nameOf(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		nameCache[userId] = online.DisplayName
		return online.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else `Player {userId}`
	nameCache[userId] = result
	return result
end

local function localTop(): { Types.LeaderboardEntry }
	local entries: { Types.LeaderboardEntry } = {}
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data and data.trophies > 0 then
			table.insert(
				entries,
				{ rank = 0, userId = player.UserId, name = player.DisplayName, trophies = data.trophies }
			)
		end
	end
	table.sort(entries, function(a, b)
		return a.trophies > b.trophies
	end)
	local out = {}
	for i = 1, math.min(#entries, Config.LeaderboardSize) do
		local entry = entries[i]
		entry.rank = i
		table.insert(out, entry)
	end
	return out
end

local function showBoard()
	local lobby = MapService.getLobby()
	local board = if lobby then lobby:FindFirstChild("ArenaBoard") else nil
	local panel = if board then board:FindFirstChild("Board") else nil
	local gui = if panel then panel:FindFirstChild("LeaderboardGui") else nil
	local rows = if gui then gui:FindFirstChild("Rows") else nil
	if not rows then
		return
	end
	for i = 1, Config.LeaderboardSize do
		local row = rows:FindFirstChild(`Row{i}`)
		if row and row:IsA("TextLabel") then
			local entry = top[i]
			if entry then
				(row :: TextLabel).Text = `{entry.rank}. {entry.name}  🏆 {entry.trophies}`
			else
				(row :: TextLabel).Text = if i == 1 and #top == 0 then "Win arena battles to get on the board!" else ""
			end
		end
	end
end

local function refreshTop()
	local store = trophyStore
	local fresh: { Types.LeaderboardEntry }? = nil
	if store then
		local ok, result = pcall(function()
			local pages = store:GetSortedAsync(false, Config.LeaderboardSize)
			return pages:GetCurrentPage()
		end)
		if ok and type(result) == "table" then
			local entries: { Types.LeaderboardEntry } = {}
			for index, item in result do
				local userId = tonumber(item.key)
				local value = tonumber(item.value)
				if userId and value then
					table.insert(entries, { rank = index, userId = userId, name = nameOf(userId), trophies = value })
				end
			end
			fresh = entries
		elseif not warnedRead then
			warnedRead = true
			warn(`ArenaService: leaderboard read failed ({result}); showing this server only`)
		end
	end
	storeWorks = fresh ~= nil
	top = fresh or localTop()
	showBoard()
end

local function writeTrophies(player: Player, force: boolean?)
	local data = DataService.get(player)
	local store = trophyStore
	if not data or not store or not dirty[player] then
		return
	end
	if not force and os.clock() - (lastWrite[player] or 0) < Config.LeaderboardWriteSec then
		return
	end
	dirty[player] = nil
	lastWrite[player] = os.clock()
	local trophies, userId = data.trophies, player.UserId
	task.spawn(function()
		local ok, err = pcall(function()
			store:SetAsync(tostring(userId), trophies)
		end)
		if not ok then
			warn(`ArenaService: couldn't save trophies to the leaderboard: {err}`)
		end
	end)
end

function ArenaService.leaderboard(player: Player): Types.LeaderboardSummary
	local data = DataService.get(player)
	local mine: number? = nil
	for _, entry in top do
		if entry.userId == player.UserId then
			mine = entry.rank
		end
	end
	return { top = table.clone(top), trophies = if data then data.trophies else 0, rank = mine }
end

---------------------------------------------------------------------------
-- Matches
---------------------------------------------------------------------------

local function removeTicket(player: Player): boolean
	for i, ticket in queue do
		if ticket.player == player then
			table.remove(queue, i)
			return true
		end
	end
	return false
end

-- The player's chosen team as fighter specs, or nil (with a message) if it isn't valid.
local function buildTeam(player: Player, uids: { string }): { FighterSpec }?
	local seen: { [string]: boolean } = {}
	local team: { FighterSpec } = {}
	local now = os.time()
	for _, uid in uids do
		if seen[uid] then
			return nil
		end
		seen[uid] = true
		local entry = CreatureService.get(uid)
		if not entry or entry.owner ~= player or entry.state ~= "Placed" then
			Net.notify(player, "Your fighters must be standing on your pedestals.", "warning")
			return nil
		end
		local def = CreatureData.get(entry.record.id)
		if not def or Growth.stage(def.growTimeSec, entry.record.plantedAt, now) ~= "Adult" then
			Net.notify(player, "Only adults can fight in the arena.", "warning")
			return nil
		end
		table.insert(team, { id = entry.record.id, mutation = entry.record.mutation :: string? })
	end
	return team
end

local function reward(player: Player, won: boolean, gained: number): (number, boolean)
	local data = DataService.get(player)
	if not data then
		return 0, false
	end
	local before = ArenaStats.rank(data.trophies)
	data.arenaBattles += 1
	if won then
		data.arenaWins += 1
		data.trophies += gained
		dirty[player] = true
	end
	refreshCosmetics(player)
	local rankUp = ArenaStats.rank(data.trophies) > before
	if rankUp then
		local tier = Config.ArenaRanks[ArenaStats.rank(data.trophies)]
		Net.notify(player, `🏆 You reached {tier.name} rank! New title and trophy unlocked.`, "success")
	end
	writeTrophies(player)
	return data.trophies, rankUp
end

local function send(
	player: Player,
	side: string,
	opponent: string,
	bot: boolean,
	result: ArenaBattle.Result,
	gained: number
)
	local won = result.winner == side
	local trophies, rankUp = reward(player, won, if won then gained else 0)
	local report: ArenaBattle.Report = {
		side = side,
		opponent = opponent,
		bot = bot,
		winner = result.winner,
		fighters = result.fighters,
		events = result.events,
		gained = if won then gained else 0,
		trophies = trophies,
		rankUp = rankUp,
	}
	cooldownUntil[player] = os.clock() + Config.ArenaCooldownSec
	Net.fire(player, "BattleStarted", report)
	ArenaService.Finished:fire(player, won, report.gained)
end

local function fightPlayers(a: Ticket, b: Ticket)
	local result = ArenaBattle.run(a.team, b.team, rng:NextInteger(1, 2 ^ 30))
	send(a.player, "A", b.player.DisplayName, false, result, Config.ArenaWinTrophies)
	send(b.player, "B", a.player.DisplayName, false, result, Config.ArenaWinTrophies)
end

local function fightBot(ticket: Ticket)
	local botTeam, botName = ArenaBots.team(ticket.team, ticket.trophies, rng)
	local result = ArenaBattle.run(ticket.team, botTeam, rng:NextInteger(1, 2 ^ 30))
	send(ticket.player, "A", botName, true, result, Config.ArenaBotWinTrophies)
end

local function onFindMatch(player: Player, uids: { string })
	local data = DataService.get(player)
	if not data then
		return
	end
	if os.clock() < (cooldownUntil[player] or 0) then
		Net.notify(player, "Catch your breath! Next battle in a few seconds.", "info")
		return
	end
	local team = buildTeam(player, uids)
	if not team or #team == 0 then
		return
	end
	removeTicket(player)
	local ticket: Ticket = { player = player, team = team, trophies = data.trophies, since = os.clock() }
	-- A real opponent close in trophies wins over a bot.
	for i, other in queue do
		if math.abs(other.trophies - ticket.trophies) <= Config.ArenaMatchRange and other.player.Parent == Players then
			table.remove(queue, i)
			fightPlayers(other, ticket)
			return
		end
	end
	table.insert(queue, ticket)
	Net.fire(player, "ArenaQueued", Config.ArenaQueueWaitSec)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

local function addDeskPrompt()
	local lobby = MapService.getLobby()
	local board = if lobby then lobby:FindFirstChild("ArenaBoard") else nil
	local desk = if board then board:FindFirstChild("Desk") else nil
	if not desk or not desk:IsA("BasePart") or desk:FindFirstChild("ArenaPrompt") then
		return
	end
	-- Everyone can use the desk; it only opens the Arena window on the client.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ArenaPrompt"
	prompt.ActionText = "Battle!"
	prompt.ObjectText = "Creature Arena"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = desk
	CollectionService:AddTag(prompt, Tags.ArenaPrompt)
end

function ArenaService.init()
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName)
	end)
	if ok then
		trophyStore = store
	else
		warn(`ArenaService: no leaderboard DataStore ({store}); ranking this server only`)
	end
end

function ArenaService.start()
	local function setup(player: Player)
		local leaderstats = player:WaitForChild("leaderstats", 10)
		if leaderstats and not leaderstats:FindFirstChild("Trophies") then
			local value = Instance.new("IntValue")
			value.Name = "Trophies"
			value.Parent = leaderstats
		end
		refreshCosmetics(player)
	end
	DataService.Loaded:connect(function(player: Player)
		task.spawn(setup, player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.get(player) then
			task.spawn(setup, player)
		end
	end
	BaseService.Assigned:connect(function(player: Player)
		refreshCosmetics(player)
	end)
	BaseService.Released:connect(function(_player: Player, base: Model)
		local trophy = base:FindFirstChild("ArenaTrophy")
		if trophy then
			trophy:Destroy()
		end
	end)
	DataService.Releasing:connect(function(player: Player)
		removeTicket(player)
		writeTrophies(player, true)
		cooldownUntil[player] = nil
		lastWrite[player] = nil
		dirty[player] = nil
	end)
	Net.onEvent("FindMatch", { Guard.list(Guard.uid(), 1, Config.ArenaTeamSize) }, onFindMatch)
	Net.onEvent("CancelMatch", {}, function(player: Player)
		if removeTicket(player) then
			Net.notify(player, "Left the arena queue.", "info")
		end
	end)
	Net.onInvoke("GetLeaderboard", {}, function(player: Player): any
		return ArenaService.leaderboard(player)
	end)
	Ticker.every("ArenaQueue", 1, function()
		local now = os.clock()
		for i = #queue, 1, -1 do
			local ticket = queue[i]
			if ticket.player.Parent ~= Players then
				table.remove(queue, i)
			elseif now - ticket.since >= Config.ArenaQueueWaitSec then
				table.remove(queue, i)
				fightBot(ticket)
			end
		end
		for player in dirty do
			writeTrophies(player)
		end
	end)
	addDeskPrompt()
	task.spawn(refreshTop)
	Ticker.every("Leaderboard", Config.LeaderboardRefreshSec, function()
		task.spawn(refreshTop)
	end)
	-- Keep the local fallback board fresh when there is no DataStore.
	Ticker.every("LeaderboardLocal", 15, function()
		if not storeWorks then
			top = localTop()
			showBoard()
		end
	end)
end

return ArenaService
