--[[
	MapBuilder.server.lua
	Procedurally generates the suburban neighborhood map at runtime.
	Creates: streets, houses (Zone 1-3), bonus locations, starter house,
	spawn points, and all interactable tagged objects.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)

local MapFolder = workspace:WaitForChild("Map")

------------------------------------------------------------------------
-- Material Palette
------------------------------------------------------------------------
local Materials = {
	Road = { material = Enum.Material.Asphalt, color = Color3.fromRGB(50, 50, 55) },
	Sidewalk = { material = Enum.Material.Concrete, color = Color3.fromRGB(160, 160, 155) },
	Grass = { material = Enum.Material.Grass, color = Color3.fromRGB(60, 120, 40) },
	HouseWall = { material = Enum.Material.Brick, color = Color3.fromRGB(140, 100, 80) },
	HouseRoof = { material = Enum.Material.Slate, color = Color3.fromRGB(80, 60, 50) },
	Floor = { material = Enum.Material.WoodPlanks, color = Color3.fromRGB(120, 90, 60) },
	RundownWall = { material = Enum.Material.Brick, color = Color3.fromRGB(100, 80, 65) },
	Window = { material = Enum.Material.Glass, color = Color3.fromRGB(150, 180, 200) },
	Door = { material = Enum.Material.Wood, color = Color3.fromRGB(100, 70, 40) },
	Metal = { material = Enum.Material.Metal, color = Color3.fromRGB(140, 140, 145) },
}

------------------------------------------------------------------------
-- Helper: Create a Part
------------------------------------------------------------------------
local function CreatePart(props)
	local part = Instance.new("Part")
	part.Name = props.Name or "Part"
	part.Size = props.Size or Vector3.new(4, 4, 4)
	part.Position = props.Position or Vector3.new(0, 0, 0)
	part.CFrame = props.CFrame or CFrame.new(part.Position)
	part.Anchored = true
	part.CanCollide = props.CanCollide ~= false
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Color = props.Color or Color3.fromRGB(200, 200, 200)
	part.Transparency = props.Transparency or 0
	part.Parent = props.Parent or MapFolder

	if props.Tags then
		for _, tag in ipairs(props.Tags) do
			CollectionService:AddTag(part, tag)
		end
	end

	for key, value in pairs(props.Attributes or {}) do
		part:SetAttribute(key, value)
	end

	return part
end

------------------------------------------------------------------------
-- Create Ground/Terrain
------------------------------------------------------------------------
local function CreateGround()
	-- Main ground plane
	CreatePart({
		Name = "Ground",
		Size = Vector3.new(Config.Map.TotalWidth, 1, Config.Map.TotalLength),
		Position = Vector3.new(0, -0.5, 0),
		Material = Materials.Grass.material,
		Color = Materials.Grass.color,
	})
end

------------------------------------------------------------------------
-- Create a Street
------------------------------------------------------------------------
local function CreateStreet(startPos: Vector3, endPos: Vector3, width: number)
	local dir = (endPos - startPos)
	local length = dir.Magnitude
	local center = (startPos + endPos) / 2

	-- Road surface
	CreatePart({
		Name = "Road",
		Size = Vector3.new(width, 0.2, length),
		CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)),
		Material = Materials.Road.material,
		Color = Materials.Road.color,
	})

	-- Sidewalks
	for _, side in ipairs({ -1, 1 }) do
		CreatePart({
			Name = "Sidewalk",
			Size = Vector3.new(6, 0.3, length),
			CFrame = CFrame.new(center + Vector3.new(side * (width / 2 + 3), 0.15, 0)),
			Material = Materials.Sidewalk.material,
			Color = Materials.Sidewalk.color,
		})
	end
end

