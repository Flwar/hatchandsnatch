--!strict
--[[
	Ticker
	The server's single heartbeat. Systems register repeating jobs with Ticker.every
	instead of running their own loops, so all periodic work (income, growth,
	conveyor clean-up) shares one RunService.Heartbeat connection.
]]

local RunService = game:GetService("RunService")

type Job = {
	name: string,
	interval: number,
	elapsed: number,
	callback: (dt: number) -> (),
}

local Ticker = {}

local jobs: { Job } = {}
local connection: RBXScriptConnection? = nil

local function step(dt: number)
	for _, job in jobs do
		job.elapsed += dt
		if job.elapsed >= job.interval then
			local elapsed = job.elapsed
			job.elapsed = 0
			-- Each job is isolated so one failing system cannot stop the others.
			xpcall(job.callback, function(err: any)
				warn(`[Ticker] {job.name} failed: {err}\n{debug.traceback()}`)
			end, elapsed)
		end
	end
end

-- Calls `callback(elapsedSeconds)` roughly every `interval` seconds.
function Ticker.every(name: string, interval: number, callback: (dt: number) -> ())
	assert(interval > 0, "Ticker.every needs a positive interval")
	table.insert(jobs, { name = name, interval = interval, elapsed = 0, callback = callback })
	if not connection then
		connection = RunService.Heartbeat:Connect(step)
	end
end

return table.freeze(Ticker)
