--!strict
--[[
	CombatService
	The bonk bat. Every player spawns with one (StarterPack). Swinging sends a
	"BatSwing" request with no arguments; the server picks the target itself:

	  * cooldown Config.BatCooldownSec, no swinging while stunned or carrying
	  * only at night and only inside a base
	  * the closest player within Config.BatRange studs in front of you
	    (look direction · direction to target >= Config.BatMinFacingDot)

	A hit never deals damage: it knocks the target back with a short stun
	(Config.BatStunSec) and makes them drop anything they were carrying. During the
	stun the server briefly owns the target's physics so the knockback can't be
	ignored by the client, then hands ownership back.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ModelKit = require(Shared:WaitForChild("Models"):WaitForChild("ModelKit"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local CycleService = require(script.Parent:WaitForChild("CycleService"))
local RaidService = require(script.Parent:WaitForChild("RaidService"))
local Character = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Character"))
local Net = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Net"))

local CombatService = {}

local BAT_NAME = "BonkBat"

local lastSwing: { [Player]: number } = {}
local stunnedUntil: { [Player]: number } = {}

local function buildBat(): Tool
	local tool = Instance.new("Tool")
	tool.Name = BAT_NAME
	tool.ToolTip = "Bonk raiders out of your base! (night only)"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	-- The bat is modelled along the handle's +X axis. R15's grip attachment points +Y up
	-- while a tool is held, so rotate the grip to stand the bat up, held near the knob.
	tool.Grip = CFrame.new(-0.35, 0, 0) * CFrame.Angles(0, 0, math.rad(-90))
	local up = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X; turn them upright
	local handle = ModelKit.part(
		"Handle",
		"Cylinder",
		Vector3.new(1.5, 0.42, 0.42),
		CFrame.new() * up,
		Color3.fromRGB(200, 60, 70),
		tool
	)
	handle.Anchored = false
	local function piece(
		name: string,
		shape: ModelKit.Shape,
		size: Vector3,
		offset: CFrame,
		color: Color3,
		material: Enum.Material?
	)
		local p = ModelKit.part(name, shape, size, handle.CFrame * offset, color, tool, { material = material })
		p.Anchored = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
	end
	-- After `up`, the handle's local +X points up the bat.
	piece("Knob", "Ball", Vector3.new(0.6, 0.6, 0.6), CFrame.new(-0.8, 0, 0), Color3.fromRGB(60, 40, 30))
	piece(
		"Barrel",
		"Cylinder",
		Vector3.new(2.4, 0.62, 0.62),
		CFrame.new(1.8, 0, 0),
		Color3.fromRGB(214, 160, 96),
		Enum.Material.Wood
	)
	piece(
		"Tip",
		"Ball",
		Vector3.new(0.8, 0.8, 0.8),
		CFrame.new(3.0, 0, 0),
		Color3.fromRGB(214, 160, 96),
		Enum.Material.Wood
	)
	piece("Band", "Cylinder", Vector3.new(0.22, 0.68, 0.68), CFrame.new(2.4, 0, 0), Color3.fromRGB(255, 210, 70))
	return tool
end

-- Knocks a player back and stuns them. No damage, ever.
function CombatService.stun(player: Player, velocity: Vector3, seconds: number)
	local now = os.clock()
	if (stunnedUntil[player] or 0) > now then
		return
	end
	local character = player.Character
	local root = Character.root(player)
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	stunnedUntil[player] = now + seconds
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = velocity
	task.delay(seconds, function()
		stunnedUntil[player] = nil
		if humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		if root.Parent and player.Parent == Players then
			pcall(function()
				root:SetNetworkOwner(player)
			end)
		end
	end)
end

function CombatService.isStunned(player: Player): boolean
	return (stunnedUntil[player] or 0) > os.clock()
end

local function findTarget(attacker: Player, attackerRoot: BasePart, base: Model): (Player?, BasePart?)
	local look = attackerRoot.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z).Unit
	local best: Player? = nil
	local bestRoot: BasePart? = nil
	local bestDistance = Config.BatRange
	for _, other in Players:GetPlayers() do
		if other == attacker then
			continue
		end
		local otherRoot = Character.root(other)
		local character = other.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if not otherRoot or not humanoid or humanoid.Health <= 0 then
			continue
		end
		local offset = otherRoot.Position - attackerRoot.Position
		local distance = offset.Magnitude
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if distance <= bestDistance and flat.Magnitude > 1e-3 and flatLook:Dot(flat.Unit) >= Config.BatMinFacingDot then
			if MapService.isInBase(base, otherRoot.Position) then
				best, bestRoot, bestDistance = other, otherRoot, distance
			end
		end
	end
	return best, bestRoot
end

local function onSwing(attacker: Player)
	local now = os.clock()
	if (lastSwing[attacker] or 0) + Config.BatCooldownSec > now or CombatService.isStunned(attacker) then
		return
	end
	local character = attacker.Character
	local tool = if character then character:FindFirstChild(BAT_NAME) else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local attackerRoot = Character.root(attacker)
	if not tool or not tool:IsA("Tool") or not humanoid or humanoid.Health <= 0 or not attackerRoot then
		return
	end
	lastSwing[attacker] = now
	-- The default Animate script plays its slash animation when it sees this value.
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
	if not CycleService.isNight() or RaidService.isCarrying(attacker) then
		return
	end
	local base = MapService.baseAt(attackerRoot.Position)
	if not base then
		return
	end
	local target, targetRoot = findTarget(attacker, attackerRoot, base)
	if not target or not targetRoot then
		return
	end
	local away =
		Vector3.new(targetRoot.Position.X - attackerRoot.Position.X, 0, targetRoot.Position.Z - attackerRoot.Position.Z)
	local dir = if away.Magnitude > 1e-3 then away.Unit else attackerRoot.CFrame.LookVector
	RaidService.drop(target)
	CombatService.stun(
		target,
		dir * Config.BatKnockbackSpeed + Vector3.new(0, Config.BatKnockbackLift, 0),
		Config.BatStunSec
	)
	Net.fireAll("BatHit", targetRoot.Position)
end

function CombatService.init()
	local existing = StarterPack:FindFirstChild(BAT_NAME)
	if existing then
		existing:Destroy()
	end
	buildBat().Parent = StarterPack
end

function CombatService.start()
	Net.onEvent("BatSwing", {}, onSwing)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastSwing[player] = nil
		stunnedUntil[player] = nil
	end)
end

return CombatService
