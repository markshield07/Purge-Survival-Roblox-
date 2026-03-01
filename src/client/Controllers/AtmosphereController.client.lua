--[[
	AtmosphereController.client.lua
	Full audio and visual effects system.
	- Phase-based ambient audio (day, night, purge)
	- Combat sounds (melee, ranged, impacts)
	- Item pickup / UI sounds
	- Environmental particles (rain, fog, fireflies)
	- Screen effects (blur, vignette, shake, color grading)
	- Generator hum / power events
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GamePhaseChanged = Remotes:WaitForChild("GamePhaseChanged")
local PurgeSiren = Remotes:WaitForChild("PurgeSiren")
local PurgeStarted = Remotes:WaitForChild("PurgeStarted")
local PurgeEnded = Remotes:WaitForChild("PurgeEnded")
local PowerOutAlert = Remotes:WaitForChild("PowerOutAlert")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")
local PlayerDowned = Remotes:WaitForChild("PlayerDowned")

------------------------------------------------------------------------
-- Sound Setup
------------------------------------------------------------------------
local function CreateSound(name: string, soundId: string, properties)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = properties and properties.Volume or 0.5
	sound.Looped = properties and properties.Looped or false
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.Parent = SoundService
	return sound
end

-- Ambient sounds (placeholder IDs - replace with real uploaded audio)
local Sounds = {
	-- Phase ambience
	DayAmbient     = CreateSound("DayAmbient", "rbxassetid://0", { Volume = 0.3, Looped = true }),
	NightAmbient   = CreateSound("NightAmbient", "rbxassetid://0", { Volume = 0.4, Looped = true }),
	PurgeAmbient   = CreateSound("PurgeAmbient", "rbxassetid://0", { Volume = 0.5, Looped = true }),

	-- Events
	Siren          = CreateSound("Siren", "rbxassetid://0", { Volume = 0.8, Looped = false }),
	PurgeHorn      = CreateSound("PurgeHorn", "rbxassetid://0", { Volume = 0.9, Looped = false }),
	VictoryStinger = CreateSound("VictoryStinger", "rbxassetid://0", { Volume = 0.7, Looped = false }),

	-- Generator
	GeneratorHum   = CreateSound("GeneratorHum", "rbxassetid://0", { Volume = 0.2, Looped = true }),
	PowerDown      = CreateSound("PowerDown", "rbxassetid://0", { Volume = 0.7, Looped = false }),

	-- Danger
	Heartbeat      = CreateSound("Heartbeat", "rbxassetid://0", { Volume = 0.6, Looped = true }),

	-- Combat
	MeleeSwing     = CreateSound("MeleeSwing", "rbxassetid://0", { Volume = 0.5, Looped = false }),
	MeleeHit       = CreateSound("MeleeHit", "rbxassetid://0", { Volume = 0.6, Looped = false }),
	GunShot        = CreateSound("GunShot", "rbxassetid://0", { Volume = 0.7, Looped = false }),
	ShotgunBlast   = CreateSound("ShotgunBlast", "rbxassetid://0", { Volume = 0.8, Looped = false }),
	RifleShot      = CreateSound("RifleShot", "rbxassetid://0", { Volume = 0.7, Looped = false }),
	BulletImpact   = CreateSound("BulletImpact", "rbxassetid://0", { Volume = 0.4, Looped = false }),
	EnemyHurt      = CreateSound("EnemyHurt", "rbxassetid://0", { Volume = 0.5, Looped = false }),
	PlayerHurt     = CreateSound("PlayerHurt", "rbxassetid://0", { Volume = 0.6, Looped = false }),

	-- UI / Interaction
	ItemPickup     = CreateSound("ItemPickup", "rbxassetid://0", { Volume = 0.4, Looped = false }),
	ItemEquip      = CreateSound("ItemEquip", "rbxassetid://0", { Volume = 0.3, Looped = false }),
	Notification   = CreateSound("Notification", "rbxassetid://0", { Volume = 0.3, Looped = false }),
	FortifyHammer  = CreateSound("FortifyHammer", "rbxassetid://0", { Volume = 0.5, Looped = false }),
	DoorCreak      = CreateSound("DoorCreak", "rbxassetid://0", { Volume = 0.4, Looped = false }),
	CookingFire    = CreateSound("CookingFire", "rbxassetid://0", { Volume = 0.3, Looped = true }),

	-- Environment
	WindLoop       = CreateSound("WindLoop", "rbxassetid://0", { Volume = 0.15, Looped = true }),
	BirdsChirp     = CreateSound("BirdsChirp", "rbxassetid://0", { Volume = 0.2, Looped = true }),
	CricketsNight  = CreateSound("CricketsNight", "rbxassetid://0", { Volume = 0.2, Looped = true }),
	ThunderRumble  = CreateSound("ThunderRumble", "rbxassetid://0", { Volume = 0.7, Looped = false }),
	RainLoop       = CreateSound("RainLoop", "rbxassetid://0", { Volume = 0.3, Looped = true }),
}

------------------------------------------------------------------------
-- Post-Processing Effects
------------------------------------------------------------------------
local blur = Instance.new("BlurEffect")
blur.Name = "PurgeBlur"
blur.Size = 0
blur.Enabled = true
blur.Parent = Lighting

local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Name = "PurgeColor"
colorCorrection.Brightness = 0
colorCorrection.Contrast = 0
colorCorrection.Saturation = 0
colorCorrection.TintColor = Color3.new(1, 1, 1)
colorCorrection.Parent = Lighting

local dangerVignette = Instance.new("ColorCorrectionEffect")
dangerVignette.Name = "DangerVignette"
dangerVignette.Brightness = 0
dangerVignette.Contrast = 0
dangerVignette.Saturation = 0
dangerVignette.TintColor = Color3.new(1, 1, 1)
dangerVignette.Parent = Lighting

-- Atmosphere for fog/weather
local atmosphere = Instance.new("Atmosphere")
atmosphere.Name = "WeatherAtmosphere"
atmosphere.Density = 0.15
atmosphere.Offset = 0
atmosphere.Color = Color3.fromRGB(199, 199, 199)
atmosphere.Decay = Color3.fromRGB(92, 60, 13)
atmosphere.Glare = 0
atmosphere.Haze = 0
atmosphere.Parent = Lighting

-- Sun rays for daytime
local sunRays = Instance.new("SunRaysEffect")
sunRays.Name = "SunRays"
sunRays.Intensity = 0.03
sunRays.Spread = 0.5
sunRays.Parent = Lighting

------------------------------------------------------------------------
-- Particle Systems (attached to camera or workspace)
------------------------------------------------------------------------
local rainEmitter = nil

local function CreateRainEffect()
	if rainEmitter then return end

	-- Create a part high above the player for rain
	local rainPart = Instance.new("Part")
	rainPart.Name = "RainEmitter"
	rainPart.Size = Vector3.new(100, 1, 100)
	rainPart.Transparency = 1
	rainPart.CanCollide = false
	rainPart.Anchored = true
	rainPart.Position = Vector3.new(0, 80, 0)
	rainPart.Parent = workspace

	rainEmitter = Instance.new("ParticleEmitter")
	rainEmitter.Name = "Rain"
	rainEmitter.Rate = 200
	rainEmitter.Lifetime = NumberRange.new(1, 2)
	rainEmitter.Speed = NumberRange.new(40, 60)
	rainEmitter.SpreadAngle = Vector2.new(5, 5)
	rainEmitter.Size = NumberSequence.new(0.05, 0.05)
	rainEmitter.Color = ColorSequence.new(Color3.fromRGB(160, 170, 190))
	rainEmitter.Transparency = NumberSequence.new(0.3, 0.7)
	rainEmitter.LightEmission = 0.1
	rainEmitter.EmissionDirection = Enum.NormalId.Bottom
	rainEmitter.Enabled = false
	rainEmitter.Parent = rainPart

	-- Follow player
	RunService.Heartbeat:Connect(function()
		local char = Player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			rainPart.Position = char.HumanoidRootPart.Position + Vector3.new(0, 60, 0)
		end
	end)
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local CurrentPhase = Enums.GamePhase.Lobby
local GeneratorPowered = true
local IsInDanger = false
local CameraShakeIntensity = 0

------------------------------------------------------------------------
-- Camera Shake
------------------------------------------------------------------------
local function ApplyCameraShake(dt)
	if CameraShakeIntensity <= 0 then return end

	local camera = workspace.CurrentCamera
	if camera then
		local shakeOffset = CFrame.new(
			math.random() * CameraShakeIntensity * 2 - CameraShakeIntensity,
			math.random() * CameraShakeIntensity * 2 - CameraShakeIntensity,
			0
		) * CFrame.Angles(
			math.rad(math.random() * CameraShakeIntensity),
			math.rad(math.random() * CameraShakeIntensity),
			0
		)
		camera.CFrame = camera.CFrame * shakeOffset
	end

	CameraShakeIntensity = CameraShakeIntensity * 0.95
	if CameraShakeIntensity < 0.01 then
		CameraShakeIntensity = 0
	end
end

------------------------------------------------------------------------
-- Atmosphere Transitions
------------------------------------------------------------------------
local function StopAllAmbient()
	Sounds.DayAmbient:Stop()
	Sounds.NightAmbient:Stop()
	Sounds.PurgeAmbient:Stop()
	Sounds.BirdsChirp:Stop()
	Sounds.CricketsNight:Stop()
	Sounds.RainLoop:Stop()
	if rainEmitter then rainEmitter.Enabled = false end
end

local function TransitionToDay()
	StopAllAmbient()

	TweenService:Create(colorCorrection, TweenInfo.new(3), {
		Brightness = 0,
		Contrast = 0,
		Saturation = 0.05,
		TintColor = Color3.new(1, 1, 1),
	}):Play()

	TweenService:Create(blur, TweenInfo.new(2), {
		Size = 0,
	}):Play()

	TweenService:Create(atmosphere, TweenInfo.new(3), {
		Density = 0.15,
		Haze = 0,
	}):Play()

	sunRays.Intensity = 0.03

	Sounds.DayAmbient:Play()
	Sounds.BirdsChirp:Play()
	Sounds.WindLoop:Play()
end

local function TransitionToNight()
	StopAllAmbient()

	TweenService:Create(colorCorrection, TweenInfo.new(3), {
		Brightness = -0.05,
		Contrast = 0.1,
		Saturation = -0.2,
		TintColor = Color3.fromRGB(190, 200, 240),
	}):Play()

	TweenService:Create(atmosphere, TweenInfo.new(3), {
		Density = 0.25,
		Haze = 1.5,
	}):Play()

	sunRays.Intensity = 0

	Sounds.NightAmbient:Play()
	Sounds.CricketsNight:Play()
	Sounds.WindLoop:Play()
end

local function TransitionToPurge()
	StopAllAmbient()
	CreateRainEffect()

	-- Dramatic red tint, heavy atmosphere
	TweenService:Create(colorCorrection, TweenInfo.new(1), {
		Brightness = -0.1,
		Contrast = 0.25,
		Saturation = -0.4,
		TintColor = Color3.fromRGB(255, 160, 160),
	}):Play()

	TweenService:Create(atmosphere, TweenInfo.new(2), {
		Density = 0.4,
		Haze = 3,
	}):Play()

	TweenService:Create(blur, TweenInfo.new(0.5), {
		Size = 2,
	}):Play()

	-- Flash effect at purge start
	TweenService:Create(dangerVignette, TweenInfo.new(0.3), {
		Brightness = 0.3,
		TintColor = Color3.fromRGB(255, 100, 100),
	}):Play()
	task.delay(0.5, function()
		TweenService:Create(dangerVignette, TweenInfo.new(1), {
			Brightness = 0,
			TintColor = Color3.new(1, 1, 1),
		}):Play()
	end)

	sunRays.Intensity = 0

	-- Rain during purge
	if rainEmitter then
		rainEmitter.Enabled = true
	end
	Sounds.RainLoop:Play()
	Sounds.PurgeAmbient:Play()
	Sounds.WindLoop:Play()
	Sounds.WindLoop.Volume = 0.35  -- louder wind during purge

	CameraShakeIntensity = 0.4

	-- Thunder rumbles at intervals during purge
	task.spawn(function()
		while CurrentPhase == Enums.GamePhase.Purge do
			task.wait(math.random(8, 20))
			if CurrentPhase ~= Enums.GamePhase.Purge then break end
			Sounds.ThunderRumble:Play()
			CameraShakeIntensity = math.max(CameraShakeIntensity, 0.15)
			-- Lightning flash
			TweenService:Create(dangerVignette, TweenInfo.new(0.1), {
				Brightness = 0.4,
			}):Play()
			task.wait(0.15)
			TweenService:Create(dangerVignette, TweenInfo.new(0.5), {
				Brightness = 0,
			}):Play()
		end
	end)
end

local function TransitionToPostPurge()
	StopAllAmbient()

	TweenService:Create(colorCorrection, TweenInfo.new(3), {
		Brightness = 0.05,
		Contrast = 0,
		Saturation = 0.1,
		TintColor = Color3.fromRGB(255, 240, 220),
	}):Play()

	TweenService:Create(blur, TweenInfo.new(2), {
		Size = 0,
	}):Play()

	TweenService:Create(atmosphere, TweenInfo.new(3), {
		Density = 0.15,
		Haze = 0,
	}):Play()

	Sounds.WindLoop.Volume = 0.15
	Sounds.Heartbeat:Stop()
	Sounds.VictoryStinger:Play()
end

------------------------------------------------------------------------
-- Power Out Effects
------------------------------------------------------------------------
local function OnPowerOut()
	GeneratorPowered = false
	Sounds.GeneratorHum:Stop()
	Sounds.PowerDown:Play()

	TweenService:Create(colorCorrection, TweenInfo.new(0.2), {
		Brightness = -0.3,
		TintColor = Color3.fromRGB(100, 100, 130),
	}):Play()

	Sounds.Heartbeat:Play()
	CameraShakeIntensity = 0.5
end

local function OnPowerRestored()
	GeneratorPowered = true
	Sounds.GeneratorHum:Play()
	Sounds.Heartbeat:Stop()

	TweenService:Create(colorCorrection, TweenInfo.new(1), {
		Brightness = 0,
		TintColor = Color3.new(1, 1, 1),
	}):Play()
end

------------------------------------------------------------------------
-- Starving Effects
------------------------------------------------------------------------
local starvingActive = false

local function UpdateStarvingEffects(hungerLevel)
	if hungerLevel == Enums.HungerLevel.Starving then
		if not starvingActive then
			starvingActive = true
			TweenService:Create(blur, TweenInfo.new(1), {
				Size = 6,
			}):Play()
			TweenService:Create(dangerVignette, TweenInfo.new(1), {
				Saturation = -0.5,
				TintColor = Color3.fromRGB(200, 200, 180),
			}):Play()
			CameraShakeIntensity = math.max(CameraShakeIntensity, 0.15)
		end
	else
		if starvingActive then
			starvingActive = false
			TweenService:Create(blur, TweenInfo.new(1), {
				Size = 0,
			}):Play()
			TweenService:Create(dangerVignette, TweenInfo.new(1), {
				Saturation = 0,
				TintColor = Color3.new(1, 1, 1),
			}):Play()
		end
	end
end

------------------------------------------------------------------------
-- Combat Effect Helpers (called from other controllers)
------------------------------------------------------------------------
-- Store these globally so InputController can call them
local CombatEffects = {}

function CombatEffects.PlayMeleeSwing()
	Sounds.MeleeSwing:Play()
end

function CombatEffects.PlayMeleeHit()
	Sounds.MeleeHit:Play()
	CameraShakeIntensity = math.max(CameraShakeIntensity, 0.1)
end

function CombatEffects.PlayGunshot(weaponType)
	if weaponType == "Shotgun" then
		Sounds.ShotgunBlast:Play()
		CameraShakeIntensity = math.max(CameraShakeIntensity, 0.25)
	elseif weaponType == "Rifle" then
		Sounds.RifleShot:Play()
		CameraShakeIntensity = math.max(CameraShakeIntensity, 0.15)
	else
		Sounds.GunShot:Play()
		CameraShakeIntensity = math.max(CameraShakeIntensity, 0.1)
	end
end

function CombatEffects.PlayEnemyHurt()
	Sounds.EnemyHurt:Play()
end

function CombatEffects.PlayItemPickup()
	Sounds.ItemPickup:Play()
end

function CombatEffects.PlayNotification()
	Sounds.Notification:Play()
end

function CombatEffects.PlayFortify()
	Sounds.FortifyHammer:Play()
end

-- Make combat effects available to other client scripts
local combatModule = Instance.new("BindableEvent")
combatModule.Name = "PlayCombatSound"
combatModule.Parent = ReplicatedStorage

combatModule.Event:Connect(function(soundType, param)
	if soundType == "MeleeSwing" then CombatEffects.PlayMeleeSwing()
	elseif soundType == "MeleeHit" then CombatEffects.PlayMeleeHit()
	elseif soundType == "Gunshot" then CombatEffects.PlayGunshot(param)
	elseif soundType == "EnemyHurt" then CombatEffects.PlayEnemyHurt()
	elseif soundType == "ItemPickup" then CombatEffects.PlayItemPickup()
	elseif soundType == "Notification" then CombatEffects.PlayNotification()
	elseif soundType == "Fortify" then CombatEffects.PlayFortify()
	end
end)

------------------------------------------------------------------------
-- Event Handlers
------------------------------------------------------------------------
GamePhaseChanged.OnClientEvent:Connect(function(phase)
	CurrentPhase = phase

	if phase == Enums.GamePhase.Scavenging then
		TransitionToDay()
	elseif phase == Enums.GamePhase.PrePurge then
		TransitionToNight()
	elseif phase == Enums.GamePhase.Purge then
		TransitionToPurge()
	elseif phase == Enums.GamePhase.PostPurge then
		TransitionToPostPurge()
	end
end)

PurgeSiren.OnClientEvent:Connect(function()
	Sounds.Siren:Play()
	Sounds.PurgeHorn:Play()
	CameraShakeIntensity = 0.3
end)

PurgeStarted.OnClientEvent:Connect(function()
	TransitionToPurge()
end)

PurgeEnded.OnClientEvent:Connect(function()
	TransitionToPostPurge()
end)

PowerOutAlert.OnClientEvent:Connect(function()
	OnPowerOut()
end)

UpdateHUD.OnClientEvent:Connect(function(updateType, data)
	if updateType == "PowerStatus" then
		if data then
			OnPowerRestored()
		else
			OnPowerOut()
		end
	elseif updateType == "HungerUpdate" then
		UpdateStarvingEffects(data.level)
	elseif updateType == "DamageTaken" then
		CameraShakeIntensity = math.max(CameraShakeIntensity, 0.35)
		Sounds.PlayerHurt:Play()

		-- Danger vignette flash (red edges)
		TweenService:Create(dangerVignette, TweenInfo.new(0.1), {
			Brightness = -0.1,
			Contrast = 0.3,
			TintColor = Color3.fromRGB(255, 150, 150),
		}):Play()
		task.delay(0.3, function()
			TweenService:Create(dangerVignette, TweenInfo.new(0.5), {
				Brightness = 0,
				Contrast = 0,
				TintColor = Color3.new(1, 1, 1),
			}):Play()
		end)

		IsInDanger = true
		Sounds.Heartbeat:Play()
		task.delay(3, function()
			IsInDanger = false
			if CurrentPhase ~= Enums.GamePhase.Purge then
				Sounds.Heartbeat:Stop()
			end
		end)

	elseif updateType == "InventoryUpdate" then
		-- Item pickup sound
		Sounds.ItemPickup:Play()

	elseif updateType == "FortificationUpdate" then
		Sounds.FortifyHammer:Play()
	end
end)

PlayerDowned.OnClientEvent:Connect(function(downedPlayer)
	if downedPlayer == Player then
		TweenService:Create(colorCorrection, TweenInfo.new(0.5), {
			Saturation = -0.8,
			Brightness = -0.2,
		}):Play()

		TweenService:Create(blur, TweenInfo.new(0.5), {
			Size = 10,
		}):Play()

		Sounds.Heartbeat:Play()
	end
end)

local PlayerRevived = Remotes:WaitForChild("PlayerRevived")
PlayerRevived.OnClientEvent:Connect(function(revivedPlayer)
	if revivedPlayer == Player then
		TweenService:Create(colorCorrection, TweenInfo.new(1), {
			Saturation = 0,
			Brightness = 0,
		}):Play()

		TweenService:Create(blur, TweenInfo.new(1), {
			Size = 0,
		}):Play()

		Sounds.Heartbeat:Stop()
	end
end)

------------------------------------------------------------------------
-- Generator Hum
------------------------------------------------------------------------
task.defer(function()
	task.wait(2)
	Sounds.GeneratorHum:Play()
	Sounds.WindLoop:Play()
end)

------------------------------------------------------------------------
-- Render Loop
------------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	ApplyCameraShake(dt)
end)

print("[AtmosphereController] Initialized with full audio/visual effects")
