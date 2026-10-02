--!strict
--[[
	TrapService
	Traps players buy for their own base (up to Config.MaxTraps), placed on the
	base's trap spots along the entrance. A trap only fires on players who are not
	the owner, then re-arms after Config.TrapRearmSec:

	  BananaPeel   the raider slips (short stun) and drops what they carry
	  StickyFloor  slows the raider to Config.StickyWalkSpeed for Config.StickySlowSec
	  HonkEgg      honks, warns the owner and highlights the raider for them

	Buying goes through the "BuyTrap" remote: the type is validated against
	Config.TrapPrices and the price always comes from Config.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TrapModels = require(Shared:WaitForChild("Models"):WaitForChild("TrapModels"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Types = require(Shared:WaitForChild("Types"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local RaidService = require(script.Parent:WaitForChild("RaidService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local Character = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Character"))
local Guard = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Guard"))
local Net = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Net"))
local Speed = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Speed"))

local TrapService = {}

TrapService.Types = table.freeze({ "BananaPeel", "StickyFloor", "HonkEgg" })
local DISPLAY_NAMES: { [string]: string } = {
	BananaPeel = "Banana Peel",
	StickyFloor = "Sticky Floor",
	HonkEgg = "Honk Egg",
}

local stickyToken: { [Player]: number } = {}

local function trapFolder(base: Model): Folder
	local folder = base:FindFirstChild("Traps")
	if folder and folder:IsA("Folder") then
		return folder :: Folder
	end
	local created = Instance.new("Folder")
	created.Name = "Traps"
	created.Parent = base
	return created
end

local function spotCFrame(base: Model, spot: number): CFrame?
	local spots = base:FindFirstChild("TrapSpots")
	local marker = if spots then spots:FindFirstChild(`TrapSpot{spot}`) else nil
	if marker and marker:IsA("BasePart") then
		return (marker :: BasePart).CFrame
	end
	return nil
end

local function setArmed(model: Model, armed: boolean)
	model:SetAttribute("Armed", armed)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "Root" and descendant.Name ~= "Trigger" then
			local part = descendant :: BasePart
			local stored = part:GetAttribute("BaseTransparency")
			local original = if typeof(stored) == "number" then stored else part.Transparency
			part:SetAttribute("BaseTransparency", original)
			part.Transparency = if armed then original else math.max(original, 0.65)
		end
	end
end

local function spring(model: Model, owner: Player, victim: Player, trapType: string)
	if trapType == "BananaPeel" then
		local root = Character.root(victim)
		local slide = if root then root.CFrame.LookVector * Config.BananaSlipSpeed else Vector3.zero
		RaidService.drop(victim)
		CombatService.stun(victim, slide + Vector3.new(0, 10, 0), Config.BananaStunSec)
		Net.notify(victim, "🍌 Whoops! You slipped on a banana peel!", "warning")
	elseif trapType == "StickyFloor" then
		local token = (stickyToken[victim] or 0) + 1
		stickyToken[victim] = token
		Speed.set(victim, "Sticky", Config.StickyWalkSpeed)
		task.delay(Config.StickySlowSec, function()
			if stickyToken[victim] == token then
				Speed.set(victim, "Sticky", nil)
			end
		end)
		Net.notify(victim, "🩷 Ew, sticky! You're stuck in goo!", "warning")
	elseif trapType == "HonkEgg" then
		Net.fire(owner, "HonkAlert", victim.UserId)
		Net.notify(owner, `🦢 HONK! {victim.DisplayName} is sneaking into your base!`, "warning")
		Net.notify(victim, "🦢 HONK!! The owner knows you're here!", "warning")
	end
	local root = model.PrimaryPart
	if root then
		Net.fireAll("TrapSprung", trapType, root.Position)
	end
end

local function spawnTrap(owner: Player, base: Model, record: Types.TrapRecord): Model?
	local cf = spotCFrame(base, record.spot)
	if not cf or not TrapModels.has(record.trapType) then
		return nil
	end
	local model = TrapModels.build(record.trapType, cf)
	model:SetAttribute("Spot", record.spot)
	local size = Config.TrapTriggerSize
	local trigger = Instance.new("Part")
	trigger.Name = "Trigger"
	trigger.Size = Vector3.new(size, 4, size)
	trigger.CFrame = cf * CFrame.new(0, 2, 0)
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.CanQuery = false
	trigger.CanTouch = true
	trigger.Transparency = 1
	trigger.Parent = model
	setArmed(model, true)
	trigger.Touched:Connect(function(hit: BasePart)
		if model:GetAttribute("Armed") ~= true then
			return
		end
		local character = hit.Parent
		local victim = if character and character:IsA("Model")
			then Players:GetPlayerFromCharacter(character :: Model)
			else nil
		if not victim or victim == owner or BaseService.getBase(owner) ~= base then
			return
		end
		setArmed(model, false)
		spring(model, owner, victim, record.trapType)
		task.delay(Config.TrapRearmSec, function()
			if model.Parent then
				setArmed(model, true)
			end
		end)
	end)
	model.Parent = trapFolder(base)
	return model
end

local function spawnAll(player: Player, base: Model)
	trapFolder(base):ClearAllChildren()
	local data = DataService.get(player)
	if not data then
		return
	end
	for _, record in data.traps do
		spawnTrap(player, base, record)
	end
end

local function freeSpot(data: Types.PlayerData): number?
	local used: { [number]: boolean } = {}
	for _, trap in data.traps do
		used[trap.spot] = true
	end
	for spot = 1, Config.MaxTraps do
		if not used[spot] then
			return spot
		end
	end
	return nil
end

-- Buys a trap of `trapType` for the player's base. Returns true on success.
function TrapService.buy(player: Player, trapType: string): boolean
	local data = DataService.get(player)
	local base = BaseService.getBase(player)
	local price = (Config.TrapPrices :: { [string]: number })[trapType]
	if not data or not base or not price then
		return false
	end
	local spot = freeSpot(data)
	if not spot then
		Net.notify(player, `Your base already has the max of {Config.MaxTraps} traps`, "warning")
		return false
	end
	if not DataService.trySpend(player, price) then
		Net.notify(player, `You need {Format.short(price - data.coins)} more coins`, "warning")
		return false
	end
	local record: Types.TrapRecord = { trapType = trapType, spot = spot }
	table.insert(data.traps, record)
	spawnTrap(player, base, record)
	Net.notify(player, `{DISPLAY_NAMES[trapType] or trapType} placed by your entrance!`, "success")
	return true
end

function TrapService.init() end

function TrapService.start()
	BaseService.Assigned:connect(spawnAll)
	BaseService.Released:connect(function(_player: Player, base: Model)
		trapFolder(base):ClearAllChildren()
	end)
	for _, player in Players:GetPlayers() do
		local base = BaseService.getBase(player)
		if base then
			spawnAll(player, base)
		end
	end
	Net.onEvent("BuyTrap", { Guard.oneOf(TrapService.Types) }, function(player: Player, trapType: string)
		TrapService.buy(player, trapType)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		stickyToken[player] = nil
	end)
end

return TrapService
