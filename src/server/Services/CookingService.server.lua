--[[
	CookingService.server.lua
	Handles cooking interactions, recipe validation, and meal creation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local ItemDatabase = require(Modules.ItemDatabase)
local RecipeDatabase = require(Modules.RecipeDatabase)
local Utils = require(Modules.Utils)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CookRequest = Remotes:WaitForChild("CookRequest")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")

------------------------------------------------------------------------
-- Helper: Get player state
------------------------------------------------------------------------
local function GetPlayerState(player)
	local getter = game.ServerStorage:FindFirstChild("GetPlayerState")
	if getter then return getter:Invoke(player) end
	return nil
end

local function GetGameState()
	local getter = game.ServerStorage:FindFirstChild("GetGameState")
	if getter then return getter:Invoke() end
	return nil
end

------------------------------------------------------------------------
-- Cooking Station Management
------------------------------------------------------------------------
-- Cooking stations in the game world are tagged parts:
--   Tag: "CookingStation"
--   Attribute "StationType": "Campfire" | "Stove" | "FullKitchen"
--   Attribute "Built": true/false

local ActiveCookingSessions = {}  -- [player] = { recipeId, startTime, stationPart }

------------------------------------------------------------------------
-- Build Cooking Station
------------------------------------------------------------------------
local function BuildCookingStation(player: Player, stationType: string, inventorySlotIndex: number)
	local playerState = GetPlayerState(player)
	local gameState = GetGameState()
	if not playerState or not gameState then return end

	local invSlot = playerState.inventory[inventorySlotIndex]
	if not invSlot then return end

	local itemData = ItemDatabase.GetItem(invSlot.itemId)
	if not itemData or itemData.category ~= Enums.ItemCategory.CookingStation then
		NotifyPlayers:FireClient(player, "That's not a cooking station item.", Color3.fromRGB(255, 100, 100))
		return
	end

	if itemData.stationType ~= stationType then
		NotifyPlayers:FireClient(player, "Wrong station type.", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Check if station already built
	if gameState.house.cookingStations[stationType] then
		NotifyPlayers:FireClient(player, stationType .. " is already built.", Color3.fromRGB(255, 200, 100))
		return
	end

	-- Build it
	gameState.house.cookingStations[stationType] = true

	-- Remove item from inventory
	invSlot.quantity -= 1
	if invSlot.quantity <= 0 then
		table.remove(playerState.inventory, inventorySlotIndex)
	end

	-- Activate the physical station in the world
	local stationParts = CollectionService:GetTagged("CookingStation")
	for _, part in ipairs(stationParts) do
		if part:GetAttribute("StationType") == stationType then
			part:SetAttribute("Built", true)
			part.Transparency = 0

			-- Add proximity prompt
			local prompt = part:FindFirstChildOfClass("ProximityPrompt")
			if not prompt then
				prompt = Instance.new("ProximityPrompt")
				prompt.ActionText = "Cook"
				prompt.ObjectText = stationType
				prompt.MaxActivationDistance = 8
				prompt.HoldDuration = 0.5
				prompt.Parent = part
			end
			prompt.Enabled = true
			break
		end
	end

	UpdateHUD:FireClient(player, "InventoryUpdate", playerState.inventory)
	NotifyPlayers:FireAllClients(
		stationType .. " has been built!",
		Color3.fromRGB(100, 255, 100)
	)
end

------------------------------------------------------------------------
-- Get Available Recipes for Player at Station
------------------------------------------------------------------------
local function GetAvailableRecipes(player: Player, stationType: string): { any }
	local playerState = GetPlayerState(player)
	if not playerState then return {} end

	local itemCounts = {}
	for _, slot in ipairs(playerState.inventory) do
		itemCounts[slot.itemId] = (itemCounts[slot.itemId] or 0) + slot.quantity
	end

	local available = {}

	for recipeId, known in pairs(playerState.knownRecipes) do
		if not known then continue end

		local recipe = RecipeDatabase.GetRecipe(recipeId)
		if not recipe then continue end

		-- Check station requirement
		if not RecipeDatabase.CanCookAt(recipe, stationType) then continue end

		-- Check ingredients
		local hasAll = RecipeDatabase.HasIngredients(recipeId, itemCounts)

		table.insert(available, {
			recipeId = recipeId,
			name = recipe.name,
			description = recipe.description,
			ingredients = recipe.ingredients,
			result = recipe.result,
			cookTime = recipe.cookTime,
			canCook = hasAll,
		})
	end

	return available
end

------------------------------------------------------------------------
-- Start Cooking
------------------------------------------------------------------------
local function StartCooking(player: Player, recipeId: string, stationPart: BasePart?)
	local playerState = GetPlayerState(player)
	if not playerState then return end

	-- Check if already cooking
	if ActiveCookingSessions[player] then
		NotifyPlayers:FireClient(player, "Already cooking something!", Color3.fromRGB(255, 200, 100))
		return
	end

	-- Validate recipe
	local recipe = RecipeDatabase.GetRecipe(recipeId)
	if not recipe then
		NotifyPlayers:FireClient(player, "Unknown recipe.", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Check if player knows recipe
	if not playerState.knownRecipes[recipeId] then
		NotifyPlayers:FireClient(player, "You don't know this recipe yet.", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Determine station type
	local stationType = stationPart and stationPart:GetAttribute("StationType") or "Campfire"

	-- Check station requirement
	if not RecipeDatabase.CanCookAt(recipe, stationType) then
		NotifyPlayers:FireClient(player,
			"Need at least a " .. recipe.requiredStation .. " to cook this.",
			Color3.fromRGB(255, 100, 100))
		return
	end

	-- Check ingredients
	local itemCounts = {}
	for _, slot in ipairs(playerState.inventory) do
		itemCounts[slot.itemId] = (itemCounts[slot.itemId] or 0) + slot.quantity
	end

	if not RecipeDatabase.HasIngredients(recipeId, itemCounts) then
		NotifyPlayers:FireClient(player, "Missing ingredients!", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Consume ingredients
	local ingredientCounts = {}
	for _, ingId in ipairs(recipe.ingredients) do
		ingredientCounts[ingId] = (ingredientCounts[ingId] or 0) + 1
	end

	for ingId, count in pairs(ingredientCounts) do
		local remaining = count
		for i = #playerState.inventory, 1, -1 do
			local slot = playerState.inventory[i]
			if slot.itemId == ingId then
				local toRemove = math.min(remaining, slot.quantity)
				slot.quantity -= toRemove
				remaining -= toRemove
				if slot.quantity <= 0 then
					table.remove(playerState.inventory, i)
				end
				if remaining <= 0 then break end
			end
		end
	end

	UpdateHUD:FireClient(player, "InventoryUpdate", playerState.inventory)

	-- Start cooking timer
	ActiveCookingSessions[player] = {
		recipeId = recipeId,
		startTime = tick(),
		cookTime = recipe.cookTime,
		stationPart = stationPart,
	}

	NotifyPlayers:FireClient(player,
		"Cooking " .. recipe.name .. "... (" .. recipe.cookTime .. "s)",
		Color3.fromRGB(255, 200, 50)
	)
	UpdateHUD:FireClient(player, "CookingStarted", {
		recipeName = recipe.name,
		cookTime = recipe.cookTime,
	})

	-- Cooking completion
	task.delay(recipe.cookTime, function()
		local session = ActiveCookingSessions[player]
		if not session or session.recipeId ~= recipeId then return end

		ActiveCookingSessions[player] = nil

		-- Add cooked item to inventory
		local resultItem = recipe.result
		local resultCount = recipe.resultCount or 1
		local currentState = GetPlayerState(player)
		if not currentState then return end

		-- Check room
		local totalSlots = 0
		for _ in ipairs(currentState.inventory) do totalSlots += 1 end

		if totalSlots < currentState.maxSlots then
			-- Find existing stack or create new
			local added = false
			local resultData = ItemDatabase.GetItem(resultItem)

			if resultData and resultData.stackable then
				for _, slot in ipairs(currentState.inventory) do
					if slot.itemId == resultItem and slot.quantity < resultData.maxStack then
						local canAdd = math.min(resultCount, resultData.maxStack - slot.quantity)
						slot.quantity += canAdd
						resultCount -= canAdd
						if resultCount <= 0 then
							added = true
							break
						end
					end
				end
			end

			if not added or resultCount > 0 then
				table.insert(currentState.inventory, {
					itemId = resultItem,
					quantity = resultCount,
					spoilDay = resultData and resultData.spoilDays or 3,
					pickedUpDay = 0,
				})
			end

			UpdateHUD:FireClient(player, "InventoryUpdate", currentState.inventory)
			UpdateHUD:FireClient(player, "CookingComplete", recipe.name)
			NotifyPlayers:FireClient(player,
				recipe.name .. " is ready!",
				Color3.fromRGB(100, 255, 100)
			)
		else
			NotifyPlayers:FireClient(player,
				"Inventory full! " .. recipe.name .. " was lost!",
				Color3.fromRGB(255, 0, 0)
			)
		end
	end)
end

------------------------------------------------------------------------
-- Remote Handler
------------------------------------------------------------------------
CookRequest.OnServerEvent:Connect(function(player, action, ...)
	if action == "GetRecipes" then
		local stationType = ...
		local recipes = GetAvailableRecipes(player, stationType or "Campfire")
		UpdateHUD:FireClient(player, "RecipeList", recipes)

	elseif action == "Cook" then
		local recipeId, stationPart = ...
		StartCooking(player, recipeId, stationPart)

	elseif action == "BuildStation" then
		local stationType, inventorySlotIndex = ...
		BuildCookingStation(player, stationType, inventorySlotIndex)
	end
end)

-- Cleanup on player leave
Players.PlayerRemoving:Connect(function(player)
	ActiveCookingSessions[player] = nil
end)

print("[CookingService] Initialized")
