--[[
	MapBuilder.server.lua
	Procedurally generates a Brookhaven-style suburban neighborhood.
	Houses face the street on proper lots with front yards, driveways,
	walkways, mailboxes, backyard fences, and trees.
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
	Road       = { material = Enum.Material.Asphalt,    color = Color3.fromRGB(50, 50, 55) },
	Sidewalk   = { material = Enum.Material.Concrete,   color = Color3.fromRGB(175, 170, 165) },
	Driveway   = { material = Enum.Material.Concrete,   color = Color3.fromRGB(155, 152, 148) },
	Grass      = { material = Enum.Material.Grass,       color = Color3.fromRGB(60, 120, 40) },
	HouseWall  = { material = Enum.Material.Brick,       color = Color3.fromRGB(140, 100, 80) },
	HouseRoof  = { material = Enum.Material.Slate,       color = Color3.fromRGB(80, 60, 50) },
	Floor      = { material = Enum.Material.WoodPlanks,  color = Color3.fromRGB(120, 90, 60) },
	RundownWall= { material = Enum.Material.Brick,       color = Color3.fromRGB(100, 80, 65) },
	Window     = { material = Enum.Material.Glass,       color = Color3.fromRGB(150, 180, 200) },
	Door       = { material = Enum.Material.Wood,        color = Color3.fromRGB(100, 70, 40) },
	Metal      = { material = Enum.Material.Metal,       color = Color3.fromRGB(140, 140, 145) },
	Fence      = { material = Enum.Material.Wood,        color = Color3.fromRGB(160, 130, 90) },
	Trim       = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(230, 230, 225) },
	Porch      = { material = Enum.Material.WoodPlanks,  color = Color3.fromRGB(140, 110, 75) },
}

-- Suburban wall color palettes per zone
local WallPalettes = {
	-- Zone 1: modest, muted colors
	{
		Color3.fromRGB(140, 120, 100), -- tan brick
		Color3.fromRGB(160, 150, 130), -- beige
		Color3.fromRGB(120, 110, 105), -- gray-brown
		Color3.fromRGB(130, 100, 80),  -- brown brick
		Color3.fromRGB(150, 140, 125), -- warm gray
	},
	-- Zone 2: middle-class, warmer tones
	{
		Color3.fromRGB(180, 160, 130), -- cream
		Color3.fromRGB(160, 140, 120), -- sandy
		Color3.fromRGB(140, 130, 110), -- stone
		Color3.fromRGB(170, 155, 130), -- light brown
		Color3.fromRGB(190, 175, 150), -- warm beige
	},
	-- Zone 3: wealthy, bolder/cleaner colors
	{
		Color3.fromRGB(220, 210, 195), -- off-white
		Color3.fromRGB(200, 190, 170), -- cream
		Color3.fromRGB(180, 175, 165), -- light gray
		Color3.fromRGB(170, 150, 130), -- sandstone
		Color3.fromRGB(160, 155, 150), -- modern gray
	},
}

local RoofPalettes = {
	{
		Color3.fromRGB(70, 55, 45),  -- dark brown
		Color3.fromRGB(80, 70, 60),  -- medium brown
		Color3.fromRGB(60, 60, 60),  -- charcoal
	},
	{
		Color3.fromRGB(90, 70, 50),  -- brown
		Color3.fromRGB(75, 65, 55),  -- dark taupe
		Color3.fromRGB(50, 50, 55),  -- dark gray
	},
	{
		Color3.fromRGB(55, 55, 60),  -- slate
		Color3.fromRGB(65, 60, 55),  -- dark brown
		Color3.fromRGB(45, 45, 50),  -- near-black
	},
}

-- Door color variety
local DoorColors = {
	Color3.fromRGB(100, 70, 40),  -- brown
	Color3.fromRGB(120, 35, 30),  -- red
	Color3.fromRGB(50, 65, 80),   -- navy
	Color3.fromRGB(60, 80, 55),   -- dark green
	Color3.fromRGB(80, 60, 45),   -- dark wood
}

