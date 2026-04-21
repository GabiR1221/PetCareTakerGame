--// Pet Inventory
local PetInventory = {} -- all pets will be added in this table

local PetFrame = Frames.Pets
local SideFrame = PetFrame.SideFrame
local SellShopFrame = Frames:FindFirstChild("SellShop")
local SellObjectHolder = SellShopFrame and SellShopFrame:FindFirstChild("PetsHolder") and SellShopFrame.PetsHolder:FindFirstChild("ObjectHolder")
PetFrame.SideFrameBlocker.Visible = true
local PetStateEvent = ReplicatedStorage:FindFirstChild("PetStateEvent")
local PetSellQuoteRemote = Remotes:FindFirstChild("PetSellQuote")

local IsMultiDeleting = false
local SelectedForDelete = {}
local CanDeletePets = false
local CachedPetStateByKey = {}
local SellSlotByPetId = {}
local OpenSellFramePetId = nil

local function setSideFrameOpen(isOpen)
	if not SideFrame then return end
	SideFrame.Visible = isOpen and true or false
	PetFrame.SideFrameBlocker.Visible = not isOpen

	if not isOpen then
		if SideFrame.Display and SideFrame.Display:FindFirstChild("PetModel") then
			SideFrame.Display.PetModel:Destroy()
		end
		if SideFrame:FindFirstChild("Title") then
			SideFrame.Title.Visible = true
		end
	end
end

setSideFrameOpen(false)

if PetFrame:GetAttribute("CanDeletePets") == nil then
	PetFrame:SetAttribute("CanDeletePets", false)
end

PetFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if not PetFrame.Visible and PetFrame:GetAttribute("CanDeletePets") then
		PetFrame:SetAttribute("CanDeletePets", false)
	end
end)

local function getPetTemplate(petInstance)
	if not petInstance then return nil end
	local petNameValue = petInstance:FindFirstChild("PetName")
	if not petNameValue then return nil end
	return ReplicatedStorage.Pets:FindFirstChild(petNameValue.Value)
end

local function getPetMultiplier(petInstance)
	local template = getPetTemplate(petInstance)
	local settings = template and template:FindFirstChild("Settings")
	local multiplier = settings and settings:FindFirstChild("Multiplier")
	return (multiplier and tonumber(multiplier.Value)) or 1
end

local function getPetUidFromFolder(petFolder)
	local uidValue = petFolder and petFolder:FindFirstChild("PetUID")
	local uid = uidValue and uidValue.Value or nil
	if type(uid) ~= "string" or uid == "" then
		return nil
	end
	return uid
end


function SortInventory(SortTable, ObjectHolder)
	local TableToSort = SortTable ~= nil and SortTable or PetInventory -- so it can differentiate between trade and normal inventories

	table.sort(TableToSort, function(a,b)
		if not a or not b then return end

		if a.Multiplier ~= b.Multiplier then
			return a.Multiplier > b.Multiplier
		else
			return a.ID > b.ID
		end
	end)

	for Order,PetInfo in TableToSort do
		if not Data.Pets:FindFirstChild(PetInfo.ID) then
			table.remove(TableToSort, Order)
			continue
		end

		if not ObjectHolder then
			PetFrame.MainFrame.ObjectHolder[PetInfo.ID].LayoutOrder = Order
		else
			ObjectHolder[PetInfo.ID].LayoutOrder = Order
		end
	end
end

local CurrentlySelected = 0

local getSelectedPetKeys
local updateSideFrameState

local function findDescendantByNameInsensitive(root, targetName)
	if not root or not targetName then return nil end
	local lowerTarget = string.lower(targetName)
	for _, desc in ipairs(root:GetDescendants()) do
		if string.lower(desc.Name) == lowerTarget then
			return desc
		end
	end
	return nil
end

local function findSideFrameObject(name)
	return SideFrame:FindFirstChild(name) or findDescendantByNameInsensitive(SideFrame, name)
end

local function getCachedStateForPetFolder(petFolder)
	if not petFolder then return nil end
	local petId = tostring(petFolder.Name)
	local petName = petFolder:FindFirstChild("PetName") and petFolder.PetName.Value or nil
	local petUid = getPetUidFromFolder(petFolder)

	return (petUid and CachedPetStateByKey[petUid])
		or CachedPetStateByKey[petId]
		or (petUid and CachedPetStateByKey["inv:"..petUid])
		or CachedPetStateByKey["invId:"..petId]
		or (petName and CachedPetStateByKey[tostring(petName)])