------------------------------------------------------------------------
-- Create a House (generic)
------------------------------------------------------------------------
local function CreateHouse(position: Vector3, zone: number, houseIndex: number, isStarter: boolean?)
	local houseFolder = Instance.new("Folder")
	houseFolder.Name = isStarter and "StarterHouse" or ("House_Z" .. zone .. "_" .. houseIndex)
	houseFolder.Parent = MapFolder

	-- House dimensions scale by zone
	local widths = { 20, 26, 36 }
	local depths = { 16, 20, 28 }
	local heights = { 10, 12, 14 }

	local w = isStarter and 22 or (widths[zone] or 20)
	local d = isStarter and 18 or (depths[zone] or 16)
	local h = isStarter and 10 or (heights[zone] or 10)

	local wallColor
	if isStarter then
		wallColor = Materials.RundownWall.color
	else
		wallColor = Color3.fromRGB(
			120 + zone * 20 + math.random(-10, 10),
			90 + zone * 15 + math.random(-10, 10),
			70 + zone * 10 + math.random(-10, 10)
		)
	end

	-- Foundation
	local foundation = CreatePart({
		Name = "Foundation",
		Size = Vector3.new(w + 2, 0.5, d + 2),
		Position = position + Vector3.new(0, 0.25, 0),
		Material = Materials.Sidewalk.material,
		Color = Materials.Sidewalk.color,
		Parent = houseFolder,
	})

	-- Floor
	CreatePart({
		Name = "Floor",
		Size = Vector3.new(w, 0.3, d),
		Position = position + Vector3.new(0, 0.65, 0),
		Material = Materials.Floor.material,
		Color = Materials.Floor.color,
		Parent = houseFolder,
	})

	-- Walls
	local walls = {
		{ name = "WallFront", size = Vector3.new(w, h, 1), offset = Vector3.new(0, h / 2 + 0.5, -d / 2) },
		{ name = "WallBack", size = Vector3.new(w, h, 1), offset = Vector3.new(0, h / 2 + 0.5, d / 2) },
		{ name = "WallLeft", size = Vector3.new(1, h, d), offset = Vector3.new(-w / 2, h / 2 + 0.5, 0) },
		{ name = "WallRight", size = Vector3.new(1, h, d), offset = Vector3.new(w / 2, h / 2 + 0.5, 0) },
	}

	for _, wallData in ipairs(walls) do
		CreatePart({
			Name = wallData.name,
			Size = wallData.size,
			Position = position + wallData.offset,
			Material = Materials.HouseWall.material,
			Color = wallColor,
			Parent = houseFolder,
		})
	end

	-- Roof
	CreatePart({
		Name = "Roof",
		Size = Vector3.new(w + 4, 1, d + 4),
		Position = position + Vector3.new(0, h + 1, 0),
		Material = Materials.HouseRoof.material,
		Color = Materials.HouseRoof.color,
		Parent = houseFolder,
	})

	-- Front door
	local doorPart = CreatePart({
		Name = "FrontDoor",
		Size = Vector3.new(4, 7, 1.2),
		Position = position + Vector3.new(0, 4, -d / 2),
		Material = Materials.Door.material,
		Color = Materials.Door.color,
		Parent = houseFolder,
		Tags = { "FortSlot" },
		Attributes = { SlotName = "FrontDoor" },
	})

	if isStarter then
		doorPart.Transparency = 0.5  -- busted door
	end

	-- Back door
	local backDoor = CreatePart({
		Name = "BackDoor",
		Size = Vector3.new(4, 7, 1.2),
		Position = position + Vector3.new(0, 4, d / 2),
		Material = Materials.Door.material,
		Color = Materials.Door.color,
		Parent = houseFolder,
		Tags = { "FortSlot" },
		Attributes = { SlotName = "BackDoor" },
	})

	-- Windows
	local windowPositions = {
		{ offset = Vector3.new(-w / 4, 5, -d / 2), name = "Window_1" },
		{ offset = Vector3.new(w / 4, 5, -d / 2), name = "Window_2" },
		{ offset = Vector3.new(-w / 2, 5, -d / 4), name = "Window_3" },
		{ offset = Vector3.new(-w / 2, 5, d / 4), name = "Window_4" },
		{ offset = Vector3.new(w / 2, 5, -d / 4), name = "Window_5" },
		{ offset = Vector3.new(w / 2, 5, d / 4), name = "Window_6" },
	}

	for _, winData in ipairs(windowPositions) do
		local windowPart = CreatePart({
			Name = winData.name,
			Size = Vector3.new(3, 3, 0.5),
			Position = position + winData.offset,
			Material = Materials.Window.material,
			Color = Materials.Window.color,
			Transparency = isStarter and 0.7 or 0.3,
			Parent = houseFolder,
			Tags = { "FortSlot" },
			Attributes = { SlotName = winData.name },
		})
	end

	-- Loot containers
	local lootContainerCount = zone == 1 and 2 or (zone == 2 and 3 or 4)
	for i = 1, lootContainerCount do
		local lootOffset = Vector3.new(
			math.random(-w / 3, w / 3),
			1.5,
			math.random(-d / 3, d / 3)
		)
		CreatePart({
			Name = "LootContainer_" .. i,
			Size = Vector3.new(3, 2, 2),
			Position = position + lootOffset,
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(90, 70, 50),
			Parent = houseFolder,
			Tags = { "LootContainer" },
			Attributes = { Zone = zone, ContainerIndex = i },
		})
	end

	-- Tag the house
	if not isStarter then
		CollectionService:AddTag(foundation, "LootableHouse")
		foundation:SetAttribute("Zone", zone)
	end

	-- Starter house specific elements
	if isStarter then
		CollectionService:AddTag(foundation, "StarterHouse")

		-- Generator (garage area)
		local generatorPart = CreatePart({
			Name = "Generator",
			Size = Vector3.new(4, 3, 3),
			Position = position + Vector3.new(w / 2 + 4, 1.5, d / 3),
			Material = Materials.Metal.material,
			Color = Color3.fromRGB(80, 80, 90),
			Parent = houseFolder,
			Tags = { "Generator" },
		})

		-- Garage structure
		CreatePart({
			Name = "Garage",
			Size = Vector3.new(10, 8, 10),
			Position = position + Vector3.new(w / 2 + 6, 4, d / 3),
			Material = Materials.HouseWall.material,
			Color = wallColor,
			Transparency = 0.8,
			Parent = houseFolder,
		})

		-- Cooking station spots
		local campfireSpot = CreatePart({
			Name = "CampfireSpot",
			Size = Vector3.new(3, 0.5, 3),
			Position = position + Vector3.new(0, 0.25, d / 2 + 5),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(60, 60, 60),
			Parent = houseFolder,
			Tags = { "CookingStation" },
			Attributes = { StationType = "Campfire", Built = false },
		})

		local stoveSpot = CreatePart({
			Name = "StoveSpot",
			Size = Vector3.new(3, 3, 2),
			Position = position + Vector3.new(-w / 3, 2, 0),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(140, 140, 140),
			Transparency = 0.5,
			Parent = houseFolder,
			Tags = { "CookingStation" },
			Attributes = { StationType = "Stove", Built = false },
		})

		local kitchenSpot = CreatePart({
			Name = "KitchenSpot",
			Size = Vector3.new(6, 4, 3),
			Position = position + Vector3.new(-w / 3, 2, -d / 3),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(160, 160, 160),
			Transparency = 0.5,
			Parent = houseFolder,
			Tags = { "CookingStation" },
			Attributes = { StationType = "FullKitchen", Built = false },
		})

		-- Wall sections to fortify
		for i = 1, Config.Fortification.WallSectionCount do
			local angle = (i / Config.Fortification.WallSectionCount) * math.pi * 2
			local wx = math.cos(angle) * (w / 2)
			local wz = math.sin(angle) * (d / 2)
			CreatePart({
				Name = "WallSection_" .. i,
				Size = Vector3.new(4, 5, 1),
				Position = position + Vector3.new(wx, 3, wz),
				Material = Materials.HouseWall.material,
				Color = Color3.fromRGB(80, 60, 45),
				Transparency = 0.6,
				Parent = houseFolder,
				Tags = { "FortSlot" },
				Attributes = { SlotName = "Wall_" .. i },
			})
		end

		-- Roof sections
		for i = 1, Config.Fortification.RoofSectionCount do
			CreatePart({
				Name = "RoofSection_" .. i,
				Size = Vector3.new(w / 2, 0.5, d / 2),
				Position = position + Vector3.new((i == 1 and -1 or 1) * w / 4, h + 0.5, 0),
				Material = Materials.HouseRoof.material,
				Color = Color3.fromRGB(60, 45, 35),
				Transparency = 0.5,
				Parent = houseFolder,
				Tags = { "FortSlot" },
				Attributes = { SlotName = "Roof_" .. i },
			})
		end

		-- Player spawn point
		local spawnPart = CreatePart({
			Name = "StarterHouseSpawn",
			Size = Vector3.new(4, 1, 4),
			Position = position + Vector3.new(0, 1, 0),
			Transparency = 1,
			CanCollide = false,
			Parent = workspace,
		})
	end

	return houseFolder
