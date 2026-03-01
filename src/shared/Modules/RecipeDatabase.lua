--[[
	RecipeDatabase.lua
	All cooking recipes for The Purge: Suburban Survival
]]

local Enums = require(script.Parent.Enums)

local RecipeDatabase = {}

RecipeDatabase.Recipes = {
	heated_beans = {
		id = "heated_beans",
		name = "Heated Beans",
		ingredients = { "canned_beans" },
		result = "heated_beans",
		resultCount = 1,
		requiredStation = Enums.CookingStation.Campfire,  -- minimum station
		cookTime = 5,  -- seconds
		description = "Heat up a can of beans for a warm meal.",
		starterRecipe = true,  -- known from the start
	},
	roasted_rabbit = {
		id = "roasted_rabbit",
		name = "Roasted Rabbit",
		ingredients = { "raw_rabbit" },
		result = "roasted_rabbit",
		resultCount = 1,
		requiredStation = Enums.CookingStation.Campfire,
		cookTime = 8,
		description = "Roast a rabbit over the fire until golden.",
		starterRecipe = true,
	},
	herb_tea = {
		id = "herb_tea",
		name = "Herb Tea",
		ingredients = { "herbs", "bottled_water" },
		result = "herb_tea",
		resultCount = 1,
		requiredStation = Enums.CookingStation.Campfire,
		cookTime = 4,
		description = "Brew a calming herbal tea.",
		starterRecipe = false,
	},
	roasted_bird = {
		id = "roasted_bird",
		name = "Roasted Bird",
		ingredients = { "raw_bird" },
		result = "roasted_rabbit",  -- same result as rabbit (small game)
		resultCount = 1,
		requiredStation = Enums.CookingStation.Campfire,
		cookTime = 7,
		description = "Roast a game bird over the fire.",
		starterRecipe = true,
	},
	grilled_fish = {
		id = "grilled_fish",
		name = "Grilled Fish",
		ingredients = { "raw_fish" },
		result = "roasted_rabbit",  -- simple cooked fish (reuses stats)
		resultCount = 1,
		requiredStation = Enums.CookingStation.Campfire,
		cookTime = 6,
		description = "Grill a fresh fish over the campfire.",
		starterRecipe = true,
	},
	venison_stew = {
		id = "venison_stew",
		name = "Venison Stew",
		ingredients = { "raw_venison", "potato", "carrot" },
		result = "venison_stew",
		resultCount = 1,
		requiredStation = Enums.CookingStation.Stove,
		cookTime = 15,
		description = "A hearty stew with venison and root vegetables.",
		starterRecipe = false,
	},
	fish_tacos = {
		id = "fish_tacos",
		name = "Fish Tacos",
		ingredients = { "raw_fish", "flour", "spices" },
		result = "fish_tacos",
		resultCount = 2,
		requiredStation = Enums.CookingStation.Stove,
		cookTime = 12,
		description = "Crispy fried fish in flour tortillas with seasoning.",
		starterRecipe = false,
	},
	meat_stir_fry = {
		id = "meat_stir_fry",
		name = "Meat Stir Fry",
		ingredients = { "raw_meat", "vegetables", "cooking_oil" },
		result = "venison_stew",  -- similar stats
		resultCount = 1,
		requiredStation = Enums.CookingStation.Stove,
		cookTime = 10,
		description = "Quick stir-fried meat with fresh vegetables.",
		starterRecipe = false,
	},
	vegetable_soup = {
		id = "vegetable_soup",
		name = "Vegetable Soup",
		ingredients = { "vegetables", "potato", "bottled_water" },
		result = "herb_tea",  -- light meal, similar buff
		resultCount = 2,
		requiredStation = Enums.CookingStation.Stove,
		cookTime = 10,
		description = "A simple nourishing vegetable soup.",
		starterRecipe = false,
	},
	power_meal = {
		id = "power_meal",
		name = "Power Meal",
		ingredients = { "steak", "vegetables", "exotic_spices" },
		result = "power_meal",
		resultCount = 1,
		requiredStation = Enums.CookingStation.FullKitchen,
		cookTime = 20,
		description = "The ultimate performance meal for peak survival.",
		starterRecipe = false,
	},
	gourmet_fish = {
		id = "gourmet_fish",
		name = "Gourmet Fish",
		ingredients = { "fresh_fish", "exotic_spices", "cooking_oil" },
		result = "fish_tacos",  -- similar tier
		resultCount = 1,
		requiredStation = Enums.CookingStation.FullKitchen,
		cookTime = 15,
		description = "Restaurant-quality fish prepared with exotic spices.",
		starterRecipe = false,
	},
}

-- Station hierarchy for checking if a station meets requirements
local stationLevel = {
	[Enums.CookingStation.Campfire] = 1,
	[Enums.CookingStation.Stove] = 2,
	[Enums.CookingStation.FullKitchen] = 3,
}

function RecipeDatabase.CanCookAt(recipe, stationType: string): boolean
	local required = stationLevel[recipe.requiredStation] or 1
	local available = stationLevel[stationType] or 1
	return available >= required
end

function RecipeDatabase.GetStarterRecipes(): { string }
	local result = {}
	for id, recipe in pairs(RecipeDatabase.Recipes) do
		if recipe.starterRecipe then
			table.insert(result, id)
		end
	end
	return result
end

function RecipeDatabase.GetRecipe(recipeId: string)
	return RecipeDatabase.Recipes[recipeId]
end

-- Check if player has all ingredients
function RecipeDatabase.HasIngredients(recipeId: string, inventory: { [string]: number }): boolean
	local recipe = RecipeDatabase.Recipes[recipeId]
	if not recipe then return false end

	-- Count required ingredients
	local needed = {}
	for _, ingredientId in ipairs(recipe.ingredients) do
		needed[ingredientId] = (needed[ingredientId] or 0) + 1
	end

	-- Check inventory
	for itemId, count in pairs(needed) do
		if not inventory[itemId] or inventory[itemId] < count then
			return false
		end
	end
	return true
end

return RecipeDatabase