end

local function getSellFrameParts(slotFrame)
	if not slotFrame then return nil, nil, nil end
	local sellFrame = slotFrame:FindFirstChild("SellFrame") or findDescendantByNameInsensitive(slotFrame, "SellFrame")
	if not sellFrame then return nil, nil, nil end

	local sellButton = sellFrame:FindFirstChild("SellButton")
		or sellFrame:FindFirstChild("Sell")
		or findDescendantByNameInsensitive(sellFrame, "SellButton")
	local titleLabel = sellFrame:FindFirstChild("TitleLabel")
		or sellFrame:FindFirstChild("Title")
		or findDescendantByNameInsensitive(sellFrame, "TitleLabel")
	return sellFrame, sellButton, titleLabel
end

local function getSellFrameTemplate()
	if not SellShopFrame then return nil end
	local template = SellShopFrame:FindFirstChild("SellFrame") or findDescendantByNameInsensitive(SellShopFrame, "SellFrame")
	if template and template:IsA("GuiObject") then
		template.Visible = false
	end
	return template
end

local function ensureSellFrameExists(slotFrame)
	if not slotFrame then return nil, nil, nil end
	local sellFrame, sellButton, titleLabel = getSellFrameParts(slotFrame)
	if sellFrame then
		return sellFrame, sellButton, titleLabel
	end

	local template = getSellFrameTemplate()
	if not template then
		return nil, nil, nil
	end

	local cloned = template:Clone()
	cloned.Name = "SellFrame"
	cloned.Visible = false
	cloned.Parent = slotFrame
	return getSellFrameParts(slotFrame)
end

local function requestSellPriceFromServer(petId)
	if not PetSellQuoteRemote then return 0 end
	local ok, result = pcall(function()
		return PetSellQuoteRemote:InvokeServer(tostring(petId))
	end)
	if not ok then return 0 end
	return math.max(0, math.floor(tonumber(result) or 0))
end

local function updateSellSlotText(petFolder, slotFrame)
	if not petFolder or not slotFrame then return end
	local sellFrame, _, titleLabel = getSellFrameParts(slotFrame)
	if not sellFrame or not titleLabel then return end

	local petId = tostring(petFolder.Name)
	local cachedState = getCachedStateForPetFolder(petFolder)
	local levelValue = petFolder:FindFirstChild("Level")
	local level = (levelValue and levelValue.Value) or (cachedState and cachedState.level) or 1

	local quotedPrice = requestSellPriceFromServer(petId)
	titleLabel.Text = ("Sell for %s (Lv.%s)"):format(Utilities.Short.en(quotedPrice), tostring(math.max(1, math.floor(tonumber(level) or 1))))
end

local function closeAllSellFrames(exceptPetId)
	for petId, slotFrame in pairs(SellSlotByPetId) do
		if exceptPetId ~= nil and tostring(petId) == tostring(exceptPetId) then
			continue
		end
		local sellFrame = slotFrame and (slotFrame:FindFirstChild("SellFrame") or findDescendantByNameInsensitive(slotFrame, "SellFrame"))
		if sellFrame then
			sellFrame.Visible = false
		end
	end
end


