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
Config.FusionBonus = 1.25

---------------------------------------------------------------------------
-- Weather mutations
---------------------------------------------------------------------------
Config.WeatherMinGapSec = 240
Config.WeatherMaxGapSec = 480
Config.WeatherMinLengthSec = 60
Config.WeatherMaxLengthSec = 90
Config.MutationChancePerTick = 0.02
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
Config.ArenaWinTrophies = 10

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
	Warning = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 0.7 },
}

---------------------------------------------------------------------------
-- Development toggles (turn these off before publishing)
---------------------------------------------------------------------------
Config.Debug = {
	ShowCreatureGallery = true, -- a showroom of every creature model in the lobby
	StartAtNight = false, -- start the server at night (handy for testing raids)
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
