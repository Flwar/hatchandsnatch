--!strict
--[[
	FusionService
	The Fusion Machine in each base turns two of the owner's adult creatures into one
	hybrid after Config.FusionTimeSec (see CreatureData for how hybrids are made).

	  1. The owner presses the machine's prompt; the client opens the Fusion window.
	  2. The client asks to fuse two creatures (StartFusion). The server checks the
	     owner, the distance to the machine, that both are their own adult originals,
	     standing on pedestals, and that the machine is free. Both creatures leave
	     their pedestals and wait in the machine's pods.
	  3. The job is saved in the player's data (parents included), so leaving or a
	     server shutdown loses nothing; the timer keeps running offline.
	  4. When the timer is up the hybrid is born as an adult on a free pedestal. With
	     no free pedestal it waits in the machine until one frees up.

	First discoveries: the first time anyone on any server makes a named recipe it is
	claimed in a global DataStore with an atomic UpdateAsync, then announced to this
	server and, through MessagingService, to every other one. Without DataStore access
	(Studio with API access off) claims fall back to this server's memory.
]]

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local FusionRecipes = require(Shared:WaitForChild("FusionRecipes"))
local Growth = require(Shared:WaitForChild("Growth"))
local Tags = require(Shared:WaitForChild("Tags"))
local Types = require(Shared:WaitForChild("Types"))
local CreatureModels = require(Shared:WaitForChild("Models"):WaitForChild("CreatureModels"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Util = script.Parent.Parent:WaitForChild("Util")
local Net = require(Util:WaitForChild("Net"))
local Guard = require(Util:WaitForChild("Guard"))
local Ticker = require(Util:WaitForChild("Ticker"))
local Character = require(Util:WaitForChild("Character"))
local RateLimiter = require(Util:WaitForChild("RateLimiter"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CreatureService = require(script.Parent:WaitForChild("CreatureService"))

type FusionJob = Types.FusionJob
type CreatureRecord = Types.CreatureRecord

local FusionService = {}

-- Fired as (player, job) when a fusion starts, and (player, record, isNew) when a hybrid is born.
FusionService.Started = Signal.new()
FusionService.Finished = Signal.new()

-- Hook for game passes: how long a fusion takes for this player.
FusionService.durationFor = function(_player: Player): number
	return Config.FusionTimeSec
end

local MINI_SCALE = 0.5
local RESULT_SCALE = 0.55

local discoveryStore: DataStore? = nil
local firsts: { [string]: { name: string, userId: number } } = {} -- named recipe id -> first discoverer
local waitingNotified: { [Player]: boolean } = {}
local claiming: { [string]: boolean } = {}

---------------------------------------------------------------------------
-- The machine in the world
---------------------------------------------------------------------------

local function machineOf(player: Player): Model?
	local base = BaseService.getBase(player)
	local machine = if base then base:FindFirstChild("FusionMachine") else nil
	return if machine and machine:IsA("Model") then machine :: Model else nil
end

local function socketOf(machine: Model, path: { string }): BasePart?
	local node: Instance? = machine
	for _, name in path do
		node = if node then node:FindFirstChild(name) else nil
	end
	return if node and node:IsA("BasePart") then node :: BasePart else nil
end

local function clearVisuals(machine: Model)
	for _, child in machine:GetChildren() do
		if child:GetAttribute("FusionVisual") then
			child:Destroy()
		end
	end
	machine:SetAttribute("State", "Idle")
	machine:SetAttribute("FusionEndsAt", 0)
	machine:SetAttribute("ResultName", "")
end

local function showMini(machine: Model, creatureId: string, socket: BasePart?, scale: number, mutation: Types.Mutation?)
	if not socket then
		return
	end
	local options: CreatureModels.BuildOptions = {
		stage = "Adult",
		origin = socket.CFrame * CFrame.new(0, socket.Size.Y / 2, 0),
		scale = scale,
		mutation = mutation,
	}
	local ok, model = pcall(CreatureModels.build, creatureId, options)
	if not ok then
		warn(`FusionService: couldn't build {creatureId}: {model}`)
		return
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			(part :: BasePart).CanQuery = false
		end
	end
	model:SetAttribute("FusionVisual", true)
	model.Parent = machine
	local root = model.PrimaryPart
	if root then
		root.Anchored = true
	end
end

-- Puts the machine's look in line with the player's saved job.
local function showJob(player: Player)
	local machine = machineOf(player)
	local data = DataService.get(player)
	if not machine then
		return
	end
	clearVisuals(machine)
	local job = if data then data.fusion else nil
	if not job then
		return
	end
	local a, b = job.parents[1], job.parents[2]
	showMini(machine, a.id, socketOf(machine, { "PodL", "Socket" }), MINI_SCALE, a.mutation)
	showMini(machine, b.id, socketOf(machine, { "PodR", "Socket" }), MINI_SCALE, b.mutation)
	local remaining = math.max(0, job.endsAt - os.time())
	machine:SetAttribute("FusionEndsAt", Workspace:GetServerTimeNow() + remaining)
	machine:SetAttribute("State", if remaining > 0 then "Fusing" else "Ready")
	if remaining <= 0 then
		local def = CreatureData.get(job.resultId)
		machine:SetAttribute("ResultName", if def then def.displayName else "")
		showMini(machine, job.resultId, socketOf(machine, { "Reactor", "ResultSocket" }), RESULT_SCALE, job.mutation)
	end
end

local function addPrompt(player: Player)
	local machine = machineOf(player)
	local panel = if machine then machine:FindFirstChild("Panel") else nil
	if not panel or not panel:IsA("BasePart") then
		return
	end
	local old = panel:FindFirstChild("FusePrompt")
	if old then
		old:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FusePrompt"
	prompt.ActionText = "Fuse"
	prompt.ObjectText = "Fusion Machine"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.FusionMachineRange * 0.6
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("OwnerUserId", player.UserId)
	CollectionService:AddTag(prompt, Tags.OwnerOnlyPrompt)
	prompt.Parent = panel
	-- The client opens the Fusion window itself; the server only collects a finished hybrid.
	prompt.Triggered:Connect(function(who: Player)
		if who == player and RateLimiter.allow(who, "FusionPrompt") then
			FusionService.tryFinish(who, true)
		end
	end)
end

local function removePrompt(base: Model?)
	local machine = if base then base:FindFirstChild("FusionMachine") else nil
	local panel = if machine then machine:FindFirstChild("Panel") else nil
	local prompt = if panel then panel:FindFirstChild("FusePrompt") else nil
	if prompt then
		prompt:Destroy()
	end
	if machine and machine:IsA("Model") then
		clearVisuals(machine :: Model)
	end
end

---------------------------------------------------------------------------
-- First discoveries
---------------------------------------------------------------------------

local function isRecipe(id: string): boolean
	for _, recipe in FusionRecipes.List do
		if recipe.id == id then
			return true
		end
	end
	return false
end

local function announceFirst(hybridId: string, discoverer: string)
	Net.fireAll("FirstDiscovery", hybridId, discoverer)
end

-- Claims a named recipe for `player` if nobody has it yet. Yields (DataStore).
local function claimFirst(player: Player, hybridId: string)
	if firsts[hybridId] or claiming[hybridId] then
		return
	end
	claiming[hybridId] = true
	local claimed = false
	local existing: any = nil
	local name = player.DisplayName
	local store = discoveryStore
	if store then
		local ok, err = pcall(function()
			store:UpdateAsync(hybridId, function(old: any)
				if type(old) == "table" and type(old.name) == "string" then
					-- Already taken: remember who has it and cancel the write.
					claimed, existing = false, old
					return nil
				end
				claimed, existing = true, nil
				return { userId = player.UserId, name = name, time = os.time() }
			end)
		end)
		if not ok then
			warn(`FusionService: first discovery claim failed ({err}); using this server only`)
			claimed = true
		end
	else
		claimed = true
	end
	if claimed then
		firsts[hybridId] = { name = name, userId = player.UserId }
	elseif existing then
		firsts[hybridId] = { name = existing.name, userId = tonumber(existing.userId) or 0 }
	end
	claiming[hybridId] = nil
	if not claimed then
		return
	end
	announceFirst(hybridId, name)
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(Config.DiscoveryTopic, {
				id = hybridId,
				name = name,
				userId = player.UserId,
				job = game.JobId,
			})
		end)
		if not ok then
			warn(`FusionService: couldn't tell other servers about a first discovery: {err}`)
		end
	end)
end

local function loadFirsts()
	local store = discoveryStore
	if not store then
		return
	end
	for _, recipe in FusionRecipes.List do
		local ok, value = pcall(function()
			return store:GetAsync(recipe.id)
		end)
		if ok and type(value) == "table" and type(value.name) == "string" and not firsts[recipe.id] then
			firsts[recipe.id] = { name = value.name, userId = tonumber(value.userId) or 0 }
		end
	end
end

local function listenForFirsts()
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(Config.DiscoveryTopic, function(message: any)
			local payload = if type(message) == "table" then message.Data else nil
			if type(payload) ~= "table" or payload.job == game.JobId then
				return
			end
			local id, name = payload.id, payload.name
			if type(id) ~= "string" or not isRecipe(id) or type(name) ~= "string" or #name > 40 then
				return
			end
			if not firsts[id] then
				firsts[id] = { name = name, userId = tonumber(payload.userId) or 0 }
				announceFirst(id, name)
			end
		end)
	end)
	if not ok then
		warn(`FusionService: cross-server discovery banners are off ({err})`)
	end
end

-- Named recipe id -> who discovered it first, for the Index.
function FusionService.firsts(): { [string]: string }
	local out = {}
	for id, entry in firsts do
		out[id] = entry.name
	end
	return out
end

---------------------------------------------------------------------------
-- Fusing
---------------------------------------------------------------------------

-- Places a finished hybrid if its timer is up and a pedestal is free.
-- `fromPrompt` gives the owner feedback when it can't happen yet.
function FusionService.tryFinish(player: Player, fromPrompt: boolean?): boolean
	local data = DataService.get(player)
	local job = if data then data.fusion else nil
	if not data or not job or os.time() < job.endsAt then
		return false
	end
	if not CreatureService.freeSlot(player) then
		if fromPrompt or not waitingNotified[player] then
			waitingNotified[player] = true
			Net.notify(player, "Your hybrid is ready! Free up a pedestal to bring it home.", "warning")
		end
		return false
	end
	local def = CreatureData.get(job.resultId)
	if not def then
		-- Shouldn't happen (ids are checked on start and on load); give the parents back.
		data.fusion = nil
		for _, parent in job.parents do
			CreatureService.add(player, parent.id, parent.plantedAt, parent.mutation)
		end
		showJob(player)
		return false
	end
	local isNew = not data.discoveries[job.resultId]
	local plantedAt = os.time() - def.growTimeSec
	local record = CreatureService.add(player, job.resultId, plantedAt, job.mutation)
	if not record then
		return false
	end
	data.fusion = nil
	waitingNotified[player] = nil
	showJob(player)
	Net.fire(player, "FusionDone", job.resultId, isNew)
	FusionService.Finished:fire(player, record, isNew)
	if def.recipe and not firsts[def.id] then
		task.spawn(claimFirst, player, def.id)
	end
	DataService.save(player)
	return true
end

local function isAdult(record: CreatureRecord): boolean
	local def = CreatureData.get(record.id)
	return def ~= nil and Growth.stage(def.growTimeSec, record.plantedAt, os.time()) == "Adult"
end

local function onStartFusion(player: Player, uidA: string, uidB: string)
	local data = DataService.get(player)
	local machine = machineOf(player)
	local panel = if machine then machine:FindFirstChild("Panel") else nil
	if not data or not machine or not panel or not panel:IsA("BasePart") or uidA == uidB then
		return
	end
	if data.fusion then
		Net.notify(player, "Your Fusion Machine is busy!", "warning")
		return
	end
	if not Character.isNear(player, (panel :: BasePart).Position, Config.FusionMachineRange) then
		return
	end
	local a, b = CreatureService.get(uidA), CreatureService.get(uidB)
	if not a or not b or a.owner ~= player or b.owner ~= player or a.state ~= "Placed" or b.state ~= "Placed" then
		Net.notify(player, "Both creatures must be standing on your pedestals.", "warning")
		return
	end
	if not isAdult(a.record) or not isAdult(b.record) then
		Net.notify(player, "Only adults can be fused.", "warning")
		return
	end
	local resultId = CreatureData.fuse(a.record.id, b.record.id)
	if not resultId then
		Net.notify(player, "Those two can't be fused (two different originals only).", "warning")
		return
	end
	local recordA = CreatureService.remove(uidA, "fused")
	local recordB = CreatureService.remove(uidB, "fused")
	if not recordA or not recordB then
		-- Something changed under us; put back whatever was taken.
		for _, record in { recordA, recordB } do
			if record then
				CreatureService.add(player, record.id, record.plantedAt, record.mutation)
			end
		end
		return
	end
	local job: FusionJob = {
		parents = { recordA, recordB },
		resultId = resultId,
		mutation = if recordA.mutation and recordA.mutation == recordB.mutation then recordA.mutation else nil,
		endsAt = os.time() + math.max(1, math.floor(FusionService.durationFor(player))),
	}
	data.fusion = job
	showJob(player)
	FusionService.Started:fire(player, job)
	DataService.save(player)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function FusionService.init()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(Config.DiscoveryStoreName)
	end)
	if ok then
		discoveryStore = store
	else
		warn(`FusionService: no DataStore access, first discoveries are per server ({store})`)
	end
	DataService.firsts = FusionService.firsts
