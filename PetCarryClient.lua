-- PetCarryClient (LocalScript)
-- Put this LocalScript in StarterPlayerScripts.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local carryRemote = ReplicatedStorage:WaitForChild("PetCarryEvent")
local petStateRemote = ReplicatedStorage:WaitForChild("PetStateEvent")

local isCarrying = false
local carriedPetName = nil
local canDropCarriedPet = false
local ownedPetModels = {}
local nearestPickablePet = nil
local pickupHelpers = {}

local MAX_PICKUP_DISTANCE = 7.5


local function disablePickupPrompt(instance)
	if instance and instance:IsA("ProximityPrompt") and instance.Name == "PetPrompt" then
		instance.Enabled = false
	end
end

local function registerPickupHelper(instance)
	if instance and instance:IsA("BasePart") and instance.Name == "PetPickupPart" then
		pickupHelpers[instance] = true
	end
end

local function unregisterPickupHelper(instance)
	pickupHelpers[instance] = nil
end

for _, desc in ipairs(workspace:GetDescendants()) do
	disablePickupPrompt(desc)
	registerPickupHelper(desc)
end
workspace.DescendantAdded:Connect(function(desc)
	disablePickupPrompt(desc)
	registerPickupHelper(desc)
end)
workspace.DescendantRemoving:Connect(unregisterPickupHelper)

local function isOwnedPetModel(model)
	return ownedPetModels[model] == true
end

local playerGui = player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "PetCarryGui"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local rootFrame = Instance.new("Frame")
rootFrame.Name = "Root"
rootFrame.BackgroundTransparency = 1
rootFrame.Size = UDim2.fromScale(1, 1)
rootFrame.Parent = gui

local actionButton = Instance.new("TextButton")
actionButton.Name = "ActionButton"
actionButton.AnchorPoint = Vector2.new(0.5, 1)
actionButton.Size = UDim2.new(0, 250, 0, 54)
actionButton.Position = UDim2.new(0.5, 0, 1, -36)
actionButton.BackgroundColor3 = Color3.fromRGB(38, 38, 42)
actionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
actionButton.Text = ""
actionButton.TextSize = 22
actionButton.Font = Enum.Font.GothamBold
actionButton.AutoButtonColor = true
actionButton.Visible = false
actionButton.Parent = rootFrame

local actionCorner = Instance.new("UICorner")
actionCorner.CornerRadius = UDim.new(0, 12)
actionCorner.Parent = actionButton

local actionStroke = Instance.new("UIStroke")
actionStroke.Thickness = 2
actionStroke.Color = Color3.fromRGB(255, 255, 255)
actionStroke.Transparency = 0.72
actionStroke.Parent = actionButton

local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "Hint"
hintLabel.BackgroundTransparency = 1
hintLabel.AnchorPoint = Vector2.new(0.5, 1)
hintLabel.Size = UDim2.new(0, 320, 0, 22)
hintLabel.Position = UDim2.new(0.5, 0, 1, -96)
hintLabel.Font = Enum.Font.Gotham
hintLabel.TextSize = 14
hintLabel.TextColor3 = Color3.fromRGB(221, 221, 221)
hintLabel.Text = ""
hintLabel.Visible = false
hintLabel.Parent = rootFrame

local pointerPart = Instance.new("Part")
pointerPart.Name = "PetPickupPointer"
pointerPart.Size = Vector3.new(0.2, 0.2, 0.2)
pointerPart.Anchored = false
pointerPart.CanCollide = false
pointerPart.CanTouch = false
pointerPart.CanQuery = false
pointerPart.Massless = true
pointerPart.Transparency = 1
pointerPart.Parent = workspace

local pointerAttachment = Instance.new("Attachment")
pointerAttachment.Name = "PointerAttachment"
pointerAttachment.Position = Vector3.new(0, 1.1, 0)
local petAttachment = Instance.new("Attachment")
petAttachment.Name = "PetAttachment"

