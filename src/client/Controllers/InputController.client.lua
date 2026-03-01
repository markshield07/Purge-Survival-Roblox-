--[[
	InputController.client.lua
	Handles player input: sprinting, interaction, weapon use, inventory.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UseItem = Remotes:WaitForChild("UseItem")
local DropItem = Remotes:WaitForChild("DropItem")
local PickupItem = Remotes:WaitForChild("PickupItem")
local CookRequest = Remotes:WaitForChild("CookRequest")
local FortifyRequest = Remotes:WaitForChild("FortifyRequest")
local RefuelRequest = Remotes:WaitForChild("RefuelRequest")
local ReviveRequest = Remotes:WaitForChild("ReviveRequest")
local InteractRequest = Remotes:WaitForChild("InteractRequest")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")

local EquipItem = Remotes:WaitForChild("EquipItem")

local CombatRemotes = ReplicatedStorage:WaitForChild("CombatRemotes")
local MeleeAttack = CombatRemotes:WaitForChild("MeleeAttack")
local RangedAttack = CombatRemotes:WaitForChild("RangedAttack")

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local IsSprinting = false
local SelectedSlot = 1
local InventoryOpen = false
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
-- Hotbar Selection (1-9 keys + 0)
------------------------------------------------------------------------
local function SelectHotbarSlot(slotNumber: number)
	SelectedSlot = slotNumber
	UpdateHUD.OnClientEvent:Connect(function() end)  -- handled by UI
end

------------------------------------------------------------------------
-- Attack (mouse click)
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
			-- Determine melee or ranged based on equipped weapon
			-- For now, send melee attack
			MeleeAttack:FireServer(targetModel)
		end
	end

	task.delay(0.5, function()
		IsAttacking = false
	end)
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
		SelectHotbarSlot(keyToSlot[input.KeyCode])
	end

	-- Use item (F key)
	if input.KeyCode == Enum.KeyCode.F then
		UseItem:FireServer(SelectedSlot)
	end

	-- Drop item (G key)
	if input.KeyCode == Enum.KeyCode.G then
		DropItem:FireServer(SelectedSlot)
	end

	-- Toggle inventory (Tab / I key)
	if input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.I then
		InventoryOpen = not InventoryOpen
		-- TODO: Toggle full inventory UI visibility
	end

	-- Interact (E key) — proximity-based
	if input.KeyCode == Enum.KeyCode.E then
		-- ProximityPrompts handle this natively in Roblox
		-- This is a fallback for custom interactions
	end

	-- Equip weapon from hotbar (Q to quick-equip)
	if input.KeyCode == Enum.KeyCode.Q then
		EquipItem:FireServer(SelectedSlot)
	end

	-- Mouse click to attack
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		OnAttack()
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
	sprintButton.Parent = Player.PlayerGui:WaitForChild("PurgeHUD")

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 40)
	corner.Parent = sprintButton

	sprintButton.MouseButton1Down:Connect(StartSprint)
	sprintButton.MouseButton1Up:Connect(StopSprint)
end

print("[InputController] Initialized")
