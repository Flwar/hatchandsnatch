--!strict
--[[
	Config
	Every tunable number in Hatch & Snatch lives here, so the game can be balanced
	without touching any logic. The table is deep-frozen at the bottom of the file,
	so nothing can change it at runtime by accident.

	Units: seconds (Sec), studs, coins. Percentages are written as 0..1 fractions.
]]

local Config = {}

---------------------------------------------------------------------------
-- Players & bases
---------------------------------------------------------------------------
Config.BaseCount = 8 -- bases per server (also the intended max players)
Config.StartingCoins = 50
Config.StartingPedestals = 6
Config.MaxPedestals = 24
Config.PedestalBaseCost = 750 -- price of the 7th pedestal
Config.PedestalCostGrowth = 1.55 -- each extra pedestal costs this much more than the last
Config.RespawnDelaySec = 3

---------------------------------------------------------------------------
-- Egg conveyor
---------------------------------------------------------------------------
Config.ConveyorSpawnInterval = 4
Config.ConveyorSpeed = 5 -- studs per second
Config.ConveyorMaxEggs = 20 -- hard cap on eggs alive on the belt
Config.EggPromptDistance = 10
Config.EggPromptHoldSec = 0 -- instant buy; raise it if players mis-buy by accident

-- Weighted odds used when the conveyor rolls a rarity. Relative weights, not percentages.
Config.RarityWeights = {
	Common = 600,
	Uncommon = 250,
	Rare = 100,
	Epic = 38,
	Legendary = 9,
	Mythic = 2.5,
	Secret = 0.5,
}

---------------------------------------------------------------------------
-- Growth & income
---------------------------------------------------------------------------
Config.BabyAtFraction = 0.3 -- Egg -> Baby at 30% of growTimeSec
Config.AdultAtFraction = 1.0 -- Baby -> Adult at 100% of growTimeSec
Config.IncomeTickSec = 1
Config.OfflineIncomeCapHours = 8
Config.SellRefundFraction = 0.5 -- selling refunds this fraction of the egg price

---------------------------------------------------------------------------
-- Base interactions (prompts and the collect pad)
---------------------------------------------------------------------------
Config.CreaturePromptDistance = 9
Config.SellPromptHoldSec = 1
Config.UnlockPromptHoldSec = 0.5
Config.CollectPadReach = 10 -- max distance from the pad centre for a valid collect
Config.ActionDistanceSlack = 4 -- extra studs allowed on server distance checks (lag)

---------------------------------------------------------------------------
-- Day / night
---------------------------------------------------------------------------
Config.DayLengthSec = 600
Config.NightLengthSec = 120
Config.LightingTweenSec = 6

---------------------------------------------------------------------------
-- Raids (night only) & fairness
---------------------------------------------------------------------------
Config.DefaultWalkSpeed = 16
Config.CarryWalkSpeed = 10
Config.StealPromptHoldSec = 1.2
Config.StealPromptDistance = 8
Config.CarryHeight = 2.6 -- studs above the head where a stolen creature is held
Config.ZoneCheckSec = 0.4 -- how often the server checks who is standing in which base
Config.ProtectedNoticeCooldownSec = 4
Config.NewPlayerShieldMinutes = 60
Config.NewPlayerShieldValue = 25000 -- base value at which the new-player shield ends early
Config.RaidValueBracketMin = 0.33
Config.RaidValueBracketMax = 3
Config.RevengeWindowSec = 180
Config.StealCooldownSec = 90
Config.DroppedCreatureWalkSpeed = 8
Config.ShieldOpenTransparency = 0.92 -- how faint an open shield looks

---------------------------------------------------------------------------
-- Bonk bat
---------------------------------------------------------------------------
Config.BatCooldownSec = 1.2
Config.BatRange = 6
Config.BatMinFacingDot = 0.35 -- cos of the max angle between look direction and target
Config.BatKnockbackSpeed = 55
Config.BatKnockbackLift = 22
Config.BatStunSec = 0.75
Config.BananaSlipSpeed = 30
Config.BananaStunSec = 1

---------------------------------------------------------------------------
-- Traps
---------------------------------------------------------------------------
Config.MaxTraps = 5
Config.TrapRearmSec = 20
Config.TrapTriggerSize = 4.5 -- studs, square trigger around each trap
Config.HonkHighlightSec = 8
Config.StickySlowSec = 3
Config.StickyWalkSpeed = 6
Config.TrapPrices = {
	BananaPeel = 1500,
	StickyFloor = 2500,
	HonkEgg = 4000,
}

