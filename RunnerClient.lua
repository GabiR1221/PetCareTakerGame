-- RunnerClient (LocalScript)
-- Put this in StarterPlayerScripts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local workspaceService = game:GetService("Workspace")

local player = Players.LocalPlayer
local stateRemote = ReplicatedStorage:WaitForChild("RunnerStateEvent")
local actionRemote = ReplicatedStorage:WaitForChild("RunnerActionEvent")
local petInteractionUiRemote = ReplicatedStorage:WaitForChild("PetInteractionUIEvent")
local BREAK_WALL_TAG = "RunnerBreakWall"
local BREAK_WALL_NAME = "RunnerBreakWall"

local function waitForRunnerGui(timeout)
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("RunnerGui")
	local startedAt = os.clock()
	timeout = timeout or 10

	while not gui and (os.clock() - startedAt) < timeout do
		task.wait(0.25)
		gui = playerGui:FindFirstChild("RunnerGui")
	end

	if gui and gui:IsA("ScreenGui") then
		return gui
	end
	return nil
end

local gui = waitForRunnerGui()
if not gui then
	warn("[RunnerClient] Missing PlayerGui.RunnerGui. Create it in Studio before sprinting starts.")
	return
end

local jumpButton = gui:FindFirstChild("RunnerJumpButton", true)
local goBackButton = gui:FindFirstChild("RunnerGoBackButton", true)
local staminaFrame = gui:FindFirstChild("RunnerStaminaFrame", true)
local staminaFill = staminaFrame and staminaFrame:FindFirstChild("RunnerStaminaFill", true)
local staminaLabel = staminaFrame and staminaFrame:FindFirstChild("RunnerStaminaLabel", true)

local gameUi = player:WaitForChild("PlayerGui"):FindFirstChild("GameUI")
local framesRoot = gameUi and gameUi:FindFirstChild("Frames")
local pendingCasesFrame = (gameUi and gameUi:FindFirstChild("PendingCases")) or (framesRoot and framesRoot:FindFirstChild("PendingCases"))
local pendingTemplate = pendingCasesFrame and pendingCasesFrame:FindFirstChild("Template")
local caseHatchRemote = ReplicatedStorage:FindFirstChild("CaseHatchEvent")
local pendingCasesDefaultSize = pendingCasesFrame and pendingCasesFrame.Size or nil

if not jumpButton or not jumpButton:IsA("GuiButton") then
	warn("[RunnerClient] Missing RunnerJumpButton (GuiButton) in RunnerGui.")
	return
end
if not goBackButton or not goBackButton:IsA("GuiButton") then
	warn("[RunnerClient] Missing RunnerGoBackButton (GuiButton) in RunnerGui.")
	return
end
if not staminaFrame or not staminaFrame:IsA("GuiObject") then
	warn("[RunnerClient] Missing RunnerStaminaFrame in RunnerGui.")
	return
end
if not staminaFill or not staminaFill:IsA("GuiObject") then
	warn("[RunnerClient] Missing RunnerStaminaFill inside RunnerStaminaFrame.")
	return
end
if not staminaLabel or not staminaLabel:IsA("TextLabel") then
	warn("[RunnerClient] Missing RunnerStaminaLabel inside RunnerStaminaFrame.")
	return
end

gui.Enabled = false
staminaFrame.Visible = false
if pendingCasesFrame then pendingCasesFrame.Visible = false end

local runnerActive = false
local jumpingNow = false
local stumblingNow = false
local exhaustedNow = false
local exhaustionPhase = nil
local waitingForJumpAnimEnd = false
local wallBreakingNow = false
local wallBreakSuccessNow = false

local runTrack = nil
local jumpStartTrack = nil
local jumpSlideTrack = nil
local stumbleTrack = nil
local exhaustedSlideTrack = nil
local exhaustedLoopTrack = nil
local jumpStartStoppedConn = nil
local wallBreakSuccessTrack = nil
local wallBreakFailTrack = nil
local wallBreakTrackStoppedConn = nil
local wallBreakMarkerConn = nil
local wallBreakKeyframeConn = nil
local petInteractionUiHidden = false

