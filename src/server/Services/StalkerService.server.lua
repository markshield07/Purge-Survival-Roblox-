--[[
	StalkerService.server.lua
	The Stalker – an unkillable night hunter (inspired by The Deer from 99 Nights).
	Spawns at night starting Day 2, repelled by campfire safe zone and flashlights.
	Cannot be killed. Chases players outside the safe zone with increasing speed.
	Has a "hungry" frenzy state on certain nights.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local Utils = require(Modules.Utils)

------------------------------------------------------------------------
-- Wait for Remotes
------------------------------------------------------------------------
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")

-- Create stalker-specific remotes
local StalkerAlert = Instance.new("RemoteEvent")
StalkerAlert.Name = "StalkerAlert"
StalkerAlert.Parent = Remotes

------------------------------------------------------------------------
-- Stalker State
------------------------------------------------------------------------
local StalkerState = {
	status = Enums.StalkerState.Dormant,
	isSpawned = false,
	isHungry = false,
	currentTarget = nil,
	chaseStartTime = 0,
	currentSpeed = Config.Stalker.BaseSpeed,
	stunEndTime = 0,
	lastAttackTime = 0,
	model = nil,
}

------------------------------------------------------------------------
-- Create Stalker Model
------------------------------------------------------------------------
local function CreateStalkerModel(spawnPosition: Vector3)
	local model = Instance.new("Model")
	model.Name = "TheStalker"

	-- Torso (main body)
	local torso = Instance.new("Part")
	torso.Name = "HumanoidRootPart"
	torso.Size = Vector3.new(3, 5, 2)
	torso.Position = spawnPosition + Vector3.new(0, 3, 0)
	torso.Anchored = false
	torso.CanCollide = true
	torso.Material = Enum.Material.SmoothPlastic
	torso.BrickColor = BrickColor.new("Really black")
	torso.Parent = model

	-- Head with glowing eyes
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(3, 3, 3)
	head.Shape = Enum.PartType.Ball
	head.Material = Enum.Material.SmoothPlastic
	head.BrickColor = BrickColor.new("Really black")
	head.Parent = model

	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = torso
	headWeld.Part1 = head
	headWeld.Parent = head
	head.Position = torso.Position + Vector3.new(0, 4, 0)

	-- Glowing eyes
	local leftEye = Instance.new("Part")
	leftEye.Name = "LeftEye"
	leftEye.Size = Vector3.new(0.5, 0.5, 0.1)
	leftEye.Material = Enum.Material.Neon
	leftEye.BrickColor = BrickColor.new("Bright red")
	leftEye.CanCollide = false
	leftEye.Parent = model

	local leftEyeWeld = Instance.new("WeldConstraint")
	leftEyeWeld.Part0 = head
	leftEyeWeld.Part1 = leftEye
	leftEyeWeld.Parent = leftEye
	leftEye.Position = head.Position + Vector3.new(-0.6, 0.3, -1.3)

	local rightEye = leftEye:Clone()
	rightEye.Name = "RightEye"
	rightEye.Parent = model
	local rightEyeWeld = Instance.new("WeldConstraint")
	rightEyeWeld.Part0 = head
	rightEyeWeld.Part1 = rightEye
	rightEyeWeld.Parent = rightEye
	rightEye.Position = head.Position + Vector3.new(0.6, 0.3, -1.3)

	-- Antler-like protrusions
	for i, offset in ipairs({Vector3.new(-1, 2, 0), Vector3.new(1, 2, 0)}) do
		local antler = Instance.new("Part")
		antler.Name = "Antler" .. i
		antler.Size = Vector3.new(0.3, 2, 0.3)
		antler.Material = Enum.Material.SmoothPlastic
		antler.BrickColor = BrickColor.new("Dark stone grey")
		antler.CanCollide = false
		antler.Parent = model

		local antlerWeld = Instance.new("WeldConstraint")
		antlerWeld.Part0 = head
		antlerWeld.Part1 = antler
		antlerWeld.Parent = antler
		antler.Position = head.Position + offset
	end

	-- Humanoid for pathfinding
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.WalkSpeed = Config.Stalker.BaseSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	-- Make it unkillable: heal back to full on any damage
	humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth < math.huge then
			humanoid.Health = math.huge
		end
	end)

	-- Eerie point light
	local glow = Instance.new("PointLight")
	glow.Brightness = 0.5
	glow.Range = 8
	glow.Color = Color3.fromRGB(255, 0, 0)
	glow.Parent = torso

	-- Ambient smoke
	local smoke = Instance.new("Smoke")
	smoke.Size = 2
	smoke.Opacity = 0.15
	smoke.RiseVelocity = 1
	smoke.Color = Color3.fromRGB(30, 0, 30)
	smoke.Parent = torso

	model.PrimaryPart = torso
	CollectionService:AddTag(model, "Stalker")
	model.Parent = workspace

	return model
end

------------------------------------------------------------------------
-- Core Logic
------------------------------------------------------------------------
local function GetSpawnPosition(): Vector3
	-- Spawn far from campfire, at the edge of detection radius
	local GetCampfireState = game.ServerStorage:FindFirstChild("GetCampfireState")
	local campPos = Vector3.new(0, 0, 0)
	if GetCampfireState then
		local cs = GetCampfireState:Invoke()
		campPos = cs.position or Vector3.zero
	end

	local angle = math.random() * math.pi * 2
	local dist = Config.Stalker.DetectionRadius + 50
	return campPos + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
end

local function IsInSafeZone(position: Vector3): boolean
	local IsInSafeZoneBF = game.ServerStorage:FindFirstChild("IsInSafeZone")
	if not IsInSafeZoneBF then return false end

	-- Check against campfire position/radius directly
	local GetCampfireState = game.ServerStorage:FindFirstChild("GetCampfireState")
	if not GetCampfireState then return false end

	local cs = GetCampfireState:Invoke()
	if not cs or not cs.isLit then return false end

	local dist = (position - (cs.position or Vector3.zero)).Magnitude
	return dist <= cs.safeZoneRadius
end

local function FindTarget(): Player?
	local GetCampfireState = game.ServerStorage:FindFirstChild("GetCampfireState")
	local cs = GetCampfireState and GetCampfireState:Invoke()

	local bestTarget = nil
	local bestDist = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not char then continue end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end

		-- Skip players in safe zone
		if cs and cs.isLit then
			local distToCamp = (root.Position - (cs.position or Vector3.zero)).Magnitude
			if distToCamp <= cs.safeZoneRadius then continue end
		end

		-- Skip players checking GetPlayerState for downed/dead
		local GetPlayerState = game.ServerStorage:FindFirstChild("GetPlayerState")
		if GetPlayerState then
			local ps = GetPlayerState:Invoke(player)
			if ps and ps.state ~= Enums.PlayerState.Alive then continue end
		end

		if not StalkerState.model then continue end
		local dist = (root.Position - StalkerState.model.PrimaryPart.Position).Magnitude
		if dist < bestDist and dist <= Config.Stalker.DetectionRadius then
			bestDist = dist
			bestTarget = player
		end
	end

	return bestTarget
end

local function SpawnStalker()
	if StalkerState.isSpawned then return end

	local spawnPos = GetSpawnPosition()
	StalkerState.model = CreateStalkerModel(spawnPos)
	StalkerState.isSpawned = true
	StalkerState.status = Enums.StalkerState.Hunting
	StalkerState.currentSpeed = Config.Stalker.BaseSpeed
	StalkerState.chaseStartTime = 0

	-- Check if hungry tonight
	StalkerState.isHungry = math.random() < Config.Stalker.HungryChance
	if StalkerState.isHungry then
		StalkerState.status = Enums.StalkerState.Hungry
		StalkerState.currentSpeed = Config.Stalker.BaseSpeed * Config.Stalker.HungrySpeedBoost

		-- Change eye color to brighter red
		if StalkerState.model then
			for _, part in ipairs(StalkerState.model:GetDescendants()) do
				if part.Name == "LeftEye" or part.Name == "RightEye" then
					part.BrickColor = BrickColor.new("Really red")
					part.Size = Vector3.new(0.7, 0.7, 0.1)
				end
			end
		end

		-- Warn players
		task.defer(function()
			task.wait(2)
			NotifyPlayers:FireAllClients(
				"The Stalker is hungry tonight...",
				Color3.fromRGB(255, 0, 0)
			)
			task.wait(3)
			NotifyPlayers:FireAllClients(
				"Night is approaching. The Stalker is hungry tonight.",
				Color3.fromRGB(255, 50, 0)
			)
		end)
	end

	StalkerAlert:FireAllClients("Spawned", StalkerState.isHungry)
end

local function DespawnStalker()
	if not StalkerState.isSpawned then return end

	if StalkerState.model then
		StalkerState.model:Destroy()
		StalkerState.model = nil
	end

	StalkerState.isSpawned = false
	StalkerState.status = Enums.StalkerState.Dormant
	StalkerState.currentTarget = nil
	StalkerState.chaseStartTime = 0
	StalkerState.isHungry = false

	StalkerAlert:FireAllClients("Despawned")
end

local function StunStalker(duration: number)
	if StalkerState.status == Enums.StalkerState.Stunned then return end

	local actualDuration = duration
	if StalkerState.isHungry then
		actualDuration = duration * Config.Stalker.HungryStunResist
	end

	StalkerState.status = Enums.StalkerState.Stunned
	StalkerState.stunEndTime = tick() + actualDuration
	StalkerState.currentTarget = nil
	StalkerState.chaseStartTime = 0

	-- Reset speed on stun
	StalkerState.currentSpeed = Config.Stalker.BaseSpeed
	if StalkerState.isHungry then
		StalkerState.currentSpeed = StalkerState.currentSpeed * Config.Stalker.HungrySpeedBoost
	end

	if StalkerState.model then
		local hum = StalkerState.model:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = 0
		end
	end

	StalkerAlert:FireAllClients("Stunned", actualDuration)
end

local function AttackTarget(target: Player)
	local now = tick()
	if now - StalkerState.lastAttackTime < Config.Stalker.AttackCooldown then return end

	StalkerState.lastAttackTime = now

	local GetGameState = game.ServerStorage:FindFirstChild("GetGameState")
	local currentDay = 1
	if GetGameState then
		local gs = GetGameState:Invoke()
		currentDay = gs.currentDay or 1
	end

	local baseDamage = Config.Stalker.Damage + (Config.Stalker.DamageScalePerDay * currentDay)
	if StalkerState.isHungry then
		baseDamage = baseDamage * Config.Stalker.HungryDamageBoost
	end

	local DamagePlayer = game.ServerStorage:FindFirstChild("DamagePlayer")
	if DamagePlayer then
		DamagePlayer:Invoke(target, baseDamage)
	end

	StalkerAlert:FireAllClients("Attack", target)
end

------------------------------------------------------------------------
-- Chase AI Update
------------------------------------------------------------------------
local function UpdateStalkerAI(dt: number)
	if not StalkerState.isSpawned or not StalkerState.model then return end
	if not StalkerState.model.PrimaryPart then
		DespawnStalker()
		return
	end

	local hum = StalkerState.model:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- Handle stun
	if StalkerState.status == Enums.StalkerState.Stunned then
		if tick() >= StalkerState.stunEndTime then
			StalkerState.status = StalkerState.isHungry and Enums.StalkerState.Hungry or Enums.StalkerState.Hunting
			hum.WalkSpeed = StalkerState.currentSpeed
		end
		return
	end

	-- Check if stalker wandered into safe zone - repel it
	if IsInSafeZone(StalkerState.model.PrimaryPart.Position) then
		-- Push away from campfire
		local GetCampfireState = game.ServerStorage:FindFirstChild("GetCampfireState")
		if GetCampfireState then
			local cs = GetCampfireState:Invoke()
			local awayDir = (StalkerState.model.PrimaryPart.Position - (cs.position or Vector3.zero)).Unit
			local retreatPos = (cs.position or Vector3.zero) + awayDir * (cs.safeZoneRadius + 20)
			hum:MoveTo(retreatPos)
		end
		return
	end

	-- Find or update target
	local target = FindTarget()

	if target then
		StalkerState.currentTarget = target

		if StalkerState.chaseStartTime == 0 then
			StalkerState.chaseStartTime = tick()
		end

		local char = target.Character
		if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then return end

		-- Increase speed during chase
		local chaseTime = tick() - StalkerState.chaseStartTime
		StalkerState.currentSpeed = math.min(
			Config.Stalker.MaxChaseSpeed,
			(StalkerState.isHungry and Config.Stalker.BaseSpeed * Config.Stalker.HungrySpeedBoost or Config.Stalker.BaseSpeed)
				+ (chaseTime * Config.Stalker.ChaseSpeedIncrease)
		)
		hum.WalkSpeed = StalkerState.currentSpeed

		-- Move toward target
		local dist = (root.Position - StalkerState.model.PrimaryPart.Position).Magnitude

		-- Close enough to attack
		if dist <= 6 then
			AttackTarget(target)
		end

		-- Pathfind to target
		hum:MoveTo(root.Position)

		StalkerState.status = StalkerState.isHungry and Enums.StalkerState.Hungry or Enums.StalkerState.Chasing
	else
		-- No target - wander
		StalkerState.currentTarget = nil
		StalkerState.chaseStartTime = 0
		StalkerState.currentSpeed = Config.Stalker.BaseSpeed * 0.5
		hum.WalkSpeed = StalkerState.currentSpeed
		StalkerState.status = StalkerState.isHungry and Enums.StalkerState.Hungry or Enums.StalkerState.Hunting

		-- Wander randomly near campfire edge
		if math.random() < 0.01 then  -- occasionally pick new wander point
			local GetCampfireState = game.ServerStorage:FindFirstChild("GetCampfireState")
			if GetCampfireState then
				local cs = GetCampfireState:Invoke()
				local angle = math.random() * math.pi * 2
				local dist = cs.safeZoneRadius + 20 + math.random(0, 50)
				local wanderPos = (cs.position or Vector3.zero) + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
				hum:MoveTo(wanderPos)
			end
		end
	end
end

------------------------------------------------------------------------
-- Flashlight Stun Handler
------------------------------------------------------------------------
local FlashlightStun = Instance.new("RemoteEvent")
FlashlightStun.Name = "FlashlightStun"
FlashlightStun.Parent = Remotes

FlashlightStun.OnServerEvent:Connect(function(player)
	if not StalkerState.isSpawned or not StalkerState.model then return end

	-- Check if player is pointing flashlight at the stalker (within range)
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local dist = (root.Position - StalkerState.model.PrimaryPart.Position).Magnitude
	if dist > 40 then return end  -- flashlight range

	StunStalker(Config.Stalker.FlashlightStunDuration)
end)

------------------------------------------------------------------------
-- Main Loop
------------------------------------------------------------------------
task.defer(function()
	task.wait(3)  -- wait for other services to init

	RunService.Heartbeat:Connect(function(dt)
		local GetGameState = game.ServerStorage:FindFirstChild("GetGameState")
		if not GetGameState then return end

		local gs = GetGameState:Invoke()
		if not gs or not gs.sessionStarted then return end

		-- Check day/night status
		local timePercent = gs.dayTimeElapsed / Config.DayCycle.DayLengthSeconds
		local isNight = timePercent >= Config.DayCycle.NightStartPercent

		-- Only spawn after configured day
		local canSpawn = gs.currentDay >= Config.Stalker.SpawnDay

		if isNight and canSpawn then
			if not StalkerState.isSpawned then
				SpawnStalker()
			end
			UpdateStalkerAI(dt)
		elseif not isNight and StalkerState.isSpawned then
			-- Dawn - despawn
			if Config.Stalker.DespawnAtDawn then
				StalkerAlert:FireAllClients("Fleeing")
				task.delay(3, DespawnStalker)
			end
		end
	end)
end)

------------------------------------------------------------------------
-- Expose for other services
------------------------------------------------------------------------
local GetStalkerState = Instance.new("BindableFunction")
GetStalkerState.Name = "GetStalkerState"
GetStalkerState.Parent = game.ServerStorage
GetStalkerState.OnInvoke = function()
	return StalkerState
end
