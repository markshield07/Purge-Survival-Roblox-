--[[
	Config.lua
	Central configuration for The Purge: Suburban Survival
	All tunable game constants live here.
]]

local Config = {}

------------------------------------------------------------------------
-- Time & Day Cycle
------------------------------------------------------------------------
Config.DayCycle = {
	DayLengthSeconds = 300,       -- 5 real minutes per in-game day
	NightStartPercent = 0.65,     -- night begins at 65% through the cycle
	DawnPercent = 0.05,           -- dawn at 5%
	PurgeCycleInterval = 3,       -- Purge every N in-game days
	PrePurgeWarningSeconds = 30,  -- siren warning before Purge starts
	PostPurgeGraceSeconds = 15,   -- grace period after surviving
}

------------------------------------------------------------------------
-- Player
------------------------------------------------------------------------
Config.Player = {
	MaxHealth = 100,
	BaseWalkSpeed = 16,
	BaseSprintSpeed = 24,
	DownedCrawlSpeed = 4,
	ReviveTimeSeconds = 5,
	MaxInventorySlots = 15,
	MaxInventorySlotsVIP = 20,
	InteractRange = 8,
	PickupRange = 6,
}

------------------------------------------------------------------------
-- Hunger System
------------------------------------------------------------------------
Config.Hunger = {
	MaxHunger = 100,
	PassiveDrainPerSecond = 0.15,      -- base passive drain
	SprintDrainMultiplier = 2.5,        -- drain multiplier when sprinting
	FightDrainMultiplier = 2.0,         -- drain multiplier when in combat
	CarryHeavyDrainMultiplier = 1.5,    -- drain multiplier when carrying heavy loot
	PurgeDrainMultiplier = 1.8,         -- drain multiplier during Purge

	-- Thresholds
	FullThreshold = 80,                 -- >= 80 = Full
	SatisfiedThreshold = 50,            -- >= 50 = Satisfied
	HungryThreshold = 25,              -- >= 25 = Hungry
	-- below 25 = Starving

	-- Effects
	FullStaminaBoost = 1.2,             -- 20% stamina boost
	FullHealthRegen = 0.5,              -- HP/sec regen when full
	HungrySprintReduction = 0.75,       -- 25% slower sprint
	HungryMeleeDamageReduction = 0.8,   -- 20% less melee damage
	StarvingHealthDrain = 1.0,          -- HP/sec lost when starving
}

------------------------------------------------------------------------
-- Food & Cooking
------------------------------------------------------------------------
Config.Food = {
	RawSpoilDays = 1,            -- raw food spoils in 1 day cycle
	CookedSpoilDays = 3,         -- cooked food spoils in 3 day cycles
	CannedSpoilDays = -1,        -- -1 = never spoils
	FridgeMultiplier = 3,        -- fridge extends freshness by 3x
	SicknessChanceRaw = 0.35,    -- 35% chance of sickness from raw meat
	SicknessDuration = 30,       -- seconds of nausea debuff
}

------------------------------------------------------------------------
-- Electricity / Generator
------------------------------------------------------------------------
Config.Generator = {
	-- Fuel capacity per tier (units)
	FuelCapacity = { 100, 175, 300, 300 },
	-- Fuel consumption per second per tier (base)
	BaseFuelDrain = { 0.5, 0.35, 0.2, 0.2 },
	-- Additional drain per powered system
	PerSystemDrain = 0.05,
	-- Noise radius per tier (attracts enemies during Purge)
	NoiseRadius = { 60, 40, 15, 15 },
	-- Flicker chance per tick per tier
	FlickerChance = { 0.02, 0.005, 0, 0 },
	-- Solar passive charge rate (tier 4 only, daytime)
	SolarChargeRate = 0.3,
}

-- Systems that consume power
Config.PoweredSystems = {
	Lights = { drain = 0.03, name = "House Lights" },
	Fridge = { drain = 0.04, name = "Refrigerator" },
	ElectricFence = { drain = 0.08, name = "Electric Fence" },
	Turret = { drain = 0.1, name = "Automated Turret" },
	Floodlight = { drain = 0.05, name = "Floodlights" },
	SecurityAlarm = { drain = 0.02, name = "Security Alarm" },
}

------------------------------------------------------------------------
-- Fortification
------------------------------------------------------------------------
Config.Fortification = {
	-- Durability multipliers by tier
	TierDurability = {
		Common = 50,
		Uncommon = 150,
		Rare = 400,
		Epic = 0, -- Epic items are active systems, not passive barriers
	},
	-- Slot counts on starter house
	WindowCount = 6,
	WallSectionCount = 4,
	RoofSectionCount = 2,
}

