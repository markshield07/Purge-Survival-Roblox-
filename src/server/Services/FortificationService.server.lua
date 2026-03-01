--[[
	FortificationService.server.lua
	Manages house fortification: installing materials, upgrading slots,
	damage during Purge, and repair.
	Players can only fortify their own home base (StarterHouse).
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
-- Helpers: read from GameManager (copies, safe for reads only)
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
-- Helpers: mutate authoritative state via GameManager BindableFunctions
------------------------------------------------------------------------
local function SetFortSlot(slotName, slotData)
	local setter = game.ServerStorage:FindFirstChild("SetFortificationSlot")
	if setter then return setter:Invoke(slotName, slotData) end
	return false
end

local function GetFortSlot(slotName)
	local getter = game.ServerStorage:FindFirstChild("GetFortificationSlot")
	if getter then return getter:Invoke(slotName) end
	return nil
end

local function RemovePlayerItem(player, slotIndex, quantity)
	local remover = game.ServerStorage:FindFirstChild("RemovePlayerItem")
	if remover then return remover:Invoke(player, slotIndex, quantity) end
	return false
end

------------------------------------------------------------------------
-- Ownership: Check if a FortSlot belongs to the StarterHouse
------------------------------------------------------------------------
local function IsStarterHouseSlot(slotName: string): boolean
	local slotParts = CollectionService:GetTagged("FortSlot")
	for _, part in ipairs(slotParts) do
		if part:GetAttribute("SlotName") == slotName then
			-- Walk up parents to check if inside StarterHouse folder
			local parent = part.Parent
			while parent do
				if parent.Name == "StarterHouse" then
					return true
				end
				parent = parent.Parent
			end
			return false
		end
	end
	return false
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
	-- Ownership check: only allow fortifying your own home base
	if not IsStarterHouseSlot(slotName) then
		NotifyPlayers:FireClient(player,
			"You can only fortify your own home base!",
			Color3.fromRGB(255, 100, 100)
		)
		return
	end

	local slot = GetFortSlot(slotName)
	if not slot then
		NotifyPlayers:FireClient(player, "Invalid fortification slot.", Color3.fromRGB(255, 100, 100))
		return
	end

	local playerState = GetPlayerState(player)
	if not playerState then return end

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

	-- Install the material (mutate authoritative state)
	local durability = FortificationService.GetDurability(invSlot.itemId)
	slot.materialId = invSlot.itemId
	slot.durability = durability
	slot.maxDurability = durability
	SetFortSlot(slotName, slot)

	-- Remove item from authoritative inventory
	RemovePlayerItem(player, inventorySlotIndex, 1)

	-- Update visuals
	FortificationService.UpdateSlotVisual(slotName, slot)
	UpdateHUD:FireAllClients("FortificationUpdate", { slotName = slotName, data = slot })
	NotifyPlayers:FireClient(player,
		"Installed " .. itemData.name .. " on " .. slotName .. " (HP: " .. durability .. ")",
		Color3.fromRGB(100, 255, 100)
	)
end

-- Install a trap
function FortificationService.InstallTrap(player: Player, slotName: string, inventorySlotIndex: number)
	-- Ownership check
	if not IsStarterHouseSlot(slotName) then
		NotifyPlayers:FireClient(player,
			"You can only place traps in your own home base!",
			Color3.fromRGB(255, 100, 100)
		)
		return
	end

	local gameState = GetGameState()
	if not gameState then return end

	local playerState = GetPlayerState(player)
	if not playerState then return end

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

	-- Build trap slot data and persist via authoritative mutation
	local existingSlot = GetFortSlot(slotName)
	local trapSlot = existingSlot or {}
	trapSlot.slotType = Enums.FortSlot.HallwayTrap
	trapSlot.materialId = invSlot.itemId
	trapSlot.durability = 1
	trapSlot.maxDurability = 1
	trapSlot.isTrap = true
	trapSlot.trapDamage = itemData.damage or 0
	trapSlot.requiresPower = itemData.requiresPower or false
	SetFortSlot(slotName, trapSlot)

	-- Remove item from authoritative inventory
	RemovePlayerItem(player, inventorySlotIndex, 1)

	NotifyPlayers:FireClient(player,
		"Installed " .. itemData.name .. " at " .. slotName,
		Color3.fromRGB(100, 255, 100)
	)
end

-- Damage a fortification slot (called by Purge enemies)
function FortificationService.DamageSlot(slotName: string, damage: number): boolean
	local slot = GetFortSlot(slotName)
	if not slot or not slot.materialId then
		return true  -- no fortification = breached
	end

	slot.durability = slot.durability - damage
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
		SetFortSlot(slotName, slot)
		return true  -- enemies can pass through
	end

	SetFortSlot(slotName, slot)
	return false  -- still holding
end

-- Repair a fortification slot
function FortificationService.RepairSlot(player: Player, slotName: string)
	-- Ownership check
	if not IsStarterHouseSlot(slotName) then
		NotifyPlayers:FireClient(player,
			"You can only repair your own home base!",
			Color3.fromRGB(255, 100, 100)
		)
		return
	end

	local slot = GetFortSlot(slotName)
	if not slot or not slot.materialId then
		NotifyPlayers:FireClient(player, "Nothing to repair here.", Color3.fromRGB(255, 200, 100))
		return
	end

	if slot.durability >= slot.maxDurability then
		NotifyPlayers:FireClient(player, "Already at full durability.", Color3.fromRGB(200, 200, 200))
		return
	end

	-- Find repair material in player's inventory (read copy is fine for search)
	local playerState = GetPlayerState(player)
	if not playerState then return end

	local repairSlotIdx = nil
	for i, invSlot in ipairs(playerState.inventory) do
		if invSlot.itemId == "duct_tape" or invSlot.itemId == "nails" then
			repairSlotIdx = i
			break
		end
	end

	if not repairSlotIdx then
		NotifyPlayers:FireClient(player, "Need duct tape or nails to repair.", Color3.fromRGB(255, 200, 100))
		return
	end

	-- Restore 25% durability (mutate authoritative state)
	local repairAmount = math.ceil(slot.maxDurability * 0.25)
	slot.durability = math.min(slot.maxDurability, slot.durability + repairAmount)
	SetFortSlot(slotName, slot)

	-- Consume repair material from authoritative inventory
	RemovePlayerItem(player, repairSlotIdx, 1)

	FortificationService.UpdateSlotVisual(slotName, slot)
	UpdateHUD:FireAllClients("FortificationUpdate", { slotName = slotName, data = slot })
	NotifyPlayers:FireClient(player,
		"Repaired " .. slotName .. " (+" .. repairAmount .. " HP)",
		Color3.fromRGB(100, 200, 255)
	)
end

-- Update visual representation of a fortification slot
function FortificationService.UpdateSlotVisual(slotName: string, slotData)
	local slotParts = CollectionService:GetTagged("FortSlot")
	for _, part in ipairs(slotParts) do
		if part:GetAttribute("SlotName") == slotName then
			if slotData.materialId then
				-- Show fortified appearance (solid barrier)
				local itemData = ItemDatabase.GetItem(slotData.materialId)
				local tierColor = Enums.TierColor[itemData and itemData.tier or "Common"]
				part.Color = tierColor or Color3.fromRGB(139, 90, 43)
				part.Transparency = 0
				part.CanCollide = true
				part.Material = Enum.Material.Wood

				if itemData and itemData.tier == "Rare" then
					part.Material = Enum.Material.Metal
				elseif itemData and itemData.tier == "Epic" then
					part.Material = Enum.Material.Neon
				end
			else
				-- Show broken / unfortified (walk-through)
				part.Transparency = 0.5
				part.CanCollide = false
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