local staminaCurrent = 0
local staminaMax = 50
local hiddenUiState = {}
local savedCameraSubject = nil
local modifiedWalls = {}
local wallGradientStates = {}

local ContextActionService = game:GetService("ContextActionService")
local MOVEMENT_LOCK_ACTION = "RunnerExhaustedMoveLock"

local function movementLockAction()
	return Enum.ContextActionResult.Sink
end

local function setMovementLocked(locked)
	if locked then
		ContextActionService:BindActionAtPriority(
			MOVEMENT_LOCK_ACTION,
			movementLockAction,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.PlayerActions.CharacterForward,
			Enum.PlayerActions.CharacterBackward,
			Enum.PlayerActions.CharacterLeft,
			Enum.PlayerActions.CharacterRight,
			Enum.PlayerActions.CharacterJump
		)
	else
		ContextActionService:UnbindAction(MOVEMENT_LOCK_ACTION)
	end
end

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
	local jumpLocked = jumpingNow or stumblingNow or exhaustedNow
	local goBackLocked = jumpingNow or stumblingNow or wallBreakingNow or (exhaustedNow and exhaustionPhase ~= "Collapsed")
	jumpLocked = jumpLocked or wallBreakingNow
	jumpButton.Active = (not jumpLocked) and runnerActive
	goBackButton.Active = (not goBackLocked) and runnerActive
	jumpButton.AutoButtonColor = (not jumpLocked) and runnerActive
	goBackButton.AutoButtonColor = (not goBackLocked) and runnerActive
	setMovementLocked(exhaustedNow or wallBreakingNow)
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
	
	local blur = gameUi:FindFirstChild("Blur")
	if active then
		hiddenUiState.__blurVisible = blur and blur:IsA("GuiObject") and blur.Visible or false
		hiddenUiState.__blurTransparency = blur and blur:IsA("GuiObject") and blur.BackgroundTransparency or nil
		if blur and blur:IsA("GuiObject") then
			blur.Visible = false
			blur.BackgroundTransparency = 1
		end
	elseif blur and blur:IsA("GuiObject") then
		blur.Visible = false
		blur.BackgroundTransparency = 1
		hiddenUiState.__blurVisible = nil
		hiddenUiState.__blurTransparency = nil
	end

	local function setContainerVisible(containerName)
		local container = gameUi:FindFirstChild(containerName)
		if not container then return end

		if active then
			hiddenUiState[containerName] = hiddenUiState[containerName] or {}
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("GuiObject") and child.Visible then
					hiddenUiState[containerName][child] = true
					if containerName == "Frames" and child:IsA("Frame") then
						local closeSize = child.Size - UDim2.fromScale(0.15, 0.15)
						child:TweenSize(closeSize, Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.1, true)
						task.wait(0.04)
					end
					child.Visible = false
				end
			end
		else
			if containerName == "Frames" then
				hiddenUiState[containerName] = {}
			else
				for child in pairs(hiddenUiState[containerName] or {}) do
					if child and child.Parent == container then
						child.Visible = true
					end
				end
				hiddenUiState[containerName] = {}
			end
		end
	end

	setContainerVisible("Frames")
	setContainerVisible("LeftSide")
end

local function refreshGameUiSuppression()
	setGameUiSprinting(runnerActive or petInteractionUiHidden)
end

local function clearAllTracks()
	if jumpStartStoppedConn then
		jumpStartStoppedConn:Disconnect()
		jumpStartStoppedConn = nil
	end
	if wallBreakTrackStoppedConn then
		wallBreakTrackStoppedConn:Disconnect()
		wallBreakTrackStoppedConn = nil
	end
	if wallBreakMarkerConn then
		wallBreakMarkerConn:Disconnect()
		wallBreakMarkerConn = nil
	end
	if wallBreakKeyframeConn then
		wallBreakKeyframeConn:Disconnect()
		wallBreakKeyframeConn = nil
	end

	stopTrack(runTrack)
	stopTrack(jumpStartTrack)
	stopTrack(jumpSlideTrack)
	stopTrack(stumbleTrack)
	stopTrack(exhaustedSlideTrack)
	stopTrack(exhaustedLoopTrack)
	stopTrack(wallBreakSuccessTrack)
	stopTrack(wallBreakFailTrack)

	runTrack = nil
	jumpStartTrack = nil
	jumpSlideTrack = nil
	stumbleTrack = nil
	exhaustedSlideTrack = nil
	exhaustedLoopTrack = nil
	wallBreakSuccessTrack = nil
	wallBreakFailTrack = nil
