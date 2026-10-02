--!strict
--[[
	CreatureService
	Owns every placed creature: the CreatureRecord in the owner's data and the Model
	standing on its pedestal. Other systems go through this service to add, remove
	or re-stage creatures, so data and world never drift apart.

	Models are tagged "Creature" and carry attributes the client reads for labels
	and animation: Uid, OwnerUserId, Slot, PlantedAt, GrowTimeSec, Stage,
	StageChangedAt, Mutation, Locked. Each model has an owner-only "Sell" prompt.
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
local Net = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Net"))
local RateLimiter = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("RateLimiter"))

type CreatureRecord = Types.CreatureRecord

export type Placed = {
	record: CreatureRecord,
	owner: Player,
	model: Model,
	stage: Growth.Stage,
}

local CreatureService = {}

-- (player, record) after a creature is placed; (player, record, reason) after removal.
CreatureService.Added = Signal.new()
CreatureService.Removed = Signal.new()
-- (player, record, newStage) when a creature hatches or grows up.
CreatureService.StageChanged = Signal.new()

local placed: { [string]: Placed } = {}

local function stageOf(record: CreatureRecord): Growth.Stage
	local def = CreatureData.get(record.id)
	assert(def, `Unknown creature {record.id}`)
	return Growth.stage(def.growTimeSec, record.plantedAt, os.time())
end
CreatureService.stageOf = stageOf

local function socketCFrame(base: Model, slot: number): CFrame?
	local pedestals = base:FindFirstChild("Pedestals")
	local pedestal = if pedestals then pedestals:FindFirstChild(`Pedestal{slot}`) else nil
	local top = if pedestal then pedestal:FindFirstChild("Top") else nil
	local socket = if top then top:FindFirstChild("Socket") else nil
	if socket and socket:IsA("Attachment") then
		return (socket :: Attachment).WorldCFrame
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
		for index, record in data.creatures do
			if record.uid == uid then
				table.remove(data.creatures, index)
				break
			end
		end
	end
	CreatureService.Removed:fire(entry.owner, entry.record, reason)
	return entry.record
end

local function onSellTriggered(player: Player, uid: string)
	if not RateLimiter.allow(player, "SellCreature") then
		return
	end
	local entry = placed[uid]
	if not entry or entry.owner ~= player then
		return
	end
	local root = entry.model.PrimaryPart
	if
		not root
		or not Character.isNear(player, root.Position, Config.CreaturePromptDistance + Config.ActionDistanceSlack)
	then
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

local function addSellPrompt(model: Model, owner: Player, record: CreatureRecord)
	local root = model.PrimaryPart
	local def = CreatureData.get(record.id)
	if not root or not def then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SellPrompt"
	prompt.ActionText = `Sell for {Format.short(Economy.sellValue(record.id, record.mutation))}`
	prompt.ObjectText = def.displayName
	prompt.HoldDuration = Config.SellPromptHoldSec
	prompt.MaxActivationDistance = Config.CreaturePromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt:SetAttribute("OwnerUserId", owner.UserId)
	CollectionService:AddTag(prompt, Tags.OwnerOnlyPrompt)
	prompt.Triggered:Connect(function(player: Player)
		onSellTriggered(player, record.uid)
	end)
	prompt.Parent = root
end

local function spawnModel(owner: Player, record: CreatureRecord, stage: Growth.Stage, stageChangedAt: number?): Model?
	local base = BaseService.getBase(owner)
	if not base then
		return nil
	end
	local origin = socketCFrame(base, record.slot)
	local folder = base:FindFirstChild("Creatures")
	if not origin or not folder then
		return nil
	end
	local def = CreatureData.get(record.id)
	assert(def, `Unknown creature {record.id}`)
	local model = CreatureModels.build(record.id, { stage = stage, origin = origin })
	model:SetAttribute("Uid", record.uid)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("Slot", record.slot)
	model:SetAttribute("PlantedAt", record.plantedAt)
	model:SetAttribute("GrowTimeSec", def.growTimeSec)
	model:SetAttribute("Locked", record.locked)
	model:SetAttribute("Mutation", record.mutation)
	model:SetAttribute("StageChangedAt", stageChangedAt or 0)
	addSellPrompt(model, owner, record)
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
	placed[record.uid] = { record = record, owner = owner, model = model, stage = stage }
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

-- Creates a brand new creature (an egg planted now) on the owner's first free pedestal.
function CreatureService.add(player: Player, creatureId: string): CreatureRecord?
	local data = DataService.get(player)
	local slot = CreatureService.freeSlot(player)
	if not data or not slot or not CreatureData.get(creatureId) then
		return nil
	end
	local record: CreatureRecord = {
		uid = HttpService:GenerateGUID(false),
		id = creatureId,
		plantedAt = os.time(),
		mutation = nil,
		locked = false,
		slot = slot,
	}
	table.insert(data.creatures, record)
	if not place(player, record, Workspace:GetServerTimeNow()) then
		table.remove(data.creatures, table.find(data.creatures, record))
		return nil
	end
	CreatureService.Added:fire(player, record)
	return record
end

function CreatureService.remove(uid: string, reason: string): CreatureRecord?
	return removeInternal(uid, reason)
end

function CreatureService.get(uid: string): Placed?
	return placed[uid]
end

-- Every placed creature on the server. Read-only for callers.
function CreatureService.all(): { [string]: Placed }
	return placed
end

-- Rebuilds a creature's model if its growth stage changed. Returns the new stage if it did.
function CreatureService.refreshStage(uid: string): Growth.Stage?
	local entry = placed[uid]
	if not entry then
		return nil
	end
	local stage: Growth.Stage = stageOf(entry.record)
	if stage == entry.stage then
		return nil
	end
	local model = spawnModel(entry.owner, entry.record, stage, Workspace:GetServerTimeNow())
	if not model then
		return nil
	end
	entry.model:Destroy()
	entry.model = model
	entry.stage = stage
	CreatureService.StageChanged:fire(entry.owner, entry.record, stage)
	return stage
end

-- Coins per second the player's adult creatures produce right now.
function CreatureService.incomePerSec(player: Player): number
	local total = 0
	for _, entry in placed do
		if entry.owner == player and entry.stage == "Adult" then
			total += Economy.incomePerSec(entry.record.id, entry.record.mutation)
		end
	end
	return total
end

-- Total worth of everything the player owns (for raid brackets later).
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
	-- Players who got a base before this service started (onBaseAssigned is idempotent).
	for _, player in Players:GetPlayers() do
		local base = BaseService.getBase(player)
		if base then
			task.spawn(onBaseAssigned, player, base)
		end
	end
end

return CreatureService
