local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera
local showerRemote = ReplicatedStorage:WaitForChild("ShowerMinigameEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "ShowerMinigameGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -30, 0.5, 0)
panel.Size = UDim2.new(0, 260, 0, 170)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.Active = true
panel.ZIndex = 10
panel.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 12, 0, 8)
title.Size = UDim2.new(1, -24, 0, 28)
title.Font = Enum.Font.SourceSansBold
title.TextSize = 22
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Shower"
title.ZIndex = 11
title.Parent = panel
title.Size = UDim2.new(1, -64, 0, 28)

local stageLabel = Instance.new("TextLabel")
stageLabel.Name = "StageLabel"
stageLabel.BackgroundTransparency = 1
stageLabel.Position = UDim2.new(0, 12, 0, 38)
stageLabel.Size = UDim2.new(1, -24, 0, 24)
stageLabel.Font = Enum.Font.SourceSansSemibold
stageLabel.TextSize = 18
stageLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
stageLabel.TextXAlignment = Enum.TextXAlignment.Left
stageLabel.Text = "Scrub with Sponge"
stageLabel.ZIndex = 11
stageLabel.Parent = panel

local barBg = Instance.new("Frame")
barBg.Name = "BarBg"
barBg.Position = UDim2.new(0, 12, 0, 72)
barBg.Size = UDim2.new(1, -24, 0, 24)
barBg.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
barBg.BorderSizePixel = 0
barBg.Parent = panel

local barFill = Instance.new("Frame")
barFill.Name = "BarFill"
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
barFill.BorderSizePixel = 0
barFill.ZIndex = 12
barFill.Parent = barBg

local percentLabel = Instance.new("TextLabel")
percentLabel.Name = "Percent"
percentLabel.BackgroundTransparency = 1
percentLabel.Size = UDim2.new(1, 0, 1, 0)
percentLabel.Font = Enum.Font.SourceSansBold
percentLabel.TextSize = 16
percentLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
percentLabel.Text = "0%"
percentLabel.ZIndex = 13
percentLabel.Parent = barBg

local rotateLabel = Instance.new("TextLabel")
rotateLabel.Name = "RotateLabel"
rotateLabel.BackgroundTransparency = 1
rotateLabel.Position = UDim2.new(0, 12, 0, 105)
rotateLabel.Size = UDim2.new(1, -24, 0, 22)
rotateLabel.Font = Enum.Font.SourceSansSemibold
rotateLabel.TextSize = 18
rotateLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
rotateLabel.TextXAlignment = Enum.TextXAlignment.Left
rotateLabel.Text = "Rotate Pet"
rotateLabel.ZIndex = 11
rotateLabel.Parent = panel

local rotateLeft = Instance.new("TextButton")
rotateLeft.Name = "RotateLeft"
rotateLeft.Position = UDim2.new(0, 12, 0, 132)
rotateLeft.Size = UDim2.new(0.5, -18, 0, 28)
rotateLeft.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
rotateLeft.TextColor3 = Color3.new(1, 1, 1)
rotateLeft.Font = Enum.Font.SourceSansBold
rotateLeft.TextSize = 20
rotateLeft.Text = "⟵"
rotateLeft.AutoButtonColor = false
rotateLeft.Active = true
rotateLeft.Selectable = true
rotateLeft.ZIndex = 12
rotateLeft.Parent = panel

local rotateRight = Instance.new("TextButton")
rotateRight.Name = "RotateRight"
rotateRight.Position = UDim2.new(0.5, 6, 0, 132)
rotateRight.Size = UDim2.new(0.5, -18, 0, 28)
rotateRight.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
rotateRight.TextColor3 = Color3.new(1, 1, 1)
rotateRight.Font = Enum.Font.SourceSansBold
rotateRight.TextSize = 20
rotateRight.Text = "⟶"
rotateRight.AutoButtonColor = false
rotateRight.Active = true 
rotateRight.Selectable = true
rotateRight.ZIndex = 12
rotateRight.Parent = panel

local exitButton = Instance.new("TextButton")
exitButton.Name = "ExitButton"
exitButton.AnchorPoint = Vector2.new(1, 0)
exitButton.Position = UDim2.new(1, -12, 0, 10)
exitButton.Size = UDim2.new(0, 28, 0, 24)
exitButton.BackgroundColor3 = Color3.fromRGB(130, 50, 50)
exitButton.TextColor3 = Color3.new(1, 1, 1)
exitButton.Font = Enum.Font.SourceSansBold
exitButton.TextSize = 18
exitButton.Text = "X"
exitButton.AutoButtonColor = true
exitButton.ZIndex = 12
exitButton.Parent = panel
exitButton.Visible = false


