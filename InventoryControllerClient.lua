---INVENTORYCONTROLLERLOCALSCRIPTINGUI
-- services
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- references
local player = game:GetService("Players").LocalPlayer
local backpack = player:WaitForChild("Backpack")
local camera = workspace.CurrentCamera

-- DISABLE BASIC ROBLOX HOTBAR
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

local CustomInventoryGUI = script.Parent
local hotBar = CustomInventoryGUI.hotBar
local Inventory = CustomInventoryGUI.Inventory
local hotbar = CustomInventoryGUI.hotBar
local openButton = CustomInventoryGUI:FindFirstChild("openButton")
local toolButton = script.toolButton
local inventoryRemotes = ReplicatedStorage:FindFirstChild("InventoryRemotes")
local switchInventoryTabRemote = inventoryRemotes and inventoryRemotes:FindFirstChild("SwitchInventoryTab")
local inventoryTabChangedRemote = inventoryRemotes and inventoryRemotes:FindFirstChild("InventoryTabChanged")

local TAB_PETS = "Pets"
local TAB_FOOD = "Food"
local currentTab = TAB_PETS
local backpackAddedConn
local characterAddedConn
local reloadInventory
local function isRunnerActive()
	return player:GetAttribute("RunnerActive") == true or player:GetAttribute("PetInteractionActive") == true
end

local inventoryHandler = require(script.SETTINGS)

local switchTabButton = hotBar:FindFirstChild("SwitchInventoryTabButton")

local function getNextTabName()
	return currentTab == TAB_PETS and TAB_FOOD or TAB_PETS
end

local function updateSwitchTabButtonLabel()
	if switchTabButton and switchTabButton:IsA("TextButton") then
		switchTabButton.Text = ("Tab: %s  (Switch → %s)"):format(currentTab, getNextTabName())
	end
end

updateSwitchTabButtonLabel()

if switchTabButton and switchTabButton:IsA("TextButton") then
	switchTabButton.Activated:Connect(function()
		if isRunnerActive() then
			return
		end
		if switchInventoryTabRemote then
			switchInventoryTabRemote:FireServer(getNextTabName())
		end
	end)
else
	warn("[InventoryController] Missing Inventory.SwitchInventoryTabButton (TextButton).")
end

if inventoryTabChangedRemote then
	inventoryTabChangedRemote.OnClientEvent:Connect(function(tabName)
		if tabName == TAB_PETS or tabName == TAB_FOOD then
			currentTab = tabName
			updateSwitchTabButtonLabel()
			if reloadInventory then
				local currentCharacter = player.Character
				if currentCharacter then
					task.delay(0.06, function()
						if player.Character == currentCharacter then
							reloadInventory(currentCharacter)
						end
					end)
				end
			end
		end
	end)
end

local function showSlots()
	for index = 1, inventoryHandler.slotAmount do
		local toolObject = inventoryHandler.OBJECTS.HotBar[index]
		if not toolObject and not hotBar:FindFirstChild(index) and index <= inventoryHandler.slotAmount then
			local frame = toolButton:Clone()
			frame.toolName.Text = ""
			frame.toolAmount.Text = ""
			frame.toolNumber.Text = index
			frame.Name = index
			frame.Parent = hotBar
		end
	end
end

local function removeEmptySlots()
	for index = 1, 9 do
		local toolObject = inventoryHandler.OBJECTS.HotBar[index]
		local toolFrame = hotBar:FindFirstChild(index)
		if not toolObject and toolFrame then
			toolFrame:Destroy()
			if hotBar:FindFirstChild(index) then
				removeEmptySlots()
			end
		end
	end
end

local function manageInventory (_, inputState)
	if inputState == Enum.UserInputState.Begin then
		if isRunnerActive() then
			return
		end
		Inventory.Visible = not Inventory.Visible
		local currentState = Inventory.Visible

		inventoryHandler:removeCurrentDescription()
		if currentState then
			showSlots()
			if openButton then
				openButton.Position = UDim2.fromScale(0.5,0.5)
				local infoLabel = openButton:FindFirstChild("info")
				if infoLabel and infoLabel:IsA("TextLabel") then
					infoLabel.Text = "(') close inventory"
				end
			end
		else
			if not inventoryHandler.SETTINGS.SHOW_EMPTY_TOOL_FRAMES_IN_HOTBAR then
				removeEmptySlots()
			end
			if openButton then
				openButton.Position = UDim2.fromScale(0.5,0.909)
				local infoLabel = openButton:FindFirstChild("info")
				if infoLabel and infoLabel:IsA("TextLabel") then
					infoLabel.Text = "(') open inventory"
				end
			end
		end
	elseif not inputState then
		for index = inventoryHandler.slotAmount + 1, inventoryHandler.slotAmount do
			local toolObject = inventoryHandler.OBJECTS.HotBar[index]
			local toolFrame = hotBar:FindFirstChild(index)
			if toolObject then
				local tool = toolObject.Tool
				toolObject:DisconnectAll()
				tool:SetAttribute("toolAdded", nil)
				inventoryHandler:newTool(tool)
			elseif toolFrame then
				toolFrame:Destroy()
			end
		end
	end
end

local function searchTool()
	inventoryHandler:searchTool()
