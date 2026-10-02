--!strict
--[[
	RaidService
	Night raids. Owns everything between "Steal" and "it's mine now":

	  * Steal prompts on adult creatures, validated against every fairness rule
	    (RaidRules + lock slot + steal cooldown + free pedestal + being inside the base).
	  * Carrying: the creature is welded above the raider's head and they slow to
	    Config.CarryWalkSpeed. It only becomes theirs when they bring it into their
	    own base and a free pedestal exists.
	  * Dropping (bonked or slipped): the creature walks back home on its own.
	  * Sunrise, leaving or dying returns anything still being carried.
	  * Revenge: after a theft the victim may raid the thief for
	    Config.RevengeWindowSec, even by day and ignoring the value bracket.
	  * Base zones: shields are only solid on clients, so the server checks every
	    Config.ZoneCheckSec who is standing in which base and teleports out anyone
	    who isn't allowed there. This is what stops noclip exploits.
	  * Publishes BaseValue / RaidProtected attributes for client UI.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local RaidRules = require(Shared:WaitForChild("RaidRules"))
local Tags = require(Shared:WaitForChild("Tags"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CreatureService = require(script.Parent:WaitForChild("CreatureService"))
local CycleService = require(script.Parent:WaitForChild("CycleService"))
local Character = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Character"))
local Net = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Net"))
local RateLimiter = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("RateLimiter"))
local Speed = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Speed"))
local Ticker = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ticker"))

type Carry = {
	uid: string,
	victim: Player,
	diedConnection: RBXScriptConnection?,
}

type Walker = {
	root: BasePart,
	attachment: Attachment,
	waypoints: { Vector3 },
	index: number,
	velocity: LinearVelocity,
	align: AlignOrientation,
	startedAt: number,
}

local RaidService = {}

-- (thief, victim, record) after a successful steal.
RaidService.Stole = Signal.new()
-- (raider, victim) when a raider grabs a creature.
RaidService.Grabbed = Signal.new()
-- (raider) the first time per session a player walks into someone else's base at night.
RaidService.Raided = Signal.new()

local carrying: { [Player]: Carry } = {}
local walkers: { [string]: Walker } = {}
local revenge: { [Player]: { [Player]: number } } = {} -- revenge[victim][thief] = expiresAt
local lastSteal: { [Player]: number } = {}
local lastNotice: { [Player]: number } = {}
local raidedThisSession: { [Player]: boolean } = {}
local carriedFolder: Folder

local WALK_TIMEOUT_SEC = 60

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function noticeOnce(player: Player, message: string)
	local t = os.clock()
	if (lastNotice[player] or 0) + Config.ProtectedNoticeCooldownSec < t then
		lastNotice[player] = t
		Net.notify(player, message, "warning")
	end
end

local function creatureName(id: string): string
	local def = CreatureData.get(id)
	return if def then def.displayName else "creature"
end

function RaidService.hasRevenge(attacker: Player, owner: Player): boolean
	local targets = revenge[attacker]
	local expiresAt = if targets then targets[owner] else nil
	return expiresAt ~= nil and expiresAt > now()
end

function RaidService.isProtected(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return true
	end
	return RaidRules.isProtected(DataService.playtime(player), CreatureService.baseValue(player), data.hasStolen)
end

-- Can `attacker` raid `owner` right now? Returns the reason when not.
function RaidService.check(attacker: Player, owner: Player): (boolean, string?)
	return RaidRules.canRaid({
		isNight = CycleService.isNight(),
		attackerValue = CreatureService.baseValue(attacker),
		victimValue = CreatureService.baseValue(owner),
		victimProtected = RaidService.isProtected(owner),
		hasRevenge = RaidService.hasRevenge(attacker, owner),
	})
end

function RaidService.isCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

local function mayEnter(player: Player, base: Model): (boolean, string?)
	local ownerId = base:GetAttribute("OwnerUserId")
	if typeof(ownerId) ~= "number" or ownerId == 0 or ownerId == player.UserId then
		return true, nil
	end
	local owner = Players:GetPlayerByUserId(ownerId)
	if not owner then
		return true, nil
	end
	return RaidService.check(player, owner)
end

local function clearCarry(raider: Player): Carry?
	local carry = carrying[raider]
	if not carry then
		return nil
	end
	carrying[raider] = nil
	if carry.diedConnection then
		carry.diedConnection:Disconnect()
	end
	Speed.set(raider, "Carry", nil)
	raider:SetAttribute("Carrying", nil)
	return carry
end

-- Sends whatever the raider is carrying straight back to its pedestal.
local function returnCarried(raider: Player)
	local carry = clearCarry(raider)
	if carry then
		CreatureService.returnHome(carry.uid)
	end
end

local function stopWalker(uid: string)
	local walker = walkers[uid]
	if walker then
		walkers[uid] = nil
		walker.velocity:Destroy()
		walker.align:Destroy()
		walker.attachment:Destroy()
	end
end

local function pivotPosition(root: BasePart): Vector3
	return (root.CFrame * root.PivotOffset).Position
end

local function aimWalker(walker: Walker)
	local target = walker.waypoints[walker.index]
	local here = pivotPosition(walker.root)
	local flat = Vector3.new(target.X - here.X, 0, target.Z - here.Z)
	if flat.Magnitude < 1e-3 then
		walker.velocity.VectorVelocity = Vector3.zero
		return
	end
	local dir = flat.Unit
	walker.velocity.VectorVelocity = dir * Config.DroppedCreatureWalkSpeed
	walker.align.CFrame = CFrame.lookAt(Vector3.zero, dir)
end

-- A dropped creature walks back to its own pedestal through the base entrance.
local function startWalking(uid: string, from: Vector3)
	local entry = CreatureService.get(uid)
	local base = if entry then BaseService.getBase(entry.owner) else nil
	local root = if entry then entry.model.PrimaryPart else nil
	if not entry or not base or not root then
		CreatureService.returnHome(uid)
		return
	end
	local home = CreatureService.socketCFrame(base, entry.record.slot)
	if not home then
		CreatureService.returnHome(uid)
		return
	end
	local floorY = home.Position.Y - 1.35 -- socket sits on the pedestal top; walk on the floor
	local start = Vector3.new(from.X, floorY, from.Z)
	local waypoints: { Vector3 } = {}
	if not MapService.isInBase(base, start) then
		local outside = (MapService.outsideEntrance(base)).Position
		table.insert(waypoints, Vector3.new(outside.X, floorY, outside.Z))
		local inside = MapService.insideEntrance(base)
		table.insert(waypoints, Vector3.new(inside.X, floorY, inside.Z))
	end
	table.insert(waypoints, Vector3.new(home.Position.X, floorY, home.Position.Z))

	root.Anchored = true
	root.CFrame = CFrame.new(start) * root.PivotOffset:Inverse()
	local attachment = Instance.new("Attachment")
	attachment.Name = "Walk"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.ForceLimitsEnabled = false
	velocity.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.Parent = root
	entry.model.Parent = carriedFolder
	root.Anchored = false
	root:SetNetworkOwner(nil)
	local walker: Walker = {
		root = root,
		attachment = attachment,
		waypoints = waypoints,
		index = 1,
		velocity = velocity,
		align = align,
		startedAt = os.clock(),
	}
	walkers[uid] = walker
	aimWalker(walker)
end

-- Drops whatever the raider is carrying; it walks home. Used by the bat and traps.
function RaidService.drop(raider: Player)
	local carry = clearCarry(raider)
	if not carry then
		return
	end
	local entry = CreatureService.get(carry.uid)
	local root = if entry then entry.model.PrimaryPart else nil
	if not entry or not root then
		return
	end
	for _, child in root:GetChildren() do
		if child:IsA("WeldConstraint") and child.Name == "CarryWeld" then
			child:Destroy()
		end
	end
	CreatureService.setReturning(carry.uid)
	local raiderRoot = Character.root(raider)
	startWalking(carry.uid, if raiderRoot then raiderRoot.Position else pivotPosition(root))
	Net.notify(carry.victim, `Your {creatureName(entry.record.id)} escaped and is walking home!`, "success")
end

local function grab(raider: Player, uid: string, victim: Player)
	local raiderRoot = Character.root(raider)
	local model = CreatureService.detach(uid)
	local root = if model then model.PrimaryPart else nil
	if not raiderRoot or not model or not root then
		if model then
			CreatureService.returnHome(uid)
		end
		return
	end
	root.Anchored = false
	root.Massless = true
	root.CanCollide = false
	root.CFrame = raiderRoot.CFrame * CFrame.new(0, Config.CarryHeight + root.Size.Y / 2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = raiderRoot
	weld.Part1 = root
	weld.Parent = root
	model.Parent = carriedFolder

	local carry: Carry = { uid = uid, victim = victim, diedConnection = nil }
	local character = raider.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		carry.diedConnection = humanoid.Died:Connect(function()
			returnCarried(raider)
		end)
	end
	carrying[raider] = carry
	Speed.set(raider, "Carry", Config.CarryWalkSpeed)
	raider:SetAttribute("Carrying", uid)
	local entry = CreatureService.get(uid)
	local name = if entry then creatureName(entry.record.id) else "creature"
	Net.notify(raider, `Got the {name}! Run it back to a free pedestal in your base!`, "success")
	Net.notify(victim, `⚠️ {raider.DisplayName} grabbed your {name}! Bonk them before they get away!`, "warning")
	RaidService.Grabbed:fire(raider, victim)
end

local function onSteal(raider: Player, uid: string)
	if not RateLimiter.allow(raider, "Steal") then
		return
	end
	local entry = CreatureService.get(uid)
	if not entry or entry.state ~= "Placed" or entry.stage ~= "Adult" then
		return
	end
	local victim = entry.owner
	if victim == raider then
		return
	end
	local root = entry.model.PrimaryPart
	local raiderRoot = Character.root(raider)
	local victimBase = BaseService.getBase(victim)
	if not root or not raiderRoot or not victimBase then
		return
	end
	if not Character.isNear(raider, root.Position, Config.StealPromptDistance + Config.ActionDistanceSlack) then
		return
	end
	if not MapService.isInBase(victimBase, raiderRoot.Position) then
		return
	end
	if carrying[raider] then
		Net.notify(raider, "You're already carrying something!", "warning")
		return
	end
	if entry.record.locked then
		Net.notify(raider, "That creature is locked 🔒 and can't be stolen", "warning")
		return
	end
	if not BaseService.getBase(raider) then
		return
	end
	if not CreatureService.freeSlot(raider) then
		Net.notify(raider, "You need a free pedestal at home to steal!", "warning")
		return
	end
	local cooldownLeft = (lastSteal[raider] or -math.huge) + Config.StealCooldownSec - now()
	if cooldownLeft > 0 then
		Net.notify(raider, `Catch your breath! You can steal again in {math.ceil(cooldownLeft)}s`, "warning")
		return
	end
	local allowed, reason = RaidService.check(raider, victim)
	if not allowed then
		Net.notify(raider, reason or "You can't raid this base right now", "warning")
		return
	end
	grab(raider, uid, victim)
end

local function deliver(raider: Player, carry: Carry)
	clearCarry(raider)
	local record = CreatureService.transfer(carry.uid, raider)
	if not record then
		CreatureService.returnHome(carry.uid)
		return
	end
	local victim = carry.victim
	lastSteal[raider] = now()
	local data = DataService.get(raider)
	if data then
		data.hasStolen = true
	end
	local expiresAt = now() + Config.RevengeWindowSec
	local targets = revenge[victim]
	if not targets then
		targets = {}
		revenge[victim] = targets
	end
	targets[raider] = expiresAt
	if victim.Parent == Players then
		Net.fire(victim, "RevengeStarted", raider.UserId, expiresAt)
	end
	local def = CreatureData.get(record.id)
	Net.fireAll(
		"TheftAnnounced",
		raider.DisplayName,
		victim.DisplayName,
		if def then def.rarity else "",
		if def then def.displayName else "creature"
	)
	Net.notify(raider, "It's yours now! Watch out for revenge...", "success")
	RaidService.Stole:fire(raider, victim, record)
end

local function addStealPrompt(owner: Player, entry: CreatureService.Placed)
	if entry.stage ~= "Adult" then
		return
	end
	local root = entry.model.PrimaryPart
	if not root then
		return
	end
	local uid = entry.record.uid
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Steal"
	prompt.ObjectText = creatureName(entry.record.id)
	prompt.HoldDuration = Config.StealPromptHoldSec
	prompt.MaxActivationDistance = Config.StealPromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	prompt:SetAttribute("OwnerUserId", owner.UserId)
	CollectionService:AddTag(prompt, Tags.StealPrompt)
	prompt.Triggered:Connect(function(player: Player)
		onSteal(player, uid)
	end)
	prompt.Parent = root
end

local function stepCarriesAndWalkers()
	for raider, carry in table.clone(carrying) do
		local entry = CreatureService.get(carry.uid)
		if not entry or entry.state ~= "Carried" then
			clearCarry(raider)
			continue
		end
		local raiderRoot = Character.root(raider)
		if not raiderRoot or raider.Parent ~= Players then
			returnCarried(raider)
			continue
		end
		local home = BaseService.getBase(raider)
		if home and MapService.isInBase(home, raiderRoot.Position) then
			if CreatureService.freeSlot(raider) then
				deliver(raider, carry)
			else
				noticeOnce(raider, "No free pedestal! Free one up to keep it.")
			end
		end
	end
	for uid, walker in table.clone(walkers) do
		local entry = CreatureService.get(uid)
		if not entry or entry.state ~= "Returning" or not walker.root.Parent then
			stopWalker(uid)
			continue
		end
		if os.clock() - walker.startedAt > WALK_TIMEOUT_SEC then
			stopWalker(uid)
			CreatureService.returnHome(uid)
			continue
		end
		local here = pivotPosition(walker.root)
		local target = walker.waypoints[walker.index]
		if Vector3.new(target.X - here.X, 0, target.Z - here.Z).Magnitude < 0.8 then
			walker.index += 1
			if walker.index > #walker.waypoints then
				stopWalker(uid)
				CreatureService.returnHome(uid)
				continue
			end
		end
		aimWalker(walker)
	end
end

local function enforceZones()
	for _, player in Players:GetPlayers() do
		local root = Character.root(player)
		if not root then
			continue
		end
		local base = MapService.baseAt(root.Position)
		if not base then
			continue
		end
		local allowed, reason = mayEnter(player, base)
		if not allowed then
			returnCarried(player)
			local character = player.Character
			if character then
				character:PivotTo(MapService.outsideEntrance(base))
			end
			noticeOnce(player, `🛡️ Shield's up! {reason or "You can't enter this base right now"}`)
		elseif
			CycleService.isNight()
			and base:GetAttribute("OwnerUserId") ~= player.UserId
			and base:GetAttribute("OwnerUserId") ~= 0
			and not raidedThisSession[player]
		then
			raidedThisSession[player] = true
			RaidService.Raided:fire(player)
		end
	end
end

local function publishRaidInfo()
	for _, player in Players:GetPlayers() do
		if DataService.get(player) then
			local value = CreatureService.baseValue(player)
			if player:GetAttribute("BaseValue") ~= value then
				player:SetAttribute("BaseValue", value)
			end
			local protected = RaidService.isProtected(player)
			if player:GetAttribute("RaidProtected") ~= protected then
				player:SetAttribute("RaidProtected", protected)
			end
		end
	end
end

local function setShields(open: boolean)
	for _, base in MapService.getBases() do
		base:SetAttribute("ShieldOpen", open)
		local shield = base:FindFirstChild("Shield")
		if shield and shield:IsA("BasePart") then
			(shield :: BasePart).Transparency = if open then Config.ShieldOpenTransparency else 0.15
		end
	end
end

local function onPhaseChanged(phase: string)
	setShields(phase == "Night")
	if phase == "Day" then
		for raider in table.clone(carrying) do
			returnCarried(raider)
		end
		for uid in table.clone(walkers) do
			stopWalker(uid)
			CreatureService.returnHome(uid)
		end
		enforceZones()
		Net.fireAll("Notify", "☀️ Sunrise! Shields are back up.", "info")
	else
		Net.fireAll("Notify", "🌙 Night falls... shields are down. Raid or defend!", "warning")
	end
end

function RaidService.init()
	carriedFolder = Instance.new("Folder")
	carriedFolder.Name = "LooseCreatures"
	carriedFolder.Parent = Workspace
	for _, base in MapService.getBases() do
		-- Shields are only solid on each client (see ShieldController); the server enforces zones.
		local shield = base:FindFirstChild("Shield")
		if shield and shield:IsA("BasePart") then
			(shield :: BasePart).CanCollide = false
		end
	end
	setShields(CycleService.isNight())
end

function RaidService.start()
	CreatureService.ModelSpawned:connect(addStealPrompt)
	for _, entry in CreatureService.all() do
		addStealPrompt(entry.owner, entry)
	end
	CycleService.PhaseChanged:connect(onPhaseChanged)
	Players.PlayerRemoving:Connect(function(player: Player)
		returnCarried(player)
		revenge[player] = nil
		for _, targets in revenge do
			targets[player] = nil
		end
		lastSteal[player] = nil
		lastNotice[player] = nil
		raidedThisSession[player] = nil
	end)
	DataService.Releasing:connect(function(player: Player)
		returnCarried(player)
	end)
	Ticker.every("RaidCarry", 0.1, stepCarriesAndWalkers)
	Ticker.every("RaidZones", Config.ZoneCheckSec, enforceZones)
	Ticker.every("RaidInfo", 1, publishRaidInfo)
end

return RaidService