local savedCameraType = nil
local savedCameraSubject = nil
local cameraPart = nil
local controlWall = nil
local currentPet = nil
local cameraConn = nil
local cursorTrackConn = nil
local lastToolMoveFireAt = 0
local lastToolMovePoint = nil
local lastExitFireAt = 0
local pointerScreenPos = nil
local activeTouch = nil
local isTouchDragging = false
local currentStage = 1
local localToolVisuals = {}
local localSpongeOriginal = nil
local localShowerHeadOriginal = nil
local originalVisualSnapshots = {}
local lastLocalToolPos = nil
local lastLocalToolNormal = nil
local localArmPose = nil
local localPetBasePivot = nil
local localPetRubOffset = Vector3.zero
local localPetRubTilt = Vector3.zero
local lastLocalRubWorldPos = nil
local lastLocalRubAt = nil

local function clearCameraFollow()
	if cameraConn then
		cameraConn:Disconnect()
		cameraConn = nil
	end
end

local function clearCursorTracking()
	if cursorTrackConn then
		cursorTrackConn:Disconnect()
		cursorTrackConn = nil
	end
end

local function getToolHandle(toolInstance)
	if not toolInstance then return nil end
	if toolInstance:IsA("BasePart") then
		return toolInstance
	end
	if toolInstance:IsA("Model") then
		return toolInstance.PrimaryPart or toolInstance:FindFirstChild("Handle", true) or toolInstance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function prepareLocalVisualInstance(instance)
	if instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript") then
		instance:Destroy()
		return false
	end
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanQuery = false
		instance.CanTouch = false
		instance.Massless = true
		instance.LocalTransparencyModifier = 0
	end
	return true
end

