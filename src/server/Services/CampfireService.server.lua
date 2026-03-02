--[[
	CampfireService.server.lua
	Central campfire safe zone system (inspired by 99 Nights in the Forest).
	The campfire is the player's only safe haven at night — keeps
	The Stalker and enemies out while it burns. Upgrading the campfire
	expands the accessible map area and unlocks crafting tiers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local Utils = require(Modules.Utils)
local ItemDB = require(Modules.ItemDatabase)

------------------------------------------------------------------------
-- Wait for GameManager to set up Remotes
------------------------------------------------------------------------
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")

-- Create campfire-specific remotes
local CampfireUpdate = Instance.new("RemoteEvent")
CampfireUpdate.Name = "CampfireUpdate"
CampfireUpdate.Parent = Remotes

local RefuelCampfire = Instance.new("RemoteEvent")
RefuelCampfire.Name = "RefuelCampfire"
RefuelCampfire.Parent = Remotes

local UpgradeCampfire = Instance.new("RemoteEvent")
UpgradeCampfire.Name = "UpgradeCampfire"
UpgradeCampfire.Parent = Remotes

------------------------------------------------------------------------
-- Campfire State
------------------------------------------------------------------------
local CampfireState = {
	tier = 1,
	fuel = Config.Campfire.Tiers[1].fuelCapacity * 0.6, -- start 60% full
	maxFuel = Config.Campfire.Tiers[1].fuelCapacity,
	isLit = true,
	safeZoneRadius = Config.Campfire.Tiers[1].radius,
	mapRadius = Config.Campfire.Tiers[1].mapRadius,
	position = Vector3.new(0, 0, 0),  -- set during map build
	extinguishedAt = 0,
}

------------------------------------------------------------------------
-- Campfire Part (visual + collision reference)
------------------------------------------------------------------------
local campfirePart = nil

local function CreateCampfirePart()
	-- Create the campfire base
	local base = Instance.new("Part")
	base.Name = "Campfire"
	base.Size = Vector3.new(6, 1, 6)
	base.Position = CampfireState.position + Vector3.new(0, 0.5, 0)
	base.Anchored = true
	base.Material = Enum.Material.Slate
	base.BrickColor = BrickColor.new("Dark stone grey")
	base.Shape = Enum.PartType.Cylinder
	base.Orientation = Vector3.new(0, 0, 90)
	base.Parent = workspace

	-- Fire effect
	local fire = Instance.new("Fire")
	fire.Name = "CampfireFire"
	fire.Size = 8
	fire.Heat = 15
	fire.Color = Color3.fromRGB(255, 150, 30)
	fire.SecondaryColor = Color3.fromRGB(255, 80, 0)
	fire.Parent = base

	-- Light
	local light = Instance.new("PointLight")
	light.Name = "CampfireLight"
	light.Brightness = 2
	light.Range = 40
	light.Color = Color3.fromRGB(255, 170, 50)
	light.Parent = base

	-- Smoke when fire is strong
	local smoke = Instance.new("Smoke")
	smoke.Name = "CampfireSmoke"
	smoke.Size = 3
	smoke.Opacity = 0.3
	smoke.RiseVelocity = 5
	smoke.Color = Color3.fromRGB(100, 100, 100)
	smoke.Parent = base

	CollectionService:AddTag(base, "Campfire")

	-- Safe zone visualizer (transparent cylinder)
	local zone = Instance.new("Part")
	zone.Name = "SafeZone"
	zone.Shape = Enum.PartType.Cylinder
	zone.Size = Vector3.new(1, CampfireState.safeZoneRadius * 2, CampfireState.safeZoneRadius * 2)
	zone.Position = CampfireState.position + Vector3.new(0, 0.1, 0)
	zone.Orientation = Vector3.new(0, 0, 90)
	zone.Anchored = true
	zone.CanCollide = false
	zone.Transparency = 0.95
	zone.Material = Enum.Material.ForceField
	zone.BrickColor = BrickColor.new("Bright orange")
	zone.Parent = workspace

	campfirePart = base
	return base
end

------------------------------------------------------------------------
-- Core Logic
------------------------------------------------------------------------
local function IsPlayerNearCampfire(player: Player): boolean
	local char = player.Character
	if not char then return false end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return false end

	local dist = (root.Position - CampfireState.position).Magnitude
	return dist <= CampfireState.safeZoneRadius
end

local function UpdateFireVisuals()
	if not campfirePart then return end

	local fire = campfirePart:FindFirstChild("CampfireFire")
	local light = campfirePart:FindFirstChild("CampfireLight")
	local smoke = campfirePart:FindFirstChild("CampfireSmoke")

	if CampfireState.isLit then
		-- Scale fire size based on fuel percentage
		local fuelPercent = CampfireState.fuel / CampfireState.maxFuel
		if fire then
			fire.Enabled = true
			fire.Size = 4 + (fuelPercent * 12)  -- 4 to 16 based on fuel
			fire.Heat = 8 + (fuelPercent * 12)
		end
		if light then
			light.Enabled = true
			light.Brightness = 1 + (fuelPercent * 2)
			light.Range = 20 + (fuelPercent * 30)
		end
		if smoke then
			smoke.Enabled = true
			smoke.Opacity = 0.1 + (fuelPercent * 0.3)
		end
	else
		-- Fire is out
		if fire then fire.Enabled = false end
		if light then light.Brightness = 0.2; light.Range = 5 end
		if smoke then smoke.Enabled = false end
	end
end

local function ExtinguishCampfire()
	if not CampfireState.isLit then return end

	CampfireState.isLit = false
	CampfireState.extinguishedAt = tick()
	UpdateFireVisuals()

	-- Alert all players
	NotifyPlayers:FireAllClients(
		"THE CAMPFIRE HAS GONE OUT! You are no longer safe!",
		Color3.fromRGB(255, 0, 0)
	)
	CampfireUpdate:FireAllClients("Extinguished", CampfireState)
end

local function RelightCampfire()
	if CampfireState.isLit then return end
	if CampfireState.fuel < Config.Campfire.RelightFuelCost then return end

	CampfireState.isLit = true
	CampfireState.extinguishedAt = 0
	UpdateFireVisuals()

	NotifyPlayers:FireAllClients(
		"The campfire has been relit! Safe zone restored.",
		Color3.fromRGB(255, 200, 50)
	)
	CampfireUpdate:FireAllClients("Relit", CampfireState)
end

------------------------------------------------------------------------
-- Fuel Management
------------------------------------------------------------------------
local function UpdateCampfireFuel(dt: number)
	if not CampfireState.isLit then return end

	-- Get game state to check if it's night
	local GetGameState = game.ServerStorage:FindFirstChild("GetGameState")
	local isNight = false
	if GetGameState then
		local gs = GetGameState:Invoke()
		local timePercent = gs.dayTimeElapsed / Config.DayCycle.DayLengthSeconds
		isNight = timePercent >= Config.DayCycle.NightStartPercent
	end

	-- Fuel drain (mostly at night)
	local drainRate = Config.Campfire.FuelDrainPerSecond
	if not isNight then
		drainRate = drainRate * Config.Campfire.DayDrainMultiplier
	end

	CampfireState.fuel = CampfireState.fuel - (drainRate * dt)

	-- Extinguish if out of fuel
	if CampfireState.fuel <= 0 then
		CampfireState.fuel = 0
		ExtinguishCampfire()
	end

	-- Periodically broadcast state
	UpdateFireVisuals()
end

------------------------------------------------------------------------
-- Player Benefits (warmth/hunger reduction near campfire)
------------------------------------------------------------------------
local function ApplyCampfireBuffs(dt: number)
	if not CampfireState.isLit then return end

	for _, player in ipairs(Players:GetPlayers()) do
		if IsPlayerNearCampfire(player) then
			-- Health regen near campfire
			local DamagePlayerBF = game.ServerStorage:FindFirstChild("DamagePlayer")
			-- We use negative damage for healing via a dedicated heal path
			local GetPlayerState = game.ServerStorage:FindFirstChild("GetPlayerState")
			if GetPlayerState then
				local ps = GetPlayerState:Invoke(player)
				if ps and ps.state == Enums.PlayerState.Alive and ps.health < Config.Player.MaxHealth then
					-- Heal via DamagePlayer with negative damage
					if DamagePlayerBF then
						DamagePlayerBF:Invoke(player, -Config.Campfire.WarmthRegenPerSecond * dt)
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Remote Handlers
------------------------------------------------------------------------

-- Refuel campfire with wood/fuel items
RefuelCampfire.OnServerEvent:Connect(function(player, slotIndex)
	local GetPlayerState = game.ServerStorage:FindFirstChild("GetPlayerState")
	if not GetPlayerState then return end

	local ps = GetPlayerState:Invoke(player)
	if not ps then return end

	local item = ps.inventory[slotIndex]
	if not item then return end

	local itemData = ItemDB.GetItem(item.itemId)
	if not itemData then return end

	-- Accept campfire fuel, wood, or regular fuel items
	local fuelAmount = 0
	if itemData.campfireFuel then
		fuelAmount = itemData.campfireFuel
	elseif item.itemId == "wood" then
		fuelAmount = 8  -- raw wood gives less than dedicated fuel
	elseif itemData.category == Enums.ItemCategory.Fuel then
		fuelAmount = (itemData.fuelAmount or 10) * 0.5  -- general fuel half as effective
	else
		NotifyPlayers:FireClient(player, "Can't use that as campfire fuel.", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Check proximity
	if not IsPlayerNearCampfire(player) then
		NotifyPlayers:FireClient(player, "Too far from campfire.", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Remove item and add fuel
	local RemoveItem = game.ServerStorage:FindFirstChild("RemovePlayerItem")
	if RemoveItem then
		RemoveItem:Invoke(player, slotIndex, 1)
	end

	CampfireState.fuel = math.min(CampfireState.maxFuel, CampfireState.fuel + fuelAmount)

	-- Relight if it was out and we have enough fuel
	if not CampfireState.isLit and CampfireState.fuel >= Config.Campfire.RelightFuelCost then
		RelightCampfire()
	end

	UpdateFireVisuals()
	NotifyPlayers:FireClient(player, "Added fuel to campfire (+" .. fuelAmount .. ")", Color3.fromRGB(255, 200, 50))
	CampfireUpdate:FireAllClients("FuelUpdate", CampfireState)
end)

-- Upgrade campfire
UpgradeCampfire.OnServerEvent:Connect(function(player)
	local nextTier = CampfireState.tier + 1
	if nextTier > #Config.Campfire.Tiers then
		NotifyPlayers:FireClient(player, "Campfire is already max level!", Color3.fromRGB(255, 200, 50))
		return
	end

	if not IsPlayerNearCampfire(player) then
		NotifyPlayers:FireClient(player, "Too far from campfire.", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Check costs
	local costs = Config.Campfire.UpgradeCosts[nextTier]
	if not costs then return end

	local CountItem = game.ServerStorage:FindFirstChild("CountPlayerItem")
	local RemoveById = game.ServerStorage:FindFirstChild("RemovePlayerItemById")
	if not CountItem or not RemoveById then return end

	-- Verify player has all required materials
	for itemId, needed in pairs(costs) do
		local have = CountItem:Invoke(player, itemId)
		if have < needed then
			NotifyPlayers:FireClient(player,
				"Need " .. needed .. "x " .. (ItemDB.GetItem(itemId) and ItemDB.GetItem(itemId).name or itemId),
				Color3.fromRGB(255, 100, 100)
			)
			return
		end
	end

	-- Consume materials
	for itemId, needed in pairs(costs) do
		RemoveById:Invoke(player, itemId, needed)
	end

	-- Apply upgrade
	CampfireState.tier = nextTier
	local tierData = Config.Campfire.Tiers[nextTier]
	CampfireState.maxFuel = tierData.fuelCapacity
	CampfireState.fuel = CampfireState.maxFuel  -- full refuel on upgrade
	CampfireState.safeZoneRadius = tierData.radius
	CampfireState.mapRadius = tierData.mapRadius
	CampfireState.isLit = true

	-- Update safe zone visual
	local zone = workspace:FindFirstChild("SafeZone")
	if zone then
		zone.Size = Vector3.new(1, CampfireState.safeZoneRadius * 2, CampfireState.safeZoneRadius * 2)
	end

	UpdateFireVisuals()

	NotifyPlayers:FireAllClients(
		player.Name .. " upgraded the campfire to " .. tierData.name .. "!",
		Color3.fromRGB(255, 200, 0)
	)
	CampfireUpdate:FireAllClients("Upgraded", CampfireState)
end)

------------------------------------------------------------------------
-- Expose state for other services
------------------------------------------------------------------------
local GetCampfireState = Instance.new("BindableFunction")
GetCampfireState.Name = "GetCampfireState"
GetCampfireState.Parent = game.ServerStorage
GetCampfireState.OnInvoke = function()
	return CampfireState
end

local IsInSafeZone = Instance.new("BindableFunction")
IsInSafeZone.Name = "IsInSafeZone"
IsInSafeZone.Parent = game.ServerStorage
IsInSafeZone.OnInvoke = function(player)
	return CampfireState.isLit and IsPlayerNearCampfire(player)
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
task.defer(function()
	-- Wait a moment for map to generate
	task.wait(2)
	CreateCampfirePart()

	-- Main update loop
	RunService.Heartbeat:Connect(function(dt)
		local GetGameState = game.ServerStorage:FindFirstChild("GetGameState")
		if not GetGameState then return end
		local gs = GetGameState:Invoke()
		if not gs or not gs.sessionStarted then return end

		UpdateCampfireFuel(dt)
		ApplyCampfireBuffs(dt)
	end)
end)