---------------------------------------------------------------------------
-- Fusion
---------------------------------------------------------------------------
Config.FusionTimeSec = 60
Config.FusionBonus = 1.25 -- a fallback hybrid earns (a + b) x this
Config.FusionRecipeBonus = 1.6 -- a named recipe hybrid earns (a + b) x this
Config.FusionMachineRange = 16 -- studs: how close you must be to use your machine
Config.DiscoveryStoreName = "HatchAndSnatch_FirstDiscoveries_v1" -- global first discoveries
Config.DiscoveryTopic = "FirstDiscovery" -- MessagingService topic for cross-server banners

---------------------------------------------------------------------------
-- Weather mutations
---------------------------------------------------------------------------
Config.WeatherMinGapSec = 240 -- quiet time between two weather events
Config.WeatherMaxGapSec = 480
Config.WeatherMinLengthSec = 60
Config.WeatherMaxLengthSec = 90
Config.WeatherTickSec = 3 -- how often growing creatures roll for a mutation during an event
-- Each event: how often it is picked (weight), the mutation it gives, and the chance per
-- tick that one growing creature gets it. Over a 75 s event that is about 1 - (1 - chance)^25.
Config.WeatherEvents = {
	GoldenRain = { mutation = "Golden", weight = 4, chance = 0.015 },
	LightningStorm = { mutation = "Electric", weight = 3, chance = 0.01 },
	Frost = { mutation = "Frozen", weight = 4, chance = 0.02 },
	Rainbow = { mutation = "Rainbow", weight = 1, chance = 0.004 },
}
Config.MutationMultipliers = {
	Golden = 2,
	Electric = 3,
	Frozen = 1.5,
	Rainbow = 5,
}

---------------------------------------------------------------------------
-- Arena
---------------------------------------------------------------------------
Config.ArenaTeamSize = 3
Config.ArenaWinTrophies = 10 -- for beating another player (losing never costs trophies)
Config.ArenaBotWinTrophies = 7 -- for beating a bot
Config.ArenaQueueWaitSec = 6 -- wait this long for a real opponent before a bot steps in
Config.ArenaCooldownSec = 15 -- between two battles of the same player
Config.ArenaMatchRange = 150 -- real opponents must be within this many trophies of each other
Config.ArenaMaxRounds = 25 -- after this the side with more health left wins
Config.ArenaBaseStats = { hp = 100, attack = 14, speed = 10 } -- a Common creature
Config.ArenaTierGrowth = 1.35 -- each rarity tier above Common multiplies HP and attack by this
Config.ArenaSpeedPerTier = 1
Config.ArenaDamageSpread = 0.15 -- each hit does 85%..115% of the attack stat
Config.ArenaMutationBonus = {
	Golden = { hp = 1.15, attack = 1.0, speed = 1.0 },
	Electric = { hp = 1.0, attack = 1.1, speed = 1.2 },
	Frozen = { hp = 1.25, attack = 1.0, speed = 0.9 },
	Rainbow = { hp = 1.15, attack = 1.15, speed = 1.1 },
}
-- Bots copy your team's tiers and scale their stats by min + trophies x perTrophy (up to max),
-- +-jitter. Battles swing hard on small stat gaps: 0.96 wins you ~70%, 1.0 ~50%, 1.02 ~40%.
Config.ArenaBotStrength = { min = 0.96, max = 1.02, perTrophy = 1 / 20000, jitter = 0.08 }
-- One special ability per fusion tag. kind: stun / dodge / shield / crit / heal / splash /
-- burn / first / team / rage / revive / lifesteal / thorns. `value` is a chance or a fraction.
Config.ArenaAbilities = {
	slime = { name = "Sticky Slime", kind = "stun", value = 0.15 },
	cute = { name = "Too Cute", kind = "dodge", value = 0.2 },
	rock = { name = "Stone Skin", kind = "shield", value = 0.2 },
	pup = { name = "Loyal Bite", kind = "crit", value = 0.2 },
	plant = { name = "Photosynthesis", kind = "heal", value = 0.08, every = 2 },
	shell = { name = "Shell Up", kind = "shield", value = 0.25 },
	bug = { name = "Swarm", kind = "splash", value = 0.3 },
	fluffy = { name = "Fluff Cushion", kind = "thorns", value = 0.15 },
	sweet = { name = "Sugar Rush", kind = "first", value = 4 },
	bird = { name = "Swoop", kind = "dodge", value = 0.15 },
	water = { name = "Splash", kind = "splash", value = 0.25 },
	fizzy = { name = "Fizz Pop", kind = "stun", value = 0.1 },
	paper = { name = "Paper Cut", kind = "crit", value = 0.25 },
	fungus = { name = "Spore Cloud", kind = "burn", value = 0.3 },
	glow = { name = "Dazzle", kind = "dodge", value = 0.15 },
	food = { name = "Snack Break", kind = "heal", value = 0.1, every = 3 },
	storm = { name = "Thunderclap", kind = "stun", value = 0.2 },
	armor = { name = "Plate Armor", kind = "shield", value = 0.3 },
	party = { name = "Hype", kind = "team", value = 0.1 },
	fire = { name = "Scorch", kind = "burn", value = 0.4 },
	dino = { name = "Stomp", kind = "splash", value = 0.35 },
	space = { name = "Zero-G", kind = "dodge", value = 0.2 },
	dragon = { name = "Dragon Fury", kind = "rage", value = 0.4 },
	glitch = { name = "Lag Spike", kind = "stun", value = 0.25 },
	furniture = { name = "Comfy", kind = "revive", value = 1 },
}
Config.ArenaCaps = { dodge = 0.45, shield = 0.6, stun = 0.4 } -- stacking limits
-- Arena ranks unlock arena-only cosmetics: an overhead title and a trophy in your base.
Config.ArenaRanks = {
	{ name = "Bronze", trophies = 50, title = "Bronze Brawler", icon = "🥉" },
	{ name = "Silver", trophies = 150, title = "Silver Slugger", icon = "🥈" },
	{ name = "Gold", trophies = 400, title = "Gold Gladiator", icon = "🥇" },
	{ name = "Diamond", trophies = 1000, title = "Diamond Champion", icon = "💎" },
}
Config.LeaderboardStoreName = "HatchAndSnatch_Trophies_v1" -- OrderedDataStore
Config.LeaderboardRefreshSec = 120
Config.LeaderboardSize = 10
Config.LeaderboardWriteSec = 60 -- write a player's trophies at most this often

