
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local accessoryEvent = ReplicatedStorage:WaitForChild("PetAccessoryEvent")

--[[
	UI contract (you build this in Studio):
	PlayerGui
	└─ AccessoryServiceGui (ScreenGui)
	   └─ Main (Frame)
	      ├─ Close (GuiButton)
	      ├─ AccessoriesList (Frame or ScrollingFrame)
	      │  └─ AccessoryTemplate (GuiButton, hidden template)
	      └─ (optional) EmptyLabel (TextLabel)
]]

local function resolveAccessoryGui()
	local screen = PlayerGui:WaitForChild("AccessoryServiceGui")
	if not screen then
		warn("[AccessoryClient] Missing PlayerGui.AccessoryServiceGui. Create it in Studio.")
		return nil
	end

	local main = screen:FindFirstChild("Main")
	if not main then
		warn("[AccessoryClient] Missing AccessoryServiceGui.Main")
		return nil
	end

	local closeButton = main:FindFirstChild("Close")
	if not closeButton or not closeButton:IsA("GuiButton") then
		warn("[AccessoryClient] Missing Main.Close (GuiButton)")
		return nil
	end

	local accessoriesList = main:FindFirstChild("AccessoriesList")
	if not accessoriesList then
		warn("[AccessoryClient] Missing Main.AccessoriesList")
		return nil
	end

	local template = accessoriesList:FindFirstChild("AccessoryTemplate")
	if not template or not template:IsA("GuiButton") then
		warn("[AccessoryClient] Missing AccessoriesList.AccessoryTemplate (GuiButton template)")
		return nil
	end

	return {
		screen = screen,
		main = main,
		close = closeButton,
		list = accessoriesList,
		template = template,
	}
end

local guiRefs = resolveAccessoryGui()

local locked = false
local targetPart = nil
local lastCFrame = nil
local petRef = nil
local equippedByName = {}
local accessoryButtonsByName = {}

local guiConnections = {
	close = nil,
	dynamic = {},
}

local function enableCameraAtPart(part)
	if not part then return end
	local cam = workspace.CurrentCamera
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
	if lastCFrame then
		pcall(function() cam.CFrame = lastCFrame end)
		lastCFrame = nil
	end
end

RunService.RenderStepped:Connect(function(dt)
	if not locked or not targetPart or not targetPart.Parent then return end
	local cam = workspace.CurrentCamera
	local desiredCFrame
	if targetPart.Name == "Camera" then
		desiredCFrame = targetPart.CFrame
	else
		desiredCFrame = targetPart.CFrame * CFrame.new(0, 2, 3) * CFrame.Angles(-0.2, math.rad(180), 0)
	end
	cam.CFrame = cam.CFrame:Lerp(desiredCFrame, math.clamp(16 * dt, 0, 1))
end)

local function disconnectGuiConnections()
	for _, conn in ipairs(guiConnections.dynamic) do
		pcall(function() conn:Disconnect() end)
	end
	guiConnections.dynamic = {}

	if guiConnections.close then
		pcall(function() guiConnections.close:Disconnect() end)
		guiConnections.close = nil
	end

	petRef = nil
	accessoryButtonsByName = {}
end

local function clearAccessoryButtons()
	if not guiRefs then return end
	for _, child in ipairs(guiRefs.list:GetChildren()) do
		if child:IsA("GuiButton") and child ~= guiRefs.template then
			child:Destroy()
		end
	end
end

local function setAccessoryButtonVisual(accessoryName)
	local button = accessoryButtonsByName[accessoryName]
	if not button then return end
	if equippedByName[accessoryName] then
		button:SetAttribute("IsEquipped", true)
		button.Text = tostring(accessoryName) .. " ✓"
	else
		button:SetAttribute("IsEquipped", false)
		button.Text = tostring(accessoryName)
	end
end

local function applyEquippedState(equippedSlots)
	equippedByName = {}
	if type(equippedSlots) == "table" then
		if type(equippedSlots.A) == "string" and equippedSlots.A ~= "" then
			equippedByName[equippedSlots.A] = true
		end
		if type(equippedSlots.B) == "string" and equippedSlots.B ~= "" then
			equippedByName[equippedSlots.B] = true
		end
	end

	for accessoryName in pairs(accessoryButtonsByName) do
		setAccessoryButtonVisual(accessoryName)
	end
