
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
	      ├─ Close (Frame)
	      │  └─ Button (GuiButton)
	      ├─ AccessoriesList (Frame or ScrollingFrame)
	      │  └─ UIListLayout (optional, recommended)
	      └─ (optional) EmptyLabel (TextLabel)
]]

local function getPrimaryPartForDisplay(instance)
	if not instance then return nil end
	if instance:IsA("Model") then
		return instance:FindFirstChild("MainPart") or instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	if instance:IsA("BasePart") then
		return instance
	end
	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function getDisplaySize(instance)
	if not instance then return Vector3.new(2, 2, 2) end
	if instance:IsA("Model") then
		return instance:GetExtentsSize()
	end
	if instance:IsA("BasePart") then
		return instance.Size
	end
	local part = instance:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Size or Vector3.new(2, 2, 2)
end

local function tryClonePetInventoryTemplate(listParent)
	local gameUi = PlayerGui:FindFirstChild("GameUI")
	local petsHolder = gameUi
		and gameUi:FindFirstChild("Frames")
		and gameUi.Frames:FindFirstChild("Pets")
		and gameUi.Frames.Pets:FindFirstChild("MainFrame")
		and gameUi.Frames.Pets.MainFrame:FindFirstChild("ObjectHolder")
	if not petsHolder then
		return nil
	end

	local source
	for _, child in ipairs(petsHolder:GetChildren()) do
		local display = child:FindFirstChild("Display")
		local button = child:FindFirstChild("Button")
		if display and display:IsA("ViewportFrame") and button and button:IsA("GuiButton") then
			source = child
			break
		end
	end
	if not source then
		return nil
	end

	local template = source:Clone()
	template.Name = "AccessoryTemplate"
	template.Visible = false
	template.Parent = listParent

	local display = template:FindFirstChild("Display")
	if display and display:IsA("ViewportFrame") then
		for _, item in ipairs(display:GetChildren()) do
			item:Destroy()
		end
		display.CurrentCamera = nil
	end

	local sellFrame = template:FindFirstChild("SellFrame")
	if sellFrame then
		sellFrame:Destroy()
	end

	return template
end

local function createAccessoryTemplate(listParent)
	local clonedTemplate = tryClonePetInventoryTemplate(listParent)
	if clonedTemplate then
		return clonedTemplate
	end

	local template = Instance.new("Frame")
	template.Name = "AccessoryTemplate"
	template.Size = UDim2.new(1, 0, 0, 46)
	template.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	template.Visible = false
	template.Parent = listParent

	local display = Instance.new("ViewportFrame")
	display.Name = "Display"
	display.BackgroundTransparency = 1
	display.Size = UDim2.new(0, 44, 0, 44)
	display.Position = UDim2.fromOffset(1, 1)
	display.Parent = template

	local title = Instance.new("TextLabel")
	title.Name = "Name"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -56, 1, 0)
	title.Position = UDim2.fromOffset(52, 0)
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 16
	title.Font = Enum.Font.SourceSansSemibold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Accessory"
	title.Parent = template

	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.Text = ""
	button.Parent = template

	local equipped = Instance.new("TextLabel")
	equipped.Name = "Equipped"
	equipped.BackgroundTransparency = 1
	equipped.Size = UDim2.fromOffset(18, 18)
	equipped.Position = UDim2.new(1, -21, 0, 2)
	equipped.Font = Enum.Font.GothamBold
	equipped.TextScaled = true
	equipped.Text = "✓"
	equipped.TextColor3 = Color3.fromRGB(85, 255, 127)
	equipped.Visible = false
	equipped.Parent = template

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = template

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = template

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(82, 82, 82)
	stroke.Transparency = 0.3
	stroke.Parent = template

	return template
end

local function resolveCloseButton(main)
	local close = main:FindFirstChild("Close")
	if not close then
		return nil
	end

	if close:IsA("GuiButton") then
		return close
	end

	local nestedButton = close:FindFirstChildWhichIsA("GuiButton", true)
	if nestedButton then
		return nestedButton
	end

	return nil
