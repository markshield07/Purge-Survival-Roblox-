--[[
	DataService.server.lua
	Persistent data storage using Roblox DataStoreService.
	Saves player progression, cosmetics, currency, and stats.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)

------------------------------------------------------------------------
-- DataStore Setup
------------------------------------------------------------------------
local DATASTORE_NAME = "PurgeSurvival_v1"
local PlayerDataStore = DataStoreService:GetDataStore(DATASTORE_NAME)
local LeaderboardStore = DataStoreService:GetOrderedDataStore("PurgeSurvival_Leaderboard")

------------------------------------------------------------------------
-- Default Player Data Template
------------------------------------------------------------------------
local DEFAULT_DATA = {
	-- Currency
	scrap = 0,
	purgeCoins = 0,

	-- Stats
	totalPurgesSurvived = 0,
	highestPurgeSurvived = 0,
	totalEnemiesKilled = 0,
	totalGamesPlayed = 0,
	totalDaysLived = 0,

	-- Cosmetics owned
	ownedMasks = {},          -- { "mask_hockey", "mask_skull", ... }
	ownedOutfits = {},        -- { "outfit_tactical", ... }
	ownedWeaponSkins = {},    -- { "skin_neon_bat", ... }
	ownedHouseDecor = {},     -- { "decor_retro_diner", ... }
	ownedEmotes = {},         -- { "emote_victory", ... }

	-- Equipped cosmetics
	equippedMask = nil,
	equippedOutfit = nil,
	equippedEmote = nil,

	-- Game passes
	gamePasses = {},          -- { [passId] = true }

	-- Season pass
	seasonPassPremium = false,
	seasonPassXP = 0,
	seasonPassLevel = 0,

	-- Settings
	musicVolume = 0.5,
	sfxVolume = 0.7,

	-- Metadata
	version = 1,
	lastLogin = 0,
	firstLogin = 0,
}

------------------------------------------------------------------------
-- In-Memory Player Data Cache
------------------------------------------------------------------------
local PlayerData = {}  -- [Player] = data table

------------------------------------------------------------------------
-- Data Operations
------------------------------------------------------------------------
local DataService = {}

-- Deep merge with default (adds missing fields from default)
local function MergeWithDefault(saved, default)
	local result = {}
	for key, defaultValue in pairs(default) do
		if saved[key] ~= nil then
			if type(defaultValue) == "table" and type(saved[key]) == "table" then
				result[key] = MergeWithDefault(saved[key], defaultValue)
			else
				result[key] = saved[key]
			end
		else
			if type(defaultValue) == "table" then
				-- Deep copy default tables
				result[key] = {}
				for k, v in pairs(defaultValue) do
					result[key][k] = v
				end
			else
				result[key] = defaultValue
			end
		end
	end
	-- Keep extra keys from saved data
	for key, value in pairs(saved) do
		if result[key] == nil then
			result[key] = value
		end
	end
	return result
end

-- Load player data
function DataService.LoadData(player: Player): boolean
	local key = "Player_" .. player.UserId
	local success, data = pcall(function()
		return PlayerDataStore:GetAsync(key)
	end)

	if success then
		if data then
			PlayerData[player] = MergeWithDefault(data, DEFAULT_DATA)
		else
			-- New player
			PlayerData[player] = table.clone(DEFAULT_DATA)
			PlayerData[player].firstLogin = os.time()
		end
		PlayerData[player].lastLogin = os.time()
		return true
	else
		warn("[DataService] Failed to load data for", player.Name, ":", data)
		-- Use default data so the game is playable
		PlayerData[player] = table.clone(DEFAULT_DATA)
		return false
	end
end

-- Save player data
function DataService.SaveData(player: Player): boolean
	local data = PlayerData[player]
	if not data then return false end

	local key = "Player_" .. player.UserId
	local success, err = pcall(function()
		PlayerDataStore:SetAsync(key, data)
	end)

	if not success then
		warn("[DataService] Failed to save data for", player.Name, ":", err)
		return false
	end
	return true
end

-- Get player data
function DataService.GetData(player: Player)
	return PlayerData[player]
end

-- Update a specific field
function DataService.UpdateField(player: Player, field: string, value: any)
	local data = PlayerData[player]
	if not data then return end
	data[field] = value
end

-- Increment a numeric field
function DataService.IncrementField(player: Player, field: string, amount: number)
	local data = PlayerData[player]
	if not data then return end
	data[field] = (data[field] or 0) + amount
end

-- Add currency (server authoritative)
function DataService.AddScrap(player: Player, amount: number)
	DataService.IncrementField(player, "scrap", amount)
	-- Sync with in-game state
	local getPS = game.ServerStorage:FindFirstChild("GetPlayerState")
	if getPS then
		local state = getPS:Invoke(player)
		if state then
			state.scrap = PlayerData[player].scrap
		end
	end
end

function DataService.AddPurgeCoins(player: Player, amount: number)
	DataService.IncrementField(player, "purgeCoins", amount)
end

function DataService.SpendScrap(player: Player, amount: number): boolean
	local data = PlayerData[player]
	if not data or data.scrap < amount then return false end
	data.scrap -= amount
	return true
end

function DataService.SpendPurgeCoins(player: Player, amount: number): boolean
	local data = PlayerData[player]
	if not data or data.purgeCoins < amount then return false end
	data.purgeCoins -= amount
	return true
end

-- Cosmetic ownership
function DataService.OwnCosmetic(player: Player, category: string, itemId: string)
	local data = PlayerData[player]
	if not data then return end

	local listName = "owned" .. category
	if data[listName] then
		if not table.find(data[listName], itemId) then
			table.insert(data[listName], itemId)
		end
	end
end

function DataService.HasCosmetic(player: Player, category: string, itemId: string): boolean
	local data = PlayerData[player]
	if not data then return false end

	local listName = "owned" .. category
	if data[listName] then
		return table.find(data[listName], itemId) ~= nil
	end
	return false
end

-- Update leaderboard
function DataService.UpdateLeaderboard(player: Player, score: number)
	local success, err = pcall(function()
		LeaderboardStore:SetAsync(tostring(player.UserId), score)
	end)
	if not success then
		warn("[DataService] Leaderboard update failed:", err)
	end
end

-- Get top leaderboard entries
function DataService.GetLeaderboard(count: number): { any }
	local success, pages = pcall(function()
		return LeaderboardStore:GetSortedAsync(false, count)
	end)

	if not success or not pages then return {} end

	local entries = {}
	local page = pages:GetCurrentPage()
	for rank, entry in ipairs(page) do
		table.insert(entries, {
			rank = rank,
			userId = tonumber(entry.key),
			score = entry.value,
		})
	end
	return entries
end

------------------------------------------------------------------------
-- Record end-of-session stats
------------------------------------------------------------------------
function DataService.RecordSessionEnd(player: Player, purgesSurvived: number, enemiesKilled: number, daysLived: number)
	local data = PlayerData[player]
	if not data then return end

	data.totalPurgesSurvived += purgesSurvived
	data.totalEnemiesKilled += enemiesKilled
	data.totalGamesPlayed += 1
	data.totalDaysLived += daysLived

	if purgesSurvived > data.highestPurgeSurvived then
		data.highestPurgeSurvived = purgesSurvived
		DataService.UpdateLeaderboard(player, purgesSurvived)
	end
end

------------------------------------------------------------------------
-- Season Pass XP
------------------------------------------------------------------------
function DataService.AddSeasonXP(player: Player, xp: number)
	local data = PlayerData[player]
	if not data then return end

	data.seasonPassXP += xp

	-- Level up check (100 XP per level)
	local xpPerLevel = 100
	local newLevel = math.floor(data.seasonPassXP / xpPerLevel)
	if newLevel > data.seasonPassLevel then
		data.seasonPassLevel = newLevel
		local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if Remotes then
			local notify = Remotes:FindFirstChild("NotifyPlayers")
			if notify then
				notify:FireClient(player,
					"Season Pass Level Up! Level " .. newLevel,
					Color3.fromRGB(255, 200, 50)
				)
			end
		end
	end
end

------------------------------------------------------------------------
-- Player Connection
------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	local loaded = DataService.LoadData(player)
	if loaded then
		print("[DataService] Loaded data for", player.Name)
	end

	-- Send initial data to client
	local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if Remotes then
		local updateHUD = Remotes:FindFirstChild("UpdateHUD")
		if updateHUD then
			local data = PlayerData[player]
			if data then
				updateHUD:FireClient(player, "PlayerDataLoaded", {
					scrap = data.scrap,
					purgeCoins = data.purgeCoins,
					stats = {
						totalPurgesSurvived = data.totalPurgesSurvived,
						highestPurgeSurvived = data.highestPurgeSurvived,
						totalEnemiesKilled = data.totalEnemiesKilled,
						totalGamesPlayed = data.totalGamesPlayed,
					},
					seasonPassLevel = data.seasonPassLevel,
					seasonPassXP = data.seasonPassXP,
					seasonPassPremium = data.seasonPassPremium,
				})
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	DataService.SaveData(player)
	PlayerData[player] = nil
end)

------------------------------------------------------------------------
-- Auto-save every 5 minutes
------------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(300)
		for player, _ in pairs(PlayerData) do
			if player.Parent then  -- still in game
				DataService.SaveData(player)
			end
		end
		print("[DataService] Auto-save complete")
	end
end)

-- Save all on server shutdown
game:BindToClose(function()
	for player, _ in pairs(PlayerData) do
		DataService.SaveData(player)
	end
	print("[DataService] Shutdown save complete")
end)

------------------------------------------------------------------------
-- Expose for other server scripts
------------------------------------------------------------------------
local getPlayerData = Instance.new("BindableFunction")
getPlayerData.Name = "GetPlayerData"
getPlayerData.Parent = game.ServerStorage
getPlayerData.OnInvoke = function(player)
	return DataService.GetData(player)
end

local addScrap = Instance.new("BindableFunction")
addScrap.Name = "AddScrap"
addScrap.Parent = game.ServerStorage
addScrap.OnInvoke = function(player, amount)
	DataService.AddScrap(player, amount)
end

print("[DataService] Initialized")
