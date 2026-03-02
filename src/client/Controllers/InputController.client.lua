--[[
	InputController.client.lua
	Handles player input: 99 Nights-style hotbar selection, combat,
	sprint, item use/drop, and scroll-wheel cycling.

	Controls (matching 99 Nights in the Forest):
	  [1-5+]        Select hotbar slot
	  Scroll Wheel  Cycle hotbar slots
	  Left Click    Use selected item (eat food / use consumable)
	                Attack with equipped weapon (if clicking enemy)
	  Backspace     Drop the selected item
	  Shift         Sprint (hold)
	  E             Interact (Roblox ProximityPrompt)
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local ItemDatabase = require(Modules.ItemDatabase)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UseItem = Remotes:WaitForChild("UseItem")
local DropItem = Remotes:WaitForChild("DropItem")
local PickupItem = Remotes:WaitForChild("PickupItem")
local EquipItem = Remotes:WaitForChild("EquipItem")

local CombatRemotes = ReplicatedStorage:WaitForChild("CombatRemotes")
local MeleeAttack = CombatRemotes:WaitForChild("MeleeAttack")
local RangedAttack = CombatRemotes:WaitForChild("RangedAttack")

------------------------------------------------------------------------
-- HUD communication (via BindableFunction / BindableEvent in PurgeHUD)
------------------------------------------------------------------------
local HUD = Player.PlayerGui:WaitForChild("PurgeHUD")
local GetHotbarState = HUD:WaitForChild("GetHotbarState")
local HotbarAction = HUD:WaitForChild("HotbarAction")

local function GetSelectedSlot(): number
	return GetHotbarState:Invoke("GetSelectedSlot") or 0
end

local function GetInventory()
	return GetHotbarState:Invoke("GetInventory") or {}
end

local function GetMaxSlots(): number
	return GetHotbarState:Invoke("GetMaxSlots") or 5
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local IsSprinting = false
local IsAttacking = false

------------------------------------------------------------------------
-- Character Refresh
------------------------------------------------------------------------
Player.CharacterAdded:Connect(function(char)
	Character = char
	Humanoid = char:WaitForChild("Humanoid")
end)

------------------------------------------------------------------------
-- Sprint System
------------------------------------------------------------------------
local function StartSprint()
	if IsSprinting then return end
	IsSprinting = true
	if Humanoid then
		Humanoid.WalkSpeed = Config.Player.BaseSprintSpeed
	end
end

local function StopSprint()
	if not IsSprinting then return end
	IsSprinting = false
	if Humanoid then
		Humanoid.WalkSpeed = Config.Player.BaseWalkSpeed
	end
end

------------------------------------------------------------------------
-- Attack (left click on enemy)
------------------------------------------------------------------------
local function OnAttack()
	if IsAttacking then return end
	IsAttacking = true

	-- Raycast from camera to find target
	local mouse = Player:GetMouse()
	local camera = workspace.CurrentCamera

	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { Character }

	local result = workspace:Raycast(ray.Origin, ray.Direction * 100, raycastParams)

	if result and result.Instance then
		local targetModel = result.Instance:FindFirstAncestorOfClass("Model")
		if targetModel and targetModel:FindFirstChildOfClass("Humanoid") then
			MeleeAttack:FireServer(targetModel)
		end
	end

	task.delay(0.5, function()
		IsAttacking = false
	end)
end

------------------------------------------------------------------------
-- Left Click Handler — 99 Nights style
-- If clicking on an enemy model → attack
-- If not on enemy → use selected hotbar item (eat/consume)
------------------------------------------------------------------------
local function OnLeftClick()
	-- First check if clicking on an enemy
	local mouse = Player:GetMouse()
	local camera = workspace.CurrentCamera

	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { Character }

	local result = workspace:Raycast(ray.Origin, ray.Direction * 100, raycastParams)

	if result and result.Instance then
		local targetModel = result.Instance:FindFirstAncestorOfClass("Model")
		if targetModel and targetModel:FindFirstChildOfClass("Humanoid") then
			-- Clicking on an enemy → attack
			OnAttack()
			return
		end
	end

	-- Not clicking on an enemy → use selected hotbar item
	local slot = GetSelectedSlot()
	if slot > 0 then
		local inventory = GetInventory()
		local item = inventory[slot]
		if item then
			local itemData = ItemDatabase.GetItem(item.itemId)
			if itemData then
				-- Don't "use" weapons via click (they attack via the raycast above)
				if itemData.category ~= Enums.ItemCategory.Weapon then
					HotbarAction:Fire("UseSelected")
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Scroll Wheel — cycle hotbar slots
------------------------------------------------------------------------
local function OnScrollWheel(direction)
	local maxSlots = GetMaxSlots()
	local current = GetSelectedSlot()

	if current == 0 then
		-- Nothing selected, start at 1
		HotbarAction:Fire("SelectSlot", 1)
		return
	end

	local newSlot = current + direction
	if newSlot < 1 then
		newSlot = maxSlots
	elseif newSlot > maxSlots then
		newSlot = 1
	end

	HotbarAction:Fire("SelectSlot", newSlot)
end

------------------------------------------------------------------------
-- Input Bindings
------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- Sprint (Left Shift)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		StartSprint()
	end

	-- Hotbar slots (1-9, 0)
	local keyToSlot = {
		[Enum.KeyCode.One] = 1,
		[Enum.KeyCode.Two] = 2,
		[Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4,
		[Enum.KeyCode.Five] = 5,
		[Enum.KeyCode.Six] = 6,
		[Enum.KeyCode.Seven] = 7,
		[Enum.KeyCode.Eight] = 8,
		[Enum.KeyCode.Nine] = 9,
		[Enum.KeyCode.Zero] = 10,
	}
	if keyToSlot[input.KeyCode] then
		local slot = keyToSlot[input.KeyCode]
		local maxSlots = GetMaxSlots()
		if slot <= maxSlots then
			HotbarAction:Fire("SelectSlot", slot)
		end
	end

	-- Backspace — Drop selected item (99 Nights style)
	if input.KeyCode == Enum.KeyCode.Backspace then
		HotbarAction:Fire("DropSelected")
	end

	-- Left click — attack enemy or use selected item
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		OnLeftClick()
	end

	-- Scroll wheel
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		-- Negative = scroll down (next slot), Positive = scroll up (prev slot)
		-- Note: scroll direction is in input.Position.Z
	end
end)

-- Scroll wheel via InputChanged (more reliable for mouse wheel)
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local direction = input.Position.Z > 0 and -1 or 1
		OnScrollWheel(direction)
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		StopSprint()
	end
end)

------------------------------------------------------------------------
-- Mobile Support: Touch sprint button
------------------------------------------------------------------------
if UserInputService.TouchEnabled then
	local sprintButton = Instance.new("TextButton")
	sprintButton.Name = "SprintButton"
	sprintButton.Size = UDim2.new(0, 80, 0, 80)
	sprintButton.Position = UDim2.new(1, -100, 1, -200)
	sprintButton.AnchorPoint = Vector2.new(1, 1)
	sprintButton.Text = "SPRINT"
	sprintButton.TextColor3 = Color3.new(1, 1, 1)
	sprintButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	sprintButton.BackgroundTransparency = 0.4
	sprintButton.Font = Enum.Font.GothamBold
	sprintButton.TextScaled = true
	sprintButton.Parent = HUD

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 40)
	corner.Parent = sprintButton

	sprintButton.MouseButton1Down:Connect(StartSprint)
	sprintButton.MouseButton1Up:Connect(StopSprint)
