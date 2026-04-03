-- PetHoverAndMenu (LocalScript) -> StarterPlayerScripts
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local petEvent = ReplicatedStorage:WaitForChild("PetStateEvent")
local carryEvent = ReplicatedStorage:WaitForChild("PetCarryEvent")

local knownPets = {} -- petInstance -> latest payload table
local hoveredPet = nil
local menuOpenPet = nil
local currentCarriedPet = nil

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
menuFrame.Size = UDim2.new(0, 380, 0, 150)
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

-- Wetness row
local wetLabel = Instance.new("TextLabel", menuFrame)
wetLabel.Size = UDim2.new(0, 80, 0, 22)
wetLabel.Position = UDim2.new(0, 8, 0, 66)
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

-- Hunger row
local hungerLabel = Instance.new("TextLabel", menuFrame)
hungerLabel.Size = UDim2.new(0, 80, 0, 22)
hungerLabel.Position = UDim2.new(0, 8, 0, 92)
hungerLabel.BackgroundTransparency = 1
hungerLabel.TextColor3 = Color3.fromRGB(220,220,220)
hungerLabel.Text = "Hunger"
hungerLabel.Font = Enum.Font.SourceSans
hungerLabel.TextSize = 16
hungerLabel.TextXAlignment = Enum.TextXAlignment.Left

local hungerBarBg = Instance.new("Frame", menuFrame)
hungerBarBg.Position = UDim2.new(0, 96, 0, 92)
hungerBarBg.Size = UDim2.new(0, 276, 0, 22)
hungerBarBg.BackgroundColor3 = Color3.fromRGB(60,60,60)
hungerBarBg.BorderSizePixel = 0

local hungerBarFill = Instance.new("Frame", hungerBarBg)
hungerBarFill.AnchorPoint = Vector2.new(0,0)
hungerBarFill.Size = UDim2.new(0,0,1,0)
hungerBarFill.Position = UDim2.new(0,0,0,0)
hungerBarFill.BackgroundColor3 = Color3.fromRGB(255,170,70)
hungerBarFill.BorderSizePixel = 0

local hungerBarText = Instance.new("TextLabel", hungerBarBg)
hungerBarText.Size = UDim2.new(1,0,1,0)
hungerBarText.BackgroundTransparency = 1
hungerBarText.TextColor3 = Color3.fromRGB(255,255,255)
hungerBarText.Font = Enum.Font.SourceSansBold
hungerBarText.TextSize = 14
hungerBarText.Text = "100 / 100"
hungerBarText.TextScaled = false

-- Adjust Level / XP row Y positions
levelLabel.Position = UDim2.new(0, 8, 0, 122)
xpBarBg.Position = UDim2.new(0, 96, 0, 122)

local function updateMenuForPet(pet, payload)
	if not pet or not payload then return end
	titleLabel.Text = tostring(payload.petName or pet.Name)

	local dirt = tonumber(payload.dirtiness) or 0
	dirtBarFill.Size = UDim2.new(math.clamp(dirt / 100, 0, 1), 0, 1, 0)
	dirtBarText.Text = ("%d / 100"):format(dirt)

	local wet = tonumber(payload.wetness) or 0
	wetBarFill.Size = UDim2.new(math.clamp(wet / 100, 0, 1), 0, 1, 0)
	wetBarText.Text = ("%d / 100"):format(wet)

	local hunger = tonumber(payload.hunger) or 100
	hungerBarFill.Size = UDim2.new(math.clamp(hunger / 100, 0, 1), 0, 1, 0)
	hungerBarText.Text = ("%d / 100"):format(hunger)

	levelLabel.Text = ("Lv %d"):format(payload.level or 1)
	local prog = tonumber(payload.levelProgress) or 0
	xpBarFill.Size = UDim2.new(math.clamp(prog, 0, 1), 0, 1, 0)

	if payload.xpInLevel and payload.xpForNext then
		xpText.Text = ("%d / %d XP"):format(math.max(0, payload.xpInLevel), math.max(0, math.floor(payload.xpForNext)))
	else
		xpText.Text = ("%d XP"):format(math.max(0, payload.xp or 0))
	end