local function setOriginalToolLocalHidden(toolInstance, hidden)
	if not toolInstance then return end
	local parts = {}
	if toolInstance:IsA("BasePart") then
		table.insert(parts, toolInstance)
	elseif toolInstance:IsA("Model") then
		for _, d in ipairs(toolInstance:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(parts, d) end
		end
	end
	for _, part in ipairs(parts) do
		if originalVisualSnapshots[part] == nil then
			originalVisualSnapshots[part] = part.LocalTransparencyModifier
		end
		part.LocalTransparencyModifier = hidden and 1 or (originalVisualSnapshots[part] or 0)
	end
end

local function cloneLocalToolVisual(toolInstance)
	if not toolInstance then return nil end
	local clone = toolInstance:Clone()
	clone.Name = "LocalShower" .. tostring(toolInstance.Name)
	for _, d in ipairs(clone:GetDescendants()) do
		prepareLocalVisualInstance(d)
	end
	prepareLocalVisualInstance(clone)
	if clone:IsA("Model") and not clone.PrimaryPart then
		local handle = getToolHandle(clone)
		if handle then
			pcall(function() clone.PrimaryPart = handle end)
		end
	end
	clone.Parent = workspace.CurrentCamera or workspace
	return clone
end

local function cleanupLocalArmPose()
	if not localArmPose then return end
	if localArmPose.ikControl then
		pcall(function()
			localArmPose.ikControl.Enabled = false
			localArmPose.ikControl:Destroy()
		end)
	end
	if localArmPose.targetPart then
		pcall(function() localArmPose.targetPart:Destroy() end)
	end
	localArmPose = nil
end

local function setupLocalArmPose()
	cleanupLocalArmPose()
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local endEffector = character:FindFirstChild("RightHand") or character:FindFirstChild("RightLowerArm") or character:FindFirstChild("Right Arm")
	-- Keep the IK chain rooted in the arm so the whole character body does not twist.
	local chainRoot = character:FindFirstChild("RightUpperArm") or character:FindFirstChild("Right Arm") or character:FindFirstChild("UpperTorso")
	if not endEffector or not chainRoot or not endEffector:IsA("BasePart") or not chainRoot:IsA("BasePart") then return end

	local targetPart = Instance.new("Part")
	targetPart.Name = "LocalShowerToolIKTarget"
	targetPart.Size = Vector3.new(0.2, 0.2, 0.2)
	targetPart.Transparency = 1
	targetPart.CanCollide = false
	targetPart.CanQuery = false
	targetPart.CanTouch = false
	targetPart.Anchored = true
	targetPart.Parent = workspace.CurrentCamera or workspace

	local attachment = Instance.new("Attachment")
	attachment.Name = "LocalShowerToolIKTargetAttachment"
	attachment.Parent = targetPart

	local ikControl = Instance.new("IKControl")
	ikControl.Name = "LocalShowerToolIK"
	ikControl.Type = Enum.IKControlType.Position
	ikControl.ChainRoot = chainRoot
	ikControl.EndEffector = endEffector
	ikControl.Target = attachment
	ikControl.Priority = 100
	ikControl.Weight = 0.9
	ikControl.SmoothTime = 0.08
	ikControl.Enabled = true
	ikControl.Parent = humanoid

	localArmPose = { targetPart = targetPart, ikControl = ikControl }
end

local function updateLocalArmPose(toolWorldPos, toolNormal)
	if not localArmPose or not localArmPose.targetPart or not toolWorldPos then return end
	local normal = toolNormal
	if typeof(normal) ~= "Vector3" or normal.Magnitude < 1e-4 then
		normal = Vector3.new(0, 1, 0)
	end
	local targetPos = toolWorldPos - (normal.Unit * 0.26)
	localArmPose.targetPart.CFrame = CFrame.lookAt(targetPos, targetPos + normal.Unit)
end

local function cleanupLocalShowerVisuals()
	for original, visual in pairs(localToolVisuals) do
		if visual then pcall(function() visual:Destroy() end) end
		setOriginalToolLocalHidden(original, false)
	end
	for part, localTransparency in pairs(originalVisualSnapshots) do
		if part and part.Parent then
			part.LocalTransparencyModifier = localTransparency or 0
		end
	end
	localToolVisuals = {}
	localSpongeOriginal = nil
	localShowerHeadOriginal = nil
	originalVisualSnapshots = {}
	lastLocalToolPos = nil
	lastLocalToolNormal = nil
	localPetBasePivot = nil
	localPetRubOffset = Vector3.zero
	localPetRubTilt = Vector3.zero
	lastLocalRubWorldPos = nil
	lastLocalRubAt = nil
	cleanupLocalArmPose()
end

local function setupLocalShowerVisuals(payload)
	cleanupLocalShowerVisuals()
	localSpongeOriginal = payload.spongeTool or payload.spongePart
	localShowerHeadOriginal = payload.showerHeadTool or payload.showerHeadPart
	for _, original in ipairs({ localSpongeOriginal, localShowerHeadOriginal }) do
		if original then
			local visual = cloneLocalToolVisual(original)
			if visual then
				localToolVisuals[original] = visual
				setOriginalToolLocalHidden(original, true)
			end
		end
	end
	setupLocalArmPose()
end

local function getLocalActiveOriginalTool()
	if currentStage == 1 and localSpongeOriginal and localToolVisuals[localSpongeOriginal] then
		return localSpongeOriginal
	end
	if currentStage ~= 1 and localShowerHeadOriginal and localToolVisuals[localShowerHeadOriginal] then
		return localShowerHeadOriginal
	end
	for original in pairs(localToolVisuals) do return original end
	return nil
end

local function getLocalToolHalfThickness(toolInstance)
	local handle = getToolHandle(toolInstance)
	if handle then
		return math.max(handle.Size.X, handle.Size.Y, handle.Size.Z) * 0.5
	end
	return 0.6
end

local function moveLocalToolToPosition(toolInstance, worldPos, surfaceNormal)
	local visual = toolInstance and localToolVisuals[toolInstance]
	if not visual or not worldPos then return end
	local normal = surfaceNormal
	if typeof(normal) ~= "Vector3" or normal.Magnitude < 1e-4 then
		normal = lastLocalToolNormal or Vector3.new(0, 1, 0)
	end
	normal = normal.Unit
	local up = normal
	local right = Vector3.new(0, 1, 0):Cross(up)
	if right.Magnitude < 1e-4 then
		right = Vector3.new(1, 0, 0):Cross(up)
	end
	right = right.Unit
	local cf = CFrame.fromMatrix(worldPos, right, up)
	if visual:IsA("Model") then
		local handle = getToolHandle(visual)
		if handle then
			local relative = visual:GetPivot():ToObjectSpace(handle.CFrame)
			visual:PivotTo(cf * relative:Inverse())
		else
			visual:PivotTo(cf)
		end
	elseif visual:IsA("BasePart") then
		visual.CFrame = cf
	end
	updateLocalArmPose(worldPos, normal)
end

local function applyLocalPetRub(targetSurfacePos, targetSurfaceNormal, isTouchingPet)
	if not currentPet or not currentPet.Parent then return end
	localPetBasePivot = localPetBasePivot or currentPet:GetPivot()
	local now = tick()
	if isTouchingPet and typeof(targetSurfacePos) == "Vector3" then
		local normal = targetSurfaceNormal
		if typeof(normal) ~= "Vector3" or normal.Magnitude < 1e-4 then
			normal = Vector3.new(0, 1, 0)
		else
			normal = normal.Unit
		end
		local dt = math.max(now - (lastLocalRubAt or now), 1 / 240)
		local dragIntensity = 0.55
		if lastLocalRubWorldPos then
			dragIntensity = math.clamp(((targetSurfacePos - lastLocalRubWorldPos).Magnitude / dt) / 22, 0.35, 1)
		end
		lastLocalRubWorldPos = targetSurfacePos
		lastLocalRubAt = now

		localPetRubOffset = localPetRubOffset:Lerp(-normal * (0.07 + (0.05 * dragIntensity)), 0.48)
		local petPivot = currentPet:GetPivot()
		local localHit = petPivot:PointToObjectSpace(targetSurfacePos)
		local tiltX = math.clamp(-localHit.Z * 0.011, -0.06, 0.06)
		local tiltZ = math.clamp(localHit.X * 0.011, -0.06, 0.06)
		localPetRubTilt = localPetRubTilt:Lerp(Vector3.new(tiltX, 0, tiltZ), 0.4)
	else
		lastLocalRubWorldPos = nil
		lastLocalRubAt = now
		localPetRubOffset = localPetRubOffset:Lerp(Vector3.zero, 0.22)
		localPetRubTilt = localPetRubTilt:Lerp(Vector3.zero, 0.18)
	end

	currentPet:PivotTo(localPetBasePivot * CFrame.new(localPetRubOffset) * CFrame.Angles(localPetRubTilt.X, 0, localPetRubTilt.Z))
end

local function suppressLocalServerShowerLoop(animationId)
	if type(animationId) ~= "string" or animationId == "" then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	local expectedDigits = string.match(animationId, "%d+")
	if not expectedDigits then return end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local trackAnimation = track.Animation
		local trackDigits = trackAnimation and string.match(tostring(trackAnimation.AnimationId or ""), "%d+")
		if track.Name == "ShowerLoopAnimation" or (trackDigits and trackDigits == expectedDigits) then
			pcall(function() track:Stop(0.05) end)
		end
	end
end

local function rotateLocalPet(direction)
	if not currentPet or not currentPet.Parent then return end
	local rotationStep = math.rad(90) * ((direction or 0) >= 0 and 1 or -1)
	pcall(function()
		localPetBasePivot = (localPetBasePivot or currentPet:GetPivot()) * CFrame.Angles(0, rotationStep, 0)
		currentPet:PivotTo(localPetBasePivot * CFrame.new(localPetRubOffset) * CFrame.Angles(localPetRubTilt.X, 0, localPetRubTilt.Z))
	end)
end

local function endShowerView()
	clearCameraFollow()
	clearCursorTracking()
	cleanupLocalShowerVisuals()
	if savedCameraType then
		camera.CameraType = savedCameraType
		savedCameraType = nil
	end
	if savedCameraSubject then
		camera.CameraSubject = savedCameraSubject
		savedCameraSubject = nil
	end
	cameraPart = nil
	controlWall = nil
	currentPet = nil
	gui.Enabled = false
	exitButton.Visible = false
end

local function startShowerView(targetCameraPart)
	if not targetCameraPart or not targetCameraPart:IsA("BasePart") then
		return
	end

	savedCameraType = camera.CameraType
	savedCameraSubject = camera.CameraSubject
	cameraPart = targetCameraPart

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = targetCameraPart.CFrame

	clearCameraFollow()
	cameraConn = RunService.RenderStepped:Connect(function()
		if cameraPart and cameraPart.Parent then
			local baseCFrame = cameraPart.CFrame
			local viewport = camera.ViewportSize
			local nx = 0
			local ny = 0
			if viewport.X > 0 and viewport.Y > 0 then
				nx = ((mouse.X / viewport.X) - 0.5) * 2
				ny = ((mouse.Y / viewport.Y) - 0.5) * 2
			end
			nx = math.clamp(nx, -1, 1)
			ny = math.clamp(ny, -1, 1)

			local yaw = math.rad(nx * 4.5)
			local pitch = math.rad(-ny * 2.8)
			local localOffset = Vector3.new(nx * 0.15, -ny * 0.08, 0)
			camera.CFrame = baseCFrame * CFrame.new(localOffset) * CFrame.Angles(pitch, yaw, 0)
		end
	end)
end

local function updateBar(progress)
	progress = math.clamp(tonumber(progress) or 0, 0, 1)
	barFill.Size = UDim2.new(progress, 0, 1, 0)
	percentLabel.Text = ("%d%%"):format(math.floor(progress * 100 + 0.5))
end

local function getMovePoint(screenPos)
	local x = (screenPos and screenPos.X) or mouse.X
	local y = (screenPos and screenPos.Y) or mouse.Y
	local ray = camera:ViewportPointToRay(x, y)
	if currentPet and currentPet.Parent then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {currentPet}
		local hitPet = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
		if hitPet then
			return {
				worldPos = hitPet.Position + (hitPet.Normal * 0.02),
				hitPet = true,
				surfaceNormal = hitPet.Normal,
			}
		end
	end

	if controlWall and controlWall:IsA("BasePart") then
		local wallCf = controlWall.CFrame
		local normal = wallCf.LookVector
		local originToWall = wallCf.Position - ray.Origin
		local denom = ray.Direction:Dot(normal)
		if math.abs(denom) > 1e-4 then
			local distance = originToWall:Dot(normal) / denom
			if distance > 0 then
				return {
					worldPos = ray.Origin + (ray.Direction * distance),
					hitPet = false,
				}
			end
		end
	end

	if mouse and mouse.Hit then
		return {
			worldPos = mouse.Hit.Position,
			hitPet = false,
		}
	end

	return nil
end

local function startCursorTracking()
	clearCursorTracking()
	cursorTrackConn = RunService.RenderStepped:Connect(function()
		if not gui.Enabled then return end
		local mousePos = pointerScreenPos or UserInputService:GetMouseLocation()
		local isOverPanel = mousePos and (
			mousePos.X >= panel.AbsolutePosition.X
				and mousePos.X <= (panel.AbsolutePosition.X + panel.AbsoluteSize.X)
				and mousePos.Y >= panel.AbsolutePosition.Y
				and mousePos.Y <= (panel.AbsolutePosition.Y + panel.AbsoluteSize.Y)
		)
		if isOverPanel then return end

		local now = tick()
		local movePoint = getMovePoint(mousePos)
		if not movePoint then return end
		local worldPos = movePoint.worldPos
		if typeof(worldPos) ~= "Vector3" then return end

		local activeOriginalTool = getLocalActiveOriginalTool()
		if activeOriginalTool then
			local normal = movePoint.surfaceNormal
			if typeof(normal) ~= "Vector3" or normal.Magnitude < 1e-4 then
				normal = lastLocalToolNormal or Vector3.new(0, 1, 0)
			end
			normal = normal.Unit
			local toolOffset = math.clamp(getLocalToolHalfThickness(activeOriginalTool) * 0.65, 0.18, 0.4)
			local desiredPos = movePoint.hitPet and (worldPos + (normal * toolOffset)) or worldPos
			if lastLocalToolPos then
				desiredPos = lastLocalToolPos:Lerp(desiredPos, movePoint.hitPet and 0.85 or 0.55)
			end
			lastLocalToolPos = desiredPos
			lastLocalToolNormal = normal
			moveLocalToolToPosition(activeOriginalTool, desiredPos, normal)
		end

		local hasMovedEnough = (not lastToolMovePoint) or ((worldPos - lastToolMovePoint).Magnitude >= 0.04)
		if not hasMovedEnough and (now - lastToolMoveFireAt) < 0.06 then
			return
		end
		if (now - lastToolMoveFireAt) < 0.02 then return end
		lastToolMoveFireAt = now
		lastToolMovePoint = worldPos

		if worldPos then
			showerRemote:FireServer("ToolMove", {
				worldPos = worldPos,
				hitPet = movePoint.hitPet == true,
				surfaceNormal = movePoint.surfaceNormal,
			})
		end
	end)
end

local defaultRotateButtonColor = Color3.fromRGB(70, 70, 70)
local pressedRotateButtonColor = Color3.fromRGB(110, 110, 110)

local function pulseButton(button)
	if not button then return end
	button.BackgroundColor3 = pressedRotateButtonColor
	local tween = TweenService:Create(
		button,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundColor3 = defaultRotateButtonColor }
	)
	tween:Play()
