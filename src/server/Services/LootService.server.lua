--[[
	LootService.server.lua
	Manages loot spawning in houses throughout the neighborhood.
	Items visually look like what they are (cans, weapons, tools, etc.)
	and are placed on furniture surfaces (shelves, tables, counters).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local ItemDatabase = require(Modules.ItemDatabase)
local ItemVisuals = require(Modules.ItemVisuals)
local Utils = require(Modules.Utils)

------------------------------------------------------------------------
-- Loot Container Registry
------------------------------------------------------------------------
local LootContainers = {}  -- [containerPart] = { zone, items, lastLooted, respawnDay }

------------------------------------------------------------------------
-- Part shape helper
------------------------------------------------------------------------
local ShapeMap = {
	Block = Enum.PartType.Block,
	Cylinder = Enum.PartType.Cylinder,
	Ball = Enum.PartType.Ball,
}

------------------------------------------------------------------------
-- Generate Loot for a Container
------------------------------------------------------------------------
local function GenerateLootForContainer(zone: number, locationType: string?): { any }
	local maxItems = Config.Loot.MaxItemsPerHouse[zone] or 4
	local itemCount = math.random(math.ceil(maxItems * 0.5), maxItems)

	local pool
	if locationType and ItemDatabase.BonusLoot[locationType] then
		pool = ItemDatabase.BonusLoot[locationType]
		local mult = Config.Loot.BonusMultiplier[locationType] or 1
		itemCount = math.floor(itemCount * mult)
	else
		pool = ItemDatabase.ZoneLoot[zone] or ItemDatabase.ZoneLoot[1]
	end

	local items = {}
	local tierWeights = Config.Loot.TierWeights[zone] or Config.Loot.TierWeights[1]

	for _ = 1, itemCount do
		local itemId = pool[math.random(1, #pool)]
		local itemData = ItemDatabase.GetItem(itemId)

		if itemData then
			local targetTier = Utils.PickTier(tierWeights)
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
-- Create a single loot item Part with proper visuals
------------------------------------------------------------------------
local function CreateLootPart(item, itemData, position: CFrame, parent)
	local visual = ItemVisuals.GetVisual(item.itemId, itemData.category)

	local lootPart = Instance.new("Part")
	lootPart.Name = "Loot_" .. item.itemId
	lootPart.Size = visual.size
	lootPart.Anchored = true
	lootPart.CanCollide = false
	lootPart.Material = visual.material
	lootPart.Color = visual.color
	lootPart.Transparency = visual.transparency or 0

	-- Apply shape
	local shape = ShapeMap[visual.shape]
	if shape then
		lootPart.Shape = shape
	end

	lootPart.CFrame = position

	-- Set item data as attributes
	lootPart:SetAttribute("ItemId", item.itemId)
	lootPart:SetAttribute("Quantity", item.quantity)
	lootPart:SetAttribute("ItemName", itemData.name)
	lootPart:SetAttribute("ItemTier", itemData.tier)

	CollectionService:AddTag(lootPart, "LootItem")

	-- Glow effect for rare/special items
	if visual.glow then
		local glow = Instance.new("PointLight")
		glow.Color = visual.glow
		glow.Range = 4
		glow.Brightness = 0.6
		glow.Parent = lootPart
	end

	-- Tier-colored sparkle for Rare+ items
	local tierOrder = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4 }
	if (tierOrder[itemData.tier] or 1) >= 3 then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "TierSparkle"
		sparkle.Rate = 3
		sparkle.Lifetime = NumberRange.new(0.5, 1)
		sparkle.Speed = NumberRange.new(0.5, 1)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Size = NumberSequence.new(0.15, 0)
		sparkle.LightEmission = 1
		sparkle.Color = ColorSequence.new(Enums.TierColor[itemData.tier] or Color3.new(1, 1, 1))
		sparkle.Parent = lootPart
	end

	-- Billboard label (name + quantity)
	local tierColor = Enums.TierColor[itemData.tier]

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 150, 0, 45)
	billboard.StudsOffset = Vector3.new(0, 1.2, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 16
	billboard.Parent = lootPart

	-- Background frame for readability
	local bgFrame = Instance.new("Frame")
	bgFrame.Size = UDim2.new(1, 0, 1, 0)
	bgFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	bgFrame.BackgroundTransparency = 0.5
	bgFrame.BorderSizePixel = 0
	bgFrame.Parent = billboard

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 4)
	bgCorner.Parent = bgFrame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -4, 0.65, 0)
	nameLabel.Position = UDim2.new(0, 2, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = itemData.name
	nameLabel.TextColor3 = tierColor or Color3.new(1, 1, 1)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = bgFrame

	if item.quantity > 1 then
		local quantityLabel = Instance.new("TextLabel")
		quantityLabel.Size = UDim2.new(1, -4, 0.35, 0)
		quantityLabel.Position = UDim2.new(0, 2, 0.65, 0)
		quantityLabel.BackgroundTransparency = 1
		quantityLabel.Text = "x" .. item.quantity
		quantityLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		quantityLabel.TextScaled = true
		quantityLabel.Font = Enum.Font.Gotham
		quantityLabel.Parent = bgFrame
	end

	-- Proximity prompt for pickup
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = itemData.name
	prompt.MaxActivationDistance = Config.Player.PickupRange
	prompt.HoldDuration = 0.2
	prompt.Parent = lootPart

	lootPart.Parent = parent
	return lootPart
end

------------------------------------------------------------------------
-- Spawn Loot in a Container (furniture surface)
------------------------------------------------------------------------
local function SpawnLootInContainer(containerPart: BasePart, items: { any })
	-- Clear existing loot
	for _, child in ipairs(containerPart:GetChildren()) do
		if child:HasTag("LootItem") then
			child:Destroy()
		end
	end

	local containerSize = containerPart.Size
	local containerCF = containerPart.CFrame

	for i, item in ipairs(items) do
		local itemData = ItemDatabase.GetItem(item.itemId)
		if not itemData then continue end

		local visual = ItemVisuals.GetVisual(item.itemId, itemData.category)

		-- Spread items across the furniture surface
		local maxPerRow = math.max(1, math.floor(containerSize.X / 1.2))
		local row = math.floor((i - 1) / maxPerRow)
		local col = (i - 1) % maxPerRow

		local xSpread = containerSize.X * 0.8
		local zSpread = containerSize.Z * 0.6
		local xStart = -xSpread / 2
		local zStart = -zSpread / 2

		local xStep = maxPerRow > 1 and (xSpread / (maxPerRow - 1)) or 0
		local zStep = 1.2

		local localX = maxPerRow > 1 and (xStart + col * xStep) or 0
		local localZ = zStart + row * zStep
		local localY = containerSize.Y / 2 + visual.size.Y / 2 + 0.05

		local itemCF = containerCF * CFrame.new(localX, localY, localZ)

		-- Slight random rotation for natural look
		local yRot = math.rad(math.random(-15, 15))
		itemCF = itemCF * CFrame.Angles(0, yRot, 0)

		CreateLootPart(item, itemData, itemCF, containerPart)
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

	print("[LootService] Initialized " .. #containers .. " loot containers with visual items")
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
-- Loot Respawn Check
------------------------------------------------------------------------
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local lastKnownDay = 0

RunService.Heartbeat:Connect(function()
	local getState = game.ServerStorage:FindFirstChild("GetGameState")
	if not getState then return end

	local state = getState:Invoke()
	if not state then return end

	if state.currentDay > lastKnownDay then
		lastKnownDay = state.currentDay

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

CollectionService:GetInstanceRemovedSignal("LootItem"):Connect(function(lootPart)
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
