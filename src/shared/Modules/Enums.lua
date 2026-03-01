--[[
	Enums.lua
	Shared enumerations for The Purge: Suburban Survival
]]

local Enums = {}

-- Game phases
Enums.GamePhase = {
	Lobby = "Lobby",
	Scavenging = "Scavenging",
	PrePurge = "PrePurge",
	Purge = "Purge",
	PostPurge = "PostPurge",
}

-- Map zones
Enums.Zone = {
	Starter = 0,
	Zone1 = 1,
	Zone2 = 2,
	Zone3 = 3,
	Bonus = 4,
}

-- Item tiers
Enums.ItemTier = {
	Common = "Common",
	Uncommon = "Uncommon",
	Rare = "Rare",
	Epic = "Epic",
}

-- Item tier colors (for UI)
Enums.TierColor = {
	Common = Color3.fromRGB(255, 255, 255),
	Uncommon = Color3.fromRGB(0, 255, 0),
	Rare = Color3.fromRGB(0, 120, 255),
	Epic = Color3.fromRGB(180, 0, 255),
}

-- Item categories
Enums.ItemCategory = {
	BuildingMaterial = "BuildingMaterial",
	Food = "Food",
	Fuel = "Fuel",
	Weapon = "Weapon",
	Tool = "Tool",
	Trap = "Trap",
	LightSource = "LightSource",
	GeneratorPart = "GeneratorPart",
	CookingStation = "CookingStation",
	Seed = "Seed",
	Recipe = "Recipe",
	Cosmetic = "Cosmetic",
	Ammo = "Ammo",
}

-- Hunger levels
Enums.HungerLevel = {
	Full = "Full",
	Satisfied = "Satisfied",
	Hungry = "Hungry",
	Starving = "Starving",
}

-- Cooking station types
Enums.CookingStation = {
	Campfire = "Campfire",
	Stove = "Stove",
	FullKitchen = "FullKitchen",
}

-- Fortification slot types
Enums.FortSlot = {
	FrontDoor = "FrontDoor",
	BackDoor = "BackDoor",
	Window = "Window",
	WallSection = "WallSection",
	RoofSection = "RoofSection",
	YardBarricade = "YardBarricade",
	HallwayTrap = "HallwayTrap",
	SafeRoom = "SafeRoom",
	Floodlight = "Floodlight",
	ElectricFence = "ElectricFence",
	Turret = "Turret",
}

-- Generator tiers
Enums.GeneratorTier = {
	Busted = 1,
	Repaired = 2,
	HeavyDuty = 3,
	SolarBackup = 4,
}

-- NPC types
Enums.NPCType = {
	-- House defenders
	StrayDog = "StrayDog",
	WeakResident = "WeakResident",
	ArmedResident = "ArmedResident",
	GuardDog = "GuardDog",
	HeavyResident = "HeavyResident",
	HouseBoss = "HouseBoss",
	-- Purge enemies
	MaskedAttacker = "MaskedAttacker",
	ArmedAttacker = "ArmedAttacker",
	BreacherAttacker = "BreacherAttacker",
	ArmoredAttacker = "ArmoredAttacker",
	ExplosiveAttacker = "ExplosiveAttacker",
	PurgeBoss = "PurgeBoss",
	-- Wildlife
	Rabbit = "Rabbit",
	Squirrel = "Squirrel",
	Raccoon = "Raccoon",
	Bird = "Bird",
	Deer = "Deer",
	StrayDogWild = "StrayDogWild",
}

-- Player states
Enums.PlayerState = {
	Alive = "Alive",
	Downed = "Downed",
	Dead = "Dead",
	Reviving = "Reviving",
}

-- Bonus location types
Enums.BonusLocation = {
	HardwareStore = "HardwareStore",
	PoliceStation = "PoliceStation",
	GasStation = "GasStation",
	AbandonedSchool = "AbandonedSchool",
	UndergroundBunker = "UndergroundBunker",
}

-- Weapon types
Enums.WeaponType = {
	Melee = "Melee",
	Ranged = "Ranged",
}

-- Light source types
Enums.LightSource = {
	Flashlight = "Flashlight",
	Candle = "Candle",
	Flare = "Flare",
	GlowStick = "GlowStick",
	BarrelFire = "BarrelFire",
}

-- Currency types
Enums.Currency = {
	Scrap = "Scrap",
	PurgeCoins = "PurgeCoins",
}

-- Game mode
Enums.GameMode = {
	Endless = "Endless",
	SurviveX = "SurviveX",
	Escape = "Escape",
}

return Enums
