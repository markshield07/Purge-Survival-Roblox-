--[[
	NightEventService.server.lua
	Random night events (inspired by 99 Nights in the Forest).
	Each night has a chance to trigger a special event:
	  - Cultist Raid: cultists assault the campfire
	  - Meteor Shower: meteors crash nearby, spawn crabs
	  - Frog Invasion: wave of hostile frogs
	  - Alien Visit: UFO crashes with loot
	  - Blood Moon: enhanced enemy aggression
	  - Thunder Storm: lightning strikes, wet wood
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local Utils = require(Modules.Utils)

------------------------------------------------------------------------
-- Wait for Remotes
------------------------------------------------------------------------
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")

-- Create event-specific remotes
local NightEventStarted = Instance.new("RemoteEvent")
NightEventStarted.Name = "NightEventStarted"
NightEventStarted.Parent = Remotes

local NightEventEnded = Instance.new("RemoteEvent")
NightEventEnded.Name = "NightEventEnded"
NightEventEnded.Parent = Remotes

------------------------------------------------------------------------
-- Event State
------------------------------------------------------------------------
local EventState = {
	activeEvent = nil,     -- current event type or nil
	eventDay = 0,          -- day the event started
	eventData = {},        -- event-specific data
	checkedTonight = false, -- prevent double-checking per night
}

------------------------------------------------------------------------
-- Event Handlers
------------------------------------------------------------------------

local function StartCultistRaid()
	local playerCount = math.max(1, #Players:GetPlayers())

	-- Scale cultist count with day and player count
	local GetGameState = game.ServerStorage:FindFirstChild("GetGameState")
	local currentDay = 1
	if GetGameState then
		local gs = GetGameState:Invoke()
		currentDay = gs.currentDay or 1
	end

	local cultistCount = 3 + math.floor(currentDay / 5) + (playerCount - 1) * 2

	NotifyPlayers:FireAllClients(
		"CULTIST RAID! " .. cultistCount .. " cultists are attacking the campfire!",
		Color3.fromRGB(200, 0, 0)
	)

	-- Signal PurgeService to spawn cultist-type enemies near campfire
	local purgeSignal = game.ServerStorage:FindFirstChild("PurgeStartSignal")
	if purgeSignal then
		purgeSignal:Fire(0, {
			totalEnemies = cultistCount,
			duration = 90,
			hasFirearms = currentDay >= 10,
			hasExplosives = false,
			hasArmored = currentDay >= 20,
			hasBoss = currentDay >= 30,
			targetsPower = false,
			waveCount = math.ceil(cultistCount / 3),
			isCultistRaid = true,
		})
	end

	return { cultistCount = cultistCount }
end

local function StartMeteorShower()
	NotifyPlayers:FireAllClients(
		"THE SKY IS ON FIRE! Meteors are crashing nearby!",
		Color3.fromRGB(255, 100, 0)
	)

	-- Spawn meteor crater parts near campfire
	local GetCampfireState = game.ServerStorage:FindFirstChild("GetCampfireState")
	local campPos = Vector3.new(0, 0, 0)
	if GetCampfireState then
		local cs = GetCampfireState:Invoke()
		campPos = cs.position or Vector3.zero
	end

	local craterCount = math.random(3, 7)
	local craters = {}
	for i = 1, craterCount do
		local angle = math.random() * math.pi * 2
		local dist = 50 + math.random(0, 150)
		local pos = campPos + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)

		local crater = Instance.new("Part")
		crater.Name = "MeteorCrater_" .. i
		crater.Size = Vector3.new(8, 1, 8)
		crater.Position = pos + Vector3.new(0, 0.5, 0)
		crater.Anchored = true
		crater.Shape = Enum.PartType.Cylinder
		crater.Orientation = Vector3.new(0, 0, 90)
		crater.Material = Enum.Material.CrackedLava
		crater.BrickColor = BrickColor.new("Dark orange")
		crater.Parent = workspace

		-- Glow effect
		local light = Instance.new("PointLight")
		light.Brightness = 3
		light.Range = 15
		light.Color = Color3.fromRGB(255, 100, 0)
		light.Parent = crater

		-- Fire
		local fire = Instance.new("Fire")
		fire.Size = 5
		fire.Heat = 10
		fire.Parent = crater

		table.insert(craters, crater)

		-- Auto-cleanup after event
		task.delay(120, function()
			crater:Destroy()
		end)
	end

	return { craterCount = craterCount, craters = craters }
end

local function StartFrogInvasion()
	NotifyPlayers:FireAllClients(
		"FROG INVASION! The forest is overrun with hostile frogs!",
		Color3.fromRGB(0, 200, 0)
	)

	-- Spawn frog enemies near players outside safe zone
	local GetCampfireState = game.ServerStorage:FindFirstChild("GetCampfireState")
	local campPos = Vector3.new(0, 0, 0)
	if GetCampfireState then
		local cs = GetCampfireState:Invoke()
		campPos = cs.position or Vector3.zero
	end

	local frogCount = 5 + math.random(3, 8)

	-- Create frog parts
	for i = 1, frogCount do
		local angle = math.random() * math.pi * 2
		local dist = 30 + math.random(0, 80)
		local pos = campPos + Vector3.new(math.cos(angle) * dist, 1, math.sin(angle) * dist)

		local frog = Instance.new("Part")
		frog.Name = "HostileFrog_" .. i
		frog.Size = Vector3.new(2, 1.5, 2)
		frog.Position = pos
		frog.Anchored = false
		frog.Material = Enum.Material.SmoothPlastic
		frog.BrickColor = BrickColor.new("Bright green")
		frog.Shape = Enum.PartType.Ball
		frog.Parent = workspace

		-- Auto-cleanup
		task.delay(90, function()
			if frog.Parent then frog:Destroy() end
		end)
	end

	return { frogCount = frogCount }
end

local function StartAlienVisit()
	NotifyPlayers:FireAllClients(
		"Something mysterious is flying above you...",
		Color3.fromRGB(0, 255, 200)
	)

	local GetCampfireState = game.ServerStorage:FindFirstChild("GetCampfireState")
	local campPos = Vector3.new(0, 0, 0)
	if GetCampfireState then
		local cs = GetCampfireState:Invoke()
		campPos = cs.position or Vector3.zero
	end

	-- Spawn a crashed UFO part
	task.delay(5, function()
		NotifyPlayers:FireAllClients(
			"A UFO has crashed in the forest!",
			Color3.fromRGB(0, 255, 100)
		)

		local angle = math.random() * math.pi * 2
		local dist = 80 + math.random(0, 120)
		local pos = campPos + Vector3.new(math.cos(angle) * dist, 2, math.sin(angle) * dist)

		local ufo = Instance.new("Part")
		ufo.Name = "CrashedUFO"
		ufo.Size = Vector3.new(15, 3, 15)
		ufo.Position = pos
		ufo.Anchored = true
		ufo.Shape = Enum.PartType.Cylinder
		ufo.Orientation = Vector3.new(15, math.random(0, 360), 5)
		ufo.Material = Enum.Material.Metal
		ufo.BrickColor = BrickColor.new("Medium stone grey")
		ufo.Parent = workspace

		-- Green glow
		local light = Instance.new("PointLight")
		light.Brightness = 3
		light.Range = 30
		light.Color = Color3.fromRGB(0, 255, 100)
		light.Parent = ufo

		-- Sparkle
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(0, 255, 100)
		sparkles.Parent = ufo

		-- Auto-cleanup
		task.delay(180, function()
			if ufo.Parent then ufo:Destroy() end
		end)
	end)

	return {}
end

local function StartBloodMoon()
	NotifyPlayers:FireAllClients(
		"BLOOD MOON RISES... The creatures are restless tonight.",
		Color3.fromRGB(180, 0, 0)
	)

	-- Tint the lighting red
	local Lighting = game:GetService("Lighting")
	local originalAmbient = Lighting.Ambient
	Lighting.Ambient = Color3.fromRGB(80, 10, 10)
	Lighting.OutdoorAmbient = Color3.fromRGB(100, 20, 20)

	-- Create blood moon color correction
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "BloodMoon"
	cc.TintColor = Color3.fromRGB(255, 100, 100)
	cc.Saturation = 0.3
	cc.Parent = Lighting

	-- Restore after event
	task.delay(Config.DayCycle.DayLengthSeconds * 0.35, function()
		if cc.Parent then cc:Destroy() end
		Lighting.Ambient = originalAmbient
	end)

	return { enhanced = true }
end

local function StartThunderStorm()
	NotifyPlayers:FireAllClients(
		"A violent thunderstorm rolls in!",
		Color3.fromRGB(100, 100, 200)
	)

	-- Create storm atmosphere
	local Lighting = game:GetService("Lighting")
	local atmosphere = Lighting:FindFirstChild("Atmosphere")
	if atmosphere then
		atmosphere.Density = 0.7
	end

	-- Periodic lightning flashes
	local stormActive = true
	task.spawn(function()
		while stormActive do
			task.wait(3 + math.random() * 8)
			if not stormActive then break end

			-- Flash
			local originalBrightness = Lighting.Brightness
			Lighting.Brightness = 8
			task.wait(0.1)
			Lighting.Brightness = originalBrightness

			-- Thunder sound delay
			task.wait(0.5 + math.random() * 2)
		end
	end)

	-- End storm after night
	task.delay(Config.DayCycle.DayLengthSeconds * 0.35, function()
		stormActive = false
		if atmosphere then
			atmosphere.Density = 0.3
		end
	end)

	return { stormActive = true }
end

------------------------------------------------------------------------
-- Event Trigger Logic
------------------------------------------------------------------------
local EventHandlers = {
	CultistRaid = StartCultistRaid,
	MeteorShower = StartMeteorShower,
	FrogInvasion = StartFrogInvasion,
	AlienVisit = StartAlienVisit,
	BloodMoon = StartBloodMoon,
	ThunderStorm = StartThunderStorm,
}

local function PickRandomEvent(currentDay: number): string?
	local totalWeight = 0
	local eligible = {}

	for eventName, eventConfig in pairs(Config.NightEvents.Events) do
		if currentDay >= eventConfig.minDay then
			totalWeight = totalWeight + eventConfig.weight
			table.insert(eligible, { name = eventName, weight = eventConfig.weight })
		end
	end

	if #eligible == 0 then return nil end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, event in ipairs(eligible) do
		cumulative = cumulative + event.weight
		if roll <= cumulative then
			return event.name
		end
	end

	return eligible[#eligible].name
end

local function TryTriggerEvent(currentDay: number)
	if currentDay < Config.NightEvents.MinDayForEvents then return end
	if EventState.activeEvent then return end
	if EventState.checkedTonight then return end

	EventState.checkedTonight = true

	-- Roll for event
	if math.random() > Config.NightEvents.ChancePerNight then return end

	local eventType = PickRandomEvent(currentDay)
	if not eventType then return end

	EventState.activeEvent = eventType
	EventState.eventDay = currentDay

	local handler = EventHandlers[eventType]
	if handler then
		EventState.eventData = handler()
	end

	NightEventStarted:FireAllClients(eventType, EventState.eventData)
end

local function EndEvent()
	if not EventState.activeEvent then return end

	NightEventEnded:FireAllClients(EventState.activeEvent)

	EventState.activeEvent = nil
	EventState.eventData = {}
end

------------------------------------------------------------------------
-- Main Loop
------------------------------------------------------------------------
task.defer(function()
	task.wait(3)

	local wasNight = false

	RunService.Heartbeat:Connect(function(dt)
		local GetGameState = game.ServerStorage:FindFirstChild("GetGameState")
		if not GetGameState then return end
		local gs = GetGameState:Invoke()
		if not gs or not gs.sessionStarted then return end

		local timePercent = gs.dayTimeElapsed / Config.DayCycle.DayLengthSeconds
		local isNight = timePercent >= Config.DayCycle.NightStartPercent

		-- Night started
		if isNight and not wasNight then
			wasNight = true
			EventState.checkedTonight = false
			TryTriggerEvent(gs.currentDay)
		end

		-- Day started (night ended)
		if not isNight and wasNight then
			wasNight = false
			EndEvent()
		end
	end)
end)

------------------------------------------------------------------------
-- Expose state
------------------------------------------------------------------------
local GetNightEvent = Instance.new("BindableFunction")
GetNightEvent.Name = "GetNightEvent"
GetNightEvent.Parent = game.ServerStorage
GetNightEvent.OnInvoke = function()
	return EventState
end