end

local function forEachBreakWall(callback)
	for _, wall in ipairs(CollectionService:GetTagged(BREAK_WALL_TAG)) do
		if wall:IsA("BasePart") then
			callback(wall)
		end
	end
	for _, inst in ipairs(workspaceService:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == BREAK_WALL_NAME then
			callback(inst)
		end
	end
end

local function setWallFrameVisible(wallPart, visible)
	if not wallPart then return end
	for _, descendant in ipairs(wallPart:GetDescendants()) do
		if descendant:IsA("SurfaceGui") then
			descendant.Enabled = visible
			local frame = descendant:FindFirstChild("Frame")
			if frame and frame:IsA("GuiObject") then
				frame.Visible = visible
			end
		end
	end
end

local function setBreakWallFramesVisible(visible)
	forEachBreakWall(function(wall)
		setWallFrameVisible(wall, visible)
	end)
end

local function blendColorToWhite(color, alpha)
	return color:Lerp(Color3.new(1, 1, 1), math.clamp(alpha, 0, 1))
end

local function blendSequenceToWhite(sequence, alpha)
	local keypoints = {}
	for _, keypoint in ipairs(sequence.Keypoints) do
		table.insert(keypoints, ColorSequenceKeypoint.new(keypoint.Time, blendColorToWhite(keypoint.Value, alpha)))
	end
	if #keypoints == 0 then
		return ColorSequence.new(Color3.new(1, 1, 1))
	end
	return ColorSequence.new(keypoints)
end

local function getWallGradients(wallPart)
	local gradients = {}
	if not wallPart then return gradients end
	for _, descendant in ipairs(wallPart:GetDescendants()) do
		if descendant:IsA("UIGradient") then
			table.insert(gradients, descendant)
		end
	end
	return gradients
end

local function snapshotWallSurfaceGuis(wallPart)
	local snapshots = {}
	if not wallPart then return snapshots end
	for _, descendant in ipairs(wallPart:GetDescendants()) do
		if descendant:IsA("SurfaceGui") then
			snapshots[descendant] = descendant.Enabled
		end
	end
	return snapshots
end

local function setWallSurfaceGuisEnabled(wallPart, enabled)
	if not wallPart then return end
	for _, descendant in ipairs(wallPart:GetDescendants()) do
		if descendant:IsA("SurfaceGui") then
			descendant.Enabled = enabled
		end
	end
end

local function animateWallGradientBreak(wallPart, durationOverride)
	if not wallPart or not wallPart.Parent then return 0.25 end
	local duration = math.clamp(tonumber(durationOverride) or tonumber(wallPart:GetAttribute("BreakGradientDuration")) or 0.35, 0.035, 2)
	local gradients = getWallGradients(wallPart)
	if #gradients == 0 then return 0 end
	local state = wallGradientStates[wallPart]
	if state and state.running then return duration end
	state = state or {snapshots = {}}
	state.running = true
	state.cancelled = false
	wallGradientStates[wallPart] = state
	for _, gradient in ipairs(gradients) do
		if gradient and gradient.Parent and not state.snapshots[gradient] then
			state.snapshots[gradient] = gradient.Color
		end
	end
	task.spawn(function()
		local startedAt = os.clock()
		while wallPart.Parent and not state.cancelled do
			local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
			for gradient, originalColor in pairs(state.snapshots) do
				if gradient and gradient.Parent then
					gradient.Color = blendSequenceToWhite(originalColor, alpha)
				end
			end
			if alpha >= 1 then break end
			task.wait()
		end
		state.running = false
	end)
	return duration
end

local function resetWallGradient(wallPart)
	local state = wallGradientStates[wallPart]
	if not state then return end
	state.cancelled = true
	for gradient, originalColor in pairs(state.snapshots or {}) do
		if gradient and gradient.Parent then
			gradient.Color = originalColor
		end
	end
	wallGradientStates[wallPart] = nil
end

local function applyLocalWallBreakVisual(wallPart, visualDuration)
	if not wallPart or not wallPart:IsA("BasePart") then return end
	if not modifiedWalls[wallPart] then
		modifiedWalls[wallPart] = {
			localTransparencyModifier = wallPart.LocalTransparencyModifier,
			canCollide = wallPart.CanCollide,
			surfaceGuis = snapshotWallSurfaceGuis(wallPart),
		}
	end
	wallPart.CanCollide = false
	local hideDelay = animateWallGradientBreak(wallPart, visualDuration)
	task.delay(hideDelay, function()
		if wallPart and wallPart.Parent and modifiedWalls[wallPart] then
			wallPart.LocalTransparencyModifier = 1
			setWallSurfaceGuisEnabled(wallPart, false)
		end
	end)
end

local function resetLocalWalls()
	for wallPart, snapshot in pairs(modifiedWalls) do
		if wallPart and wallPart.Parent then
			resetWallGradient(wallPart)
			wallPart.LocalTransparencyModifier = snapshot.localTransparencyModifier or 0
			wallPart.CanCollide = snapshot.canCollide == true
			for surfaceGui, wasEnabled in pairs(snapshot.surfaceGuis or {}) do
				if surfaceGui and surfaceGui.Parent then
					surfaceGui.Enabled = wasEnabled == true
				end
			end
		end
		modifiedWalls[wallPart] = nil
	end
end


setBreakWallFramesVisible(false)
CollectionService:GetInstanceAddedSignal(BREAK_WALL_TAG):Connect(function(inst)
	if inst:IsA("BasePart") then
		setWallFrameVisible(inst, runnerActive)
	end
end)
workspaceService.DescendantAdded:Connect(function(inst)
	if inst:IsA("BasePart") and inst.Name == BREAK_WALL_NAME then
		setWallFrameVisible(inst, runnerActive)
	end
end)


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
	if not runnerActive or jumpingNow or stumblingNow or exhaustedNow or wallBreakingNow then return end
	actionRemote:FireServer("Jump")
end)

