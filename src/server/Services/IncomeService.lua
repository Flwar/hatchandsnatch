--!strict
--[[
	IncomeService
	Adult creatures earn coins into their owner's collect pad on one server-wide
	tick (Config.IncomeTickSec). Stepping on your own pad moves the pending coins
	into your balance. Pending coins are saved with the player's data.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CreatureService = require(script.Parent:WaitForChild("CreatureService"))
local Character = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Character"))
local Net = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Net"))
local RateLimiter = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("RateLimiter"))
local Ticker = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ticker"))

local IncomeService = {}

-- Fired as (player, amount) whenever a player collects their pad.
IncomeService.Collected = Signal.new()

local function padOf(base: Model): BasePart?
	local padModel = base:FindFirstChild("CollectPad")
	local pad = if padModel then padModel:FindFirstChild("Pad") else nil
	if pad and pad:IsA("BasePart") then
		return pad :: BasePart
	end
	return nil
end

local function setPadText(base: Model, amount: number)
	local pad = padOf(base)
	local gui = if pad then pad:FindFirstChild("CoinsGui") else nil
	local label = if gui then gui:FindFirstChild("Amount") else nil
	if label and label:IsA("TextLabel") then
		(label :: TextLabel).Text = `💰 {Format.short(math.floor(amount))}`
	end
end

local function refreshPad(player: Player)
	local base = BaseService.getBase(player)
	local data = DataService.get(player)
	if base and data then
		setPadText(base, data.padCoins)
	end
end

-- Moves the whole-coin part of the pad balance into the player's coins.
function IncomeService.collect(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	local amount = math.floor(data.padCoins)
	if amount < 1 then
		return 0
	end
	data.padCoins -= amount
	DataService.addCoins(player, amount)
	refreshPad(player)
	Net.notify(player, `+{Format.short(amount)} coins collected!`, "success")
	IncomeService.Collected:fire(player, amount)
	return amount
end

local function onPadTouched(base: Model, pad: BasePart, hit: BasePart)
	local character = hit.Parent
	local player = if character and character:IsA("Model")
		then Players:GetPlayerFromCharacter(character :: Model)
		else nil
	if not player then
		return
	end
	local index = base:GetAttribute("BaseIndex")
	if typeof(index) ~= "number" or BaseService.getOwner(index) ~= player then
		return
	end
	-- Touches fire for every limb; the rate limiter quietly drops the duplicates.
	if not RateLimiter.allow(player, "CollectPad") then
		return
	end
	if not Character.isNear(player, pad.Position, Config.CollectPadReach + Config.ActionDistanceSlack) then
		return
	end
	IncomeService.collect(player)
end

local function tick(dt: number)
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data then
			local rate = CreatureService.incomePerSec(player)
			if player:GetAttribute("IncomePerSec") ~= rate then
				player:SetAttribute("IncomePerSec", rate)
			end
			if rate > 0 then
				data.padCoins += rate * dt
				refreshPad(player)
			end
		end
	end
end

function IncomeService.init()
	for _, base in MapService.getBases() do
		local pad = padOf(base)
		if pad then
			pad.Touched:Connect(function(hit: BasePart)
				onPadTouched(base, pad, hit)
			end)
		end
	end
end

function IncomeService.start()
	BaseService.Assigned:connect(function(player: Player)
		refreshPad(player)
	end)
	BaseService.Released:connect(function(_player: Player, base: Model)
		setPadText(base, 0)
	end)
	Ticker.every("Income", Config.IncomeTickSec, tick)
end

return IncomeService
