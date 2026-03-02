--[[
	RescueService.server.lua
	Rescue objectives system (inspired by 99 Nights in the Forest).
	4 missing people are scattered across the map in guarded locations.
	Finding them speeds up the day counter and gives rewards.
	Each rescue adds +1 to the day multiplier per cycle.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local Utils = require(Modules.Utils)
local ItemDB = require(Modules.ItemDatabase)

------------------------------------------------------------------------
-- Wait for Remotes
------------------------------------------------------------------------
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")

-- Create rescue-specific remotes
local RescueUpdate = Instance.new("RemoteEvent")
RescueUpdate.Name = "RescueUpdate"
RescueUpdate.Parent = Remotes

local StartRescue = Instance.new("RemoteEvent")
StartRescue.Name = "StartRescue"
StartRescue.Parent = Remotes

------------------------------------------------------------------------
-- Rescue State
------------------------------------------------------------------------
local RescueState = {
	totalMissing = Config.Rescue.TotalMissing,
	rescued = 0,
	dayMultiplierBonus = 0,  -- each rescue adds +1
	people = {},  -- { name, position, state, guardCount }
}

-- Missing person names
local MissingNames = { "Alex", "Jordan", "Morgan", "Casey" }

------------------------------------------------------------------------
-- Spawn Missing People
------------------------------------------------------------------------
local function SpawnMissingPeople()
	local GetCampfireState = game.ServerStorage:FindFirstChild("GetCampfireState")
	local campPos = Vector3.new(0, 0, 0)
	if GetCampfireState then
		local cs = GetCampfireState:Invoke()
		campPos = cs.position or Vector3.zero
	end

	for i = 1, Config.Rescue.TotalMissing do
		local angle = (i / Config.Rescue.TotalMissing) * math.pi * 2 + math.random() * 0.5
		local dist = Config.Rescue.SpawnDistances[i] or (200 * i)
		local pos = campPos + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)

		-- Create the missing person marker
		local marker = Instance.new("Part")
		marker.Name = "MissingPerson_" .. MissingNames[i]
		marker.Size = Vector3.new(3, 5, 3)
		marker.Position = pos + Vector3.new(0, 2.5, 0)
		marker.Anchored = true
		marker.CanCollide = false
		marker.Transparency = 0.3
		marker.Material = Enum.Material.Neon
		marker.BrickColor = BrickColor.new("Bright blue")
		marker.Shape = Enum.PartType.Cylinder
		marker.Parent = workspace

		-- Billboard for name
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(0, 200, 0, 50)
		billboard.StudsOffset = Vector3.new(0, 4, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = marker

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, 0, 0.6, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = "? " .. MissingNames[i]
		nameLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Parent = billboard

		local helpLabel = Instance.new("TextLabel")
		helpLabel.Size = UDim2.new(1, 0, 0.4, 0)
		helpLabel.Position = UDim2.new(0, 0, 0.6, 0)
		helpLabel.BackgroundTransparency = 1
		helpLabel.Text = "Press [E] to rescue"
		helpLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		helpLabel.TextScaled = true
		helpLabel.Font = Enum.Font.Gotham
		helpLabel.Parent = billboard

		-- Glow beacon
		local light = Instance.new("PointLight")
		light.Brightness = 2
		light.Range = 20
		light.Color = Color3.fromRGB(100, 200, 255)
		light.Parent = marker

		-- Sparkle
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = Color3.fromRGB(100, 200, 255)
		sparkle.Parent = marker

		-- Proximity prompt
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Rescue " .. MissingNames[i]
		prompt.ObjectText = "Missing Person"
		prompt.HoldDuration = Config.Rescue.RescueTime
		prompt.MaxActivationDistance = Config.Rescue.SearchRadius
		prompt.RequiresLineOfSight = false
		prompt.Parent = marker

		CollectionService:AddTag(marker, "MissingPerson")

		-- Store state
		table.insert(RescueState.people, {
			name = MissingNames[i],
			position = pos,
			state = Enums.RescueState.Hidden,
			marker = marker,
			index = i,
		})

		-- Handle rescue interaction
		prompt.Triggered:Connect(function(player)
			-- Find this person in state
			local person = nil
			for _, p in ipairs(RescueState.people) do
				if p.marker == marker then
					person = p
					break
				end
			end
			if not person or person.state == Enums.RescueState.Rescued then return end

			-- Complete rescue
			person.state = Enums.RescueState.Rescued
			RescueState.rescued = RescueState.rescued + 1
			RescueState.dayMultiplierBonus = RescueState.dayMultiplierBonus + Config.Rescue.DaySpeedupPerRescue

			-- Remove marker
			marker:Destroy()

			-- Give rewards
			local rewards = Config.Rescue.Rewards[person.index]
			if rewards then
				local AddItem = game.ServerStorage:FindFirstChild("AddPlayerItem")
				if rewards.item and AddItem then
					AddItem:Invoke(player, rewards.item, 1)
				end
				-- Give scrap
				local ps = nil
				local GetPlayerState = game.ServerStorage:FindFirstChild("GetPlayerState")
				if GetPlayerState then
					ps = GetPlayerState:Invoke(player)
				end
			end

			-- Notify all players
			NotifyPlayers:FireAllClients(
				player.Name .. " rescued " .. person.name .. "! Day counter now +" .. RescueState.dayMultiplierBonus .. " per cycle. (" .. RescueState.rescued .. "/" .. Config.Rescue.TotalMissing .. ")",
				Color3.fromRGB(100, 255, 200)
			)

			RescueUpdate:FireAllClients("Rescued", {
				personName = person.name,
				rescued = RescueState.rescued,
				totalMissing = Config.Rescue.TotalMissing,
				dayMultiplierBonus = RescueState.dayMultiplierBonus,
				rewardItem = rewards and rewards.item or nil,
			})

			-- Check if all rescued
			if RescueState.rescued >= Config.Rescue.TotalMissing then
				task.delay(3, function()
					NotifyPlayers:FireAllClients(
						"ALL MISSING PEOPLE RESCUED! The forest stirs...",
						Color3.fromRGB(255, 200, 0)
					)
				end)
			end
		end)
	end
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
task.defer(function()
	-- Wait for map generation and other services
	task.wait(5)
	SpawnMissingPeople()

	-- Bulletin board at campfire showing rescue status
	local GetCampfireState = game.ServerStorage:FindFirstChild("GetCampfireState")
	if GetCampfireState then
		local cs = GetCampfireState:Invoke()
		local boardPos = (cs.position or Vector3.zero) + Vector3.new(8, 0, 0)

		local board = Instance.new("Part")
		board.Name = "RescueBoard"
		board.Size = Vector3.new(6, 4, 0.5)
		board.Position = boardPos + Vector3.new(0, 3, 0)
		board.Anchored = true
		board.Material = Enum.Material.Wood
		board.BrickColor = BrickColor.new("Brown")
		board.Parent = workspace

		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.Parent = board

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0.25, 0)
		title.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		title.Text = "MISSING PERSONS"
		title.TextColor3 = Color3.fromRGB(255, 100, 100)
		title.TextScaled = true
		title.Font = Enum.Font.GothamBold
		title.Parent = gui

		for i, name in ipairs(MissingNames) do
			local label = Instance.new("TextLabel")
			label.Name = "Person_" .. i
			label.Size = UDim2.new(1, 0, 0.18, 0)
			label.Position = UDim2.new(0, 0, 0.25 + (i - 1) * 0.18, 0)
			label.BackgroundTransparency = 0.5
			label.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
			label.Text = "  " .. name .. " - MISSING"
			label.TextColor3 = Color3.fromRGB(255, 200, 100)
			label.TextScaled = true
			label.Font = Enum.Font.Gotham
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Parent = gui
		end
	end
end)

------------------------------------------------------------------------
-- Expose state for GameManager (day multiplier)
------------------------------------------------------------------------
local GetRescueState = Instance.new("BindableFunction")
GetRescueState.Name = "GetRescueState"
GetRescueState.Parent = game.ServerStorage
GetRescueState.OnInvoke = function()
	return RescueState
end

local GetDayMultiplier = Instance.new("BindableFunction")
GetDayMultiplier.Name = "GetDayMultiplier"
GetDayMultiplier.Parent = game.ServerStorage
GetDayMultiplier.OnInvoke = function()
	return 1 + RescueState.dayMultiplierBonus
end