end

------------------------------------------------------------------------
-- Create Bonus Location
------------------------------------------------------------------------
local function CreateBonusLocation(position: Vector3, locationType: string)
	local folder = Instance.new("Folder")
	folder.Name = "Bonus_" .. locationType
	folder.Parent = MapFolder

	local sizes = {
		HardwareStore = Vector3.new(40, 12, 30),
		PoliceStation = Vector3.new(45, 14, 35),
		GasStation = Vector3.new(35, 8, 25),
		AbandonedSchool = Vector3.new(60, 12, 40),
		UndergroundBunker = Vector3.new(20, 8, 20),
	}

	local colors = {
		HardwareStore = Color3.fromRGB(200, 120, 50),
		PoliceStation = Color3.fromRGB(80, 80, 120),
		GasStation = Color3.fromRGB(180, 30, 30),
		AbandonedSchool = Color3.fromRGB(150, 140, 130),
		UndergroundBunker = Color3.fromRGB(60, 60, 60),
	}

	local size = sizes[locationType] or Vector3.new(30, 10, 20)
	local color = colors[locationType] or Color3.fromRGB(150, 150, 150)

	-- Building structure
	CreatePart({
		Name = "Building",
		Size = size,
		Position = position + Vector3.new(0, size.Y / 2, 0),
		Material = Enum.Material.Concrete,
		Color = color,
		Parent = folder,
	})

	-- Roof
	CreatePart({
		Name = "Roof",
		Size = Vector3.new(size.X + 4, 1, size.Z + 4),
		Position = position + Vector3.new(0, size.Y + 0.5, 0),
		Material = Enum.Material.Concrete,
		Color = color * 0.8,
		Parent = folder,
	})

	-- Sign
	local sign = CreatePart({
		Name = "Sign",
		Size = Vector3.new(12, 4, 0.5),
		Position = position + Vector3.new(0, size.Y + 4, -size.Z / 2 - 1),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 255, 200),
		Parent = folder,
	})

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 200, 0, 60)
	billboard.StudsOffset = Vector3.new(0, 0, 0)
	billboard.Parent = sign

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = locationType:gsub("(%u)", " %1"):sub(2)  -- CamelCase to spaces
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = billboard

	-- Loot containers
	local containerCount = locationType == "UndergroundBunker" and 6 or 4
	for i = 1, containerCount do
		local lootOffset = Vector3.new(
			math.random(-size.X / 3, size.X / 3),
			2,
			math.random(-size.Z / 3, size.Z / 3)
		)
		CreatePart({
			Name = "LootContainer_" .. i,
			Size = Vector3.new(3, 2, 2),
			Position = position + lootOffset,
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(90, 70, 50),
			Parent = folder,
			Tags = { "LootContainer" },
			Attributes = {
				Zone = locationType == "UndergroundBunker" and 3 or 2,
				LocationType = locationType,
				ContainerIndex = i,
			},
		})
	end

	-- Tag as lootable house for NPC spawning
	CollectionService:AddTag(folder, "LootableHouse")

	return folder
