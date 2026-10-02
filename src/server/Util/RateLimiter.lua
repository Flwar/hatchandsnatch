--!strict
--[[
	RateLimiter
	Token-bucket rate limiting per player and per key (usually a remote name).
	Limits come from Config.RateLimits, falling back to Config.DefaultRateLimit.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

type Bucket = { tokens: number, updated: number }

local RateLimiter = {}

local buckets: { [Player]: { [string]: Bucket } } = {}

local function limitFor(key: string): { rate: number, burst: number }
	local limits = Config.RateLimits :: { [string]: { rate: number, burst: number } }
	return limits[key] or Config.DefaultRateLimit
end

-- Returns true and spends a token if `player` may perform `key` now.
function RateLimiter.allow(player: Player, key: string): boolean
	local limit = limitFor(key)
	local now = os.clock()
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local bucket = perPlayer[key]
	if not bucket then
		bucket = { tokens = limit.burst, updated = now }
		perPlayer[key] = bucket
	end
	bucket.tokens = math.min(limit.burst, bucket.tokens + (now - bucket.updated) * limit.rate)
	bucket.updated = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

Players.PlayerRemoving:Connect(function(player: Player)
	buckets[player] = nil
end)

return table.freeze(RateLimiter)
