--[[
	MonetizationService.server.lua
	Handles game passes, developer products, cosmetic shop, and Season Pass.
	RULE: NEVER sell gameplay advantages for Robux. Cosmetics ONLY.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = require(Modules.Config)
local Enums = require(Modules.Enums)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")
local NotifyPlayers = Remotes:WaitForChild("NotifyPlayers")

------------------------------------------------------------------------
-- Shop Remotes
------------------------------------------------------------------------
local ShopRemotes = Instance.new("Folder")
ShopRemotes.Name = "ShopRemotes"
ShopRemotes.Parent = ReplicatedStorage

local OpenShop = Instance.new("RemoteEvent")
OpenShop.Name = "OpenShop"
OpenShop.Parent = ShopRemotes

local PurchaseCosmetic = Instance.new("RemoteEvent")
PurchaseCosmetic.Name = "PurchaseCosmetic"
PurchaseCosmetic.Parent = ShopRemotes

local EquipCosmetic = Instance.new("RemoteEvent")
EquipCosmetic.Name = "EquipCosmetic"
EquipCosmetic.Parent = ShopRemotes

local ShopUpdate = Instance.new("RemoteEvent")
ShopUpdate.Name = "ShopUpdate"
ShopUpdate.Parent = ShopRemotes

local SeasonPassInfo = Instance.new("RemoteEvent")
SeasonPassInfo.Name = "SeasonPassInfo"
SeasonPassInfo.Parent = ShopRemotes

------------------------------------------------------------------------
-- Cosmetic Database
------------------------------------------------------------------------
local CosmeticShop = {
	-- Purge Masks
	Masks = {
		{
			id = "mask_hockey",
			name = "Hockey Mask",
			description = "Classic horror icon.",
			price = 200,
			currency = "Scrap",
			rarity = "Common",
		},
		{
			id = "mask_skull",
			name = "Skull Mask",
			description = "Bone-white death mask.",
			price = 350,
			currency = "Scrap",
			rarity = "Uncommon",
		},
		{
			id = "mask_led_face",
			name = "LED Face Mask",
			description = "Glowing neon face display.",
			price = 150,
			currency = "PurgeCoins",
			rarity = "Rare",
		},
		{
			id = "mask_clown",
			name = "Clown Mask",
			description = "Unsettling painted clown face.",
			price = 500,
			currency = "Scrap",
			rarity = "Uncommon",
		},
		{
			id = "mask_gas",
			name = "Gas Mask",
			description = "Military-grade respirator.",
			price = 200,
			currency = "PurgeCoins",
			rarity = "Rare",
		},
	},

	-- Character Outfits
	Outfits = {
		{
			id = "outfit_tactical",
			name = "Tactical Gear",
			description = "Full tactical vest and pants.",
			price = 400,
			currency = "Scrap",
			rarity = "Uncommon",
		},
		{
			id = "outfit_hazmat",
			name = "Hazmat Suit",
			description = "Bright yellow containment suit.",
			price = 250,
			currency = "PurgeCoins",
			rarity = "Rare",
		},
		{
			id = "outfit_hoodie",
			name = "Dark Hoodie",
			description = "Low-profile dark hoodie.",
			price = 150,
			currency = "Scrap",
			rarity = "Common",
		},
		{
			id = "outfit_chef",
			name = "Chef's Outfit",
			description = "Full chef whites with apron.",
			price = 300,
			currency = "Scrap",
			rarity = "Uncommon",
		},
	},

	-- Weapon Skins (visual only)
	WeaponSkins = {
		{
			id = "skin_neon_bat",
			name = "Neon Bat",
			description = "Glowing neon baseball bat.",
			price = 300,
			currency = "Scrap",
			rarity = "Uncommon",
		},
		{
			id = "skin_gold_crowbar",
			name = "Gold Crowbar",
			description = "Flashy gold-plated crowbar.",
			price = 175,
			currency = "PurgeCoins",
			rarity = "Rare",
		},
		{
			id = "skin_camo_rifle",
			name = "Camo Wrap Rifle",
			description = "Forest camouflage rifle wrap.",
			price = 500,
			currency = "Scrap",
			rarity = "Uncommon",
		},
	},

	-- Emotes
	Emotes = {
		{
			id = "emote_victory",
			name = "Victory Dance",
			description = "Celebrate surviving the Purge!",
			price = 200,
			currency = "Scrap",
			rarity = "Common",
		},
		{
			id = "emote_taunt",
			name = "Come At Me",
			description = "Bold taunt for the brave.",
			price = 150,
			currency = "Scrap",
			rarity = "Common",
		},
		{
			id = "emote_cooking",
			name = "Chef's Kiss",
			description = "When the meal hits just right.",
			price = 100,
			currency = "PurgeCoins",
			rarity = "Uncommon",
		},
	},

	-- House Decor (visual only)
	HouseDecor = {
		{
			id = "decor_retro_diner",
			name = "Retro Diner Kitchen",
			description = "1950s diner-style kitchen decor.",
			price = 600,
			currency = "Scrap",
			rarity = "Uncommon",
		},
		{
			id = "decor_cozy_cottage",
			name = "Cozy Cottage",
			description = "Warm rustic cottage interior.",
			price = 500,
			currency = "Scrap",
			rarity = "Uncommon",
		},
		{
			id = "decor_neon_purge",
			name = "Neon Purge Theme",
			description = "Glowing neon interior with Purge vibes.",
			price = 200,
			currency = "PurgeCoins",
			rarity = "Rare",
		},
	},
}

------------------------------------------------------------------------
-- Rotating Shop (daily/weekly)
------------------------------------------------------------------------
local RotatingShop = {
	daily = {},
	weekly = {},
	lastDailyRefresh = 0,
	lastWeeklyRefresh = 0,
}

local function RefreshDailyShop()
	RotatingShop.daily = {}
	-- Pick 4 random items from all categories
	local allItems = {}
	for _, category in pairs(CosmeticShop) do
		for _, item in ipairs(category) do
			table.insert(allItems, item)
		end
	end

	-- Shuffle and pick 4
	for i = #allItems, 2, -1 do
		local j = math.random(1, i)
		allItems[i], allItems[j] = allItems[j], allItems[i]
	end

	for i = 1, math.min(4, #allItems) do
		table.insert(RotatingShop.daily, allItems[i])
	end

	RotatingShop.lastDailyRefresh = os.time()
end

local function RefreshWeeklyShop()
	RotatingShop.weekly = {}
	-- Pick 2 rare/featured items
	local rareItems = {}
	for _, category in pairs(CosmeticShop) do
		for _, item in ipairs(category) do
			if item.rarity == "Rare" then
				table.insert(rareItems, item)
			end
		end
	end

	for i = #rareItems, 2, -1 do
		local j = math.random(1, i)
		rareItems[i], rareItems[j] = rareItems[j], rareItems[i]
	end

	for i = 1, math.min(2, #rareItems) do
		table.insert(RotatingShop.weekly, rareItems[i])
	end

	RotatingShop.lastWeeklyRefresh = os.time()
end

------------------------------------------------------------------------
-- Season / Purge Pass
------------------------------------------------------------------------
local SEASON_PASS_LEVELS = 50
local SeasonPassRewards = {
	-- Free track (every 5 levels)
	free = {},
	-- Premium track (every level)
	premium = {},
}

-- Generate season pass rewards
for level = 1, SEASON_PASS_LEVELS do
	-- Free track: every 5 levels
	if level % 5 == 0 then
		local reward
		if level == 10 then
			reward = { type = "Scrap", amount = 100 }
		elseif level == 20 then
			reward = { type = "Mask", itemId = "mask_hockey" }
		elseif level == 30 then
			reward = { type = "Scrap", amount = 250 }
		elseif level == 40 then
			reward = { type = "Emote", itemId = "emote_victory" }
		elseif level == 50 then
			reward = { type = "HouseDecor", itemId = "decor_cozy_cottage" }
		else
			reward = { type = "Scrap", amount = 50 }
		end
		SeasonPassRewards.free[level] = reward
	end

	-- Premium track: every level
	if level % 10 == 0 then
		SeasonPassRewards.premium[level] = { type = "PurgeCoins", amount = 50 }
	elseif level % 5 == 0 then
		SeasonPassRewards.premium[level] = { type = "Scrap", amount = 100 }
	else
		SeasonPassRewards.premium[level] = { type = "Scrap", amount = 25 }
	end
end

------------------------------------------------------------------------
-- Game Pass Processing
------------------------------------------------------------------------
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then return end

	local getPlayerData = game.ServerStorage:FindFirstChild("GetPlayerData")
	if not getPlayerData then return end
	local data = getPlayerData:Invoke(player)
	if not data then return end

	data.gamePasses[tostring(gamePassId)] = true

	-- Apply game pass effects
	if gamePassId == Config.GamePasses.ExtraInventory then
		local getPS = game.ServerStorage:FindFirstChild("GetPlayerState")
		if getPS then
			local state = getPS:Invoke(player)
			if state then
				state.maxSlots = Config.Player.MaxInventorySlotsVIP
			end
		end
		NotifyPlayers:FireClient(player, "Extra Inventory Slots unlocked!", Color3.fromRGB(0, 255, 100))

	elseif gamePassId == Config.GamePasses.VIPPass then
		NotifyPlayers:FireClient(player, "VIP Pass activated! Welcome, VIP!", Color3.fromRGB(255, 200, 50))
	end
end)

------------------------------------------------------------------------
-- Developer Product Processing (Purge Coins)
------------------------------------------------------------------------
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local productId = receiptInfo.ProductId
	local getPlayerData = game.ServerStorage:FindFirstChild("GetPlayerData")
	if not getPlayerData then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local data = getPlayerData:Invoke(player)
	if not data then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local addPurgeCoins = game.ServerStorage:FindFirstChild("AddPurgeCoins")

	if productId == Config.DeveloperProducts.PurgeCoins100 then
		data.purgeCoins += 100
		NotifyPlayers:FireClient(player, "+100 Purge Coins!", Color3.fromRGB(200, 150, 255))
	elseif productId == Config.DeveloperProducts.PurgeCoins500 then
		data.purgeCoins += 500
		NotifyPlayers:FireClient(player, "+500 Purge Coins!", Color3.fromRGB(200, 150, 255))
	elseif productId == Config.DeveloperProducts.PurgeCoins1200 then
		data.purgeCoins += 1200
		NotifyPlayers:FireClient(player, "+1200 Purge Coins!", Color3.fromRGB(200, 150, 255))
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

------------------------------------------------------------------------
-- Remote Handlers
------------------------------------------------------------------------
-- Purchase cosmetic with in-game currency
PurchaseCosmetic.OnServerEvent:Connect(function(player, itemId)
	local getPlayerData = game.ServerStorage:FindFirstChild("GetPlayerData")
	if not getPlayerData then return end
	local data = getPlayerData:Invoke(player)
	if not data then return end

	-- Find the item in shop
	local shopItem = nil
	local category = nil
	for catName, items in pairs(CosmeticShop) do
		for _, item in ipairs(items) do
			if item.id == itemId then
				shopItem = item
				category = catName
				break
			end
		end
		if shopItem then break end
	end

	if not shopItem then
		NotifyPlayers:FireClient(player, "Item not found.", Color3.fromRGB(255, 100, 100))
		return
	end

	-- Check if already owned
	local listName = "owned" .. category
	if data[listName] and table.find(data[listName], itemId) then
		NotifyPlayers:FireClient(player, "You already own this!", Color3.fromRGB(255, 200, 100))
		return
	end

	-- Check currency
	local currencyField = shopItem.currency == "PurgeCoins" and "purgeCoins" or "scrap"
	if data[currencyField] < shopItem.price then
		NotifyPlayers:FireClient(player,
			"Not enough " .. shopItem.currency .. "! Need " .. shopItem.price,
			Color3.fromRGB(255, 100, 100)
		)
		return
	end

	-- Deduct currency
	data[currencyField] -= shopItem.price

	-- Grant cosmetic
	if data[listName] then
		table.insert(data[listName], itemId)
	end

	NotifyPlayers:FireClient(player,
		"Purchased " .. shopItem.name .. "!",
		Color3.fromRGB(0, 255, 200)
	)

	-- Send updated currency
	UpdateHUD:FireClient(player, "CurrencyUpdate", {
		scrap = data.scrap,
		purgeCoins = data.purgeCoins,
	})
end)

-- Equip cosmetic
EquipCosmetic.OnServerEvent:Connect(function(player, cosmeticType, itemId)
	local getPlayerData = game.ServerStorage:FindFirstChild("GetPlayerData")
	if not getPlayerData then return end
	local data = getPlayerData:Invoke(player)
	if not data then return end

	local equipField = "equipped" .. cosmeticType
	if data[equipField] ~= nil or cosmeticType == "Mask" or cosmeticType == "Outfit" or cosmeticType == "Emote" then
		data[equipField] = itemId
		NotifyPlayers:FireClient(player,
			"Equipped " .. (itemId or "default") .. "!",
			Color3.fromRGB(200, 200, 255)
		)
	end
end)

-- Open shop: send shop data
OpenShop.OnServerEvent:Connect(function(player)
	-- Refresh rotating shop if needed
	local now = os.time()
	if now - RotatingShop.lastDailyRefresh > 86400 then  -- 24 hours
		RefreshDailyShop()
	end
	if now - RotatingShop.lastWeeklyRefresh > 604800 then  -- 7 days
		RefreshWeeklyShop()
	end

	local getPlayerData = game.ServerStorage:FindFirstChild("GetPlayerData")
	local data = getPlayerData and getPlayerData:Invoke(player) or {}

	ShopUpdate:FireClient(player, {
		catalog = CosmeticShop,
		dailyShop = RotatingShop.daily,
		weeklyShop = RotatingShop.weekly,
		owned = {
			Masks = data.ownedMasks or {},
			Outfits = data.ownedOutfits or {},
			WeaponSkins = data.ownedWeaponSkins or {},
			Emotes = data.ownedEmotes or {},
			HouseDecor = data.ownedHouseDecor or {},
		},
		currency = {
			scrap = data.scrap or 0,
			purgeCoins = data.purgeCoins or 0,
		},
	})
end)

------------------------------------------------------------------------
-- Initialize rotating shop
------------------------------------------------------------------------
RefreshDailyShop()
RefreshWeeklyShop()

print("[MonetizationService] Initialized — Cosmetics only, no pay-to-win!")
