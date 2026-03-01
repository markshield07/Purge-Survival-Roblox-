--[[
	PurgeService.server.lua
	Manages Purge wave spawning, enemy behavior, scaling, and rewards.
	Enemies use PathfindingService to navigate to the player's house.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local Utils = require(Modules.Utils)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local ActiveEnemies = {}  -- [npcModel] = { type, health, maxHealth, damage, speed, target, ... }
local CurrentWave = 0
local TotalWaves = 0
local WaveTimer = 0
local PurgeActive = false
local CurrentDifficulty = nil

------------------------------------------------------------------------
-- Helper: Get game state
------------------------------------------------------------------------
local function GetGameState()
	local getter = game.ServerStorage:FindFirstChild("GetGameState")
	if getter then return getter:Invoke() end
	return nil
end

------------------------------------------------------------------------
-- Enemy Spawning
------------------------------------------------------------------------
local function GetSpawnPositions(count: number): { Vector3 }
	local positions = {}
	local spawnFolder = workspace:FindFirstChild("SpawnPoints")

	if spawnFolder then
		local spawnParts = spawnFolder:GetChildren()
		if #spawnParts > 0 then
			for i = 1, count do
				local sp = spawnParts[math.random(1, #spawnParts)]
				local offset = Vector3.new(
					math.random(-20, 20),
					0,
					math.random(-20, 20)
				)
				table.insert(positions, sp.Position + offset)
			end
			return positions
		end
	end

	-- Fallback: spawn around perimeter
	local radius = Config.Map.PurgeSpawnRadius
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.5
		local x = math.cos(angle) * radius + math.random(-30, 30)
		local z = math.sin(angle) * radius + math.random(-30, 30)
		table.insert(positions, Vector3.new(x, 5, z))
	end
	return positions
end

local function PickEnemyType(difficulty): string
	local types = { Enums.NPCType.MaskedAttacker }

	if difficulty.hasFirearms then
		table.insert(types, Enums.NPCType.ArmedAttacker)
		table.insert(types, Enums.NPCType.ArmedAttacker)
	end
	if difficulty.hasExplosives then
		table.insert(types, Enums.NPCType.ExplosiveAttacker)
	end
	if difficulty.hasArmored then
		table.insert(types, Enums.NPCType.ArmoredAttacker)
	end

	-- Add breacher type always (they target barricades)
	table.insert(types, Enums.NPCType.BreacherAttacker)

	return types[math.random(1, #types)]
end

local function CreateEnemyModel(enemyType: string, position: Vector3): Model
	local stats = Config.NPCStats[enemyType]
	if not stats then
		stats = Config.NPCStats.MaskedAttacker
	end

	-- Create a basic humanoid NPC model
	local model = Instance.new("Model")
	model.Name = "PurgeEnemy_" .. enemyType

	-- Torso / HumanoidRootPart
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Position = position
	hrp.Anchored = false
	hrp.CanCollide = true
	hrp.Parent = model

	-- Head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.5, 1.5, 1.5)
	head.Shape = Enum.PartType.Ball
	head.Position = position + Vector3.new(0, 2.5, 0)
	head.Anchored = false
	head.CanCollide = false
	head.Parent = model

	-- Color enemies by type
	local colors = {
		[Enums.NPCType.MaskedAttacker] = Color3.fromRGB(80, 80, 80),
		[Enums.NPCType.ArmedAttacker] = Color3.fromRGB(100, 50, 50),
		[Enums.NPCType.BreacherAttacker] = Color3.fromRGB(120, 80, 40),
		[Enums.NPCType.ArmoredAttacker] = Color3.fromRGB(60, 60, 80),
		[Enums.NPCType.ExplosiveAttacker] = Color3.fromRGB(150, 50, 0),
		[Enums.NPCType.PurgeBoss] = Color3.fromRGB(200, 0, 0),
	}
	local color = colors[enemyType] or Color3.fromRGB(80, 80, 80)
	hrp.Color = color
	head.Color = color

	-- Weld head to body
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hrp
	weld.Part1 = head
	weld.Parent = hrp

	-- Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = stats.health
	humanoid.Health = stats.health
	humanoid.WalkSpeed = stats.speed
	humanoid.Parent = model

	model.PrimaryPart = hrp

	-- Set attributes for identification
	model:SetAttribute("EnemyType", enemyType)
	model:SetAttribute("Damage", stats.damage)
	model:SetAttribute("AttackRange", stats.attackRange)
	model:SetAttribute("BarricadeDamageMultiplier", stats.barricadeDamageMultiplier or 1)
	model:SetAttribute("AOERadius", stats.aoeRadius or 0)

	CollectionService:AddTag(model, "PurgeEnemy")

	return model
end

------------------------------------------------------------------------
-- Enemy AI
------------------------------------------------------------------------
local function GetHouseTarget(): Vector3?
	-- Find the starter house center (tagged part)
	local houseParts = CollectionService:GetTagged("StarterHouse")
	if #houseParts > 0 then
		return houseParts[1].Position
	end
	return Vector3.new(0, 5, 0)  -- fallback to origin
end

local function GetNearestPlayer(position: Vector3): Player?
	local nearestDist = math.huge
	local nearest = nil

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local dist = Utils.Distance(position, hrp.Position)
				if dist < nearestDist then
					nearestDist = dist
					nearest = player
				end
			end
		end
	end

	return nearest, nearestDist
end

local function MoveEnemyToTarget(enemyModel: Model, targetPos: Vector3)
	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local hrp = enemyModel:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Use PathfindingService for navigation
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentCanClimb = false,
	})

	local success, errorMessage = pcall(function()
		path:ComputeAsync(hrp.Position, targetPos)
	end)

	if success and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		for _, waypoint in ipairs(waypoints) do
			if humanoid.Health <= 0 then break end
			humanoid:MoveTo(waypoint.Position)
			humanoid.MoveToFinished:Wait()
		end
	else
		-- Fallback: direct move
		humanoid:MoveTo(targetPos)
	end
end

local function EnemyAttackLoop(enemyModel: Model, enemyData)
	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	while humanoid.Health > 0 and PurgeActive do
		local hrp = enemyModel:FindFirstChild("HumanoidRootPart")
		if not hrp then break end

		local attackRange = enemyData.attackRange or 5
		local damage = enemyData.damage or 15

		-- Find target: nearest player or house fortification
		local nearestPlayer, playerDist = GetNearestPlayer(hrp.Position)
		local housePos = GetHouseTarget()
		local houseDist = housePos and Utils.Distance(hrp.Position, housePos) or math.huge

		-- Breacher types prioritize fortifications
		local isBreacher = enemyData.type == Enums.NPCType.BreacherAttacker

		if isBreacher and houseDist < 30 then
			-- Attack nearest fortification
			local getWeakest = game.ServerStorage:FindFirstChild("GetWeakestFortification")
			if getWeakest then
				local slotName = getWeakest:Invoke()
				if slotName then
					local damageFort = game.ServerStorage:FindFirstChild("DamageFortification")
					if damageFort then
						local breached = damageFort:Invoke(slotName,
							damage * (enemyData.barricadeDamageMultiplier or 1))
					end
				end
			end
			task.wait(1.5)
		elseif nearestPlayer and playerDist <= attackRange then
			-- Attack player
			local playerState = nil
			local getPS = game.ServerStorage:FindFirstChild("GetPlayerState")
			if getPS then
				playerState = getPS:Invoke(nearestPlayer)
			end

			if playerState and playerState.state == Enums.PlayerState.Alive then
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
			task.wait(1.0)
		else
			-- Move toward target
			local target = housePos
			if nearestPlayer and playerDist < houseDist then
				local char = nearestPlayer.Character
				if char and char:FindFirstChild("HumanoidRootPart") then
					target = char.HumanoidRootPart.Position
				end
			end

			if target then
				MoveEnemyToTarget(enemyModel, target)
			end
			task.wait(0.5)
		end
	end
end

------------------------------------------------------------------------
-- Enemy Death Handler
------------------------------------------------------------------------
local function OnEnemyDied(enemyModel: Model)
	local data = ActiveEnemies[enemyModel]
	if not data then return end

	ActiveEnemies[enemyModel] = nil

	-- Death effects
	local hrp = enemyModel:FindFirstChild("HumanoidRootPart")
	if hrp then
		-- Flash red then fade
		hrp.Color = Color3.fromRGB(255, 0, 0)
	end

	-- Update game state
	local gameState = GetGameState()
	if gameState then
		gameState.totalEnemiesKilled += 1
	end

	-- Clean up after delay
	task.delay(3, function()
		if enemyModel.Parent then
			enemyModel:Destroy()
		end
	end)
end

------------------------------------------------------------------------
-- Wave Spawning
------------------------------------------------------------------------
local function SpawnWave(waveNumber: number)
	if not CurrentDifficulty then return end

	CurrentWave = waveNumber
	local enemiesThisWave = Config.Purge.EnemiesPerWave + math.floor(waveNumber * 0.5)

	-- Scale with player count
	local playerCount = math.max(1, #Players:GetPlayers())
	enemiesThisWave = math.floor(enemiesThisWave * (1 + (playerCount - 1) * 0.3))

	NotifyPlayers:FireAllClients(
		"Wave " .. waveNumber .. "/" .. TotalWaves .. " incoming!",
		Color3.fromRGB(255, 100, 0)
	)

	local spawnPositions = GetSpawnPositions(enemiesThisWave)

	-- Spawn boss on last wave if applicable
	local spawnBoss = CurrentDifficulty.hasBoss and waveNumber == TotalWaves

	for i, pos in ipairs(spawnPositions) do
		local enemyType
		if spawnBoss and i == 1 then
			enemyType = Enums.NPCType.PurgeBoss
		else
			enemyType = PickEnemyType(CurrentDifficulty)
		end

		local model = CreateEnemyModel(enemyType, pos)
		model.Parent = workspace:FindFirstChild("PurgeEnemies")

		local stats = Config.NPCStats[enemyType] or Config.NPCStats.MaskedAttacker
		local enemyData = {
			type = enemyType,
			health = stats.health,
			maxHealth = stats.health,
			damage = stats.damage,
			speed = stats.speed,
			attackRange = stats.attackRange,
			barricadeDamageMultiplier = stats.barricadeDamageMultiplier or 1,
			aoeRadius = stats.aoeRadius or 0,
		}

		ActiveEnemies[model] = enemyData

		-- Set up death detection
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				OnEnemyDied(model)
			end)
		end

		-- Start AI loop
		task.spawn(function()
			-- Small stagger so they don't all arrive at once
			task.wait(math.random() * 2)
			EnemyAttackLoop(model, enemyData)
		end)
	end

	-- Power targeting (Purge 3+)
	if CurrentDifficulty.targetsPower and waveNumber >= 2 then
		-- Some enemies specifically target the generator
		task.spawn(function()
			task.wait(5)
			local gameState = GetGameState()
			if gameState and gameState.generator.isPowered then
				-- Spawn a flanker that goes for the generator
				local genParts = CollectionService:GetTagged("Generator")
				if #genParts > 0 then
					local flankerPos = GetSpawnPositions(1)[1]
					local flanker = CreateEnemyModel(Enums.NPCType.BreacherAttacker, flankerPos)
					flanker.Name = "PowerFlanker"
					flanker.Parent = workspace:FindFirstChild("PurgeEnemies")

					local flankerStats = Config.NPCStats.BreacherAttacker
					local flankerData = {
						type = Enums.NPCType.BreacherAttacker,
						damage = flankerStats.damage,
						attackRange = flankerStats.attackRange,
						barricadeDamageMultiplier = 3,
					}
					ActiveEnemies[flanker] = flankerData

					local hum = flanker:FindFirstChildOfClass("Humanoid")
					if hum then
						hum.Died:Connect(function() OnEnemyDied(flanker) end)
					end

					NotifyPlayers:FireAllClients(
						"ENEMIES TARGETING THE GENERATOR!",
						Color3.fromRGB(255, 0, 100)
					)
				end
			end
		end)
	end
end

------------------------------------------------------------------------
-- Purge Start/End
------------------------------------------------------------------------
local function OnPurgeStart(purgeNumber: number, difficulty)
	PurgeActive = true
	CurrentDifficulty = difficulty
	CurrentWave = 0
	TotalWaves = difficulty.waveCount or 3
	WaveTimer = 0

	-- Spawn first wave immediately
	task.spawn(function()
		SpawnWave(1)
	end)
end

local function OnPurgeEnd()
	PurgeActive = false
	CurrentDifficulty = nil
	CurrentWave = 0
	TotalWaves = 0

	-- Despawn remaining enemies
	for model, _ in pairs(ActiveEnemies) do
		if model.Parent then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = 0
			end
			task.delay(2, function()
				if model.Parent then model:Destroy() end
			end)
		end
	end
	ActiveEnemies = {}
end

------------------------------------------------------------------------
-- Wave Timer
------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	if not PurgeActive then return end

	WaveTimer += dt
	if WaveTimer >= Config.Purge.WaveIntervalSeconds and CurrentWave < TotalWaves then
		WaveTimer = 0
		task.spawn(function()
			SpawnWave(CurrentWave + 1)
		end)
	end

	-- Send enemy count to clients
	local aliveCount = 0
	for model, _ in pairs(ActiveEnemies) do
		if model.Parent then
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				aliveCount += 1
			end
		end
	end

	UpdateHUD:FireAllClients("PurgeStatus", {
		wave = CurrentWave,
		totalWaves = TotalWaves,
		enemiesAlive = aliveCount,
		purgeActive = true,
	})
end)

------------------------------------------------------------------------
-- Listen for Purge start signal from GameManager
------------------------------------------------------------------------
local purgeSignal = game.ServerStorage:WaitForChild("PurgeStartSignal", 30)
if purgeSignal then
	purgeSignal.Event:Connect(OnPurgeStart)
end

-- Listen for purge end
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PurgeEnded = Remotes:WaitForChild("PurgeEnded")

-- We detect purge end when GameManager fires PurgeEnded
-- Since PurgeEnded is a RemoteEvent to clients, we track state changes
RunService.Heartbeat:Connect(function()
	local gameState = GetGameState()
	if gameState and not gameState.purgeActive and PurgeActive then
		OnPurgeEnd()
	end
end)

------------------------------------------------------------------------
-- Expose enemy count for other services
------------------------------------------------------------------------
local getEnemyCount = Instance.new("BindableFunction")
getEnemyCount.Name = "GetPurgeEnemyCount"
getEnemyCount.Parent = game.ServerStorage
getEnemyCount.OnInvoke = function()
	local count = 0
	for model, _ in pairs(ActiveEnemies) do
		if model.Parent then
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				count += 1
			end
		end
	end
	return count
end

print("[PurgeService] Initialized")
