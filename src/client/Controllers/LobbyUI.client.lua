--[[
	LobbyUI.client.lua
	Lobby screen: player list, ready button, game mode selection, countdown.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Enums = require(Modules.Enums)

local LobbyRemotes = ReplicatedStorage:WaitForChild("LobbyRemotes")
local PlayerReady = LobbyRemotes:WaitForChild("PlayerReady")
local PlayerUnready = LobbyRemotes:WaitForChild("PlayerUnready")
local LobbyUpdate = LobbyRemotes:WaitForChild("LobbyUpdate")
local SelectGameMode = LobbyRemotes:WaitForChild("SelectGameMode")

------------------------------------------------------------------------
-- Create Lobby ScreenGui
------------------------------------------------------------------------
local LobbyGui = Instance.new("ScreenGui")
LobbyGui.Name = "LobbyUI"
LobbyGui.ResetOnSpawn = false
LobbyGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
LobbyGui.Parent = PlayerGui

-- Main frame
local MainFrame = Instance.new("Frame")
MainFrame.Name = "LobbyFrame"
MainFrame.Size = UDim2.new(0, 500, 0, 450)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 12, 18)
MainFrame.BackgroundTransparency = 0.05
MainFrame.BorderSizePixel = 0
MainFrame.Parent = LobbyGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = MainFrame

-- Title
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 60)
Title.BackgroundTransparency = 1
Title.Text = "THE PURGE: SUBURBAN SURVIVAL"
Title.TextColor3 = Color3.fromRGB(255, 50, 50)
Title.TextScaled = true
Title.Font = Enum.Font.GothamBlack
Title.Parent = MainFrame

-- Subtitle
local Subtitle = Instance.new("TextLabel")
Subtitle.Size = UDim2.new(1, 0, 0, 25)
Subtitle.Position = UDim2.new(0, 0, 0, 55)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "Survive the night. Fortify your home. Work together."
Subtitle.TextColor3 = Color3.fromRGB(180, 180, 180)
Subtitle.TextScaled = true
Subtitle.Font = Enum.Font.Gotham
Subtitle.Parent = MainFrame

-- Player list
local PlayerList = Instance.new("ScrollingFrame")
PlayerList.Name = "PlayerList"
PlayerList.Size = UDim2.new(0.85, 0, 0, 180)
PlayerList.Position = UDim2.new(0.075, 0, 0, 90)
PlayerList.BackgroundColor3 = Color3.fromRGB(25, 22, 30)
PlayerList.BackgroundTransparency = 0.3
PlayerList.BorderSizePixel = 0
PlayerList.ScrollBarThickness = 4
PlayerList.Parent = MainFrame

local listCorner = Instance.new("UICorner")
listCorner.CornerRadius = UDim.new(0, 8)
listCorner.Parent = PlayerList

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 3)
listLayout.Parent = PlayerList

-- Game mode selector
local ModeFrame = Instance.new("Frame")
ModeFrame.Size = UDim2.new(0.85, 0, 0, 35)
ModeFrame.Position = UDim2.new(0.075, 0, 0, 280)
ModeFrame.BackgroundTransparency = 1
ModeFrame.Parent = MainFrame

local ModeLabel = Instance.new("TextLabel")
ModeLabel.Size = UDim2.new(0.3, 0, 1, 0)
ModeLabel.BackgroundTransparency = 1
ModeLabel.Text = "Mode:"
ModeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
ModeLabel.TextScaled = true
ModeLabel.TextXAlignment = Enum.TextXAlignment.Left
ModeLabel.Font = Enum.Font.GothamBold
ModeLabel.Parent = ModeFrame

local modes = { "Endless", "SurviveX", "Escape" }
local modeButtons = {}

for i, mode in ipairs(modes) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0.2, 0, 1, 0)
	btn.Position = UDim2.new(0.3 + (i - 1) * 0.22, 0, 0, 0)
	btn.BackgroundColor3 = Color3.fromRGB(50, 40, 60)
	btn.Text = mode
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextScaled = true
	btn.Font = Enum.Font.GothamBold
	btn.BorderSizePixel = 0
	btn.Parent = ModeFrame

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = btn

	btn.MouseButton1Click:Connect(function()
		SelectGameMode:FireServer(mode)
	end)

	modeButtons[mode] = btn
end