---------------------------------------------------------------------------
-- Monetization. Create the passes and products on the Roblox website (Creator
-- Dashboard) and paste their ids here; an id of 0 shows "coming soon" in the Shop.
-- Rules: nothing random for Robux, no advantage in raids or the arena, no pressure.
---------------------------------------------------------------------------
Config.GamePasses = {
	DoubleIncome = {
		id = 0,
		name = "2x Income",
		icon = "💰",
		description = "Every creature earns twice as many coins, even while you're offline.",
	},
	ExtraPedestals = {
		id = 0,
		name = "+6 Pedestals",
		icon = "🏛️",
		description = "Unlocks 6 more pedestals for free right away (a base holds 24).",
	},
	VipBase = {
		id = 0,
		name = "VIP Base",
		icon = "👑",
		description = "A golden VIP look for your base: crown, gold trim and a red carpet. Looks only.",
	},
	FastFusion = {
		id = 0,
		name = "Faster Fusion",
		icon = "⚡",
		description = "Your Fusion Machine works twice as fast.",
	},
}
Config.PassIncomeMultiplier = 2
Config.PassBonusPedestals = 6
Config.PassFusionSpeed = 0.5 -- fusion time multiplier with Faster Fusion

-- Coin packs give minutes of your current income (at least `minimum`), so they stay
-- useful at every stage. The exact amount is shown before buying.
Config.DevProducts = {
	CoinsSmall = { id = 0, kind = "coins", name = "Coin Pouch", icon = "🪙", minutes = 15, minimum = 2500 },
	CoinsMedium = { id = 0, kind = "coins", name = "Coin Sack", icon = "💰", minutes = 60, minimum = 10000 },
	CoinsLarge = { id = 0, kind = "coins", name = "Coin Vault", icon = "🏦", minutes = 240, minimum = 50000 },
	GrowToken = {
		id = 0,
		kind = "growToken",
		name = "Instant Grow",
		icon = "🌱",
		description = "Grow one egg or baby into an adult right away.",
	},
	BatGolden = { id = 0, kind = "batSkin", skin = "Golden", name = "Golden Bat", icon = "🏆" },
	BatCandy = { id = 0, kind = "batSkin", skin = "Candy", name = "Candy Bat", icon = "🍭" },
	BatGalaxy = { id = 0, kind = "batSkin", skin = "Galaxy", name = "Galaxy Bat", icon = "🌌" },
}
Config.ReceiptHistorySize = 50 -- purchase ids remembered per player (idempotent receipts)