end

------------------------------------------------------------------------
-- Create Purge Spawn Points
------------------------------------------------------------------------
local function CreateSpawnPoints()
	local spawnFolder = workspace:FindFirstChild("SpawnPoints")
	local radius = Config.Map.PurgeSpawnRadius

	for i = 1, 12 do
		local angle = (i / 12) * math.pi * 2
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius

		CreatePart({
			Name = "PurgeSpawn_" .. i,
			Size = Vector3.new(4, 1, 4),
			Position = Vector3.new(x, 2, z),
			Transparency = 1,
			CanCollide = false,
			Parent = spawnFolder,
		})
	end
end

------------------------------------------------------------------------
-- Create Street Lights
------------------------------------------------------------------------
local function CreateStreetLight(position: Vector3)
	local pole = CreatePart({
		Name = "LightPole",
		Size = Vector3.new(0.5, 12, 0.5),
		Position = position + Vector3.new(0, 6, 0),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(80, 80, 80),
	})

	local lampHead = CreatePart({
		Name = "Lamp",
		Size = Vector3.new(2, 0.5, 2),
		Position = position + Vector3.new(0, 12.5, 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 240, 200),
	})

	local light = Instance.new("PointLight")
	light.Range = 40
	light.Brightness = 1
	light.Color = Color3.fromRGB(255, 240, 200)
	light.Parent = lampHead
