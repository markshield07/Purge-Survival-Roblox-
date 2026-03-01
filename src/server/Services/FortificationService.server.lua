--[[
	FortificationService.server.lua
	Manages house fortification: installing materials, upgrading slots,
	damage during Purge, and repair.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local ItemDatabase = require(Modules.ItemDatabase)
local Utils = require(Modules.Utils)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FortifyRequest = Remotes:WaitForChild("FortifyRequest")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")

------------------------------------------------------------------------
-- Helper: Get shared game state
------------------------------------------------------------------------
local function GetGameState()
	local getter = game.ServerStorage:FindFirstChild("GetGameState")
	if getter then return getter:Invoke() end
	return nil
end

local function GetPlayerState(player)
	local getter = game.ServerStorage:FindFirstChild("GetPlayerState")
	if getter then return getter:Invoke(player) end
	return nil
end

------------------------------------------------------------------------
-- Fortification Logic
------------------------------------------------------------------------
local FortificationService = {}

-- Check if an item can be used for fortification
function FortificationService.IsValidMaterial(itemId: string): boolean
	local itemData = ItemDatabase.GetItem(itemId)
	if not itemData then return false end
	return itemData.category == Enums.ItemCategory.BuildingMaterial
end

-- Get durability for a material
function FortificationService.GetDurability(itemId: string): number
	local itemData = ItemDatabase.GetItem(itemId)
	if not itemData then return 0 end
	return Config.Fortification.TierDurability[itemData.tier] or 0
end

-- Install material on a fortification slot
function FortificationService.InstallFortification(player: Player, slotName: string, inventorySlotIndex: number)
	local gameState = GetGameState()
	local playerState = GetPlayerState(player)
	if not gameState or not playerState then return end

	local slot = gameState.house.fortifications[slotName]
	if not slot then
		NotifyPlayers:FireClient(player, "Invalid fortification slot.", Color3.fromRGB(255, 100, 100))
		return
	end

	local invSlot = playerState.inventory[inventorySlotIndex]
	if not invSlot then return end

	local itemData = ItemDatabase.GetItem(invSlot.itemId)
	if not itemData or itemData.category ~= Enums.ItemCategory.BuildingMaterial then
		NotifyPlayers:FireClient(player, "That item can't be used for fortification.", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Check if this is an upgrade (new material is better tier)
	local tierOrder = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4 }
	if slot.materialId then
		local existingData = ItemDatabase.GetItem(slot.materialId)
		if existingData then
			local existingTier = tierOrder[existingData.tier] or 0
			local newTier = tierOrder[itemData.tier] or 0
			if newTier <= existingTier then
				NotifyPlayers:FireClient(player,
					"Current fortification is equal or better. Use higher tier materials.",
					Color3.fromRGB(255, 200, 100)
				)
				return
			end
		end
	end

	-- Install the material
	local durability = FortificationService.GetDurability(invSlot.itemId)
	slot.materialId = invSlot.itemId
	slot.durability = durability
	slot.maxDurability = durability

	-- Remove from inventory
	invSlot.quantity -= 1
	if invSlot.quantity <= 0 then
		table.remove(playerState.inventory, inventorySlotIndex)
	end

	-- Update the physical fortification in workspace
	FortificationService.UpdateSlotVisual(slotName, slot)

	UpdateHUD:FireClient(player, "InventoryUpdate", playerState.inventory)
	UpdateHUD:FireAllClients("FortificationUpdate", { slotName = slotName, data = slot })
	NotifyPlayers:FireClient(player,
		"Installed " .. itemData.name .. " on " .. slotName .. " (HP: " .. durability .. ")",
		Color3.fromRGB(100, 255, 100)
	)
end

-- Install a trap
function FortificationService.InstallTrap(player: Player, slotName: string, inventorySlotIndex: number)
	local gameState = GetGameState()
	local playerState = GetPlayerState(player)
	if not gameState or not playerState then return end

	local invSlot = playerState.inventory[inventorySlotIndex]
	if not invSlot then return end

	local itemData = ItemDatabase.GetItem(invSlot.itemId)
	if not itemData or itemData.category ~= Enums.ItemCategory.Trap then
		NotifyPlayers:FireClient(player, "That item is not a trap.", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Check power requirement
	if itemData.requiresPower and not gameState.generator.isPowered then
		NotifyPlayers:FireClient(player, "This requires electricity! Generator is off.", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Install trap at slot
	local slot = gameState.house.fortifications[slotName]
	if not slot then
		-- Create new trap slot
		gameState.house.fortifications[slotName] = {
			slotType = Enums.FortSlot.HallwayTrap,
			materialId = invSlot.itemId,
			durability = 1,  -- traps are single-use or active
			maxDurability = 1,
			isTrap = true,
			trapDamage = itemData.damage or 0,
			requiresPower = itemData.requiresPower or false,
		}
	else
		slot.materialId = invSlot.itemId
		slot.isTrap = true
		slot.trapDamage = itemData.damage or 0
		slot.requiresPower = itemData.requiresPower or false
	end

	-- Remove from inventory
	invSlot.quantity -= 1
	if invSlot.quantity <= 0 then
		table.remove(playerState.inventory, inventorySlotIndex)
	end

	UpdateHUD:FireClient(player, "InventoryUpdate", playerState.inventory)
	NotifyPlayers:FireClient(player,
		"Installed " .. itemData.name .. " at " .. slotName,
		Color3.fromRGB(100, 255, 100)
	)
end

-- Damage a fortification slot (called by Purge enemies)
function FortificationService.DamageSlot(slotName: string, damage: number): boolean
	local gameState = GetGameState()
	if not gameState then return true end  -- broken through

	local slot = gameState.house.fortifications[slotName]
	if not slot or not slot.materialId then
		return true  -- no fortification = breached
	end

	slot.durability -= damage
	UpdateHUD:FireAllClients("FortificationUpdate", { slotName = slotName, data = slot })

	if slot.durability <= 0 then
		-- Fortification destroyed
		slot.materialId = nil
		slot.durability = 0
		slot.maxDurability = 0

		NotifyPlayers:FireAllClients(
			slotName .. " fortification has been BREACHED!",
			Color3.fromRGB(255, 0, 0)
		)

		FortificationService.UpdateSlotVisual(slotName, slot)
		return true  -- enemies can pass through
	end

	return false  -- still holding
end

-- Repair a fortification slot
function FortificationService.RepairSlot(player: Player, slotName: string)
	local gameState = GetGameState()
	local playerState = GetPlayerState(player)
	if not gameState or not playerState then return end

	local slot = gameState.house.fortifications[slotName]
	if not slot or not slot.materialId then
		NotifyPlayers:FireClient(player, "Nothing to repair here.", Color3.fromRGB(255, 200, 100))
		return
	end

	if slot.durability >= slot.maxDurability then
		NotifyPlayers:FireClient(player, "Already at full durability.", Color3.fromRGB(200, 200, 200))
		return
	end

	-- Require duct tape or nails for repair
	local repairItem = nil
	local repairSlotIdx = nil
	for i, invSlot in ipairs(playerState.inventory) do
		if invSlot.itemId == "duct_tape" or invSlot.itemId == "nails" then
			repairItem = invSlot
			repairSlotIdx = i
			break
		end
	end

	if not repairItem then
		NotifyPlayers:FireClient(player, "Need duct tape or nails to repair.", Color3.fromRGB(255, 200, 100))
		return
	end

	-- Restore 25% durability
	local repairAmount = math.ceil(slot.maxDurability * 0.25)
	slot.durability = math.min(slot.maxDurability, slot.durability + repairAmount)

	-- Consume repair material
	repairItem.quantity -= 1
	if repairItem.quantity <= 0 then
		table.remove(playerState.inventory, repairSlotIdx)
	end

	FortificationService.UpdateSlotVisual(slotName, slot)
	UpdateHUD:FireClient(player, "InventoryUpdate", playerState.inventory)
	UpdateHUD:FireAllClients("FortificationUpdate", { slotName = slotName, data = slot })
	NotifyPlayers:FireClient(player,
		"Repaired " .. slotName .. " (+" .. repairAmount .. " HP)",
		Color3.fromRGB(100, 200, 255)
	)
end

-- Update visual representation of a fortification slot
function FortificationService.UpdateSlotVisual(slotName: string, slotData)
	-- Find the physical slot in the workspace
	local slotParts = CollectionService:GetTagged("FortSlot")
	for _, part in ipairs(slotParts) do
		if part:GetAttribute("SlotName") == slotName then
			if slotData.materialId then
				-- Show fortified appearance
				local itemData = ItemDatabase.GetItem(slotData.materialId)
				local tierColor = Enums.TierColor[itemData and itemData.tier or "Common"]
				part.Color = tierColor or Color3.fromRGB(139, 90, 43)
				part.Transparency = 0
				part.Material = Enum.Material.Wood

				if itemData and itemData.tier == "Rare" then
					part.Material = Enum.Material.Metal
				elseif itemData and itemData.tier == "Epic" then
					part.Material = Enum.Material.Neon
				end
			else
				-- Show broken / unfortified
				part.Transparency = 0.5
				part.Color = Color3.fromRGB(80, 50, 30)
				part.Material = Enum.Material.Wood
			end
			break
		end
	end
end

-- Get weakest fortification slot (for Purge enemy targeting)
function FortificationService.GetWeakestSlot(): (string?, any?)
	local gameState = GetGameState()
	if not gameState then return nil, nil end

	local weakestName = nil
	local weakestData = nil
	local lowestDurability = math.huge

	for name, data in pairs(gameState.house.fortifications) do
		local dur = data.materialId and data.durability or 0
		if dur < lowestDurability then
			lowestDurability = dur
			weakestName = name
			weakestData = data
		end
	end

	return weakestName, weakestData
end

------------------------------------------------------------------------
-- Remote Event Handlers
------------------------------------------------------------------------
FortifyRequest.OnServerEvent:Connect(function(player, action, slotName, inventorySlotIndex)
	if action == "install" then
		FortificationService.InstallFortification(player, slotName, inventorySlotIndex)
	elseif action == "trap" then
		FortificationService.InstallTrap(player, slotName, inventorySlotIndex)
	elseif action == "repair" then
		FortificationService.RepairSlot(player, slotName)
	end
end)

------------------------------------------------------------------------
-- Expose service via BindableFunction for other server scripts
------------------------------------------------------------------------
local fortDamage = Instance.new("BindableFunction")
fortDamage.Name = "DamageFortification"
fortDamage.Parent = game.ServerStorage
fortDamage.OnInvoke = function(slotName, damage)
	return FortificationService.DamageSlot(slotName, damage)
end

local getWeakest = Instance.new("BindableFunction")
getWeakest.Name = "GetWeakestFortification"
getWeakest.Parent = game.ServerStorage
getWeakest.OnInvoke = function()
	return FortificationService.GetWeakestSlot()
end

print("[FortificationService] Initialized")
