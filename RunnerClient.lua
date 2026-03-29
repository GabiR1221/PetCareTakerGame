-- RunnerClient (LocalScript)
-- Put this in StarterPlayerScripts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local stateRemote = ReplicatedStorage:WaitForChild("RunnerStateEvent")
local actionRemote = ReplicatedStorage:WaitForChild("RunnerActionEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "RunnerGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local jumpButton = Instance.new("TextButton")
jumpButton.Name = "RunnerJumpButton"
jumpButton.Size = UDim2.new(0, 140, 0, 46)
jumpButton.Position = UDim2.new(1, -170, 0.62, 0)
jumpButton.BackgroundColor3 = Color3.fromRGB(33, 142, 255)
jumpButton.TextColor3 = Color3.fromRGB(255, 255, 255)
jumpButton.Font = Enum.Font.SourceSansBold
jumpButton.TextSize = 22
jumpButton.Text = "Jump"
jumpButton.Parent = gui

local goBackButton = Instance.new("TextButton")
goBackButton.Name = "RunnerGoBackButton"
goBackButton.Size = UDim2.new(0, 170, 0, 42)
goBackButton.Position = UDim2.new(0.5, -85, 0.08, 0)
goBackButton.BackgroundColor3 = Color3.fromRGB(65, 65, 65)
goBackButton.TextColor3 = Color3.fromRGB(255, 255, 255)
goBackButton.Font = Enum.Font.SourceSansBold
goBackButton.TextSize = 20
goBackButton.Text = "Go Back"
goBackButton.Parent = gui

local runnerActive = false
local jumpingNow = false
local runTrack = nil
local jumpTrack = nil

local function stopTrack(track)
	if track then
		pcall(function() track:Stop(0.1) end)
	end
end

local function loadTrack(animId)
	if not animId then return nil end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = tostring(animId)
	return animator:LoadAnimation(anim)
end

jumpButton.Activated:Connect(function()
	if not runnerActive or jumpingNow then return end
	actionRemote:FireServer("Jump")
end)

goBackButton.Activated:Connect(function()
	if not runnerActive then return end
	actionRemote:FireServer("GoBack")
end)

stateRemote.OnClientEvent:Connect(function(action, enabled, payload)
	if action == "RunnerState" then
		runnerActive = enabled == true
		gui.Enabled = runnerActive
		if not runnerActive then
			jumpingNow = false
			stopTrack(runTrack)
			stopTrack(jumpTrack)
			runTrack = nil
			jumpTrack = nil
			return
		end

		stopTrack(runTrack)
		runTrack = loadTrack(payload and payload.runAnimationId)
		if runTrack then
			runTrack.Looped = true
			runTrack:Play(0.1)
		end
		jumpTrack = loadTrack(payload and payload.jumpAnimationId)
	elseif action == "JumpState" then
		local jumping = enabled == true
		jumpingNow = jumping
		if jumping then
			if runTrack then stopTrack(runTrack) end
			if jumpTrack then
				jumpTrack.Looped = false
				jumpTrack:Play(0.05)
			end
		else
			if runTrack then
				runTrack.Looped = true
				runTrack:Play(0.08)
			end
		end
	end
end)
