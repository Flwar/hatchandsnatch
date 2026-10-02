--!strict
--[[
	ArenaBattle
	A deterministic auto-battle between two teams of up to Config.ArenaTeamSize
	creatures. The server runs it in one go and sends the event log to the players'
	clients, which play it back; the same seed always gives the same battle.

	Each round every fighter still standing acts once, fastest first:
	  * burns tick, stunned fighters lose their turn, healers heal on their beat
	  * otherwise it attacks the front enemy: spread, crits, dodges, shields, then
	    on-hit effects (splash, burn, stun, lifesteal, thorns)
	  * Comfy (revive) survives one knockout with 1 HP; Dragon Fury hits harder
	    below half HP; Hype buffs the whole team's attack at the start
	After Config.ArenaMaxRounds the side with more health left (as a share) wins.
]]

local Config = require(script.Parent.Config)
local ArenaStats = require(script.Parent.ArenaStats)

export type Side = "A" | "B"

export type FighterSpec = { id: string, mutation: string?, scale: number? }

export type FighterInfo = {
	key: string, -- "A1", "B2", ...
	side: Side,
	slot: number,
	id: string,
	name: string,
	mutation: string?,
	maxHp: number,
	attack: number,
	speed: number,
	abilities: { string },
}

export type Event = {
	kind: string, -- "buff" | "attack" | "heal" | "burn" | "stunned" | "revive" | "faint" | "thorns"
	actor: string,
	target: string?,
	amount: number?,
	hp: number?, -- the target's (or actor's) health after this event
	crit: boolean?,
	dodged: boolean?,
	ability: string?, -- the ability that caused or changed this event
}

export type Result = {
	winner: Side,
	rounds: number,
	fighters: { FighterInfo },
	events: { Event },
}

-- What the server sends a player to play back (BattleStarted).
export type Report = {
	side: string, -- which side is you ("A" or "B")
	opponent: string,
	bot: boolean,
	winner: string,
	fighters: { FighterInfo },
	events: { Event },
	gained: number, -- trophies won (0 on a loss: losing never costs trophies)
	trophies: number, -- your total after the battle
	rankUp: boolean,
}

type Fighter = FighterInfo & {
	hp: number,
	alive: boolean,
	turns: number,
	stunned: boolean,
	burn: number, -- damage per turn
	burnTurns: number,
	revived: boolean,
	attackBonus: number,
	dodge: number,
	shield: number,
	crit: number,
	stun: number,
	splash: number,
	burnPower: number,
	lifesteal: number,
	thorns: number,
	rage: number,
	revive: boolean,
	heals: { { name: string, value: number, every: number } },
	teamBuffs: { { name: string, value: number } }, -- Hype: buffs the whole team at the start
	names: { [string]: string }, -- ability kind -> display name (for event labels)
}

local ArenaBattle = {}

local function makeFighter(spec: FighterSpec, side: Side, slot: number): Fighter?
	local stats = ArenaStats.forCreature(spec.id, spec.mutation, spec.scale)
	if not stats then
		return nil
	end
	local caps = Config.ArenaCaps
	local fighter: Fighter = {
		key = `{side}{slot}`,
		side = side,
		slot = slot,
		id = stats.id,
		name = stats.name,
		mutation = stats.mutation,
		maxHp = stats.hp,
		attack = stats.attack,
		speed = stats.speed,
		abilities = {},
		hp = stats.hp,
		alive = true,
		turns = 0,
		stunned = false,
		burn = 0,
		burnTurns = 0,
		revived = false,
		attackBonus = 0,
		dodge = 0,
		shield = 0,
		crit = 0,
		stun = 0,
		splash = 0,
		burnPower = 0,
		lifesteal = 0,
		thorns = 0,
		rage = 0,
		revive = false,
		heals = {},
		teamBuffs = {},
		names = {},
	}
	for _, ability in stats.abilities do
		table.insert(fighter.abilities, ability.name)
		fighter.names[ability.kind] = ability.name
		local kind, value = ability.kind, ability.value
		if kind == "dodge" then
			fighter.dodge = math.min(fighter.dodge + value, caps.dodge)
		elseif kind == "shield" then
			fighter.shield = math.min(fighter.shield + value, caps.shield)
		elseif kind == "crit" then
			fighter.crit += value
		elseif kind == "stun" then
			fighter.stun = math.min(fighter.stun + value, caps.stun)
		elseif kind == "splash" then
			fighter.splash += value
		elseif kind == "burn" then
			fighter.burnPower += value
		elseif kind == "lifesteal" then
			fighter.lifesteal += value
		elseif kind == "thorns" then
			fighter.thorns += value
		elseif kind == "rage" then
			fighter.rage += value
		elseif kind == "revive" then
			fighter.revive = true
		elseif kind == "first" then
			fighter.speed += value
		elseif kind == "heal" then
			table.insert(fighter.heals, { name = ability.name, value = value, every = ability.every or 2 })
		elseif kind == "team" then
			table.insert(fighter.teamBuffs, { name = ability.name, value = value })
		end
	end
	return fighter
