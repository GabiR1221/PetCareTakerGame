--// Rebirth
local RebirthPrice, RebirthMulti = GameSettings.RebirthBasePrice.Value, GameSettings.RebirthMultiplier.Value
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TycoonRebirthEvent = ReplicatedStorage:WaitForChild("TycoonRebirthEvent")
local GetTycoonRebirthRequirements = ReplicatedStorage:WaitForChild("TycoonGetRebirthRequirementsFunction")

local LocalNotifyBridge = ReplicatedStorage:FindFirstChild("ClientNotificationEvent")
if not LocalNotifyBridge or not LocalNotifyBridge:IsA("BindableEvent") then
	LocalNotifyBridge = Instance.new("BindableEvent")
	LocalNotifyBridge.Name = "ClientNotificationEvent"
	LocalNotifyBridge.Parent = ReplicatedStorage
end

local function notifyLocal(notificationType, message)
	if LocalNotifyBridge and LocalNotifyBridge:IsA("BindableEvent") then
		LocalNotifyBridge:Fire(notificationType, message)
	end
end

local RebirthCanBuy = true
local RebirthRequirementsHolder = nil
local RebirthPetSlots = {}

local LOCKED_BUTTON_COLOR = Color3.fromRGB(115, 115, 115)
local UNLOCKED_BUTTON_COLOR = Color3.fromRGB(44, 202, 100)

local function clearRequirementSlot(slot)
	if not slot then return end
	local viewport = slot:FindFirstChild("Display")
	if viewport and viewport:IsA("ViewportFrame") then
		for _, child in ipairs(viewport:GetChildren()) do
			child:Destroy()
		end
	end
end

