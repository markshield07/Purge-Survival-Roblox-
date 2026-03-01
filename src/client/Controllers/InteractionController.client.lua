--[[
	InteractionController.client.lua
	Handles proximity-based interactions: loot pickup (store in backpack),
	cooking stations, generator interaction, fortification slots,
	base upgrades, and reviving teammates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)
local ItemDatabase = require(Modules.ItemDatabase)
local RecipeDatabase = require(Modules.RecipeDatabase)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PickupItem = Remotes:WaitForChild("PickupItem")
local CookRequest = Remotes:WaitForChild("CookRequest")
local FortifyRequest = Remotes:WaitForChild("FortifyRequest")
local RefuelRequest = Remotes:WaitForChild("RefuelRequest")
local ReviveRequest = Remotes:WaitForChild("ReviveRequest")
local InteractRequest = Remotes:WaitForChild("InteractRequest")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")
local UpgradeBase = Remotes:WaitForChild("UpgradeBase")

------------------------------------------------------------------------
-- Pickup Popup (brief "Store in Backpack" confirmation)
------------------------------------------------------------------------
local PickupPopup = nil

local function ShowPickupPopup(lootPart)
	if PickupPopup then PickupPopup:Destroy() end

	local itemId = lootPart:GetAttribute("ItemId")
	local quantity = lootPart:GetAttribute("Quantity") or 1
	if not itemId then return end

	local itemData = ItemDatabase.GetItem(itemId)
	if not itemData then return end

	local tierColor = Enums.TierColor[itemData.tier] or Color3.new(1, 1, 1)

	PickupPopup = Instance.new("ScreenGui")
	PickupPopup.Name = "PickupPopup"
	PickupPopup.Parent = PlayerGui

	local frame = Instance.new("Frame")
	frame.Name = "PopupFrame"
	frame.Size = UDim2.new(0, 280, 0, 100)
	frame.Position = UDim2.new(0.5, 0, 0.65, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = PickupPopup

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	-- Item name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -10, 0, 24)
	nameLabel.Position = UDim2.new(0, 5, 0, 5)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = itemData.name .. (quantity > 1 and (" x" .. quantity) or "")
	nameLabel.TextColor3 = tierColor
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = frame

	-- Tier label
	local tierLabel = Instance.new("TextLabel")
	tierLabel.Size = UDim2.new(1, -10, 0, 16)
	tierLabel.Position = UDim2.new(0, 5, 0, 28)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Text = itemData.tier .. " " .. itemData.category
	tierLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	tierLabel.TextScaled = true
	tierLabel.Font = Enum.Font.Gotham
	tierLabel.Parent = frame

	-- "Store in Backpack" button
	local storeBtn = Instance.new("TextButton")
	storeBtn.Size = UDim2.new(0.9, 0, 0, 32)
	storeBtn.Position = UDim2.new(0.05, 0, 1, -40)
	storeBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 40)
	storeBtn.Text = "Store in Backpack"
	storeBtn.TextColor3 = Color3.fromRGB(200, 255, 200)
	storeBtn.TextScaled = true
	storeBtn.Font = Enum.Font.GothamBold
	storeBtn.BorderSizePixel = 0
	storeBtn.Parent = frame

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = storeBtn

	storeBtn.MouseButton1Click:Connect(function()
		PickupItem:FireServer(lootPart)
		if PickupPopup then
			PickupPopup:Destroy()
			PickupPopup = nil
		end
	end)

	-- Auto-dismiss after 5 seconds
	task.delay(5, function()
		if PickupPopup then
			PickupPopup:Destroy()
			PickupPopup = nil
		end
	end)
end

