--[[
	NPCService.server.lua
	Manages house defender NPCs and wildlife spawning/behavior.
	House defenders guard loot in Zone 1-3 houses.
	Wildlife roams the map edges for hunting.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local ItemDatabase = require(Modules.ItemDatabase)
local Utils = require(Modules.Utils)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")

------------------------------------------------------------------------
-- NPC Registry
------------------------------------------------------------------------
local ActiveNPCs = {}      -- [model] = { type, state, homePosition, ... }
local ActiveWildlife = {}  -- [model] = { type, state, roamCenter, ... }

------------------------------------------------------------------------
-- House Defender Spawning
------------------------------------------------------------------------
local DefenderCompositions = {
	-- Zone 1: minimal resistance
	[1] = {
		{ type = Enums.NPCType.StrayDog, chance = 0.4 },
		{ type = Enums.NPCType.WeakResident, chance = 0.3 },
		-- 30% chance of no defenders
	},
	-- Zone 2: moderate resistance
	[2] = {
		{ type = Enums.NPCType.ArmedResident, count = { 1, 2 }, chance = 0.5 },
		{ type = Enums.NPCType.GuardDog, count = { 1, 1 }, chance = 0.4 },
		{ type = Enums.NPCType.WeakResident, count = { 1, 2 }, chance = 0.3 },
	},
	-- Zone 3: heavy resistance
	[3] = {
		{ type = Enums.NPCType.HeavyResident, count = { 2, 3 }, chance = 0.6 },
		{ type = Enums.NPCType.ArmedResident, count = { 1, 2 }, chance = 0.5 },
		{ type = Enums.NPCType.GuardDog, count = { 1, 2 }, chance = 0.4 },
		{ type = Enums.NPCType.HouseBoss, count = { 1, 1 }, chance = 0.3 },
	},
}

local function CreateNPCModel(npcType: string, position: Vector3): Model
	local stats = Config.NPCStats[npcType]
	if not stats then return nil end

	local model = Instance.new("Model")
	model.Name = "NPC_" .. npcType

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Position = position
	hrp.Anchored = false
	hrp.CanCollide = true
	hrp.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Shape = Enum.PartType.Ball
	head.Position = position + Vector3.new(0, 2, 0)
	head.Anchored = false
	head.CanCollide = false
	head.Parent = model

	-- Color by type
	local colors = {
		[Enums.NPCType.StrayDog] = Color3.fromRGB(139, 90, 43),
		[Enums.NPCType.WeakResident] = Color3.fromRGB(180, 150, 120),
		[Enums.NPCType.ArmedResident] = Color3.fromRGB(100, 100, 120),
		[Enums.NPCType.GuardDog] = Color3.fromRGB(80, 60, 40),
		[Enums.NPCType.HeavyResident] = Color3.fromRGB(70, 70, 90),
		[Enums.NPCType.HouseBoss] = Color3.fromRGB(150, 40, 40),
		-- Wildlife
		[Enums.NPCType.Rabbit] = Color3.fromRGB(200, 180, 160),
		[Enums.NPCType.Squirrel] = Color3.fromRGB(160, 100, 60),
		[Enums.NPCType.Raccoon] = Color3.fromRGB(100, 100, 100),
		[Enums.NPCType.Bird] = Color3.fromRGB(50, 120, 180),
		[Enums.NPCType.Deer] = Color3.fromRGB(180, 140, 80),
		[Enums.NPCType.StrayDogWild] = Color3.fromRGB(150, 120, 80),
	}
	local color = colors[npcType] or Color3.fromRGB(150, 150, 150)
	hrp.Color = color
	head.Color = color

	-- Scale wildlife smaller
	local wildlifeScale = {
		[Enums.NPCType.Rabbit] = 0.4,
		[Enums.NPCType.Squirrel] = 0.3,
		[Enums.NPCType.Raccoon] = 0.5,
		[Enums.NPCType.Bird] = 0.3,
		[Enums.NPCType.Deer] = 1.2,
		[Enums.NPCType.StrayDogWild] = 0.7,
	}
	local scale = wildlifeScale[npcType]
	if scale then
		hrp.Size = hrp.Size * scale
		head.Size = head.Size * scale
	end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hrp
	weld.Part1 = head
	weld.Parent = hrp

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = stats.health
	humanoid.Health = stats.health
	humanoid.WalkSpeed = stats.speed
	humanoid.Parent = model

	model.PrimaryPart = hrp
	model:SetAttribute("NPCType", npcType)
	model:SetAttribute("Damage", stats.damage)

	CollectionService:AddTag(model, "NPC")

	return model
end

-- Spawn defenders for a house
local function SpawnHouseDefenders(housePart: BasePart)
	local zone = housePart:GetAttribute("Zone") or 1
	local composition = DefenderCompositions[zone]
	if not composition then return end

	local spawnedTypes = {}

	for _, entry in ipairs(composition) do
		if math.random() > entry.chance then continue end

		local count = 1
		if entry.count then
			count = math.random(entry.count[1], entry.count[2])
		end

		for _ = 1, count do
			local offset = Vector3.new(
				math.random(-8, 8),
				3,
				math.random(-8, 8)
			)
			local spawnPos = housePart.Position + offset
			local model = CreateNPCModel(entry.type, spawnPos)
			if model then
				model.Parent = workspace:FindFirstChild("NPCs")

				ActiveNPCs[model] = {
					type = entry.type,
					state = "idle",
					homePosition = housePart.Position,
					alertRange = 25,
					chaseRange = 40,
					house = housePart,
				}

				-- Death handler
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.Died:Connect(function()
						ActiveNPCs[model] = nil
						task.delay(3, function()
							if model.Parent then model:Destroy() end
						end)
					end)
				end

				table.insert(spawnedTypes, entry.type)
			end
		end
	end

	return spawnedTypes
end

------------------------------------------------------------------------
-- House Defender AI
------------------------------------------------------------------------
local function DefenderAITick()
	for model, data in pairs(ActiveNPCs) do
		if not model.Parent then
			ActiveNPCs[model] = nil
			continue
		end

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then continue end

		local hrp = model:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end

		-- Find nearest player
		local nearestPlayer = nil
		local nearestDist = math.huge

		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			if char then
				local playerHRP = char:FindFirstChild("HumanoidRootPart")
				if playerHRP then
					local dist = Utils.Distance(hrp.Position, playerHRP.Position)
					if dist < nearestDist then
						nearestDist = dist
						nearestPlayer = player
					end
				end
			end
		end

		if data.state == "idle" then
			-- Check if player is within alert range
			if nearestPlayer and nearestDist <= data.alertRange then
				data.state = "alert"
			end

		elseif data.state == "alert" then
			-- Chase player
			if nearestPlayer and nearestDist <= data.chaseRange then
				local char = nearestPlayer.Character
				if char and char:FindFirstChild("HumanoidRootPart") then
					humanoid:MoveTo(char.HumanoidRootPart.Position)
				end

				-- Attack if in range
				local attackRange = Config.NPCStats[data.type] and Config.NPCStats[data.type].attackRange or 5
				if nearestDist <= attackRange then
					data.state = "attacking"
				end
			else
				-- Return home if player left
				data.state = "returning"
			end

		elseif data.state == "attacking" then
			if not nearestPlayer or nearestDist > (Config.NPCStats[data.type] and Config.NPCStats[data.type].attackRange or 5) + 5 then
				data.state = "alert"
			else
				-- Deal damage
				local getPS = game.ServerStorage:FindFirstChild("GetPlayerState")
				if getPS and nearestPlayer then
					local playerState = getPS:Invoke(nearestPlayer)
					if playerState and playerState.state == Enums.PlayerState.Alive then
						local damage = Config.NPCStats[data.type] and Config.NPCStats[data.type].damage or 10
						playerState.health -= damage
						UpdateHUD:FireClient(nearestPlayer, "DamageTaken", damage)

						if playerState.health <= 0 then
							playerState.health = 0
							playerState.state = Enums.PlayerState.Downed
							playerState.downedAt = tick()
							local PlayerDowned = Remotes:FindFirstChild("PlayerDowned")
							if PlayerDowned then
								PlayerDowned:FireAllClients(nearestPlayer)
							end
						end
					end
				end
			end

		elseif data.state == "returning" then
			local homeDist = Utils.Distance(hrp.Position, data.homePosition)
			if homeDist > 5 then
				humanoid:MoveTo(data.homePosition)
			else
				data.state = "idle"
			end

			-- Re-alert if player comes close
			if nearestPlayer and nearestDist <= data.alertRange then
				data.state = "alert"
			end
		end
	end
end

------------------------------------------------------------------------
-- Wildlife Spawning
------------------------------------------------------------------------
local WildlifeTypes = {
	{ type = Enums.NPCType.Rabbit, weight = 4, dropItem = "raw_rabbit" },
	{ type = Enums.NPCType.Squirrel, weight = 3, dropItem = nil },  -- too small
	{ type = Enums.NPCType.Raccoon, weight = 2, dropItem = "raw_meat" },
	{ type = Enums.NPCType.Bird, weight = 2, dropItem = "raw_bird" },
	{ type = Enums.NPCType.Deer, weight = 1, dropItem = "raw_venison" },
	{ type = Enums.NPCType.StrayDogWild, weight = 1, dropItem = "raw_meat" },
}

local MAX_WILDLIFE = 12
local WILDLIFE_SPAWN_INTERVAL = 30  -- seconds
local wildlifeSpawnTimer = 0

local function SpawnWildlife()
	-- Count current wildlife
	local count = 0
	for _ in pairs(ActiveWildlife) do count += 1 end
	if count >= MAX_WILDLIFE then return end

	-- Pick type
	local choices = {}
	for _, entry in ipairs(WildlifeTypes) do
		table.insert(choices, { item = entry, weight = entry.weight })
	end
	local chosen = Utils.WeightedRandom(choices)

	-- Spawn at map edges
	local mapW = Config.Map.TotalWidth / 2
	local mapL = Config.Map.TotalLength / 2
	local edge = math.random(1, 4)
	local pos
	if edge == 1 then
		pos = Vector3.new(math.random(-mapW, mapW), 3, -mapL + math.random(0, 50))
	elseif edge == 2 then
		pos = Vector3.new(math.random(-mapW, mapW), 3, mapL - math.random(0, 50))
	elseif edge == 3 then
		pos = Vector3.new(-mapW + math.random(0, 50), 3, math.random(-mapL, mapL))
	else
		pos = Vector3.new(mapW - math.random(0, 50), 3, math.random(-mapL, mapL))
	end

	local model = CreateNPCModel(chosen.type, pos)
	if not model then return end

	model.Parent = workspace:FindFirstChild("Wildlife")
	CollectionService:AddTag(model, "Wildlife")

	ActiveWildlife[model] = {
		type = chosen.type,
		state = "roaming",
		roamCenter = pos,
		roamRadius = 60,
		dropItem = chosen.dropItem,
		fleeRange = Config.NPCStats[chosen.type] and Config.NPCStats[chosen.type].fleeRange or 20,
	}

	-- Death handler: drop meat
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			local data = ActiveWildlife[model]
			if data and data.dropItem then
				local hrp = model:FindFirstChild("HumanoidRootPart")
				if hrp then
					-- Drop loot
					local lootPart = Instance.new("Part")
					lootPart.Name = "Loot_" .. data.dropItem
					lootPart.Size = Vector3.new(1, 1, 1)
					lootPart.Position = hrp.Position + Vector3.new(0, 1, 0)
					lootPart.Anchored = true
					lootPart.CanCollide = false
					lootPart.Color = Color3.fromRGB(200, 50, 50)
					lootPart:SetAttribute("ItemId", data.dropItem)
					lootPart:SetAttribute("Quantity", 1)
					CollectionService:AddTag(lootPart, "LootItem")

					local itemData = ItemDatabase.GetItem(data.dropItem)

					local prompt = Instance.new("ProximityPrompt")
					prompt.ActionText = "Pick Up"
					prompt.ObjectText = itemData and itemData.name or data.dropItem
					prompt.MaxActivationDistance = Config.Player.PickupRange
					prompt.HoldDuration = 0.3
					prompt.Parent = lootPart

					local billboard = Instance.new("BillboardGui")
					billboard.Size = UDim2.new(0, 100, 0, 25)
					billboard.StudsOffset = Vector3.new(0, 1.5, 0)
					billboard.AlwaysOnTop = false
					billboard.MaxDistance = 15
					billboard.Parent = lootPart

					local label = Instance.new("TextLabel")
					label.Size = UDim2.new(1, 0, 1, 0)
					label.BackgroundTransparency = 1
					label.Text = itemData and itemData.name or data.dropItem
					label.TextColor3 = Color3.new(1, 1, 1)
					label.TextScaled = true
					label.Font = Enum.Font.GothamBold
					label.Parent = billboard

					lootPart.Parent = workspace:FindFirstChild("LootItems")
				end
			end

			ActiveWildlife[model] = nil
			task.delay(3, function()
				if model.Parent then model:Destroy() end
			end)
		end)
	end
end

------------------------------------------------------------------------
-- Wildlife AI
------------------------------------------------------------------------
local function WildlifeAITick()
	for model, data in pairs(ActiveWildlife) do
		if not model.Parent then
			ActiveWildlife[model] = nil
			continue
		end

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then continue end

		local hrp = model:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end

		-- Check for nearby players
		local nearestDist = math.huge
		local nearestPlayerPos = nil

		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			if char then
				local playerHRP = char:FindFirstChild("HumanoidRootPart")
				if playerHRP then
					local dist = Utils.Distance(hrp.Position, playerHRP.Position)
					if dist < nearestDist then
						nearestDist = dist
						nearestPlayerPos = playerHRP.Position
					end
				end
			end
		end

		if data.state == "roaming" then
			-- Random roam
			if math.random() < 0.02 then
				local offset = Vector3.new(
					math.random(-20, 20),
					0,
					math.random(-20, 20)
				)
				local target = data.roamCenter + offset
				humanoid:MoveTo(target)
			end

			-- Flee from players
			if nearestDist <= data.fleeRange then
				data.state = "fleeing"
			end

		elseif data.state == "fleeing" then
			if nearestPlayerPos then
				-- Run away from player
				local direction = (hrp.Position - nearestPlayerPos).Unit
				local fleeTarget = hrp.Position + direction * 40
				humanoid:MoveTo(fleeTarget)
			end

			-- Stop fleeing when far enough
			if nearestDist > data.fleeRange * 1.5 then
				data.state = "roaming"
			end
		end
	end
end

------------------------------------------------------------------------
-- Main AI Loop
------------------------------------------------------------------------
local aiTickRate = 0
RunService.Heartbeat:Connect(function(dt)
	aiTickRate += dt
	if aiTickRate < 0.5 then return end  -- AI ticks at 2Hz
	aiTickRate = 0

	DefenderAITick()
	WildlifeAITick()

	-- Wildlife spawning
	wildlifeSpawnTimer += 0.5
	if wildlifeSpawnTimer >= WILDLIFE_SPAWN_INTERVAL then
		wildlifeSpawnTimer = 0
		SpawnWildlife()
	end
end)

------------------------------------------------------------------------
-- Initialize house defenders when houses are loaded
------------------------------------------------------------------------
local function InitializeHouseDefenders()
	local houses = CollectionService:GetTagged("LootableHouse")
	for _, house in ipairs(houses) do
		SpawnHouseDefenders(house)
	end
	print("[NPCService] Spawned defenders for " .. #houses .. " houses")
end

CollectionService:GetInstanceAddedSignal("LootableHouse"):Connect(function(house)
	task.defer(function()
		SpawnHouseDefenders(house)
	end)
end)

task.defer(function()
	InitializeHouseDefenders()
	-- Spawn initial wildlife
	for _ = 1, 6 do
		SpawnWildlife()
	end
end)

print("[NPCService] Initialized")