end

local lastRotateFireAt = 0
local function fireRotate(direction, button)
	if not gui.Enabled then return end
	local now = tick()
	if (now - lastRotateFireAt) < 0.08 then return end
	lastRotateFireAt = now
	pulseButton(button)
	rotateLocalPet(direction)
	showerRemote:FireServer("Rotate", { direction = direction })
end

local function hookRotateButton(button, direction)
	button.MouseButton1Down:Connect(function()
		button.BackgroundColor3 = pressedRotateButtonColor
	end)
	button.MouseButton1Up:Connect(function()
		button.BackgroundColor3 = defaultRotateButtonColor
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = defaultRotateButtonColor
	end)
	button.Activated:Connect(function()
		fireRotate(direction, button)
	end)
	button.MouseButton1Click:Connect(function()
		fireRotate(direction, button)
	end)
end

hookRotateButton(rotateLeft, -1)
hookRotateButton(rotateRight, 1)

exitButton.Activated:Connect(function()
	if gui.Enabled then
		local now = tick()
		if (now - lastExitFireAt) < 0.2 then return end
		lastExitFireAt = now
		showerRemote:FireServer("Exit", {})
		endShowerView()
	end
end)


local function isPointInsideButton(button, screenPos)
	if not button or not button.Visible then return false end
	local pos = button.AbsolutePosition
	local size = button.AbsoluteSize
	return screenPos.X >= pos.X
		and screenPos.X <= (pos.X + size.X)
		and screenPos.Y >= pos.Y
		and screenPos.Y <= (pos.Y + size.Y)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not gui.Enabled then return end
	if not gui.Enabled then return end
	local isPointerPress = input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	if not isPointerPress then return end

	local inputPos = input.Position or UserInputService:GetMouseLocation()
	if not inputPos then return end

	if isPointInsideButton(rotateLeft, inputPos) then
		fireRotate(-1, rotateLeft)
	elseif isPointInsideButton(rotateRight, inputPos) then
		fireRotate(1, rotateRight)
	elseif gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.Touch then
		activeTouch = input
		isTouchDragging = true
		pointerScreenPos = inputPos
	end
