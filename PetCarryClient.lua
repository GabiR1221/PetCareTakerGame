-- PetCarryClient (LocalScript)
-- Put this LocalScript in StarterPlayerScripts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local carryRemote = ReplicatedStorage:WaitForChild("PetCarryEvent")
local isCarrying = false
local carriedPetName = nil

local playerGui = player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "PetCarryGui"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local dropButton = Instance.new("TextButton")
dropButton.Name = "DropPetButton"
dropButton.Size = UDim2.new(0, 150, 0, 44)
dropButton.Position = UDim2.new(1, -170, 1, -80)
dropButton.BackgroundColor3 = Color3.fromRGB(190, 70, 70)
dropButton.TextColor3 = Color3.fromRGB(255, 255, 255)
dropButton.Text = "Drop Pet (No Pet)"
dropButton.TextSize = 20
dropButton.Font = Enum.Font.SourceSansBold
dropButton.Visible = true
dropButton.Parent = gui

dropButton.Activated:Connect(function()
	carryRemote:FireServer("DropPet")
end)

carryRemote.OnClientEvent:Connect(function(action, value, petName)
	if action == "CarryState" then
		isCarrying = value == true
		carriedPetName = isCarrying and (petName or "Pet") or nil
	end
end)

RunService.RenderStepped:Connect(function()
	dropButton.Visible = isCarrying
	dropButton.AutoButtonColor = true
	dropButton.Active = true
	if isCarrying then
		dropButton.Text = ("Drop Pet (%s)"):format(tostring(carriedPetName or "Pet"))
		dropButton.BackgroundColor3 = Color3.fromRGB(190, 70, 70)
	else
		dropButton.Text = "Drop Pet"
		dropButton.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
	end
end)

task.defer(function()
	while true do
		carryRemote:FireServer("RequestCarryState")
		task.wait(0.75)
	end
end)
