--[[
	GameManager.server.lua
	Core game loop controller for The Purge: Suburban Survival
	Manages day/night cycle, game phases, Purge triggering, and session state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local Utils = require(Modules.Utils)

------------------------------------------------------------------------
-- RemoteEvents Setup
------------------------------------------------------------------------
local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local function CreateRemote(name: string, className: string): Instance
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = Remotes
	return remote
end

-- Game state remotes
local GamePhaseChanged = CreateRemote("GamePhaseChanged", "RemoteEvent")
local DayChanged = CreateRemote("DayChanged", "RemoteEvent")
local PurgeCountdown = CreateRemote("PurgeCountdown", "RemoteEvent")
local PurgeSiren = CreateRemote("PurgeSiren", "RemoteEvent")
local PurgeStarted = CreateRemote("PurgeStarted", "RemoteEvent")
local PurgeEnded = CreateRemote("PurgeEnded", "RemoteEvent")
local PowerOutAlert = CreateRemote("PowerOutAlert", "RemoteEvent")
local PlayerDowned = CreateRemote("PlayerDowned", "RemoteEvent")
local PlayerRevived = CreateRemote("PlayerRevived", "RemoteEvent")
local NotifyPlayers = CreateRemote("NotifyPlayers", "RemoteEvent")

-- Interaction remotes
local InteractRequest = CreateRemote("InteractRequest", "RemoteEvent")
local PickupItem = CreateRemote("PickupItem", "RemoteEvent")
local DropItem = CreateRemote("DropItem", "RemoteEvent")
local UseItem = CreateRemote("UseItem", "RemoteEvent")
local CookRequest = CreateRemote("CookRequest", "RemoteEvent")
local FortifyRequest = CreateRemote("FortifyRequest", "RemoteEvent")
local RefuelRequest = CreateRemote("RefuelRequest", "RemoteEvent")
local ReviveRequest = CreateRemote("ReviveRequest", "RemoteEvent")
local CraftRequest = CreateRemote("CraftRequest", "RemoteEvent")
local EquipItem = CreateRemote("EquipItem", "RemoteEvent")
local UpgradeBase = CreateRemote("UpgradeBase", "RemoteEvent")

-- Data remotes
local RequestInventory = CreateRemote("RequestInventory", "RemoteFunction")
local RequestGameState = CreateRemote("RequestGameState", "RemoteFunction")
local UpdateHUD = CreateRemote("UpdateHUD", "RemoteEvent")

------------------------------------------------------------------------
-- Forward declarations
------------------------------------------------------------------------
local SyncPowerValue  -- defined at end, after ReplicatedStorage value is created

------------------------------------------------------------------------
-- Game State
------------------------------------------------------------------------
local GameState = {
	phase = Enums.GamePhase.Lobby,
	currentDay = 0,
	dayTimeElapsed = 0,
	purgeNumber = 0,
	purgeActive = false,
	purgeTimeRemaining = 0,
	playerCount = 0,
	sessionStarted = false,

	-- Shared house state
	house = {
		fortifications = {},  -- [slotName] = { materialId, durability, maxDurability }
		cookingStations = {},  -- [stationType] = true/false
		gardenPlots = {},     -- { seedId, plantedDay, grown }
		baseLevel = 1,        -- expansion level (1-4)
	},

	-- Generator state
	generator = {
		tier = 1,
		fuel = 50,              -- starting fuel
		maxFuel = Config.Generator.FuelCapacity[1],
		poweredSystems = { Lights = true },
		isPowered = true,
		solarCharging = false,
	},

	-- Food state
	foodStorage = {},  -- { itemId, quantity, spoilDay }

	-- Purge stats
	totalPurgesSurvived = 0,
	totalEnemiesKilled = 0,
}

-- Per-player state (server authoritative)
local PlayerStates = {}  -- [Player] = { health, hunger, stamina, state, inventory, ... }

------------------------------------------------------------------------
-- Player State Management
------------------------------------------------------------------------
local function InitPlayerState(player: Player)
	PlayerStates[player] = {
		health = Config.Player.MaxHealth,
		hunger = 70,  -- start slightly hungry to encourage scavenging
		stamina = 100,
		state = Enums.PlayerState.Alive,
		inventory = {},  -- { { itemId, quantity } }
		maxSlots = Config.Player.MaxInventorySlots,  -- 5 by default
		equippedWeapon = "baseball_bat",  -- equipped weapon (separate from backpack)
		knownRecipes = {},
		buffs = {},  -- { { type, amount, expiresAt } }
		isSprinting = false,
		isInCombat = false,
		carryingHeavy = false,
		downedAt = 0,
		scrap = 0,
		purgeCoins = 0,
	}

	-- Add starter recipes
	local RecipeDB = require(Modules.RecipeDatabase)
	for _, recipeId in ipairs(RecipeDB.GetStarterRecipes()) do
		PlayerStates[player].knownRecipes[recipeId] = true
	end
end

local function CleanupPlayerState(player: Player)
	PlayerStates[player] = nil
end

------------------------------------------------------------------------
-- Day / Night Cycle
------------------------------------------------------------------------
local function GetTimeOfDay(): number
	-- Returns 0-1 representing position in day cycle
	return GameState.dayTimeElapsed / Config.DayCycle.DayLengthSeconds
end

local function IsNightTime(): boolean
	return GetTimeOfDay() >= Config.DayCycle.NightStartPercent
end

local function UpdateLighting(dt: number)
	local timePercent = GetTimeOfDay()

	-- Map to ClockTime (0-24)
	-- Dawn at 5%, peak day at 50%, night at 65%
	local clockTime
	if timePercent < Config.DayCycle.DawnPercent then
		clockTime = Utils.Lerp(4, 6, timePercent / Config.DayCycle.DawnPercent)
	elseif timePercent < 0.5 then
		clockTime = Utils.Lerp(6, 14, (timePercent - Config.DayCycle.DawnPercent) / (0.5 - Config.DayCycle.DawnPercent))
	elseif timePercent < Config.DayCycle.NightStartPercent then
		clockTime = Utils.Lerp(14, 19, (timePercent - 0.5) / (Config.DayCycle.NightStartPercent - 0.5))
	else
		clockTime = Utils.Lerp(19, 4, (timePercent - Config.DayCycle.NightStartPercent) / (1 - Config.DayCycle.NightStartPercent))
	end

	Lighting.ClockTime = clockTime

	-- Fog during night
	local atmosphere = Lighting:FindFirstChild("Atmosphere")
	if atmosphere then
		if IsNightTime() then
			atmosphere.Density = Utils.Lerp(atmosphere.Density, 0.5, dt * 0.5)
		else
			atmosphere.Density = Utils.Lerp(atmosphere.Density, 0.2, dt * 0.5)
		end
	end

	-- Ambient lighting
	if IsNightTime() then
		Lighting.Ambient = Color3.fromRGB(20, 20, 30)
		Lighting.OutdoorAmbient = Color3.fromRGB(30, 30, 50)
		Lighting.Brightness = 0.5
	else
		Lighting.Ambient = Color3.fromRGB(120, 120, 120)
		Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 150)
		Lighting.Brightness = 2
	end
end

------------------------------------------------------------------------
-- Purge Logic
------------------------------------------------------------------------
local function ShouldTriggerPurge(): boolean
	return GameState.currentDay > 0
		and GameState.currentDay % Config.DayCycle.PurgeCycleInterval == 0
		and not GameState.purgeActive
end

local function CalculatePurgeDifficulty()
	local purgeNum = GameState.purgeNumber
	local playerCount = math.max(1, #Players:GetPlayers())

	local baseEnemies = Config.Purge.BaseEnemyCount
	local enemyCount = math.floor(
		baseEnemies
		* (Config.Purge.PurgeNumberMultiplier ^ (purgeNum - 1))
		* (1 + (playerCount - 1) * (Config.Purge.PlayerCountMultiplier - 1))
	)

	local duration = Config.Purge.BaseDurationSeconds
		+ Config.Purge.DurationScalePerPurge * (purgeNum - 1)

	local hasFirearms = purgeNum >= Config.Purge.FirearmsStartPurge
	local hasExplosives = purgeNum >= Config.Purge.ExplosivesStartPurge
	local hasArmored = purgeNum >= Config.Purge.ArmoredStartPurge
	local hasBoss = purgeNum >= Config.Purge.BossStartPurge
	local targetsPower = purgeNum >= Config.Purge.PowerCutStartPurge

	return {
		totalEnemies = enemyCount,
		duration = duration,
		hasFirearms = hasFirearms,
		hasExplosives = hasExplosives,
		hasArmored = hasArmored,
		hasBoss = hasBoss,
		targetsPower = targetsPower,
		waveCount = math.ceil(enemyCount / Config.Purge.EnemiesPerWave),
	}
end

local function StartPurge()
	GameState.purgeNumber += 1
	GameState.purgeActive = true
	GameState.phase = Enums.GamePhase.Purge

	local difficulty = CalculatePurgeDifficulty()
	GameState.purgeTimeRemaining = difficulty.duration

	PurgeStarted:FireAllClients(GameState.purgeNumber, difficulty)
	GamePhaseChanged:FireAllClients(Enums.GamePhase.Purge)
	NotifyPlayers:FireAllClients("PURGE NIGHT #" .. GameState.purgeNumber .. " HAS BEGUN!", Color3.fromRGB(255, 0, 0))

	-- Purge wave spawning is handled by PurgeService
	-- Signal it via BindableEvent
	local purgeSignal = game.ServerStorage:FindFirstChild("PurgeStartSignal")
	if purgeSignal then
		purgeSignal:Fire(GameState.purgeNumber, difficulty)
	end
end

local function EndPurge()
	GameState.purgeActive = false
	GameState.phase = Enums.GamePhase.PostPurge
	GameState.totalPurgesSurvived += 1

	-- Calculate rewards
	local scrapReward = Config.Purge.BaseScrapReward
		+ Config.Purge.ScrapPerPurgeLevel * GameState.purgeNumber

	for player, state in pairs(PlayerStates) do
		if state.state == Enums.PlayerState.Alive then
			state.scrap += scrapReward
		end
	end

	PurgeEnded:FireAllClients(GameState.purgeNumber, scrapReward)
	GamePhaseChanged:FireAllClients(Enums.GamePhase.PostPurge)
	NotifyPlayers:FireAllClients(
		"Purge Night #" .. GameState.purgeNumber .. " survived! +" .. scrapReward .. " Scrap",
		Color3.fromRGB(0, 255, 0)
	)

	-- Grace period then back to scavenging
	task.delay(Config.DayCycle.PostPurgeGraceSeconds, function()
		if not GameState.purgeActive then
			GameState.phase = Enums.GamePhase.Scavenging
			GamePhaseChanged:FireAllClients(Enums.GamePhase.Scavenging)
		end
	end)
end

-- Called when power goes out (not during scheduled Purge)
local function TriggerPowerOutAttack()
	if GameState.purgeActive then return end  -- already in a Purge

	GameState.purgeActive = true
	GameState.phase = Enums.GamePhase.Purge

	PowerOutAlert:FireAllClients()
	NotifyPlayers:FireAllClients("POWER OUT! ENEMIES INCOMING!", Color3.fromRGB(255, 50, 0))

	local difficulty = CalculatePurgeDifficulty()
	-- Power-out attacks are slightly easier than scheduled Purges
	difficulty.totalEnemies = math.floor(difficulty.totalEnemies * 0.7)
	difficulty.duration = math.floor(difficulty.duration * 0.6)

	GameState.purgeTimeRemaining = difficulty.duration

	PurgeStarted:FireAllClients(0, difficulty)  -- purge 0 = power out attack

	local purgeSignal = game.ServerStorage:FindFirstChild("PurgeStartSignal")
	if purgeSignal then
		purgeSignal:Fire(0, difficulty)
	end
end

------------------------------------------------------------------------
-- Generator / Power Tick
------------------------------------------------------------------------
local function UpdateGenerator(dt: number)
	local gen = GameState.generator
	if not gen.isPowered then return end

	-- Count active powered systems
	local systemCount = 0
	for _, active in pairs(gen.poweredSystems) do
		if active then systemCount += 1 end
	end

	-- Calculate fuel drain
	local baseDrain = Config.Generator.BaseFuelDrain[gen.tier]
	local systemDrain = systemCount * Config.Generator.PerSystemDrain
	local totalDrain = (baseDrain + systemDrain) * dt

	-- Solar charging during daytime (tier 4)
	if gen.tier >= 4 and not IsNightTime() then
		gen.solarCharging = true
		local solarGain = Config.Generator.SolarChargeRate * dt
		gen.fuel = math.min(gen.maxFuel, gen.fuel + solarGain)
	else
		gen.solarCharging = false
	end

	gen.fuel = gen.fuel - totalDrain

	-- Random flicker
	local flickerChance = Config.Generator.FlickerChance[gen.tier]
	if flickerChance > 0 and math.random() < flickerChance * dt then
		-- Brief flicker effect
		UpdateHUD:FireAllClients("GeneratorFlicker", true)
		task.delay(0.5, function()
			if gen.isPowered then
				UpdateHUD:FireAllClients("GeneratorFlicker", false)
			end
		end)
	end

	-- Power out check
	if gen.fuel <= 0 then
		gen.fuel = 0
		gen.isPowered = false

		-- Shut down all powered systems
		for systemName, _ in pairs(gen.poweredSystems) do
			gen.poweredSystems[systemName] = false
		end

		SyncPowerValue()
		UpdateHUD:FireAllClients("PowerStatus", false)
		TriggerPowerOutAttack()
	end
end

------------------------------------------------------------------------
-- Hunger Tick
------------------------------------------------------------------------
local function UpdateHunger(dt: number)
	for player, state in pairs(PlayerStates) do
		if state.state ~= Enums.PlayerState.Alive then continue end

		-- Calculate drain multiplier
		local drainMult = 1
		if state.isSprinting then
			drainMult *= Config.Hunger.SprintDrainMultiplier
		end
		if state.isInCombat then
			drainMult *= Config.Hunger.FightDrainMultiplier
		end
		if state.carryingHeavy then
			drainMult *= Config.Hunger.CarryHeavyDrainMultiplier
		end
		if GameState.purgeActive then
			drainMult *= Config.Hunger.PurgeDrainMultiplier
		end

		local drain = Config.Hunger.PassiveDrainPerSecond * drainMult * dt
		state.hunger = Utils.Clamp(state.hunger - drain, 0, Config.Hunger.MaxHunger)

		-- Apply hunger effects
		local hungerLevel
		if state.hunger >= Config.Hunger.FullThreshold then
			hungerLevel = Enums.HungerLevel.Full
			-- Health regen
			state.health = math.min(Config.Player.MaxHealth,
				state.health + Config.Hunger.FullHealthRegen * dt)
		elseif state.hunger >= Config.Hunger.SatisfiedThreshold then
			hungerLevel = Enums.HungerLevel.Satisfied
		elseif state.hunger >= Config.Hunger.HungryThreshold then
			hungerLevel = Enums.HungerLevel.Hungry
		else
			hungerLevel = Enums.HungerLevel.Starving
			-- Health drain
			state.health = state.health - Config.Hunger.StarvingHealthDrain * dt
			if state.health <= 0 then
				state.health = 0
				state.state = Enums.PlayerState.Downed
				state.downedAt = tick()
				PlayerDowned:FireAllClients(player)
			end
		end

		-- Update client HUD
		UpdateHUD:FireClient(player, "HungerUpdate", {
			hunger = state.hunger,
			level = hungerLevel,
			health = state.health,
			stamina = state.stamina,
		})
	end
end

------------------------------------------------------------------------
-- Downed Player Tick
------------------------------------------------------------------------
local function UpdateDownedPlayers(dt: number)
	for player, state in pairs(PlayerStates) do
		if state.state ~= Enums.PlayerState.Downed then continue end

		local downedDuration = tick() - state.downedAt
		if downedDuration >= Config.Combat.DownedBleedoutTime then
			state.state = Enums.PlayerState.Dead
			NotifyPlayers:FireAllClients(
				player.Name .. " has been eliminated.",
				Color3.fromRGB(255, 80, 80)
			)
		end
	end
end

------------------------------------------------------------------------
-- Food Spoilage Tick (runs once per day transition)
------------------------------------------------------------------------
local function CheckFoodSpoilage()
	-- Check shared food storage (fridge)
	local hasFridgePower = GameState.generator.isPowered
		and GameState.generator.poweredSystems.Fridge

	for i = #GameState.foodStorage, 1, -1 do
		local food = GameState.foodStorage[i]
		if food.spoilDay > 0 then  -- -1 means never spoils
			local effectiveSpoilDay = food.spoilDay
			if hasFridgePower then
				effectiveSpoilDay = food.spoilDay * Config.Food.FridgeMultiplier
			end
			if GameState.currentDay >= food.addedDay + effectiveSpoilDay then
				table.remove(GameState.foodStorage, i)
				NotifyPlayers:FireAllClients(
					food.name .. " has spoiled!",
					Color3.fromRGB(180, 150, 0)
				)
			end
		end
	end
end

------------------------------------------------------------------------
-- Buff Tick
------------------------------------------------------------------------
local function UpdateBuffs(dt: number)
	local now = tick()
	for player, state in pairs(PlayerStates) do
		for i = #state.buffs, 1, -1 do
			local buff = state.buffs[i]
			if now >= buff.expiresAt then
				table.remove(state.buffs, i)
				UpdateHUD:FireClient(player, "BuffExpired", buff.type)
			end
		end
	end
end

------------------------------------------------------------------------
-- Session Start
------------------------------------------------------------------------
local function StartSession()
	if GameState.sessionStarted then return end
	GameState.sessionStarted = true
	GameState.phase = Enums.GamePhase.Scavenging
	GameState.currentDay = 1

	-- Initialize house fortification slots
	local fortSlots = {
		{ name = "FrontDoor", type = Enums.FortSlot.FrontDoor },
		{ name = "BackDoor", type = Enums.FortSlot.BackDoor },
	}
	for i = 1, Config.Fortification.WindowCount do
		table.insert(fortSlots, { name = "Window_" .. i, type = Enums.FortSlot.Window })
	end
	for i = 1, Config.Fortification.WallSectionCount do
		table.insert(fortSlots, { name = "Wall_" .. i, type = Enums.FortSlot.WallSection })
	end
	for i = 1, Config.Fortification.RoofSectionCount do
		table.insert(fortSlots, { name = "Roof_" .. i, type = Enums.FortSlot.RoofSection })
	end

	for _, slot in ipairs(fortSlots) do
		GameState.house.fortifications[slot.name] = {
			slotType = slot.type,
			materialId = nil,  -- empty = unfortified
			durability = 0,
			maxDurability = 0,
		}
	end

	GamePhaseChanged:FireAllClients(Enums.GamePhase.Scavenging)
	DayChanged:FireAllClients(GameState.currentDay)
	NotifyPlayers:FireAllClients("Day " .. GameState.currentDay .. " — Scavenge the neighborhood!", Color3.fromRGB(255, 200, 50))
end

------------------------------------------------------------------------
-- Player Connection Handlers
------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	InitPlayerState(player)
	GameState.playerCount = #Players:GetPlayers()

	if GameState.playerCount >= 1 and not GameState.sessionStarted then
		task.delay(5, StartSession)  -- 5 second delay to let others join
	end
end)

Players.PlayerRemoving:Connect(function(player)
	CleanupPlayerState(player)
	GameState.playerCount = #Players:GetPlayers()
end)

------------------------------------------------------------------------
-- Remote Handlers
------------------------------------------------------------------------
RequestGameState.OnServerInvoke = function(player)
	return {
		phase = GameState.phase,
		currentDay = GameState.currentDay,
		purgeNumber = GameState.purgeNumber,
		purgeActive = GameState.purgeActive,
		purgeTimeRemaining = GameState.purgeTimeRemaining,
		generator = {
			tier = GameState.generator.tier,
			fuel = GameState.generator.fuel,
			maxFuel = GameState.generator.maxFuel,
			isPowered = GameState.generator.isPowered,
		},
		house = GameState.house,
		playerState = PlayerStates[player],
	}
end

RequestInventory.OnServerInvoke = function(player)
	local state = PlayerStates[player]
	if not state then return {} end
	return {
		inventory = state.inventory,
		maxSlots = state.maxSlots,
		equippedWeapon = state.equippedWeapon,
	}
end

-- Refuel generator
RefuelRequest.OnServerEvent:Connect(function(player, fuelItemIndex)
	local state = PlayerStates[player]
	if not state then return end

	local item = state.inventory[fuelItemIndex]
	if not item then return end

	local ItemDB = require(Modules.ItemDatabase)
	local itemData = ItemDB.GetItem(item.itemId)
	if not itemData or itemData.category ~= Enums.ItemCategory.Fuel then return end

	local gen = GameState.generator
	local fuelToAdd = itemData.fuelAmount or 0
	gen.fuel = math.min(gen.maxFuel, gen.fuel + fuelToAdd)

	-- Remove fuel item from inventory
	item.quantity -= 1
	if item.quantity <= 0 then
		table.remove(state.inventory, fuelItemIndex)
	end

	-- Restart power if it was out
	if not gen.isPowered and gen.fuel > 0 then
		gen.isPowered = true
		gen.poweredSystems.Lights = true
		SyncPowerValue()
		UpdateHUD:FireAllClients("PowerStatus", true)

		-- If power-out attack was happening, end it
		if GameState.purgeActive and GameState.purgeNumber == 0 then
			EndPurge()
		end
	end

	UpdateHUD:FireClient(player, "GeneratorUpdate", {
		fuel = gen.fuel,
		maxFuel = gen.maxFuel,
		isPowered = gen.isPowered,
		tier = gen.tier,
	})

	NotifyPlayers:FireClient(player, "Refueled generator (+" .. fuelToAdd .. " fuel)", Color3.fromRGB(0, 200, 255))
end)

-- Revive request
ReviveRequest.OnServerEvent:Connect(function(player, targetPlayer)
	local state = PlayerStates[player]
	local targetState = PlayerStates[targetPlayer]
	if not state or not targetState then return end
	if state.state ~= Enums.PlayerState.Alive then return end
	if targetState.state ~= Enums.PlayerState.Downed then return end

	-- Check proximity
	local char = player.Character
	local targetChar = targetPlayer.Character
	if not char or not targetChar then return end

	local dist = Utils.Distance(
		char:GetPivot().Position,
		targetChar:GetPivot().Position
	)
	if dist > Config.Player.InteractRange then return end

	-- Start revive (takes time)
	state.state = Enums.PlayerState.Reviving
	NotifyPlayers:FireAllClients(
		player.Name .. " is reviving " .. targetPlayer.Name .. "...",
		Color3.fromRGB(100, 200, 255)
	)

	task.delay(Config.Player.ReviveTimeSeconds, function()
		if state.state == Enums.PlayerState.Reviving
			and targetState.state == Enums.PlayerState.Downed then
			targetState.state = Enums.PlayerState.Alive
			targetState.health = Config.Player.MaxHealth * 0.5  -- revive at half health
			state.state = Enums.PlayerState.Alive

			PlayerRevived:FireAllClients(targetPlayer)
			NotifyPlayers:FireAllClients(
				targetPlayer.Name .. " has been revived!",
				Color3.fromRGB(0, 255, 100)
			)
		end
	end)
end)

------------------------------------------------------------------------
-- Main Game Loop
------------------------------------------------------------------------
local lastDayNumber = 0

RunService.Heartbeat:Connect(function(dt)
	if not GameState.sessionStarted then return end

	-- Update day cycle
	GameState.dayTimeElapsed += dt
	if GameState.dayTimeElapsed >= Config.DayCycle.DayLengthSeconds then
		GameState.dayTimeElapsed = 0

		-- Apply day multiplier from rescued people
		local dayMultiplier = 1
		local GetDayMultiplier = game.ServerStorage:FindFirstChild("GetDayMultiplier")
		if GetDayMultiplier then
			dayMultiplier = GetDayMultiplier:Invoke()
		end
		GameState.currentDay += dayMultiplier
		lastDayNumber = GameState.currentDay

		DayChanged:FireAllClients(GameState.currentDay)
		local dayMsg = "Day " .. GameState.currentDay
		if dayMultiplier > 1 then
			dayMsg = dayMsg .. " (x" .. dayMultiplier .. " multiplier)"
		end
		NotifyPlayers:FireAllClients(dayMsg, Color3.fromRGB(255, 200, 50))
		CheckFoodSpoilage()
	end

	-- Pre-purge warning
	local timeToEndOfDay = Config.DayCycle.DayLengthSeconds - GameState.dayTimeElapsed
	if ShouldTriggerPurge() and timeToEndOfDay <= Config.DayCycle.PrePurgeWarningSeconds and not GameState.purgeActive then
		if timeToEndOfDay <= Config.DayCycle.PrePurgeWarningSeconds and GameState.phase ~= Enums.GamePhase.PrePurge then
			GameState.phase = Enums.GamePhase.PrePurge
			GamePhaseChanged:FireAllClients(Enums.GamePhase.PrePurge)
			PurgeSiren:FireAllClients()
			NotifyPlayers:FireAllClients(
				"EMERGENCY BROADCAST: Purge commencing in " .. math.ceil(timeToEndOfDay) .. " seconds!",
				Color3.fromRGB(255, 0, 0)
			)
		end

		PurgeCountdown:FireAllClients(math.ceil(timeToEndOfDay))
	end

	-- Start Purge at end of day
	if ShouldTriggerPurge() and timeToEndOfDay <= 0 and not GameState.purgeActive then
		StartPurge()
	end

	-- Update Purge timer
	if GameState.purgeActive then
		GameState.purgeTimeRemaining -= dt
		if GameState.purgeTimeRemaining <= 0 then
			EndPurge()
		end
	end

	-- Tick systems
	UpdateLighting(dt)
	UpdateGenerator(dt)
	UpdateHunger(dt)
	UpdateDownedPlayers(dt)
	UpdateBuffs(dt)
end)

------------------------------------------------------------------------
-- Expose game state for other server scripts
------------------------------------------------------------------------
local GameManagerModule = Instance.new("ModuleScript")
GameManagerModule.Name = "GameManagerAPI"
GameManagerModule.Parent = game.ServerStorage

-- Store references in ServerStorage for other services
local stateRef = Instance.new("BindableEvent")
stateRef.Name = "PurgeStartSignal"
stateRef.Parent = game.ServerStorage

local powerOutSignal = Instance.new("BindableFunction")
powerOutSignal.Name = "TriggerPowerOutAttack"
powerOutSignal.Parent = game.ServerStorage
powerOutSignal.OnInvoke = function()
	TriggerPowerOutAttack()
end

-- Expose GameState and PlayerStates via module
local SharedState = Instance.new("BindableFunction")
SharedState.Name = "GetGameState"
SharedState.Parent = game.ServerStorage
SharedState.OnInvoke = function()
	return GameState
end

local GetPlayerState = Instance.new("BindableFunction")
GetPlayerState.Name = "GetPlayerState"
GetPlayerState.Parent = game.ServerStorage
GetPlayerState.OnInvoke = function(player)
	return PlayerStates[player]
end

------------------------------------------------------------------------
-- Mutation BindableFunctions
-- BindableFunctions copy tables across script boundaries, so other
-- scripts cannot mutate PlayerStates/GameState directly. These
-- functions run inside GameManager's scope with direct access.
------------------------------------------------------------------------

-- DamagePlayer: apply damage to the authoritative player state
-- Returns: { newHealth: number, isDowned: boolean }
local DamagePlayerBF = Instance.new("BindableFunction")
DamagePlayerBF.Name = "DamagePlayer"
DamagePlayerBF.Parent = game.ServerStorage
DamagePlayerBF.OnInvoke = function(player, damage)
	local state = PlayerStates[player]
	if not state or state.state ~= Enums.PlayerState.Alive then
		return { newHealth = 0, isDowned = false }
	end

	state.health = state.health - damage

	-- Sync with Humanoid so other systems see accurate health
	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = math.max(0, state.health)
		end
	end

	local isDowned = false
	if state.health <= 0 then
		state.health = 0
		state.state = Enums.PlayerState.Downed
		state.downedAt = tick()
		isDowned = true

		local PlayerDownedRemote = Remotes:FindFirstChild("PlayerDowned")
		if PlayerDownedRemote then
			PlayerDownedRemote:FireAllClients(player)
		end
	end

	-- Send immediate health update to client
	UpdateHUD:FireClient(player, "HealthUpdate", {
		health = state.health,
		damage = damage,
	})

	return { newHealth = state.health, isDowned = isDowned }
end

-- SetFortificationSlot: modify fortification state in the authoritative GameState
local SetFortSlotBF = Instance.new("BindableFunction")
SetFortSlotBF.Name = "SetFortificationSlot"
SetFortSlotBF.Parent = game.ServerStorage
SetFortSlotBF.OnInvoke = function(slotName, slotData)
	if not GameState.house or not GameState.house.fortifications then return false end
	GameState.house.fortifications[slotName] = slotData
	return true
end

-- RemovePlayerItem: remove an item from the authoritative player inventory
-- Returns: true if successful
local RemoveItemBF = Instance.new("BindableFunction")
RemoveItemBF.Name = "RemovePlayerItem"
RemoveItemBF.Parent = game.ServerStorage
RemoveItemBF.OnInvoke = function(player, slotIndex, quantity)
	local state = PlayerStates[player]
	if not state or not state.inventory[slotIndex] then return false end

	local slot = state.inventory[slotIndex]
	slot.quantity = slot.quantity - (quantity or 1)
	if slot.quantity <= 0 then
		table.remove(state.inventory, slotIndex)
	end

	-- Send updated inventory to client
	UpdateHUD:FireClient(player, "InventoryUpdate", state.inventory)
	return true
end

-- AddPlayerItem: add an item to the authoritative player inventory
-- Handles stacking with existing items of the same type
-- Returns: true if successful, false if no room
local ItemDB = require(Modules.ItemDatabase)
local AddItemBF = Instance.new("BindableFunction")
AddItemBF.Name = "AddPlayerItem"
AddItemBF.Parent = game.ServerStorage
AddItemBF.OnInvoke = function(player, itemId, quantity)
	local state = PlayerStates[player]
	if not state then return false end

	local itemData = ItemDB.GetItem(itemId)
	if not itemData then return false end

	-- Check room: can we fit this quantity?
	local remaining = quantity

	-- Count space in existing stacks
	if itemData.stackable then
		for _, slot in ipairs(state.inventory) do
			if slot.itemId == itemId and slot.quantity < itemData.maxStack then
				remaining = remaining - (itemData.maxStack - slot.quantity)
			end
		end
	end

	-- Count empty slots needed
	if remaining > 0 then
		local slotsNeeded
		if itemData.stackable then
			slotsNeeded = math.ceil(remaining / itemData.maxStack)
		else
			slotsNeeded = remaining
		end
		if (#state.inventory + slotsNeeded) > state.maxSlots then
			NotifyPlayers:FireClient(player, "Inventory full!", Color3.fromRGB(255, 100, 100))
			return false
		end
	end

	-- Actually add the items
	remaining = quantity

	-- Stack with existing
	if itemData.stackable then
		for _, slot in ipairs(state.inventory) do
			if slot.itemId == itemId and slot.quantity < itemData.maxStack then
				local canAdd = math.min(remaining, itemData.maxStack - slot.quantity)
				slot.quantity = slot.quantity + canAdd
				remaining = remaining - canAdd
				if remaining <= 0 then break end
			end
		end
	end

	-- New slots for remainder
	while remaining > 0 do
		local addCount = 1
		if itemData.stackable then
			addCount = math.min(remaining, itemData.maxStack)
		end
		table.insert(state.inventory, {
			itemId = itemId,
			quantity = addCount,
			spoilDay = itemData.spoilDays or -1,
			pickedUpDay = GameState.currentDay,
		})
		remaining = remaining - addCount
	end

	UpdateHUD:FireClient(player, "InventoryUpdate", state.inventory)
	return true
end

-- HasPlayerRoom: check if player has room for an item without adding it
local HasRoomBF = Instance.new("BindableFunction")
HasRoomBF.Name = "HasPlayerRoom"
HasRoomBF.Parent = game.ServerStorage
HasRoomBF.OnInvoke = function(player, itemId, quantity)
	local state = PlayerStates[player]
	if not state then return false end

	local itemData = ItemDB.GetItem(itemId)
	if not itemData then return false end

	local remaining = quantity

	if itemData.stackable then
		for _, slot in ipairs(state.inventory) do
			if slot.itemId == itemId then
				local space = itemData.maxStack - slot.quantity
				if space >= remaining then return true end
				remaining = remaining - space
			end
		end
	end

	local slotsNeeded = 1
	if itemData.stackable then
		slotsNeeded = math.ceil(remaining / itemData.maxStack)
	else
		slotsNeeded = remaining
	end

	return (#state.inventory + slotsNeeded) <= state.maxSlots
end

-- CountPlayerItem: count how many of an item the player has
local CountItemBF = Instance.new("BindableFunction")
CountItemBF.Name = "CountPlayerItem"
CountItemBF.Parent = game.ServerStorage
CountItemBF.OnInvoke = function(player, itemId)
	local state = PlayerStates[player]
	if not state then return 0 end

	local count = 0
	for _, slot in ipairs(state.inventory) do
		if slot.itemId == itemId then
			count = count + slot.quantity
		end
	end
	return count
end

-- RemovePlayerItemById: remove items by ID from anywhere in inventory
local RemoveByIdBF = Instance.new("BindableFunction")
RemoveByIdBF.Name = "RemovePlayerItemById"
RemoveByIdBF.Parent = game.ServerStorage
RemoveByIdBF.OnInvoke = function(player, itemId, quantity)
	local state = PlayerStates[player]
	if not state then return false end

	local remaining = quantity
	for i = #state.inventory, 1, -1 do
		local slot = state.inventory[i]
		if slot.itemId == itemId then
			local toRemove = math.min(remaining, slot.quantity)
			slot.quantity = slot.quantity - toRemove
			remaining = remaining - toRemove
			if slot.quantity <= 0 then
				table.remove(state.inventory, i)
			end
			if remaining <= 0 then break end
		end
	end

	UpdateHUD:FireClient(player, "InventoryUpdate", state.inventory)
	return remaining <= 0
end

-- GetPlayerInventoryInfo: return inventory slot count and max slots
local GetInvInfoBF = Instance.new("BindableFunction")
GetInvInfoBF.Name = "GetPlayerInventoryInfo"
GetInvInfoBF.Parent = game.ServerStorage
GetInvInfoBF.OnInvoke = function(player)
	local state = PlayerStates[player]
	if not state then return { slotCount = 0, maxSlots = Config.Player.MaxInventorySlots } end
	return { slotCount = #state.inventory, maxSlots = state.maxSlots }
end

-- UsePlayerItem: use/consume an item from the authoritative player inventory
-- Handles food consumption, recipes, energy drinks, etc.
local UseItemBF = Instance.new("BindableFunction")
UseItemBF.Name = "UsePlayerItem"
UseItemBF.Parent = game.ServerStorage
UseItemBF.OnInvoke = function(player, slotIndex)
	local state = PlayerStates[player]
	if not state then return false end

	local slot = state.inventory[slotIndex]
	if not slot then return false end

	local itemData = ItemDB.GetItem(slot.itemId)
	if not itemData then return false end

	-- Food consumption
	if itemData.category == Enums.ItemCategory.Food and itemData.hungerRestore and itemData.hungerRestore > 0 then
		-- Raw meat sickness check
		if itemData.rawMeat then
			if math.random() < Config.Food.SicknessChanceRaw then
				NotifyPlayers:FireClient(player,
					"You feel sick from eating raw meat...",
					Color3.fromRGB(150, 200, 0)
				)
				table.insert(state.buffs, {
					type = "Nausea",
					amount = 1,
					expiresAt = tick() + Config.Food.SicknessDuration,
				})
			end
		end

		-- Restore hunger
		state.hunger = Utils.Clamp(
			state.hunger + itemData.hungerRestore,
			0, Config.Hunger.MaxHunger
		)

		-- Apply buff if any
		if itemData.buff then
			table.insert(state.buffs, {
				type = itemData.buff.type,
				amount = itemData.buff.amount,
				expiresAt = tick() + (itemData.buff.duration or 0),
			})
			UpdateHUD:FireClient(player, "BuffApplied", itemData.buff)
		end

		NotifyPlayers:FireClient(player,
			"Ate " .. itemData.name .. " (+" .. itemData.hungerRestore .. "% hunger)",
			Color3.fromRGB(100, 255, 100)
		)

		-- Remove 1 from inventory
		slot.quantity = slot.quantity - 1
		if slot.quantity <= 0 then
			table.remove(state.inventory, slotIndex)
		end
		UpdateHUD:FireClient(player, "InventoryUpdate", state.inventory)
		return true
	end

	-- Recipe card
	if itemData.category == Enums.ItemCategory.Recipe then
		local recipeId = itemData.recipeId
		if recipeId and not state.knownRecipes[recipeId] then
			state.knownRecipes[recipeId] = true
			NotifyPlayers:FireClient(player,
				"Learned recipe: " .. itemData.name,
				Color3.fromRGB(255, 200, 50)
			)
			slot.quantity = slot.quantity - 1
			if slot.quantity <= 0 then
				table.remove(state.inventory, slotIndex)
			end
			UpdateHUD:FireClient(player, "InventoryUpdate", state.inventory)
		else
			NotifyPlayers:FireClient(player,
				"You already know this recipe.",
				Color3.fromRGB(200, 200, 200)
			)
		end
		return true
	end

	-- Energy drink
	if slot.itemId == "energy_drink" then
		state.stamina = 100
		state.hunger = Utils.Clamp(state.hunger + 10, 0, Config.Hunger.MaxHunger)
		if itemData.buff then
			table.insert(state.buffs, {
				type = itemData.buff.type,
				amount = itemData.buff.amount,
				expiresAt = tick() + (itemData.buff.duration or 0),
			})
		end
		NotifyPlayers:FireClient(player, "Energy drink consumed! Full stamina!", Color3.fromRGB(0, 255, 255))
		slot.quantity = slot.quantity - 1
		if slot.quantity <= 0 then
			table.remove(state.inventory, slotIndex)
		end
		UpdateHUD:FireClient(player, "InventoryUpdate", state.inventory)
		return true
	end

	return false
end

-- GetFortificationSlot: read a single fortification slot from authoritative state
local GetFortSlotBF = Instance.new("BindableFunction")
GetFortSlotBF.Name = "GetFortificationSlot"
GetFortSlotBF.Parent = game.ServerStorage
GetFortSlotBF.OnInvoke = function(slotName)
	if not GameState.house or not GameState.house.fortifications then return nil end
	return GameState.house.fortifications[slotName]
end

------------------------------------------------------------------------
-- Equip / Unequip Weapon
------------------------------------------------------------------------
EquipItem.OnServerEvent:Connect(function(player, slotIndex)
	local state = PlayerStates[player]
	if not state then return end

	if slotIndex == nil or slotIndex == 0 then
		-- Unequip current weapon back to inventory
		if state.equippedWeapon then
			local ItemDB = require(Modules.ItemDatabase)
			local weaponData = ItemDB.GetItem(state.equippedWeapon)
			if weaponData then
				-- Try to add back to inventory
				if #state.inventory < state.maxSlots then
					table.insert(state.inventory, {
						itemId = state.equippedWeapon,
						quantity = 1,
						spoilDay = -1,
						pickedUpDay = GameState.currentDay,
					})
				else
					NotifyPlayers:FireClient(player, "Backpack full! Can't unequip.", Color3.fromRGB(255, 100, 100))
					return
				end
			end
			state.equippedWeapon = nil
			UpdateHUD:FireClient(player, "EquippedWeapon", nil)
			UpdateHUD:FireClient(player, "InventoryUpdate", state.inventory)
		end
		return
	end

	local slot = state.inventory[slotIndex]
	if not slot then return end

	local ItemDB = require(Modules.ItemDatabase)
	local itemData = ItemDB.GetItem(slot.itemId)
	if not itemData or itemData.category ~= Enums.ItemCategory.Weapon then
		NotifyPlayers:FireClient(player, "Can only equip weapons!", Color3.fromRGB(255, 100, 100))
		return
	end

	-- If already have a weapon equipped, swap it back to inventory
	if state.equippedWeapon then
		local oldWeapon = state.equippedWeapon
		state.equippedWeapon = slot.itemId
		-- Replace the inventory slot with the old weapon
		slot.itemId = oldWeapon
		slot.quantity = 1
		slot.spoilDay = -1
	else
		-- Equip from inventory, remove from backpack
		state.equippedWeapon = slot.itemId
		table.remove(state.inventory, slotIndex)
	end

	UpdateHUD:FireClient(player, "EquippedWeapon", state.equippedWeapon)
	UpdateHUD:FireClient(player, "InventoryUpdate", state.inventory)
	NotifyPlayers:FireClient(player, "Equipped " .. itemData.name, Color3.fromRGB(100, 200, 255))
end)

------------------------------------------------------------------------
-- Backpack Upgrade (called by InventoryService when a backpack is picked up)
------------------------------------------------------------------------
local UpgradeBackpackBF = Instance.new("BindableFunction")
UpgradeBackpackBF.Name = "UpgradeBackpack"
UpgradeBackpackBF.Parent = game.ServerStorage
UpgradeBackpackBF.OnInvoke = function(player, newMaxSlots)
	local state = PlayerStates[player]
	if not state then return false end

	if newMaxSlots > state.maxSlots then
		state.maxSlots = newMaxSlots
		UpdateHUD:FireClient(player, "BackpackUpgrade", state.maxSlots)
		return true
	end
	return false
end

------------------------------------------------------------------------
-- Base Expansion
------------------------------------------------------------------------
UpgradeBase.OnServerEvent:Connect(function(player)
	local state = PlayerStates[player]
	if not state then return end

	-- Check player is at their base
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Find starter house
	local starterHouse = MapFolder and MapFolder:FindFirstChild("StarterHouse")
	if not starterHouse then
		local mapFolder = workspace:FindFirstChild("Map")
		if mapFolder then
			starterHouse = mapFolder:FindFirstChild("StarterHouse")
		end
	end
	if not starterHouse then
		NotifyPlayers:FireClient(player, "Can't find your base!", Color3.fromRGB(255, 100, 100))
		return
	end

	local currentLevel = GameState.house.baseLevel
	if currentLevel >= Config.BaseExpansion.MaxLevel then
		NotifyPlayers:FireClient(player, "Base is fully upgraded!", Color3.fromRGB(255, 200, 50))
		return
	end

	local nextLevel = currentLevel + 1
	local costs = Config.BaseExpansion.Costs[nextLevel]
	if not costs then return end

	-- Check if player has all required materials
	local ItemDB = require(Modules.ItemDatabase)
	for itemId, needed in pairs(costs) do
		local count = 0
		for _, slot in ipairs(state.inventory) do
			if slot.itemId == itemId then
				count = count + slot.quantity
			end
		end
		if count < needed then
			local itemData = ItemDB.GetItem(itemId)
			local name = itemData and itemData.name or itemId
			NotifyPlayers:FireClient(player,
				"Need " .. needed .. "x " .. name .. " (have " .. count .. ")",
				Color3.fromRGB(255, 100, 100))
			return
		end
	end

	-- Consume materials
	for itemId, needed in pairs(costs) do
		local remaining = needed
		for i = #state.inventory, 1, -1 do
			local slot = state.inventory[i]
			if slot.itemId == itemId then
				local take = math.min(remaining, slot.quantity)
				slot.quantity = slot.quantity - take
				remaining = remaining - take
				if slot.quantity <= 0 then
					table.remove(state.inventory, i)
				end
				if remaining <= 0 then break end
			end
		end
	end

	-- Upgrade base level
	GameState.house.baseLevel = nextLevel

	-- Signal MapBuilder to expand the house
	local expandSignal = game.ServerStorage:FindFirstChild("ExpandBaseSignal")
	if expandSignal then
		expandSignal:Fire(nextLevel)
	end

	UpdateHUD:FireClient(player, "InventoryUpdate", state.inventory)
	NotifyPlayers:FireAllClients(
		"Base upgraded to Level " .. nextLevel .. "!",
		Color3.fromRGB(0, 255, 100))
	UpdateHUD:FireAllClients("BaseLevel", nextLevel)
end)

-- Create expand signal for MapBuilder
local expandSignal = Instance.new("BindableEvent")
expandSignal.Name = "ExpandBaseSignal"
expandSignal.Parent = game.ServerStorage

------------------------------------------------------------------------
-- SetPlayerMaxSlots: modify max inventory slots (for sack upgrades)
------------------------------------------------------------------------
local SetMaxSlotsBF = Instance.new("BindableFunction")
SetMaxSlotsBF.Name = "SetPlayerMaxSlots"
SetMaxSlotsBF.Parent = game.ServerStorage
SetMaxSlotsBF.OnInvoke = function(player, newMax)
	local state = PlayerStates[player]
	if not state then return false end
	if newMax > state.maxSlots then
		state.maxSlots = newMax
		UpdateHUD:FireClient(player, "BackpackUpgrade", state.maxSlots)
		return true
	end
	return false
end

------------------------------------------------------------------------
-- Replicated Power State (for home waypoint visibility)
------------------------------------------------------------------------
local PowerOnValue = Instance.new("BoolValue")
PowerOnValue.Name = "GeneratorPowered"
PowerOnValue.Value = GameState.generator.isPowered
PowerOnValue.Parent = ReplicatedStorage

-- Keep it in sync whenever power changes
SyncPowerValue = function()
	PowerOnValue.Value = GameState.generator.isPowered
end

print("[GameManager] Initialized - The Purge: Suburban Survival")
