--[[
	CraftingBenchService.server.lua
	Tiered crafting bench + grinder system (inspired by 99 Nights in the Forest).
	- Grinder: converts junk items into scrap/bolts
	- Crafting Bench: 5 tiers, each unlocking new recipes
	- Recipes consume wood, scrap, bolts, cultist gems, forest gems
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local ItemDB = require(Modules.ItemDatabase)

------------------------------------------------------------------------
-- Wait for Remotes
------------------------------------------------------------------------
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")

-- Create crafting-specific remotes
local GrindItem = Instance.new("RemoteEvent")
GrindItem.Name = "GrindItem"
GrindItem.Parent = Remotes

local CraftItem = Instance.new("RemoteEvent")
CraftItem.Name = "CraftItem"
CraftItem.Parent = Remotes

local UpgradeBench = Instance.new("RemoteEvent")
UpgradeBench.Name = "UpgradeBench"
UpgradeBench.Parent = Remotes

local CraftingUpdate = Instance.new("RemoteEvent")
CraftingUpdate.Name = "CraftingUpdate"
CraftingUpdate.Parent = Remotes

------------------------------------------------------------------------
-- Crafting State (shared for the session)
------------------------------------------------------------------------
local CraftingState = {
	benchTier = 1,
}

------------------------------------------------------------------------
-- Crafting Recipes (tiered)
------------------------------------------------------------------------
local Recipes = {
	-- Tier 1: Basic survival
	[1] = {
		map = {
			name = "Map",
			costs = { wood = 3 },
			result = "map",
			resultQty = 1,
			description = "Shows your surroundings and teammate locations.",
		},
		old_bed = {
			name = "Old Bed",
			costs = { wood = 20 },
			result = "old_bed",
			resultQty = 1,
			description = "A basic respawn point. Adds +1 to day multiplier.",
		},
		bunny_trap = {
			name = "Bunny Trap",
			costs = { wood = 5, scrap = 2 },
			result = "bear_trap",
			resultQty = 1,
			description = "A small trap for catching critters.",
		},
		wooden_fence = {
			name = "Wooden Fence",
			costs = { wood = 8 },
			result = "plywood",
			resultQty = 2,
			description = "Basic fence section for camp defense.",
		},
		stone_axe = {
			name = "Stone Axe",
			costs = { wood = 3, scrap = 2 },
			result = "crowbar",
			resultQty = 1,
			description = "A basic chopping tool. Better than bare hands.",
		},
		campfire_wood_bundle = {
			name = "Campfire Wood Bundle",
			costs = { wood = 5 },
			result = "campfire_wood",
			resultQty = 3,
			description = "Processed fuel wood for the campfire.",
		},
	},

	-- Tier 2: Camp improvements
	[2] = {
		farm_plot = {
			name = "Farm Plot",
			costs = { wood = 10 },
			result = "carrot_seeds",
			resultQty = 3,
			description = "A plot for growing food. Plant seeds for sustainable meals.",
		},
		log_wall = {
			name = "Log Wall",
			costs = { wood = 12 },
			result = "reinforced_boards",
			resultQty = 2,
			description = "Sturdy wall section for base defense.",
		},
		sundial = {
			name = "Sundial",
			costs = { wood = 5, scrap = 3 },
			result = "sundial",
			resultQty = 1,
			description = "Shows time remaining until day/night transition.",
		},
		compass = {
			name = "Compass",
			costs = { bolts = 5 },
			result = "compass",
			resultQty = 1,
			description = "Navigation tool. Points toward campfire.",
		},
		bear_trap_craft = {
			name = "Bear Trap",
			costs = { scrap = 8, bolts = 3 },
			result = "bear_trap",
			resultQty = 1,
			description = "Large trap that slows and damages enemies.",
		},
		regular_bed = {
			name = "Regular Bed",
			costs = { scrap = 5 },
			result = "regular_bed",
			resultQty = 1,
			description = "Better bed. Adds +1 to day multiplier.",
		},
	},

	-- Tier 3: Advanced survival
	[3] = {
		crock_pot = {
			name = "Crock Pot",
			costs = { wood = 15, scrap = 10 },
			result = "portable_stove",
			resultQty = 1,
			description = "Cook advanced recipes. Stew = 45% hunger from 3 carrots.",
		},
		biofuel_processor = {
			name = "Biofuel Processor",
			costs = { wood = 10, scrap = 15 },
			result = "fuel_large",
			resultQty = 2,
			description = "Converts organic materials into campfire fuel.",
		},
		lightning_rod = {
			name = "Lightning Rod",
			costs = { scrap = 12, bolts = 5 },
			result = "lightning_rod",
			resultQty = 1,
			description = "Protects campfire area from lightning strikes.",
		},
		boost_pad = {
			name = "Boost Pad",
			costs = { wood = 8, scrap = 10 },
			result = "boost_pad",
			resultQty = 1,
			description = "Launch pad for quick escape from enemy attacks.",
		},
		good_bed = {
			name = "Good Bed",
			costs = { wood = 10, scrap = 10 },
			result = "good_bed",
			resultQty = 1,
			description = "Best bed. Adds +1 to day multiplier.",
		},
		torch = {
			name = "Torch",
			costs = { wood = 3, scrap = 1 },
			result = "flare",
			resultQty = 3,
			description = "Placeable light source. Creates small safe zones.",
		},
	},

	-- Tier 4: Late-game
	[4] = {
		oil_drill = {
			name = "Oil Drill",
			costs = { scrap = 35, wood = 25, cultist_gem = 1 },
			result = "fuel_large",
			resultQty = 5,
			description = "Automated fuel generation for the campfire.",
		},
		teleporter = {
			name = "Teleporter",
			costs = { scrap = 25, wood = 15, cultist_gem = 1 },
			result = "teleporter",
			resultQty = 1,
			description = "Fast travel between set points.",
		},
		ammo_crate = {
			name = "Ammo Crate",
			costs = { scrap = 20, bolts = 10 },
			result = "rifle_ammo",
			resultQty = 10,
			description = "Produces ammunition over time.",
		},
		giant_bed = {
			name = "Giant Bed",
			costs = { scrap = 30, wood = 20, cultist_gem = 1 },
			result = "giant_bed",
			resultQty = 1,
			description = "Luxurious bed. Maximum day multiplier bonus.",
		},
	},

	-- Tier 5: Endgame
	[5] = {
		respawn_capsule = {
			name = "Respawn Capsule",
			costs = { scrap = 40, wood = 40, forest_gem = 1 },
			result = "respawn_capsule",
			resultQty = 1,
			description = "Instantly revives a dead player when charged.",
		},
		temporal_accelerometer = {
			name = "Temporal Accelerometer",
			costs = { scrap = 40, wood = 40, forest_gem = 1 },
			result = "temporal_accelerometer",
			resultQty = 1,
			description = "Skips one night cycle. Costs 1 Cultist Gem per use.",
		},
		weather_machine = {
			name = "Weather Machine",
			costs = { scrap = 40, wood = 40, forest_gem = 1 },
			result = "weather_machine",
			resultQty = 1,
			description = "Stops storms for 3 days when activated.",
		},
	},
}

------------------------------------------------------------------------
-- Helper: check if player near campfire (for crafting access)
------------------------------------------------------------------------
local function IsNearCampfire(player: Player): boolean
	local IsInSafeZone = game.ServerStorage:FindFirstChild("IsInSafeZone")
	if IsInSafeZone then
		return IsInSafeZone:Invoke(player)
	end
	return true  -- fallback: allow crafting anywhere
end

------------------------------------------------------------------------
-- Grinder: convert junk items to scrap
------------------------------------------------------------------------
GrindItem.OnServerEvent:Connect(function(player, slotIndex)
	if not IsNearCampfire(player) then
		NotifyPlayers:FireClient(player, "Must be near campfire to use grinder.", Color3.fromRGB(255, 100, 100))
		return
	end

	local GetPlayerState = game.ServerStorage:FindFirstChild("GetPlayerState")
	if not GetPlayerState then return end
	local ps = GetPlayerState:Invoke(player)
	if not ps then return end

	local item = ps.inventory[slotIndex]
	if not item then return end

	local itemData = ItemDB.GetItem(item.itemId)
	if not itemData then return end

	-- Check if item is grindable
	local scrapYield = 0
	if itemData.grindable and itemData.scrapYield then
		scrapYield = itemData.scrapYield
	elseif item.itemId == "scrap_metal" then
		scrapYield = 1
	else
		NotifyPlayers:FireClient(player, "Can't grind this item.", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Remove the item
	local RemoveItem = game.ServerStorage:FindFirstChild("RemovePlayerItem")
	if RemoveItem then
		RemoveItem:Invoke(player, slotIndex, 1)
	end

	-- Add scrap to player
	local AddItem = game.ServerStorage:FindFirstChild("AddPlayerItem")
	if AddItem then
		AddItem:Invoke(player, "scrap", scrapYield)
	end

	NotifyPlayers:FireClient(player,
		"Ground " .. itemData.name .. " into " .. scrapYield .. " Scrap",
		Color3.fromRGB(200, 200, 100)
	)
end)

------------------------------------------------------------------------
-- Craft Item
------------------------------------------------------------------------
CraftItem.OnServerEvent:Connect(function(player, recipeId)
	if not IsNearCampfire(player) then
		NotifyPlayers:FireClient(player, "Must be near campfire to craft.", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Find recipe across all unlocked tiers
	local recipe = nil
	for tier = 1, CraftingState.benchTier do
		if Recipes[tier] and Recipes[tier][recipeId] then
			recipe = Recipes[tier][recipeId]
			break
		end
	end

	if not recipe then
		NotifyPlayers:FireClient(player, "Recipe not available at current bench tier.", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Check costs
	local CountItem = game.ServerStorage:FindFirstChild("CountPlayerItem")
	local RemoveById = game.ServerStorage:FindFirstChild("RemovePlayerItemById")
	local AddItem = game.ServerStorage:FindFirstChild("AddPlayerItem")
	if not CountItem or not RemoveById or not AddItem then return end

	for itemId, needed in pairs(recipe.costs) do
		local have = CountItem:Invoke(player, itemId)
		if have < needed then
			local itemName = ItemDB.GetItem(itemId) and ItemDB.GetItem(itemId).name or itemId
			NotifyPlayers:FireClient(player,
				"Need " .. needed .. "x " .. itemName .. " (have " .. have .. ")",
				Color3.fromRGB(255, 100, 100)
			)
			return
		end
	end

	-- Check inventory space for result
	local HasRoom = game.ServerStorage:FindFirstChild("HasPlayerRoom")
	if HasRoom and not HasRoom:Invoke(player, recipe.result, recipe.resultQty) then
		NotifyPlayers:FireClient(player, "Inventory full!", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Consume materials
	for itemId, needed in pairs(recipe.costs) do
		RemoveById:Invoke(player, itemId, needed)
	end

	-- Give crafted item
	AddItem:Invoke(player, recipe.result, recipe.resultQty)

	NotifyPlayers:FireClient(player,
		"Crafted " .. recipe.name .. "!",
		Color3.fromRGB(100, 255, 100)
	)

	CraftingUpdate:FireClient(player, "Crafted", {
		recipeId = recipeId,
		itemId = recipe.result,
		quantity = recipe.resultQty,
	})
end)

------------------------------------------------------------------------
-- Upgrade Crafting Bench
------------------------------------------------------------------------
UpgradeBench.OnServerEvent:Connect(function(player)
	if not IsNearCampfire(player) then
		NotifyPlayers:FireClient(player, "Must be near campfire to upgrade.", Color3.fromRGB(255, 100, 100))
		return
	end

	local nextTier = CraftingState.benchTier + 1
	if nextTier > Config.CraftingBench.MaxTier then
		NotifyPlayers:FireClient(player, "Crafting Bench is already max level!", Color3.fromRGB(255, 200, 50))
		return
	end

	local costs = Config.CraftingBench.UpgradeCosts[nextTier]
	if not costs then return end

	local CountItem = game.ServerStorage:FindFirstChild("CountPlayerItem")
	local RemoveById = game.ServerStorage:FindFirstChild("RemovePlayerItemById")
	if not CountItem or not RemoveById then return end

	-- Verify materials
	for itemId, needed in pairs(costs) do
		local have = CountItem:Invoke(player, itemId)
		if have < needed then
			local itemName = ItemDB.GetItem(itemId) and ItemDB.GetItem(itemId).name or itemId
			NotifyPlayers:FireClient(player,
				"Need " .. needed .. "x " .. itemName,
				Color3.fromRGB(255, 100, 100)
			)
			return
		end
	end

	-- Consume materials
	for itemId, needed in pairs(costs) do
		RemoveById:Invoke(player, itemId, needed)
	end

	CraftingState.benchTier = nextTier

	NotifyPlayers:FireAllClients(
		player.Name .. " upgraded Crafting Bench to Tier " .. nextTier .. "!",
		Color3.fromRGB(255, 200, 0)
	)

	CraftingUpdate:FireAllClients("BenchUpgraded", {
		tier = nextTier,
	})
end)

------------------------------------------------------------------------
-- Expose state
------------------------------------------------------------------------
local GetBenchTier = Instance.new("BindableFunction")
GetBenchTier.Name = "GetBenchTier"
GetBenchTier.Parent = game.ServerStorage
GetBenchTier.OnInvoke = function()
	return CraftingState.benchTier
end

local GetRecipes = Instance.new("BindableFunction")
GetRecipes.Name = "GetCraftingRecipes"
GetRecipes.Parent = game.ServerStorage
GetRecipes.OnInvoke = function()
	local available = {}
	for tier = 1, CraftingState.benchTier do
		if Recipes[tier] then
			for id, recipe in pairs(Recipes[tier]) do
				available[id] = recipe
				available[id].tier = tier
			end
		end
	end
	return available
end