local function ensureRequirementsHolder()
	if RebirthRequirementsHolder and RebirthRequirementsHolder.Parent then
		return RebirthRequirementsHolder
	end

	local existing = Frames.Rebirth:FindFirstChild("PetRequirementsHolder")
	if existing and existing:IsA("Frame") then
		RebirthRequirementsHolder = existing
	else
		local holder = Instance.new("Frame")
		holder.Name = "PetRequirementsHolder"
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(1, -20, 0, 105)
		holder.Position = UDim2.new(0, 10, 0, 112)
		holder.ClipsDescendants = true
		holder.Parent = Frames.Rebirth
		RebirthRequirementsHolder = holder
	end

	local layout = RebirthRequirementsHolder:FindFirstChild("RequirementsLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.Name = "RequirementsLayout"
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = RebirthRequirementsHolder
	end

	return RebirthRequirementsHolder
end

local function ensurePetRequirementSlot(slotId)
	local holder = ensureRequirementsHolder()
	local key = tostring(slotId)
	local slot = RebirthPetSlots[key]
	if slot and slot.Parent == holder then
		return slot
	end

	local frame = Instance.new("Frame")
	frame.Name = key
	frame.Size = UDim2.new(0, 76, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
	frame.BorderSizePixel = 0
	frame.Parent = holder

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(62, 62, 62)
	stroke.Parent = frame

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Display"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.new(1, -8, 0, 58)
	viewport.Position = UDim2.new(0, 4, 0, 4)
	viewport.Parent = frame

	local check = Instance.new("TextLabel")
	check.Name = "Check"
	check.BackgroundTransparency = 1
	check.Size = UDim2.new(0, 18, 0, 18)
	check.Position = UDim2.new(1, -21, 0, 2)
	check.Font = Enum.Font.GothamBold
	check.TextScaled = true
	check.Text = "✓"
	check.TextColor3 = Color3.fromRGB(85, 255, 127)
	check.Visible = false
	check.Parent = frame

	local petName = Instance.new("TextLabel")
	petName.Name = "PetName"
	petName.BackgroundTransparency = 1
	petName.Size = UDim2.new(1, -8, 0, 35)
	petName.Position = UDim2.new(0, 4, 1, -35)
	petName.TextColor3 = Color3.fromRGB(255, 255, 255)
	petName.TextSize = 12
	petName.TextWrapped = true
	petName.TextYAlignment = Enum.TextYAlignment.Top
	petName.TextXAlignment = Enum.TextXAlignment.Center
	petName.Parent = frame

	RebirthPetSlots[key] = frame
	return frame
end

local function renderPetInSlot(slot, petName, isOwned)
	if not slot then return end
	clearRequirementSlot(slot)

	local display = slot:FindFirstChild("Display")
	local check = slot:FindFirstChild("Check")
	local label = slot:FindFirstChild("PetName")
	if label then
		label.Text = tostring(petName)
	end
	if check then
		check.Visible = isOwned and true or false
	end
	slot.BackgroundColor3 = isOwned and Color3.fromRGB(30, 62, 34) or Color3.fromRGB(38, 38, 38)

	if not (display and display:IsA("ViewportFrame")) then return end

	local template = ReplicatedStorage:FindFirstChild("Pets") and ReplicatedStorage.Pets:FindFirstChild(tostring(petName))
	if not template then return end

	local model = template:Clone()
	model.Parent = display
	local mainPart = model:FindFirstChild("MainPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not mainPart then
		model:Destroy()
		return
	end

	model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(180), 0))
	local cam = Instance.new("Camera")
	cam.Parent = display
	display.CurrentCamera = cam
	local pos = mainPart.Position
	cam.CFrame = CFrame.new(Vector3.new(pos.X + model:GetExtentsSize().X * 1.5, pos.Y, pos.Z + 1), pos)
end

local function updateBuyButtonState(isUnlocked)
	RebirthCanBuy = isUnlocked and true or false
	local clickButton = Frames.Rebirth.Buy.Click
	clickButton.Active = RebirthCanBuy
	clickButton.AutoButtonColor = RebirthCanBuy
	Frames.Rebirth.Buy.BackgroundColor3 = RebirthCanBuy and UNLOCKED_BUTTON_COLOR or LOCKED_BUTTON_COLOR
	if Frames.Rebirth.Buy:FindFirstChild("Title") then
		Frames.Rebirth.Buy.Title.Text = RebirthCanBuy and "Rebirth" or "Locked"
	end
end

local function FormatCurrencyRequirements(requiredCurrency)
	local formatted = {}
	for currencyName, amount in pairs(requiredCurrency or {}) do
		local cleanName = tostring(currencyName)
		table.insert(formatted, Utilities.Short.en(tonumber(amount) or 0).." "..cleanName)
	end
	table.sort(formatted)
	return table.concat(formatted, ", ")
end

local function UpdatePetRequirementsUi(requiredPets, requiredPetStatus)
	local holder = ensureRequirementsHolder()
	local activeSlots = {}

	if type(requiredPets) ~= "table" or #requiredPets == 0 then
		holder.Visible = false
		for _, slot in pairs(RebirthPetSlots) do
			clearRequirementSlot(slot)
			slot.Visible = false
		end
		return
	end

	holder.Visible = true
	for order, petName in ipairs(requiredPets) do
		local slot = ensurePetRequirementSlot(order)
		local owned = type(requiredPetStatus) == "table" and requiredPetStatus[tostring(petName)] == true
		slot.LayoutOrder = order
		slot.Visible = true
		renderPetInSlot(slot, petName, owned)
		activeSlots[tostring(order)] = true
	end

	for key, slot in pairs(RebirthPetSlots) do
		if not activeSlots[key] then
			clearRequirementSlot(slot)
			slot.Visible = false
		end
	end
	return table.concat(requiredPets, ", ")
end

function UpdateRebirthInfo()
	Frames.Rebirth.Counter.Text = "You have "..Utilities.Short.en(PlayerData.Rebirth.Value).." Rebirths"
	local success, requirements = pcall(function()
		return GetTycoonRebirthRequirements:InvokeServer()
	end)

	if success and type(requirements) == "table" then
		local limit = tonumber(requirements.RebirthLimit) or 0
		local current = tonumber(requirements.RebirthCount) or 0
		local nextTier = tonumber(requirements.NextTier) or (current + 1)
		local completion = tonumber(requirements.CompletionPercentage) or 100
		local currentCompletion = tonumber(requirements.CurrentCompletionPercentage) or 0
		local requiredCurrencyText = FormatCurrencyRequirements(requirements.RequiredCurrency)
		local requiredPetsCount = type(requirements.RequiredPets) == "table" and #requirements.RequiredPets or 0
		local hasRequiredPets = requirements.HasRequiredPets == true
		local hasRequiredCurrency = requirements.HasRequiredCurrency == true
		local completionMet = currentCompletion >= completion
		local canRebirthNow = requirements.IsEligible == true
		if limit > 0 and current >= limit then
			canRebirthNow = false
		end

		UpdatePetRequirementsUi(requirements.RequiredPets, requirements.RequiredPetStatus)

		if limit > 0 and current >= limit then
			Frames.Rebirth.Description.Text = "Tycoon rebirth limit reached ("..current.."/"..limit..")"
			Frames.Rebirth.Cost.Text = "No more rebirths available"
			updateBuyButtonState(false)
		else
			local petStatusText = requiredPetsCount > 0 and (hasRequiredPets and "pets ✅" or "pets ❌") or "pets: none"
			local currencyStatusText = hasRequiredCurrency and "currency ✅" or "currency ❌"
			Frames.Rebirth.Description.Text = "Tycoon Rebirth "..nextTier.." | Progress "..math.floor(currentCompletion).."% / "..math.floor(completion).."% | "..petStatusText.." | "..currencyStatusText
			Frames.Rebirth.Cost.Text = "Required Currency: "..(requiredCurrencyText ~= "" and requiredCurrencyText or "None")
			updateBuyButtonState(canRebirthNow and completionMet and hasRequiredCurrency and hasRequiredPets)
		end
		return
	end

	updateBuyButtonState(true)
	if GameSettings.RebirthType.Value == "Linear" then
		Frames.Rebirth.Description.Text = "Buying a Rebirth will increase your "..GameSettings.CurrencyName.Value.." Multiplier with x"..RebirthMulti
		Frames.Rebirth.Cost.Text = "You need atleast "..Utilities.Short.en(RebirthPrice * (PlayerData.Rebirth.Value + 1)).." "..GameSettings.CurrencyName.Value
	elseif GameSettings.RebirthType.Value == "Exponential" then
		Frames.Rebirth.Description.Text = "Buying a Rebirth will increase your "..GameSettings.CurrencyName.Value.." Multiplier with ^"..(RebirthMulti+0.5)
		Frames.Rebirth.Cost.Text = "You need atleast "..Utilities.Short.en(RebirthPrice * ((RebirthMulti+1.25) ^ PlayerData.Rebirth.Value)).." "..GameSettings.CurrencyName.Value
	end
end

UpdateRebirthInfo()

PlayerData.Rebirth.Changed:Connect(function()
	UpdateRebirthInfo()
end)

Utilities.ButtonAnimations.Create(Frames.Rebirth.Buy)

Frames.Rebirth.Buy.Click.MouseButton1Click:Connect(function()
	if not RebirthCanBuy then
		notifyLocal("error", "❌ You can't rebirth yet. Complete the listed requirements first.")
		Utilities.Audio.PlayAudio("Click")
		return
	end
	Remotes.Rebirth:FireServer()
	if TycoonRebirthEvent then
		TycoonRebirthEvent:FireServer()
	end
	notifyLocal("info", "⏳ Rebirth request sent...")
	Utilities.Audio.PlayAudio("Click")
end)

task.spawn(function()
	while true do
		task.wait(2)
		if Frames and Frames.Rebirth and Frames.Rebirth.Visible then
			UpdateRebirthInfo()
		end
	end
end)
