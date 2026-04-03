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


local savedCameraType = nil
local savedCameraSubject = nil
local cameraPart = nil
local controlWall = nil
local currentPet = nil
local cameraConn = nil
local cursorTrackConn = nil
local lastToolMoveFireAt = 0
local lastToolMovePoint = nil

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

local function endShowerView()
	clearCameraFollow()
	clearCursorTracking()
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
			camera.CFrame = cameraPart.CFrame
		end
	end)
end

local function updateBar(progress)
	progress = math.clamp(tonumber(progress) or 0, 0, 1)
	barFill.Size = UDim2.new(progress, 0, 1, 0)
	percentLabel.Text = ("%d%%"):format(math.floor(progress * 100 + 0.5))
end

local function getMovePoint()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	if currentPet and currentPet.Parent then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {currentPet}
		local hitPet = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
		if hitPet then
			return hitPet.Position + (hitPet.Normal * 0.02)
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
				return ray.Origin + (ray.Direction * distance)
			end
		end
	end

	if mouse and mouse.Hit then
		return mouse.Hit.Position
	end

	return nil
end

local function startCursorTracking()
	clearCursorTracking()
	cursorTrackConn = RunService.RenderStepped:Connect(function()
		if not gui.Enabled then return end
		local mousePos = UserInputService:GetMouseLocation()
		local isOverPanel = mousePos and (
			mousePos.X >= panel.AbsolutePosition.X
				and mousePos.X <= (panel.AbsolutePosition.X + panel.AbsoluteSize.X)
				and mousePos.Y >= panel.AbsolutePosition.Y
				and mousePos.Y <= (panel.AbsolutePosition.Y + panel.AbsoluteSize.Y)
		)
		if isOverPanel then return end

		local now = tick()
		local worldPos = getMovePoint()
		if not worldPos then return end

		local hasMovedEnough = (not lastToolMovePoint) or ((worldPos - lastToolMovePoint).Magnitude >= 0.04)
		if not hasMovedEnough and (now - lastToolMoveFireAt) < 0.06 then
			return
		end
		if (now - lastToolMoveFireAt) < 0.02 then return end
		lastToolMoveFireAt = now
		lastToolMovePoint = worldPos

		if worldPos then
			showerRemote:FireServer("ToolMove", { worldPos = worldPos })
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
		showerRemote:FireServer("Exit", {})
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
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local inputPos = input.Position
	if not inputPos then return end

	if isPointInsideButton(rotateLeft, inputPos) then
		fireRotate(-1, rotateLeft)
	elseif isPointInsideButton(rotateRight, inputPos) then
		fireRotate(1, rotateRight)
	elseif gameProcessed then
		return
	end
end)	

showerRemote.OnClientEvent:Connect(function(action, payload)
	payload = payload or {}

	if action == "Start" then
		gui.Enabled = true
		lastRotateFireAt = 0
		lastToolMoveFireAt = 0
		lastToolMovePoint = nil
		stageLabel.Text = tostring(payload.stageText or "Scrub with Sponge")
		updateBar(payload.progress or 0)
		controlWall = payload.controlWall
		currentPet = payload.pet
		startShowerView(payload.cameraPart)
		startCursorTracking()
	elseif action == "Progress" then
		if payload.stageText then
			stageLabel.Text = tostring(payload.stageText)
		end
		updateBar(payload.progress or 0)
	elseif action == "Stage" then
		if payload.stageText then
			stageLabel.Text = tostring(payload.stageText)
		end
		updateBar(payload.progress or 0)
	elseif action == "End" then
		endShowerView()
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.2)
	endShowerView()
end)