end)	

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed or not gui.Enabled then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		pointerScreenPos = input.Position
		return
	end
	if input.UserInputType == Enum.UserInputType.Touch and activeTouch and input == activeTouch and isTouchDragging then
		pointerScreenPos = input.Position
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch and activeTouch and input == activeTouch then
		activeTouch = nil
		isTouchDragging = false
		pointerScreenPos = nil
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		pointerScreenPos = nil
	end
end)

showerRemote.OnClientEvent:Connect(function(action, payload)
	payload = payload or {}

	if action == "Start" then
		gui.Enabled = true
		pointerScreenPos = nil
		activeTouch = nil
		isTouchDragging = false
		lastRotateFireAt = 0
		lastToolMoveFireAt = 0
		lastToolMovePoint = nil
		currentStage = tonumber(payload.stage) or 1
		stageLabel.Text = tostring(payload.stageText or "Scrub with Sponge")
		updateBar(payload.progress or 0)
		controlWall = payload.controlWall
		currentPet = payload.pet
		localPetBasePivot = currentPet and currentPet:GetPivot() or nil
		setupLocalShowerVisuals(payload)
		task.defer(suppressLocalServerShowerLoop, payload.serverLoopAnimationId)
		task.delay(0.25, suppressLocalServerShowerLoop, payload.serverLoopAnimationId)
		task.delay(0.75, suppressLocalServerShowerLoop, payload.serverLoopAnimationId)
		startShowerView(payload.cameraPart)
		startCursorTracking()
	elseif action == "Progress" then
		if payload.stageText then
			stageLabel.Text = tostring(payload.stageText)
		end
		updateBar(payload.progress or 0)
	elseif action == "Stage" then
		currentStage = tonumber(payload.stage) or currentStage
		lastLocalToolPos = nil
		if payload.stageText then
			stageLabel.Text = tostring(payload.stageText)
		end
		updateBar(payload.progress or 0)
	elseif action == "End" then
		endShowerView()
		pointerScreenPos = nil
		activeTouch = nil
		isTouchDragging = false
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.2)
	endShowerView()
end)