local pickupBeam = Instance.new("Beam")
pickupBeam.Name = "PetPickupBeam"
pickupBeam.Width0 = 0.12
pickupBeam.Width1 = 0.03
pickupBeam.Color = ColorSequence.new(Color3.fromRGB(112, 214, 255), Color3.fromRGB(235, 246, 255))
pickupBeam.Transparency = NumberSequence.new(0.12)
pickupBeam.LightEmission = 1
pickupBeam.FaceCamera = true
pickupBeam.Segments = 8
pickupBeam.TextureSpeed = 0
pickupBeam.Attachment0 = pointerAttachment
pickupBeam.Enabled = false
pickupBeam.Parent = workspace.Terrain

local function bindPointerToPlayer()
	local character = player.Character
	local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
	if not root then return end

	pointerAttachment.Parent = root
end

bindPointerToPlayer()
player.CharacterAdded:Connect(function()
	task.wait(0.2)
	bindPointerToPlayer()
end)

local function getNearestPickablePet()
	local character = player.Character
	local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
	if not root then
		return nil
	end

	local nearest = nil
	local nearestDist = MAX_PICKUP_DISTANCE

	for helper in pairs(pickupHelpers) do
		if helper.Parent then
			local petModel = helper.Parent
			if petModel and petModel:IsA("Model") and isOwnedPetModel(petModel) and petModel:GetAttribute("WildPet") ~= true then
				local dist = (helper.Position - root.Position).Magnitude
				if dist <= nearestDist then
					nearest = petModel
					nearestDist = dist
				end
			end
		else
			pickupHelpers[helper] = nil
		end
	end

	return nearest
end

local function setPickupBeamTarget(petModel)
	if not petModel or not petModel.Parent then
		pickupBeam.Enabled = false
		petAttachment.Parent = nil
		pickupBeam.Attachment1 = nil
		return
	end

	local helper = petModel:FindFirstChild("PetPickupPart")
	if not helper or not helper:IsA("BasePart") then
		pickupBeam.Enabled = false
		petAttachment.Parent = nil
		pickupBeam.Attachment1 = nil
		return
	end

	petAttachment.Parent = helper
	pickupBeam.Attachment1 = petAttachment
	pickupBeam.Enabled = true
end

local function performCurrentAction()
	if isCarrying then
		carryRemote:FireServer("DropPet")
		return
	end
	if nearestPickablePet then
		carryRemote:FireServer("TryPickupPet", nearestPickablePet)
	end
end

actionButton.Activated:Connect(performCurrentAction)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E and actionButton.Visible then
		performCurrentAction()
	end
end)


carryRemote.OnClientEvent:Connect(function(action, value, petName, canDrop)
	if action == "CarryState" then
		isCarrying = value == true
		carriedPetName = isCarrying and (petName or "Pet") or nil
		canDropCarriedPet = (isCarrying and canDrop == true) or false
	end
end)

petStateRemote.OnClientEvent:Connect(function(action, petModel)
	if action ~= "UpdatePetState" then return end
	if typeof(petModel) ~= "Instance" or not petModel:IsA("Model") then return end
	ownedPetModels[petModel] = true
end)

RunService.RenderStepped:Connect(function()
	if isCarrying then
		nearestPickablePet = nil
		setPickupBeamTarget(nil)
		actionButton.Visible = true
		hintLabel.Visible = true
		if canDropCarriedPet then
			actionButton.Text = ("Drop %s"):format(tostring(carriedPetName or "Pet"))
			actionButton.BackgroundColor3 = Color3.fromRGB(184, 71, 71)
			hintLabel.Text = "Press E or tap button to drop"
		else
			actionButton.Text = "Adopt pet first"
			actionButton.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
			hintLabel.Text = "You can only drop owned pets"
		end
		return
	end

	nearestPickablePet = getNearestPickablePet()
	setPickupBeamTarget(nearestPickablePet)

	if nearestPickablePet then
		actionButton.Visible = true
		hintLabel.Visible = true
		actionButton.Text = ("Pick up %s"):format(tostring(nearestPickablePet.Name))
		actionButton.BackgroundColor3 = Color3.fromRGB(66, 132, 201)
		hintLabel.Text = "Press E or tap button"
	else
		actionButton.Visible = false
		hintLabel.Visible = false
	end
end)

task.defer(function()
	while true do
		carryRemote:FireServer("RequestCarryState")
		petStateRemote:FireServer("RequestOwnedPetsState")
		task.wait(0.75)
	end
end)
