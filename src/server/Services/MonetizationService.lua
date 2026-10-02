--!strict
--[[
	MonetizationService
	Game passes and developer products (ids in Config.GamePasses / Config.DevProducts).

	Passes (checked on join and right after a purchase):
	  * 2x Income      IncomeService and offline earnings multiplier
	  * +6 Pedestals   unlocks Config.PassBonusPedestals pedestals for free, once
	  * VIP Base       a golden look for the base (World/VipDecor), cosmetic only
	  * Faster Fusion  FusionService duration multiplier

	Products (MarketplaceService.ProcessReceipt):
	  * coin packs: minutes of the player's current income (shared/Products)
	  * Instant Grow: a token that grows one egg or baby into an adult (UseGrowToken)
	  * bat skins: cosmetic bonk bat looks (EquipBatSkin)

	Receipts are idempotent: a purchase id is recorded in the player's profile in the
	same change that grants it, and the purchase is only confirmed to Roblox once a
	saved copy of the profile contains that id (ProfileStore LastSavedData). A retry
	of an already granted purchase is confirmed without granting it again.

	Nothing sold is random, and nothing gives an edge in raids or the arena.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Growth = require(Shared:WaitForChild("Growth"))
local Products = require(Shared:WaitForChild("Products"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))

local Util = script.Parent.Parent:WaitForChild("Util")
local Net = require(Util:WaitForChild("Net"))
local Guard = require(Util:WaitForChild("Guard"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CreatureService = require(script.Parent:WaitForChild("CreatureService"))
local IncomeService = require(script.Parent:WaitForChild("IncomeService"))
local FusionService = require(script.Parent:WaitForChild("FusionService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

local VipDecor = require(script.Parent.Parent:WaitForChild("World"):WaitForChild("VipDecor"))

local MonetizationService = {}

-- Fired as (player, productKey) after a product is granted.
MonetizationService.Granted = Signal.new()

local owned: { [Player]: { [string]: boolean } } = {}

function MonetizationService.owns(player: Player, passKey: string): boolean
	local passes = owned[player]
	return passes ~= nil and passes[passKey] == true
end

---------------------------------------------------------------------------
-- Passes
---------------------------------------------------------------------------

local function publish(player: Player)
	local data = DataService.get(player)
	for key in Config.GamePasses :: any do
		player:SetAttribute(`Pass{key}`, MonetizationService.owns(player, key))
	end
	if data then
		player:SetAttribute("GrowTokens", data.growTokens)
		player:SetAttribute("BatSkin", data.equippedBat)
		local skins = {}
		for skin, has in data.batSkins do
			if has then
				table.insert(skins, skin)
			end
		end
		table.sort(skins)
		player:SetAttribute("BatSkins", table.concat(skins, ","))
	end
end

local function grantBonusPedestals(player: Player)
	local data = DataService.get(player)
	if not data or not MonetizationService.owns(player, "ExtraPedestals") then
		return
	end
	local grant = math.min(Config.PassBonusPedestals - data.bonusPedestals, Config.MaxPedestals - data.pedestals)
	if grant > 0 then
		data.pedestals += grant
		data.bonusPedestals += grant
		BaseService.refresh(player)
		Net.notify(player, `🏛️ {grant} free pedestals unlocked!`, "success")
	end
end

local function applyPasses(player: Player)
	grantBonusPedestals(player)
	local base = BaseService.getBase(player)
	if base then
		if MonetizationService.owns(player, "VipBase") then
			VipDecor.apply(base)
		else
			VipDecor.remove(base)
		end
	end
	publish(player)
end

local function checkPasses(player: Player)
	local passes = owned[player] or {}
	owned[player] = passes
	for key, pass in Config.GamePasses :: any do
		if pass.id ~= 0 and not passes[key] then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and has then
				passes[key] = true
			end
		end
	end
	applyPasses(player)
end

local function passKeyFor(passId: number): string?
	for key, pass in Config.GamePasses :: any do
		if pass.id == passId and passId ~= 0 then
			return key
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Products
---------------------------------------------------------------------------

local function grantProduct(player: Player, key: string): boolean
	local product = (Config.DevProducts :: any)[key]
	local data = DataService.get(player)
	if not product or not data then
		return false
	end
	if product.kind == "coins" then
		local rate = player:GetAttribute("IncomePerSec")
		local amount = Products.coinPackAmount(key, if typeof(rate) == "number" then rate else 0)
		DataService.addCoins(player, amount)
		Net.notify(player, `{product.icon} +{Format.short(amount)} coins. Thank you!`, "success")
	elseif product.kind == "growToken" then
		data.growTokens += 1
		Net.notify(player, "🌱 Instant Grow token added! Use it from your Inventory.", "success")
	elseif product.kind == "batSkin" then
		data.batSkins[product.skin] = true
		data.equippedBat = product.skin
		CombatService.applySkin(player, product.skin)
		Net.notify(player, `{product.icon} {product.name} unlocked and equipped!`, "success")
	else
		return false
	end
	publish(player)
	MonetizationService.Granted:fire(player, key)
	return true
end

local function isSaved(profile: any, purchaseId: string): boolean
	local last = profile.LastSavedData
	return type(last) == "table" and type(last.receipts) == "table" and table.find(last.receipts, purchaseId) ~= nil
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = if player then DataService.getProfile(player) else nil
	local data = if player then DataService.get(player) else nil
	if not player or not profile or not data or not profile:IsActive() then
		-- Not loaded here; Roblox retries next time the player joins.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = Products.productKey(receipt.ProductId)
	if not key then
		warn(`MonetizationService: unknown product {receipt.ProductId}; set its id in Config.DevProducts`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if not table.find(data.receipts, purchaseId) then
		if not grantProduct(player, key) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		table.insert(data.receipts, purchaseId)
		while #data.receipts > Config.ReceiptHistorySize do
			table.remove(data.receipts, 1)
		end
	end
	-- Confirm only once the receipt id has been saved.
	if not isSaved(profile, purchaseId) then
		profile:Save()
		while profile:IsActive() and not isSaved(profile, purchaseId) do
			task.wait(0.5)
		end
	end
	return if isSaved(profile, purchaseId)
		then Enum.ProductPurchaseDecision.PurchaseGranted
		else Enum.ProductPurchaseDecision.NotProcessedYet
end

---------------------------------------------------------------------------
-- Using what was bought
---------------------------------------------------------------------------

local function onUseGrowToken(player: Player, uid: string)
	local data = DataService.get(player)
	local entry = CreatureService.get(uid)
	if not data or data.growTokens <= 0 or not entry or entry.owner ~= player or entry.state ~= "Placed" then
		return
	end
	local def = CreatureData.get(entry.record.id)
	if not def or Growth.stage(def.growTimeSec, entry.record.plantedAt, os.time()) == "Adult" then
		return
	end
	data.growTokens -= 1
	entry.record.plantedAt = os.time() - def.growTimeSec
	CreatureService.refreshStage(uid)
	publish(player)
	Net.notify(player, `🌱 Your {def.displayName} grew up instantly!`, "success")
end

local function onEquipBatSkin(player: Player, skin: string)
	local data = DataService.get(player)
	if not data or (skin ~= "Classic" and data.batSkins[skin] ~= true) then
		return
	end
	data.equippedBat = skin
	CombatService.applySkin(player, skin)
	publish(player)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function MonetizationService.init()
	IncomeService.multiplier = function(player: Player): number
		return if MonetizationService.owns(player, "DoubleIncome") then Config.PassIncomeMultiplier else 1
	end
	DataService.offlineMultiplier = function(player: Player): number
		return if MonetizationService.owns(player, "DoubleIncome") then Config.PassIncomeMultiplier else 1
	end
	FusionService.durationFor = function(player: Player): number
		local speed = if MonetizationService.owns(player, "FastFusion") then Config.PassFusionSpeed else 1
		return Config.FusionTimeSec * speed
	end
end

function MonetizationService.start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			local key = passKeyFor(passId)
			if purchased and key then
				local passes = owned[player] or {}
				owned[player] = passes
				passes[key] = true
				applyPasses(player)
				local pass = (Config.GamePasses :: any)[key]
				Net.notify(player, `{pass.icon} {pass.name} unlocked. Thank you!`, "success")
			end
		end
	)
	DataService.Loaded:connect(function(player: Player)
		task.spawn(checkPasses, player)
		player.CharacterAdded:Connect(function(character: Model)
			-- The bat arrives from StarterPack a moment after the character.
			character:WaitForChild("Humanoid", 10)
			task.wait(0.5)
			local data = DataService.get(player)
			if data then
				CombatService.applySkin(player, data.equippedBat)
			end
		end)
	end)
	BaseService.Assigned:connect(function(player: Player)
		if owned[player] then
			applyPasses(player)
		end
	end)
	BaseService.Released:connect(function(_player: Player, base: Model)
		VipDecor.remove(base)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		owned[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if DataService.get(player) then
			task.spawn(checkPasses, player)
		end
	end
	Net.onEvent("UseGrowToken", { Guard.uid() }, onUseGrowToken)
	Net.onEvent("EquipBatSkin", { Guard.oneOf(Products.BatOrder :: any) }, onEquipBatSkin)
end

return MonetizationService
