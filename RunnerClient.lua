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

local staminaFrame = Instance.new("Frame")
staminaFrame.Name = "RunnerStaminaFrame"
staminaFrame.Size = UDim2.new(0, 240, 0, 22)
staminaFrame.Position = UDim2.new(0.5, -120, 0.15, 0)
staminaFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
staminaFrame.BorderSizePixel = 0
staminaFrame.Visible = false
staminaFrame.Parent = gui

local staminaFill = Instance.new("Frame")
staminaFill.Name = "RunnerStaminaFill"
staminaFill.Size = UDim2.new(1, 0, 1, 0)
staminaFill.BackgroundColor3 = Color3.fromRGB(82, 255, 125)
staminaFill.BorderSizePixel = 0
staminaFill.Parent = staminaFrame

local staminaLabel = Instance.new("TextLabel")
staminaLabel.Name = "RunnerStaminaLabel"
staminaLabel.Size = UDim2.new(1, 0, 1, 0)
staminaLabel.BackgroundTransparency = 1
staminaLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
staminaLabel.Font = Enum.Font.SourceSansBold
staminaLabel.TextSize = 16
staminaLabel.Text = "Stamina"
staminaLabel.Parent = staminaFrame


local runnerActive = false
local jumpingNow = false
local runTrack = nil
local jumpTrack = nil
local staminaCurrent = 0
local staminaMax = 50

local function stopTrack(track)
	if track then
		pcall(function() track:Stop(0.1) end)
	end
end

local function renderStamina(exhausted)
	local max = math.max(1, staminaMax)
	local ratio = math.clamp(staminaCurrent / max, 0, 1)
	staminaFill.Size = UDim2.new(ratio, 0, 1, 0)
	if exhausted then
		staminaFill.BackgroundColor3 = Color3.fromRGB(255, 92, 92)
	else
		staminaFill.BackgroundColor3 = Color3.fromRGB(82, 255, 125)
	end
	staminaLabel.Text = string.format("Stamina: %d / %d", math.floor(staminaCurrent + 0.5), math.floor(max + 0.5))
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
		staminaFrame.Visible = runnerActive
		if not runnerActive then
			jumpingNow = false
			stopTrack(runTrack)
			stopTrack(jumpTrack)
			runTrack = nil
			jumpTrack = nil
			staminaCurrent = 0
			staminaMax = 50
			renderStamina(false)
			return
		end
		
		staminaCurrent = (payload and payload.currentStamina) or staminaMax
		staminaMax = (payload and payload.maxStamina) or staminaMax
		renderStamina(false)


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
	elseif action == "StaminaUpdate" then
		if not runnerActive then return end
		staminaCurrent = payload and payload.current or staminaCurrent
		staminaMax = payload and payload.max or staminaMax
		renderStamina(payload and payload.exhausted == true)
	end
end)
