--[[
	LootService.server.lua
	Manages loot spawning in houses throughout the neighborhood.
	Each house has loot containers that respawn on a day-cycle timer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local ItemDatabase = require(Modules.ItemDatabase)
local Utils = require(Modules.Utils)

------------------------------------------------------------------------
-- Loot Container Registry
------------------------------------------------------------------------
-- Each house/location in the map should have parts tagged "LootContainer"
-- with attributes: Zone (1-3), LocationType (string), ContainerIndex (number)

local LootContainers = {}  -- [containerPart] = { zone, items, lastLooted, respawnDay }

------------------------------------------------------------------------
-- Spawn Loot for a Container
------------------------------------------------------------------------
local function GenerateLootForContainer(zone: number, locationType: string?): { any }
	local maxItems = Config.Loot.MaxItemsPerHouse[zone] or 4
	local itemCount = math.random(math.ceil(maxItems * 0.5), maxItems)

	-- Get loot pool
	local pool
	if locationType and ItemDatabase.BonusLoot[locationType] then
		pool = ItemDatabase.BonusLoot[locationType]
		-- Apply bonus multiplier
		local mult = Config.Loot.BonusMultiplier[locationType] or 1
		itemCount = math.floor(itemCount * mult)
	else
		pool = ItemDatabase.ZoneLoot[zone] or ItemDatabase.ZoneLoot[1]
	end

	local items = {}
	local tierWeights = Config.Loot.TierWeights[zone] or Config.Loot.TierWeights[1]

	for _ = 1, itemCount do
		-- Pick a random item from the pool
		local itemId = pool[math.random(1, #pool)]
		local itemData = ItemDatabase.GetItem(itemId)

		if itemData then
			-- Check if item tier matches zone tier weights
			local targetTier = Utils.PickTier(tierWeights)
			-- Allow the item if its tier matches or is lower than target
			local tierOrder = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4 }
			local itemTierOrder = tierOrder[itemData.tier] or 1
			local targetTierOrder = tierOrder[targetTier] or 1

			if itemTierOrder <= targetTierOrder then
				local quantity = 1
				if itemData.stackable then
					quantity = math.random(1, math.min(3, itemData.maxStack))
				end
				table.insert(items, {
					itemId = itemId,
					quantity = quantity,
				})
			end
		end
	end

	return items
end

------------------------------------------------------------------------
-- Create Physical Loot Items in a Container
------------------------------------------------------------------------
local function SpawnLootInContainer(containerPart: BasePart, items: { any })
	-- Clear existing loot
	for _, child in ipairs(containerPart:GetChildren()) do
		if child:HasTag("LootItem") then
			child:Destroy()
		end
	end

	for i, item in ipairs(items) do
		local itemData = ItemDatabase.GetItem(item.itemId)
		if not itemData then continue end

		local lootPart = Instance.new("Part")
		lootPart.Name = "Loot_" .. item.itemId
		lootPart.Size = Vector3.new(1, 1, 1)
		lootPart.Anchored = true
		lootPart.CanCollide = false

		-- Position loot items inside the container spread out
		local offset = Vector3.new(
			(i - 1) % 3 * 1.5 - 1.5,
			0.5,
			math.floor((i - 1) / 3) * 1.5
		)
		lootPart.CFrame = containerPart.CFrame * CFrame.new(offset)

		-- Color by tier
		local tierColor = Enums.TierColor[itemData.tier]
		if tierColor then
			lootPart.Color = tierColor
		end

		-- Set item data as attributes
		lootPart:SetAttribute("ItemId", item.itemId)
		lootPart:SetAttribute("Quantity", item.quantity)
		lootPart:SetAttribute("ItemName", itemData.name)
		lootPart:SetAttribute("ItemTier", itemData.tier)

		CollectionService:AddTag(lootPart, "LootItem")

		-- Billboard label
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(0, 140, 0, 40)
		billboard.StudsOffset = Vector3.new(0, 1.5, 0)
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = 20
		billboard.Parent = lootPart

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, 0, 0.6, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = itemData.name
		nameLabel.TextColor3 = tierColor or Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Parent = billboard

		local quantityLabel = Instance.new("TextLabel")
		quantityLabel.Size = UDim2.new(1, 0, 0.4, 0)
		quantityLabel.Position = UDim2.new(0, 0, 0.6, 0)
		quantityLabel.BackgroundTransparency = 1
		quantityLabel.Text = item.quantity > 1 and ("x" .. item.quantity) or ""
		quantityLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		quantityLabel.TextScaled = true
		quantityLabel.Font = Enum.Font.Gotham
		quantityLabel.Parent = billboard

		-- Proximity prompt for pickup
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pick Up"
		prompt.ObjectText = itemData.name
		prompt.MaxActivationDistance = Config.Player.PickupRange
		prompt.HoldDuration = 0.3
		prompt.Parent = lootPart

		lootPart.Parent = containerPart
	end
end

------------------------------------------------------------------------
-- Initialize All Containers
------------------------------------------------------------------------
local function InitializeContainers()
	local containers = CollectionService:GetTagged("LootContainer")

	for _, containerPart in ipairs(containers) do
		local zone = containerPart:GetAttribute("Zone") or 1
		local locationType = containerPart:GetAttribute("LocationType")

		local items = GenerateLootForContainer(zone, locationType)
		SpawnLootInContainer(containerPart, items)

		LootContainers[containerPart] = {
			zone = zone,
			locationType = locationType,
			items = items,
			lastLooted = 0,
			respawnDay = 0,
		}
	end

	print("[LootService] Initialized " .. #containers .. " loot containers")
end

------------------------------------------------------------------------
-- Handle New Containers Added at Runtime
------------------------------------------------------------------------
CollectionService:GetInstanceAddedSignal("LootContainer"):Connect(function(containerPart)
	local zone = containerPart:GetAttribute("Zone") or 1
	local locationType = containerPart:GetAttribute("LocationType")

	local items = GenerateLootForContainer(zone, locationType)
	SpawnLootInContainer(containerPart, items)

	LootContainers[containerPart] = {
		zone = zone,
		locationType = locationType,
		items = items,
		lastLooted = 0,
		respawnDay = 0,
	}
end)

------------------------------------------------------------------------
-- Loot Respawn Check (triggered by DayChanged event)
------------------------------------------------------------------------
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DayChanged = Remotes:WaitForChild("DayChanged")

-- Listen for day changes to handle respawns
-- We use a BindableEvent since DayChanged is a RemoteEvent (client-facing)
-- Instead, we'll poll the game state periodically
local lastKnownDay = 0

RunService.Heartbeat:Connect(function()
	local getState = game.ServerStorage:FindFirstChild("GetGameState")
	if not getState then return end

	local state = getState:Invoke()
	if not state then return end

	if state.currentDay > lastKnownDay then
		lastKnownDay = state.currentDay

		-- Check each container for respawn
		for containerPart, data in pairs(LootContainers) do
			if not containerPart.Parent then
				LootContainers[containerPart] = nil
				continue
			end

			if data.respawnDay > 0 and lastKnownDay >= data.respawnDay then
				local items = GenerateLootForContainer(data.zone, data.locationType)
				SpawnLootInContainer(containerPart, items)
				data.items = items
				data.respawnDay = 0
			end
		end
	end
end)

------------------------------------------------------------------------
-- Mark Container as Looted
------------------------------------------------------------------------
local function MarkContainerLooted(containerPart: BasePart)
	local data = LootContainers[containerPart]
	if not data then return end

	data.lastLooted = lastKnownDay
	data.respawnDay = lastKnownDay + Config.Loot.HouseRespawnDays
end

-- Detect when all loot is taken from a container
CollectionService:GetInstanceRemovedSignal("LootItem"):Connect(function(lootPart)
	-- Check if the parent container is now empty
	local parent = lootPart.Parent
	if parent and LootContainers[parent] then
		local hasLoot = false
		for _, child in ipairs(parent:GetChildren()) do
			if child:HasTag("LootItem") then
				hasLoot = true
				break
			end
		end
		if not hasLoot then
			MarkContainerLooted(parent)
		end
	end
end)

------------------------------------------------------------------------
-- Initialize on startup
------------------------------------------------------------------------
task.defer(InitializeContainers)

print("[LootService] Initialized")