-- Ready button
local ReadyButton = Instance.new("TextButton")
ReadyButton.Name = "ReadyButton"
ReadyButton.Size = UDim2.new(0.5, 0, 0, 50)
ReadyButton.Position = UDim2.new(0.25, 0, 0, 330)
ReadyButton.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
ReadyButton.Text = "READY UP"
ReadyButton.TextColor3 = Color3.new(1, 1, 1)
ReadyButton.TextScaled = true
ReadyButton.Font = Enum.Font.GothamBlack
ReadyButton.BorderSizePixel = 0
ReadyButton.Parent = MainFrame

local readyCorner = Instance.new("UICorner")
readyCorner.CornerRadius = UDim.new(0, 10)
readyCorner.Parent = ReadyButton

local isReady = false

ReadyButton.MouseButton1Click:Connect(function()
	isReady = not isReady
	if isReady then
		PlayerReady:FireServer()
		ReadyButton.Text = "UNREADY"
		ReadyButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	else
		PlayerUnready:FireServer()
		ReadyButton.Text = "READY UP"
		ReadyButton.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
	end
end)

-- Countdown label
local CountdownLabel = Instance.new("TextLabel")
CountdownLabel.Size = UDim2.new(1, 0, 0, 30)
CountdownLabel.Position = UDim2.new(0, 0, 0, 390)
CountdownLabel.BackgroundTransparency = 1
CountdownLabel.Text = ""
CountdownLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
CountdownLabel.TextScaled = true
CountdownLabel.Font = Enum.Font.GothamBold
CountdownLabel.Parent = MainFrame

------------------------------------------------------------------------
-- Update Lobby Display
------------------------------------------------------------------------
local function UpdateLobbyDisplay(lobbyInfo)
	-- Clear player list
	for _, child in ipairs(PlayerList:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	-- Add players
	for i, pData in ipairs(lobbyInfo.players) do
		local entry = Instance.new("Frame")
		entry.Size = UDim2.new(1, -10, 0, 32)
		entry.BackgroundColor3 = pData.ready
			and Color3.fromRGB(30, 60, 30)
			or Color3.fromRGB(50, 40, 40)
		entry.BackgroundTransparency = 0.3
		entry.BorderSizePixel = 0
		entry.Parent = PlayerList

		local entryCorner = Instance.new("UICorner")
		entryCorner.CornerRadius = UDim.new(0, 4)
		entryCorner.Parent = entry

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.7, -5, 1, 0)
		nameLabel.Position = UDim2.new(0, 5, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = pData.displayName or pData.name
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Parent = entry

		local statusLabel = Instance.new("TextLabel")
		statusLabel.Size = UDim2.new(0.3, -5, 1, 0)
		statusLabel.Position = UDim2.new(0.7, 0, 0, 0)
		statusLabel.BackgroundTransparency = 1
		statusLabel.Text = pData.ready and "READY" or "NOT READY"
		statusLabel.TextColor3 = pData.ready
			and Color3.fromRGB(0, 255, 100)
			or Color3.fromRGB(255, 100, 100)
		statusLabel.TextScaled = true
		statusLabel.Font = Enum.Font.GothamBold
		statusLabel.Parent = entry
	end

	PlayerList.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)

	-- Update mode highlight
	for mode, btn in pairs(modeButtons) do
		if mode == lobbyInfo.gameMode then
			btn.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
		else
			btn.BackgroundColor3 = Color3.fromRGB(50, 40, 60)
		end
	end

	-- Countdown
	if lobbyInfo.countdownActive then
		CountdownLabel.Text = "Starting in " .. lobbyInfo.countdownTime .. "..."
	else
		CountdownLabel.Text = lobbyInfo.maxPlayers - #lobbyInfo.players .. " slots available"
	end

	-- Hide lobby when session starts
	if lobbyInfo.sessionActive then
		LobbyGui.Enabled = false
	end
end

------------------------------------------------------------------------
-- Event Handler
------------------------------------------------------------------------
LobbyUpdate.OnClientEvent:Connect(UpdateLobbyDisplay)

-- Hide lobby after game starts (listen for phase change)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GamePhaseChanged = Remotes:WaitForChild("GamePhaseChanged")
GamePhaseChanged.OnClientEvent:Connect(function(phase)
	if phase ~= Enums.GamePhase.Lobby then
		LobbyGui.Enabled = false
	end
end)

print("[LobbyUI] Initialized")
