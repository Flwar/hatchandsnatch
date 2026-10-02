--[[
	tests/run.luau
	Headless tests for everything that does not need a live Roblox server: config
	sanity, number formatting, rarity odds, creature data integrity, every creature
	model at every stage, and the procedural map structure.

	Run from the repo root:  lune run tests/run.luau
]]

local process = require("@lune/process")

local Loader = require("../tools/preview/loader")
local roblox = Loader.roblox
local Random = Loader.Random

local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print(`FAIL  {name}\n      {err}`)
	end
end

local function expect(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

local function eq(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(`{message or "values differ"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

local Config = Loader.require("src/shared/Config")
local Format = Loader.require("src/shared/Util/Format")
local Rarity = Loader.require("src/shared/Rarity")
local CreatureData = Loader.require("src/shared/CreatureData")
local CreatureModels = Loader.require("src/shared/Models/CreatureModels")
local MapBuilder = Loader.require("src/server/World/MapBuilder")

---------------------------------------------------------------------------
-- Config
---------------------------------------------------------------------------

test("Config is frozen, including nested tables", function()
	expect(table.isfrozen(Config), "Config should be frozen")
	expect(table.isfrozen(Config.Map), "Config.Map should be frozen")
	expect(table.isfrozen(Config.RarityWeights), "Config.RarityWeights should be frozen")
end)

test("Config has sensible core values", function()
	eq(Config.BaseCount, 8, "BaseCount")
	expect(Config.StartingPedestals <= Config.MaxPedestals, "starting pedestals exceed max")
	eq(
		Config.MaxPedestals,
		Config.Map.PedestalColumns * Config.Map.PedestalRows,
		"pedestal grid must hold MaxPedestals"
	)
	expect(Config.RaidValueBracketMin < 1 and Config.RaidValueBracketMax > 1, "raid bracket must include 1x")
	expect(Config.DayLengthSec > 0 and Config.NightLengthSec > 0, "cycle lengths must be positive")
end)

---------------------------------------------------------------------------
-- Format
---------------------------------------------------------------------------

test("Format.short", function()
	local cases = {
		{ 0, "0" },
		{ 7, "7" },
		{ 999, "999" },
		{ 1000, "1K" },
		{ 1234, "1.2K" },
		{ 12345, "12.3K" },
		{ 123456, "123K" },
		{ 999999, "999K" },
		{ 3400000, "3.4M" },
		{ 5.6e9, "5.6B" },
		{ 1.5e12, "1.5T" },
		{ -2500, "-2.5K" },
		{ 2.5, "2.5" },
		{ 0 / 0, "0" },
	}
	for _, case in cases do
		eq(Format.short(case[1]), case[2], `Format.short({case[1]})`)
	end
end)

test("Format.clock and commas", function()
	eq(Format.clock(151), "2:31")
	eq(Format.clock(45), "0:45")
	eq(Format.clock(3725), "1:02:05")
	eq(Format.clock(-5), "0:00")
	eq(Format.commas(1234567), "1,234,567")
	eq(Format.commas(999), "999")
	eq(Format.commas(-1000), "-1,000")
end)

---------------------------------------------------------------------------
-- Rarity
---------------------------------------------------------------------------

test("Rarity order and helpers", function()
	eq(#Rarity.Order, 7, "seven tiers")
	eq(Rarity.rank("Common"), 1)
	eq(Rarity.rank("Secret"), 7)
	eq(Rarity.step("Epic", 1), "Legendary")
	eq(Rarity.step("Secret", 1), "Secret", "step clamps at the top")
	expect(not Rarity.isValid("Banana"), "unknown rarity rejected")
	for _, name in Rarity.Order do
		expect(Config.RarityWeights[name] and Config.RarityWeights[name] > 0, `missing weight for {name}`)
	end
end)

test("Rarity.roll follows the configured weights", function()
	local rng = Random.new(1234)
	local counts: { [string]: number } = {}
	local samples = 50000
	for _ = 1, samples do
		local name = Rarity.roll(rng)
		counts[name] = (counts[name] or 0) + 1
	end
	local total = 0
	for _, weight in Config.RarityWeights do
		total += weight
	end
	for _, name in { "Common", "Uncommon", "Rare" } do
		local expected = Config.RarityWeights[name] / total
		local actual = (counts[name] or 0) / samples
		expect(math.abs(actual - expected) < 0.02, `{name}: expected ~{expected}, got {actual}`)
	end
	expect((counts.Common or 0) > (counts.Rare or 0), "Common must be more frequent than Rare")
end)

---------------------------------------------------------------------------
-- Creature data
---------------------------------------------------------------------------

test("Creature roster: 3 per tier, unique ids, art for every model", function()
	eq(#CreatureData.List, 21, "21 creatures")
	for _, name in Rarity.Order do
		eq(#CreatureData.ofRarity(name), 3, `{name} tier size`)
	end
	local seen = {}
	for _, def in CreatureData.List do
		expect(not seen[def.id], `duplicate id {def.id}`)
		seen[def.id] = true
		expect(CreatureModels.has(def.modelName), `no model for {def.modelName}`)
		expect(def.baseIncomePerSec > 0 and def.growTimeSec > 0 and def.eggPrice > 0, `bad numbers for {def.id}`)
		expect(#def.fusionTags >= 1, `{def.id} needs at least one fusion tag`)
		expect(#def.description > 0, `{def.id} needs a description`)
	end
end)

test("Higher tiers cost more and earn more", function()
	local previousMaxPrice, previousMaxIncome = 0, 0
	for _, name in Rarity.Order do
		local minPrice, maxPrice, minIncome, maxIncome = math.huge, 0, math.huge, 0
		for _, def in CreatureData.ofRarity(name) do
			minPrice = math.min(minPrice, def.eggPrice)
			maxPrice = math.max(maxPrice, def.eggPrice)
			minIncome = math.min(minIncome, def.baseIncomePerSec)
			maxIncome = math.max(maxIncome, def.baseIncomePerSec)
		end
		expect(minPrice > previousMaxPrice, `{name} eggs should all cost more than the tier below`)
		expect(minIncome > previousMaxIncome, `{name} should all earn more than the tier below`)
		previousMaxPrice, previousMaxIncome = maxPrice, maxIncome
	end
end)

---------------------------------------------------------------------------
-- Creature models
---------------------------------------------------------------------------

local PART_BUDGET = { Egg = 20, Baby = 52, Adult = 36 }

test("Every creature builds at every stage within the part budget", function()
	for _, def in CreatureData.List do
		for _, stage in { "Egg", "Baby", "Adult" } do
			local origin = roblox.CFrame.new(10, 2, -5)
			local model = CreatureModels.build(def.id, { stage = stage, origin = origin })
			local root = model.PrimaryPart
			expect(root and root.Name == "Root", `{def.id} {stage}: missing Root`)
			expect(root.Anchored and root.Transparency == 1, `{def.id} {stage}: Root must be invisible and anchored`)
			eq(model:GetAttribute("CreatureId"), def.id, `{def.id} {stage}: CreatureId attribute`)
			eq(model:GetAttribute("Stage"), stage, `{def.id} {stage}: Stage attribute`)
			-- Pivot sits on the ground under the creature.
			local pivot = root.CFrame * root.PivotOffset
			expect((pivot.Position - origin.Position).Magnitude < 1e-3, `{def.id} {stage}: pivot is off the origin`)
			local count = 0
			for _, inst in model:GetDescendants() do
				if inst:IsA("BasePart") and inst ~= root then
					count += 1
					expect(not inst.Anchored, `{def.id} {stage}: {inst.Name} should be welded, not anchored`)
					expect(not inst.CanCollide, `{def.id} {stage}: {inst.Name} should not collide`)
					local weld = inst:FindFirstChildOfClass("WeldConstraint")
					expect(weld and weld.Part0 == root, `{def.id} {stage}: {inst.Name} is not welded to Root`)
					expect(
						inst.Size.X > 0 and inst.Size.Y > 0 and inst.Size.Z > 0,
						`{def.id} {stage}: {inst.Name} has a zero size`
					)
				end
			end
			expect(count <= PART_BUDGET[stage], `{def.id} {stage}: {count} parts exceeds budget {PART_BUDGET[stage]}`)
			-- Adults must fit on a pedestal (with a little overhang) and nothing sinks deep below it.
			if stage == "Adult" then
				local footprint = math.max(root.Size.X, root.Size.Z)
				expect(footprint <= 9.5, `{def.id}: footprint {footprint} too large for a pedestal`)
				local bottom = root.CFrame.Position.Y - root.Size.Y / 2
				expect(
					bottom >= origin.Position.Y - 0.3,
					`{def.id}: model sinks {origin.Position.Y - bottom} studs below its pivot`
				)
			end
		end
	end
end)

test("Unknown creature ids are rejected", function()
	local ok = pcall(CreatureModels.build, "not_a_creature", nil)
	expect(not ok, "building an unknown creature should error")
end)

---------------------------------------------------------------------------
-- Map
---------------------------------------------------------------------------

test("Map has a lobby, conveyor markers and every base fully built", function()
	local workspace = roblox.Instance.new("Folder")
	local map = MapBuilder.build(workspace)
	eq(map.Name, "Map")
	local lobby = map:FindFirstChild("Lobby")
	expect(lobby, "missing Lobby")
	local conveyor = lobby:FindFirstChild("Conveyor")
	expect(
		conveyor and conveyor:FindFirstChild("BeltStart") and conveyor:FindFirstChild("BeltEnd"),
		"missing belt markers"
	)
	expect(lobby:FindFirstChild("LobbySpawn"), "missing LobbySpawn")
	expect(lobby:FindFirstChild("GalleryAnchor"), "missing GalleryAnchor")
	local bases = map:FindFirstChild("Bases"):GetChildren()
	eq(#bases, Config.BaseCount, "base count")
	local seenIndex = {}
	for _, base in bases do
		local index = base:GetAttribute("BaseIndex")
		expect(index and not seenIndex[index], `bad BaseIndex on {base.Name}`)
		seenIndex[index] = true
		eq(base:GetAttribute("OwnerUserId"), 0, `{base.Name} starts unowned`)
		for _, name in { "Spawn", "Shield", "Sign", "CollectPad", "Pedestals", "Barriers" } do
			expect(base:FindFirstChild(name), `{base.Name} missing {name}`)
		end
		local shield = base:FindFirstChild("Shield")
		expect(shield.CanCollide and shield.Material == roblox.Enum.Material.ForceField, `{base.Name} shield`)
		local pedestals = base:FindFirstChild("Pedestals"):GetChildren()
		eq(#pedestals, Config.MaxPedestals, `{base.Name} pedestal count`)
		for _, pedestal in pedestals do
			local top = pedestal:FindFirstChild("Top")
			expect(top and top:FindFirstChild("Socket"), `{base.Name} {pedestal.Name} missing Socket`)
			eq(pedestal:GetAttribute("Unlocked"), false, `{pedestal.Name} starts locked`)
		end
	end
end)

test("Bases do not overlap each other or the lobby", function()
	local half = Config.Map.BaseSize / 2
	local corner = math.sqrt(2) * half
	for i = 1, Config.BaseCount do
		local a = MapBuilder.baseCFrame(i).Position
		expect(a.Magnitude - corner > Config.Map.LobbyRadius + 10, `base {i} is too close to the lobby`)
		for j = i + 1, Config.BaseCount do
			local b = MapBuilder.baseCFrame(j).Position
			expect((a - b).Magnitude > Config.Map.BaseSize + 8, `bases {i} and {j} overlap`)
		end
		-- Every base faces the lobby.
		local look = MapBuilder.baseCFrame(i).LookVector
		expect(look:Dot(-a.Unit) > 0.999, `base {i} does not face the lobby`)
	end
end)

test("Pedestal unlock toggles visuals and collision", function()
	local workspace = roblox.Instance.new("Folder")
	local map = MapBuilder.build(workspace)
	local pedestal =
		map:FindFirstChild("Bases"):FindFirstChild("Base1"):FindFirstChild("Pedestals"):FindFirstChild("Pedestal1")
	MapBuilder.setPedestalUnlocked(pedestal, true)
	eq(pedestal:FindFirstChild("Top").Transparency, 0, "top visible when unlocked")
	expect(pedestal:FindFirstChild("Top").CanCollide, "top collides when unlocked")
	eq(pedestal:FindFirstChild("LockedPad").Transparency, 1, "locked pad hidden when unlocked")
	MapBuilder.setPedestalUnlocked(pedestal, false)
	eq(pedestal:FindFirstChild("Top").Transparency, 1, "top hidden when locked")
	expect(not pedestal:FindFirstChild("Top").CanCollide, "top does not collide when locked")
end)

---------------------------------------------------------------------------
-- Growth & economy (Milestone 1)
---------------------------------------------------------------------------

local Growth = Loader.require("src/shared/Growth")
local Economy = Loader.require("src/shared/Economy")

test("Growth stages follow the configured fractions", function()
	local grow, planted = 100, 1000
	eq(Growth.stage(grow, planted, planted), "Egg")
	eq(Growth.stage(grow, planted, planted + 29), "Egg")
	eq(Growth.stage(grow, planted, planted + 30), "Baby")
	eq(Growth.stage(grow, planted, planted + 99), "Baby")
	eq(Growth.stage(grow, planted, planted + 100), "Adult")
	eq(Growth.stage(grow, planted, planted + 1e6), "Adult", "offline growth keeps going")
	eq(Growth.progress(grow, planted, planted - 50), 0, "clock skew never goes negative")
	eq(Growth.secondsToNextStage(grow, planted, planted + 10), 20)
	eq(Growth.secondsToNextStage(grow, planted, planted + 40), 60)
	eq(Growth.secondsToNextStage(grow, planted, planted + 100), nil)
end)

test("Economy formulas", function()
	eq(Economy.pedestalCost(Config.StartingPedestals), Config.PedestalBaseCost, "7th pedestal price")
	expect(
		Economy.pedestalCost(Config.StartingPedestals + 1) > Economy.pedestalCost(Config.StartingPedestals),
		"pedestals get pricier"
	)
	eq(Economy.incomePerSec("blobbit", nil), 1)
	eq(Economy.incomePerSec("blobbit", "Rainbow"), 5)
	eq(Economy.incomePerSec("not_real", nil), 0)
	eq(Economy.sellValue("pebblepup", nil), math.floor(40 * Config.SellRefundFraction))
	expect(Economy.sellValue("blobbit", nil) < 25, "selling never refunds the full price")
end)

-- Plays the core loop with the real config and data: a fresh player buys the best egg
-- they can afford from the belt, collects their pad every 15 s, and swaps a weaker
-- creature for a better egg when every pedestal is full. Milestone 1 is "done" when
-- a new player can reach a Rare through normal play.
local function simulate(seed: number): number?
	local rng = Random.new(seed)
	local workspace = roblox.Instance.new("Folder")
	local conveyor = MapBuilder.build(workspace):FindFirstChild("Lobby"):FindFirstChild("Conveyor")
	local beltLength = (
		conveyor:FindFirstChild("BeltEnd").CFrame.Position - conveyor:FindFirstChild("BeltStart").CFrame.Position
	).Magnitude
	local beltSeconds = beltLength / Config.ConveyorSpeed
	local coins, pad = Config.StartingCoins, 0
	local owned: { { id: string, planted: number } } = {}
	local belt: { { id: string, spawned: number } } = {}
	local rareRank = Rarity.rank("Rare")
	for t = 0, 3600 do
		if t % Config.ConveyorSpawnInterval == 0 then
			local options = CreatureData.ofRarity(Rarity.roll(rng))
			table.insert(belt, { id = options[rng:NextInteger(1, #options)].id, spawned = t })
		end
		for i = #belt, 1, -1 do
			if t - belt[i].spawned >= beltSeconds then
				table.remove(belt, i)
			end
		end
		for _, creature in owned do
			local def = CreatureData.get(creature.id)
			if Growth.stage(def.growTimeSec, creature.planted, t) == "Adult" then
				pad += Economy.incomePerSec(creature.id, nil)
			end
		end
		if t % 15 == 0 then
			coins += math.floor(pad)
			pad -= math.floor(pad)
		end
		local bestIndex, bestPrice = nil, -1
		for i, egg in belt do
			local price = CreatureData.get(egg.id).eggPrice
			if price <= coins and price > bestPrice then
				bestIndex, bestPrice = i, price
			end
		end
		if bestIndex then
			local egg = belt[bestIndex]
			local def = CreatureData.get(egg.id)
			local bought = false
			if #owned < Config.StartingPedestals then
				bought = true
			else
				local worstIndex, worstPrice = 1, math.huge
				for i, creature in owned do
					local price = CreatureData.get(creature.id).eggPrice
					if price < worstPrice then
						worstIndex, worstPrice = i, price
					end
				end
				local worst = owned[worstIndex]
				if Rarity.rank(def.rarity) > Rarity.rank(CreatureData.get(worst.id).rarity) then
					coins += Economy.sellValue(worst.id, nil)
					table.remove(owned, worstIndex)
					bought = coins >= def.eggPrice
				end
			end
			if bought then
				coins -= def.eggPrice
				table.insert(owned, { id = egg.id, planted = t })
				table.remove(belt, bestIndex)
				if Rarity.rank(def.rarity) >= rareRank then
					return t
				end
			end
		end
	end
	return nil
end

test("A new player can reach a Rare creature through normal play", function()
	local times = {}
	for seed = 1, 60 do
		local reached = simulate(seed)
		expect(reached, `seed {seed}: never reached a Rare within an hour`)
		table.insert(times, reached)
	end
	table.sort(times)
	local median = times[#times // 2]
	local worst = times[#times]
	expect(median <= 10 * 60, `median time to first Rare is {median}s (target: under 10 minutes)`)
	expect(worst <= 20 * 60, `slowest time to first Rare is {worst}s (target: under 20 minutes)`)
	print(`      first Rare: median {Format.clock(median)}, slowest {Format.clock(worst)} over {#times} runs`)
end)

test("Conveyor markers, egg folder and creature folders exist", function()
	local workspace = roblox.Instance.new("Folder")
	local map = MapBuilder.build(workspace)
	local conveyor = map:FindFirstChild("Lobby"):FindFirstChild("Conveyor")
	expect(conveyor:FindFirstChild("Eggs"), "missing Eggs folder")
	local startX = conveyor:FindFirstChild("BeltStart").CFrame.Position.X
	local endX = conveyor:FindFirstChild("BeltEnd").CFrame.Position.X
	expect(endX - startX > Config.Map.ConveyorLength - 5, "belt path too short")
	for _, base in map:FindFirstChild("Bases"):GetChildren() do
		expect(base:FindFirstChild("Creatures"), `{base.Name} missing Creatures folder`)
	end
end)

---------------------------------------------------------------------------
-- Persistence (Milestone 2)
---------------------------------------------------------------------------

local Offline = Loader.require("src/shared/Offline")
local DataSchema = Loader.require("src/server/Util/DataSchema")

test("Offline earnings only count adult time and respect the cap", function()
	local logout = 1000000
	-- Blobbit: 1 coin/s, grows up 30 s after planting.
	local adult = { uid = "a", id = "blobbit", plantedAt = logout - 100, locked = false, slot = 1 }
	local coins, seconds = Offline.earnings({ adult }, logout, logout + 600, nil)
	eq(coins, 600, "an adult earns for the whole absence")
	eq(seconds, 600)
	local egg = { uid = "b", id = "blobbit", plantedAt = logout, locked = false, slot = 2 }
	coins = Offline.earnings({ egg }, logout, logout + 600, nil)
	eq(coins, 570, "an egg only earns after it grows up (30 s)")
	local capSec = Config.OfflineIncomeCapHours * 3600
	coins, seconds = Offline.earnings({ adult }, logout, logout + capSec * 3, nil)
	eq(coins, capSec, "earnings stop at the offline cap")
	eq(seconds, capSec)
	coins = Offline.earnings({ adult }, logout, logout + 600, 2)
	eq(coins, 1200, "multipliers apply")
	eq((Offline.earnings({ adult }, 0, logout, nil)), 0, "first ever login earns nothing")
	eq((Offline.earnings({ adult }, logout, logout - 5, nil)), 0, "clock going backwards earns nothing")
end)

test("DataSchema template and migration repair old or broken saves", function()
	local fresh = DataSchema.template()
	eq(fresh.coins, Config.StartingCoins)
	eq(fresh.pedestals, Config.StartingPedestals)
	eq(fresh.version, Config.DataSchemaVersion)
	local old = {
		coins = "123",
		pedestals = 999,
		creatures = {
			{ uid = "x", id = "blobbit", plantedAt = 5, slot = 2 },
			{ id = "missing_uid" },
			"garbage",
		},
		discoveries = 7,
	}
	local migrated = DataSchema.migrate(old)
	eq(migrated.coins, 123, "numeric strings become numbers")
	eq(migrated.pedestals, Config.MaxPedestals, "pedestals clamp to the max")
	eq(#migrated.creatures, 1, "malformed creature records are dropped")
	eq(migrated.creatures[1].locked, false, "missing booleans default to false")
	eq(type(migrated.discoveries), "table", "wrong-typed fields are replaced")
	eq(migrated.padCoins, 0, "missing fields get their default")
	eq(migrated.version, Config.DataSchemaVersion)
	local nan = DataSchema.migrate({ coins = 0 / 0, pedestals = -4 })
	eq(nan.coins, Config.StartingCoins, "corrupt NaN coins reset to the starting balance")
	eq(nan.pedestals, Config.StartingPedestals, "pedestals never drop below the start")
	eq(fresh.tutorialStep, 1, "new players start the tutorial")
	eq(fresh.settings.sfx and fresh.settings.labels, true, "settings default on")
	local settings = DataSchema.migrate({ settings = { sfx = false }, tutorialStep = 42 })
	eq(settings.settings.sfx, false, "saved settings are kept")
	eq(settings.settings.labels, true, "missing settings default on")
	eq(settings.tutorialStep, 5, "tutorial step clamps to done")
	eq(DataSchema.migrate({ settings = "bad" }).settings.sfx, true, "broken settings are replaced")
end)

---------------------------------------------------------------------------
-- Night raids (Milestone 3)
---------------------------------------------------------------------------

local RaidRules = Loader.require("src/shared/RaidRules")
local TrapModels = Loader.require("src/shared/Models/TrapModels")

test("New-player shield", function()
	local hour = Config.NewPlayerShieldMinutes * 60
	expect(RaidRules.isProtected(0, 0, false), "brand new players are protected")
	expect(RaidRules.isProtected(hour - 1, Config.NewPlayerShieldValue, false), "still protected just under the limits")
	expect(not RaidRules.isProtected(hour, 0, false), "protection ends after the playtime limit")
	expect(
		not RaidRules.isProtected(0, Config.NewPlayerShieldValue + 1, false),
		"protection ends above the value limit"
	)
	expect(not RaidRules.isProtected(0, 0, true), "stealing ends your own protection")
end)

test("Value bracket", function()
	expect(RaidRules.inBracket(1000, 1000), "equal bases are in bracket")
	expect(RaidRules.inBracket(1000, 1000 * Config.RaidValueBracketMax), "upper edge is in bracket")
	expect(RaidRules.inBracket(1000, 1000 * Config.RaidValueBracketMin), "lower edge is in bracket")
	expect(not RaidRules.inBracket(1000, 1000 * Config.RaidValueBracketMax + 1), "too rich is out")
	expect(not RaidRules.inBracket(1000, 1000 * Config.RaidValueBracketMin - 1), "too poor is out")
	expect(not RaidRules.inBracket(0, 500), "a player with nothing can't raid")
	expect(not RaidRules.inBracket(500, 0), "an empty base isn't worth raiding")
end)

test("canRaid combines night, protection, bracket and revenge", function()
	local base =
		{ isNight = true, attackerValue = 1000, victimValue = 1200, victimProtected = false, hasRevenge = false }
	expect((RaidRules.canRaid(base)), "a fair night raid is allowed")
	local day = table.clone(base)
	day.isNight = false
	local allowed, reason = RaidRules.canRaid(day)
	expect(not allowed and reason ~= nil, "no raids by day")
	local protected = table.clone(base)
	protected.victimProtected = true
	expect(not RaidRules.canRaid(protected), "protected players can't be raided")
	local rich = table.clone(base)
	rich.victimValue = 1e9
	expect(not RaidRules.canRaid(rich), "out-of-bracket raids are blocked")
	local revengeByDay = table.clone(day)
	revengeByDay.hasRevenge = true
	revengeByDay.victimValue = 1e9
	revengeByDay.victimProtected = true
	expect((RaidRules.canRaid(revengeByDay)), "revenge works by day and ignores the bracket")
end)

test("Trap models build and every base has a trap spot per trap slot", function()
	for _, trapType in { "BananaPeel", "StickyFloor", "HonkEgg" } do
		local model = TrapModels.build(trapType, roblox.CFrame.new(0, 0, 0))
		expect(model.PrimaryPart and model.PrimaryPart.Name == "Root", `{trapType} has a Root`)
		expect(Config.TrapPrices[trapType] and Config.TrapPrices[trapType] > 0, `{trapType} has a price`)
	end
	local workspace = roblox.Instance.new("Folder")
	local map = MapBuilder.build(workspace)
	for _, base in map:FindFirstChild("Bases"):GetChildren() do
		local spots = base:FindFirstChild("TrapSpots")
		eq(#spots:GetChildren(), Config.MaxTraps, `{base.Name} trap spots`)
	end
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
