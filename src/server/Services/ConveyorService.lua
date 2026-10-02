--!strict
--[[
	ConveyorService
	Runs the shared egg conveyor in the lobby. Every Config.ConveyorSpawnInterval a
	new egg is rolled with the weighted rarity odds and glides down the belt. Its
	creature, rarity and price are shown above it, so nobody ever buys a mystery.

	Eggs are physics assemblies owned by the server and driven by a LinearVelocity,
	so clients see them move smoothly. They collide with nothing (players can't
	shove them) and are removed when they drop into the egg hole.

	Buying (ProximityPrompt) is validated on the server: the egg must still be on
	the belt, the player must be close, own a base, have a free pedestal and enough
	coins. The price always comes from CreatureData, never from the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local CreatureModels = require(Shared:WaitForChild("Models"):WaitForChild("CreatureModels"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CreatureService = require(script.Parent:WaitForChild("CreatureService"))
local Character = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Character"))
local Net = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Net"))
local RateLimiter = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("RateLimiter"))
local Ticker = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ticker"))

type Egg = {
	model: Model,
	root: BasePart,
	creatureId: string,
	price: number,
	sold: boolean,
}

local ConveyorService = {}

local eggs: { [Model]: Egg } = {}
local eggCount = 0
local folder: Folder
local startCFrame: CFrame
local direction: Vector3
local length: number
local rng = Random.new()

local CLEANUP_SEC = 0.25

local function addInfoBoard(root: BasePart, def: CreatureData.CreatureDef)
	local rarity = Rarity.get(def.rarity)
	local gui = Instance.new("BillboardGui")
	gui.Name = "EggInfo"
	gui.Size = UDim2.fromOffset(170, 66)
	gui.StudsOffsetWorldSpace = Vector3.new(0, root.Size.Y / 2 + 1.9, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Parent = root
	local rows: { { name: string, text: string, color: Color3, height: number } } = {
		{ name = "CreatureName", text = def.displayName, color = Color3.new(1, 1, 1), height = 0.38 },
		{ name = "Rarity", text = def.rarity, color = rarity.color, height = 0.3 },
		{
			name = "Price",
			text = `💰 {Format.short(def.eggPrice)}`,
			color = Color3.fromRGB(255, 220, 80),
			height = 0.32,
		},
	}
	local y = 0
	for _, row in rows do
		local label = Instance.new("TextLabel")
		label.Name = row.name
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0, y)
		label.Size = UDim2.fromScale(1, row.height)
		label.Font = Enum.Font.FredokaOne
		label.Text = row.text
		label.TextColor3 = row.color
		label.TextScaled = true
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = if row.name == "Rarity" then rarity.dark else Color3.fromRGB(30, 26, 40)
		stroke.Parent = label
		y += row.height
	end
end

local function destroyEgg(egg: Egg)
	if eggs[egg.model] then
		eggs[egg.model] = nil
		eggCount -= 1
	end
	egg.model:Destroy()
end

local function onBuy(player: Player, egg: Egg)
	if egg.sold or not eggs[egg.model] then
		return
	end
	if not RateLimiter.allow(player, "BuyEgg") then
		return
	end
	if not Character.isNear(player, egg.root.Position, Config.EggPromptDistance + Config.ActionDistanceSlack) then
		return
	end
	local def = CreatureData.get(egg.creatureId)
	if not def then
		return
	end
	if not BaseService.getBase(player) then
		Net.notify(player, "You need a base first. Hang tight!", "warning")
		return
	end
	if not CreatureService.freeSlot(player) then
		Net.notify(player, "No free pedestal! Unlock another one or sell a creature.", "warning")
		return
	end
	local coins = DataService.getCoins(player)
	if coins < def.eggPrice then
		Net.notify(player, `You need {Format.short(def.eggPrice - coins)} more coins`, "warning")
		return
	end
	-- Everything checked and nothing yields from here: charge, claim the egg, place it.
	if not DataService.trySpend(player, def.eggPrice) then
		return
	end
	egg.sold = true
	destroyEgg(egg)
	local record = CreatureService.add(player, def.id)
	if not record then
		DataService.addCoins(player, def.eggPrice) -- refund if placement failed
		Net.notify(player, "Couldn't place that egg, your coins were refunded.", "warning")
		return
	end
	Net.notify(player, `{def.displayName} egg placed on pedestal {record.slot}!`, "success")
end

local function spawnEgg()
	if eggCount >= Config.ConveyorMaxEggs then
		return
	end
	local rarity = Rarity.roll(rng)
	local options = CreatureData.ofRarity(rarity)
	if #options == 0 then
		return
	end
	local def = options[rng:NextInteger(1, #options)]
	local model = CreatureModels.build(def.id, { stage = "Egg", origin = startCFrame })
	local root = model.PrimaryPart :: BasePart
	root.Anchored = false
	root.CanCollide = false
	root.CanTouch = false
	root.Massless = false

	local attachment = Instance.new("Attachment")
	attachment.Name = "Drive"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.VectorVelocity = direction * Config.ConveyorSpeed
	velocity.ForceLimitsEnabled = false
	velocity.Parent = root
	local orientation = Instance.new("AlignOrientation")
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.Attachment0 = attachment
	orientation.CFrame = startCFrame.Rotation
	orientation.RigidityEnabled = true
	orientation.Parent = root

	addInfoBoard(root, def)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = `Buy for {Format.short(def.eggPrice)}`
	prompt.ObjectText = `{def.displayName} ({def.rarity})`
	prompt.HoldDuration = Config.EggPromptHoldSec
	prompt.MaxActivationDistance = Config.EggPromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	model:SetAttribute("Price", def.eggPrice)
	local egg: Egg = { model = model, root = root, creatureId = def.id, price = def.eggPrice, sold = false }
	prompt.Triggered:Connect(function(player: Player)
		onBuy(player, egg)
	end)
	eggs[model] = egg
	eggCount += 1
	model.Parent = folder
	root:SetNetworkOwner(nil)
	root.AssemblyLinearVelocity = direction * Config.ConveyorSpeed
end

local function cleanup()
	for _, egg in table.clone(eggs) do
		local travelled = (egg.root.Position - startCFrame.Position):Dot(direction)
		if travelled >= length or egg.root.Position.Y < -50 or not egg.root.Parent then
			destroyEgg(egg)
		end
	end
end

function ConveyorService.init()
	local conveyor = MapService.getLobby():WaitForChild("Conveyor")
	local beltStart = conveyor:WaitForChild("BeltStart") :: BasePart
	local beltEnd = conveyor:WaitForChild("BeltEnd") :: BasePart
	folder = conveyor:WaitForChild("Eggs") :: Folder
	local delta = beltEnd.Position - beltStart.Position
	direction = Vector3.new(delta.X, 0, delta.Z).Unit
	length = Vector3.new(delta.X, 0, delta.Z).Magnitude
	startCFrame = CFrame.lookAt(beltStart.Position, beltStart.Position + direction:Cross(Vector3.yAxis))
end

function ConveyorService.start()
	Ticker.every("ConveyorSpawn", Config.ConveyorSpawnInterval, spawnEgg)
	Ticker.every("ConveyorCleanup", CLEANUP_SEC, cleanup)
	spawnEgg()
end

return ConveyorService
