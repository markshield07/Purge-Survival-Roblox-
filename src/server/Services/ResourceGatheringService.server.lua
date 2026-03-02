--[[
	ResourceGatheringService.server.lua
	Handles tree chopping for wood and the Grinder for scrap.
	Trees have health (chops to fell), regrow after N days, and drop wood.
	Also handles sack/backpack upgrades when players pick up sack items.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local ItemDB = require(Modules.ItemDatabase)

------------------------------------------------------------------------
-- Wait for Remotes
------------------------------------------------------------------------
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")

-- Create gathering-specific remotes
local ChopTree = Instance.new("RemoteEvent")
ChopTree.Name = "ChopTree"
ChopTree.Parent = Remotes

local GatheringUpdate = Instance.new("RemoteEvent")
GatheringUpdate.Name = "GatheringUpdate"
GatheringUpdate.Parent = Remotes

local UpgradeSack = Instance.new("RemoteEvent")
UpgradeSack.Name = "UpgradeSack"
UpgradeSack.Parent = Remotes

------------------------------------------------------------------------
-- Tree State Tracking
------------------------------------------------------------------------
local TreeStates = {}  -- [treePart] = { health, maxHealth, fellDay, respawnDay }

local function InitTree(treePart)
	if TreeStates[treePart] then return end
	TreeStates[treePart] = {
		health = Config.Gathering.TreeHealth,
		maxHealth = Config.Gathering.TreeHealth,
		fellDay = 0,
		isChopped = false,
	}
end

local function RegrowTree(treePart)
	local state = TreeStates[treePart]
	if not state then return end

	state.health = state.maxHealth
	state.isChopped = false
	state.fellDay = 0

	-- Make tree visible again
	for _, desc in ipairs(treePart:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = 0
			desc.CanCollide = true
		end
	end
end

local function FellTree(treePart)
	local state = TreeStates[treePart]
	if not state then return end

	state.isChopped = true

	-- Get current day
	local GetGameState = game.ServerStorage:FindFirstChild("GetGameState")
	if GetGameState then
		local gs = GetGameState:Invoke()
		state.fellDay = gs.currentDay or 0
	end

	-- Make tree "disappear" (transparent + no collide)
	for _, desc in ipairs(treePart:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = 1
			desc.CanCollide = false
		end
	end

	-- Also handle the main part
	if treePart:IsA("BasePart") then
		treePart.Transparency = 1
		treePart.CanCollide = false
	end
end

------------------------------------------------------------------------
-- Chop Handler
------------------------------------------------------------------------
ChopTree.OnServerEvent:Connect(function(player, treePart)
	if not treePart or not treePart:IsA("BasePart") and not treePart:IsA("Model") then return end

	-- Check player has a weapon/tool equipped (any will do for now)
	local GetPlayerState = game.ServerStorage:FindFirstChild("GetPlayerState")
	if not GetPlayerState then return end
	local ps = GetPlayerState:Invoke(player)
	if not ps or ps.state ~= Enums.PlayerState.Alive then return end

	-- Check proximity
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local treePos = treePart:IsA("Model") and treePart:GetPivot().Position or treePart.Position
	local dist = (root.Position - treePos).Magnitude
	if dist > Config.Player.InteractRange + 2 then return end

	-- Initialize tree state if not tracked
	InitTree(treePart)
	local state = TreeStates[treePart]

	if state.isChopped then
		NotifyPlayers:FireClient(player, "This tree is already chopped.", Color3.fromRGB(200, 200, 100))
		return
	end

	-- Apply chop damage
	state.health = state.health - 1

	-- Give wood
	local AddItem = game.ServerStorage:FindFirstChild("AddPlayerItem")
	if AddItem then
		AddItem:Invoke(player, "wood", Config.Gathering.WoodPerChop)
	end

	GatheringUpdate:FireClient(player, "Chopped", {
		woodGained = Config.Gathering.WoodPerChop,
		treeHealth = state.health,
		treeMaxHealth = state.maxHealth,
	})

	-- Check if tree is felled
	if state.health <= 0 then
		FellTree(treePart)

		-- Bonus wood on fell
		if AddItem then
			AddItem:Invoke(player, "wood", Config.Gathering.WoodPerChop)
		end

		NotifyPlayers:FireClient(player,
			"Tree felled! +" .. (Config.Gathering.WoodPerChop * 2) .. " Wood total",
			Color3.fromRGB(100, 200, 100)
		)
	end
end)

------------------------------------------------------------------------
-- Tree Regrowth Check (runs per day transition)
------------------------------------------------------------------------
local function CheckTreeRegrowth(currentDay: number)
	for treePart, state in pairs(TreeStates) do
		if state.isChopped and state.fellDay > 0 then
			if currentDay >= state.fellDay + Config.Gathering.TreeRespawnDays then
				RegrowTree(treePart)
			end
		end
	end
end

------------------------------------------------------------------------
-- Sack/Backpack Upgrade
------------------------------------------------------------------------
UpgradeSack.OnServerEvent:Connect(function(player, slotIndex)
	local GetPlayerState = game.ServerStorage:FindFirstChild("GetPlayerState")
	if not GetPlayerState then return end
	local ps = GetPlayerState:Invoke(player)
	if not ps then return end

	local item = ps.inventory[slotIndex]
	if not item then return end

	local itemData = ItemDB.GetItem(item.itemId)
	if not itemData or itemData.category ~= Enums.ItemCategory.Backpack then return end

	-- Check if this sack is better than current
	local newSlots = itemData.sackSlots or 0
	if newSlots <= ps.maxSlots then
		NotifyPlayers:FireClient(player,
			"You already have a better or equal backpack!",
			Color3.fromRGB(255, 200, 100)
		)
		return
	end

	-- Remove the sack item from inventory
	local RemoveItem = game.ServerStorage:FindFirstChild("RemovePlayerItem")
	if RemoveItem then
		RemoveItem:Invoke(player, slotIndex, 1)
	end

	-- Upgrade max slots - need to modify the authoritative state directly
	-- Since we can't modify across script boundaries, use a BindableFunction
	local SetMaxSlots = game.ServerStorage:FindFirstChild("SetPlayerMaxSlots")
	if SetMaxSlots then
		SetMaxSlots:Invoke(player, newSlots)
	end

	NotifyPlayers:FireClient(player,
		"Equipped " .. itemData.name .. "! Inventory expanded to " .. newSlots .. " slots.",
		Color3.fromRGB(100, 255, 200)
	)

	-- Notify about special properties
	if itemData.cooksFood then
		NotifyPlayers:FireClient(player,
			"This sack slowly cooks raw food stored inside!",
			Color3.fromRGB(255, 150, 50)
		)
	end

	GatheringUpdate:FireClient(player, "SackUpgraded", {
		newSlots = newSlots,
		sackName = itemData.name,
	})
end)

------------------------------------------------------------------------
-- Forest Gem Fragment Combination
------------------------------------------------------------------------
local CombineFragments = Instance.new("RemoteEvent")
CombineFragments.Name = "CombineFragments"
CombineFragments.Parent = Remotes

CombineFragments.OnServerEvent:Connect(function(player)
	local CountItem = game.ServerStorage:FindFirstChild("CountPlayerItem")
	local RemoveById = game.ServerStorage:FindFirstChild("RemovePlayerItemById")
	local AddItem = game.ServerStorage:FindFirstChild("AddPlayerItem")
	if not CountItem or not RemoveById or not AddItem then return end

	local fragmentCount = CountItem:Invoke(player, "forest_gem_fragment")
	if fragmentCount < 4 then
		NotifyPlayers:FireClient(player,
			"Need 4 Forest Gem Fragments (have " .. fragmentCount .. ")",
			Color3.fromRGB(255, 100, 100)
		)
		return
	end

	-- Check room for the gem
	local HasRoom = game.ServerStorage:FindFirstChild("HasPlayerRoom")
	if HasRoom and not HasRoom:Invoke(player, "forest_gem", 1) then
		NotifyPlayers:FireClient(player, "Inventory full!", Color3.fromRGB(255, 100, 100))
		return
	end

	RemoveById:Invoke(player, "forest_gem_fragment", 4)
	AddItem:Invoke(player, "forest_gem", 1)

	NotifyPlayers:FireAllClients(
		player.Name .. " assembled a Gem of the Forest!",
		Color3.fromRGB(180, 0, 255)
	)
end)

------------------------------------------------------------------------
-- Listen for day changes to check tree regrowth
------------------------------------------------------------------------
task.defer(function()
	task.wait(3)

	-- Register existing trees
	for _, tree in ipairs(CollectionService:GetTagged("Tree")) do
		InitTree(tree)
	end
	CollectionService:GetInstanceAddedSignal("Tree"):Connect(function(tree)
		InitTree(tree)
	end)

	-- Listen for day changes via polling
	local lastDay = 0
	game:GetService("RunService").Heartbeat:Connect(function()
		local GetGameState = game.ServerStorage:FindFirstChild("GetGameState")
		if not GetGameState then return end
		local gs = GetGameState:Invoke()
		if not gs then return end

		if gs.currentDay > lastDay then
			lastDay = gs.currentDay
			CheckTreeRegrowth(lastDay)
		end
	end)
end)