end

local function info(fighter: Fighter): FighterInfo
	return {
		key = fighter.key,
		side = fighter.side,
		slot = fighter.slot,
		id = fighter.id,
		name = fighter.name,
		mutation = fighter.mutation,
		maxHp = fighter.maxHp,
		attack = fighter.attack,
		speed = fighter.speed,
		abilities = fighter.abilities,
	}
end

local function frontEnemy(fighters: { Fighter }, side: Side): Fighter?
	local best: Fighter? = nil
	for _, fighter in fighters do
		if fighter.alive and fighter.side ~= side and (best == nil or fighter.slot < best.slot) then
			best = fighter
		end
	end
	return best
end

local function nextEnemy(fighters: { Fighter }, after: Fighter): Fighter?
	local best: Fighter? = nil
	for _, fighter in fighters do
		if
			fighter.alive
			and fighter.side == after.side
			and fighter ~= after
			and (best == nil or fighter.slot < best.slot)
		then
			best = fighter
		end
	end
	return best
end

local function sideAlive(fighters: { Fighter }, side: Side): boolean
	for _, fighter in fighters do
		if fighter.alive and fighter.side == side then
			return true
		end
	end
	return false
end

-- Takes `amount` damage; handles revive and fainting. Returns the damage actually dealt.
local function hurt(target: Fighter, amount: number, events: { Event }): number
	local dealt = math.max(1, math.floor(amount + 0.5))
	target.hp -= dealt
	if target.hp <= 0 then
		if target.revive and not target.revived then
			target.revived = true
			target.hp = 1
			table.insert(events, { kind = "revive", actor = target.key, hp = 1, ability = target.names.revive })
		else
			target.hp = 0
			target.alive = false
			table.insert(events, { kind = "faint", actor = target.key })
		end
	end
	return dealt
end

local function heal(fighter: Fighter, amount: number): number
	local before = fighter.hp
	fighter.hp = math.min(fighter.maxHp, fighter.hp + math.floor(amount + 0.5))
	return fighter.hp - before
end

local function act(actor: Fighter, fighters: { Fighter }, rng: Random, events: { Event })
	actor.turns += 1
	if actor.burnTurns > 0 then
		actor.burnTurns -= 1
		local dealt = math.max(1, math.floor(actor.burn + 0.5))
		actor.hp -= dealt
		table.insert(events, { kind = "burn", actor = actor.key, amount = dealt, hp = math.max(0, actor.hp) })
		if actor.hp <= 0 then
			actor.hp = 0
			actor.alive = false
			table.insert(events, { kind = "faint", actor = actor.key })
			return
		end
	end
	if actor.stunned then
		actor.stunned = false
		table.insert(events, { kind = "stunned", actor = actor.key })
		return
	end
	for _, healer in actor.heals do
		if actor.turns % healer.every == 0 and actor.hp < actor.maxHp then
			local healed = heal(actor, actor.maxHp * healer.value)
			if healed > 0 then
				table.insert(
					events,
					{ kind = "heal", actor = actor.key, amount = healed, hp = actor.hp, ability = healer.name }
				)
			end
		end
	end
	local target = frontEnemy(fighters, actor.side)
	if not target then
		return
	end
	-- Dodge first: a dodged attack does nothing else.
	if rng:NextNumber() < target.dodge then
		table.insert(events, {
			kind = "attack",
			actor = actor.key,
			target = target.key,
			amount = 0,
			hp = target.hp,
			dodged = true,
			ability = target.names.dodge,
		})
		return
	end
	local spread = Config.ArenaDamageSpread
	local power = actor.attack * (1 + actor.attackBonus) * (1 - spread + rng:NextNumber() * spread * 2)
	local ability: string? = nil
	if actor.rage > 0 and actor.hp < actor.maxHp / 2 then
		power *= 1 + actor.rage
		ability = actor.names.rage
	end
	local crit = rng:NextNumber() < actor.crit
	if crit then
		power *= 2
		ability = actor.names.crit
	end
	power *= 1 - target.shield
	local attackEvent: Event = {
		kind = "attack",
		actor = actor.key,
		target = target.key,
		amount = 0,
		crit = crit,
		ability = ability,
	}
	table.insert(events, attackEvent)
	local dealt = hurt(target, power, events)
	attackEvent.amount = dealt
	attackEvent.hp = target.hp
	if actor.lifesteal > 0 then
		heal(actor, dealt * actor.lifesteal)
	end
	if target.thorns > 0 and target.alive then
		local thornsEvent: Event = {
			kind = "thorns",
			actor = target.key,
			target = actor.key,
			ability = target.names.thorns,
		}
		table.insert(events, thornsEvent)
		thornsEvent.amount = hurt(actor, dealt * target.thorns, events)
		thornsEvent.hp = actor.hp
	end
	if target.alive then
		if actor.burnPower > 0 then
			target.burn = actor.attack * actor.burnPower
			target.burnTurns = 2
			attackEvent.ability = attackEvent.ability or actor.names.burn
		end
		if actor.stun > 0 and rng:NextNumber() < actor.stun then
			target.stunned = true
			attackEvent.ability = actor.names.stun
		end
	end
	if actor.splash > 0 then
		local second = nextEnemy(fighters, target)
		if second then
			local splashEvent: Event = {
				kind = "attack",
				actor = actor.key,
				target = second.key,
				ability = actor.names.splash,
			}
			table.insert(events, splashEvent)
			splashEvent.amount = hurt(second, dealt * actor.splash, events)
			splashEvent.hp = second.hp
		end
	end