------------------------------------------------------------------------
-- Proximity Prompt Handler
------------------------------------------------------------------------
ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	if player ~= Player then return end

	local part = prompt.Parent
	if not part then return end

	-- Loot Item Pickup — show "Store in Backpack" popup
	if CollectionService:HasTag(part, "LootItem") then
		ShowPickupPopup(part)
		return
	end

	-- Cooking Station Interaction
	if CollectionService:HasTag(part, "CookingStation") then
		local stationType = part:GetAttribute("StationType") or "Campfire"
		local built = part:GetAttribute("Built")

		if not built then
			return
		end

		CookRequest:FireServer("GetRecipes", stationType)
		OpenCookingUI(stationType, part)
		return
	end

	-- Fortification Slot (only allow on your own StarterHouse)
	if CollectionService:HasTag(part, "FortSlot") then
		local isOwnBase = false
		local parent = part.Parent
		while parent do
			if parent.Name == "StarterHouse" then
				isOwnBase = true
				break
			end
			parent = parent.Parent
		end

		if not isOwnBase then
			return
		end

		local slotName = part:GetAttribute("SlotName")
		if slotName then
			OpenFortificationUI(slotName)
		end
		return
	end

	-- Generator
	if CollectionService:HasTag(part, "Generator") then
		OpenGeneratorUI()
		return
	end

	-- Base Upgrade Workbench
	if CollectionService:HasTag(part, "UpgradeStation") then
		UpgradeBase:FireServer()
		return
	end

	-- Downed Player (Revive)
	if part.Parent and part.Parent:FindFirstChildOfClass("Humanoid") then
		local targetChar = part.Parent
		local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
		if targetPlayer and targetPlayer ~= Player then
			ReviveRequest:FireServer(targetPlayer)
		end
		return
	end
end)

------------------------------------------------------------------------
-- Cooking UI
------------------------------------------------------------------------
local CookingUI = nil

function OpenCookingUI(stationType: string, stationPart: BasePart)
	if CookingUI then CookingUI:Destroy() end

	CookingUI = Instance.new("ScreenGui")
	CookingUI.Name = "CookingUI"
	CookingUI.Parent = PlayerGui

	local frame = Instance.new("Frame")
	frame.Name = "CookingFrame"
	frame.Size = UDim2.new(0, 350, 0, 400)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Parent = CookingUI

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.Text = stationType .. " - Cooking"
	title.TextColor3 = Color3.fromRGB(255, 200, 50)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.Parent = frame

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -35, 0, 5)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = frame

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 6)
	closeCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		CookingUI:Destroy()
		CookingUI = nil
	end)

	-- Recipe list area
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Size = UDim2.new(1, -20, 1, -50)
	scrollFrame.Position = UDim2.new(0, 10, 0, 45)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.Parent = scrollFrame

	-- Listen for recipe list from server
	local connection
	connection = UpdateHUD.OnClientEvent:Connect(function(updateType, data)
		if updateType ~= "RecipeList" then return end
		connection:Disconnect()

		for _, recipe in ipairs(data) do
			local recipeBtn = Instance.new("TextButton")
			recipeBtn.Size = UDim2.new(1, 0, 0, 60)
			recipeBtn.BackgroundColor3 = recipe.canCook
				and Color3.fromRGB(40, 60, 40)
				or Color3.fromRGB(60, 40, 40)
			recipeBtn.BackgroundTransparency = 0.2
			recipeBtn.BorderSizePixel = 0
			recipeBtn.AutoButtonColor = recipe.canCook
			recipeBtn.Parent = scrollFrame

			local btnCorner2 = Instance.new("UICorner")
			btnCorner2.CornerRadius = UDim.new(0, 6)
			btnCorner2.Parent = recipeBtn

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -10, 0, 20)
			nameLabel.Position = UDim2.new(0, 5, 0, 2)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = recipe.name .. (recipe.canCook and "" or " (Missing ingredients)")
			nameLabel.TextColor3 = recipe.canCook
				and Color3.fromRGB(100, 255, 100)
				or Color3.fromRGB(255, 100, 100)
			nameLabel.TextScaled = true
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.Parent = recipeBtn

			-- Ingredients list
			local ingredientNames = {}
			for _, ingId in ipairs(recipe.ingredients) do
				local ingData = ItemDatabase.GetItem(ingId)
				table.insert(ingredientNames, ingData and ingData.name or ingId)
			end

			local ingLabel = Instance.new("TextLabel")
			ingLabel.Size = UDim2.new(1, -10, 0, 16)
			ingLabel.Position = UDim2.new(0, 5, 0, 22)
			ingLabel.BackgroundTransparency = 1
			ingLabel.Text = "Needs: " .. table.concat(ingredientNames, ", ")
			ingLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
			ingLabel.TextScaled = true
			ingLabel.TextXAlignment = Enum.TextXAlignment.Left
			ingLabel.Font = Enum.Font.Gotham
			ingLabel.Parent = recipeBtn

			local timeLabel = Instance.new("TextLabel")
			timeLabel.Size = UDim2.new(1, -10, 0, 14)
			timeLabel.Position = UDim2.new(0, 5, 0, 40)
			timeLabel.BackgroundTransparency = 1
			timeLabel.Text = "Cook time: " .. recipe.cookTime .. "s"
			timeLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
			timeLabel.TextScaled = true
			timeLabel.TextXAlignment = Enum.TextXAlignment.Left
			timeLabel.Font = Enum.Font.Gotham
			timeLabel.Parent = recipeBtn

			if recipe.canCook then
				recipeBtn.MouseButton1Click:Connect(function()
					CookRequest:FireServer("Cook", recipe.recipeId, stationPart)
					CookingUI:Destroy()
					CookingUI = nil
				end)
			end
		end

		-- Update scroll canvas
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
	end)
