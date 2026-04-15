-- RunnerClient (LocalScript)
-- Put this in StarterPlayerScripts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local workspaceService = game:GetService("Workspace")

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
jumpButton.AutoButtonColor = false
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
goBackButton.AutoButtonColor = false
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
local stumblingNow = false
local waitingForJumpAnimEnd = false

local runTrack = nil
local jumpStartTrack = nil
local jumpSlideTrack = nil
local stumbleTrack = nil
local jumpStartStoppedConn = nil

local staminaCurrent = 0
local staminaMax = 50
local hiddenUiState = {}
local savedCameraSubject = nil

local function animateButtonScale(button, scaleValue, time)
	local scale = button:FindFirstChild("RunnerScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "RunnerScale"
		scale.Scale = 1
		scale.Parent = button
	end

	TweenService:Create(scale, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = scaleValue,
	}):Play()
end

local function hookButtonAnimation(button)
	button.MouseEnter:Connect(function()
		animateButtonScale(button, 1.05, 0.08)
	end)

	button.MouseLeave:Connect(function()
		animateButtonScale(button, 1, 0.08)
	end)

	button.MouseButton1Down:Connect(function()
		animateButtonScale(button, 0.96, 0.05)
	end)

	button.MouseButton1Up:Connect(function()
		animateButtonScale(button, 1.05, 0.06)
	end)
end

hookButtonAnimation(jumpButton)
hookButtonAnimation(goBackButton)

local function updateControlsLocked()
	local locked = jumpingNow or stumblingNow
	jumpButton.Active = not locked and runnerActive
	goBackButton.Active = not locked and runnerActive
	jumpButton.AutoButtonColor = not locked and runnerActive
	goBackButton.AutoButtonColor = not locked and runnerActive
end

local function stopTrack(track)
	if track then
		pcall(function()
			track:Stop(0.1)
		end)
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

local function setGameUiSprinting(active)
	local playerGui = player:FindFirstChild("PlayerGui")
	local gameUi = playerGui and playerGui:FindFirstChild("GameUI")
	if not gameUi then return end

	local function setContainerVisible(containerName)
		local container = gameUi:FindFirstChild(containerName)
		if not container then return end

		if active then
			hiddenUiState[containerName] = hiddenUiState[containerName] or {}
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("GuiObject") and child.Visible then
					hiddenUiState[containerName][child] = true
					child.Visible = false
				end
			end
		else
			for child in pairs(hiddenUiState[containerName] or {}) do
				if child and child.Parent == container then
					child.Visible = true
				end
			end
			hiddenUiState[containerName] = {}
		end
	end

	setContainerVisible("Frames")
	setContainerVisible("LeftSide")
end

local function clearAllTracks()
	if jumpStartStoppedConn then
		jumpStartStoppedConn:Disconnect()
		jumpStartStoppedConn = nil
	end

	stopTrack(runTrack)
	stopTrack(jumpStartTrack)
	stopTrack(jumpSlideTrack)
	stopTrack(stumbleTrack)

	runTrack = nil
	jumpStartTrack = nil
	jumpSlideTrack = nil
	stumbleTrack = nil
end

local function restoreRunnerCamera()
	local camera = workspaceService.CurrentCamera
	if camera and savedCameraSubject and savedCameraSubject.Parent then
		camera.CameraSubject = savedCameraSubject
	end
	savedCameraSubject = nil
end

local function setRunnerCameraToHead()
	local camera = workspaceService.CurrentCamera
	local char = player.Character
	if not camera or not char then return end

	local head = char:FindFirstChild("Head")
	if not head then return end

	if not savedCameraSubject then
		savedCameraSubject = camera.CameraSubject
	end

	camera.CameraSubject = head
end


jumpButton.Activated:Connect(function()
	if not runnerActive or jumpingNow or stumblingNow then return end
	actionRemote:FireServer("Jump")
end)

goBackButton.Activated:Connect(function()
	if not runnerActive or jumpingNow or stumblingNow then return end
	actionRemote:FireServer("GoBack")
end)

stateRemote.OnClientEvent:Connect(function(action, enabled, payload)
	if action == "RunnerState" then
		runnerActive = enabled == true
		gui.Enabled = runnerActive
		staminaFrame.Visible = runnerActive
		setGameUiSprinting(runnerActive)

		if not runnerActive then
			jumpingNow = false
			stumblingNow = false
			waitingForJumpAnimEnd = false
			clearAllTracks()
			staminaCurrent = 0
			staminaMax = 50
			renderStamina(false)
			updateControlsLocked()
			restoreRunnerCamera()
			return
		end

		staminaCurrent = (payload and payload.currentStamina) or staminaMax
		staminaMax = (payload and payload.maxStamina) or staminaMax
		renderStamina(false)

		clearAllTracks()

		runTrack = loadTrack(payload and payload.runAnimationId)
		if runTrack then
			runTrack.Looped = true
			runTrack:Play(0.1)
		end

		stumbleTrack = loadTrack(payload and (payload.stumbleAnimationId or payload.jumpSlideAnimationId or payload.jumpAnimationId))
		jumpStartTrack = loadTrack(payload and (payload.jumpStartAnimationId or payload.jumpAnimationId))
		jumpSlideTrack = loadTrack(payload and (payload.jumpSlideAnimationId or payload.jumpAnimationId))

		if jumpStartTrack then
			jumpStartStoppedConn = jumpStartTrack.Stopped:Connect(function()
				if runnerActive and jumpingNow and not stumblingNow and waitingForJumpAnimEnd then
					waitingForJumpAnimEnd = false
					actionRemote:FireServer("JumpAnimEnded")
				end
			end)
		end

		updateControlsLocked()
		setRunnerCameraToHead()

	elseif action == "JumpState" then
		local jumping = enabled == true
		local phase = payload and payload.phase or "Start"

		jumpingNow = jumping
		stumblingNow = false
		updateControlsLocked()

		if jumping then
			if runTrack then stopTrack(runTrack) end
			if stumbleTrack then stopTrack(stumbleTrack) end

			if phase == "Slide" then
				waitingForJumpAnimEnd = false
				if jumpStartTrack then stopTrack(jumpStartTrack) end
				if jumpSlideTrack then
					jumpSlideTrack.Looped = true
					jumpSlideTrack:Play(0.05)
				end
			else
				if jumpSlideTrack then stopTrack(jumpSlideTrack) end
				waitingForJumpAnimEnd = true
				if jumpStartTrack then
					jumpStartTrack.Looped = false
					jumpStartTrack:Play(0.05)
				end
			end
		else
			waitingForJumpAnimEnd = false
			if jumpStartTrack then stopTrack(jumpStartTrack) end
			if jumpSlideTrack then stopTrack(jumpSlideTrack) end
			if runTrack then
				runTrack.Looped = true
				runTrack:Play(0.08)
			end
		end

	elseif action == "StumbleState" then
		local stumbling = enabled == true
		stumblingNow = stumbling
		waitingForJumpAnimEnd = false
		updateControlsLocked()

		if stumbling then
			if runTrack then stopTrack(runTrack) end
			if jumpStartTrack then stopTrack(jumpStartTrack) end
			if jumpSlideTrack then stopTrack(jumpSlideTrack) end

			if stumbleTrack then
				stumbleTrack.Looped = false
				stumbleTrack:Play(0.05)
			end
		else
			if stumbleTrack then stopTrack(stumbleTrack) end
			if runnerActive and not jumpingNow and runTrack then
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

player.CharacterAdded:Connect(function()
	if runnerActive then
		task.defer(setRunnerCameraToHead)
	end
end)
