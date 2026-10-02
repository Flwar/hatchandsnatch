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

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