end

-- Runs a whole battle. Teams are lists of fighter specs (front first).
function ArenaBattle.run(teamA: { FighterSpec }, teamB: { FighterSpec }, seed: number): Result
	local rng = Random.new(seed)
	local fighters: { Fighter } = {}
	local sides: { { side: Side, team: { FighterSpec } } } =
		{ { side = "A", team = teamA }, { side = "B", team = teamB } }
	for _, entry in sides do
		local side, team = entry.side, entry.team
		for slot, spec in team do
			if slot > Config.ArenaTeamSize then
				break
			end
			local fighter = makeFighter(spec, side :: Side, slot)
			if fighter then
				table.insert(fighters, fighter)
			end
		end
	end
	table.sort(fighters, function(a, b)
		return a.key < b.key
	end)
	local events: { Event } = {}
	-- Hype: team-wide attack buffs before the first round.
	for _, fighter in fighters do
		for _, buff in fighter.teamBuffs do
			for _, ally in fighters do
				if ally.side == fighter.side then
					ally.attackBonus += buff.value
				end
			end
			table.insert(events, { kind = "buff", actor = fighter.key, ability = buff.name })
		end
	end
	local rounds = 0
	while rounds < Config.ArenaMaxRounds and sideAlive(fighters, "A") and sideAlive(fighters, "B") do
		rounds += 1
		local order = {}
		for _, fighter in fighters do
			if fighter.alive then
				table.insert(order, { fighter = fighter, tie = rng:NextNumber() })
			end
		end
		table.sort(order, function(a, b)
			if a.fighter.speed ~= b.fighter.speed then
				return a.fighter.speed > b.fighter.speed
			end
			return a.tie < b.tie
		end)
		for _, entry in order do
			local actor = entry.fighter
			if actor.alive and sideAlive(fighters, "A") and sideAlive(fighters, "B") then
				act(actor, fighters, rng, events)
			end
		end
	end
	local winner: Side
	local aliveA, aliveB = sideAlive(fighters, "A"), sideAlive(fighters, "B")
	if aliveA ~= aliveB then
		winner = if aliveA then "A" else "B"
	else
		-- Out of rounds: more health left (as a share of the team's maximum) wins; A on a tie.
		local share = { A = 0, B = 0 }
		local total = { A = 0, B = 0 }
		for _, fighter in fighters do
			share[fighter.side] += fighter.hp
			total[fighter.side] += fighter.maxHp
		end
		local a = share.A / math.max(total.A, 1)
		local b = share.B / math.max(total.B, 1)
		winner = if b > a then "B" else "A"
	end
	local infos = {}
	for _, fighter in fighters do
		table.insert(infos, info(fighter))
	end
	return { winner = winner, rounds = rounds, fighters = infos, events = events }
end

return table.freeze(ArenaBattle)