end

petEvent.OnClientEvent:Connect(function(action, pet, payload)
	if action ~= "UpdatePetState" then return end
	if not pet or not payload then return end
	knownPets[pet] = payload
	if menuOpenPet == pet then
		updateMenuForPet(pet, payload)
	end
end)

local function requestOwnedPetStates()
	pcall(function()
		petEvent:FireServer("RequestOwnedPetsState")
	end)
end

requestOwnedPetStates()
task.spawn(function()
	while true do
		task.wait(6)
		requestOwnedPetStates()
	end
end)


carryEvent.OnClientEvent:Connect(function(action, isCarrying, petName)
	if action ~= "CarryState" then return end
	if not isCarrying then
		currentCarriedPet = nil
		return
	end
	if currentCarriedPet and currentCarriedPet.Parent and knownPets[currentCarriedPet] then
		return
	end

	for pet in pairs(knownPets) do
		if pet and pet.Parent and (not petName or pet.Name == petName) then
			currentCarriedPet = pet
			return
		end
	end
	currentCarriedPet = nil
end)

local function resolveHoverFromMouseTarget()
	local target = mouse.Target
	if not target then return nil end

	local p = target
	while p and p.Parent do
		if p:IsA("Model") then
			if knownPets[p] then return p end
		else
			local ancestor = p
			while ancestor and not ancestor:IsA("Model") do
				ancestor = ancestor.Parent
			end
			if ancestor and knownPets[ancestor] then return ancestor end
		end
		p = p.Parent
	end
	return nil
end

local function resolveHoverFromCarriedPetProjection()
	local pet = currentCarriedPet
	local camera = workspace.CurrentCamera
	if not pet or not pet.Parent or not camera then return nil end
	if not knownPets[pet] then return nil end

	local primary = pet.PrimaryPart or pet:FindFirstChildWhichIsA("BasePart")
	if not primary then return nil end

	local viewportPos, onScreen = camera:WorldToViewportPoint(primary.Position)
	if not onScreen then return nil end

	local dx = viewportPos.X - mouse.X
	local dy = viewportPos.Y - mouse.Y
	local dist = math.sqrt((dx * dx) + (dy * dy))
	if dist <= 85 then
		return pet
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	for pet in pairs(knownPets) do
		if not pet or not pet.Parent then
			knownPets[pet] = nil
			if hoveredPet == pet then hoveredPet = nil end
			if menuOpenPet == pet then
				menuOpenPet = nil
				menuFrame.Visible = false
			end
			if currentCarriedPet == pet then
				currentCarriedPet = nil
			end
		end
	end
	
	local newHover = resolveHoverFromMouseTarget() or resolveHoverFromCarriedPetProjection()


	if newHover ~= hoveredPet then
		hoveredPet = newHover
		if hoveredPet then
			hoverLabel.Text = tostring((knownPets[hoveredPet] and knownPets[hoveredPet].petName) or hoveredPet.Name)
			hoverLabel.Visible = true
		else
			hoverLabel.Visible = false
		end
	end

	if hoverLabel.Visible then
		local x = math.clamp(mouse.X + 16, 2, workspace.CurrentCamera.ViewportSize.X - hoverLabel.AbsoluteSize.X - 2)
		local y = math.clamp(mouse.Y + 16, 2, workspace.CurrentCamera.ViewportSize.Y - hoverLabel.AbsoluteSize.Y - 2)
		hoverLabel.Position = UDim2.new(0, x, 0, y)
	end
end)

mouse.Button1Down:Connect(function()
	if hoveredPet then
		menuOpenPet = hoveredPet
		menuFrame.Visible = true
		local payload = knownPets[menuOpenPet]
		updateMenuForPet(menuOpenPet, payload)
	else
		menuOpenPet = nil
		menuFrame.Visible = false
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape then
		menuOpenPet = nil
		menuFrame.Visible = false
	end
end)
