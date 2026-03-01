--[[
	InventoryService.server.lua
	Server-authoritative inventory management
	Handles picking up, dropping, using, and transferring items.
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
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")

------------------------------------------------------------------------
-- Helper: Get player state from GameManager
------------------------------------------------------------------------
local function GetPlayerState(player: Player)
	local getter = game.ServerStorage:FindFirstChild("GetPlayerState")
	if getter then
		return getter:Invoke(player)
	end
	return nil
end

------------------------------------------------------------------------
-- Inventory Operations
------------------------------------------------------------------------
local InventoryService = {}

function InventoryService.GetInventory(player: Player): { any }
	local state = GetPlayerState(player)
	if not state then return {} end
	return state.inventory
end

function InventoryService.GetSlotCount(player: Player): number
	local state = GetPlayerState(player)
	if not state then return 0 end
	return #state.inventory
end

function InventoryService.GetMaxSlots(player: Player): number
	local state = GetPlayerState(player)
	if not state then return Config.Player.MaxInventorySlots end
	return state.maxSlots
end

function InventoryService.HasRoom(player: Player, itemId: string, quantity: number): boolean
	local state = GetPlayerState(player)
	if not state then return false end

	local itemData = ItemDatabase.GetItem(itemId)
	if not itemData then return false end

	-- Check if item can stack with existing
	if itemData.stackable then
		for _, slot in ipairs(state.inventory) do
			if slot.itemId == itemId then
				local spaceInStack = itemData.maxStack - slot.quantity
				if spaceInStack >= quantity then
					return true
				end
				quantity -= spaceInStack
			end
		end
	end

	-- Need new slot(s)
	local slotsNeeded = 1
	if itemData.stackable then
		slotsNeeded = math.ceil(quantity / itemData.maxStack)
	else
		slotsNeeded = quantity
	end

	return (#state.inventory + slotsNeeded) <= state.maxSlots
end

function InventoryService.AddItem(player: Player, itemId: string, quantity: number): boolean
	local state = GetPlayerState(player)
	if not state then return false end

	local itemData = ItemDatabase.GetItem(itemId)
	if not itemData then
		warn("[InventoryService] Unknown item:", itemId)
		return false
	end

	if not InventoryService.HasRoom(player, itemId, quantity) then
		NotifyPlayers:FireClient(player, "Inventory full!", Color3.fromRGB(255, 100, 100))
		return false
	end

	local remaining = quantity

	-- Try to stack with existing items
	if itemData.stackable then
		for _, slot in ipairs(state.inventory) do
			if slot.itemId == itemId and slot.quantity < itemData.maxStack then
				local canAdd = math.min(remaining, itemData.maxStack - slot.quantity)
				slot.quantity += canAdd
				remaining -= canAdd
				if remaining <= 0 then break end
			end
		end
	end

	-- Add to new slots
	while remaining > 0 do
		local addCount = 1
		if itemData.stackable then
			addCount = math.min(remaining, itemData.maxStack)
		end
		table.insert(state.inventory, {
			itemId = itemId,
			quantity = addCount,
			spoilDay = itemData.spoilDays or -1,
			pickedUpDay = 0, -- set by caller
		})
		remaining -= addCount
	end

	-- Send inventory update to client
	UpdateHUD:FireClient(player, "InventoryUpdate", state.inventory)
	return true
end

function InventoryService.RemoveItem(player: Player, slotIndex: number, quantity: number): boolean
	local state = GetPlayerState(player)
	if not state then return false end

	local slot = state.inventory[slotIndex]
	if not slot then return false end

	slot.quantity -= quantity
	if slot.quantity <= 0 then
		table.remove(state.inventory, slotIndex)
	end

	UpdateHUD:FireClient(player, "InventoryUpdate", state.inventory)
	return true
end

function InventoryService.RemoveItemById(player: Player, itemId: string, quantity: number): boolean
	local state = GetPlayerState(player)
	if not state then return false end

	local remaining = quantity
	for i = #state.inventory, 1, -1 do
		local slot = state.inventory[i]
		if slot.itemId == itemId then
			local toRemove = math.min(remaining, slot.quantity)
			slot.quantity -= toRemove
			remaining -= toRemove
			if slot.quantity <= 0 then
				table.remove(state.inventory, i)
			end
			if remaining <= 0 then break end
		end
	end

	UpdateHUD:FireClient(player, "InventoryUpdate", state.inventory)
	return remaining <= 0
end

function InventoryService.CountItem(player: Player, itemId: string): number
	local state = GetPlayerState(player)
	if not state then return 0 end

	local count = 0
	for _, slot in ipairs(state.inventory) do
		if slot.itemId == itemId then
			count += slot.quantity
		end
	end
	return count
end

function InventoryService.HasItem(player: Player, itemId: string, quantity: number?): boolean
	return InventoryService.CountItem(player, itemId) >= (quantity or 1)
end

-- Get a count map of all items { [itemId] = totalCount }
function InventoryService.GetItemCounts(player: Player): { [string]: number }
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

	-- Add to inventory (backpack)
	if InventoryService.AddItem(player, itemId, quantity) then
		-- Remove from world
		lootInstance:Destroy()

		local name = itemData.name or itemId
		local state = GetPlayerState(player)
		local slotCount = state and #state.inventory or 0
		local maxSlots = state and state.maxSlots or Config.Player.MaxInventorySlots
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

	-- Remove from inventory
	table.remove(state.inventory, slotIndex)
	UpdateHUD:FireClient(player, "InventoryUpdate", state.inventory)
end)

------------------------------------------------------------------------
-- Use Item (eat food, use light source, etc.)
------------------------------------------------------------------------
UseItem.OnServerEvent:Connect(function(player, slotIndex)
	local state = GetPlayerState(player)
	if not state then return end

	local slot = state.inventory[slotIndex]
	if not slot then return end

	local itemData = ItemDatabase.GetItem(slot.itemId)
	if not itemData then return end

	-- Food consumption
	if itemData.category == Enums.ItemCategory.Food and itemData.hungerRestore and itemData.hungerRestore > 0 then
		-- Raw meat sickness check
		if itemData.rawMeat then
			if math.random() < Config.Food.SicknessChanceRaw then
				NotifyPlayers:FireClient(player,
					"You feel sick from eating raw meat...",
					Color3.fromRGB(150, 200, 0)
				)
				-- Apply nausea debuff
				table.insert(state.buffs, {
					type = "Nausea",
					amount = 1,
					expiresAt = tick() + Config.Food.SicknessDuration,
				})
			end
		end

		-- Restore hunger
		state.hunger = Utils.Clamp(
			state.hunger + itemData.hungerRestore,
			0, Config.Hunger.MaxHunger
		)

		-- Apply buff if any
		if itemData.buff then
			table.insert(state.buffs, {
				type = itemData.buff.type,
				amount = itemData.buff.amount,
				expiresAt = tick() + (itemData.buff.duration or 0),
			})
			UpdateHUD:FireClient(player, "BuffApplied", itemData.buff)
		end

		NotifyPlayers:FireClient(player,
			"Ate " .. itemData.name .. " (+" .. itemData.hungerRestore .. "% hunger)",
			Color3.fromRGB(100, 255, 100)
		)

		InventoryService.RemoveItem(player, slotIndex, 1)
		return
	end

	-- Recipe card
	if itemData.category == Enums.ItemCategory.Recipe then
		local recipeId = itemData.recipeId
		if recipeId and not state.knownRecipes[recipeId] then
			state.knownRecipes[recipeId] = true
			NotifyPlayers:FireClient(player,
				"Learned recipe: " .. itemData.name,
				Color3.fromRGB(255, 200, 50)
			)
			InventoryService.RemoveItem(player, slotIndex, 1)
		else
			NotifyPlayers:FireClient(player,
				"You already know this recipe.",
				Color3.fromRGB(200, 200, 200)
			)
		end
		return
	end

	-- Energy drink (instant use)
	if slot.itemId == "energy_drink" then
		state.stamina = 100
		state.hunger = Utils.Clamp(state.hunger + 10, 0, Config.Hunger.MaxHunger)
		if itemData.buff then
			table.insert(state.buffs, {
				type = itemData.buff.type,
				amount = itemData.buff.amount,
				expiresAt = tick() + (itemData.buff.duration or 0),
			})
		end
		NotifyPlayers:FireClient(player, "Energy drink consumed! Full stamina!", Color3.fromRGB(0, 255, 255))
		InventoryService.RemoveItem(player, slotIndex, 1)
		return
	end
end)

print("[InventoryService] Initialized")