------------------------------------------------------------------------
-- Helper: Create a Part
------------------------------------------------------------------------
local function CreatePart(props)
	local part = Instance.new("Part")
	part.Name = props.Name or "Part"
	part.Size = props.Size or Vector3.new(4, 4, 4)
	part.Anchored = true
	part.CanCollide = props.CanCollide ~= false
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Color = props.Color or Color3.fromRGB(200, 200, 200)
	part.Transparency = props.Transparency or 0
	part.Parent = props.Parent or MapFolder

	if props.CFrame then
		part.CFrame = props.CFrame
	else
		part.Position = props.Position or Vector3.new(0, 0, 0)
	end

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
-- Helper: pick from palette
------------------------------------------------------------------------
local function pickColor(palette, index)
	return palette[((index - 1) % #palette) + 1]
end

------------------------------------------------------------------------
-- Create Ground
------------------------------------------------------------------------
local function CreateGround()
	CreatePart({
		Name = "Ground",
		Size = Vector3.new(Config.Map.TotalWidth, 1, Config.Map.TotalLength),
		Position = Vector3.new(0, -0.5, 0),
		Material = Materials.Grass.material,
		Color = Materials.Grass.color,
	})
end

------------------------------------------------------------------------
-- Create a Street (runs along a direction)
-- startPos/endPos define the centerline
------------------------------------------------------------------------
local function CreateStreet(startPos: Vector3, endPos: Vector3, width: number)
	local dir = (endPos - startPos)
	local length = dir.Magnitude
	local center = (startPos + endPos) / 2
	local angle = math.atan2(dir.X, dir.Z)

	local roadCF = CFrame.new(center + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, angle, 0)

	-- Road surface
	CreatePart({
		Name = "Road",
		Size = Vector3.new(width, 0.2, length),
		CFrame = roadCF,
		Material = Materials.Road.material,
		Color = Materials.Road.color,
	})

	-- Center line (yellow dashes)
	CreatePart({
		Name = "CenterLine",
		Size = Vector3.new(0.4, 0.22, length),
		CFrame = roadCF + Vector3.new(0, 0.02, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(220, 200, 50),
	})

	-- Sidewalks on both sides
	local sidewalkWidth = 6
	for _, side in ipairs({ -1, 1 }) do
		local offset = roadCF.RightVector * (side * (width / 2 + sidewalkWidth / 2))
		CreatePart({
			Name = "Sidewalk",
			Size = Vector3.new(sidewalkWidth, 0.3, length),
			CFrame = CFrame.new(roadCF.Position + offset + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, angle, 0),
			Material = Materials.Sidewalk.material,
			Color = Materials.Sidewalk.color,
		})
	end
end

------------------------------------------------------------------------
-- Create a Tree
------------------------------------------------------------------------
local function CreateTree(position: Vector3, parent)
	local trunkH = 6 + math.random() * 4
	local canopyR = 3 + math.random() * 3

	CreatePart({
		Name = "TreeTrunk",
		Size = Vector3.new(1.2, trunkH, 1.2),
		Position = position + Vector3.new(0, trunkH / 2, 0),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(85, 60, 35),
		Parent = parent,
	})

	CreatePart({
		Name = "TreeCanopy",
		Size = Vector3.new(canopyR * 2, canopyR * 1.5, canopyR * 2),
		Position = position + Vector3.new(0, trunkH + canopyR * 0.5, 0),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(40 + math.random(0, 30), 100 + math.random(0, 40), 30 + math.random(0, 20)),
		Parent = parent,
	})
end

------------------------------------------------------------------------
-- Create a Bush
------------------------------------------------------------------------
local function CreateBush(position: Vector3, parent)
	CreatePart({
		Name = "Bush",
		Size = Vector3.new(2.5 + math.random(), 2 + math.random() * 0.5, 2.5 + math.random()),
		Position = position + Vector3.new(0, 1, 0),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(35 + math.random(0, 15), 90 + math.random(0, 30), 25 + math.random(0, 15)),
		Parent = parent,
	})
end

------------------------------------------------------------------------
-- Create a Mailbox
------------------------------------------------------------------------
local function CreateMailbox(position: Vector3, parent)
	-- Post
	CreatePart({
		Name = "MailboxPost",
		Size = Vector3.new(0.4, 3.5, 0.4),
		Position = position + Vector3.new(0, 1.75, 0),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(60, 45, 30),
		Parent = parent,
	})
	-- Box
	CreatePart({
		Name = "MailboxBox",
		Size = Vector3.new(1.2, 1, 1.5),
		Position = position + Vector3.new(0, 3.8, 0),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(30, 30, 35),
		Parent = parent,
	})
end

------------------------------------------------------------------------
-- Create a Fence segment (runs along local X axis)
------------------------------------------------------------------------
local function CreateFenceSegment(cf: CFrame, length: number, parent)
	-- Posts at each end
	for _, side in ipairs({ -1, 1 }) do
		CreatePart({
			Name = "FencePost",
			Size = Vector3.new(0.4, 4, 0.4),
			CFrame = cf * CFrame.new(side * length / 2, 2, 0),
			Material = Materials.Fence.material,
			Color = Materials.Fence.color,
			Parent = parent,
		})
	end
	-- Rails
	for _, yOff in ipairs({ 1, 2.5 }) do
		CreatePart({
			Name = "FenceRail",
			Size = Vector3.new(length, 0.3, 0.3),
			CFrame = cf * CFrame.new(0, yOff, 0),
			Material = Materials.Fence.material,
			Color = Materials.Fence.color,
			Parent = parent,
		})
	end
	-- Pickets
	local picketSpacing = 2
	local picketCount = math.floor(length / picketSpacing)
	for i = 0, picketCount do
		local px = -length / 2 + i * picketSpacing
		CreatePart({
			Name = "Picket",
			Size = Vector3.new(0.3, 3.2, 0.3),
			CFrame = cf * CFrame.new(px, 1.6, 0),
			Material = Materials.Fence.material,
			Color = Materials.Fence.color,
			Parent = parent,
		})
	end
end

------------------------------------------------------------------------
-- Create a House on a Lot
-- baseCFrame: center of the lot at ground level, -Z = front (faces street)
-- zone: 1-3
-- houseIndex: used for color picking
-- isStarter: if true, this is the player's starter house
------------------------------------------------------------------------
local function CreateHouseLot(baseCFrame: CFrame, zone: number, houseIndex: number, isStarter: boolean?)
	local houseFolder = Instance.new("Folder")
	houseFolder.Name = isStarter and "StarterHouse" or ("House_Z" .. zone .. "_" .. houseIndex)
	houseFolder.Parent = MapFolder

	-- House dimensions scale by zone
	local widths  = { 22, 28, 38 }
	local depths  = { 18, 22, 30 }
	local heights = { 10, 12, 14 }

	local w = isStarter and 22 or (widths[zone] or 22)
	local d = isStarter and 18 or (depths[zone] or 18)
	local h = isStarter and 10 or (heights[zone] or 10)

	-- Lot dimensions
	local lotWidth = w + 18  -- house + side gaps
	local frontYardDepth = 14
	local backYardDepth = 12

	-- House center is offset back from lot center (behind the front yard)
	local houseCF = baseCFrame * CFrame.new(0, 0, frontYardDepth / 2 - 2)

	-- Colors
	local wallPalette = WallPalettes[zone] or WallPalettes[1]
	local roofPalette = RoofPalettes[zone] or RoofPalettes[1]
	local wallColor = isStarter and Materials.RundownWall.color or pickColor(wallPalette, houseIndex)
	local roofColor = isStarter and Materials.HouseRoof.color or pickColor(roofPalette, houseIndex)
	local doorColor = pickColor(DoorColors, houseIndex)

	--------------------------------------------------------------------
	-- FRONT YARD
	--------------------------------------------------------------------
	-- Grass
	CreatePart({
		Name = "FrontYard",
		Size = Vector3.new(lotWidth, 0.2, frontYardDepth),
		CFrame = baseCFrame * CFrame.new(0, 0.1, -d / 2 + frontYardDepth / 2 - 6),
		Material = Materials.Grass.material,
		Color = Color3.fromRGB(55 + math.random(0, 15), 115 + math.random(0, 20), 35 + math.random(0, 10)),
		Parent = houseFolder,
	})

	-- Concrete walkway from sidewalk to front door
	CreatePart({
		Name = "Walkway",
		Size = Vector3.new(3, 0.2, frontYardDepth),
		CFrame = baseCFrame * CFrame.new(0, 0.12, -d / 2 + frontYardDepth / 2 - 6),
		Material = Materials.Sidewalk.material,
		Color = Materials.Sidewalk.color,
		Parent = houseFolder,
	})

	-- Driveway (to the right side, leads to garage area)
	local drivewaySide = (houseIndex % 2 == 0) and -1 or 1
	CreatePart({
		Name = "Driveway",
		Size = Vector3.new(5, 0.2, frontYardDepth + 4),
		CFrame = baseCFrame * CFrame.new(drivewaySide * (w / 2 - 1), 0.12, -d / 2 + frontYardDepth / 2 - 4),
		Material = Materials.Driveway.material,
		Color = Materials.Driveway.color,
		Parent = houseFolder,
	})

	-- Mailbox (at the front of the yard, near the sidewalk)
	CreateMailbox(
		(baseCFrame * CFrame.new(lotWidth / 2 - 3, 0, -d / 2 - frontYardDepth / 2 - 2)).Position,
		houseFolder
	)

	-- Front yard trees/bushes
	if math.random() > 0.3 then
		local treeX = (math.random() > 0.5 and 1 or -1) * (lotWidth / 2 - 4)
		CreateTree(
			(baseCFrame * CFrame.new(treeX, 0, -d / 2 + frontYardDepth / 2 - 8)).Position,
			houseFolder
		)
	end
	if math.random() > 0.5 then
		CreateBush(
			(baseCFrame * CFrame.new(drivewaySide * -1 * (w / 2 - 2), 0, -d / 2 - 1)).Position,
			houseFolder
		)
	end

	--------------------------------------------------------------------
	-- BACKYARD
	--------------------------------------------------------------------
	CreatePart({
		Name = "BackYard",
		Size = Vector3.new(lotWidth, 0.2, backYardDepth),
		CFrame = baseCFrame * CFrame.new(0, 0.1, d / 2 + backYardDepth / 2 - 2),
		Material = Materials.Grass.material,
		Color = Color3.fromRGB(50 + math.random(0, 15), 110 + math.random(0, 20), 30 + math.random(0, 10)),
		Parent = houseFolder,
	})

	-- Backyard fence (3 sides: left, right, back)
	local fenceBaseCF = baseCFrame * CFrame.new(0, 0, d / 2 - 2)
	-- Back fence
	CreateFenceSegment(
		fenceBaseCF * CFrame.new(0, 0, backYardDepth),
		lotWidth,
		houseFolder
	)
	-- Left fence
	CreateFenceSegment(
		fenceBaseCF * CFrame.new(-lotWidth / 2, 0, backYardDepth / 2) * CFrame.Angles(0, math.rad(90), 0),
		backYardDepth,
		houseFolder
	)
	-- Right fence
	CreateFenceSegment(
		fenceBaseCF * CFrame.new(lotWidth / 2, 0, backYardDepth / 2) * CFrame.Angles(0, math.rad(90), 0),
		backYardDepth,
		houseFolder
	)

	-- Backyard tree
	if math.random() > 0.4 then
		CreateTree(
			(baseCFrame * CFrame.new(math.random(-6, 6), 0, d / 2 + backYardDepth / 2)).Position,
			houseFolder
		)
	end

	--------------------------------------------------------------------
	-- HOUSE STRUCTURE
	--------------------------------------------------------------------

	-- Foundation
	local foundation = CreatePart({
		Name = "Foundation",
		Size = Vector3.new(w + 2, 0.5, d + 2),
		CFrame = houseCF * CFrame.new(0, 0.25, 0),
		Material = Materials.Sidewalk.material,
		Color = Color3.fromRGB(145, 142, 138),
		Parent = houseFolder,
	})

	-- Floor
	CreatePart({
		Name = "Floor",
		Size = Vector3.new(w, 0.3, d),
		CFrame = houseCF * CFrame.new(0, 0.65, 0),
		Material = Materials.Floor.material,
		Color = Materials.Floor.color,
		Parent = houseFolder,
	})

	-- Walls with doorway gaps
	local doorWidth = 4
	local doorHeight = 7
	local sideWidth = (w - doorWidth) / 2

	-- Front wall (faces -Z in house space = toward street)
	CreatePart({
		Name = "WallFrontLeft",
		Size = Vector3.new(sideWidth, h, 1),
		CFrame = houseCF * CFrame.new(-(sideWidth / 2 + doorWidth / 2), h / 2 + 0.5, -d / 2),
		Material = Materials.HouseWall.material,
		Color = wallColor,
		Parent = houseFolder,
	})
	CreatePart({
		Name = "WallFrontRight",
		Size = Vector3.new(sideWidth, h, 1),
		CFrame = houseCF * CFrame.new(sideWidth / 2 + doorWidth / 2, h / 2 + 0.5, -d / 2),
		Material = Materials.HouseWall.material,
		Color = wallColor,
		Parent = houseFolder,
	})
	CreatePart({
		Name = "WallFrontHeader",
		Size = Vector3.new(doorWidth, h - doorHeight, 1),
		CFrame = houseCF * CFrame.new(0, doorHeight + (h - doorHeight) / 2 + 0.5, -d / 2),
		Material = Materials.HouseWall.material,
		Color = wallColor,
		Parent = houseFolder,
	})

	-- Back wall
	CreatePart({
		Name = "WallBackLeft",
		Size = Vector3.new(sideWidth, h, 1),
		CFrame = houseCF * CFrame.new(-(sideWidth / 2 + doorWidth / 2), h / 2 + 0.5, d / 2),
		Material = Materials.HouseWall.material,
		Color = wallColor,
		Parent = houseFolder,
	})
	CreatePart({
		Name = "WallBackRight",
		Size = Vector3.new(sideWidth, h, 1),
		CFrame = houseCF * CFrame.new(sideWidth / 2 + doorWidth / 2, h / 2 + 0.5, d / 2),
		Material = Materials.HouseWall.material,
		Color = wallColor,
		Parent = houseFolder,
	})
	CreatePart({
		Name = "WallBackHeader",
		Size = Vector3.new(doorWidth, h - doorHeight, 1),
		CFrame = houseCF * CFrame.new(0, doorHeight + (h - doorHeight) / 2 + 0.5, d / 2),
		Material = Materials.HouseWall.material,
		Color = wallColor,
		Parent = houseFolder,
	})

	-- Side walls (solid)
	CreatePart({
		Name = "WallLeft",
		Size = Vector3.new(1, h, d),
		CFrame = houseCF * CFrame.new(-w / 2, h / 2 + 0.5, 0),
		Material = Materials.HouseWall.material,
		Color = wallColor,
		Parent = houseFolder,
	})
	CreatePart({
		Name = "WallRight",
		Size = Vector3.new(1, h, d),
		CFrame = houseCF * CFrame.new(w / 2, h / 2 + 0.5, 0),
		Material = Materials.HouseWall.material,
		Color = wallColor,
		Parent = houseFolder,
	})

	-- Roof with overhang
	CreatePart({
		Name = "Roof",
		Size = Vector3.new(w + 4, 1, d + 4),
		CFrame = houseCF * CFrame.new(0, h + 1, 0),
		Material = Materials.HouseRoof.material,
		Color = roofColor,
		Parent = houseFolder,
	})

	-- Roof trim (front edge)
	CreatePart({
		Name = "RoofTrimFront",
		Size = Vector3.new(w + 4, 0.6, 0.6),
		CFrame = houseCF * CFrame.new(0, h + 0.5, -(d / 2 + 2)),
		Material = Materials.Trim.material,
		Color = Materials.Trim.color,
		Parent = houseFolder,
	})

	--------------------------------------------------------------------
	-- FRONT PORCH
	--------------------------------------------------------------------
	local porchDepth = 5
	local porchWidth = w * 0.6

	-- Porch floor
	CreatePart({
		Name = "PorchFloor",
		Size = Vector3.new(porchWidth, 0.4, porchDepth),
		CFrame = houseCF * CFrame.new(0, 0.5, -d / 2 - porchDepth / 2),
		Material = Materials.Porch.material,
		Color = Materials.Porch.color,
		Parent = houseFolder,
	})

	-- Porch roof (overhang)
	CreatePart({
		Name = "PorchRoof",
		Size = Vector3.new(porchWidth + 2, 0.4, porchDepth + 1),
		CFrame = houseCF * CFrame.new(0, doorHeight + 1.5, -d / 2 - porchDepth / 2),
		Material = Materials.HouseRoof.material,
		Color = roofColor,
		Parent = houseFolder,
	})

	-- Porch columns (2 front posts)
	for _, side in ipairs({ -1, 1 }) do
		CreatePart({
			Name = "PorchColumn",
			Size = Vector3.new(0.6, doorHeight + 1, 0.6),
			CFrame = houseCF * CFrame.new(side * (porchWidth / 2 - 0.5), (doorHeight + 1) / 2 + 0.5, -d / 2 - porchDepth + 0.5),
			Material = Materials.Trim.material,
			Color = Materials.Trim.color,
			Parent = houseFolder,
		})
	end

	-- Porch steps
	for step = 1, 2 do
		CreatePart({
			Name = "PorchStep_" .. step,
			Size = Vector3.new(4, 0.25, 1.5),
			CFrame = houseCF * CFrame.new(0, step * 0.25 - 0.12, -d / 2 - porchDepth - 1.5 + step * 1.5),
			Material = Materials.Sidewalk.material,
			Color = Materials.Sidewalk.color,
			Parent = houseFolder,
		})
	end

	--------------------------------------------------------------------
	-- DOORS (walk-through by default)
	--------------------------------------------------------------------
	CreatePart({
		Name = "FrontDoor",
		Size = Vector3.new(doorWidth, doorHeight, 1.2),
		CFrame = houseCF * CFrame.new(0, doorHeight / 2 + 0.5, -d / 2),
		Material = Materials.Door.material,
		Color = doorColor,
		CanCollide = false,
		Transparency = 0.5,
		Parent = houseFolder,
		Tags = { "FortSlot" },
		Attributes = { SlotName = "FrontDoor" },
	})

	CreatePart({
		Name = "BackDoor",
		Size = Vector3.new(doorWidth, doorHeight, 1.2),
		CFrame = houseCF * CFrame.new(0, doorHeight / 2 + 0.5, d / 2),
		Material = Materials.Door.material,
		Color = doorColor,
		CanCollide = false,
		Transparency = 0.5,
		Parent = houseFolder,
		Tags = { "FortSlot" },
		Attributes = { SlotName = "BackDoor" },
	})

	--------------------------------------------------------------------
	-- WINDOWS (on front and sides)
	--------------------------------------------------------------------
	local windowPositions = {
		-- Front windows (flanking the door)
		{ offset = CFrame.new(-w / 4, 5, -d / 2), name = "Window_1" },
		{ offset = CFrame.new(w / 4,  5, -d / 2), name = "Window_2" },
		-- Left side
		{ offset = CFrame.new(-w / 2, 5, -d / 4), name = "Window_3", sizeOverride = Vector3.new(0.5, 3, 3) },
		{ offset = CFrame.new(-w / 2, 5, d / 4),  name = "Window_4", sizeOverride = Vector3.new(0.5, 3, 3) },
		-- Right side
		{ offset = CFrame.new(w / 2, 5, -d / 4), name = "Window_5", sizeOverride = Vector3.new(0.5, 3, 3) },
		{ offset = CFrame.new(w / 2, 5, d / 4),  name = "Window_6", sizeOverride = Vector3.new(0.5, 3, 3) },
	}

	for _, winData in ipairs(windowPositions) do
		CreatePart({
			Name = winData.name,
			Size = winData.sizeOverride or Vector3.new(3, 3, 0.5),
			CFrame = houseCF * winData.offset,
			Material = Materials.Window.material,
			Color = Materials.Window.color,
			Transparency = isStarter and 0.7 or 0.3,
			Parent = houseFolder,
			Tags = { "FortSlot" },
			Attributes = { SlotName = winData.name },
		})
	end

	-- Window trim (white frames on front windows)
	for _, xOff in ipairs({ -w / 4, w / 4 }) do
		CreatePart({
			Name = "WindowTrim",
			Size = Vector3.new(4, 3.8, 0.3),
			CFrame = houseCF * CFrame.new(xOff, 5, -d / 2 - 0.3),
			Material = Materials.Trim.material,
			Color = Materials.Trim.color,
			Parent = houseFolder,
		})
	end

	--------------------------------------------------------------------
	-- LOOT CONTAINERS
	--------------------------------------------------------------------
	local lootContainerCount = zone == 1 and 2 or (zone == 2 and 3 or 4)
	for i = 1, lootContainerCount do
		local lootOffset = CFrame.new(
			math.random(-w / 3, w / 3),
			1.5,
			math.random(-d / 3, d / 3)
		)
		CreatePart({
			Name = "LootContainer_" .. i,
			Size = Vector3.new(3, 2, 2),
			CFrame = houseCF * lootOffset,
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

	--------------------------------------------------------------------
	-- STARTER HOUSE extras
	--------------------------------------------------------------------
	if isStarter then
		CollectionService:AddTag(foundation, "StarterHouse")

		-- Generator (in garage area at side of house)
		CreatePart({
			Name = "Generator",
			Size = Vector3.new(4, 3, 3),
			CFrame = houseCF * CFrame.new(drivewaySide * (w / 2 + 4), 1.5, d / 3),
			Material = Materials.Metal.material,
			Color = Color3.fromRGB(80, 80, 90),
			Parent = houseFolder,
			Tags = { "Generator" },
		})

		-- Garage (attached to house side)
		CreatePart({
			Name = "Garage",
			Size = Vector3.new(10, 8, 10),
			CFrame = houseCF * CFrame.new(drivewaySide * (w / 2 + 6), 4, d / 3),
			Material = Materials.HouseWall.material,
			Color = wallColor,
			Transparency = 0.8,
			Parent = houseFolder,
		})

		-- Cooking stations
		CreatePart({
			Name = "CampfireSpot",
			Size = Vector3.new(3, 0.5, 3),
			CFrame = houseCF * CFrame.new(0, 0.25, d / 2 + 5),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(60, 60, 60),
			Parent = houseFolder,
			Tags = { "CookingStation" },
			Attributes = { StationType = "Campfire", Built = false },
		})
		CreatePart({
			Name = "StoveSpot",
			Size = Vector3.new(3, 3, 2),
			CFrame = houseCF * CFrame.new(-w / 3, 2, 0),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(140, 140, 140),
			Transparency = 0.5,
			Parent = houseFolder,
			Tags = { "CookingStation" },
			Attributes = { StationType = "Stove", Built = false },
		})
		CreatePart({
			Name = "KitchenSpot",
			Size = Vector3.new(6, 4, 3),
			CFrame = houseCF * CFrame.new(-w / 3, 2, -d / 3),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(160, 160, 160),
			Transparency = 0.5,
			Parent = houseFolder,
			Tags = { "CookingStation" },
			Attributes = { StationType = "FullKitchen", Built = false },
		})

		-- Fortification wall sections (non-solid placeholders)
		for i = 1, Config.Fortification.WallSectionCount do
			local angle = (i / Config.Fortification.WallSectionCount) * math.pi * 2
			local wx = math.cos(angle) * (w / 2)
			local wz = math.sin(angle) * (d / 2)
			CreatePart({
				Name = "WallSection_" .. i,
				Size = Vector3.new(4, 5, 1),
				CFrame = houseCF * CFrame.new(wx, 3, wz),
				Material = Materials.HouseWall.material,
				Color = Color3.fromRGB(80, 60, 45),
				Transparency = 0.6,
				CanCollide = false,
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
				CFrame = houseCF * CFrame.new((i == 1 and -1 or 1) * w / 4, h + 0.5, 0),
				Material = Materials.HouseRoof.material,
				Color = Color3.fromRGB(60, 45, 35),
				Transparency = 0.5,
				Parent = houseFolder,
				Tags = { "FortSlot" },
				Attributes = { SlotName = "Roof_" .. i },
			})
		end

		-- Spawn point
		CreatePart({
			Name = "StarterHouseSpawn",
			Size = Vector3.new(4, 1, 4),
			CFrame = houseCF * CFrame.new(0, 1, 0),
			Transparency = 1,
			CanCollide = false,
			Parent = workspace,
		})
	end

	return houseFolder
end

------------------------------------------------------------------------
-- Create Bonus Location (unchanged, just a larger building)
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

	-- Building
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
	label.Text = locationType:gsub("(%u)", " %1"):sub(2)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = billboard

	-- Loot
	local containerCount = locationType == "UndergroundBunker" and 6 or 4
	for i = 1, containerCount do
		CreatePart({
			Name = "LootContainer_" .. i,
			Size = Vector3.new(3, 2, 2),
			Position = position + Vector3.new(
				math.random(-size.X / 3, size.X / 3),
				2,
				math.random(-size.Z / 3, size.Z / 3)
			),
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
		CreatePart({
			Name = "PurgeSpawn_" .. i,
			Size = Vector3.new(4, 1, 4),
			Position = Vector3.new(math.cos(angle) * radius, 2, math.sin(angle) * radius),
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
	CreatePart({
		Name = "LightPole",
		Size = Vector3.new(0.5, 14, 0.5),
		Position = position + Vector3.new(0, 7, 0),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(70, 70, 70),
	})

	-- Arm
	CreatePart({
		Name = "LightArm",
		Size = Vector3.new(3, 0.3, 0.3),
		Position = position + Vector3.new(1.5, 14, 0),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(70, 70, 70),
	})

	local lampHead = CreatePart({
		Name = "Lamp",
		Size = Vector3.new(2, 0.8, 1.5),
		Position = position + Vector3.new(3, 14, 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 240, 200),
	})

	local light = Instance.new("PointLight")
	light.Range = 45
	light.Brightness = 1
	light.Color = Color3.fromRGB(255, 240, 200)
	light.Parent = lampHead
end

------------------------------------------------------------------------
-- Create a Stop Sign
------------------------------------------------------------------------
local function CreateStopSign(position: Vector3, facingAngle: number)
	local cf = CFrame.new(position) * CFrame.Angles(0, facingAngle, 0)

	CreatePart({
		Name = "StopSignPole",
		Size = Vector3.new(0.3, 7, 0.3),
		CFrame = cf * CFrame.new(0, 3.5, 0),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(90, 90, 90),
	})
	CreatePart({
		Name = "StopSign",
		Size = Vector3.new(2.5, 2.5, 0.2),
		CFrame = cf * CFrame.new(0, 7.5, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(200, 30, 30),
	})
end

------------------------------------------------------------------------
-- Build the Complete Neighborhood
------------------------------------------------------------------------
local function BuildMap()
	print("[MapBuilder] Building Brookhaven-style neighborhood...")

	-- Ground
	CreateGround()

	------------------------------------------------------------------------
	-- STREETS
	------------------------------------------------------------------------

	-- Main Avenue (N-S through center)
	local mainAveLength = 1200
	CreateStreet(
		Vector3.new(0, 0, -mainAveLength / 2),
		Vector3.new(0, 0, mainAveLength / 2),
		Config.Map.StreetWidth
	)

	-- Residential streets (E-W)
	local streets = {
		{ z = 60,   name = "Cedar Court",   zone = 1, halfLen = 280 },
		{ z = -120, name = "Elm Street",     zone = 1, halfLen = 280 },
		{ z = 240,  name = "Pine Lane",      zone = 2, halfLen = 380 },
		{ z = -300, name = "Oak Avenue",     zone = 2, halfLen = 380 },
		{ z = 440,  name = "Maple Drive",    zone = 3, halfLen = 500 },
		{ z = -500, name = "Birch Road",     zone = 3, halfLen = 500 },
	}

	for _, st in ipairs(streets) do
		-- East side of Main Ave
		CreateStreet(
			Vector3.new(Config.Map.StreetWidth / 2 + 6, 0, st.z),
			Vector3.new(st.halfLen, 0, st.z),
			Config.Map.StreetWidth - 10
		)
		-- West side of Main Ave
		CreateStreet(
			Vector3.new(-(Config.Map.StreetWidth / 2 + 6), 0, st.z),
			Vector3.new(-st.halfLen, 0, st.z),
			Config.Map.StreetWidth - 10
		)

		-- Stop signs at intersections
		local signOffset = Config.Map.StreetWidth / 2 + 8
		CreateStopSign(Vector3.new(signOffset, 0, st.z + signOffset), math.rad(0))
		CreateStopSign(Vector3.new(-signOffset, 0, st.z - signOffset), math.rad(180))
	end

	------------------------------------------------------------------------
	-- HOUSES along each residential street
	------------------------------------------------------------------------
	local houseGlobalIndex = 0

	-- Starter house on Cedar Court
	local starterCF = CFrame.new(80, 0, 60) * CFrame.Angles(0, math.rad(180), 0)
	CreateHouseLot(starterCF, 1, 1, true)

	for _, st in ipairs(streets) do
		local zone = st.zone
		local lotW = zone == 1 and 40 or (zone == 2 and 48 or 60)
		local streetHalfWidth = (Config.Map.StreetWidth - 10) / 2
		local sidewalkW = 6
		local setback = streetHalfWidth + sidewalkW + 10  -- distance from street center to lot center

		-- Place houses along both sides of the street, on both east and west halves
		for _, xSign in ipairs({ 1, -1 }) do  -- east / west of Main Ave
			local startX = Config.Map.StreetWidth / 2 + 30  -- start past the main ave intersection
			local endX = st.halfLen - 20

			local houseX = startX
			while houseX < endX do
				houseGlobalIndex = houseGlobalIndex + 1

				-- North side of street (house faces south, toward +Z = toward street)
				local northCF = CFrame.new(xSign * houseX, 0, st.z - setback) * CFrame.Angles(0, math.rad(0), 0)
				-- Skip if this is where the starter house is
				local isStarterSpot = (st.z == 60 and xSign == 1 and houseX < 110 and houseX > 50)
				if not isStarterSpot then
					CreateHouseLot(northCF, zone, houseGlobalIndex)
				end

				-- South side of street (house faces north, toward -Z = toward street)
				houseGlobalIndex = houseGlobalIndex + 1
				local southCF = CFrame.new(xSign * houseX, 0, st.z + setback) * CFrame.Angles(0, math.rad(180), 0)
				CreateHouseLot(southCF, zone, houseGlobalIndex)

				houseX = houseX + lotW + 4  -- lot width + gap between lots
			end
		end
	end

	------------------------------------------------------------------------
	-- BONUS LOCATIONS (at map edges / special spots)
	------------------------------------------------------------------------
	CreateBonusLocation(Vector3.new(-420, 0, 0), "HardwareStore")
	CreateBonusLocation(Vector3.new(420, 0, 0), "PoliceStation")
	CreateBonusLocation(Vector3.new(0, 0, 520), "GasStation")
	CreateBonusLocation(Vector3.new(-280, 0, 420), "AbandonedSchool")
	CreateBonusLocation(Vector3.new(320, 0, -550), "UndergroundBunker")

	------------------------------------------------------------------------
	-- PURGE SPAWN POINTS
	------------------------------------------------------------------------
	CreateSpawnPoints()

	------------------------------------------------------------------------
	-- STREET LIGHTS along Main Avenue
	------------------------------------------------------------------------
	for z = -550, 550, 70 do
		CreateStreetLight(Vector3.new(-(Config.Map.StreetWidth / 2 + 4), 0, z))
		CreateStreetLight(Vector3.new(Config.Map.StreetWidth / 2 + 4, 0, z))
	end

	-- Street lights along residential streets
	for _, st in ipairs(streets) do
		local streetHalfWidth = (Config.Map.StreetWidth - 10) / 2
		for x = 60, st.halfLen - 20, 80 do
			for _, xSign in ipairs({ 1, -1 }) do
				CreateStreetLight(Vector3.new(xSign * x, 0, st.z - streetHalfWidth - 4))
				CreateStreetLight(Vector3.new(xSign * x, 0, st.z + streetHalfWidth + 4))
			end
		end
	end

	------------------------------------------------------------------------
	-- FISHING POND (park area)
	------------------------------------------------------------------------
	local pond = CreatePart({
		Name = "FishingPond",
		Size = Vector3.new(35, 1, 25),
		Position = Vector3.new(-450, -0.3, 400),
		Material = Enum.Material.Water,
		Color = Color3.fromRGB(40, 80, 120),
	})
	CollectionService:AddTag(pond, "FishingSpot")

	-- Park area around pond
	CreatePart({
		Name = "ParkGrass",
		Size = Vector3.new(60, 0.15, 50),
		Position = Vector3.new(-450, 0.08, 400),
		Material = Materials.Grass.material,
		Color = Color3.fromRGB(50, 130, 45),
	})

	-- Park benches
	for _, offset in ipairs({ Vector3.new(-440, 0, 385), Vector3.new(-460, 0, 415) }) do
		CreatePart({
			Name = "ParkBench",
			Size = Vector3.new(4, 1.5, 1.5),
			Position = offset + Vector3.new(0, 0.75, 0),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(100, 70, 40),
		})
	end

	-- Park trees
	for _, offset in ipairs({
		Vector3.new(-435, 0, 390),
		Vector3.new(-465, 0, 410),
		Vector3.new(-445, 0, 420),
	}) do
		CreateTree(offset, MapFolder)
	end

	print("[MapBuilder] Neighborhood generation complete!")
	print("  Streets:", #streets)
	print("  Total houses (approx):", houseGlobalIndex)
end

------------------------------------------------------------------------
-- Build on startup
------------------------------------------------------------------------
task.defer(BuildMap)
