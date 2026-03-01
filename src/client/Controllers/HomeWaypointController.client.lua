--[[
	HomeWaypointController.client.lua
	Displays a home-base waypoint indicator on screen so the player can
	always find their way back — as long as the generator has power.
	When power is off, the waypoint disappears.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

------------------------------------------------------------------------
-- Wait for home base data from server (placed by MapBuilder)
------------------------------------------------------------------------
local HomeBaseCFrame = ReplicatedStorage:WaitForChild("HomeBaseCFrame", 30)
if not HomeBaseCFrame then
	warn("[HomeWaypoint] No HomeBaseCFrame found — waypoint disabled")
	return
end

local homePosition = HomeBaseCFrame.Value.Position

-- Generator power state (replicated BoolValue)
local GeneratorPowered = ReplicatedStorage:WaitForChild("GeneratorPowered", 30)
if not GeneratorPowered then
	warn("[HomeWaypoint] No GeneratorPowered value found — waypoint always on")
end

------------------------------------------------------------------------
-- Config
------------------------------------------------------------------------
local HIDE_DISTANCE = 40       -- hide waypoint when within this range of home
local EDGE_PADDING = 60        -- pixels from screen edge for the arrow
local ARROW_SIZE = 36          -- arrow frame size
local ICON_SIZE = 42           -- home icon size when on-screen

------------------------------------------------------------------------
-- Create Waypoint ScreenGui
------------------------------------------------------------------------
local WaypointGui = Instance.new("ScreenGui")
WaypointGui.Name = "HomeWaypoint"
WaypointGui.ResetOnSpawn = false
WaypointGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
WaypointGui.DisplayOrder = 5
WaypointGui.Parent = PlayerGui

-- Container for the whole waypoint (icon + distance label)
local WaypointFrame = Instance.new("Frame")
WaypointFrame.Name = "WaypointFrame"
WaypointFrame.Size = UDim2.new(0, ICON_SIZE + 60, 0, ICON_SIZE + 20)
WaypointFrame.BackgroundTransparency = 1
WaypointFrame.AnchorPoint = Vector2.new(0.5, 0.5)
WaypointFrame.Parent = WaypointGui

-- Home icon (text-based house symbol)
local HomeIcon = Instance.new("TextLabel")
HomeIcon.Name = "HomeIcon"
HomeIcon.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
HomeIcon.Position = UDim2.new(0.5, 0, 0, 0)
HomeIcon.AnchorPoint = Vector2.new(0.5, 0)
HomeIcon.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
HomeIcon.BackgroundTransparency = 0.3
HomeIcon.Text = "H"
HomeIcon.TextColor3 = Color3.fromRGB(80, 200, 255)
HomeIcon.TextScaled = true
HomeIcon.Font = Enum.Font.GothamBlack
HomeIcon.Parent = WaypointFrame

local iconCorner = Instance.new("UICorner")
iconCorner.CornerRadius = UDim.new(0, 8)
iconCorner.Parent = HomeIcon

local iconStroke = Instance.new("UIStroke")
iconStroke.Color = Color3.fromRGB(80, 200, 255)
iconStroke.Thickness = 2
iconStroke.Transparency = 0.3
iconStroke.Parent = HomeIcon

-- Distance label below icon
local DistLabel = Instance.new("TextLabel")
DistLabel.Name = "Distance"
DistLabel.Size = UDim2.new(1, 0, 0, 16)
DistLabel.Position = UDim2.new(0, 0, 1, 2)
DistLabel.AnchorPoint = Vector2.new(0, 0)
DistLabel.BackgroundTransparency = 1
DistLabel.Text = "0m"
DistLabel.TextColor3 = Color3.fromRGB(200, 220, 255)
DistLabel.TextScaled = true
DistLabel.Font = Enum.Font.GothamBold
DistLabel.Parent = HomeIcon

-- Arrow indicator (shown when home is off-screen, points toward it)
local ArrowFrame = Instance.new("TextLabel")
ArrowFrame.Name = "Arrow"
ArrowFrame.Size = UDim2.new(0, ARROW_SIZE, 0, ARROW_SIZE)
ArrowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
ArrowFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
ArrowFrame.BackgroundTransparency = 0.3
ArrowFrame.Text = ">"
ArrowFrame.TextColor3 = Color3.fromRGB(80, 200, 255)
ArrowFrame.TextScaled = true
ArrowFrame.Font = Enum.Font.GothamBlack
ArrowFrame.Rotation = 0
ArrowFrame.Visible = false
ArrowFrame.Parent = WaypointGui

local arrowCorner = Instance.new("UICorner")
arrowCorner.CornerRadius = UDim.new(0.5, 0)
arrowCorner.Parent = ArrowFrame

local arrowStroke = Instance.new("UIStroke")
arrowStroke.Color = Color3.fromRGB(80, 200, 255)
arrowStroke.Thickness = 2
arrowStroke.Transparency = 0.3
arrowStroke.Parent = ArrowFrame

------------------------------------------------------------------------
-- Power state tracking
------------------------------------------------------------------------
local isPowered = GeneratorPowered and GeneratorPowered.Value or true

if GeneratorPowered then
	GeneratorPowered.Changed:Connect(function(newValue)
		isPowered = newValue
		if not isPowered then
			-- Fade out
			TweenService:Create(WaypointFrame, TweenInfo.new(0.5), {
				GroupTransparency = 1,
			})
			TweenService:Create(ArrowFrame, TweenInfo.new(0.5), {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			})
		end
	end)
end

------------------------------------------------------------------------
-- Update loop
------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	-- Hide everything if power is off
	if not isPowered then
		WaypointFrame.Visible = false
		ArrowFrame.Visible = false
		return
	end

	local character = Player.Character
	if not character then
		WaypointFrame.Visible = false
		ArrowFrame.Visible = false
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		WaypointFrame.Visible = false
		ArrowFrame.Visible = false
		return
	end

	local playerPos = hrp.Position
	local toHome = homePosition - playerPos
	local distance = toHome.Magnitude

	-- Hide when very close to home
	if distance < HIDE_DISTANCE then
		WaypointFrame.Visible = false
		ArrowFrame.Visible = false
		return
	end

	-- Try to project home position to screen
	local screenPos, onScreen = Camera:WorldToScreenPoint(homePosition + Vector3.new(0, 12, 0))
	local viewportSize = Camera.ViewportSize

	local distText = math.floor(distance) .. "m"
	DistLabel.Text = distText

	-- Color by distance (close = green, far = blue, very far = red)
	if distance < 100 then
		HomeIcon.TextColor3 = Color3.fromRGB(80, 255, 120)
		iconStroke.Color = Color3.fromRGB(80, 255, 120)
		ArrowFrame.TextColor3 = Color3.fromRGB(80, 255, 120)
		arrowStroke.Color = Color3.fromRGB(80, 255, 120)
	elseif distance < 300 then
		HomeIcon.TextColor3 = Color3.fromRGB(80, 200, 255)
		iconStroke.Color = Color3.fromRGB(80, 200, 255)
		ArrowFrame.TextColor3 = Color3.fromRGB(80, 200, 255)
		arrowStroke.Color = Color3.fromRGB(80, 200, 255)
	else
		HomeIcon.TextColor3 = Color3.fromRGB(255, 150, 80)
		iconStroke.Color = Color3.fromRGB(255, 150, 80)
		ArrowFrame.TextColor3 = Color3.fromRGB(255, 150, 80)
		arrowStroke.Color = Color3.fromRGB(255, 150, 80)
	end

	if onScreen and screenPos.X > 0 and screenPos.X < viewportSize.X
		and screenPos.Y > 0 and screenPos.Y < viewportSize.Y then
		-- Home is on screen: show icon at projected position
		WaypointFrame.Visible = true
		ArrowFrame.Visible = false
		WaypointFrame.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y)
	else
		-- Home is off screen: show edge arrow pointing toward it
		WaypointFrame.Visible = false
		ArrowFrame.Visible = true

		-- Calculate angle from screen center to home's projected position
		local centerX = viewportSize.X / 2
		local centerY = viewportSize.Y / 2

		-- Use the screen-space direction even when behind camera
		local dir2D
		if screenPos.Z < 0 then
			-- Behind camera: flip direction
			dir2D = Vector2.new(-(screenPos.X - centerX), -(screenPos.Y - centerY))
		else
			dir2D = Vector2.new(screenPos.X - centerX, screenPos.Y - centerY)
		end

		local angle = math.atan2(dir2D.Y, dir2D.X)
		ArrowFrame.Rotation = math.deg(angle)

		-- Place arrow on screen edge
		local edgeX = centerX + math.cos(angle) * (centerX - EDGE_PADDING)
		local edgeY = centerY + math.sin(angle) * (centerY - EDGE_PADDING)

		-- Clamp to screen bounds
		edgeX = math.clamp(edgeX, EDGE_PADDING, viewportSize.X - EDGE_PADDING)
		edgeY = math.clamp(edgeY, EDGE_PADDING, viewportSize.Y - EDGE_PADDING)

		ArrowFrame.Position = UDim2.new(0, edgeX, 0, edgeY)
	end
end)

print("[HomeWaypoint] Initialized — waypoint active while generator has power")