end

local function buildAccessoryButtons(ownedAccessories)
	if not guiRefs then return end
	clearAccessoryButtons()
	accessoryButtonsByName = {}

	local count = 0
	if type(ownedAccessories) == "table" then
		for _, accessoryName in ipairs(ownedAccessories) do
			if type(accessoryName) == "string" and accessoryName ~= "" then
				local button = guiRefs.template:Clone()
				button.Name = "Accessory_" .. accessoryName
				button.Visible = true
				button.Text = accessoryName
				button.Parent = guiRefs.list
				accessoryButtonsByName[accessoryName] = button
				count += 1

				table.insert(guiConnections.dynamic, button.MouseButton1Click:Connect(function()
					if not petRef then return end
					button.Active = false
					accessoryEvent:FireServer("ToggleAccessory", { pet = petRef, accessoryName = accessoryName })
					task.delay(0.2, function()
						if button and button.Parent then
							button.Active = true
						end
					end)
				end))
			end
		end
	end

	guiRefs.template.Visible = false

	if guiRefs.list:IsA("ScrollingFrame") then
		local cellWidth = guiRefs.template.AbsoluteSize.X > 0 and guiRefs.template.AbsoluteSize.X or 120
		guiRefs.list.CanvasSize = UDim2.new(0, math.max(0, count * (cellWidth + 8)), 0, 0)
	end

	local emptyLabel = guiRefs.main:FindFirstChild("EmptyLabel")
	if emptyLabel and emptyLabel:IsA("TextLabel") then
		emptyLabel.Visible = count == 0
	end
end

local function wireCloseButton()
	if not guiRefs then return end
	if guiConnections.close then
		pcall(function() guiConnections.close:Disconnect() end)
	end
	guiConnections.close = guiRefs.close.MouseButton1Click:Connect(function()
		local sendPet = petRef
		if sendPet then
			accessoryEvent:FireServer("ExitAccessory", { pet = sendPet })
		end
		guiRefs.screen.Enabled = false
		disableCameraRestore()
		disconnectGuiConnections()
	end)
end

-- Listen to open UI event (safe: disconnect previous handlers before wiring)
accessoryEvent.OnClientEvent:Connect(function(action, tablePart, pet, payload)
	if action == "OpenAccessoryUI" then
		guiRefs = guiRefs or resolveAccessoryGui()
		if not guiRefs then return end
		if not tablePart or not pet or not tablePart.Parent or not pet.Parent then return end

		disconnectGuiConnections()
		petRef = pet
		guiRefs.screen.Enabled = true

		local owned = (type(payload) == "table" and payload.ownedAccessories) or {}
		local equipped = (type(payload) == "table" and payload.equipped) or {}

		buildAccessoryButtons(owned)
		applyEquippedState(equipped)
		wireCloseButton()

		local camPart = nil
		if tablePart.Parent and tablePart.Parent:IsA("BasePart") and tablePart.Parent.Name == "Camera" then
			camPart = tablePart.Parent
		else
			local childCam = tablePart:FindFirstChild("Camera")
			camPart = (childCam and childCam:IsA("BasePart")) and childCam or tablePart
		end
		enableCameraAtPart(camPart)
	elseif action == "AccessoryState" then
		if type(payload) == "table" then
			applyEquippedState(payload.equipped)
		end
	elseif action == "AccessoryToggleFailed" then
		if type(payload) == "table" and type(payload.reason) == "string" then
			warn("[AccessoryClient] Toggle failed: " .. payload.reason)
		end
	end
end)

-- Add this to the local script, after the event listener:

-- Close GUI if pet is no longer valid
RunService.Heartbeat:Connect(function()
	if guiRefs and guiRefs.screen.Enabled and petRef then
		if not petRef.Parent then
			guiRefs.screen.Enabled = false
			disableCameraRestore()
			disconnectGuiConnections()
		end
	end
end)
