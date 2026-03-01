--[[
	ItemVisuals.lua
	Defines visual appearance for every item so loot looks like
	what it actually is (canned food, weapons, tools, etc.)
	instead of generic colored cubes.
]]

local ItemVisuals = {}

-- Shape constants (maps to Enum.PartType)
local BLOCK = "Block"
local CYLINDER = "Cylinder"
local BALL = "Ball"

------------------------------------------------------------------------
-- Per-item visual definitions
-- shape: Part shape (Block, Cylinder, Ball)
-- size: Vector3 dimensions
-- color: Color3 appearance
-- material: Enum.Material
-- glow: optional, adds PointLight for rare/special items
------------------------------------------------------------------------
ItemVisuals.Items = {
	------------------------------------------------------------------------
	-- FOOD - Canned / Packaged
	------------------------------------------------------------------------
	canned_beans = {
		shape = CYLINDER,
		size = Vector3.new(0.8, 0.8, 0.8),
		color = Color3.fromRGB(50, 100, 60),
		material = Enum.Material.Metal,
		label = "Beans",
	},
	stale_bread = {
		shape = BLOCK,
		size = Vector3.new(1.2, 0.5, 0.6),
		color = Color3.fromRGB(180, 150, 90),
		material = Enum.Material.Fabric,
	},
	crackers = {
		shape = BLOCK,
		size = Vector3.new(0.8, 1.0, 0.3),
		color = Color3.fromRGB(200, 170, 100),
		material = Enum.Material.Cardboard,
	},
	bottled_water = {
		shape = CYLINDER,
		size = Vector3.new(0.5, 1.2, 0.5),
		color = Color3.fromRGB(100, 160, 220),
		material = Enum.Material.Glass,
		transparency = 0.3,
	},
	mre = {
		shape = BLOCK,
		size = Vector3.new(1.0, 0.6, 0.8),
		color = Color3.fromRGB(90, 85, 70),
		material = Enum.Material.Fabric,
	},
	energy_drink = {
		shape = CYLINDER,
		size = Vector3.new(0.4, 1.0, 0.4),
		color = Color3.fromRGB(0, 200, 100),
		material = Enum.Material.Metal,
		glow = Color3.fromRGB(0, 255, 100),
	},

	------------------------------------------------------------------------
	-- FOOD - Raw Meats
	------------------------------------------------------------------------
	raw_rabbit = {
		shape = BLOCK,
		size = Vector3.new(0.8, 0.3, 0.6),
		color = Color3.fromRGB(190, 120, 110),
		material = Enum.Material.SmoothPlastic,
	},
	raw_fish = {
		shape = BLOCK,
		size = Vector3.new(1.2, 0.3, 0.5),
		color = Color3.fromRGB(140, 160, 180),
		material = Enum.Material.SmoothPlastic,
	},
	raw_bird = {
		shape = BLOCK,
		size = Vector3.new(0.7, 0.4, 0.5),
		color = Color3.fromRGB(200, 150, 130),
		material = Enum.Material.SmoothPlastic,
	},
	raw_venison = {
		shape = BLOCK,
		size = Vector3.new(1.0, 0.4, 0.7),
		color = Color3.fromRGB(160, 60, 50),
		material = Enum.Material.SmoothPlastic,
	},
	raw_meat = {
		shape = BLOCK,
		size = Vector3.new(0.9, 0.3, 0.6),
		color = Color3.fromRGB(180, 70, 60),
		material = Enum.Material.SmoothPlastic,
	},

	------------------------------------------------------------------------
	-- FOOD - Produce / Ingredients
	------------------------------------------------------------------------
	vegetables = {
		shape = BALL,
		size = Vector3.new(0.6, 0.6, 0.6),
		color = Color3.fromRGB(50, 140, 40),
		material = Enum.Material.Grass,
	},
	herbs = {
		shape = BLOCK,
		size = Vector3.new(0.5, 0.6, 0.4),
		color = Color3.fromRGB(40, 120, 35),
		material = Enum.Material.LeafyGrass,
	},
	potato = {
		shape = BALL,
		size = Vector3.new(0.6, 0.5, 0.6),
		color = Color3.fromRGB(160, 130, 80),
		material = Enum.Material.Sand,
	},
	carrot = {
		shape = BLOCK,
		size = Vector3.new(0.2, 0.8, 0.2),
		color = Color3.fromRGB(230, 120, 30),
		material = Enum.Material.SmoothPlastic,
	},
	flour = {
		shape = BLOCK,
		size = Vector3.new(0.7, 0.9, 0.4),
		color = Color3.fromRGB(240, 235, 220),
		material = Enum.Material.Fabric,
	},
	spices = {
		shape = CYLINDER,
		size = Vector3.new(0.3, 0.6, 0.3),
		color = Color3.fromRGB(150, 60, 20),
		material = Enum.Material.Glass,
	},
	exotic_spices = {
		shape = CYLINDER,
		size = Vector3.new(0.3, 0.6, 0.3),
		color = Color3.fromRGB(200, 50, 180),
		material = Enum.Material.Glass,
		glow = Color3.fromRGB(200, 50, 180),
	},
	cooking_oil = {
		shape = CYLINDER,
		size = Vector3.new(0.5, 1.0, 0.5),
		color = Color3.fromRGB(220, 190, 60),
		material = Enum.Material.Glass,
		transparency = 0.2,
	},

	------------------------------------------------------------------------
	-- FOOD - Cooked
	------------------------------------------------------------------------
	heated_beans = {
		shape = CYLINDER,
		size = Vector3.new(0.8, 0.6, 0.8),
		color = Color3.fromRGB(140, 80, 40),
		material = Enum.Material.SmoothPlastic,
	},
	roasted_rabbit = {
		shape = BLOCK,
		size = Vector3.new(0.9, 0.4, 0.7),
		color = Color3.fromRGB(120, 70, 30),
		material = Enum.Material.SmoothPlastic,
	},
	venison_stew = {
		shape = CYLINDER,
		size = Vector3.new(0.9, 0.6, 0.9),
		color = Color3.fromRGB(100, 60, 30),
		material = Enum.Material.SmoothPlastic,
	},
	fish_tacos = {
		shape = BLOCK,
		size = Vector3.new(0.8, 0.4, 0.5),
		color = Color3.fromRGB(210, 180, 100),
		material = Enum.Material.SmoothPlastic,
	},
	herb_tea = {
		shape = CYLINDER,
		size = Vector3.new(0.5, 0.7, 0.5),
		color = Color3.fromRGB(80, 140, 60),
		material = Enum.Material.Glass,
		transparency = 0.2,
	},
	power_meal = {
		shape = BLOCK,
		size = Vector3.new(1.0, 0.5, 0.8),
		color = Color3.fromRGB(200, 160, 80),
		material = Enum.Material.SmoothPlastic,
		glow = Color3.fromRGB(255, 200, 50),
	},
	steak = {
		shape = BLOCK,
		size = Vector3.new(0.8, 0.3, 0.6),
		color = Color3.fromRGB(130, 50, 40),
		material = Enum.Material.SmoothPlastic,
	},
	fresh_fish = {
		shape = BLOCK,
		size = Vector3.new(1.2, 0.3, 0.5),
		color = Color3.fromRGB(120, 150, 170),
		material = Enum.Material.SmoothPlastic,
	},

	------------------------------------------------------------------------
	-- WEAPONS - Melee
	------------------------------------------------------------------------
	baseball_bat = {
		shape = BLOCK,
		size = Vector3.new(0.3, 0.3, 2.5),
		color = Color3.fromRGB(140, 100, 55),
		material = Enum.Material.Wood,
	},
	kitchen_knife = {
		shape = BLOCK,
		size = Vector3.new(0.15, 0.1, 1.2),
		color = Color3.fromRGB(180, 180, 190),
		material = Enum.Material.Metal,
	},
	crowbar = {
		shape = BLOCK,
		size = Vector3.new(0.2, 0.2, 2.0),
		color = Color3.fromRGB(60, 60, 70),
		material = Enum.Material.Metal,
	},
	fire_axe = {
		shape = BLOCK,
		size = Vector3.new(0.3, 1.0, 2.2),
		color = Color3.fromRGB(180, 30, 20),
		material = Enum.Material.Metal,
	},

	------------------------------------------------------------------------
	-- WEAPONS - Ranged
	------------------------------------------------------------------------
	pistol = {
		shape = BLOCK,
		size = Vector3.new(0.3, 0.7, 0.9),
		color = Color3.fromRGB(40, 40, 45),
		material = Enum.Material.Metal,
	},
	shotgun = {
		shape = BLOCK,
		size = Vector3.new(0.25, 0.35, 2.5),
		color = Color3.fromRGB(50, 45, 40),
		material = Enum.Material.Metal,
	},
	rifle = {
		shape = BLOCK,
		size = Vector3.new(0.2, 0.35, 3.0),
		color = Color3.fromRGB(45, 50, 45),
		material = Enum.Material.Metal,
	},

	------------------------------------------------------------------------
	-- AMMO
	------------------------------------------------------------------------
	pistol_ammo = {
		shape = BLOCK,
		size = Vector3.new(0.6, 0.4, 0.4),
		color = Color3.fromRGB(170, 150, 60),
		material = Enum.Material.Cardboard,
	},
	shotgun_shells = {
		shape = BLOCK,
		size = Vector3.new(0.7, 0.4, 0.5),
		color = Color3.fromRGB(180, 40, 30),
		material = Enum.Material.Cardboard,
	},
	rifle_ammo = {
		shape = BLOCK,
		size = Vector3.new(0.6, 0.5, 0.4),
		color = Color3.fromRGB(60, 80, 50),
		material = Enum.Material.Cardboard,
	},

	------------------------------------------------------------------------
	-- BUILDING MATERIALS
	------------------------------------------------------------------------
	plywood = {
		shape = BLOCK,
		size = Vector3.new(1.5, 1.2, 0.15),
		color = Color3.fromRGB(180, 150, 90),
		material = Enum.Material.Wood,
	},
	wooden_planks = {
		shape = BLOCK,
		size = Vector3.new(1.5, 0.2, 0.6),
		color = Color3.fromRGB(150, 120, 70),
		material = Enum.Material.Wood,
	},
	duct_tape = {
		shape = CYLINDER,
		size = Vector3.new(0.6, 0.3, 0.6),
		color = Color3.fromRGB(130, 130, 130),
		material = Enum.Material.Fabric,
	},
	nails = {
		shape = BLOCK,
		size = Vector3.new(0.5, 0.3, 0.4),
		color = Color3.fromRGB(120, 120, 130),
		material = Enum.Material.Metal,
	},
	scrap_metal = {
		shape = BLOCK,
		size = Vector3.new(0.8, 0.5, 0.6),
		color = Color3.fromRGB(100, 100, 110),
		material = Enum.Material.CorrodedMetal,
	},
	reinforced_boards = {
		shape = BLOCK,
		size = Vector3.new(1.4, 0.3, 0.8),
		color = Color3.fromRGB(100, 80, 55),
		material = Enum.Material.Wood,
	},
	steel_nails = {
		shape = BLOCK,
		size = Vector3.new(0.4, 0.3, 0.3),
		color = Color3.fromRGB(170, 170, 180),
		material = Enum.Material.Metal,
	},
	chain_lock = {
		shape = CYLINDER,
		size = Vector3.new(0.5, 0.5, 0.5),
		color = Color3.fromRGB(150, 150, 160),
		material = Enum.Material.Metal,
	},
	sandbags = {
		shape = BLOCK,
		size = Vector3.new(1.0, 0.5, 0.6),
		color = Color3.fromRGB(160, 145, 100),
		material = Enum.Material.Fabric,
	},
	steel_panels = {
		shape = BLOCK,
		size = Vector3.new(1.5, 1.0, 0.1),
		color = Color3.fromRGB(160, 160, 170),
		material = Enum.Material.Metal,
	},
	bulletproof_glass = {
		shape = BLOCK,
		size = Vector3.new(1.2, 0.8, 0.1),
		color = Color3.fromRGB(150, 180, 200),
		material = Enum.Material.Glass,
		transparency = 0.3,
	},
	industrial_lock = {
		shape = BLOCK,
		size = Vector3.new(0.4, 0.5, 0.3),
		color = Color3.fromRGB(80, 80, 90),
		material = Enum.Material.Metal,
	},
	steel_door = {
		shape = BLOCK,
		size = Vector3.new(1.2, 1.5, 0.15),
		color = Color3.fromRGB(120, 120, 130),
		material = Enum.Material.Metal,
	},

	------------------------------------------------------------------------
	-- FUEL
	------------------------------------------------------------------------
	fuel_small = {
		shape = CYLINDER,
		size = Vector3.new(0.5, 0.7, 0.5),
		color = Color3.fromRGB(200, 40, 30),
		material = Enum.Material.Metal,
	},
	fuel_medium = {
		shape = CYLINDER,
		size = Vector3.new(0.6, 1.0, 0.6),
		color = Color3.fromRGB(200, 40, 30),
		material = Enum.Material.Metal,
	},
	fuel_large = {
		shape = CYLINDER,
		size = Vector3.new(0.8, 1.2, 0.8),
		color = Color3.fromRGB(200, 40, 30),
		material = Enum.Material.Metal,
	},

	------------------------------------------------------------------------
	-- GENERATOR PARTS
	------------------------------------------------------------------------
	spark_plugs = {
		shape = BLOCK,
		size = Vector3.new(0.4, 0.5, 0.3),
		color = Color3.fromRGB(140, 140, 150),
		material = Enum.Material.Metal,
	},
	wiring = {
		shape = BLOCK,
		size = Vector3.new(0.6, 0.4, 0.6),
		color = Color3.fromRGB(200, 60, 30),
		material = Enum.Material.Fabric,
	},
	fan_belt = {
		shape = CYLINDER,
		size = Vector3.new(0.7, 0.15, 0.7),
		color = Color3.fromRGB(30, 30, 30),
		material = Enum.Material.Fabric,
	},
	industrial_motor = {
		shape = BLOCK,
		size = Vector3.new(0.8, 0.6, 0.6),
		color = Color3.fromRGB(80, 80, 90),
		material = Enum.Material.Metal,
		glow = Color3.fromRGB(80, 120, 255),
	},
	voltage_regulator = {
		shape = BLOCK,
		size = Vector3.new(0.5, 0.6, 0.4),
		color = Color3.fromRGB(60, 70, 60),
		material = Enum.Material.Metal,
	},
	heavy_fuel_tank = {
		shape = CYLINDER,
		size = Vector3.new(1.0, 1.4, 1.0),
		color = Color3.fromRGB(180, 50, 30),
		material = Enum.Material.Metal,
	},
	solar_panel = {
		shape = BLOCK,
		size = Vector3.new(1.5, 0.1, 1.0),
		color = Color3.fromRGB(30, 40, 80),
		material = Enum.Material.Glass,
		glow = Color3.fromRGB(50, 100, 255),
	},

	------------------------------------------------------------------------
	-- TOOLS
	------------------------------------------------------------------------
	flashlight = {
		shape = CYLINDER,
		size = Vector3.new(0.3, 1.0, 0.3),
		color = Color3.fromRGB(40, 40, 45),
		material = Enum.Material.Metal,
	},
	candle = {
		shape = CYLINDER,
		size = Vector3.new(0.2, 0.6, 0.2),
		color = Color3.fromRGB(230, 220, 180),
		material = Enum.Material.SmoothPlastic,
		glow = Color3.fromRGB(255, 200, 100),
	},
	flare = {
		shape = CYLINDER,
		size = Vector3.new(0.2, 0.8, 0.2),
		color = Color3.fromRGB(220, 40, 30),
		material = Enum.Material.Neon,
	},
	glow_stick = {
		shape = CYLINDER,
		size = Vector3.new(0.15, 0.8, 0.15),
		color = Color3.fromRGB(50, 255, 100),
		material = Enum.Material.Neon,
		glow = Color3.fromRGB(50, 255, 100),
	},
	lockpick = {
		shape = BLOCK,
		size = Vector3.new(0.1, 0.1, 0.8),
		color = Color3.fromRGB(150, 150, 160),
		material = Enum.Material.Metal,
	},
	fishing_rod = {
		shape = BLOCK,
		size = Vector3.new(0.15, 0.15, 2.5),
		color = Color3.fromRGB(100, 80, 50),
		material = Enum.Material.Wood,
	},
	snare_trap = {
		shape = BLOCK,
		size = Vector3.new(0.6, 0.4, 0.6),
		color = Color3.fromRGB(120, 100, 70),
		material = Enum.Material.Fabric,
	},

	------------------------------------------------------------------------
	-- TRAPS
	------------------------------------------------------------------------
	noise_maker = {
		shape = CYLINDER,
		size = Vector3.new(0.4, 0.4, 0.4),
		color = Color3.fromRGB(200, 200, 50),
		material = Enum.Material.Metal,
	},
	spike_strip = {
		shape = BLOCK,
		size = Vector3.new(1.2, 0.15, 0.6),
		color = Color3.fromRGB(80, 80, 90),
		material = Enum.Material.Metal,
	},
	tripwire = {
		shape = BLOCK,
		size = Vector3.new(0.3, 0.3, 0.8),
		color = Color3.fromRGB(100, 100, 50),
		material = Enum.Material.Fabric,
	},
	turret_components = {
		shape = BLOCK,
		size = Vector3.new(0.8, 0.6, 0.8),
		color = Color3.fromRGB(60, 60, 70),
		material = Enum.Material.Metal,
		glow = Color3.fromRGB(180, 0, 255),
	},
	electric_fence_kit = {
		shape = BLOCK,
		size = Vector3.new(0.8, 0.6, 0.5),
		color = Color3.fromRGB(220, 200, 50),
		material = Enum.Material.Metal,
		glow = Color3.fromRGB(255, 255, 50),
	},

	------------------------------------------------------------------------
	-- BACKPACKS
	------------------------------------------------------------------------
	small_backpack = {
		shape = BLOCK,
		size = Vector3.new(0.9, 1.0, 0.5),
		color = Color3.fromRGB(60, 100, 60),
		material = Enum.Material.Fabric,
	},
	medium_backpack = {
		shape = BLOCK,
		size = Vector3.new(1.0, 1.2, 0.6),
		color = Color3.fromRGB(80, 60, 40),
		material = Enum.Material.Fabric,
		glow = Color3.fromRGB(0, 120, 255),
	},
	large_backpack = {
		shape = BLOCK,
		size = Vector3.new(1.1, 1.4, 0.7),
		color = Color3.fromRGB(50, 60, 50),
		material = Enum.Material.Fabric,
		glow = Color3.fromRGB(180, 0, 255),
	},

	------------------------------------------------------------------------
	-- SEEDS
	------------------------------------------------------------------------
	tomato_seed = {
		shape = BLOCK,
		size = Vector3.new(0.4, 0.5, 0.2),
		color = Color3.fromRGB(180, 50, 30),
		material = Enum.Material.Cardboard,
	},
	potato_seed = {
		shape = BLOCK,
		size = Vector3.new(0.4, 0.5, 0.2),
		color = Color3.fromRGB(160, 130, 70),
		material = Enum.Material.Cardboard,
	},
	herb_seed = {
		shape = BLOCK,
		size = Vector3.new(0.4, 0.5, 0.2),
		color = Color3.fromRGB(50, 130, 40),
		material = Enum.Material.Cardboard,
	},

	------------------------------------------------------------------------
	-- COOKING STATIONS
	------------------------------------------------------------------------
	campfire_kit = {
		shape = BLOCK,
		size = Vector3.new(0.8, 0.5, 0.6),
		color = Color3.fromRGB(120, 80, 40),
		material = Enum.Material.Wood,
	},
	stove_parts = {
		shape = BLOCK,
		size = Vector3.new(0.7, 0.6, 0.5),
		color = Color3.fromRGB(100, 100, 110),
		material = Enum.Material.Metal,
	},
	kitchen_parts = {
		shape = BLOCK,
		size = Vector3.new(0.9, 0.6, 0.6),
		color = Color3.fromRGB(160, 160, 165),
		material = Enum.Material.Metal,
		glow = Color3.fromRGB(80, 120, 255),
	},

	------------------------------------------------------------------------
	-- RECIPES (paper/book items)
	------------------------------------------------------------------------
	recipe_heated_beans = {
		shape = BLOCK,
		size = Vector3.new(0.6, 0.05, 0.4),
		color = Color3.fromRGB(220, 210, 180),
		material = Enum.Material.SmoothPlastic,
	},
	recipe_roasted_rabbit = {
		shape = BLOCK,
		size = Vector3.new(0.6, 0.05, 0.4),
		color = Color3.fromRGB(220, 210, 180),
		material = Enum.Material.SmoothPlastic,
	},
	recipe_venison_stew = {
		shape = BLOCK,
		size = Vector3.new(0.6, 0.05, 0.4),
		color = Color3.fromRGB(220, 210, 180),
		material = Enum.Material.SmoothPlastic,
	},
	recipe_fish_tacos = {
		shape = BLOCK,
		size = Vector3.new(0.6, 0.05, 0.4),
		color = Color3.fromRGB(220, 210, 180),
		material = Enum.Material.SmoothPlastic,
	},
	recipe_herb_tea = {
		shape = BLOCK,
		size = Vector3.new(0.6, 0.05, 0.4),
		color = Color3.fromRGB(200, 220, 180),
		material = Enum.Material.SmoothPlastic,
	},
	recipe_power_meal = {
		shape = BLOCK,
		size = Vector3.new(0.6, 0.05, 0.4),
		color = Color3.fromRGB(255, 230, 180),
		material = Enum.Material.SmoothPlastic,
		glow = Color3.fromRGB(255, 200, 50),
	},
}

