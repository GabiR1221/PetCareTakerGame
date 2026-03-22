-- PetHoverAndMenu (LocalScript) -> StarterPlayerScripts
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local petEvent = ReplicatedStorage:WaitForChild("PetStateEvent")

local knownPets = {} -- petInstance -> latest payload table
local hoveredPet = nil
local menuOpenPet = nil

-- Create GUI
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PetHoverMenuGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Hover label (near cursor)
local hoverLabel = Instance.new("TextLabel")
hoverLabel.Name = "HoverLabel"
hoverLabel.Size = UDim2.new(0, 180, 0, 28)
hoverLabel.BackgroundTransparency = 0.3
hoverLabel.BackgroundColor3 = Color3.fromRGB(0,0,0)
hoverLabel.BorderSizePixel = 0
hoverLabel.TextColor3 = Color3.fromRGB(255,255,255)
hoverLabel.TextStrokeTransparency = 0.6
hoverLabel.TextScaled = true
hoverLabel.Visible = false
hoverLabel.AnchorPoint = Vector2.new(0,0)
hoverLabel.Parent = screenGui

-- Pet menu frame (center-ish, slightly lower)
local menuFrame = Instance.new("Frame")
menuFrame.Name = "PetMenu"
menuFrame.Size = UDim2.new(0, 380, 0, 120)
menuFrame.Position = UDim2.new(0.5, -190, 0.6, -60) -- center horizontally, lower than center
menuFrame.AnchorPoint = Vector2.new(0,0)
menuFrame.BackgroundTransparency = 0.15
menuFrame.BackgroundColor3 = Color3.fromRGB(15,15,15)
menuFrame.BorderSizePixel = 0
menuFrame.Visible = false
menuFrame.Parent = screenGui

local titleLabel = Instance.new("TextLabel", menuFrame)
titleLabel.Size = UDim2.new(1, -12, 0, 28)
titleLabel.Position = UDim2.new(0,6,0,6)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(255,255,255)
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextSize = 20
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "Pet"

-- Dirtiness row
local dirtLabel = Instance.new("TextLabel", menuFrame)
dirtLabel.Size = UDim2.new(0, 80, 0, 22)
dirtLabel.Position = UDim2.new(0, 8, 0, 40)
dirtLabel.BackgroundTransparency = 1
dirtLabel.TextColor3 = Color3.fromRGB(220,220,220)
dirtLabel.Text = "Dirtiness"
dirtLabel.Font = Enum.Font.SourceSans
dirtLabel.TextSize = 16
dirtLabel.TextXAlignment = Enum.TextXAlignment.Left

local dirtBarBg = Instance.new("Frame", menuFrame)
dirtBarBg.Position = UDim2.new(0, 96, 0, 40)
dirtBarBg.Size = UDim2.new(0, 276, 0, 22)
dirtBarBg.BackgroundColor3 = Color3.fromRGB(60,60,60)
dirtBarBg.BorderSizePixel = 0

local dirtBarFill = Instance.new("Frame", dirtBarBg)
dirtBarFill.AnchorPoint = Vector2.new(0,0)
dirtBarFill.Size = UDim2.new(0,0,1,0)
dirtBarFill.Position = UDim2.new(0,0,0,0)
dirtBarFill.BackgroundColor3 = Color3.fromRGB(200,150,50)
dirtBarFill.BorderSizePixel = 0

local dirtBarText = Instance.new("TextLabel", dirtBarBg)
dirtBarText.Size = UDim2.new(1,0,1,0)
dirtBarText.BackgroundTransparency = 1
dirtBarText.TextColor3 = Color3.fromRGB(255,255,255)
dirtBarText.Font = Enum.Font.SourceSansBold
dirtBarText.TextSize = 14
dirtBarText.Text = "0 / 100"
dirtBarText.TextScaled = false

-- Level / XP row
local levelLabel = Instance.new("TextLabel", menuFrame)
levelLabel.Size = UDim2.new(0, 80, 0, 22)
levelLabel.Position = UDim2.new(0, 8, 0, 70)
levelLabel.BackgroundTransparency = 1
levelLabel.TextColor3 = Color3.fromRGB(220,220,220)
levelLabel.Text = "Level"
levelLabel.Font = Enum.Font.SourceSans
levelLabel.TextSize = 16
levelLabel.TextXAlignment = Enum.TextXAlignment.Left

local xpBarBg = Instance.new("Frame", menuFrame)
xpBarBg.Position = UDim2.new(0, 96, 0, 70)
xpBarBg.Size = UDim2.new(0, 276, 0, 22)
xpBarBg.BackgroundColor3 = Color3.fromRGB(60,60,60)
xpBarBg.BorderSizePixel = 0

local xpBarFill = Instance.new("Frame", xpBarBg)
xpBarFill.AnchorPoint = Vector2.new(0,0)
xpBarFill.Size = UDim2.new(0,0,1,0)
xpBarFill.Position = UDim2.new(0,0,0,0)
xpBarFill.BackgroundColor3 = Color3.fromRGB(80,160,240)
xpBarFill.BorderSizePixel = 0

local xpText = Instance.new("TextLabel", xpBarBg)
xpText.Size = UDim2.new(1,0,1,0)
xpText.BackgroundTransparency = 1
xpText.TextColor3 = Color3.fromRGB(255,255,255)
xpText.Font = Enum.Font.SourceSansBold
xpText.TextSize = 14
xpText.Text = "XP"
xpText.TextScaled = false

