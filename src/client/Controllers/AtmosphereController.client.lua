--[[
	AtmosphereController.client.lua
	Controls atmosphere, audio, and visual effects.
	- Emergency broadcast siren
	- Ambient audio (day vs night vs Purge)
	- Generator hum / silence
	- Heartbeat during danger
	- Screen effects (blur, vignette, shake)
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
	sound.Parent = SoundService
	return sound
end

-- Ambient sounds (using placeholder SoundIds — replace with real asset IDs)
local Sounds = {
	-- These are placeholder rbxasset IDs. Replace with real uploaded sound IDs.
	DayAmbient = CreateSound("DayAmbient", "rbxassetid://0", { Volume = 0.3, Looped = true }),
	NightAmbient = CreateSound("NightAmbient", "rbxassetid://0", { Volume = 0.4, Looped = true }),
	PurgeAmbient = CreateSound("PurgeAmbient", "rbxassetid://0", { Volume = 0.5, Looped = true }),
	Siren = CreateSound("Siren", "rbxassetid://0", { Volume = 0.8, Looped = false }),
	GeneratorHum = CreateSound("GeneratorHum", "rbxassetid://0", { Volume = 0.2, Looped = true }),
	Heartbeat = CreateSound("Heartbeat", "rbxassetid://0", { Volume = 0.6, Looped = true }),
	PowerDown = CreateSound("PowerDown", "rbxassetid://0", { Volume = 0.7, Looped = false }),
	PurgeHorn = CreateSound("PurgeHorn", "rbxassetid://0", { Volume = 0.9, Looped = false }),
	VictoryStinger = CreateSound("VictoryStinger", "rbxassetid://0", { Volume = 0.7, Looped = false }),
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

local vignette = Instance.new("ColorCorrectionEffect")
vignette.Name = "DangerVignette"
vignette.Brightness = 0
vignette.Contrast = 0
vignette.Saturation = 0
vignette.TintColor = Color3.new(1, 1, 1)
vignette.Parent = Lighting

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

	-- Decay
	CameraShakeIntensity = CameraShakeIntensity * 0.95
	if CameraShakeIntensity < 0.01 then
		CameraShakeIntensity = 0
	end
end

------------------------------------------------------------------------
-- Atmosphere Transitions
------------------------------------------------------------------------
local function TransitionToDay()
	TweenService:Create(colorCorrection, TweenInfo.new(3), {
		Brightness = 0,
		Contrast = 0,
		Saturation = 0,
		TintColor = Color3.new(1, 1, 1),
	}):Play()

	TweenService:Create(blur, TweenInfo.new(2), {
		Size = 0,
	}):Play()

	Sounds.NightAmbient:Stop()
	Sounds.PurgeAmbient:Stop()
	Sounds.DayAmbient:Play()
end

local function TransitionToNight()
	TweenService:Create(colorCorrection, TweenInfo.new(3), {
		Brightness = -0.05,
		Contrast = 0.1,
		Saturation = -0.2,
		TintColor = Color3.fromRGB(200, 210, 255),
	}):Play()

	Sounds.DayAmbient:Stop()
	Sounds.NightAmbient:Play()
end

local function TransitionToPurge()
	-- Dramatic red tint
	TweenService:Create(colorCorrection, TweenInfo.new(1), {
		Brightness = -0.1,
		Contrast = 0.2,
		Saturation = -0.3,
		TintColor = Color3.fromRGB(255, 180, 180),
	}):Play()

	Sounds.DayAmbient:Stop()
	Sounds.NightAmbient:Stop()
	Sounds.PurgeAmbient:Play()

	CameraShakeIntensity = 0.3
end

local function TransitionToPostPurge()
	TweenService:Create(colorCorrection, TweenInfo.new(3), {
		Brightness = 0,
		Contrast = 0,
		Saturation = 0,
		TintColor = Color3.new(1, 1, 1),
	}):Play()

	Sounds.PurgeAmbient:Stop()
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

	-- Sudden darkness
	TweenService:Create(colorCorrection, TweenInfo.new(0.2), {
		Brightness = -0.3,
		TintColor = Color3.fromRGB(100, 100, 130),
	}):Play()

	-- Start heartbeat
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
			CameraShakeIntensity = math.max(CameraShakeIntensity, 0.15)
		end
	else
		if starvingActive then
			starvingActive = false
			TweenService:Create(blur, TweenInfo.new(1), {
				Size = 0,
			}):Play()
		end
	end
end

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
	CameraShakeIntensity = 0.2
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
		CameraShakeIntensity = math.max(CameraShakeIntensity, 0.3)
		IsInDanger = true
		Sounds.Heartbeat:Play()
		task.delay(3, function()
			IsInDanger = false
			if CurrentPhase ~= Enums.GamePhase.Purge then
				Sounds.Heartbeat:Stop()
			end
		end)
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
-- Generator Hum (start when game begins)
------------------------------------------------------------------------
task.defer(function()
	task.wait(2)
	Sounds.GeneratorHum:Play()
end)

------------------------------------------------------------------------
-- Render Loop
------------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	ApplyCameraShake(dt)
end)

print("[AtmosphereController] Initialized")
