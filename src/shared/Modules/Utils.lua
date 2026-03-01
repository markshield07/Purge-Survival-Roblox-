--[[
	Utils.lua
	Shared utility functions for The Purge: Suburban Survival
]]

local Utils = {}

-- Weighted random selection from a table of { item, weight } pairs
function Utils.WeightedRandom(choices: { { item: any, weight: number } }): any
	local totalWeight = 0
	for _, choice in ipairs(choices) do
		totalWeight += choice.weight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, choice in ipairs(choices) do
		cumulative += choice.weight
		if roll <= cumulative then
			return choice.item
		end
	end

	return choices[#choices].item
end

-- Pick a random tier based on zone tier weights
function Utils.PickTier(tierWeights: { number }): string
	local tierNames = { "Common", "Uncommon", "Rare", "Epic" }
	local choices = {}
	for i, weight in ipairs(tierWeights) do
		if weight > 0 then
			table.insert(choices, { item = tierNames[i], weight = weight })
		end
	end
	return Utils.WeightedRandom(choices)
end

-- Shuffle an array in-place (Fisher-Yates)
function Utils.Shuffle(t: { any })
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

-- Clamp a value between min and max
function Utils.Clamp(value: number, min: number, max: number): number
	return math.max(min, math.min(max, value))
end

-- Lerp between two values
function Utils.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Get distance between two Vector3 positions
function Utils.Distance(a: Vector3, b: Vector3): number
	return (a - b).Magnitude
end

-- Get distance ignoring Y axis (horizontal only)
function Utils.HorizontalDistance(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Format time as MM:SS
function Utils.FormatTime(seconds: number): string
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%02d:%02d", mins, secs)
end

-- Format a number with comma separators (e.g., 1,234,567)
function Utils.FormatNumber(n: number): string
	local formatted = tostring(math.floor(n))
	local k
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then break end
	end
	return formatted
end

-- Deep copy a table
function Utils.DeepCopy(original)
	if type(original) ~= "table" then
		return original
	end
	local copy = {}
	for key, value in pairs(original) do
		copy[Utils.DeepCopy(key)] = Utils.DeepCopy(value)
	end
	return setmetatable(copy, getmetatable(original))
end

-- Merge two tables (second overrides first)
function Utils.Merge(base, override)
	local result = Utils.DeepCopy(base)
	for key, value in pairs(override) do
		result[key] = value
	end
	return result
end

-- Safe require with fallback
function Utils.SafeRequire(module)
	local success, result = pcall(require, module)
	if success then
		return result
	end
	warn("[Utils] Failed to require module:", tostring(module), result)
	return nil
end

-- Create a signal (simple event system for server-side modules)
function Utils.CreateSignal()
	local signal = {
		_listeners = {},
	}

	function signal:Connect(callback)
		local connection = { callback = callback, connected = true }
		table.insert(self._listeners, connection)

		return {
			Disconnect = function()
				connection.connected = false
				for i, listener in ipairs(signal._listeners) do
					if listener == connection then
						table.remove(signal._listeners, i)
						break
					end
				end
			end,
		}
	end

	function signal:Fire(...)
		for _, listener in ipairs(self._listeners) do
			if listener.connected then
				task.spawn(listener.callback, ...)
			end
		end
	end

	return signal
end

-- Rate limiter: returns true if action is allowed
function Utils.CreateRateLimiter(maxCalls: number, windowSeconds: number)
	local calls = {}

	return function(): boolean
		local now = tick()
		-- Remove expired calls
		local i = 1
		while i <= #calls do
			if now - calls[i] > windowSeconds then
				table.remove(calls, i)
			else
				i += 1
			end
		end
		-- Check limit
		if #calls >= maxCalls then
			return false
		end
		table.insert(calls, now)
		return true
	end
end

return Utils