-- Wetness row (insert between dirtiness and level if you like)
local wetLabel = Instance.new("TextLabel", menuFrame)
wetLabel.Size = UDim2.new(0, 80, 0, 22)
wetLabel.Position = UDim2.new(0, 8, 0, 66) -- slightly below dirtiness
wetLabel.BackgroundTransparency = 1
wetLabel.TextColor3 = Color3.fromRGB(220,220,220)
wetLabel.Text = "Wetness"
wetLabel.Font = Enum.Font.SourceSans
wetLabel.TextSize = 16
wetLabel.TextXAlignment = Enum.TextXAlignment.Left

local wetBarBg = Instance.new("Frame", menuFrame)
wetBarBg.Position = UDim2.new(0, 96, 0, 66)
wetBarBg.Size = UDim2.new(0, 276, 0, 22)
wetBarBg.BackgroundColor3 = Color3.fromRGB(60,60,60)
wetBarBg.BorderSizePixel = 0

local wetBarFill = Instance.new("Frame", wetBarBg)
wetBarFill.AnchorPoint = Vector2.new(0,0)
wetBarFill.Size = UDim2.new(0,0,1,0)
wetBarFill.Position = UDim2.new(0,0,0,0)
wetBarFill.BackgroundColor3 = Color3.fromRGB(80,200,180)
wetBarFill.BorderSizePixel = 0

local wetBarText = Instance.new("TextLabel", wetBarBg)
wetBarText.Size = UDim2.new(1,0,1,0)
wetBarText.BackgroundTransparency = 1
wetBarText.TextColor3 = Color3.fromRGB(255,255,255)
wetBarText.Font = Enum.Font.SourceSansBold
wetBarText.TextSize = 14
wetBarText.Text = "0 / 100"
wetBarText.TextScaled = false

-- Adjust Level / XP row Y positions (shift them down if necessary)
levelLabel.Position = UDim2.new(0, 8, 0, 96)
xpBarBg.Position = UDim2.new(0, 96, 0, 96)

-- Helper to update GUI (replace your existing updateMenuForPet)
local function updateMenuForPet(pet, payload)
	if not pet or not payload then return end
	titleLabel.Text = tostring(payload.petName or pet.Name)

	-- Dirtiness
	local dirt = tonumber(payload.dirtiness) or 0
	dirtBarFill.Size = UDim2.new(math.clamp(dirt / 100, 0, 1), 0, 1, 0)
	dirtBarText.Text = ("%d / 100"):format(dirt)

	-- Wetness
	local wet = tonumber(payload.wetness) or 0
	wetBarFill.Size = UDim2.new(math.clamp(wet / 100, 0, 1), 0, 1, 0)
	wetBarText.Text = ("%d / 100"):format(wet)

	-- Level / XP
	levelLabel.Text = ("Lv %d"):format(payload.level or 1)
	local prog = tonumber(payload.levelProgress) or 0
	xpBarFill.Size = UDim2.new(math.clamp(prog, 0, 1), 0, 1, 0)

	if payload.xpInLevel and payload.xpForNext then
		xpText.Text = ("%d / %d XP"):format(math.max(0, payload.xpInLevel), math.max(0, math.floor(payload.xpForNext)))
	else
		xpText.Text = ("%d XP"):format(math.max(0, payload.xp or 0))
	end
end

-- PetStateEvent handler
petEvent.OnClientEvent:Connect(function(action, pet, payload)
	if action ~= "UpdatePetState" then return end
	if not pet or not payload then return end
	knownPets[pet] = payload
	-- if the menu is open for this pet, update it
	if menuOpenPet == pet then
		updateMenuForPet(pet, payload)
	end
end)

-- Hover detection
RunService.RenderStepped:Connect(function()
	local target = mouse.Target
	local newHover = nil
	if target then
		local p = target
		while p and p.Parent do
			-- check if p.Parent is a known pet model (or p itself is a model part belonging to a known pet)
			if p:IsA("Model") then
				if knownPets[p] then newHover = p; break end
			else
				local ancestor = p
				while ancestor and not ancestor:IsA("Model") do
					ancestor = ancestor.Parent
				end
				if ancestor and knownPets[ancestor] then newHover = ancestor; break end
			end
			p = p.Parent
		end
	end

	if newHover ~= hoveredPet then
		hoveredPet = newHover
		if hoveredPet then
			hoverLabel.Text = tostring((knownPets[hoveredPet] and knownPets[hoveredPet].petName) or hoveredPet.Name)
			hoverLabel.Visible = true
		else
			hoverLabel.Visible = false
		end
	end

	-- position hover label near mouse
	if hoverLabel.Visible then
		local x = math.clamp(mouse.X + 16, 2, workspace.CurrentCamera.ViewportSize.X - hoverLabel.AbsoluteSize.X - 2)
		local y = math.clamp(mouse.Y + 16, 2, workspace.CurrentCamera.ViewportSize.Y - hoverLabel.AbsoluteSize.Y - 2)
		hoverLabel.Position = UDim2.new(0, x, 0, y)
	end
end)

-- Open menu on click when hovering a pet
mouse.Button1Down:Connect(function()
	if hoveredPet then
		menuOpenPet = hoveredPet
		menuFrame.Visible = true
		local payload = knownPets[menuOpenPet]
		updateMenuForPet(menuOpenPet, payload)
	else
		-- close menu if click elsewhere
		menuOpenPet = nil
		menuFrame.Visible = false
	end
end)

-- Close menu on Escape or right-click
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape then
		menuOpenPet = nil
		menuFrame.Visible = false
	end
end)
