-- PetFeedingClient (LocalScript)
-- Put this LocalScript in StarterPlayerScripts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local feedRemote = ReplicatedStorage:WaitForChild("PetFeedEvent")

local function getPetModelFromTarget(target)
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

mouse.Button1Down:Connect(function()
	local foodTool = getEquippedFoodTool()
	if not foodTool then
		return
	end

	local target = mouse.Target
	if not target then
		return
	end

	local petModel = getPetModelFromTarget(target)
	if not petModel then
		return
	end

	feedRemote:FireServer(petModel)
end)
