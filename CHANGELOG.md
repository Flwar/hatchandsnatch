# Changelog

## [0.5.0] - Milestone 4: UI and onboarding

### Added
- Menu buttons down the left edge (Shop, Inventory, Index, Settings), at least 44 px on phones.
  One window is open at a time (`Window`), built from shared touch-sized `Widgets`.
- Shop:
  - Eggs tab: the odds for each rarity. Eggs are still bought on the conveyor, where you
    always see what is inside.
  - Base tab: unlock the next pedestal through the new `BuyPedestal` remote, which uses the
    same server code as the in-world Unlock prompt (`BaseService.buyPedestal`).
  - Traps tab: buy traps, with what each one does.
- Inventory: every creature in your base with a 3D preview, slot, stage, income and sell price. Lock one
  creature, or sell any of them after a confirmation popup. Selling uses the validated
  `SellCreature` remote and `CreatureService.sell`, which share the checks with the F prompt.
- Index: all 21 creatures. Ones you have owned are in full color; the rest are silhouettes.
  It has a hook (`Index.extraEntries`) for the hybrids coming in Milestone 5.
- Settings: sound effects and creature labels on or off. They are saved to your profile
  through the rate-limited `SaveSettings` remote, and labels hide or show instantly.
- Sounds (`Config.Sounds`, `SoundController`): buying, hatching, growing up, collecting,
  stealing, thefts, bonks, traps, nightfall and sunrise. They play only on your own client,
  and 3D sounds play where the event happened. The ids are built-in placeholders until you
  upload your own.
- Tutorial (`TutorialService` and `TutorialController`): buy an egg, watch it hatch, collect
  coins, then a short note about night raids. The server advances each step when you
  actually do it, and the step is saved. The client shows a hint card, a spinning arrow over
  the target and a guide beam. Returning players who already own creatures skip ahead.
- `GetProfile` remote for menus: discoveries, pedestals, traps and settings.
- Save data: `settings` and `tutorialStep`, repaired by the migration. Tests cover both.

## [0.4.0] - Milestone 3: night and PvP

### Added
- Day/night cycle (`CycleService`): Day `Config.DayLengthSec`, Night `Config.NightLengthSec`,
  published as Workspace attributes. Each client tweens its own Lighting (clock, brightness,
  ambient, Atmosphere, ColorCorrection) and shows "Night in 2:31" / "Sunrise in 0:45".
  `Config.Debug.StartAtNight` starts the server at night for testing.
- Shields: open at night and closed by day. A shield is solid only on each player's own
  machine, decided by the same rules as the server (`ShieldController`). The server checks
  base zones every `Config.ZoneCheckSec` and teleports out anyone who isn't allowed inside,
  which also stops noclip exploits. Everyone left in a base gets swept out at sunrise.
- Raids (`RaidService`):
  - "Steal" prompts on adult creatures. Carried creatures sit over the raider's head and
    slow them to `Config.CarryWalkSpeed`.
  - A stolen creature becomes the raider's only once they reach a free pedestal in their
    own base. The whole server sees a theft banner.
  - A dropped creature walks home on its own. Sunrise, leaving or dying returns anything
    still being carried.
- Fairness rules (`RaidRules`, shared by server and client):
  - new-player shield: 60 minutes of playtime, or a base worth more than
    `Config.NewPlayerShieldValue`;
  - value bracket (0.33x to 3x);
  - lock one creature with an owner-only Lock prompt;
  - revenge window: by day, ignoring the bracket, with a 🎯 marker over the thief;
  - steal cooldown.
  - New: stealing ends your own new-player protection, so it can't be used as cover.
- Bonk bat (`CombatService`): a StarterPack tool. Swings send no arguments, so the server
  picks the target: the closest player in range and in front of you, at night, inside a
  base. A hit causes knockback plus a `Config.BatStunSec` stun, with the server briefly
  owning the target's physics, and makes carriers drop what they carry. It never does damage.
- Traps (`TrapService`, `TrapModels`): Banana Peel (slip, stun and drop), Sticky Floor (slow)
  and Honk Egg (warns the owner and highlights the raider). Up to `Config.MaxTraps` per base,
  on trap spots along the entrance. They re-arm after `Config.TrapRearmSec` and are bought
  through the validated `BuyTrap` remote.
- `Speed` helper: several slow-downs can stack, and the slowest one always wins.
- Effects: "BONK!", "SLIP!", "SPLAT!" and "HONK!" pop-ups with sparkle bursts.
- Tests for every fairness rule, trap models and trap spots.

## [0.3.0] - Milestone 2: persistence

### Added
- Saving with [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore), vendored in
  `src/server/Packages`, Apache-2.0 (see `licenses/`). Sessions are locked so the same profile
  is never open on two servers. Data saves on leave, autosaves every `Config.AutoSaveSec`
  through the shared Ticker, and is saved by ProfileStore on server shutdown. If loading
  fails, the player is kicked with a friendly message instead of playing on unsaved data.
