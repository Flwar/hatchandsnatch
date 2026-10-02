--!strict
--[[
	CreatureService
	Owns every creature in a base: the CreatureRecord in the owner's data and the
	Model standing on its pedestal. Other systems go through this service to add,
	remove, re-stage, lock, carry or transfer creatures, so data and world never
	drift apart.

	A creature is in one of three states:
	  Placed     standing on its pedestal (earns income when adult)
	  Carried    held overhead by a raider (still belongs to its owner)
	  Returning  dropped by a raider and walking home (RaidService moves it)

	Models are tagged "Creature" and carry attributes the client reads for labels
	and animation: Uid, OwnerUserId, Slot, PlantedAt, GrowTimeSec, Stage,
	StageChangedAt, Mutation, Locked. Each model gets owner-only "Sell" and "Lock"
	prompts; RaidService adds a "Steal" prompt to adults through ModelSpawned.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local CreatureModels = require(Shared:WaitForChild("Models"):WaitForChild("CreatureModels"))
local Economy = require(Shared:WaitForChild("Economy"))
local Growth = require(Shared:WaitForChild("Growth"))
local Types = require(Shared:WaitForChild("Types"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Tags = require(Shared:WaitForChild("Tags"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local Character = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Character"))
local Guard = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Guard"))
local Net = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Net"))
local RateLimiter = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("RateLimiter"))

type CreatureRecord = Types.CreatureRecord

export type State = "Placed" | "Carried" | "Returning"

export type Placed = {
	record: CreatureRecord,
	owner: Player,
	model: Model,
	stage: Growth.Stage,
	state: State,
}

local CreatureService = {}

-- (player, record) after a creature is added; (player, record, reason) after removal.
CreatureService.Added = Signal.new()
CreatureService.Removed = Signal.new()
-- (player, record, newStage) when a creature hatches or grows up.
CreatureService.StageChanged = Signal.new()
-- (player, entry) whenever a pedestal model is (re)built; RaidService adds steal prompts here.
CreatureService.ModelSpawned = Signal.new()
-- (player, record) when a creature changes owner (a successful steal).
CreatureService.Transferred = Signal.new()

local placed: { [string]: Placed } = {}

local PLACED: State = "Placed"
local CARRIED: State = "Carried"
local RETURNING: State = "Returning"

local function stageOf(record: CreatureRecord): Growth.Stage
	local def = CreatureData.get(record.id)
	assert(def, `Unknown creature {record.id}`)
	return Growth.stage(def.growTimeSec, record.plantedAt, os.time())
end
CreatureService.stageOf = stageOf

function CreatureService.socketCFrame(base: Model, slot: number): CFrame?
	local pedestals = base:FindFirstChild("Pedestals")
	local pedestal = if pedestals then pedestals:FindFirstChild(`Pedestal{slot}`) else nil
	local top = if pedestal then pedestal:FindFirstChild("Top") else nil
	local socket = if top then top:FindFirstChild("Socket") else nil
	if socket and socket:IsA("Attachment") then
		return (socket :: Attachment).WorldCFrame
	end
	return nil
end

local function findRecordIndex(data: Types.PlayerData, uid: string): number?
	for index, record in data.creatures do
		if record.uid == uid then
			return index
		end
	end
	return nil
end

local function removeInternal(uid: string, reason: string): CreatureRecord?
	local entry = placed[uid]
	if not entry then
		return nil
	end
	placed[uid] = nil
	entry.model:Destroy()
	local data = DataService.get(entry.owner)
	if data then
		local index = findRecordIndex(data, uid)
		if index then
			table.remove(data.creatures, index)
		end
	end
	CreatureService.Removed:fire(entry.owner, entry.record, reason)
	return entry.record
end

local function ownerAction(player: Player, uid: string, limitKey: string): Placed?
	if not RateLimiter.allow(player, limitKey) then
		return nil
	end
	local entry = placed[uid]
	if not entry or entry.owner ~= player or entry.state ~= PLACED then
		return nil
	end
	local root = entry.model.PrimaryPart
	if
		not root
		or not Character.isNear(player, root.Position, Config.CreaturePromptDistance + Config.ActionDistanceSlack)
	then
		return nil
	end
	return entry
end

local function onSellTriggered(player: Player, uid: string)
	local entry = ownerAction(player, uid, "SellCreature")
	if not entry then
		return
	end
	local record = removeInternal(uid, "sold")
	if not record then
		return
	end
	local value = Economy.sellValue(record.id, record.mutation)
	DataService.addCoins(player, value)
	local def = CreatureData.get(record.id)
	Net.notify(player, `Sold {if def then def.displayName else "creature"} for {Format.short(value)} coins`, "success")
end

local function addOwnerPrompt(
	root: BasePart,
	owner: Player,
	name: string,
	action: string,
	objectText: string,
	key: Enum.KeyCode,
	hold: number
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = objectText
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = Config.CreaturePromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = key
	prompt:SetAttribute("OwnerUserId", owner.UserId)
	CollectionService:AddTag(prompt, Tags.OwnerOnlyPrompt)
	prompt.Parent = root
	return prompt
end

local function lockText(locked: boolean): string
	return if locked then "Unlock" else "Lock"
end

local function spawnModel(owner: Player, record: CreatureRecord, stage: Growth.Stage, stageChangedAt: number?): Model?
	local base = BaseService.getBase(owner)
	if not base then
		return nil
	end
	local origin = CreatureService.socketCFrame(base, record.slot)
	local folder = base:FindFirstChild("Creatures")
	if not origin or not folder then
		return nil
	end
	local def = CreatureData.get(record.id)
	assert(def, `Unknown creature {record.id}`)
	local model = CreatureModels.build(record.id, { stage = stage, origin = origin, mutation = record.mutation })
	model:SetAttribute("Uid", record.uid)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("Slot", record.slot)
	model:SetAttribute("PlantedAt", record.plantedAt)
	model:SetAttribute("GrowTimeSec", def.growTimeSec)
	model:SetAttribute("Locked", record.locked)
	model:SetAttribute("Mutation", record.mutation)
	model:SetAttribute("StageChangedAt", stageChangedAt or 0)
	local root = model.PrimaryPart
	if root then
		local sell = addOwnerPrompt(
			root,
			owner,
			"SellPrompt",
			`Sell for {Format.short(Economy.sellValue(record.id, record.mutation))}`,
			def.displayName,
			Enum.KeyCode.F,
			Config.SellPromptHoldSec
		)
		sell.Triggered:Connect(function(player: Player)
			onSellTriggered(player, record.uid)
		end)
		if stage == "Adult" then
			local lock =
				addOwnerPrompt(root, owner, "LockPrompt", lockText(record.locked), "Lock slot", Enum.KeyCode.R, 0.3)
			lock.Triggered:Connect(function(player: Player)
				local entry = ownerAction(player, record.uid, "SetLocked")
				if entry then
					CreatureService.setLocked(player, record.uid, not entry.record.locked)
				end
			end)
		end
	end
	CollectionService:AddTag(model, Tags.Creature)
	model.Parent = folder
	return model
end

-- Puts an existing record into the world (used for new creatures and loaded saves).
local function place(owner: Player, record: CreatureRecord, stageChangedAt: number?): boolean
	local stage: Growth.Stage = stageOf(record)
	local model = spawnModel(owner, record, stage, stageChangedAt)
	if not model then
		return false
	end
	local entry: Placed = { record = record, owner = owner, model = model, stage = stage, state = PLACED }
	placed[record.uid] = entry
	CreatureService.ModelSpawned:fire(owner, entry)
	return true
end

-- The lowest unlocked pedestal slot with nothing on it, or nil when full.
function CreatureService.freeSlot(player: Player): number?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	local used: { [number]: boolean } = {}
	for _, record in data.creatures do
		used[record.slot] = true
	end
	for slot = 1, data.pedestals do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

-- Creates a brand new creature (an egg planted now, unless `plantedAt` says otherwise)
-- on the owner's first free pedestal.
function CreatureService.add(
	player: Player,
	creatureId: string,
	plantedAt: number?,
	mutation: Types.Mutation?
): CreatureRecord?
	local data = DataService.get(player)
	local slot = CreatureService.freeSlot(player)
	if not data or not slot or not CreatureData.get(creatureId) then
		return nil
	end
	local record: CreatureRecord = {
		uid = HttpService:GenerateGUID(false),
		id = creatureId,
		plantedAt = plantedAt or os.time(),
		mutation = mutation,
		locked = false,
		slot = slot,
	}
	table.insert(data.creatures, record)
	if not place(player, record, Workspace:GetServerTimeNow()) then
		local index = table.find(data.creatures, record)
		if index then
			table.remove(data.creatures, index)
		end
		return nil
	end
	data.discoveries[creatureId] = true
	CreatureService.Added:fire(player, record)
	return record
end

function CreatureService.remove(uid: string, reason: string): CreatureRecord?
	return removeInternal(uid, reason)
end

function CreatureService.get(uid: string): Placed?
	return placed[uid]
end

-- Every creature on the server. Read-only for callers.
function CreatureService.all(): { [string]: Placed }
	return placed
end

-- Rebuilds a placed creature's model (for example after a mutation) in its current stage.
function CreatureService.rebuild(uid: string, celebrate: boolean?)
	local entry = placed[uid]
	if not entry or entry.state ~= PLACED then
		return
	end
	local model =
		spawnModel(entry.owner, entry.record, entry.stage, if celebrate then Workspace:GetServerTimeNow() else nil)
	if model then
		entry.model:Destroy()
		entry.model = model
		CreatureService.ModelSpawned:fire(entry.owner, entry)
	end
end

-- Rebuilds a creature's model if its growth stage changed. Returns the new stage if it did.
function CreatureService.refreshStage(uid: string): Growth.Stage?
	local entry = placed[uid]
	if not entry or entry.state ~= PLACED then
		return nil
	end
	local stage: Growth.Stage = stageOf(entry.record)
	if stage == entry.stage then
		return nil
	end
	entry.stage = stage
	CreatureService.rebuild(uid, true)
	CreatureService.StageChanged:fire(entry.owner, entry.record, stage)
	return stage
end

-- Locks one creature so it can't be stolen. Each player may lock only one at a time.
function CreatureService.setLocked(player: Player, uid: string, locked: boolean)
	local data = DataService.get(player)
	local target = placed[uid]
	if not data or not target or target.owner ~= player then
		return
	end
	for _, record in data.creatures do
		local shouldLock = locked and record.uid == uid
		if record.locked ~= shouldLock then
			record.locked = shouldLock
			local entry = placed[record.uid]
			if entry then
				entry.model:SetAttribute("Locked", shouldLock)
				local root = entry.model.PrimaryPart
				local prompt = if root then root:FindFirstChild("LockPrompt") else nil
				if prompt and prompt:IsA("ProximityPrompt") then
					(prompt :: ProximityPrompt).ActionText = lockText(shouldLock)
				end
			end
		end
	end
	local def = CreatureData.get(target.record.id)
	local name = if def then def.displayName else "creature"
	Net.notify(player, if locked then `🔒 {name} is locked and can't be stolen` else `{name} is unlocked`, "info")
end

-- Coins per second the player's adult creatures produce right now (only ones at home).
function CreatureService.incomePerSec(player: Player): number
	local total = 0
	for _, entry in placed do
		if entry.owner == player and entry.stage == "Adult" and entry.state == PLACED then
			total += Economy.incomePerSec(entry.record.id, entry.record.mutation)
		end
	end
	return total
end

-- Total worth of everything the player owns (for raid brackets and protection).
function CreatureService.baseValue(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	local total = 0
	for _, record in data.creatures do
		total += Economy.creatureValue(record.id, record.mutation)
	end
	return total
end

-- Hands a creature's model to the caller to be carried. Returns the model, or nil.
function CreatureService.detach(uid: string): Model?
	local entry = placed[uid]
	if not entry or entry.state ~= PLACED then
		return nil
	end
	entry.state = CARRIED
	for _, prompt in entry.model:GetDescendants() do
		if prompt:IsA("ProximityPrompt") then
			prompt:Destroy()
		end
	end
	return entry.model
end

function CreatureService.setReturning(uid: string)
	local entry = placed[uid]
	if entry and entry.state == CARRIED then
		entry.state = RETURNING
	end
end

-- Puts a carried or returning creature straight back on its pedestal.
function CreatureService.returnHome(uid: string)
	local entry = placed[uid]
	if not entry or entry.state == PLACED then
		return
	end
	local model = spawnModel(entry.owner, entry.record, entry.stage, nil)
	entry.model:Destroy()
	entry.state = PLACED
	if model then
		entry.model = model
		CreatureService.ModelSpawned:fire(entry.owner, entry)
	else
		placed[uid] = nil -- the owner's base is gone; their saved data still has the record
	end
end

-- Moves a creature (carried by `newOwner`) into `newOwner`'s base and data.
function CreatureService.transfer(uid: string, newOwner: Player): CreatureRecord?
	local entry = placed[uid]
	local newData = DataService.get(newOwner)
	local slot = CreatureService.freeSlot(newOwner)
	if not entry or not newData or not slot then
		return nil
	end
	local oldData = DataService.get(entry.owner)
	if oldData then
		local index = findRecordIndex(oldData, uid)
		if index then
			table.remove(oldData.creatures, index)
		end
	end
	local previousOwner = entry.owner
	placed[uid] = nil
	entry.model:Destroy()
	local record: CreatureRecord = {
		uid = entry.record.uid,
		id = entry.record.id,
		plantedAt = entry.record.plantedAt,
		mutation = entry.record.mutation,
		locked = false,
		slot = slot,
	}
	table.insert(newData.creatures, record)
	newData.discoveries[record.id] = true
	CreatureService.Removed:fire(previousOwner, entry.record, "stolen")
	place(newOwner, record, Workspace:GetServerTimeNow())
	CreatureService.Transferred:fire(newOwner, record)
	return record
end

local function clearPlayer(player: Player)
	for uid, entry in placed do
		if entry.owner == player then
			placed[uid] = nil
			entry.model:Destroy()
		end
	end
end

-- Places everything a player already owns (saved creatures) once they have a base.
local function onBaseAssigned(player: Player, _base: Model)
	local data = DataService.get(player)
	if not data then
		return
	end
	clearPlayer(player)
	local used: { [number]: boolean } = {}
	for _, record in data.creatures do
		-- Repair bad or duplicate slots from old saves.
		if record.slot < 1 or record.slot > data.pedestals or used[record.slot] then
			record.slot = 0
		end
		if record.slot ~= 0 then
			used[record.slot] = true
		end
	end
	for _, record in data.creatures do
		if record.slot == 0 then
			for slot = 1, data.pedestals do
				if not used[slot] then
					record.slot = slot
					used[slot] = true
					break
				end
			end
		end
		if record.slot ~= 0 and CreatureData.get(record.id) then
			place(player, record, nil)
		end
	end
end

function CreatureService.init() end

function CreatureService.start()
	BaseService.Assigned:connect(onBaseAssigned)
	BaseService.Released:connect(function(player: Player)
		clearPlayer(player)
	end)
	Players.PlayerRemoving:Connect(clearPlayer)
	Net.onEvent("SetLocked", { Guard.uid(), Guard.boolean() }, function(player: Player, uid: string, locked: boolean)
		local entry = placed[uid]
		if entry and entry.owner == player then
			CreatureService.setLocked(player, uid, locked)
		end
	end)
	-- Players who got a base before this service started (onBaseAssigned is idempotent).
	for _, player in Players:GetPlayers() do
		local base = BaseService.getBase(player)
		if base then
			task.spawn(onBaseAssigned, player, base)
		end
	end
end

return CreatureService
