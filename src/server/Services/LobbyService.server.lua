--[[
	LobbyService.server.lua
	Lobby-based matchmaking system: 1-5 players per session.
	Handles player joining, ready-up, session start, and team management.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")
local GamePhaseChanged = Remotes:WaitForChild("GamePhaseChanged")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")

------------------------------------------------------------------------
-- Lobby Remotes
------------------------------------------------------------------------
local LobbyRemotes = Instance.new("Folder")
LobbyRemotes.Name = "LobbyRemotes"
LobbyRemotes.Parent = ReplicatedStorage

local PlayerReady = Instance.new("RemoteEvent")
PlayerReady.Name = "PlayerReady"
PlayerReady.Parent = LobbyRemotes

local PlayerUnready = Instance.new("RemoteEvent")
PlayerUnready.Name = "PlayerUnready"
PlayerUnready.Parent = LobbyRemotes

local LobbyUpdate = Instance.new("RemoteEvent")
LobbyUpdate.Name = "LobbyUpdate"
LobbyUpdate.Parent = LobbyRemotes

local SelectGameMode = Instance.new("RemoteEvent")
SelectGameMode.Name = "SelectGameMode"
SelectGameMode.Parent = LobbyRemotes

local StartGameVote = Instance.new("RemoteEvent")
StartGameVote.Name = "StartGameVote"
StartGameVote.Parent = LobbyRemotes

------------------------------------------------------------------------
-- Lobby State
------------------------------------------------------------------------
local LobbyState = {
	players = {},          -- { [Player] = { ready = bool, joinTime = number } }
	maxPlayers = 5,
	minPlayers = 1,
	gameMode = Enums.GameMode.Endless,
	countdownActive = false,
	countdownTime = 0,
	sessionActive = false,
}

local COUNTDOWN_DURATION = 10  -- seconds after all ready
local AUTO_START_DELAY = 60    -- auto-start after 60 seconds if at least 1 player

------------------------------------------------------------------------
-- Lobby Updates
------------------------------------------------------------------------
local function BroadcastLobbyState()
	local playerList = {}
	for player, data in pairs(LobbyState.players) do
		table.insert(playerList, {
			name = player.Name,
			displayName = player.DisplayName,
			ready = data.ready,
			userId = player.UserId,
		})
	end

	local lobbyInfo = {
		players = playerList,
		maxPlayers = LobbyState.maxPlayers,
		gameMode = LobbyState.gameMode,
		countdownActive = LobbyState.countdownActive,
		countdownTime = LobbyState.countdownTime,
		sessionActive = LobbyState.sessionActive,
	}

	LobbyUpdate:FireAllClients(lobbyInfo)
end

------------------------------------------------------------------------
-- Check if all players are ready
------------------------------------------------------------------------
local function AllPlayersReady(): boolean
	local count = 0
	local readyCount = 0
	for _, data in pairs(LobbyState.players) do
		count += 1
		if data.ready then readyCount += 1 end
	end
	return count >= LobbyState.minPlayers and readyCount == count
end

------------------------------------------------------------------------
-- Start Countdown
------------------------------------------------------------------------
local countdownThread = nil

local function StartCountdown()
	if LobbyState.countdownActive then return end
	LobbyState.countdownActive = true
	LobbyState.countdownTime = COUNTDOWN_DURATION

	NotifyPlayers:FireAllClients(
		"All players ready! Game starting in " .. COUNTDOWN_DURATION .. " seconds...",
		Color3.fromRGB(0, 255, 100)
	)

	countdownThread = task.spawn(function()
		while LobbyState.countdownTime > 0 do
			task.wait(1)
			LobbyState.countdownTime -= 1
			BroadcastLobbyState()

			if LobbyState.countdownTime <= 3 and LobbyState.countdownTime > 0 then
				NotifyPlayers:FireAllClients(
					tostring(LobbyState.countdownTime) .. "...",
					Color3.fromRGB(255, 255, 0)
				)
			end

			-- Cancel if someone unreadies
			if not AllPlayersReady() then
				LobbyState.countdownActive = false
				LobbyState.countdownTime = 0
				NotifyPlayers:FireAllClients(
					"Countdown cancelled — a player is not ready.",
					Color3.fromRGB(255, 100, 100)
				)
				BroadcastLobbyState()
				return
			end
		end

		-- Start the game
		StartGame()
	end)
end

------------------------------------------------------------------------
-- Start Game
------------------------------------------------------------------------
function StartGame()
	if LobbyState.sessionActive then return end
	LobbyState.sessionActive = true
	LobbyState.countdownActive = false

	NotifyPlayers:FireAllClients(
		"THE PURGE: SUBURBAN SURVIVAL — SESSION STARTING",
		Color3.fromRGB(255, 50, 50)
	)

	-- Transition to game phase
	GamePhaseChanged:FireAllClients(Enums.GamePhase.Scavenging)

	-- Teleport players from lobby area to starter house
	local starterSpawn = workspace:FindFirstChild("StarterHouseSpawn")
	if starterSpawn then
		for player, _ in pairs(LobbyState.players) do
			local char = player.Character
			if char then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp then
					char:PivotTo(starterSpawn.CFrame + Vector3.new(
						math.random(-5, 5), 3, math.random(-5, 5)
					))
				end
			end
		end
	end

	BroadcastLobbyState()
end

------------------------------------------------------------------------
-- Player Events
------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	if LobbyState.sessionActive then
		-- Late join: add to active session
		LobbyState.players[player] = { ready = true, joinTime = tick() }
		NotifyPlayers:FireAllClients(
			player.DisplayName .. " joined the session!",
			Color3.fromRGB(100, 200, 255)
		)
	else
		-- Add to lobby
		LobbyState.players[player] = { ready = false, joinTime = tick() }
		NotifyPlayers:FireAllClients(
			player.DisplayName .. " joined the lobby. (" .. #Players:GetPlayers() .. "/" .. LobbyState.maxPlayers .. ")",
			Color3.fromRGB(100, 200, 255)
		)
	end
	BroadcastLobbyState()
end)

Players.PlayerRemoving:Connect(function(player)
	LobbyState.players[player] = nil

	if not LobbyState.sessionActive then
		NotifyPlayers:FireAllClients(
			player.DisplayName .. " left the lobby.",
			Color3.fromRGB(200, 200, 200)
		)
	end
	BroadcastLobbyState()
end)

------------------------------------------------------------------------
-- Ready/Unready
------------------------------------------------------------------------
PlayerReady.OnServerEvent:Connect(function(player)
	local data = LobbyState.players[player]
	if not data or LobbyState.sessionActive then return end

	data.ready = true
	BroadcastLobbyState()

	if AllPlayersReady() then
		StartCountdown()
	end
end)

PlayerUnready.OnServerEvent:Connect(function(player)
	local data = LobbyState.players[player]
	if not data or LobbyState.sessionActive then return end

	data.ready = false
	BroadcastLobbyState()
end)

------------------------------------------------------------------------
-- Game Mode Selection (host only — first player)
------------------------------------------------------------------------
SelectGameMode.OnServerEvent:Connect(function(player, mode)
	if LobbyState.sessionActive then return end

	-- Only first player (host) can change mode
	local earliest = math.huge
	local host = nil
	for p, data in pairs(LobbyState.players) do
		if data.joinTime < earliest then
			earliest = data.joinTime
			host = p
		end
	end

	if player ~= host then
		NotifyPlayers:FireClient(player, "Only the host can change the game mode.", Color3.fromRGB(255, 200, 100))
		return
	end

	if Enums.GameMode[mode] then
		LobbyState.gameMode = mode
		NotifyPlayers:FireAllClients(
			"Game mode changed to: " .. mode,
			Color3.fromRGB(200, 200, 255)
		)
		BroadcastLobbyState()
	end
end)

------------------------------------------------------------------------
-- Auto-start timer for solo players
------------------------------------------------------------------------
task.spawn(function()
	local waitTime = 0
	while true do
		task.wait(1)
		if LobbyState.sessionActive then break end

		local playerCount = 0
		for _ in pairs(LobbyState.players) do playerCount += 1 end

		if playerCount >= 1 then
			waitTime += 1
			if waitTime >= AUTO_START_DELAY and not LobbyState.countdownActive then
				-- Auto-ready everyone and start
				for _, data in pairs(LobbyState.players) do
					data.ready = true
				end
				StartCountdown()
			end
		else
			waitTime = 0
		end
	end
end)

print("[LobbyService] Initialized")