- `DataSchema`: the template, plus a migration that upgrades older saves, converts numeric
  strings, repairs NaN and bad values, and drops malformed creature records.
- Offline progress: growth simply continues, because it is computed from timestamps. Income
  counts only the time after each creature became an adult, capped at
  `Config.OfflineIncomeCapHours`. A "While you were away" popup shows the payout once the
  client is ready.
- Client UI kit: `Popup` (queued modal dialogs with big touch-friendly buttons) and `Banner`
  (queued slide-in announcements, used by later milestones).
- Tests for offline earnings (adult-only time, cap, multipliers, clock skew) and migration.

## [0.2.0] - Milestone 1: core loop

### Added
- Egg conveyor (`ConveyorService`): a new egg every `Config.ConveyorSpawnInterval` seconds,
  rolled with the weighted rarity odds. Eggs glide smoothly down the belt, carried by
  server-owned physics. They collide with nothing, so players can't shove them, and drop into
  the egg hole at the end. Each egg shows its creature, rarity and price.
- Buying with a ProximityPrompt. The server checks that the egg is still on the belt, the
  player is close, owns a base, has a free pedestal and can afford it. It then charges the
  price, which always comes from `CreatureData`, and places the egg on the first free pedestal.
- Creatures on pedestals (`CreatureService`): data records and world models stay in sync. Each
  creature has an owner-only hold-to-sell prompt that refunds `Config.SellRefundFraction` of the
  egg price.
- Growth (`GrowthService` + shared `Growth`): Egg, then Baby at 30%, then Adult at 100% of
  `growTimeSec`, always computed from the `plantedAt` timestamp. Hatching and growing up swap
  the model and notify the owner.
- Income (`IncomeService`): adults fill the owner's collect pad on one server-wide tick. Stepping
  on your own pad collects it. The pad shows its pending total, and the HUD shows coins per
  second.
- Pedestal unlocking: an owner-only "Unlock" prompt on the next locked pedestal. Each unlock
  costs `Config.PedestalCostGrowth` times more than the last.
- `Ticker`: the server's single heartbeat. Every periodic system registers with it instead of
  running its own loop.
- Client visuals: floating creature labels (hatch and grow countdowns on the server clock,
  income per second), idle bob and sway, eggs that rock harder just before hatching, and a
  sparkle burst with a hop on place, hatch and grow-up. Egg prices turn red when you can't
  afford them.
- Tests: growth stages and offline growth, economy formulas, and a core-loop simulation using
  the real config and data. A fresh player reaches a Rare in a median of 6:20 (worst 8:00 over
  60 runs).

## [0.1.0] - Milestone 0: project setup

### Added
- Rojo project (`default.project.json`) that maps `src/shared`, `src/server` and `src/client`, and
  sets the base Lighting look (Atmosphere, Bloom, ColorCorrection, SunRays), turns
  `StreamingEnabled` off and turns `CharacterAutoLoads` off.
- `Config` with every tunable number for all planned systems, deep-frozen.
- `Remotes` registry plus server-side `Net` (per-player token-bucket rate limiting, exact
  argument-count checks, typed `Guard` validators, `xpcall`-wrapped handlers).
- Server bootstrap with ordered `init`/`start`, plus three services:
  - `DataService`: data template, schema version, migration, safe coin helpers, the `Coins`
    attribute and leaderstats. In-memory for now; ProfileStore arrives in Milestone 2.
  - `MapService`: builds the procedural map, or uses a hand-built `Workspace.Map`.
  - `BaseService`: assigns a free base when a player's data loads, frees it when they leave, and
    queues players when the server is full. Handles spawning at the base, the owner sign,
    pedestal unlock visuals, collision groups that let only the owner through their shield, and
    respawns.
- Procedural map: lobby plaza, egg conveyor with egg machine and egg hole, title arch, 8 colored
  bases in a ring (walls, invisible anti-jump barriers, entrance arch and sign, force-field
  shield, spawn, collect pad, 24 pedestals with sockets and locked states), paths and scenery.
- 21 original creatures (3 per rarity tier) in `CreatureData`, each with a hand-built model for
  Egg, Baby (in a hatched eggshell) and Adult in `CreatureModels`. The models use
  part-built faces (bean, googly, sleepy and pixel eyes; smile, open, O and flat mouths;
  cheeks), and every creature has its own palette, ready for mutations later.
- Client: HUD (short-formatted coin counter with pop animation, base number, toast
  notifications), a "YOUR BASE" marker visible only to its owner, and a dev creature showroom in
  the lobby (`Config.Debug.ShowCreatureGallery`).
- Tooling: Lune test suite (`tests/run.luau`), a model preview renderer (`tools/preview`),
  `tools/check.sh`, and `rokit.toml`.
