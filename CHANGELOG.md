# Changelog

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
