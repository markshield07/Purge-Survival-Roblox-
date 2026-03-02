--[[
	UIController.client.lua
	Client-side HUD and UI management.
	Displays: Health, Hunger, Stamina, Equipped Weapon, Backpack Inventory,
	Power meter, Purge countdown, and all game state indicators.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local ItemDatabase = require(Modules.ItemDatabase)
local RecipeDatabase = require(Modules.RecipeDatabase)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")
local GamePhaseChanged = Remotes:WaitForChild("GamePhaseChanged")
local PurgeCountdown = Remotes:WaitForChild("PurgeCountdown")
local PurgeSiren = Remotes:WaitForChild("PurgeSiren")
local PurgeStarted = Remotes:WaitForChild("PurgeStarted")
local PurgeEnded = Remotes:WaitForChild("PurgeEnded")
local DayChanged = Remotes:WaitForChild("DayChanged")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")
local PowerOutAlert = Remotes:WaitForChild("PowerOutAlert")
local EquipItem = Remotes:WaitForChild("EquipItem")
local UseItemRemote = Remotes:WaitForChild("UseItem")
local DropItemRemote = Remotes:WaitForChild("DropItem")

------------------------------------------------------------------------
-- Create Main HUD ScreenGui
------------------------------------------------------------------------
local HUD = Instance.new("ScreenGui")
HUD.Name = "PurgeHUD"
HUD.ResetOnSpawn = false
HUD.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
HUD.Parent = PlayerGui

------------------------------------------------------------------------
-- Helper: Create UI element
------------------------------------------------------------------------
local function CreateFrame(props)
	local frame = Instance.new("Frame")
	frame.Name = props.Name or "Frame"
	frame.Size = props.Size or UDim2.new(0, 100, 0, 30)
	frame.Position = props.Position or UDim2.new(0, 0, 0, 0)
	frame.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	frame.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(20, 20, 20)
	frame.BackgroundTransparency = props.BackgroundTransparency or 0.3
	frame.BorderSizePixel = 0
	frame.Parent = props.Parent or HUD

	if props.Corner then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, props.Corner)
		corner.Parent = frame
	end

	return frame
end

local function CreateLabel(props)
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "Label"
	label.Size = props.Size or UDim2.new(1, 0, 1, 0)
	label.Position = props.Position or UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = props.Text or ""
	label.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	label.TextScaled = props.TextScaled ~= false
	label.Font = props.Font or Enum.Font.GothamBold
	label.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center
	label.Parent = props.Parent
	return label
end

local function CreateBar(props)
	local container = CreateFrame({
		Name = props.Name or "Bar",
		Size = props.Size or UDim2.new(0, 200, 0, 20),
		Position = props.Position or UDim2.new(0, 0, 0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BackgroundTransparency = 0.2,
		Parent = props.Parent or HUD,
		Corner = 4,
	})

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = props.FillColor or Color3.fromRGB(0, 255, 0)
	fill.BorderSizePixel = 0
	fill.Parent = container

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	local label = CreateLabel({
		Name = "Label",
		Text = props.LabelText or "",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		Parent = container,
	})

	return container, fill, label
end

------------------------------------------------------------------------
-- Top Info Bar (Day, Phase, Time)
------------------------------------------------------------------------
local TopBar = CreateFrame({
	Name = "TopBar",
	Size = UDim2.new(0, 400, 0, 40),
	Position = UDim2.new(0.5, 0, 0, 10),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 0.5,
	Corner = 8,
})

local DayLabel = CreateLabel({
	Name = "DayLabel",
	Size = UDim2.new(0.4, 0, 1, 0),
	Text = "Day 1",
	TextColor3 = Color3.fromRGB(255, 200, 50),
	Parent = TopBar,
})

local PhaseLabel = CreateLabel({
	Name = "PhaseLabel",
	Size = UDim2.new(0.6, 0, 1, 0),
	Position = UDim2.new(0.4, 0, 0, 0),
	Text = "Lobby",
	TextColor3 = Color3.fromRGB(200, 200, 200),
	Parent = TopBar,
})

------------------------------------------------------------------------
-- Health Bar (top-left)
------------------------------------------------------------------------
local HealthContainer, HealthFill, HealthLabel = CreateBar({
	Name = "HealthBar",
	Size = UDim2.new(0, 220, 0, 22),
	Position = UDim2.new(0, 15, 0, 60),
	FillColor = Color3.fromRGB(220, 40, 40),
	LabelText = "HP: 100/100",
	Parent = HUD,
})

------------------------------------------------------------------------
-- Hunger Bar
------------------------------------------------------------------------
local HungerContainer, HungerFill, HungerLabel = CreateBar({
	Name = "HungerBar",
	Size = UDim2.new(0, 220, 0, 22),
	Position = UDim2.new(0, 15, 0, 88),
	FillColor = Color3.fromRGB(200, 150, 50),
	LabelText = "Hunger: 70%",
	Parent = HUD,
})

------------------------------------------------------------------------
-- Stamina Bar
------------------------------------------------------------------------
local StaminaContainer, StaminaFill, StaminaLabel = CreateBar({
	Name = "StaminaBar",
	Size = UDim2.new(0, 220, 0, 16),
	Position = UDim2.new(0, 15, 0, 114),
	FillColor = Color3.fromRGB(50, 150, 220),
	LabelText = "Stamina",
	Parent = HUD,
})

------------------------------------------------------------------------
-- Equipped Weapon Display (below stamina bar)
------------------------------------------------------------------------
local WeaponFrame = Instance.new("TextButton")
WeaponFrame.Name = "EquippedWeapon"
WeaponFrame.Size = UDim2.new(0, 220, 0, 36)
WeaponFrame.Position = UDim2.new(0, 15, 0, 140)
WeaponFrame.AnchorPoint = Vector2.new(0, 0)
WeaponFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
WeaponFrame.BackgroundTransparency = 0.4
WeaponFrame.BorderSizePixel = 0
WeaponFrame.Text = ""
WeaponFrame.AutoButtonColor = false
WeaponFrame.Parent = HUD

local weaponFrameCorner = Instance.new("UICorner")
weaponFrameCorner.CornerRadius = UDim.new(0, 6)
weaponFrameCorner.Parent = WeaponFrame

local WeaponIcon = CreateLabel({
	Name = "Icon",
	Size = UDim2.new(0, 28, 0, 28),
	Position = UDim2.new(0, 4, 0, 4),
	Text = "",
	TextColor3 = Color3.fromRGB(200, 200, 200),
	Font = Enum.Font.GothamBold,
	Parent = WeaponFrame,
})

local WeaponNameLabel = CreateLabel({
	Name = "WeaponName",
	Size = UDim2.new(1, -40, 0, 18),
	Position = UDim2.new(0, 36, 0, 2),
	Text = "Baseball Bat",
	TextColor3 = Color3.fromRGB(100, 200, 255),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.GothamBold,
	Parent = WeaponFrame,
})

local WeaponDmgLabel = CreateLabel({
	Name = "WeaponDmg",
	Size = UDim2.new(1, -40, 0, 14),
	Position = UDim2.new(0, 36, 0, 20),
	Text = "DMG: 18 | Melee",
	TextColor3 = Color3.fromRGB(180, 180, 180),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.Gotham,
	Parent = WeaponFrame,
})

local function UpdateEquippedWeaponDisplay(weaponId)
	if not weaponId then
		WeaponNameLabel.Text = "No weapon"
		WeaponDmgLabel.Text = "Unarmed"
		WeaponNameLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		return
	end

	local itemData = ItemDatabase.GetItem(weaponId)
	if not itemData then
		WeaponNameLabel.Text = weaponId
		WeaponDmgLabel.Text = ""
		return
	end

	local tierColor = Enums.TierColor[itemData.tier] or Color3.new(1, 1, 1)
	WeaponNameLabel.Text = itemData.name
	WeaponNameLabel.TextColor3 = tierColor

	local dmgText = "DMG: " .. (itemData.damage or "?")
	if itemData.weaponType == "Melee" then
		dmgText = dmgText .. " | Melee"
	elseif itemData.weaponType == "Ranged" then
		dmgText = dmgText .. " | Range: " .. (itemData.range or "?")
	end
	WeaponDmgLabel.Text = dmgText
end

-- Show default equipped weapon
UpdateEquippedWeaponDisplay("baseball_bat")

-- Click weapon to unequip (put back in backpack)
local currentEquippedId = "baseball_bat"
WeaponFrame.MouseButton1Click:Connect(function()
	if currentEquippedId then
		EquipItem:FireServer(0)  -- 0 = unequip
	end
end)

------------------------------------------------------------------------
-- Power Meter (bottom-right)
------------------------------------------------------------------------
local PowerFrame = CreateFrame({
	Name = "PowerFrame",
	Size = UDim2.new(0, 180, 0, 80),
	Position = UDim2.new(1, -15, 1, -100),
	AnchorPoint = Vector2.new(1, 1),
	BackgroundTransparency = 0.4,
	Corner = 8,
})

local PowerTitle = CreateLabel({
	Name = "Title",
	Size = UDim2.new(1, 0, 0, 20),
	Text = "GENERATOR",
	TextColor3 = Color3.fromRGB(0, 200, 255),
	Font = Enum.Font.GothamBold,
	Parent = PowerFrame,
})

local PowerBarContainer, PowerFill, PowerLabel = CreateBar({
	Name = "PowerBar",
	Size = UDim2.new(0.9, 0, 0, 18),
	Position = UDim2.new(0.05, 0, 0, 25),
	FillColor = Color3.fromRGB(0, 200, 255),
	LabelText = "50/100",
	Parent = PowerFrame,
})

local PowerStatus = CreateLabel({
	Name = "Status",
	Size = UDim2.new(1, 0, 0, 16),
	Position = UDim2.new(0, 0, 0, 48),
	Text = "ONLINE",
	TextColor3 = Color3.fromRGB(0, 255, 100),
	Parent = PowerFrame,
})

local PowerTier = CreateLabel({
	Name = "Tier",
	Size = UDim2.new(1, 0, 0, 14),
	Position = UDim2.new(0, 0, 0, 64),
	Text = "Tier 1 - Busted",
	TextColor3 = Color3.fromRGB(200, 200, 200),
	Font = Enum.Font.Gotham,
	Parent = PowerFrame,
})

------------------------------------------------------------------------
-- Purge Warning / Timer (center screen)
------------------------------------------------------------------------
local PurgeFrame = CreateFrame({
	Name = "PurgeFrame",
	Size = UDim2.new(0, 350, 0, 80),
	Position = UDim2.new(0.5, 0, 0.15, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(80, 0, 0),
	BackgroundTransparency = 0.3,
	Corner = 10,
})
PurgeFrame.Visible = false

local PurgeTitle = CreateLabel({
	Name = "Title",
	Size = UDim2.new(1, 0, 0.5, 0),
	Text = "PURGE NIGHT",
	TextColor3 = Color3.fromRGB(255, 0, 0),
	Font = Enum.Font.GothamBlack,
	Parent = PurgeFrame,
})

local PurgeTimer = CreateLabel({
	Name = "Timer",
	Size = UDim2.new(1, 0, 0.3, 0),
	Position = UDim2.new(0, 0, 0.5, 0),
	Text = "Wave 1/3 | Enemies: 5",
	TextColor3 = Color3.fromRGB(255, 200, 200),
	Font = Enum.Font.GothamBold,
	Parent = PurgeFrame,
})

------------------------------------------------------------------------
-- Notification System
------------------------------------------------------------------------
local NotifContainer = CreateFrame({
	Name = "Notifications",
	Size = UDim2.new(0, 400, 0, 300),
	Position = UDim2.new(0.5, 0, 0.7, 0),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
})

local NotifLayout = Instance.new("UIListLayout")
NotifLayout.SortOrder = Enum.SortOrder.LayoutOrder
NotifLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
NotifLayout.Padding = UDim.new(0, 4)
NotifLayout.Parent = NotifContainer

local notifCount = 0

local function ShowNotification(text: string, color: Color3?)
	notifCount += 1
	local notif = CreateLabel({
		Name = "Notif_" .. notifCount,
		Size = UDim2.new(1, 0, 0, 24),
		Text = text,
		TextColor3 = color or Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		Parent = NotifContainer,
	})

	-- Fade out and destroy
	task.delay(4, function()
		local tween = TweenService:Create(notif, TweenInfo.new(1, Enum.EasingStyle.Quad), {
			TextTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			notif:Destroy()
		end)
	end)
end

------------------------------------------------------------------------
-- Inventory Display (bottom-center) — 99 Nights style hotbar
------------------------------------------------------------------------
local currentMaxSlots = Config.Player.MaxInventorySlots  -- starts at 5
local currentInventory = {}  -- cached copy from server
local selectedSlot = 0       -- currently highlighted slot index (0 = none)

local InventoryFrame = CreateFrame({
	Name = "InventoryBar",
	Size = UDim2.new(0, 600, 0, 80),
	Position = UDim2.new(0.5, 0, 1, -10),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundTransparency = 0.5,
	Corner = 8,
})

-- Backpack capacity label above inventory
local BackpackLabel = CreateLabel({
	Name = "BackpackLabel",
	Size = UDim2.new(1, 0, 0, 14),
	Position = UDim2.new(0, 0, 0, 1),
	Text = "Backpack [0/" .. currentMaxSlots .. "]",
	TextColor3 = Color3.fromRGB(180, 200, 180),
	Font = Enum.Font.Gotham,
	Parent = InventoryFrame,
})

-- Controls hint label
local ControlsHint = CreateLabel({
	Name = "ControlsHint",
	Size = UDim2.new(1, 0, 0, 12),
	Position = UDim2.new(0, 0, 1, 1),
	Text = "[1-5] Select  |  [Click] Use  |  [Backspace] Drop",
	TextColor3 = Color3.fromRGB(140, 140, 140),
	Font = Enum.Font.Gotham,
	Parent = InventoryFrame,
})

-- Selected item tooltip (shows above hotbar when slot is selected)
local ItemTooltip = CreateFrame({
	Name = "ItemTooltip",
	Size = UDim2.new(0, 200, 0, 24),
	Position = UDim2.new(0.5, 0, 1, -100),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = Color3.fromRGB(20, 20, 25),
	BackgroundTransparency = 0.2,
	Corner = 6,
})
ItemTooltip.Visible = false

local TooltipLabel = CreateLabel({
	Name = "TooltipText",
	Size = UDim2.new(1, -8, 1, 0),
	Position = UDim2.new(0, 4, 0, 0),
	Text = "",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold,
	Parent = ItemTooltip,
})

local InventorySlotContainer = CreateFrame({
	Name = "SlotContainer",
	Size = UDim2.new(1, -8, 0, 56),
	Position = UDim2.new(0, 4, 0, 17),
	BackgroundTransparency = 1,
	Parent = InventoryFrame,
})

local InventoryLayout = Instance.new("UIListLayout")
InventoryLayout.FillDirection = Enum.FillDirection.Horizontal
InventoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
InventoryLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
InventoryLayout.Padding = UDim.new(0, 3)
InventoryLayout.Parent = InventorySlotContainer

local InventorySlots = {}

------------------------------------------------------------------------
-- Slot selection / deselection (99 Nights style)
------------------------------------------------------------------------
local function DeselectSlot()
	if selectedSlot > 0 and InventorySlots[selectedSlot] then
		local slotData = InventorySlots[selectedSlot]
		slotData.stroke.Color = Color3.fromRGB(60, 60, 60)
		slotData.stroke.Thickness = 2
		slotData.stroke.Transparency = 0.6
		slotData.numberLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
	end
	selectedSlot = 0
	ItemTooltip.Visible = false
end

local function SelectSlot(index)
	if index == selectedSlot then return end -- already selected

	-- Deselect previous
	DeselectSlot()

	if index < 1 or index > currentMaxSlots then return end

	selectedSlot = index

	-- Highlight selected slot
	local slotData = InventorySlots[index]
	if slotData then
		slotData.stroke.Color = Color3.fromRGB(255, 220, 80)
		slotData.stroke.Thickness = 3
		slotData.stroke.Transparency = 0
		slotData.numberLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	end

	-- Show tooltip with item name
	local item = currentInventory[index]
	if item then
		local itemData = ItemDatabase.GetItem(item.itemId)
		if itemData then
			local tierColor = Enums.TierColor[itemData.tier] or Color3.new(1, 1, 1)
			TooltipLabel.Text = itemData.name
			TooltipLabel.TextColor3 = tierColor
			ItemTooltip.Visible = true

			-- Auto-equip if it's a weapon
			if itemData.category == Enums.ItemCategory.Weapon then
				EquipItem:FireServer(index)
			end
		end
	else
		ItemTooltip.Visible = false
	end
end

------------------------------------------------------------------------
-- Create inventory slots (clickable, with number key labels)
------------------------------------------------------------------------
local function CreateInventorySlot(index)
	local slotWidth = math.min(55, math.floor(580 / currentMaxSlots) - 4)

	local slot = Instance.new("TextButton")
	slot.Name = "Slot_" .. index
	slot.Size = UDim2.new(0, slotWidth, 0, 54)
	slot.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	slot.BackgroundTransparency = 0.3
	slot.Text = ""
	slot.AutoButtonColor = false
	slot.BorderSizePixel = 0
	slot.Parent = InventorySlotContainer

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = slot

	-- Selection border stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 60)
	stroke.Thickness = 2
	stroke.Transparency = 0.6
	stroke.Parent = slot

	-- Slot number label (top-left corner)
	local numberLabel = CreateLabel({
		Name = "SlotNumber",
		Size = UDim2.new(0, 14, 0, 14),
		Position = UDim2.new(0, 2, 0, 1),
		Text = index <= 10 and tostring(index % 10) or "",
		TextColor3 = Color3.fromRGB(120, 120, 120),
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		Parent = slot,
	})

	local nameLabel = CreateLabel({
		Name = "ItemName",
		Size = UDim2.new(1, -2, 0.5, 0),
		Position = UDim2.new(0, 1, 0, 14),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.Gotham,
		Parent = slot,
	})

	local countLabel = CreateLabel({
		Name = "Count",
		Size = UDim2.new(1, -2, 0.25, 0),
		Position = UDim2.new(0, 1, 0.75, 0),
		Text = "",
		TextColor3 = Color3.fromRGB(200, 200, 200),
		Font = Enum.Font.Gotham,
		Parent = slot,
	})

	-- Click handler: select this slot
	slot.MouseButton1Click:Connect(function()
		if selectedSlot == index then
			-- Double-click / re-click: use the item
			local item = currentInventory[index]
			if item then
				local itemData = ItemDatabase.GetItem(item.itemId)
				if itemData and itemData.category ~= Enums.ItemCategory.Weapon then
					-- Use/eat non-weapon items on click
					UseItemRemote:FireServer(index)
				end
			end
		else
			SelectSlot(index)
		end
	end)

	return {
		frame = slot,
		nameLabel = nameLabel,
		countLabel = countLabel,
		numberLabel = numberLabel,
		stroke = stroke,
	}
end

local function RebuildInventorySlots(maxSlots)
	DeselectSlot()
	-- Clear existing slots
	for _, slotData in ipairs(InventorySlots) do
		slotData.frame:Destroy()
	end
	InventorySlots = {}

	currentMaxSlots = maxSlots

	for i = 1, maxSlots do
		InventorySlots[i] = CreateInventorySlot(i)
	end

	BackpackLabel.Text = "Backpack [0/" .. maxSlots .. "]"
end

-- Initialize with default slot count
RebuildInventorySlots(currentMaxSlots)

local function UpdateInventoryDisplay(inventory)
	currentInventory = inventory or {}
	local filledCount = #currentInventory
	BackpackLabel.Text = "Backpack [" .. filledCount .. "/" .. currentMaxSlots .. "]"

	-- Color the label based on capacity
	if filledCount >= currentMaxSlots then
		BackpackLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	elseif filledCount >= currentMaxSlots * 0.8 then
		BackpackLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
	else
		BackpackLabel.TextColor3 = Color3.fromRGB(180, 200, 180)
	end

	for i, slot in ipairs(InventorySlots) do
		local item = currentInventory[i]
		if item then
			local itemData = ItemDatabase.GetItem(item.itemId)
			local charLimit = currentMaxSlots > 10 and 5 or 6
			slot.nameLabel.Text = itemData and string.sub(itemData.name, 1, charLimit) or "?"
			slot.countLabel.Text = item.quantity > 1 and ("x" .. item.quantity) or ""

			local tierColor = itemData and Enums.TierColor[itemData.tier] or Color3.new(1, 1, 1)
			slot.nameLabel.TextColor3 = tierColor
			slot.frame.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
		else
			slot.nameLabel.Text = ""
			slot.countLabel.Text = ""
			slot.frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		end
	end

	-- Update tooltip if selected slot changed
	if selectedSlot > 0 then
		local item = currentInventory[selectedSlot]
		if item then
			local itemData = ItemDatabase.GetItem(item.itemId)
			if itemData then
				TooltipLabel.Text = itemData.name
				TooltipLabel.TextColor3 = Enums.TierColor[itemData.tier] or Color3.new(1, 1, 1)
				ItemTooltip.Visible = true
			end
		else
			ItemTooltip.Visible = false
		end
	end
end

------------------------------------------------------------------------
-- Expose inventory state for InputController via BindableFunction
------------------------------------------------------------------------
local GetHotbarState = Instance.new("BindableFunction")
GetHotbarState.Name = "GetHotbarState"
GetHotbarState.Parent = HUD
GetHotbarState.OnInvoke = function(action)
	if action == "GetSelectedSlot" then
		return selectedSlot
	elseif action == "GetInventory" then
		return currentInventory
	elseif action == "GetMaxSlots" then
		return currentMaxSlots
	end
	return nil
end

-- BindableEvent for InputController to trigger slot selection
local HotbarAction = Instance.new("BindableEvent")
HotbarAction.Name = "HotbarAction"
HotbarAction.Parent = HUD
HotbarAction.Event:Connect(function(action, value)
	if action == "SelectSlot" then
		SelectSlot(value)
	elseif action == "DeselectSlot" then
		DeselectSlot()
	elseif action == "UseSelected" then
		if selectedSlot > 0 and currentInventory[selectedSlot] then
			UseItemRemote:FireServer(selectedSlot)
		end
	elseif action == "DropSelected" then
		if selectedSlot > 0 and currentInventory[selectedSlot] then
			local idx = selectedSlot
			DeselectSlot()
			DropItemRemote:FireServer(idx)
		end
	elseif action == "EquipSelected" then
		if selectedSlot > 0 and currentInventory[selectedSlot] then
			EquipItem:FireServer(selectedSlot)
		end
	end
end)

------------------------------------------------------------------------
-- Currency Display (top-right)
------------------------------------------------------------------------
local CurrencyFrame = CreateFrame({
	Name = "Currency",
	Size = UDim2.new(0, 160, 0, 50),
	Position = UDim2.new(1, -15, 0, 10),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundTransparency = 0.5,
	Corner = 8,
})

local ScrapLabel = CreateLabel({
	Name = "Scrap",
	Size = UDim2.new(1, -10, 0.5, 0),
	Position = UDim2.new(0, 5, 0, 0),
	Text = "Scrap: 0",
	TextColor3 = Color3.fromRGB(200, 200, 200),
	TextXAlignment = Enum.TextXAlignment.Right,
	Font = Enum.Font.GothamBold,
	Parent = CurrencyFrame,
})

local PurgeCoinsLabel = CreateLabel({
	Name = "PurgeCoins",
	Size = UDim2.new(1, -10, 0.5, 0),
	Position = UDim2.new(0, 5, 0.5, 0),
	Text = "Coins: 0",
	TextColor3 = Color3.fromRGB(200, 150, 255),
	TextXAlignment = Enum.TextXAlignment.Right,
	Font = Enum.Font.GothamBold,
	Parent = CurrencyFrame,
})

------------------------------------------------------------------------
-- Buff Display
------------------------------------------------------------------------
local BuffFrame = CreateFrame({
	Name = "Buffs",
	Size = UDim2.new(0, 200, 0, 25),
	Position = UDim2.new(0, 15, 0, 182),
	BackgroundTransparency = 1,
})

local BuffLabel = CreateLabel({
	Name = "ActiveBuffs",
	Size = UDim2.new(1, 0, 1, 0),
	Text = "",
	TextColor3 = Color3.fromRGB(100, 255, 200),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.Gotham,
	Parent = BuffFrame,
})

------------------------------------------------------------------------
-- Remote Event Handlers
------------------------------------------------------------------------
UpdateHUD.OnClientEvent:Connect(function(updateType, data)
	if updateType == "HungerUpdate" then
		local pct = data.hunger / Config.Hunger.MaxHunger
		HungerFill.Size = UDim2.new(math.max(0, pct), 0, 1, 0)
		HungerLabel.Text = string.format("Hunger: %d%%", math.floor(data.hunger))

		-- Color by level
		if data.level == Enums.HungerLevel.Full then
			HungerFill.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
		elseif data.level == Enums.HungerLevel.Satisfied then
			HungerFill.BackgroundColor3 = Color3.fromRGB(200, 180, 50)
		elseif data.level == Enums.HungerLevel.Hungry then
			HungerFill.BackgroundColor3 = Color3.fromRGB(255, 150, 0)
		else
			HungerFill.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
		end

		-- Health update
		local healthPct = data.health / Config.Player.MaxHealth
		HealthFill.Size = UDim2.new(math.max(0, healthPct), 0, 1, 0)
		HealthLabel.Text = string.format("HP: %d/%d", math.floor(data.health), Config.Player.MaxHealth)

		-- Stamina
		local stamPct = (data.stamina or 100) / 100
		StaminaFill.Size = UDim2.new(math.max(0, stamPct), 0, 1, 0)

	elseif updateType == "GeneratorUpdate" then
		local fuelPct = data.fuel / data.maxFuel
		PowerFill.Size = UDim2.new(math.max(0, fuelPct), 0, 1, 0)
		PowerLabel.Text = string.format("%d/%d", math.floor(data.fuel), data.maxFuel)

		if data.isPowered then
			PowerStatus.Text = "ONLINE"
			PowerStatus.TextColor3 = Color3.fromRGB(0, 255, 100)
			PowerFill.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
		else
			PowerStatus.Text = "OFFLINE"
			PowerStatus.TextColor3 = Color3.fromRGB(255, 0, 0)
			PowerFill.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
		end

		local tierNames = { "Busted", "Repaired", "Heavy Duty", "Solar Backup" }
		PowerTier.Text = "Tier " .. data.tier .. " - " .. (tierNames[data.tier] or "?")

	elseif updateType == "PowerStatus" then
		if data then
			PowerStatus.Text = "ONLINE"
			PowerStatus.TextColor3 = Color3.fromRGB(0, 255, 100)
		else
			PowerStatus.Text = "OFFLINE - DANGER"
			PowerStatus.TextColor3 = Color3.fromRGB(255, 0, 0)
		end

	elseif updateType == "InventoryUpdate" then
		UpdateInventoryDisplay(data)

	elseif updateType == "EquippedWeapon" then
		currentEquippedId = data
		UpdateEquippedWeaponDisplay(data)

	elseif updateType == "BackpackUpgrade" then
		-- data = new max slots
		RebuildInventorySlots(data)
		ShowNotification("Backpack upgraded! " .. data .. " slots now available.", Color3.fromRGB(50, 255, 100))

	elseif updateType == "BaseLevel" then
		local levelNames = { "Starter", "Expanded", "Reinforced", "Fortified" }
		ShowNotification("Base Level: " .. (levelNames[data] or data), Color3.fromRGB(0, 255, 100))

	elseif updateType == "PurgeStatus" then
		if data.purgeActive then
			PurgeFrame.Visible = true
			PurgeTimer.Text = string.format("Wave %d/%d | Enemies: %d",
				data.wave, data.totalWaves, data.enemiesAlive)
		end

	elseif updateType == "HealthUpdate" then
		-- Immediate health update from DamagePlayer
		local healthPct = data.health / Config.Player.MaxHealth
		HealthFill.Size = UDim2.new(math.max(0, healthPct), 0, 1, 0)
		HealthLabel.Text = string.format("HP: %d/%d", math.floor(data.health), Config.Player.MaxHealth)

		-- Color the bar based on health
		if healthPct > 0.5 then
			HealthFill.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
		elseif healthPct > 0.25 then
			HealthFill.BackgroundColor3 = Color3.fromRGB(255, 180, 0)
		else
			HealthFill.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
		end

	elseif updateType == "DamageTaken" then
		-- Red flash effect
		local flashFrame = Instance.new("Frame")
		flashFrame.Size = UDim2.new(1, 0, 1, 0)
		flashFrame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
		flashFrame.BackgroundTransparency = 0.7
		flashFrame.BorderSizePixel = 0
		flashFrame.ZIndex = 100
		flashFrame.Parent = HUD

		TweenService:Create(flashFrame, TweenInfo.new(0.3), {
			BackgroundTransparency = 1,
		}):Play()

		task.delay(0.4, function()
			flashFrame:Destroy()
		end)

	elseif updateType == "GeneratorFlicker" then
		if data then
			HUD.BackgroundTransparency = 0.8
		else
			HUD.BackgroundTransparency = 1
		end

	elseif updateType == "CurrencyUpdate" then
		ScrapLabel.Text = "Scrap: " .. tostring(data.scrap or 0)
		PurgeCoinsLabel.Text = "Coins: " .. tostring(data.purgeCoins or 0)

	elseif updateType == "BuffApplied" then
		BuffLabel.Text = "Buff: " .. (data.type or "Unknown")

	elseif updateType == "BuffExpired" then
		BuffLabel.Text = ""

	elseif updateType == "PlayerDataLoaded" then
		ScrapLabel.Text = "Scrap: " .. tostring(data.scrap or 0)
		PurgeCoinsLabel.Text = "Coins: " .. tostring(data.purgeCoins or 0)

	elseif updateType == "CookingStarted" then
		ShowNotification("Cooking: " .. data.recipeName .. " (" .. data.cookTime .. "s)", Color3.fromRGB(255, 200, 50))

	elseif updateType == "CookingComplete" then
		ShowNotification(data .. " is ready!", Color3.fromRGB(100, 255, 100))
	end
end)

-- Game phase changes
GamePhaseChanged.OnClientEvent:Connect(function(phase)
	PhaseLabel.Text = phase

	if phase == Enums.GamePhase.Purge then
		PhaseLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
		PurgeFrame.Visible = true
	elseif phase == Enums.GamePhase.PrePurge then
		PhaseLabel.TextColor3 = Color3.fromRGB(255, 150, 0)
	elseif phase == Enums.GamePhase.PostPurge then
		PhaseLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
		PurgeFrame.Visible = false
	else
		PhaseLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		PurgeFrame.Visible = false
	end
end)

-- Day changed
DayChanged.OnClientEvent:Connect(function(day)
	DayLabel.Text = "Day " .. day
end)

-- Purge countdown
PurgeCountdown.OnClientEvent:Connect(function(seconds)
	PurgeFrame.Visible = true
	PurgeTitle.Text = "PURGE IN " .. seconds
	PurgeTimer.Text = "GET TO YOUR POSITIONS!"
end)

-- Purge started
PurgeStarted.OnClientEvent:Connect(function(purgeNumber, difficulty)
	PurgeFrame.Visible = true
	if purgeNumber > 0 then
		PurgeTitle.Text = "PURGE NIGHT #" .. purgeNumber
	else
		PurgeTitle.Text = "POWER OUT ATTACK"
	end
end)

-- Purge ended
PurgeEnded.OnClientEvent:Connect(function(purgeNumber, scrapReward)
	PurgeFrame.Visible = false
	ShowNotification(
		"SURVIVED! +" .. scrapReward .. " Scrap",
		Color3.fromRGB(0, 255, 100)
	)
end)

-- Power out alert
PowerOutAlert.OnClientEvent:Connect(function()
	ShowNotification("POWER OUT! ENEMIES INCOMING!", Color3.fromRGB(255, 50, 0))
end)

-- General notifications
NotifyPlayers.OnClientEvent:Connect(function(text, color)
	ShowNotification(text, color)
end)

-- Purge siren
PurgeSiren.OnClientEvent:Connect(function()
	ShowNotification("EMERGENCY BROADCAST: PURGE IS IMMINENT", Color3.fromRGB(255, 0, 0))
end)

------------------------------------------------------------------------
-- Request initial state from server on join
------------------------------------------------------------------------
local RequestInventory = Remotes:WaitForChild("RequestInventory")
task.defer(function()
	local data = RequestInventory:InvokeServer()
	if data and type(data) == "table" then
		if data.inventory then
			UpdateInventoryDisplay(data.inventory)
		end
		if data.maxSlots and data.maxSlots ~= currentMaxSlots then
			RebuildInventorySlots(data.maxSlots)
			if data.inventory then
				UpdateInventoryDisplay(data.inventory)
			end
		end
		if data.equippedWeapon then
			currentEquippedId = data.equippedWeapon
			UpdateEquippedWeaponDisplay(data.equippedWeapon)
		end
	end
end)

------------------------------------------------------------------------
-- Campfire Fuel Display (top-center)
------------------------------------------------------------------------
local CampfireFrame = CreateFrame({
	Name = "CampfireFrame",
	Size = UDim2.new(0, 200, 0, 50),
	Position = UDim2.new(0.5, 0, 0, 10),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.fromRGB(40, 20, 0),
	BackgroundTransparency = 0.3,
	Corner = 8,
})

local campfireIcon = CreateLabel({
	Name = "CampfireIcon",
	Text = "🔥",
	Size = UDim2.new(0, 40, 1, 0),
	Position = UDim2.new(0, 5, 0, 0),
	Parent = CampfireFrame,
	TextColor3 = Color3.fromRGB(255, 150, 30),
	TextScaled = true,
})

local campfireFuelBar = Instance.new("Frame")
campfireFuelBar.Name = "FuelBar"
campfireFuelBar.Size = UDim2.new(0.6, 0, 0.4, 0)
campfireFuelBar.Position = UDim2.new(0.25, 0, 0.15, 0)
campfireFuelBar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
campfireFuelBar.BorderSizePixel = 0
campfireFuelBar.Parent = CampfireFrame

local campfireFuelFill = Instance.new("Frame")
campfireFuelFill.Name = "Fill"
campfireFuelFill.Size = UDim2.new(0.6, 0, 1, 0)
campfireFuelFill.BackgroundColor3 = Color3.fromRGB(255, 150, 30)
campfireFuelFill.BorderSizePixel = 0
campfireFuelFill.Parent = campfireFuelBar

local campfireTierLabel = CreateLabel({
	Name = "TierLabel",
	Text = "Flickering Campfire",
	Size = UDim2.new(0.75, 0, 0.4, 0),
	Position = UDim2.new(0.25, 0, 0.55, 0),
	Parent = CampfireFrame,
	TextColor3 = Color3.fromRGB(255, 200, 100),
	TextSize = 11,
})

------------------------------------------------------------------------
-- Stalker Warning Indicator
------------------------------------------------------------------------
local StalkerFrame = CreateFrame({
	Name = "StalkerWarning",
	Size = UDim2.new(0, 300, 0, 40),
	Position = UDim2.new(0.5, 0, 0, 65),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.fromRGB(60, 0, 0),
	BackgroundTransparency = 0.4,
	Corner = 6,
})
StalkerFrame.Visible = false

local stalkerLabel = CreateLabel({
	Name = "StalkerLabel",
	Text = "THE STALKER IS HUNTING...",
	Size = UDim2.new(1, -10, 1, 0),
	Position = UDim2.new(0, 5, 0, 0),
	Parent = StalkerFrame,
	TextColor3 = Color3.fromRGB(255, 50, 50),
	TextSize = 14,
	Font = Enum.Font.GothamBold,
})

------------------------------------------------------------------------
-- Rescue Progress Display (top-right)
------------------------------------------------------------------------
local RescueFrame = CreateFrame({
	Name = "RescueFrame",
	Size = UDim2.new(0, 180, 0, 35),
	Position = UDim2.new(1, -10, 0, 10),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = Color3.fromRGB(0, 30, 50),
	BackgroundTransparency = 0.3,
	Corner = 6,
})

local rescueLabel = CreateLabel({
	Name = "RescueLabel",
	Text = "Missing: 0/4 rescued",
	Size = UDim2.new(1, -10, 1, 0),
	Position = UDim2.new(0, 5, 0, 0),
	Parent = RescueFrame,
	TextColor3 = Color3.fromRGB(100, 200, 255),
	TextSize = 12,
})

------------------------------------------------------------------------
-- Night Event Display
------------------------------------------------------------------------
local EventFrame = CreateFrame({
	Name = "EventFrame",
	Size = UDim2.new(0, 300, 0, 35),
	Position = UDim2.new(0.5, 0, 0, 110),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.fromRGB(50, 0, 50),
	BackgroundTransparency = 0.4,
	Corner = 6,
})
EventFrame.Visible = false

local eventLabel = CreateLabel({
	Name = "EventLabel",
	Text = "",
	Size = UDim2.new(1, -10, 1, 0),
	Position = UDim2.new(0, 5, 0, 0),
	Parent = EventFrame,
	TextColor3 = Color3.fromRGB(255, 200, 100),
	TextSize = 13,
	Font = Enum.Font.GothamBold,
})

------------------------------------------------------------------------
-- Connect New Remotes
------------------------------------------------------------------------

-- Campfire updates
local CampfireUpdateRemote = Remotes:FindFirstChild("CampfireUpdate")
if CampfireUpdateRemote then
	CampfireUpdateRemote.OnClientEvent:Connect(function(eventType, state)
		if type(state) == "table" then
			-- Update fuel bar
			local fuelPercent = (state.fuel or 0) / math.max(1, state.maxFuel or 100)
			campfireFuelFill.Size = UDim2.new(math.clamp(fuelPercent, 0, 1), 0, 1, 0)

			-- Color based on fuel level
			if fuelPercent > 0.5 then
				campfireFuelFill.BackgroundColor3 = Color3.fromRGB(255, 150, 30)
			elseif fuelPercent > 0.2 then
				campfireFuelFill.BackgroundColor3 = Color3.fromRGB(255, 100, 0)
			else
				campfireFuelFill.BackgroundColor3 = Color3.fromRGB(255, 30, 0)
			end

			-- Update tier name
			local tierData = Config.Campfire.Tiers[state.tier or 1]
			if tierData then
				campfireTierLabel.Text = tierData.name
			end
		end

		if eventType == "Extinguished" then
			CampfireFrame.BackgroundColor3 = Color3.fromRGB(50, 10, 10)
			campfireIcon.Text = "💀"
			ShowNotification("THE CAMPFIRE HAS GONE OUT!", Color3.fromRGB(255, 0, 0))
		elseif eventType == "Relit" then
			CampfireFrame.BackgroundColor3 = Color3.fromRGB(40, 20, 0)
			campfireIcon.Text = "🔥"
		end
	end)
end

-- Stalker alerts
local StalkerAlertRemote = Remotes:FindFirstChild("StalkerAlert")
if StalkerAlertRemote then
	StalkerAlertRemote.OnClientEvent:Connect(function(eventType, data)
		if eventType == "Spawned" then
			StalkerFrame.Visible = true
			if data then  -- data = isHungry
				stalkerLabel.Text = "THE STALKER IS HUNGRY TONIGHT..."
				stalkerLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
				StalkerFrame.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
			else
				stalkerLabel.Text = "The Stalker is hunting..."
				stalkerLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
				StalkerFrame.BackgroundColor3 = Color3.fromRGB(60, 0, 0)
			end
		elseif eventType == "Despawned" or eventType == "Fleeing" then
			StalkerFrame.Visible = false
		elseif eventType == "Stunned" then
			stalkerLabel.Text = "The Stalker is stunned! (" .. math.ceil(data or 3) .. "s)"
			stalkerLabel.TextColor3 = Color3.fromRGB(200, 200, 100)
		elseif eventType == "Attack" then
			ShowNotification("The Stalker attacks!", Color3.fromRGB(255, 0, 0))
		end
	end)
end

-- Rescue updates
local RescueUpdateRemote = Remotes:FindFirstChild("RescueUpdate")
if RescueUpdateRemote then
	RescueUpdateRemote.OnClientEvent:Connect(function(eventType, data)
		if eventType == "Rescued" and type(data) == "table" then
			rescueLabel.Text = "Missing: " .. data.rescued .. "/" .. data.totalMissing .. " rescued"
			if data.rescued >= data.totalMissing then
				rescueLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
				rescueLabel.Text = "All rescued! +" .. data.dayMultiplierBonus .. " day multiplier"
			end
		end
	end)
end

-- Night event
local NightEventStartedRemote = Remotes:FindFirstChild("NightEventStarted")
local NightEventEndedRemote = Remotes:FindFirstChild("NightEventEnded")
if NightEventStartedRemote then
	NightEventStartedRemote.OnClientEvent:Connect(function(eventType)
		EventFrame.Visible = true
		local eventNames = {
			CultistRaid = "CULTIST RAID",
			MeteorShower = "METEOR SHOWER",
			FrogInvasion = "FROG INVASION",
			AlienVisit = "ALIEN VISIT",
			BloodMoon = "BLOOD MOON",
			ThunderStorm = "THUNDERSTORM",
		}
		eventLabel.Text = eventNames[eventType] or eventType
	end)
end
if NightEventEndedRemote then
	NightEventEndedRemote.OnClientEvent:Connect(function()
		EventFrame.Visible = false
	end)
end

print("[UIController] HUD Initialized")
