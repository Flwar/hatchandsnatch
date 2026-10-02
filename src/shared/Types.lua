--!strict
--[[
	Types
	Shared data shapes. PlayerData is the saved profile (see server DataService);
	the client receives the parts it needs through attributes and remotes.
]]

export type Mutation = "Golden" | "Electric" | "Frozen" | "Rainbow"

export type CreatureRecord = {
	uid: string, -- unique per creature instance
	id: string, -- CreatureData id
	plantedAt: number, -- os.time() when placed; growth is computed from this
	mutation: Mutation?,
	locked: boolean, -- locked creatures cannot be stolen
	slot: number, -- pedestal slot in the owner's base
}

-- A fusion running in a player's machine. The parents' records stay here until the
-- hybrid is placed, so nothing is lost if the player leaves or the server stops.
export type FusionJob = {
	parents: { CreatureRecord },
	resultId: string,
	mutation: Mutation?, -- kept only when both parents had the same mutation
	endsAt: number, -- os.time() when the hybrid is done
}

export type TrapRecord = {
	trapType: string, -- "BananaPeel" | "StickyFloor" | "HonkEgg"
	spot: number, -- trap spot index in the base
}

export type PlayerData = {
	version: number,
	coins: number,
	padCoins: number, -- income waiting on the collect pad
	pedestals: number,
	creatures: { CreatureRecord },
	traps: { TrapRecord },
	hasStolen: boolean, -- stealing ends your new-player protection
	discoveries: { [string]: boolean },
	trophies: number,
	totalPlaytime: number, -- seconds
	lastLogout: number, -- os.time(), 0 if never
	receipts: { [string]: boolean }, -- processed purchase ids
	funnel: { [string]: boolean }, -- analytics milestones already logged
	settings: Settings,
	tutorialStep: number, -- 1..4 while the tutorial runs, 5 once it is done
	fusion: FusionJob?, -- the fusion running in this player's machine, if any
	arenaWins: number,
	arenaBattles: number,
}

export type Settings = {
	sfx: boolean,
	labels: boolean, -- floating creature labels
}

-- What the client asks for when opening menus (see DataService GetProfile).
export type ProfileSummary = {
	discoveries: { string },
	trophies: number,
	settings: Settings,
	pedestals: number,
	traps: { TrapRecord },
	firsts: { [string]: string }, -- named recipe id -> who discovered it first (known so far)
	arenaWins: number,
	arenaBattles: number,
}

-- One row of the arena leaderboard, and what the Arena window asks for.
export type LeaderboardEntry = { rank: number, userId: number, name: string, trophies: number }

export type LeaderboardSummary = {
	top: { LeaderboardEntry },
	trophies: number,
	rank: number?, -- your place on the board, if you are on it
}

return {}
