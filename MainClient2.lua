-- MainClient2 (LocalScript)
-- Place in StarterPlayerScripts.
-- Continuation companion for MainClientScript to avoid register overflow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local function waitForHatchFunction(timeout)
	timeout = timeout or 15
	local started = os.clock()
	while os.clock() - started < timeout do
		if type(_G.HatchEgg) == "function" then
			return _G.HatchEgg
		end
		task.wait(0.2)
	end
	return nil
end

local hatchEggFn = waitForHatchFunction()
-- It's normal for this to be nil briefly due to client script load order.

local caseHatchEvent = ReplicatedStorage:FindFirstChild("CaseHatchEvent")
if not caseHatchEvent then
	caseHatchEvent = Instance.new("RemoteEvent")
	caseHatchEvent.Name = "CaseHatchEvent"
	caseHatchEvent.Parent = ReplicatedStorage
end

caseHatchEvent.OnClientEvent:Connect(function(action, eggName, itemName)
	if action ~= "PlayHatch" then return end
	if type(eggName) ~= "string" or eggName == "" then return end
	if type(itemName) ~= "string" or itemName == "" then return end
	if type(hatchEggFn) ~= "function" then
		hatchEggFn = waitForHatchFunction(30)
	end
	if type(hatchEggFn) ~= "function" then
		warn("[MainClient2] Unable to play hatch: _G.HatchEgg unavailable.")
		return
	end
	pcall(function()
		hatchEggFn(eggName, itemName, 0)
	end)
end)

