--[[
	CombatService.server.lua
	Server-authoritative combat: melee swings, ranged shots, damage calculation,
	downed state, and revive mechanics.
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
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")

------------------------------------------------------------------------
-- Create combat remotes
------------------------------------------------------------------------
local CombatRemotes = Instance.new("Folder")
CombatRemotes.Name = "CombatRemotes"
CombatRemotes.Parent = ReplicatedStorage

local MeleeAttack = Instance.new("RemoteEvent")
MeleeAttack.Name = "MeleeAttack"
MeleeAttack.Parent = CombatRemotes

local RangedAttack = Instance.new("RemoteEvent")
RangedAttack.Name = "RangedAttack"
RangedAttack.Parent = CombatRemotes

local EquipWeapon = Instance.new("RemoteEvent")
EquipWeapon.Name = "EquipWeapon"
EquipWeapon.Parent = CombatRemotes

local DamageNumber = Instance.new("RemoteEvent")
DamageNumber.Name = "DamageNumber"
DamageNumber.Parent = CombatRemotes

------------------------------------------------------------------------
-- Helper
------------------------------------------------------------------------
local function GetPlayerState(player)
	local getter = game.ServerStorage:FindFirstChild("GetPlayerState")
	if getter then return getter:Invoke(player) end
	return nil
end

------------------------------------------------------------------------
-- Cooldown tracking
------------------------------------------------------------------------
local LastAttackTime = {}  -- [player] = tick()

------------------------------------------------------------------------
-- Weapon Equip State
------------------------------------------------------------------------
local EquippedWeapons = {}  -- [player] = { itemId, slotIndex }

EquipWeapon.OnServerEvent:Connect(function(player, slotIndex)
	local state = GetPlayerState(player)
	if not state then return end

	local slot = state.inventory[slotIndex]
	if not slot then
		EquippedWeapons[player] = nil
		return
	end

	local itemData = ItemDatabase.GetItem(slot.itemId)
	if not itemData or itemData.category ~= Enums.ItemCategory.Weapon then
		EquippedWeapons[player] = nil
		return
	end

	EquippedWeapons[player] = {
		itemId = slot.itemId,
		slotIndex = slotIndex,
		data = itemData,
	}

	UpdateHUD:FireClient(player, "WeaponEquipped", {
		name = itemData.name,
		type = itemData.weaponType,
		damage = itemData.damage,
	})
end)

------------------------------------------------------------------------
-- Melee Attack
------------------------------------------------------------------------
MeleeAttack.OnServerEvent:Connect(function(player, targetModel)
	local state = GetPlayerState(player)
	if not state or state.state ~= Enums.PlayerState.Alive then return end

	-- Cooldown check
	local now = tick()
	local lastAttack = LastAttackTime[player] or 0
	local weapon = EquippedWeapons[player]
	local cooldown = Config.Combat.MeleeSwingCooldown

	if weapon and weapon.data then
		cooldown = weapon.data.swingSpeed or cooldown
	end

	if now - lastAttack < cooldown then return end
	LastAttackTime[player] = now

	-- Validate target
	if not targetModel or not targetModel:IsA("Model") then return end
	if not targetModel:IsDescendantOf(workspace) then return end

	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local targetHRP = targetModel:FindFirstChild("HumanoidRootPart")
	if not targetHRP then return end

	-- Range check
	local maxRange = 6  -- default punch range
	if weapon and weapon.data then
		maxRange = weapon.data.range or 6
	end

	local dist = Utils.Distance(hrp.Position, targetHRP.Position)
	if dist > maxRange + 2 then return end  -- +2 tolerance for lag

	-- Calculate damage
	local baseDamage = 10  -- bare fist
	if weapon and weapon.data then
		baseDamage = weapon.data.damage
	end

	-- Hunger debuff
	if state.hunger < Config.Hunger.HungryThreshold then
		baseDamage = baseDamage * Config.Hunger.HungryMeleeDamageReduction
	end

	-- Buff check
	for _, buff in ipairs(state.buffs) do
		if buff.type == "AllStats" and tick() < buff.expiresAt then
			baseDamage = baseDamage * buff.amount
		end
	end

	local damage = math.floor(baseDamage)

	-- Apply damage to target
	local targetHumanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if targetHumanoid and targetHumanoid.Health > 0 then
		targetHumanoid:TakeDamage(damage)

		-- Show damage number to attacker
		DamageNumber:FireClient(player, targetHRP.Position, damage, false)

		-- Mark player as in combat
		state.isInCombat = true
		task.delay(5, function()
			if state then state.isInCombat = false end
		end)
	end
end)

------------------------------------------------------------------------
-- Ranged Attack
------------------------------------------------------------------------
RangedAttack.OnServerEvent:Connect(function(player, targetPosition, targetModel)
	local state = GetPlayerState(player)
	if not state or state.state ~= Enums.PlayerState.Alive then return end

	local weapon = EquippedWeapons[player]
	if not weapon or not weapon.data or weapon.data.weaponType ~= "Ranged" then
		NotifyPlayers:FireClient(player, "No ranged weapon equipped.", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Cooldown
	local now = tick()
	local lastAttack = LastAttackTime[player] or 0
	local cooldown = weapon.data.fireRate or Config.Combat.RangedFireCooldown
	if now - lastAttack < cooldown then return end
	LastAttackTime[player] = now

	-- Ammo check
	local ammoType = weapon.data.ammoType
	if ammoType then
		local hasAmmo = false
		for _, slot in ipairs(state.inventory) do
			if slot.itemId == ammoType and slot.quantity > 0 then
				slot.quantity -= 1
				if slot.quantity <= 0 then
					for i, s in ipairs(state.inventory) do
						if s == slot then
							table.remove(state.inventory, i)
							break
						end
					end
				end
				hasAmmo = true
				break
			end
		end

		if not hasAmmo then
			NotifyPlayers:FireClient(player, "Out of ammo!", Color3.fromRGB(255, 100, 100))
			return
		end
	end

	-- Range check
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local maxRange = weapon.data.range or 60
	local dist = (targetPosition - hrp.Position).Magnitude
	if dist > maxRange + 5 then return end

	-- Calculate damage
	local baseDamage = weapon.data.damage

	-- Check for headshot
	local isHeadshot = false
	if targetModel and targetModel:IsA("Model") then
		local head = targetModel:FindFirstChild("Head")
		if head then
			local headDist = (targetPosition - head.Position).Magnitude
			if headDist < 3 then
				isHeadshot = true
				baseDamage = baseDamage * Config.Combat.HeadshotMultiplier
			end
		end
	end

	-- Spread for shotguns
	if weapon.data.spread and weapon.data.spread > 0 then
		-- Shotgun hits multiple targets in cone
		-- For simplicity, apply full damage to primary target,
		-- reduced damage to nearby enemies
		local aoeRadius = weapon.data.spread

		local purgeEnemies = CollectionService:GetTagged("PurgeEnemy")
		for _, enemy in ipairs(purgeEnemies) do
			if enemy == targetModel then continue end
			local enemyHRP = enemy:FindFirstChild("HumanoidRootPart")
			if enemyHRP then
				local eDist = (targetPosition - enemyHRP.Position).Magnitude
				if eDist <= aoeRadius then
					local enemyHum = enemy:FindFirstChildOfClass("Humanoid")
					if enemyHum and enemyHum.Health > 0 then
						local splashDmg = math.floor(baseDamage * 0.4)
						enemyHum:TakeDamage(splashDmg)
						DamageNumber:FireClient(player, enemyHRP.Position, splashDmg, false)
					end
				end
			end
		end
	end

	-- Buff check (steady aim from herb tea)
	for _, buff in ipairs(state.buffs) do
		if buff.type == "AllStats" and tick() < buff.expiresAt then
			baseDamage = baseDamage * buff.amount
		end
	end

	local damage = math.floor(baseDamage)

	-- Apply to target
	if targetModel and targetModel:IsA("Model") then
		local targetHumanoid = targetModel:FindFirstChildOfClass("Humanoid")
		if targetHumanoid and targetHumanoid.Health > 0 then
			targetHumanoid:TakeDamage(damage)
			local targetHRP = targetModel:FindFirstChild("HumanoidRootPart")
			if targetHRP then
				DamageNumber:FireClient(player, targetHRP.Position, damage, isHeadshot)
			end
		end
	end

	-- Mark in combat
	state.isInCombat = true
	task.delay(5, function()
		if state then state.isInCombat = false end
	end)

	-- Update inventory (ammo consumed)
	UpdateHUD:FireClient(player, "InventoryUpdate", state.inventory)
end)

------------------------------------------------------------------------
-- Cleanup
------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
	EquippedWeapons[player] = nil
	LastAttackTime[player] = nil
end)

print("[CombatService] Initialized")