goBackButton.Activated:Connect(function()
	if not runnerActive or jumpingNow or stumblingNow or wallBreakingNow then return end
	if exhaustedNow and exhaustionPhase ~= "Collapsed" then return end
	actionRemote:FireServer("GoBack")
end)

local pendingEntries = {}

local function renderPendingCases()
	if not pendingCasesFrame or not pendingTemplate then return end
	for _, child in ipairs(pendingCasesFrame:GetChildren()) do
		if child:IsA("Frame") and child ~= pendingTemplate then child:Destroy() end
	end
	pendingTemplate.Visible = false
	pendingCasesFrame.Visible = (#pendingEntries > 0)
	for _, entry in ipairs(pendingEntries) do
		local card = pendingTemplate:Clone()
		card.Name = entry.id
		card.Visible = true
		card.Parent = pendingCasesFrame
		local image = card:FindFirstChildWhichIsA("ImageLabel", true)
		if image and entry.image and entry.image ~= "" then image.Image = entry.image end
		local btn = card:FindFirstChild("ClaimButton", true)
		if btn and btn:IsA("GuiButton") then
			btn.MouseButton1Click:Connect(function()
				actionRemote:FireServer("ClaimPendingCase", entry.id)
			end)
		end
	end
end

local function refreshPendingCasesVisibility()
	if not pendingCasesFrame then return end
	if pendingCasesDefaultSize then
		pendingCasesFrame.Size = pendingCasesDefaultSize
	end
	-- Keep hidden during sprint HUD state changes; the pending list is for out-of-run claiming.
	if runnerActive then
		pendingCasesFrame.Visible = false
		return
	end
	pendingCasesFrame.Visible = (#pendingEntries > 0)
end

stateRemote.OnClientEvent:Connect(function(action, enabled, payload)
	if action == "PendingCasesUpdate" then
		pendingEntries = (typeof(enabled) == "table" and enabled) or ((typeof(payload) == "table" and payload) or {})
		renderPendingCases()
		refreshPendingCasesVisibility()
	elseif action == "CaseClaimResult" then
		-- animation is handled by MainClientScript via CaseHatchEvent
	elseif action == "RunnerState" then
		runnerActive = enabled == true
		gui.Enabled = runnerActive
		staminaFrame.Visible = runnerActive
		refreshGameUiSuppression()

		if not runnerActive then
			jumpingNow = false
			stumblingNow = false
			exhaustedNow = false
			exhaustionPhase = nil
			waitingForJumpAnimEnd = false
			resetLocalWalls()
			setBreakWallFramesVisible(false)
			clearAllTracks()
			staminaCurrent = 0
			staminaMax = 50
			renderStamina(false)
			updateControlsLocked()
			restoreRunnerCamera()
			refreshPendingCasesVisibility()
			return
		end
		staminaCurrent = (payload and payload.currentStamina) or staminaMax
		staminaMax = (payload and payload.maxStamina) or staminaMax
		exhaustedNow = false
		exhaustionPhase = nil
		wallBreakingNow = false
		wallBreakSuccessNow = false
		renderStamina(false)
		setBreakWallFramesVisible(true)

		clearAllTracks()

		runTrack = loadTrack(payload and payload.runAnimationId)
		if runTrack then
			runTrack.Looped = true
			runTrack:Play(0.1)
		end

		stumbleTrack = loadTrack(payload and (payload.stumbleAnimationId or payload.jumpSlideAnimationId or payload.jumpAnimationId))
		jumpStartTrack = loadTrack(payload and (payload.jumpStartAnimationId or payload.jumpAnimationId))
		jumpSlideTrack = loadTrack(payload and (payload.jumpSlideAnimationId or payload.jumpAnimationId))
		exhaustedSlideTrack = loadTrack(payload and payload.exhaustedSlideAnimationId)
		exhaustedLoopTrack = loadTrack(payload and payload.exhaustedLoopAnimationId)
		wallBreakSuccessTrack = loadTrack(payload and payload.breakSuccessAnimationId)
		wallBreakFailTrack = loadTrack(payload and payload.breakFailAnimationId)

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
		if exhaustedNow then
			return
		end

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
		if exhaustedNow then
			return
		end
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
		
	elseif action == "ExhaustionState" then
		local isExhausted = enabled == true
		if not isExhausted then
			exhaustedNow = false
			exhaustionPhase = nil
			wallBreakingNow = false
			wallBreakSuccessNow = false
			if exhaustedSlideTrack then stopTrack(exhaustedSlideTrack) end
			if exhaustedLoopTrack then stopTrack(exhaustedLoopTrack) end
			if runnerActive and not jumpingNow and not stumblingNow and runTrack then
				runTrack.Looped = true
				runTrack:Play(0.08)
			end
			updateControlsLocked()
			return
		end

		exhaustedNow = true
		jumpingNow = false
		stumblingNow = false
		waitingForJumpAnimEnd = false
		exhaustionPhase = payload and payload.phase or exhaustionPhase or "Slide"
		updateControlsLocked()

		if runTrack then stopTrack(runTrack) end
		if jumpStartTrack then stopTrack(jumpStartTrack) end
		if jumpSlideTrack then stopTrack(jumpSlideTrack) end
		if stumbleTrack then stopTrack(stumbleTrack) end

		if exhaustionPhase == "Collapsed" then
			if exhaustedSlideTrack then stopTrack(exhaustedSlideTrack) end
			if exhaustedLoopTrack then
				exhaustedLoopTrack.Looped = true
				exhaustedLoopTrack:Play(0.08)
			end
		else
			if exhaustedLoopTrack then stopTrack(exhaustedLoopTrack) end
			if exhaustedSlideTrack and not exhaustedSlideTrack.IsPlaying then
				exhaustedSlideTrack.Looped = false
				exhaustedSlideTrack:Play(0.06)
			end
		end
		
	elseif action == "WallBreakState" then
		local active = enabled == true
		if not active then
			wallBreakingNow = false
			wallBreakSuccessNow = false
			if wallBreakTrackStoppedConn then
				wallBreakTrackStoppedConn:Disconnect()
				wallBreakTrackStoppedConn = nil
			end
			if wallBreakMarkerConn then
				wallBreakMarkerConn:Disconnect()
				wallBreakMarkerConn = nil
			end
			if wallBreakKeyframeConn then
				wallBreakKeyframeConn:Disconnect()
				wallBreakKeyframeConn = nil
			end
			if wallBreakSuccessTrack then stopTrack(wallBreakSuccessTrack) end
			if wallBreakFailTrack then stopTrack(wallBreakFailTrack) end
			if runnerActive and not jumpingNow and not stumblingNow and not exhaustedNow and runTrack then
				runTrack.Looped = true
				runTrack:Play(0.08)
			end
			updateControlsLocked()
			return
		end

		wallBreakingNow = true
		wallBreakSuccessNow = payload and payload.success == true
		updateControlsLocked()

		local phase = payload and payload.phase
		if phase == "Animating" then
			if runTrack then stopTrack(runTrack) end
			if jumpStartTrack then stopTrack(jumpStartTrack) end
			if jumpSlideTrack then stopTrack(jumpSlideTrack) end
			if stumbleTrack then stopTrack(stumbleTrack) end

			if wallBreakSuccessNow and payload and payload.wallPart then
				applyLocalWallBreakVisual(payload.wallPart, payload.breakVisualDuration)
			end

			if payload and payload.successAnimationId then
				wallBreakSuccessTrack = loadTrack(payload.successAnimationId) or wallBreakSuccessTrack
			end
			if payload and payload.failedAnimationId then
				wallBreakFailTrack = loadTrack(payload.failedAnimationId) or wallBreakFailTrack
			end

			if wallBreakTrackStoppedConn then
				wallBreakTrackStoppedConn:Disconnect()
				wallBreakTrackStoppedConn = nil
			end
			if wallBreakMarkerConn then
				wallBreakMarkerConn:Disconnect()
				wallBreakMarkerConn = nil
			end
			if wallBreakKeyframeConn then
				wallBreakKeyframeConn:Disconnect()
				wallBreakKeyframeConn = nil
			end

			local selectedTrack = wallBreakSuccessNow and wallBreakSuccessTrack or wallBreakFailTrack
			if selectedTrack then
				selectedTrack.Looped = false
				selectedTrack:Play(0.05)
				wallBreakTrackStoppedConn = selectedTrack.Stopped:Connect(function()
					actionRemote:FireServer("WallBreakAnimEnded")
				end)
				if not wallBreakSuccessNow then
					wallBreakMarkerConn = selectedTrack:GetMarkerReachedSignal("Knockback"):Connect(function()
						actionRemote:FireServer("WallBreakFailMarker")
					end)
					wallBreakKeyframeConn = selectedTrack.KeyframeReached:Connect(function(keyframeName)
						if keyframeName == "Knockback" then
							actionRemote:FireServer("WallBreakFailMarker")
						end
					end)
				end
			else
				actionRemote:FireServer("WallBreakAnimEnded")
			end
		end
	end
end)

if pendingCasesFrame then
	pendingCasesFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		-- If another UI flow hides this frame, restore it when it should be visible.
		if not runnerActive and #pendingEntries > 0 and pendingCasesFrame.Visible == false then
			task.defer(refreshPendingCasesVisibility)
		end
	end)
end

petInteractionUiRemote.OnClientEvent:Connect(function(hidden)
	petInteractionUiHidden = hidden == true
	refreshGameUiSuppression()
end)

player.CharacterAdded:Connect(function()
	if runnerActive then
		task.defer(setRunnerCameraToHead)
	end
end)

-- In case server sent PendingCasesUpdate before this LocalScript bound events, request a fresh sync.
task.defer(function()
	actionRemote:FireServer("RequestPendingCasesSync")
end)