-- Convert frame companion system.
-- Kept in MainClient2 instead of MainClientScript to avoid adding many locals to the large main client script.
task.spawn(function()
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")

	local function waitForLoadedPlayer()
		while player.Parent and (not player:FindFirstChild("Loaded") or not player.Loaded.Value) do
			task.wait(0.1)
		end
		return player.Parent ~= nil
	end

	if not waitForLoadedPlayer() then return end

	local data = player:WaitForChild("Data", 20)
	local petsFolder = data and data:WaitForChild("Pets", 20)
	local playerGui = player:WaitForChild("PlayerGui", 20)
	local gameUI = playerGui and playerGui:WaitForChild("GameUI", 20)
	local frames = gameUI and gameUI:WaitForChild("Frames", 20)
	local convertFrame = frames and frames:FindFirstChild("Convert")
	local petsRoot = ReplicatedStorage:WaitForChild("Pets", 20)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
	local modules = ReplicatedStorage:WaitForChild("Modules", 20)
	local utilities = modules and require(modules:WaitForChild("Utilities"))

	if not (petsFolder and convertFrame and petsRoot and remotes and utilities) then
		warn("[ConvertClient] Convert system skipped because required UI/data folders are missing.")
		return
	end

	local config = {
		RequiredCount = 3,
		RarityOrder = { Normal = "Golden", Golden = "Diamond" },
		RarityPrefixes = { "Golden ", "Diamond " },
		RingDistance = 10,
		FallbackFrameSize = UDim2.new(0.359, 0, 0.414, 0),
	}

	local ui = {
		mainFrame = convertFrame:FindFirstChild("MainFrame"),
		converter = convertFrame:FindFirstChild("Converter"),
		result = convertFrame:FindFirstChild("Result"),
	}
	ui.objectHolder = ui.mainFrame and ui.mainFrame:FindFirstChild("ObjectHolder")
	ui.amount = ui.converter and ui.converter:FindFirstChild("Amount")
	ui.selectedHolder = ui.converter and ui.converter:FindFirstChild("PetHolder")
	ui.convertButtonFrame = ui.converter and ui.converter:FindFirstChild("ConvertButton")
	ui.convertButton = ui.convertButtonFrame and ui.convertButtonFrame:FindFirstChild("Click")
	ui.resultHolder = ui.result and ui.result:FindFirstChild("PetHolder2")
	ui.income = ui.result and ui.result:FindFirstChild("Income")

	if not ui.objectHolder then
		warn("[ConvertClient] Frames.Convert.MainFrame.ObjectHolder is missing.")
		return
	end

	local notifyBridge = ReplicatedStorage:FindFirstChild("ClientNotificationEvent")
	if not notifyBridge or not notifyBridge:IsA("BindableEvent") then
		notifyBridge = Instance.new("BindableEvent")
		notifyBridge.Name = "ClientNotificationEvent"
		notifyBridge.Parent = ReplicatedStorage
	end

	local function notify(kind, message)
		notifyBridge:Fire(kind, message)
	end

	local function getMainClientPetTemplate()
		local playerScripts = player:FindFirstChild("PlayerScripts")
		local mainClient = playerScripts and playerScripts:FindFirstChild("Client")
		local template = mainClient and mainClient:FindFirstChild("PetTemplate")
		if template then return template end

		local playerScriptsWait = player:WaitForChild("PlayerScripts", 10)
		mainClient = playerScriptsWait and playerScriptsWait:WaitForChild("Client", 10)
		return mainClient and mainClient:WaitForChild("PetTemplate", 10) or nil
	end

	local slotTemplate = getMainClientPetTemplate()
	if not slotTemplate then
		warn("[ConvertClient] Could not find MainClientScript.PetTemplate for Convert slots.")
		return
	end

	local state = {
		selectionIds = {},
		selectedById = {},
		selectedName = nil,
		selectedRarity = nil,
		resultName = nil,
		busy = false,
		slotsById = {},
		ringDismissed = false,
		wasInRing = false,
		wasVisible = convertFrame.Visible,
		baseFrameSize = convertFrame.Size,
	}

	if state.baseFrameSize.X.Scale == 0 and state.baseFrameSize.X.Offset == 0 and state.baseFrameSize.Y.Scale == 0 and state.baseFrameSize.Y.Offset == 0 then
		state.baseFrameSize = config.FallbackFrameSize
	end

	local hoverRoot = playerGui and playerGui:FindFirstChild("HoverGui")
	local hoverFrame = hoverRoot and hoverRoot:FindFirstChild("Hover1")
	local hoverName = hoverFrame and hoverFrame:FindFirstChild("NameFrame") and hoverFrame.NameFrame:FindFirstChild("Name")
	local hoverPower = hoverFrame and hoverFrame:FindFirstChild("PowerFrame") and hoverFrame.PowerFrame:FindFirstChild("Power")
	local activeHoverButton = nil
	local activeHoverPetName = nil
	local activePointerPosition = nil
	local getPetTemplate

	if hoverFrame then
		hoverFrame.Visible = false
	end

	local function positionHover(pointerPosition)
		if not hoverFrame or not hoverFrame.Visible then return end
		local camera = workspace.CurrentCamera
		if not camera then return end
		local pos = pointerPosition or UserInputService:GetMouseLocation()
		local x = math.clamp(pos.X + 16, 0, camera.ViewportSize.X - hoverFrame.AbsoluteSize.X)
		local y = math.clamp(pos.Y + 16, 0, camera.ViewportSize.Y - hoverFrame.AbsoluteSize.Y)
		hoverFrame.Position = UDim2.fromOffset(x, y)
	end

	local function bindHover(guiObject, petName)
		if not guiObject or not guiObject:IsA("GuiObject") or not hoverFrame then return end
		guiObject.MouseEnter:Connect(function()
			activeHoverButton = guiObject
			activeHoverPetName = petName
			local template = getPetTemplate(petName)
			if hoverName then hoverName.Text = tostring(template and template.Name or petName or "Pet") end
			if hoverPower then
				local power = tonumber(template and template:GetAttribute("Power")) or 0
				hoverPower.Text = "Power: " .. utilities.Short.en(power)
			end
			hoverFrame.Visible = true
			activePointerPosition = UserInputService:GetMouseLocation()
			positionHover(activePointerPosition)
		end)
		guiObject.MouseLeave:Connect(function()
			if activeHoverButton ~= guiObject then return end
			activeHoverButton = nil
			activeHoverPetName = nil
			activePointerPosition = nil
			hoverFrame.Visible = false
		end)
	end

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			activePointerPosition = input.Position
			positionHover(input.Position)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if activeHoverButton and activeHoverPetName and hoverFrame and hoverFrame.Visible then
			positionHover(activePointerPosition or UserInputService:GetMouseLocation())
		end
	end)


	local function clearHolder(holder)
		if not holder then return end
		for _, child in ipairs(holder:GetChildren()) do
			if child:IsA("GuiObject") or child:IsA("Camera") then
				if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") and not child:IsA("UICorner") and not child:IsA("UIStroke") then
					child:Destroy()
				end
			end
		end
	end

	local function getPetName(petFolder)
		local petNameValue = petFolder and petFolder:FindFirstChild("PetName")
		local petName = petNameValue and tostring(petNameValue.Value) or ""
		return petName ~= "" and petName or nil
	end

	getPetTemplate = function(petFolderOrName)
		local petName = type(petFolderOrName) == "string" and petFolderOrName or getPetName(petFolderOrName)
		return petName and petsRoot:FindFirstChild(petName) or nil
	end

	local function getPetRarity(petTemplate)
		local rarity = petTemplate and petTemplate:GetAttribute("Rarity")
		if rarity == nil then
			local settings = petTemplate and petTemplate:FindFirstChild("Settings")
			local rarityValue = settings and settings:FindFirstChild("Rarity")
			rarity = rarityValue and rarityValue.Value or nil
		end
		rarity = tostring(rarity or "Normal")
		return rarity ~= "" and rarity or "Normal"
	end

	local function getBasePetName(petName, rarity)
		local baseName = tostring(petName or "")
		local rarityPrefix = tostring(rarity or "") .. " "
		if rarity ~= "Normal" and string.sub(baseName, 1, #rarityPrefix) == rarityPrefix then
			baseName = string.sub(baseName, #rarityPrefix + 1)
		end
		for _, prefix in ipairs(config.RarityPrefixes) do
			if string.sub(baseName, 1, #prefix) == prefix then
				baseName = string.sub(baseName, #prefix + 1)
				break
			end
		end
		return baseName
	end

	local function getResultName(petName, petTemplate)
		local explicitResult = petTemplate and (petTemplate:GetAttribute("ConvertResult") or petTemplate:GetAttribute("NextRarityPet"))
		if type(explicitResult) == "string" and explicitResult ~= "" and petsRoot:FindFirstChild(explicitResult) then
			return explicitResult
		end

		local rarity = getPetRarity(petTemplate)
		local nextRarity = config.RarityOrder[rarity]
		if not nextRarity then return nil, "MaxRarity" end

		local resultName = nextRarity .. " " .. getBasePetName(petName, rarity)
		if not petsRoot:FindFirstChild(resultName) then return nil, "ResultMissing" end
		return resultName
	end

	local function isPetUnavailableForConvert(petFolder)
		local runtimeLocation = petFolder and petFolder:FindFirstChild("RuntimeLocation")
		local location = runtimeLocation and tostring(runtimeLocation.Value or "") or ""
		return location == "free" or location == "petground" or location == "player" or location == "player_wild"
	end

	local function setSlotCheckmark(slot, checked)
		if not slot then return end
		local mark = slot:FindFirstChild("ConvertCheckmark")
		if not mark then
			mark = Instance.new("TextLabel")
			mark.Name = "ConvertCheckmark"
			mark.AnchorPoint = Vector2.new(1, 0)
			mark.Position = UDim2.new(1, -6, 0, 6)
			mark.Size = UDim2.fromOffset(28, 28)
			mark.BackgroundColor3 = Color3.fromRGB(43, 204, 91)
			mark.BackgroundTransparency = 0.05
			mark.BorderSizePixel = 0
			mark.Text = "✓"
			mark.Font = Enum.Font.GothamBold
			mark.TextSize = 22
			mark.TextColor3 = Color3.fromRGB(255, 255, 255)
			mark.ZIndex = 80
			mark.Parent = slot
		end
		mark.Visible = checked == true
	end

	local function renderPetModel(slot, petName)
		local display = slot and slot:FindFirstChild("Display")
		local petTemplate = getPetTemplate(petName)
		if not (display and petTemplate) then return false end
		clearHolder(display)

		local model = petTemplate:Clone()
		model.Parent = display
		local mainPart = model:FindFirstChild("MainPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if not mainPart then
			model:Destroy()
			return false
		end

		local camera = Instance.new("Camera")
		camera.Parent = display
		display.CurrentCamera = camera
		local pos = mainPart.Position
		model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(180), 0))
		camera.CFrame = CFrame.new(Vector3.new(pos.X + model:GetExtentsSize().X * 1.5, pos.Y, pos.Z + 1), pos)
		return true
	end

	local function createSlot(petName, slotName, parent, onClick)
		if not parent then return nil end
		local slot = slotTemplate:Clone()
		slot.Name = tostring(slotName or petName)
		setSlotCheckmark(slot, false)
		if not renderPetModel(slot, petName) then
			slot:Destroy()
			return nil
		end

		local button = slot:FindFirstChild("Button")
		bindHover(button, petName)
		if button and button:IsA("GuiButton") then
			if onClick then
				button.MouseButton1Click:Connect(onClick)
			else
				button.Active = false
			end
		end

		slot.Parent = parent
		return slot
	end

	local function sortConvertSlots()
		local rows = {}
		for _, petFolder in ipairs(petsFolder:GetChildren()) do
			local petName = getPetName(petFolder)
			local template = petName and getPetTemplate(petName)
			local power = tonumber(template and template:GetAttribute("Power")) or 0
			table.insert(rows, { id = petFolder.Name, power = power })
		end
		table.sort(rows, function(a, b)
			if a.power ~= b.power then return a.power > b.power end
			local aId = tonumber(a.id) or 0
			local bId = tonumber(b.id) or 0
			return aId > bId
		end)
		for order, row in ipairs(rows) do
			local slot = state.slotsById[row.id]
			if slot then slot.LayoutOrder = order end
		end
	end

	local refreshUi
	local function rebuildPreviews()
		clearHolder(ui.selectedHolder)
		clearHolder(ui.resultHolder)
		for _, petId in ipairs(state.selectionIds) do
			local petName = getPetName(petsFolder:FindFirstChild(tostring(petId)))
			if petName then
				createSlot(petName, "Selected_" .. tostring(petId), ui.selectedHolder, nil)
			end
		end
		if state.resultName then
			createSlot(state.resultName, "ResultPreview", ui.resultHolder, nil)
		end
	end

	refreshUi = function()
		local selectedCount = #state.selectionIds
		if ui.amount and ui.amount:IsA("TextLabel") then
			ui.amount.Text = tostring(selectedCount) .. "/" .. tostring(config.RequiredCount)
		end
		if ui.income and ui.income:IsA("TextLabel") then
			local resultTemplate = state.resultName and getPetTemplate(state.resultName)
			local power = tonumber(resultTemplate and resultTemplate:GetAttribute("Power"))
			ui.income.Text = power and ("$" .. utilities.Short.en(math.max(1, math.floor(power + 0.5))) .. "/s") or "$.../s"
		end
		if ui.convertButtonFrame and ui.convertButtonFrame:IsA("GuiObject") then
			ui.convertButtonFrame.Visible = selectedCount == config.RequiredCount and state.resultName ~= nil and state.busy ~= true
		end
		for petId, slot in pairs(state.slotsById) do
			setSlotCheckmark(slot, state.selectedById[tostring(petId)] == true)
		end
		rebuildPreviews()
	end

	local function resetSelection()
		state.selectionIds = {}
		state.selectedById = {}
		state.selectedName = nil
		state.selectedRarity = nil
		state.resultName = nil
		refreshUi()
	end

	local function removeSelection(petId)
		local key = tostring(petId)
		if not state.selectedById[key] then return end
		state.selectedById[key] = nil
		for index, selectedId in ipairs(state.selectionIds) do
			if tostring(selectedId) == key then
				table.remove(state.selectionIds, index)
				break
			end
		end
		if #state.selectionIds == 0 then
			state.selectedName = nil
			state.selectedRarity = nil
			state.resultName = nil
		end
		refreshUi()
	end

	local function togglePet(petFolder)
		if not petFolder then return end
		local petId = tostring(petFolder.Name)
		if state.selectedById[petId] then
			removeSelection(petId)
			utilities.Audio.PlayAudio("Click")
			return
		end
		if isPetUnavailableForConvert(petFolder) then
			notify("error", "❌ Pick up your wandering pet before converting it.")
			utilities.Audio.PlayAudio("Click")
			return
		end
		if #state.selectionIds >= config.RequiredCount then
			notify("error", "❌ You only need 3 pets to convert.")
			utilities.Audio.PlayAudio("Click")
			return
		end

		local petName = getPetName(petFolder)
		local petTemplate = getPetTemplate(petName or "")
		if not (petName and petTemplate) then
			notify("error", "❌ This pet cannot be converted right now.")
			utilities.Audio.PlayAudio("Click")
			return
		end

		local rarity = getPetRarity(petTemplate)
		local resultName, resultReason = getResultName(petName, petTemplate)
		if not resultName then
			if resultReason == "MaxRarity" then
				notify("error", "❌ This pet is already at the highest rarity.")
			else
				notify("error", "❌ The upgraded pet model is missing in ReplicatedStorage.Pets.")
			end
			utilities.Audio.PlayAudio("Click")
			return
		end

		if state.selectedName and (state.selectedName ~= petName or state.selectedRarity ~= rarity or state.resultName ~= resultName) then
			notify("error", "❌ You can only mark the same type of pets!")
			utilities.Audio.PlayAudio("Click")
			return
		end

		state.selectedName = petName
		state.selectedRarity = rarity
		state.resultName = resultName
		state.selectedById[petId] = true
		table.insert(state.selectionIds, petId)
		refreshUi()
		utilities.Audio.PlayAudio("Click")
	end

	local function addPetSlot(petFolder)
		if not petFolder or state.slotsById[petFolder.Name] then return end
		local petName = getPetName(petFolder)
		if not petName then return end
		local slot = createSlot(petName, petFolder.Name, ui.objectHolder, function()
			togglePet(petFolder)
		end)
		if not slot then return end
		state.slotsById[petFolder.Name] = slot
		sortConvertSlots()
	end

	local function removePetSlot(petFolder)
		if not petFolder then return end
		removeSelection(petFolder.Name)
		local slot = state.slotsById[petFolder.Name]
		if slot then slot:Destroy() end
		state.slotsById[petFolder.Name] = nil
		sortConvertSlots()
	end

	local function submitConvert()
		if state.busy then return end
		if #state.selectionIds ~= config.RequiredCount or not state.resultName then
			notify("error", "❌ Select 3 matching pets first.")
			utilities.Audio.PlayAudio("Click")
			return
		end

		local remote = remotes:FindFirstChild("PetConvertRequest")
		if not remote or not remote:IsA("RemoteFunction") then
			notify("error", "❌ Convert system is not ready yet. Try again in a moment.")
			utilities.Audio.PlayAudio("Click")
			return
		end

		state.busy = true
		refreshUi()
		local requestIds = table.clone(state.selectionIds)
		local ok, success, reason = pcall(function()
			return remote:InvokeServer(requestIds)
		end)
		state.busy = false

		if ok and success == true then
			resetSelection()
		elseif not ok then
			notify("error", "❌ Convert failed. Please try again.")
		else
			if reason == "MixedPets" then
				notify("error", "❌ You can only mark the same type of pets!")
			elseif reason == "PetActive" then
				notify("error", "❌ Pick up your pets before converting them.")
			end
			refreshUi()
		end
		utilities.Audio.PlayAudio("Click")
	end

	if ui.convertButton and ui.convertButton:IsA("GuiButton") then
		ui.convertButton.MouseButton1Click:Connect(submitConvert)
	end
	if ui.convertButtonFrame and ui.convertButtonFrame:IsA("GuiObject") then
		ui.convertButtonFrame.Visible = false
	end

	for _, petFolder in ipairs(petsFolder:GetChildren()) do
		addPetSlot(petFolder)
	end
	petsFolder.ChildAdded:Connect(addPetSlot)
	petsFolder.ChildRemoved:Connect(removePetSlot)
	refreshUi()

	local function setConvertVisible(visible)
		if convertFrame.Visible == visible then return end
		utilities.ButtonHandler.OnClick(convertFrame, state.baseFrameSize)
	end

	local function getConvertRingPart()
		local map = workspace:FindFirstChild("Map")
		local rings = map and map:FindFirstChild("Rings")
		local ring = rings and rings:FindFirstChild("Convert")
		return ring and ring:FindFirstChild("MainPart") or nil
	end

	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		local ringPart = getConvertRingPart()
		if not ringPart then return end
		local inRing = humanoidRootPart and (humanoidRootPart.Position - ringPart.Position).Magnitude < config.RingDistance
		local isVisible = convertFrame.Visible

		if state.wasInRing and state.wasVisible and not isVisible then
			state.ringDismissed = true
		end

		if inRing then
			if not isVisible and not state.ringDismissed then
				setConvertVisible(true)
			end
		else
			if isVisible then
				setConvertVisible(false)
			end
			state.ringDismissed = false
		end

		state.wasInRing = inRing and true or false
		state.wasVisible = convertFrame.Visible
	end)
end)