end

------------------------------------------------------------------------
-- Tree Chopping (click on trees tagged "Tree")
------------------------------------------------------------------------
local ChopTreeRemote = Remotes:FindFirstChild("ChopTree")
local CollectionService = game:GetService("CollectionService")
local Mouse = Player:GetMouse()

local lastChopTime = 0
local CHOP_COOLDOWN = Config.Gathering and Config.Gathering.TreeChopTime or 2

Mouse.Button1Down:Connect(function()
	if not ChopTreeRemote then return end
	if tick() - lastChopTime < CHOP_COOLDOWN then return end

	local target = Mouse.Target
	if not target then return end

	-- Check if target or any ancestor is a tree
	local isTree = CollectionService:HasTag(target, "Tree")
	if not isTree then
		local parent = target.Parent
		while parent and parent ~= workspace do
			if CollectionService:HasTag(parent, "Tree") then
				target = parent
				isTree = true
				break
			end
			parent = parent.Parent
		end
	end

	if isTree then
		lastChopTime = tick()
		ChopTreeRemote:FireServer(target)
	end
end)

------------------------------------------------------------------------
-- Flashlight Stun (F key to stun The Stalker)
------------------------------------------------------------------------
local FlashlightStunRemote = Remotes:FindFirstChild("FlashlightStun")

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.F and FlashlightStunRemote then
		FlashlightStunRemote:FireServer()
	end
end)

------------------------------------------------------------------------
-- Campfire Refuel (R key when near campfire with fuel in selected slot)
------------------------------------------------------------------------
local RefuelCampfireRemote = Remotes:FindFirstChild("RefuelCampfire")

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.R and RefuelCampfireRemote then
		local selected = GetSelectedSlot()
		if selected > 0 then
			RefuelCampfireRemote:FireServer(selected)
		end
	end
end)

print("[InputController] Initialized")
