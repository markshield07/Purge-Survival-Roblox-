--[[
	InventoryService.server.lua
	Server-authoritative inventory management
	Handles picking up, dropping, using, and transferring items.

	All inventory mutations are delegated to GameManager via BindableFunctions
	to avoid the copy-on-invoke problem with BindableFunction tables.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local ItemDatabase = require(Modules.ItemDatabase)
local Utils = require(Modules.Utils)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PickupItem = Remotes:WaitForChild("PickupItem")
local DropItem = Remotes:WaitForChild("DropItem")
local UseItem = Remotes:WaitForChild("UseItem")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")

------------------------------------------------------------------------
-- Helper: Get read-only player state snapshot from GameManager
------------------------------------------------------------------------
local function GetPlayerState(player: Player)
	local getter = game.ServerStorage:FindFirstChild("GetPlayerState")
	if getter then
		return getter:Invoke(player)
	end
	return nil
end

------------------------------------------------------------------------
-- Inventory Operations (all delegate to GameManager BindableFunctions)
------------------------------------------------------------------------
local InventoryService = {}

function InventoryService.AddItem(player: Player, itemId: string, quantity: number): boolean
	local bf = game.ServerStorage:FindFirstChild("AddPlayerItem")
	if not bf then return false end
	return bf:Invoke(player, itemId, quantity)
end

function InventoryService.RemoveItem(player: Player, slotIndex: number, quantity: number): boolean
	local bf = game.ServerStorage:FindFirstChild("RemovePlayerItem")
	if not bf then return false end
	return bf:Invoke(player, slotIndex, quantity)
end

function InventoryService.RemoveItemById(player: Player, itemId: string, quantity: number): boolean
	local bf = game.ServerStorage:FindFirstChild("RemovePlayerItemById")
	if not bf then return false end
	return bf:Invoke(player, itemId, quantity)
end

function InventoryService.HasRoom(player: Player, itemId: string, quantity: number): boolean
	local bf = game.ServerStorage:FindFirstChild("HasPlayerRoom")
	if not bf then return false end
	return bf:Invoke(player, itemId, quantity)
end

function InventoryService.CountItem(player: Player, itemId: string): number
	local bf = game.ServerStorage:FindFirstChild("CountPlayerItem")
	if not bf then return 0 end
	return bf:Invoke(player, itemId)
end

function InventoryService.HasItem(player: Player, itemId: string, quantity: number?): boolean
	return InventoryService.CountItem(player, itemId) >= (quantity or 1)
end

function InventoryService.GetSlotCount(player: Player): number
	local bf = game.ServerStorage:FindFirstChild("GetPlayerInventoryInfo")
	if not bf then return 0 end
	local info = bf:Invoke(player)
	return info and info.slotCount or 0
end

function InventoryService.GetMaxSlots(player: Player): number
	local bf = game.ServerStorage:FindFirstChild("GetPlayerInventoryInfo")
	if not bf then return Config.Player.MaxInventorySlots end
	local info = bf:Invoke(player)
	return info and info.maxSlots or Config.Player.MaxInventorySlots
end

function InventoryService.GetItemCounts(player: Player): { [string]: number }
	-- Read-only: snapshot is fine
	local state = GetPlayerState(player)
	if not state then return {} end

	local counts = {}
	for _, slot in ipairs(state.inventory) do
		counts[slot.itemId] = (counts[slot.itemId] or 0) + slot.quantity
	end
	return counts
end

------------------------------------------------------------------------
-- Pickup Item from World
------------------------------------------------------------------------
PickupItem.OnServerEvent:Connect(function(player, lootInstance)
	if not lootInstance or not lootInstance:IsA("BasePart") then return end
	if not lootInstance:IsDescendantOf(workspace) then return end

	-- Verify proximity
	local char = player.Character
	if not char then return end
	local humanoidRootPart = char:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end

	local dist = Utils.Distance(humanoidRootPart.Position, lootInstance.Position)
	if dist > Config.Player.PickupRange then return end

	-- Get item data from instance
	local itemId = lootInstance:GetAttribute("ItemId")
	local quantity = lootInstance:GetAttribute("Quantity") or 1
	if not itemId then return end

	local itemData = ItemDatabase.GetItem(itemId)
	if not itemData then return end

	-- Backpack pickup: auto-upgrade inventory capacity
	if itemData.category == Enums.ItemCategory.Backpack then
		local backpackSlots = itemData.backpackSlots or 10
		local upgrader = game.ServerStorage:FindFirstChild("UpgradeBackpack")
		if upgrader then
			local upgraded = upgrader:Invoke(player, backpackSlots)
			if upgraded then
				lootInstance:Destroy()
				NotifyPlayers:FireClient(player,
					"Found " .. itemData.name .. "! Backpack upgraded to " .. backpackSlots .. " slots!",
					Color3.fromRGB(50, 255, 100))
			else
				NotifyPlayers:FireClient(player,
					"Already have a better backpack!",
					Color3.fromRGB(255, 200, 50))
			end
		end
		return
	end

	-- Add to inventory via GameManager (authoritative)
	if InventoryService.AddItem(player, itemId, quantity) then
		-- Remove from world
		lootInstance:Destroy()

		local name = itemData.name or itemId
		local slotCount = InventoryService.GetSlotCount(player)
		local maxSlots = InventoryService.GetMaxSlots(player)
		NotifyPlayers:FireClient(player,
			name .. (quantity > 1 and (" x" .. quantity) or "") .. " stored in backpack [" .. slotCount .. "/" .. maxSlots .. "]",
			Color3.fromRGB(200, 200, 255)
		)
	end
end)

------------------------------------------------------------------------
-- Drop Item to World
------------------------------------------------------------------------
DropItem.OnServerEvent:Connect(function(player, slotIndex)
	-- Read snapshot to get item info for the dropped part
	local state = GetPlayerState(player)
	if not state then return end

	local slot = state.inventory[slotIndex]
	if not slot then return end

	local char = player.Character
	if not char then return end
	local humanoidRootPart = char:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end

	local itemData = ItemDatabase.GetItem(slot.itemId)
	if not itemData then return end

	-- Remove from authoritative inventory first
	-- Remove the whole stack
	local removeBF = game.ServerStorage:FindFirstChild("RemovePlayerItem")
	if not removeBF then return end
	local removed = removeBF:Invoke(player, slotIndex, slot.quantity)
	if not removed then return end

	-- Create dropped item in world
	local droppedPart = Instance.new("Part")
	droppedPart.Name = "DroppedItem_" .. slot.itemId
	droppedPart.Size = Vector3.new(1.5, 1.5, 1.5)
	droppedPart.Position = humanoidRootPart.Position + humanoidRootPart.CFrame.LookVector * 3 + Vector3.new(0, 2, 0)
	droppedPart.Anchored = false
	droppedPart.CanCollide = true
	droppedPart.BrickColor = BrickColor.new("Medium stone grey")
	droppedPart:SetAttribute("ItemId", slot.itemId)
	droppedPart:SetAttribute("Quantity", slot.quantity)
	CollectionService:AddTag(droppedPart, "LootItem")

	-- Add proximity prompt so it can be picked up again
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = itemData.name
	prompt.MaxActivationDistance = Config.Player.PickupRange
	prompt.HoldDuration = 0.2
	prompt.Parent = droppedPart

	-- Add billboard for item name
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 120, 0, 30)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = droppedPart

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = itemData.name
	label.TextColor3 = Enums.TierColor[itemData.tier] or Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	droppedPart.Parent = workspace:FindFirstChild("LootItems")
end)

------------------------------------------------------------------------
-- Use Item (eat food, use consumable, etc.)
-- Delegates actual state mutations to GameManager via UsePlayerItem BF
------------------------------------------------------------------------
UseItem.OnServerEvent:Connect(function(player, slotIndex)
	local bf = game.ServerStorage:FindFirstChild("UsePlayerItem")
	if not bf then return end
	bf:Invoke(player, slotIndex)
end)

print("[InventoryService] Initialized")