function AddPet(PetInstance, SortTable, Parent) -- Creates a pet slot
	task.wait(0.1)
	local NewPet = script.PetTemplate:Clone()

	local PetTemplate = getPetTemplate(PetInstance)
	if not PetTemplate then
		warn(("[PetInventoryClient] Missing ReplicatedStorage.Pets model for inventory pet '%s'"):format(tostring(PetInstance.Name)))
		NewPet:Destroy()
		return nil
	end
	local PetModel = PetTemplate:Clone()
	PetModel.Parent = NewPet.Display

	local MainPart = PetModel:FindFirstChild("MainPart") or PetModel.PrimaryPart or PetModel:FindFirstChildWhichIsA("BasePart", true)
	local Pos

	if not MainPart then
		warn(PetModel.Name.." does not have a BasePart, could not render inventory slot")
		NewPet:Destroy()
		return nil
	end

	Pos = MainPart.Position
	local Camera = Instance.new("Camera")
	NewPet.Display.CurrentCamera = Camera
	PetModel:PivotTo(PetModel:GetPivot() * CFrame.Angles(0, math.rad(180), 0))
	Camera.CFrame = CFrame.new(Vector3.new(Pos.X + PetModel:GetExtentsSize().X * 1.5, Pos.Y, Pos.Z + 1), Pos)

	if not Parent then -- normal pet
		NewPet.Equipped.Visible = false

		NewPet.Button.MouseButton1Click:Connect(function()
			if not IsMultiDeleting then
				UpdateSideFrame(PetInstance)
			else
				if not CanDeletePets then return end
				if not table.find(SelectedForDelete, tonumber(PetInstance.Name)) then
					table.insert(SelectedForDelete, tonumber(PetInstance.Name))
				else
					table.remove(SelectedForDelete, table.find(SelectedForDelete, tonumber(PetInstance.Name)))
				end
			end
			Utilities.Audio.PlayAudio("Click")
		end)
	end
	NewPet.Name = PetInstance.Name
	NewPet.Parent = Parent == nil and PetFrame.MainFrame.ObjectHolder or Parent
	
	if Parent == SellObjectHolder then
		SellSlotByPetId[PetInstance.Name] = NewPet
		closeAllSellFrames()

		local sellFrame, sellButton, _ = ensureSellFrameExists(NewPet)
		if sellFrame then
			sellFrame.Visible = false
		end
		updateSellSlotText(PetInstance, NewPet)

		NewPet.Button.MouseButton1Click:Connect(function()
			local myPetId = tostring(PetInstance.Name)
			local shouldOpen = OpenSellFramePetId ~= myPetId
			closeAllSellFrames(myPetId)
			local thisSellFrame = NewPet:FindFirstChild("SellFrame") or findDescendantByNameInsensitive(NewPet, "SellFrame")
			if thisSellFrame then
				thisSellFrame.Visible = shouldOpen
			end
			OpenSellFramePetId = shouldOpen and myPetId or nil
			updateSellSlotText(PetInstance, NewPet)
			Utilities.Audio.PlayAudio("Click")
		end)

		if sellButton and sellButton:IsA("GuiButton") then
			sellButton.MouseButton1Click:Connect(function()
				Remotes.Pet:FireServer("Sell", tonumber(PetInstance.Name))
				Utilities.Audio.PlayAudio("Click")
			end)
		end
	end

	local multiplier = getPetMultiplier(PetInstance)
	if Parent == nil and SortTable == nil then
		PetInventory[#PetInventory+1] = {ID = PetInstance.Name, Multiplier = multiplier}
	elseif SortTable ~= nil then
		SortTable[#SortTable+1] = {ID = PetInstance.Name, Multiplier = multiplier}
	end

	return NewPet
end

function UpdateSideFrame(PetInstance) -- PetInstance is the folder in Player.Pets
	CurrentlySelected = tonumber(PetInstance.Name)
	setSideFrameOpen(true)
	
	if SideFrame:FindFirstChild("Title") then
		SideFrame.Title.Visible = false
	end

	if SideFrame.Display:FindFirstChild("PetModel") then
		SideFrame.Display.PetModel:Destroy()
	end

	local PetTemplate = getPetTemplate(PetInstance)
	if not PetTemplate then
		SideFrame.Multiplier.Amount.Text = "x1"
		return
	end
	local PetModel = PetTemplate:Clone()
	PetModel.Name = "PetModel"
	PetModel.Parent = SideFrame.Display

	local MainPart = PetModel:FindFirstChild("MainPart") or PetModel.PrimaryPart or PetModel:FindFirstChildWhichIsA("BasePart", true)
	if not MainPart then
		SideFrame.Multiplier.Amount.Text = "x"..Utilities.Short.en(getPetMultiplier(PetInstance))
		return
	end
	local Pos = MainPart.Position
	local Camera = Instance.new("Camera")
	SideFrame.Display.CurrentCamera = Camera
	PetModel:PivotTo(PetModel:GetPivot() * CFrame.Angles(0, math.rad(180), 0))
	Camera.CFrame = CFrame.new(Vector3.new(Pos.X + PetModel:GetExtentsSize().X * 1.5, Pos.Y, Pos.Z + 1), Pos)

	SideFrame.Multiplier.Amount.Text = "x"..Utilities.Short.en(getPetMultiplier(PetInstance))
	local selectedPetId, selectedPetName, selectedPetUid = getSelectedPetKeys()
	local cachedState = selectedPetId and (
		(selectedPetUid and CachedPetStateByKey[selectedPetUid])
			or CachedPetStateByKey[selectedPetId]
			or (selectedPetUid and CachedPetStateByKey["inv:"..selectedPetUid])
			or (selectedPetId and CachedPetStateByKey["invId:"..selectedPetId])
			or (selectedPetName and CachedPetStateByKey[tostring(selectedPetName)])
	) or nil
	if cachedState then
		updateSideFrameState(cachedState)
	elseif PetStateEvent then
		pcall(function()
			PetStateEvent:FireServer("RequestOwnedPetsState")
		end)
	end
end

local function setBar(sideFrame, barName, value, maxValue)
	local barFill = sideFrame:FindFirstChild(barName) or findDescendantByNameInsensitive(sideFrame, barName)
	if not barFill then return end

	maxValue = maxValue and math.max(maxValue, 1) or 100
	local normalizedValue = math.clamp((tonumber(value) or 0) / maxValue, 0, 1)
	barFill.Size = UDim2.new(normalizedValue, 0, barFill.Size.Y.Scale, barFill.Size.Y.Offset)

	local textLabel = barFill:FindFirstChild("Text")
		or barFill:FindFirstChild("Amount")
		or barFill:FindFirstChildWhichIsA("TextLabel")
		or barFill.Parent and barFill.Parent:FindFirstChild(barName:gsub("Fill", "Text"))
		or (barFill.Parent and (barFill.Parent:FindFirstChild("Text") or barFill.Parent:FindFirstChild("Amount") or barFill.Parent:FindFirstChildWhichIsA("TextLabel")))
	if textLabel then
		textLabel.Text = ("%d / %d"):format(math.floor(tonumber(value) or 0), math.floor(maxValue))
	end
end

updateSideFrameState = function(payload)
	if not payload or not SideFrame or PetFrame.SideFrameBlocker.Visible then return end

	setBar(SideFrame, "hungerbarfill", payload.hunger, 100)
	setBar(SideFrame, "wetbarfill", payload.wetness, 100)
	setBar(SideFrame, "dirtbarfill", payload.dirtiness, 100)
	setBar(SideFrame, "happinessbarfill", payload.happiness, 100)

	local xpFill = findSideFrameObject("xpbarfill")
	if xpFill then
		local progress = math.clamp(tonumber(payload.levelProgress) or 0, 0, 1)
		xpFill.Size = UDim2.new(progress, 0, xpFill.Size.Y.Scale, xpFill.Size.Y.Offset)
		local xpText = xpFill:FindFirstChild("Text")
			or xpFill:FindFirstChild("Amount")
			or xpFill:FindFirstChildWhichIsA("TextLabel")
			or (xpFill.Parent and (xpFill.Parent:FindFirstChild("Text") or xpFill.Parent:FindFirstChild("Amount") or xpFill.Parent:FindFirstChildWhichIsA("TextLabel")))
		if xpText then
			if payload.xpInLevel and payload.xpForNext and payload.xpForNext ~= math.huge then
				xpText.Text = ("%d / %d XP"):format(math.max(0, payload.xpInLevel), math.max(1, math.floor(payload.xpForNext)))
			else
				xpText.Text = ("%d XP"):format(math.max(0, payload.xp or 0))
			end
		end
	end
end

getSelectedPetKeys = function()
	if CurrentlySelected == 0 then return nil, nil, nil end
	local selectedId = tostring(CurrentlySelected)
	local selectedPetFolder = Data.Pets:FindFirstChild(selectedId)
	local selectedPetName = selectedPetFolder and selectedPetFolder:FindFirstChild("PetName") and selectedPetFolder.PetName.Value or nil
	local selectedPetUid = getPetUidFromFolder(selectedPetFolder)
	return selectedId, selectedPetName, selectedPetUid
end

local function updateSideFrameState(payload)
	if not payload or not SideFrame or PetFrame.SideFrameBlocker.Visible then return end

	setBar(SideFrame, "hungerbarfill", payload.hunger, 100)
	setBar(SideFrame, "wetbarfill", payload.wetness, 100)
	setBar(SideFrame, "dirtbarfill", payload.dirtiness, 100)
	setBar(SideFrame, "happinessbarfill", payload.happiness, 100)

	local xpFill = findSideFrameObject("xpbarfill")
	if xpFill then
		local progress = math.clamp(tonumber(payload.levelProgress) or 0, 0, 1)
		xpFill.Size = UDim2.new(progress, 0, xpFill.Size.Y.Scale, xpFill.Size.Y.Offset)
		local xpText = xpFill:FindFirstChild("Text")
			or xpFill:FindFirstChild("Amount")
			or xpFill:FindFirstChildWhichIsA("TextLabel")
			or (xpFill.Parent and (xpFill.Parent:FindFirstChild("Text") or xpFill.Parent:FindFirstChild("Amount") or xpFill.Parent:FindFirstChildWhichIsA("TextLabel")))
		if xpText then
			if payload.xpInLevel and payload.xpForNext and payload.xpForNext ~= math.huge then
				xpText.Text = ("%d / %d XP"):format(math.max(0, payload.xpInLevel), math.max(1, math.floor(payload.xpForNext)))
			else
				xpText.Text = ("%d XP"):format(math.max(0, payload.xp or 0))
			end
		end
	end
end

local function getSelectedPetKeys()
	if CurrentlySelected == 0 then return nil, nil, nil end
	local selectedId = tostring(CurrentlySelected)
	local selectedPetFolder = Data.Pets:FindFirstChild(selectedId)
	local selectedPetName = selectedPetFolder and selectedPetFolder:FindFirstChild("PetName") and selectedPetFolder.PetName.Value or nil
	local selectedPetUid = getPetUidFromFolder(selectedPetFolder)
	return selectedId, selectedPetName, selectedPetUid
end



for _,v in Data.Pets:GetChildren() do -- load pets on join
	coroutine.wrap(function()
		AddPet(v)
	end)()
end


function UpdateCounters()
	PetFrame.InventoryCounters.Storage.Text = #Player.Data.Pets:GetChildren().."/"..Multipliers.GetMaxPetsStorage(Player)
end

UpdateCounters()

coroutine.wrap(function()
	task.wait(0.5)
	SortInventory() -- made it wait 0.5 seconds before it sorted inventory because the pets are not yet loaded
end)()

function OnPetAdded(Child) -- this function is ran when a pet is added, which updates the counters & adds a new pet ui instance
	UpdateCounters()
	AddPet(Child)
	if SellObjectHolder then
		AddPet(Child, nil, SellObjectHolder)
		SortInventory(nil, SellObjectHolder)
	end
	SortInventory()
end

function OnPetRemoved(Child)
	UpdateCounters()
	if tonumber(Child.Name) == tonumber(CurrentlySelected) then
		CurrentlySelected = 0
		setSideFrameOpen(false)
	end
	if PetFrame.MainFrame.ObjectHolder:FindFirstChild(Child.Name) then
		PetFrame.MainFrame.ObjectHolder[Child.Name]:Destroy()
	end
	if SellObjectHolder and SellObjectHolder:FindFirstChild(Child.Name) then
		SellObjectHolder[Child.Name]:Destroy()
	end
	SellSlotByPetId[Child.Name] = nil
	if OpenSellFramePetId == tostring(Child.Name) then
		OpenSellFramePetId = nil
	end
	SortInventory()
	if SellObjectHolder then
		SortInventory(nil, SellObjectHolder)
	end
end

Data.Pets.ChildAdded:Connect(OnPetAdded)
Data.Pets.ChildRemoved:Connect(OnPetRemoved)

if SellObjectHolder then
	for _, petFolder in Data.Pets:GetChildren() do
		coroutine.wrap(function()
			AddPet(petFolder, nil, SellObjectHolder)
		end)()
	end
	coroutine.wrap(function()
		task.wait(0.5)
		SortInventory(nil, SellObjectHolder)
	end)()
end


Player.NonSaveValues.PetsEquipped.Changed:Connect(UpdateCounters) -- if player equips a pet

-- Pet Sideframe scripts

if PetStateEvent then
	local function requestOwnedPetStates()
		pcall(function()
			PetStateEvent:FireServer("RequestOwnedPetsState")
		end)
	end
	
	requestOwnedPetStates()
	task.spawn(function()
		while true do
			task.wait(6)
			requestOwnedPetStates()
		end
	end)
	
	PetStateEvent.OnClientEvent:Connect(function(action, petModel, payload)
		if action ~= "UpdatePetState" or not payload then return end

		local payloadId = tostring(payload.petName or "")
		local modelName = petModel and tostring(petModel.Name) or ""
		local payloadUid = tostring(payload.petUid or "")
		local payloadInventoryId = tostring(payload.inventoryPetId or "")
		if payloadId ~= "" then
			CachedPetStateByKey[payloadId] = payload
		end
		if modelName ~= "" then
			CachedPetStateByKey[modelName] = payload
		end
		if payloadUid ~= "" then
			CachedPetStateByKey[payloadUid] = payload
			CachedPetStateByKey["inv:"..payloadUid] = payload
		end
		if payloadInventoryId ~= "" then
			CachedPetStateByKey[payloadInventoryId] = payload
			CachedPetStateByKey["invId:"..payloadInventoryId] = payload

			local petFolder = Data.Pets:FindFirstChild(payloadInventoryId)
			local sellSlot = SellSlotByPetId[payloadInventoryId]
			if petFolder and sellSlot then
				updateSellSlotText(petFolder, sellSlot)
			end
		end

		local selectedPetId, selectedPetName, selectedPetUid = getSelectedPetKeys()
		if not selectedPetId then return end
		
		if payloadInventoryId ~= "" then
			if payloadInventoryId ~= selectedPetId then return end
			updateSideFrameState(payload)
			return
		end
		if selectedPetUid and selectedPetUid ~= "" then
			if payloadUid ~= selectedPetUid then return end
			updateSideFrameState(payload)
			return
		end


		local payloadCompareId = tostring(payload.petName or (petModel and petModel.Name) or "")
		if payloadCompareId ~= selectedPetId
			and payloadCompareId ~= tostring(selectedPetName)
			and modelName ~= selectedPetId
			and modelName ~= tostring(selectedPetName) then
			return
		end

		updateSideFrameState(payload)
	end)
end

--// Toys Inventory + Pets/Toys menu switching
local function resolveToyFrameRoot()
	if not Frames then return nil end
	local petsFrame = Frames:FindFirstChild("Pets")
	if not petsFrame then return nil end
	return petsFrame
end

local ToySlotById = {}

local function getToyStorageFolder()
	if not Data then return nil end
	return Data:FindFirstChild("Toys") or Data:FindFirstChild("Pets")
end

local function getToyNameFromFolder(toyFolder)
	if not toyFolder then return nil end
	local itemType = toyFolder:FindFirstChild("ItemType")
	if itemType and tostring(itemType.Value) ~= "Toy" and toyFolder:FindFirstChild("ItemName") then
		return nil
	end
	local itemName = toyFolder:FindFirstChild("ItemName")
	if itemName and type(itemName.Value) == "string" and itemName.Value ~= "" then
		return itemName.Value
	end
	local petName = toyFolder:FindFirstChild("PetName")
	if petName and type(petName.Value) == "string" and petName.Value ~= "" then
		return petName.Value
	end
	return nil
end

local function getToyTemplate(toyName)
	if not toyName then return nil end
	local toysFolder = ReplicatedStorage:FindFirstChild("Toys")
	if toysFolder and toysFolder:FindFirstChild(toyName) then
		return toysFolder[toyName]
	end
	local petsFolder = ReplicatedStorage:FindFirstChild("Pets")
	if petsFolder and petsFolder:FindFirstChild(toyName) then
		return petsFolder[toyName]
	end
	return nil
end

local function getToysObjectHolder()
	local petsFrame = resolveToyFrameRoot()
	local toysMainFrame = petsFrame and petsFrame:FindFirstChild("ToysMainFrame")
	if not toysMainFrame then return nil end
	return toysMainFrame:FindFirstChild("ObjectHolder")
end

local function getPrimaryPartForDisplay(instance)
	if not instance then return nil end
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance:FindFirstChild("MainPart") or instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function getDisplaySize(instance)
	if not instance then return Vector3.new(2, 2, 2) end
	if instance:IsA("Model") then
		return instance:GetExtentsSize()
	end
	if instance:IsA("BasePart") then
		return instance.Size
	end
	return Vector3.new(2, 2, 2)
end

local function createToySlot(toyFolder)
	local objectHolder = getToysObjectHolder()
	if not objectHolder or not toyFolder then return end
	if objectHolder:FindFirstChild(toyFolder.Name) then return end

	local toyName = getToyNameFromFolder(toyFolder)
	if not toyName then return end
	local toyTemplate = getToyTemplate(toyName)
	if not toyTemplate then
		warn(("[ToyInventory] Missing toy template for '%s'"):format(tostring(toyName)))
		return
	end

	local slotTemplate = script:FindFirstChild("PetTemplate")
	if not slotTemplate then return end

	local newSlot = slotTemplate:Clone()
	newSlot.Name = toyFolder.Name
	newSlot.Parent = objectHolder
	ToySlotById[toyFolder.Name] = newSlot

	if newSlot:FindFirstChild("Equipped") then
		newSlot.Equipped.Visible = false
	end

	local titleLabel = newSlot:FindFirstChild("Name") or newSlot:FindFirstChild("Title")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = toyName or "Toy"
	end

	local model = toyTemplate:Clone()
	model.Parent = newSlot.Display
	local mainPart = getPrimaryPartForDisplay(model)
	if not mainPart then
		newSlot:Destroy()
		ToySlotById[toyFolder.Name] = nil
		return
	end

	local pos = mainPart.Position
	local camera = Instance.new("Camera")
	newSlot.Display.CurrentCamera = camera
	if model:IsA("Model") then
		model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(180), 0))
	else
		model.CFrame = model.CFrame * CFrame.Angles(0, math.rad(180), 0)
	end
	camera.CFrame = CFrame.new(Vector3.new(pos.X + getDisplaySize(model).X * 1.5, pos.Y, pos.Z + 1), pos)

	local equippedValue = toyFolder:FindFirstChild("Equipped")
	if equippedValue and newSlot:FindFirstChild("Equipped") then
		newSlot.Equipped.Visible = equippedValue.Value == true
		equippedValue.Changed:Connect(function()
			if newSlot and newSlot.Parent and newSlot:FindFirstChild("Equipped") then
				newSlot.Equipped.Visible = equippedValue.Value == true
			end
		end)
	end

	if newSlot:FindFirstChild("Button") and newSlot.Button:IsA("GuiButton") then
		newSlot.Button.MouseButton1Click:Connect(function()
			Remotes.Pet:FireServer("EquipToy", tostring(toyFolder.Name))
			Utilities.Audio.PlayAudio("Click")
		end)
	end
