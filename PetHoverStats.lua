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

-- UI you create in StarterGui
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:WaitForChild("PetHoverMenuGui")

local hoverLabel = screenGui:WaitForChild("HoverLabel")
local menuFrame = screenGui:WaitForChild("PetMenu")

local titleLabel = menuFrame:WaitForChild("TitleLabel")

local dirtLabel = menuFrame:WaitForChild("DirtLabel")
local dirtBarBg = menuFrame:WaitForChild("DirtBarBg")
local dirtBarFill = dirtBarBg:WaitForChild("DirtBarFill")
local dirtBarText = dirtBarBg:WaitForChild("DirtBarText")

local wetLabel = menuFrame:WaitForChild("WetLabel")
local wetBarBg = menuFrame:WaitForChild("WetBarBg")
local wetBarFill = wetBarBg:WaitForChild("WetBarFill")
local wetBarText = wetBarBg:WaitForChild("WetBarText")

local hungerLabel = menuFrame:WaitForChild("HungerLabel")
local hungerBarBg = menuFrame:WaitForChild("HungerBarBg")
local hungerBarFill = hungerBarBg:WaitForChild("HungerBarFill")
local hungerBarText = hungerBarBg:WaitForChild("HungerBarText")

local happinessBarBg = menuFrame:FindFirstChild("HappinessBarBg")
local happinessBarFill = happinessBarBg and happinessBarBg:FindFirstChild("HappinessBarFill")
local happinessBarText = happinessBarBg and happinessBarBg:FindFirstChild("HappinessBarText")

local levelLabel = menuFrame:WaitForChild("LevelLabel")
local xpBarBg = menuFrame:WaitForChild("XpBarBg")
local xpBarFill = xpBarBg:WaitForChild("XpBarFill")
local xpText = xpBarBg:WaitForChild("XpText")

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

	if happinessBarFill and happinessBarText then
		local happiness = tonumber(payload.happiness) or 100
		happinessBarFill.Size = UDim2.new(math.clamp(happiness / 100, 0, 1), 0, 1, 0)
		happinessBarText.Text = ("%d / 100"):format(happiness)
	end


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
			if ancestor and knownPets[ancestor] then
				return ancestor
			end
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
	local dist = math.sqrt(dx * dx + dy * dy)

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
		local camera = workspace.CurrentCamera
		if camera then
			local x = math.clamp(mouse.X + 16, 2, camera.ViewportSize.X - hoverLabel.AbsoluteSize.X - 2)
			local y = math.clamp(mouse.Y + 16, 2, camera.ViewportSize.Y - hoverLabel.AbsoluteSize.Y - 2)
			hoverLabel.Position = UDim2.new(0, x, 0, y)
		end
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