---------------------------------------------------------------------------
-- Data & networking
---------------------------------------------------------------------------
Config.AutoSaveSec = 120
Config.DataSchemaVersion = 1
Config.DataStoreName = "HatchAndSnatch_PlayerData_v1"
Config.OfflinePopupMinSec = 60 -- don't show the offline popup for shorter absences

-- Token-bucket rate limits per remote, per player. `rate` refills per second, `burst` is the bucket size.
Config.DefaultRateLimit = { rate = 4, burst = 8 }
Config.RateLimits = {
	ClientReady = { rate = 0.2, burst = 2 },
	BuyEgg = { rate = 3, burst = 4 },
	SellCreature = { rate = 2, burst = 3 },
	UnlockPedestal = { rate = 1, burst = 2 },
	CollectPad = { rate = 2, burst = 3 },
	Steal = { rate = 1, burst = 2 },
	BatSwing = { rate = 3, burst = 3 },
	SetLocked = { rate = 2, burst = 4 },
	SaveSettings = { rate = 1, burst = 3 },
	GetProfile = { rate = 2, burst = 4 },
	TutorialAck = { rate = 0.5, burst = 2 },
	BuyTrap = { rate = 1, burst = 3 },
	StartFusion = { rate = 0.5, burst = 2 },
	FusionPrompt = { rate = 1, burst = 2 },
	FindMatch = { rate = 0.5, burst = 2 },
	CancelMatch = { rate = 1, burst = 3 },
	GetLeaderboard = { rate = 0.5, burst = 3 },
	UseGrowToken = { rate = 1, burst = 2 },
	EquipBatSkin = { rate = 1, burst = 3 },
}

---------------------------------------------------------------------------
-- Map layout (studs). Changing these reshapes the procedural placeholder map.
---------------------------------------------------------------------------
Config.Map = {
	GroundSize = 520,
	LobbyRadius = 52,
	BaseRingRadius = 136,
	BaseSize = 68, -- square plot edge length
	BaseWallHeight = 7,
	BaseBarrierHeight = 48, -- invisible wall height so nobody can jump over walls
	EntranceWidth = 14,
	EntranceHeight = 13,
	PedestalColumns = 6,
	PedestalRows = 4,
	PedestalSpacing = 9,
	PedestalDiameter = 6,
	ConveyorLength = 64,
	ConveyorWidth = 7,
	ConveyorHeight = 3.2, -- belt surface height above the plaza
}

---------------------------------------------------------------------------
-- Sounds. Built-in Roblox placeholder sounds; swap the ids for your own uploads.
---------------------------------------------------------------------------
Config.Sounds = {
	Click = { id = "rbxasset://sounds/clickfast.wav", volume = 0.5, pitch = 1 },
	Buy = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, pitch = 1 },
	Hatch = { id = "rbxasset://sounds/snap.wav", volume = 0.8, pitch = 1.1 },
	GrowUp = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, pitch = 0.8 },
	Collect = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 1.35 },
	Steal = { id = "rbxasset://sounds/swoosh.wav", volume = 0.8, pitch = 1 },
	Theft = { id = "rbxasset://sounds/unsheath.wav", volume = 0.6, pitch = 1 },
	Bonk = { id = "rbxasset://sounds/swordslash.wav", volume = 0.8, pitch = 0.9 },
	Slip = { id = "rbxasset://sounds/splat.wav", volume = 0.8, pitch = 1 },
	Honk = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 1, pitch = 0.45 },
	Night = { id = "rbxasset://sounds/unsheath.wav", volume = 0.5, pitch = 0.7 },
	Day = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.4, pitch = 1.1 },
	Discovery = { id = "rbxasset://sounds/victory.wav", volume = 0.7, pitch = 1 },
	Weather = { id = "rbxasset://sounds/victory.wav", volume = 0.5, pitch = 0.75 },
	Thunder = { id = "rbxasset://sounds/collide.wav", volume = 0.9, pitch = 0.35 },
	Mutate = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.7, pitch = 1.5 },
	Warning = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 0.7 },
}

---------------------------------------------------------------------------
-- Development toggles (turn these off before publishing)
---------------------------------------------------------------------------
Config.Debug = {
	ShowCreatureGallery = true, -- a showroom of every creature model in the lobby
	StartAtNight = false, -- start the server at night (handy for testing raids)
	FastWeather = false, -- weather every 30-45 s, first one after 15 s (testing mutations)
}

local function deepFreeze(t: { [any]: any })
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			deepFreeze(value)
		end
	end
	table.freeze(t)
end

deepFreeze(Config)

return Config
