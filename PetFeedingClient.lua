-- PetFeedingClient (LocalScript)
-- Put this LocalScript in StarterPlayerScripts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local feedInteractRemote = ReplicatedStorage:WaitForChild("PetFeedInteractEvent")

local FEED_PROMPT_NAME = "FeedPromptClient"
local PET_PROMPT_NAME = "PetPrompt"
local FEED_MAX_DISTANCE = 8
local FEED_HOLD_DURATION = 1.2
local HOLD_COMPLETE_CANCEL_SUPPRESS_WINDOW = 0.25

local trackedPickupPrompts = {}
local cancelSuppressedUntilByPrompt = {}

local function getPetModelFromInstance(target)
	local current = target
	while current do
		if current:IsA("Model") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getEquippedFoodTool()
	local character = player.Character
	if not character then return nil end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and (child:GetAttribute("IsPetFood") == true or child:GetAttribute("HungerGain") ~= nil or child:FindFirstChild("HungerGain")) then
			return child
		end
	end

	return nil
end

local function hasFoodEquipped()
	return getEquippedFoodTool() ~= nil
end

local function getOrCreateFeedPrompt(pickupPrompt)
	if not pickupPrompt or not pickupPrompt.Parent then return nil end

	local helperPart = pickupPrompt.Parent
	if not helperPart:IsA("BasePart") then return nil end

	local feedPrompt = helperPart:FindFirstChild(FEED_PROMPT_NAME)
	if feedPrompt and not feedPrompt:IsA("ProximityPrompt") then
		feedPrompt:Destroy()
		feedPrompt = nil
	end

	if not feedPrompt then
		feedPrompt = Instance.new("ProximityPrompt")
		feedPrompt.Name = FEED_PROMPT_NAME
		feedPrompt.ActionText = "Feed"
		feedPrompt.ObjectText = "Pet"
		feedPrompt.MaxActivationDistance = FEED_MAX_DISTANCE
		feedPrompt.HoldDuration = FEED_HOLD_DURATION
		feedPrompt.RequiresLineOfSight = false
		feedPrompt.Enabled = false
		feedPrompt.Parent = helperPart

		feedPrompt.PromptButtonHoldBegan:Connect(function()
			if not hasFoodEquipped() then
				return
			end
			local petModel = getPetModelFromInstance(helperPart)
			if petModel then
				cancelSuppressedUntilByPrompt[feedPrompt] = 0
				feedInteractRemote:FireServer("start", petModel)
			end
		end)

		feedPrompt.PromptButtonHoldEnded:Connect(function()
			local suppressUntil = cancelSuppressedUntilByPrompt[feedPrompt] or 0
			if os.clock() < suppressUntil then
				cancelSuppressedUntilByPrompt[feedPrompt] = 0
				return
			end
			feedInteractRemote:FireServer("cancel")
		end)

		feedPrompt.Triggered:Connect(function()
			if not hasFoodEquipped() then
				return
			end

			local petModel = getPetModelFromInstance(helperPart)
			if not petModel then
				return
			end

			cancelSuppressedUntilByPrompt[feedPrompt] = os.clock() + HOLD_COMPLETE_CANCEL_SUPPRESS_WINDOW
			feedInteractRemote:FireServer("complete", petModel)
		end)
	end

	return feedPrompt
end

local function setPromptModeForPickupPrompt(pickupPrompt)
	if not pickupPrompt or not pickupPrompt:IsA("ProximityPrompt") or not pickupPrompt.Parent then
		return
	end

	local feedPrompt = getOrCreateFeedPrompt(pickupPrompt)
	if not feedPrompt then return end

	local shouldFeed = hasFoodEquipped()
	pickupPrompt.Enabled = not shouldFeed
	feedPrompt.Enabled = shouldFeed
end

local function registerPickupPrompt(prompt)
	if trackedPickupPrompts[prompt] then
		return
	end

	trackedPickupPrompts[prompt] = true

	prompt:GetPropertyChangedSignal("Parent"):Connect(function()
		if not prompt.Parent then
			trackedPickupPrompts[prompt] = nil
		end
	end)

	setPromptModeForPickupPrompt(prompt)
end

local function isPetPickupPrompt(instance)
	if not instance or not instance:IsA("ProximityPrompt") then
		return false
	end

	if instance.Name ~= PET_PROMPT_NAME then
		return false
	end

	local parentPart = instance.Parent
	if not parentPart or not parentPart:IsA("BasePart") then
		return false
	end

	return parentPart.Name == "PetPickupPart"
end

local function refreshAllPromptModes()
	for prompt in pairs(trackedPickupPrompts) do
		if prompt and prompt.Parent then
			setPromptModeForPickupPrompt(prompt)
		else
			trackedPickupPrompts[prompt] = nil
		end
	end
end

for _, descendant in ipairs(Workspace:GetDescendants()) do
	if isPetPickupPrompt(descendant) then
		registerPickupPrompt(descendant)
	end
end

Workspace.DescendantAdded:Connect(function(descendant)
	if isPetPickupPrompt(descendant) then
		registerPickupPrompt(descendant)
	end
end)

player.CharacterAdded:Connect(function(character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			refreshAllPromptModes()
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			refreshAllPromptModes()
		end
	end)

	refreshAllPromptModes()
end)

if player.Character then
	local character = player.Character
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			refreshAllPromptModes()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			refreshAllPromptModes()
		end
	end)
end

refreshAllPromptModes()