end
local function newTool(tool)
	if tool:IsA("Tool") then
		if isRunnerActive() then
			return
		end
		local toolCategory = tostring(tool:GetAttribute("InventoryCategory") or "")
		if toolCategory == "" then
			if tool:GetAttribute("PetTool") == true or tool:GetAttribute("PetUID") ~= nil then
				toolCategory = TAB_PETS
			else
				toolCategory = TAB_FOOD
			end
		end
		if toolCategory ~= currentTab and switchInventoryTabRemote then
			switchInventoryTabRemote:FireServer(toolCategory)
			return
		end
		inventoryHandler:newTool(tool)
	end
end

reloadInventory = function(character)
	inventoryHandler.currentlyEquipped = nil
	backpack = player:WaitForChild("Backpack")
	if backpackAddedConn then
		backpackAddedConn:Disconnect()
		backpackAddedConn = nil
	end
	if characterAddedConn then
		characterAddedConn:Disconnect()
		characterAddedConn = nil
	end

	for _, tool in pairs(backpack:GetChildren()) do
		if tool:IsA("Tool") then
			newTool(tool)
		end
	end
	backpackAddedConn = backpack.ChildAdded:Connect(newTool)
	characterAddedConn = character.ChildAdded:Connect(function(child)
		if isRunnerActive() and child:IsA("Tool") then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:UnequipTools()
			end
			child.Parent = backpack
			return
		end
		newTool(child)
	end)
	manageInventory()
end

local function updateHudPosition()
	local viewPortSize = camera.ViewportSize
	local slotSize = UDim2.fromOffset(hotBar.AbsoluteSize.Y, hotBar.AbsoluteSize.Y)
	
	Inventory.Frame.Grid.CellSize = slotSize
	hotBar.Grid.CellSize = slotSize

	manageInventory()
end

updateHudPosition(); updateHudPosition()
reloadInventory(player.Character or player.CharacterAdded:Wait())
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateHudPosition)
player.CharacterAdded:Connect(reloadInventory)
Inventory.SearchBox:GetPropertyChangedSignal("Text"):Connect(searchTool)
if inventoryHandler.SETTINGS.SHOW_EMPTY_TOOL_FRAMES_IN_HOTBAR then showSlots() end
if inventoryHandler.SETTINGS.INVENTORY_KEYBIND then ContextActionService:BindAction("manageInventory", manageInventory, false, inventoryHandler.SETTINGS.INVENTORY_KEYBIND) end
if switchInventoryTabRemote then
	switchInventoryTabRemote:FireServer(currentTab)
end
if inventoryHandler.SETTINGS.OPEN_BUTTON and openButton then
	openButton.MouseButton1Down:Connect(function()
		if isRunnerActive() then
			return
		end
		Inventory.Visible = not Inventory.Visible
		local currentState = Inventory.Visible

		inventoryHandler:removeCurrentDescription()
		if currentState then
			showSlots()
			openButton.Position = UDim2.fromScale(0.5,0.5)
			local infoLabel = openButton:FindFirstChild("info")
			if infoLabel and infoLabel:IsA("TextLabel") then
				infoLabel.Text = "(') close inventory"
			end
		else
			if not inventoryHandler.SETTINGS.SHOW_EMPTY_TOOL_FRAMES_IN_HOTBAR then
				removeEmptySlots()
			end
			openButton.Position = UDim2.fromScale(0.5,0.909)
			local infoLabel = openButton:FindFirstChild("info")
			if infoLabel and infoLabel:IsA("TextLabel") then
				infoLabel.Text = "(') open inventory"
			end
		end
	end)
else
	if openButton then
		openButton.Visible = false
	end
end

local function getToolEquipped()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Tool")
end

UserInputService.InputChanged:Connect(function(input)
	if isRunnerActive() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseWheel and inventoryHandler.SETTINGS.SCROLL_HOTBAR_WITH_WHEEL then
		local direction = input.Position.Z
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		local toolEquipped = getToolEquipped()
		local toolPosition = inventoryHandler:getToolPosition(toolEquipped) or 0
		
		for i=toolPosition + direction, direction < 0 and 1 or inventoryHandler.slotAmount, direction do
			local toolObject = inventoryHandler.OBJECTS.HotBar[i]
			if toolObject and humanoid then
				humanoid:EquipTool(toolObject.Tool)
				break
			end
		end
	end
end)

local function refreshInventorySuppressionState()
	local sprinting = isRunnerActive()
	CustomInventoryGUI.Enabled = not sprinting
	if switchTabButton and switchTabButton:IsA("TextButton") then
		switchTabButton.Active = not sprinting
		switchTabButton.AutoButtonColor = not sprinting
		switchTabButton.Visible = not sprinting
	end
	if sprinting then
		Inventory.Visible = false
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
		end
	end
end

local function onSuppressionStateChanged()
	refreshInventorySuppressionState()
	if not isRunnerActive() and reloadInventory then
		local currentCharacter = player.Character
		if currentCharacter then
			task.delay(0.08, function()
				if player.Character == currentCharacter and not isRunnerActive() then
					reloadInventory(currentCharacter)
					manageInventory()
				end
			end)
		end
	end
end

player:GetAttributeChangedSignal("RunnerActive"):Connect(onSuppressionStateChanged)
player:GetAttributeChangedSignal("PetInteractionActive"):Connect(onSuppressionStateChanged)

if isRunnerActive() then
	refreshInventorySuppressionState()
end