------------------------------------------------------------------------
-- Purge
------------------------------------------------------------------------
Config.Purge = {
	-- Base enemy count (multiplied by purge number and player count)
	BaseEnemyCount = 5,
	PlayerCountMultiplier = 1.5,  -- multiply enemy count per extra player
	PurgeNumberMultiplier = 1.3,  -- multiply enemy count per purge number

	-- Duration in seconds per purge number (base + scaling)
	BaseDurationSeconds = 180,    -- 3 minutes
	DurationScalePerPurge = 30,   -- +30 sec per purge number

	-- Wave timing
	WaveIntervalSeconds = 20,     -- time between waves
	EnemiesPerWave = 3,           -- base enemies per wave

	-- Difficulty thresholds for new enemy types
	FirearmsStartPurge = 3,       -- firearms appear at purge 3+
	ExplosivesStartPurge = 4,     -- explosives appear at purge 4+
	ArmoredStartPurge = 4,        -- armored enemies at purge 4+
	BossStartPurge = 4,           -- boss appears at purge 4+
	PowerCutStartPurge = 3,       -- enemies target generator at purge 3+

	-- Rewards
	BaseScrapReward = 50,
	ScrapPerPurgeLevel = 25,
}

------------------------------------------------------------------------
-- NPC / Enemy Stats
------------------------------------------------------------------------
Config.NPCStats = {
	-- House defenders
	StrayDog = { health = 30, damage = 8, speed = 18, attackRange = 4 },
	WeakResident = { health = 50, damage = 12, speed = 12, attackRange = 5 },
	ArmedResident = { health = 80, damage = 20, speed = 14, attackRange = 30 },
	GuardDog = { health = 50, damage = 15, speed = 20, attackRange = 4 },
	HeavyResident = { health = 120, damage = 25, speed = 12, attackRange = 35 },
	HouseBoss = { health = 250, damage = 35, speed = 14, attackRange = 40 },

	-- Purge enemies
	MaskedAttacker = { health = 60, damage = 15, speed = 16, attackRange = 5 },
	ArmedAttacker = { health = 80, damage = 25, speed = 14, attackRange = 35 },
	BreacherAttacker = { health = 100, damage = 30, speed = 14, attackRange = 5, barricadeDamageMultiplier = 3 },
	ArmoredAttacker = { health = 200, damage = 20, speed = 10, attackRange = 30 },
	ExplosiveAttacker = { health = 70, damage = 50, speed = 12, attackRange = 20, aoeRadius = 15 },
	PurgeBoss = { health = 500, damage = 40, speed = 16, attackRange = 40 },

	-- Wildlife
	Rabbit = { health = 10, damage = 0, speed = 22, fleeRange = 30 },
	Squirrel = { health = 8, damage = 0, speed = 24, fleeRange = 25 },
	Raccoon = { health = 20, damage = 5, speed = 16, fleeRange = 20 },
	Bird = { health = 8, damage = 0, speed = 28, fleeRange = 40 },
	Deer = { health = 60, damage = 0, speed = 26, fleeRange = 50 },
	StrayDogWild = { health = 40, damage = 10, speed = 18, fleeRange = 15 },
}

------------------------------------------------------------------------
-- Loot
------------------------------------------------------------------------
Config.Loot = {
	-- Max items per house by zone
	MaxItemsPerHouse = { 4, 7, 12 },   -- Zone 1, 2, 3
	-- Respawn time in day cycles
	HouseRespawnDays = 2,
	-- Tier weights by zone [Common, Uncommon, Rare, Epic]
	TierWeights = {
		[1] = { 0.70, 0.25, 0.05, 0.00 },
		[2] = { 0.30, 0.50, 0.18, 0.02 },
		[3] = { 0.10, 0.30, 0.45, 0.15 },
	},
	-- Bonus location loot multipliers
	BonusMultiplier = {
		HardwareStore = 1.5,
		PoliceStation = 1.3,
		GasStation = 1.2,
		AbandonedSchool = 1.4,
		UndergroundBunker = 2.0,
	},
}

------------------------------------------------------------------------
-- Combat
------------------------------------------------------------------------
Config.Combat = {
	MeleeSwingCooldown = 0.6,     -- seconds between melee swings
	RangedFireCooldown = 0.3,     -- seconds between ranged shots
	HeadshotMultiplier = 2.0,
	DownedBleedoutTime = 45,      -- seconds before downed player dies
	InvulnAfterRevive = 3,        -- seconds of invuln after revive
}

------------------------------------------------------------------------
-- Map Dimensions (studs)
------------------------------------------------------------------------
Config.Map = {
	TotalWidth = 1200,
	TotalLength = 1600,
	StreetWidth = 40,
	HouseSpacing = 20,
	Zone1Radius = 300,    -- from starter house center
	Zone2Radius = 600,
	Zone3Radius = 1000,
	PurgeSpawnRadius = 800, -- enemy spawn distance from house
}

------------------------------------------------------------------------
-- Monetization Product IDs (placeholder)
------------------------------------------------------------------------
Config.GamePasses = {
	ExtraInventory = 0,      -- replace with real IDs
	DoubleStarterHouse = 0,
	RadioMusic = 0,
	PrivateServer = 0,
	VIPPass = 0,
}

Config.DeveloperProducts = {
	PurgeCoins100 = 0,
	PurgeCoins500 = 0,
	PurgeCoins1200 = 0,
}

return Config