end

------------------------------------------------------------------------
-- Fortification UI
------------------------------------------------------------------------
function OpenFortificationUI(slotName: string)
	FortifyRequest:FireServer("install", slotName, 1)
end

------------------------------------------------------------------------
-- Generator UI
------------------------------------------------------------------------
function OpenGeneratorUI()
	RefuelRequest:FireServer(1)
	InteractRequest:FireServer("UpgradeGenerator")
end

------------------------------------------------------------------------
-- Setup Proximity Prompts for Tagged Objects
------------------------------------------------------------------------
local function SetupPrompts()
	-- Fortification slots
	for _, part in ipairs(CollectionService:GetTagged("FortSlot")) do
		if not part:FindFirstChildOfClass("ProximityPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Fortify"
			prompt.ObjectText = part:GetAttribute("SlotName") or "Slot"
			prompt.MaxActivationDistance = Config.Player.InteractRange
			prompt.HoldDuration = 0.5
			prompt.Parent = part
		end
	end

	-- Generator
	for _, part in ipairs(CollectionService:GetTagged("Generator")) do
		if not part:FindFirstChildOfClass("ProximityPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Generator"
			prompt.ObjectText = "Refuel / Upgrade"
			prompt.MaxActivationDistance = Config.Player.InteractRange
			prompt.HoldDuration = 0.3
			prompt.Parent = part
		end
	end

	-- Cooking stations
	for _, part in ipairs(CollectionService:GetTagged("CookingStation")) do
		local built = part:GetAttribute("Built")
		if built and not part:FindFirstChildOfClass("ProximityPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Cook"
			prompt.ObjectText = part:GetAttribute("StationType") or "Station"
			prompt.MaxActivationDistance = Config.Player.InteractRange
			prompt.HoldDuration = 0.5
			prompt.Parent = part
		end
	end

	-- Upgrade station
	for _, part in ipairs(CollectionService:GetTagged("UpgradeStation")) do
		if not part:FindFirstChildOfClass("ProximityPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Upgrade Base"
			prompt.ObjectText = "Expand your home"
			prompt.MaxActivationDistance = Config.Player.InteractRange
			prompt.HoldDuration = 1.0
			prompt.Parent = part
		end
	end
end

-- Run setup and listen for new objects
task.defer(SetupPrompts)

CollectionService:GetInstanceAddedSignal("FortSlot"):Connect(function()
	task.defer(SetupPrompts)
end)
CollectionService:GetInstanceAddedSignal("Generator"):Connect(function()
	task.defer(SetupPrompts)
end)
CollectionService:GetInstanceAddedSignal("CookingStation"):Connect(function()
	task.defer(SetupPrompts)
end)
CollectionService:GetInstanceAddedSignal("UpgradeStation"):Connect(function()
	task.defer(SetupPrompts)
end)

print("[InteractionController] Initialized")
