
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local accessoryEvent = ReplicatedStorage:WaitForChild("PetAccessoryEvent")

-- Simple ScreenGui template (create on first use)
local function createAccessoryGui()
	local screen = Instance.new("ScreenGui")
	screen.Name = "AccessoryServiceGui"
	screen.ResetOnSpawn = false
	screen.Parent = PlayerGui

	local frame = Instance.new("Frame", screen)
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -120)
	frame.Size = UDim2.new(0, 420, 0, 120)
	frame.BackgroundTransparency = 0.25
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.BorderSizePixel = 0
	frame.Name = "Main"

	-- Exit button (X)
	local close = Instance.new("TextButton", frame)
	close.Text = "X"
	close.Size = UDim2.new(0, 40, 0, 40)
	close.Position = UDim2.new(1, -48, 0, 8)
	close.Name = "Close"

	-- Accessory A button
	local btnA = Instance.new("TextButton", frame)
	btnA.Name = "AccessoryA"
	btnA.Text = "Toggle Accessory A"
	btnA.Size = UDim2.new(0, 180, 0, 44)
	btnA.Position = UDim2.new(0, 12, 0, 12)

	-- Accessory B button
	local btnB = Instance.new("TextButton", frame)
	btnB.Name = "AccessoryB"
	btnB.Text = "Toggle Accessory B"
	btnB.Size = UDim2.new(0, 180, 0, 44)
	btnB.Position = UDim2.new(0, 210, 0, 12)

	return screen
end

local gui = createAccessoryGui()
gui.Enabled = false

-- camera control state
local locked = false
local targetPart = nil
local lastCFrame = nil
local petRef = nil

local function enableCameraAtPart(part)
	if not part then return end
	local cam = workspace.CurrentCamera
	-- save previous cam state so we can restore later
	lastCFrame = cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable
	targetPart = part
	locked = true
end

local function disableCameraRestore()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	locked = false
	targetPart = nil
	-- restore last camera CFrame if available
	if lastCFrame then
		-- small protected pcall to avoid errors in edge cases
		pcall(function() cam.CFrame = lastCFrame end)
		lastCFrame = nil
	end
end

-- RenderStepped follow camera
local camConn
camConn = RunService.RenderStepped:Connect(function(dt)
	if not locked or not targetPart or not targetPart.Parent then return end
	local cam = workspace.CurrentCamera

	-- If this is a dedicated Camera part (named "Camera") use its exact CFrame,
	-- otherwise use a small offset so we look at the table nicely.
	local desiredCFrame
	if targetPart.Name == "Camera" then
		-- use the Camera part's orientation/position exactly (you can position/rotate this part in Studio)
		desiredCFrame = targetPart.CFrame
	else
		-- desired offset: slightly above and in front of table so we can see pet (adjust as needed)
		desiredCFrame = targetPart.CFrame * CFrame.new(0, 2, 3) * CFrame.Angles(-0.2, math.rad(180), 0)
	end

	-- smooth lerp to the target
	cam.CFrame = cam.CFrame:Lerp(desiredCFrame, math.clamp(16*dt, 0, 1))
end)

-- store connections so we can disconnect when UI is reopened or closed
local guiConnections = {A = nil, B = nil, Close = nil}

local function disconnectGuiConnections()
	-- safely disconnect stored RBXScriptConnections if present
	if guiConnections.A then
		pcall(function() guiConnections.A:Disconnect() end)
		guiConnections.A = nil
	end
	if guiConnections.B then
		pcall(function() guiConnections.B:Disconnect() end)
		guiConnections.B = nil
	end
	if guiConnections.Close then
		pcall(function() guiConnections.Close:Disconnect() end)
		guiConnections.Close = nil
	end

	-- clear local pet reference when UI is closed or handlers removed
	petRef = nil
end

-- wire up GUI buttons (safe: disconnect previous handlers first)
local function wireGuiButtons(player, pet)
	-- disconnect any old handlers to avoid duplicate fires
	disconnectGuiConnections()

	-- remember current pet in a local variable (do NOT attach arbitrary fields to Instances)
	petRef = pet

	local screen = gui
	local btnA = screen.Main:FindFirstChild("AccessoryA")
	local btnB = screen.Main:FindFirstChild("AccessoryB")
	local close = screen.Main:FindFirstChild("Close")

	-- small local debounce via disabling the button briefly after click
	if btnA then
		guiConnections.A = btnA.MouseButton1Click:Connect(function()
			-- disable briefly so accidental double-clicks still won't spam
			pcall(function() btnA.Active = false end)
			-- use the captured 'pet' from this closure (safe because wireGuiButtons was called with the correct pet)
			accessoryEvent:FireServer("ToggleAccessory", { pet = pet, which = "A" })
			task.delay(0.15, function() if btnA and btnA.Parent then pcall(function() btnA.Active = true end) end end)
		end)
	end

	if btnB then
		guiConnections.B = btnB.MouseButton1Click:Connect(function()
			pcall(function() btnB.Active = false end)
			accessoryEvent:FireServer("ToggleAccessory", { pet = pet, which = "B" })
			task.delay(0.15, function() if btnB and btnB.Parent then pcall(function() btnB.Active = true end) end end)
		end)
	end

	if close then
		guiConnections.Close = close.MouseButton1Click:Connect(function()
			-- request server to exit and close UI locally
			-- prefer petRef if available (defensive), else use closure 'pet'
			local sendPet = petRef or pet
			accessoryEvent:FireServer("ExitAccessory", { pet = sendPet })
			gui.Enabled = false
			disableCameraRestore()
			-- disconnect handlers as UI is closed (this also clears petRef)
			disconnectGuiConnections()
		end)
	end
end

-- Listen to open UI event (safe: disconnect previous handlers before wiring)
accessoryEvent.OnClientEvent:Connect(function(action, tablePart, pet)
	if action == "OpenAccessoryUI" and tablePart and pet then
		-- basic sanity: ensure instances exist
		if not tablePart.Parent or not pet.Parent then return end

		-- disconnect any previous handlers (extra safety) then show UI
		disconnectGuiConnections()
		gui.Enabled = true

		-- wire buttons to the given pet (this will disconnect old handlers so we don't double-fire)
		wireGuiButtons(Player, pet)

		-- Resolve camera target:
		local camPart = nil
		if tablePart.Parent and tablePart.Parent:IsA("BasePart") and tablePart.Parent.Name == "Camera" then
			camPart = tablePart.Parent
		else
			local childCam = tablePart:FindFirstChild("Camera")
			if childCam and childCam:IsA("BasePart") then
				camPart = childCam
			else
				camPart = tablePart
			end
		end

		enableCameraAtPart(camPart)
	end
end)

-- Add this to the local script, after the event listener:

-- Close GUI if pet is no longer valid
game:GetService("RunService").Heartbeat:Connect(function()
	if gui.Enabled and petRef then
		if not petRef or not petRef.Parent then
			-- Pet was removed/destroyed
			gui.Enabled = false
			disableCameraRestore()
			disconnectGuiConnections()
		end
	end
end)

