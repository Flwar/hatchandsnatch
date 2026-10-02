--!strict
--[[
	Format
	Number and time formatting for the UI: short coin numbers (1.2K, 3.4M, 5.6B),
	countdown timers (2:31) and thousands separators.
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 999 -> "999", 1234 -> "1.2K", 12345 -> "12.3K", 123456 -> "123K", 3.4e6 -> "3.4M".
function Format.short(value: number): string
	if value ~= value then
		return "0"
	end
	local sign = if value < 0 then "-" else ""
	local n = math.abs(value)
	if n < 1000 then
		if n == math.floor(n) or n >= 100 then
			return sign .. tostring(math.floor(n))
		end
		return sign .. string.format("%.1f", math.floor(n * 10) / 10):gsub("%.0$", "")
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	local text: string
	if scaled >= 100 then
		text = tostring(math.floor(scaled))
	else
		-- Truncate (never round up) so 999.96K does not show as "1000K".
		text = string.format("%.1f", math.floor(scaled * 10) / 10):gsub("%.0$", "")
	end
	return sign .. text .. SUFFIXES[tier + 1]
end

-- 151 -> "2:31", 3725 -> "1:02:05".
function Format.clock(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local h = total // 3600
	local m = (total % 3600) // 60
	local s = total % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- 1234567 -> "1,234,567".
function Format.commas(value: number): string
	local text = tostring(math.floor(math.abs(value)))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return (if value < 0 then "-" else "") .. formatted
end

return table.freeze(Format)