end

local function removeToySlot(toyFolder)
	if not toyFolder then return end
	local holder = getToysObjectHolder()
	if holder and holder:FindFirstChild(toyFolder.Name) then
		holder[toyFolder.Name]:Destroy()
	end
	ToySlotById[toyFolder.Name] = nil
end

local function wirePetsToysMenu()
	local petsFrame = resolveToyFrameRoot()
	if not petsFrame then return end

	local mainFrame = petsFrame:FindFirstChild("MainFrame")
	local toysFrame = petsFrame:FindFirstChild("ToysMainFrame")
	local menusHolder = petsFrame:FindFirstChild("OtherMenusHolder")
	if not mainFrame or not toysFrame or not menusHolder then return end

	local petsButton = menusHolder:FindFirstChild("PetsButton")
	local toysButton = menusHolder:FindFirstChild("ToysButton")

	local function showFrame(frameName)
		mainFrame.Visible = frameName == "Pets"
		toysFrame.Visible = frameName == "Toys"
	end

	showFrame("Pets") -- default view

	if petsButton and petsButton:IsA("GuiButton") and not petsButton:GetAttribute("_Wired") then
		petsButton:SetAttribute("_Wired", true)
		petsButton.MouseButton1Click:Connect(function()
			showFrame("Pets")
			Utilities.Audio.PlayAudio("Click")
		end)
	end

	if toysButton and toysButton:IsA("GuiButton") and not toysButton:GetAttribute("_Wired") then
		toysButton:SetAttribute("_Wired", true)
		toysButton.MouseButton1Click:Connect(function()
			showFrame("Toys")
			Utilities.Audio.PlayAudio("Click")
		end)
	end
end

local toysFolder = getToyStorageFolder()
if toysFolder then
	for _, toyFolder in ipairs(toysFolder:GetChildren()) do
		coroutine.wrap(function()
			createToySlot(toyFolder)
		end)()
	end

	toysFolder.ChildAdded:Connect(function(child)
		createToySlot(child)
	end)

	toysFolder.ChildRemoved:Connect(function(child)
		removeToySlot(child)
	end)
end

wirePetsToysMenu()