------------------------------------------------------------------------
-- Category defaults (fallback for items without specific definitions)
------------------------------------------------------------------------
ItemVisuals.CategoryDefaults = {
	Food = {
		shape = BLOCK,
		size = Vector3.new(0.7, 0.5, 0.5),
		color = Color3.fromRGB(160, 130, 80),
		material = Enum.Material.SmoothPlastic,
	},
	Weapon = {
		shape = BLOCK,
		size = Vector3.new(0.3, 0.3, 1.5),
		color = Color3.fromRGB(80, 80, 90),
		material = Enum.Material.Metal,
	},
	Ammo = {
		shape = BLOCK,
		size = Vector3.new(0.5, 0.4, 0.4),
		color = Color3.fromRGB(160, 140, 60),
		material = Enum.Material.Cardboard,
	},
	BuildingMaterial = {
		shape = BLOCK,
		size = Vector3.new(1.0, 0.5, 0.5),
		color = Color3.fromRGB(140, 120, 80),
		material = Enum.Material.Wood,
	},
	Fuel = {
		shape = CYLINDER,
		size = Vector3.new(0.6, 0.8, 0.6),
		color = Color3.fromRGB(200, 40, 30),
		material = Enum.Material.Metal,
	},
	Tool = {
		shape = BLOCK,
		size = Vector3.new(0.3, 0.3, 1.0),
		color = Color3.fromRGB(100, 90, 70),
		material = Enum.Material.Metal,
	},
	Trap = {
		shape = BLOCK,
		size = Vector3.new(0.6, 0.4, 0.6),
		color = Color3.fromRGB(120, 110, 60),
		material = Enum.Material.Metal,
	},
	LightSource = {
		shape = CYLINDER,
		size = Vector3.new(0.25, 0.7, 0.25),
		color = Color3.fromRGB(200, 190, 100),
		material = Enum.Material.SmoothPlastic,
	},
	GeneratorPart = {
		shape = BLOCK,
		size = Vector3.new(0.6, 0.5, 0.5),
		color = Color3.fromRGB(100, 100, 110),
		material = Enum.Material.Metal,
	},
	CookingStation = {
		shape = BLOCK,
		size = Vector3.new(0.8, 0.5, 0.6),
		color = Color3.fromRGB(120, 100, 70),
		material = Enum.Material.Metal,
	},
	Seed = {
		shape = BLOCK,
		size = Vector3.new(0.4, 0.5, 0.2),
		color = Color3.fromRGB(140, 120, 60),
		material = Enum.Material.Cardboard,
	},
	Recipe = {
		shape = BLOCK,
		size = Vector3.new(0.6, 0.05, 0.4),
		color = Color3.fromRGB(220, 210, 180),
		material = Enum.Material.SmoothPlastic,
	},
	Backpack = {
		shape = BLOCK,
		size = Vector3.new(0.9, 1.0, 0.5),
		color = Color3.fromRGB(70, 90, 60),
		material = Enum.Material.Fabric,
	},
}

------------------------------------------------------------------------
-- Get visual definition for an item (falls back to category default)
------------------------------------------------------------------------
function ItemVisuals.GetVisual(itemId: string, category: string?)
	local specific = ItemVisuals.Items[itemId]
	if specific then return specific end

	if category then
		local catDefault = ItemVisuals.CategoryDefaults[category]
		if catDefault then return catDefault end
	end

	-- Ultimate fallback
	return {
		shape = BLOCK,
		size = Vector3.new(0.6, 0.6, 0.6),
		color = Color3.fromRGB(180, 180, 180),
		material = Enum.Material.SmoothPlastic,
	}
end

return ItemVisuals
