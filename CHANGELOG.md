# Changelog

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