end

function FusionService.start()
	BaseService.Assigned:connect(function(player: Player)
		addPrompt(player)
		local data = DataService.get(player)
		-- Saves from before validation: drop jobs whose result no longer exists.
		if data and data.fusion and not CreatureData.get(data.fusion.resultId) then
			local job = data.fusion
			data.fusion = nil
			for _, parent in job.parents do
				CreatureService.add(player, parent.id, parent.plantedAt, parent.mutation)
			end
		end
		showJob(player)
	end)
	BaseService.Released:connect(function(player: Player, base: Model)
		waitingNotified[player] = nil
		removePrompt(base)
	end)
	for _, player in Players:GetPlayers() do
		if BaseService.getBase(player) then
			addPrompt(player)
			showJob(player)
		end
	end
	Net.onEvent("StartFusion", { Guard.uid(), Guard.uid() }, onStartFusion)
	Ticker.every("Fusion", 1, function()
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			local job = if data then data.fusion else nil
			if job and os.time() >= job.endsAt then
				local machine = machineOf(player)
				if machine and machine:GetAttribute("State") == "Fusing" then
					showJob(player)
				end
				FusionService.tryFinish(player)
			end
		end
	end)
	task.spawn(loadFirsts)
	task.spawn(listenForFirsts)
end

return FusionService