end

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

	local closeButton = resolveCloseButton(main)
	if not closeButton then
		warn("[AccessoryClient] Missing Main.Close button. Add Close frame with a child GuiButton.")
		return nil
	end

	local accessoriesList = main:FindFirstChild("AccessoriesList")
	if not accessoriesList then
		warn("[AccessoryClient] Missing Main.AccessoriesList")
		return nil
	end

	local template = accessoriesList:FindFirstChild("AccessoryTemplate")
	if not template or not template:IsA("GuiObject") then
		template = createAccessoryTemplate(accessoriesList)
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
	listLayout = nil,
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

	if guiConnections.listLayout then
		pcall(function() guiConnections.listLayout:Disconnect() end)
		guiConnections.listLayout = nil
	end

	petRef = nil
	accessoryButtonsByName = {}
end

local function clearAccessoryButtons()
	if not guiRefs then return end
	for _, child in ipairs(guiRefs.list:GetChildren()) do
		if child:IsA("GuiObject") and child ~= guiRefs.template then
			child:Destroy()
		end
	end
end

local function setAccessoryButtonVisual(accessoryName)
	local entry = accessoryButtonsByName[accessoryName]
	if not entry then return end
	local slot = entry.slot
	if equippedByName[accessoryName] then
		slot:SetAttribute("IsEquipped", true)
		local equippedMark = slot:FindFirstChild("Equipped")
		if equippedMark and equippedMark:IsA("GuiObject") then
			equippedMark.Visible = true
		end
	else
		slot:SetAttribute("IsEquipped", false)
		local equippedMark = slot:FindFirstChild("Equipped")
		if equippedMark and equippedMark:IsA("GuiObject") then
			equippedMark.Visible = false
		end
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
				button.Parent = guiRefs.list

				local titleLabel = button:FindFirstChild("Name") or button:FindFirstChild("Title")
				if titleLabel and titleLabel:IsA("TextLabel") then
					titleLabel.Text = accessoryName
				elseif button:IsA("GuiButton") then
					button.Text = accessoryName
				end

				local display = button:FindFirstChild("Display")
				if display and display:IsA("ViewportFrame") then
					for _, child in ipairs(display:GetChildren()) do
						child:Destroy()
					end
					local template = ReplicatedStorage:FindFirstChild("Accessories")
						and ReplicatedStorage.Accessories:FindFirstChild(accessoryName)
					if template then
						local model = template:Clone()
						model.Parent = display
						local mainPart = getPrimaryPartForDisplay(model)
						if mainPart then
							local pos = mainPart.Position
							local camera = Instance.new("Camera")
							camera.Parent = display
							display.CurrentCamera = camera
							if model:IsA("Model") then
								model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(180), 0))
							elseif model:IsA("BasePart") then
								model.CFrame = model.CFrame * CFrame.Angles(0, math.rad(180), 0)
							end
							camera.CFrame = CFrame.new(Vector3.new(pos.X + getDisplaySize(model).X * 1.5, pos.Y, pos.Z + 1), pos)
						else
							model:Destroy()
						end
					end
				end

				local clickButton = button:FindFirstChild("Button")
				if not (clickButton and clickButton:IsA("GuiButton")) and button:IsA("GuiButton") then
					clickButton = button
				end
				if not (clickButton and clickButton:IsA("GuiButton")) then
					continue
				end

				accessoryButtonsByName[accessoryName] = { slot = button, click = clickButton }
				count += 1

				table.insert(guiConnections.dynamic, clickButton.MouseButton1Click:Connect(function()
					if not petRef then return end
					clickButton.Active = false
					accessoryEvent:FireServer("ToggleAccessory", { pet = petRef, accessoryName = accessoryName })
					task.delay(0.2, function()
						if clickButton and clickButton.Parent then
							clickButton.Active = true
						end
					end)
				end))
			end
		end
	end

	guiRefs.template.Visible = false

	if guiRefs.list:IsA("ScrollingFrame") then
		local listLayout = guiRefs.list:FindFirstChildOfClass("UIListLayout")
		if listLayout then
			if guiConnections.listLayout then
				pcall(function() guiConnections.listLayout:Disconnect() end)
			end
			local function refreshCanvasFromLayout()
				guiRefs.list.CanvasSize = UDim2.fromOffset(0, math.max(0, listLayout.AbsoluteContentSize.Y + 4))
			end
			refreshCanvasFromLayout()
			guiConnections.listLayout = listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshCanvasFromLayout)
		else
			local rowHeight = guiRefs.template.AbsoluteSize.Y > 0 and guiRefs.template.AbsoluteSize.Y or 46
			guiRefs.list.CanvasSize = UDim2.fromOffset(0, math.max(0, count * (rowHeight + 8)))
		end
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