end

------------------------------------------------------------------------
-- Build the Complete Map
------------------------------------------------------------------------
local function BuildMap()
	print("[MapBuilder] Building neighborhood map...")

	-- Ground
	CreateGround()

	-- Main streets
	CreateStreet(Vector3.new(0, 0, -600), Vector3.new(0, 0, 600), Config.Map.StreetWidth)
	CreateStreet(Vector3.new(-400, 0, 0), Vector3.new(400, 0, 0), Config.Map.StreetWidth)

	-- Starter house (center)
	local starterPos = Vector3.new(0, 0, 0)
	CreateHouse(starterPos, 1, 0, true)

	-- Zone 1 houses (close to starter)
	local zone1Positions = {
		Vector3.new(-60, 0, -50),
		Vector3.new(60, 0, -50),
		Vector3.new(-60, 0, 50),
		Vector3.new(60, 0, 50),
		Vector3.new(-60, 0, -130),
		Vector3.new(60, 0, -130),
	}

	for i, pos in ipairs(zone1Positions) do
		CreateHouse(pos, 1, i)
	end

	-- Zone 2 houses (next block)
	local zone2Positions = {
		Vector3.new(-160, 0, -180),
		Vector3.new(160, 0, -180),
		Vector3.new(-160, 0, -100),
		Vector3.new(160, 0, -100),
		Vector3.new(-160, 0, 100),
		Vector3.new(160, 0, 100),
		Vector3.new(-160, 0, 180),
		Vector3.new(160, 0, 180),
	}

	for i, pos in ipairs(zone2Positions) do
		CreateHouse(pos, 2, i)
	end

	-- Zone 3 houses (wealthy neighborhood, far end)
	local zone3Positions = {
		Vector3.new(-300, 0, -350),
		Vector3.new(300, 0, -350),
		Vector3.new(-300, 0, -250),
		Vector3.new(300, 0, -250),
		Vector3.new(-300, 0, 250),
		Vector3.new(300, 0, 250),
	}

	for i, pos in ipairs(zone3Positions) do
		CreateHouse(pos, 3, i)
	end

	-- Bonus locations
	CreateBonusLocation(Vector3.new(-350, 0, 0), "HardwareStore")
	CreateBonusLocation(Vector3.new(350, 0, 0), "PoliceStation")
	CreateBonusLocation(Vector3.new(0, 0, 400), "GasStation")
	CreateBonusLocation(Vector3.new(-200, 0, 350), "AbandonedSchool")
	CreateBonusLocation(Vector3.new(250, 0, -450), "UndergroundBunker")

	-- Spawn points for Purge
	CreateSpawnPoints()

	-- Street lights along main roads
	for z = -500, 500, 80 do
		CreateStreetLight(Vector3.new(-25, 0, z))
		CreateStreetLight(Vector3.new(25, 0, z))
	end
	for x = -350, 350, 80 do
		CreateStreetLight(Vector3.new(x, 0, -25))
		CreateStreetLight(Vector3.new(x, 0, 25))
	end

	-- Fishing pond (near map edge)
	local pond = CreatePart({
		Name = "FishingPond",
		Size = Vector3.new(30, 1, 20),
		Position = Vector3.new(-400, -0.3, 350),
		Material = Enum.Material.Water,
		Color = Color3.fromRGB(40, 80, 120),
	})
	CollectionService:AddTag(pond, "FishingSpot")

	print("[MapBuilder] Map generation complete!")
	print("  Zone 1 houses:", #zone1Positions)
	print("  Zone 2 houses:", #zone2Positions)
	print("  Zone 3 houses:", #zone3Positions)
	print("  Bonus locations: 5")
end

------------------------------------------------------------------------
-- Build on startup
------------------------------------------------------------------------
task.defer(BuildMap)
