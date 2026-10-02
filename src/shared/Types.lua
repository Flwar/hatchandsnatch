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

export type PlayerData = {
	version: number,
	coins: number,
	padCoins: number, -- income waiting on the collect pad
	pedestals: number,
	creatures: { CreatureRecord },
	traps: { string },
	discoveries: { [string]: boolean },
	trophies: number,
	totalPlaytime: number, -- seconds
	lastLogout: number, -- os.time(), 0 if never
	receipts: { [string]: boolean }, -- processed purchase ids
	funnel: { [string]: boolean }, -- analytics milestones already logged
}

return {}
