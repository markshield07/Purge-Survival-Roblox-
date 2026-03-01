--[[
	ElectricityService.server.lua
	Generator management, power system, and upgrades.
	Works with GameManager for the power-out attack trigger.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local ItemDatabase = require(Modules.ItemDatabase)
local Utils = require(Modules.Utils)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RefuelRequest = Remotes:WaitForChild("RefuelRequest")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")

------------------------------------------------------------------------
-- Helper: Get shared game state
------------------------------------------------------------------------
local function GetGameState()
	local getter = game.ServerStorage:FindFirstChild("GetGameState")
	if getter then return getter:Invoke() end
	return nil
end

local function GetPlayerState(player)
	local getter = game.ServerStorage:FindFirstChild("GetPlayerState")
	if getter then return getter:Invoke(player) end
	return nil
end

------------------------------------------------------------------------
-- Generator Upgrade System
------------------------------------------------------------------------
local ElectricityService = {}

-- Parts needed per generator tier
local UpgradeRequirements = {
	[2] = { "spark_plugs", "wiring", "fan_belt" },         -- Repaired
	[3] = { "industrial_motor", "voltage_regulator", "heavy_fuel_tank" },  -- Heavy Duty
	[4] = { "solar_panel" },                                 -- Solar Backup
}

function ElectricityService.CanUpgradeGenerator(player: Player): (boolean, string)
	local gameState = GetGameState()
	local playerState = GetPlayerState(player)
	if not gameState or not playerState then return false, "No state" end

	local currentTier = gameState.generator.tier
	local nextTier = currentTier + 1

	if nextTier > 4 then
		return false, "Generator is already at maximum tier."
	end

	local requiredParts = UpgradeRequirements[nextTier]
	if not requiredParts then
		return false, "No upgrade path defined."
	end

	-- Check if player has all parts (check all players' inventories)
	for _, partId in ipairs(requiredParts) do
		local found = false
		for _, p in ipairs(Players:GetPlayers()) do
			local pState = GetPlayerState(p)
			if pState then
				for _, slot in ipairs(pState.inventory) do
					if slot.itemId == partId and slot.quantity > 0 then
						found = true
						break
					end
				end
			end
			if found then break end
		end
		if not found then
			local itemData = ItemDatabase.GetItem(partId)
			return false, "Missing: " .. (itemData and itemData.name or partId)
		end
	end

	return true, "Ready to upgrade"
end

function ElectricityService.UpgradeGenerator(player: Player)
	local canUpgrade, message = ElectricityService.CanUpgradeGenerator(player)
	if not canUpgrade then
		NotifyPlayers:FireClient(player, message, Color3.fromRGB(255, 100, 100))
		return
	end

	local gameState = GetGameState()
	local nextTier = gameState.generator.tier + 1
	local requiredParts = UpgradeRequirements[nextTier]

	-- Consume parts from players' inventories
	for _, partId in ipairs(requiredParts) do
		local consumed = false
		for _, p in ipairs(Players:GetPlayers()) do
			local pState = GetPlayerState(p)
			if pState then
				for i, slot in ipairs(pState.inventory) do
					if slot.itemId == partId and slot.quantity > 0 then
						slot.quantity -= 1
						if slot.quantity <= 0 then
							table.remove(pState.inventory, i)
						end
						UpdateHUD:FireClient(p, "InventoryUpdate", pState.inventory)
						consumed = true
						break
					end
				end
			end
			if consumed then break end
		end
	end

	-- Apply upgrade
	gameState.generator.tier = nextTier
	gameState.generator.maxFuel = Config.Generator.FuelCapacity[nextTier]
	-- Don't lose existing fuel, but cap at new max
	gameState.generator.fuel = math.min(gameState.generator.fuel, gameState.generator.maxFuel)

	local tierNames = { "Busted", "Repaired", "Heavy Duty", "Solar Backup" }
	NotifyPlayers:FireAllClients(
		"Generator upgraded to Tier " .. nextTier .. ": " .. tierNames[nextTier] .. "!",
		Color3.fromRGB(0, 255, 200)
	)

	UpdateHUD:FireAllClients("GeneratorUpdate", {
		fuel = gameState.generator.fuel,
		maxFuel = gameState.generator.maxFuel,
		isPowered = gameState.generator.isPowered,
		tier = nextTier,
	})
end

-- Toggle a powered system on/off
function ElectricityService.ToggleSystem(player: Player, systemName: string)
	local gameState = GetGameState()
	if not gameState then return end

	local systemConfig = Config.PoweredSystems[systemName]
	if not systemConfig then
		NotifyPlayers:FireClient(player, "Unknown system: " .. systemName, Color3.fromRGB(255, 100, 100))
		return
	end

	if not gameState.generator.isPowered then
		NotifyPlayers:FireClient(player, "No power! Generator is off.", Color3.fromRGB(255, 100, 100))
		return
	end

	local current = gameState.generator.poweredSystems[systemName] or false
	gameState.generator.poweredSystems[systemName] = not current

	local status = gameState.generator.poweredSystems[systemName] and "ON" or "OFF"
	NotifyPlayers:FireAllClients(
		systemConfig.name .. " turned " .. status,
		Color3.fromRGB(200, 200, 255)
	)

	UpdateHUD:FireAllClients("GeneratorUpdate", {
		fuel = gameState.generator.fuel,
		maxFuel = gameState.generator.maxFuel,
		isPowered = gameState.generator.isPowered,
		tier = gameState.generator.tier,
		systems = gameState.generator.poweredSystems,
	})
end

-- Get current power status info
function ElectricityService.GetPowerInfo()
	local gameState = GetGameState()
	if not gameState then return nil end

	local gen = gameState.generator
	local activeSystems = 0
	local totalDrain = Config.Generator.BaseFuelDrain[gen.tier]

	for name, active in pairs(gen.poweredSystems) do
		if active then
			activeSystems += 1
			local sysConfig = Config.PoweredSystems[name]
			if sysConfig then
				totalDrain += sysConfig.drain
			end
		end
	end

	local timeRemaining = 0
	if totalDrain > 0 and gen.fuel > 0 then
		timeRemaining = gen.fuel / totalDrain
	end

	return {
		tier = gen.tier,
		fuel = gen.fuel,
		maxFuel = gen.maxFuel,
		isPowered = gen.isPowered,
		activeSystems = activeSystems,
		totalDrain = totalDrain,
		timeRemainingSeconds = timeRemaining,
		solarCharging = gen.solarCharging,
	}
end

------------------------------------------------------------------------
-- Remote: Generator interaction (upgrade, toggle systems)
------------------------------------------------------------------------
local InteractRequest = Remotes:WaitForChild("InteractRequest")

InteractRequest.OnServerEvent:Connect(function(player, interactType, data)
	if interactType == "UpgradeGenerator" then
		ElectricityService.UpgradeGenerator(player)
	elseif interactType == "ToggleSystem" then
		ElectricityService.ToggleSystem(player, data)
	end
end)

------------------------------------------------------------------------
-- Expose service
------------------------------------------------------------------------
local getPowerInfo = Instance.new("BindableFunction")
getPowerInfo.Name = "GetPowerInfo"
getPowerInfo.Parent = game.ServerStorage
getPowerInfo.OnInvoke = function()
	return ElectricityService.GetPowerInfo()
end

print("[ElectricityService] Initialized")
