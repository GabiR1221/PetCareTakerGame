--// Pet Inventory
local PetInventory = {} -- all pets will be added in this table

local PetFrame = Frames.Pets
local SideFrame = PetFrame.SideFrame
PetFrame.SideFrameBlocker.Visible = true
local PetStateEvent = ReplicatedStorage:FindFirstChild("PetStateEvent")

local IsMultiDeleting = false
local SelectedForDelete = {}
local CanDeletePets = false
local CachedPetStateByKey = {}

local function setDeleteMode(canDelete)
	CanDeletePets = canDelete and true or false
	SideFrame.Delete.Visible = CanDeletePets
	PetFrame.Buttons.MultiDelete.Visible = CanDeletePets

	if not CanDeletePets then
		if IsMultiDeleting then
			IsMultiDeleting = false
			PetFrame.Buttons.MultiDelete.Title.Text = "Multi Delete"
		end

		for _, petId in ipairs(SelectedForDelete) do
			local petSlot = PetFrame.MainFrame.ObjectHolder:FindFirstChild(tostring(petId))
			if petSlot and petSlot:FindFirstChild("Delete") then
				petSlot.Delete.Visible = false
			end
		end
		SelectedForDelete = {}
	end
end

if PetFrame:GetAttribute("CanDeletePets") == nil then
	PetFrame:SetAttribute("CanDeletePets", false)
end
setDeleteMode(PetFrame:GetAttribute("CanDeletePets"))
PetFrame:GetAttributeChangedSignal("CanDeletePets"):Connect(function()
	setDeleteMode(PetFrame:GetAttribute("CanDeletePets"))
end)
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
					NewPet.Delete.Visible = true
				else
					table.remove(SelectedForDelete, table.find(SelectedForDelete, tonumber(PetInstance.Name)))
					NewPet.Delete.Visible = false
				end
			end
			Utilities.Audio.PlayAudio("Click")
		end)
	end
	NewPet.Name = PetInstance.Name
	NewPet.Parent = Parent == nil and PetFrame.MainFrame.ObjectHolder or Parent

	local multiplier = getPetMultiplier(PetInstance)
	if SortTable == nil then
		PetInventory[#PetInventory+1] = {ID = PetInstance.Name, Multiplier = multiplier}
	else
		SortTable[#SortTable+1] = {ID = PetInstance.Name, Multiplier = multiplier}
	end

	return NewPet
end

function UpdateSideFrame(PetInstance) -- PetInstance is the folder in Player.Pets
	CurrentlySelected = tonumber(PetInstance.Name)
	PetFrame.SideFrameBlocker.Visible = false
	
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
	PetFrame.InventoryCounters.Equipped.Text = Player.NonSaveValues.PetsEquipped.Value.."/"..Multipliers.GetMaxPetsEquipped(Player)
end

UpdateCounters()

coroutine.wrap(function()
	task.wait(0.5)
	SortInventory() -- made it wait 0.5 seconds before it sorted inventory because the pets are not yet loaded
end)()

function OnPetAdded(Child) -- this function is ran when a pet is added, which updates the counters & adds a new pet ui instance
	UpdateCounters()
	AddPet(Child)
	SortInventory()
end

function OnPetRemoved(Child)
	UpdateCounters()
	PetFrame.MainFrame.ObjectHolder[Child.Name]:Destroy()
	SortInventory()
end

Data.Pets.ChildAdded:Connect(OnPetAdded)
Data.Pets.ChildRemoved:Connect(OnPetRemoved)

Player.NonSaveValues.PetsEquipped.Changed:Connect(UpdateCounters) -- if player equips a pet

-- Pet Sideframe scripts
Utilities.ButtonAnimations.Create(SideFrame.Delete, 1.04)

if SideFrame:FindFirstChild("Equip") then
	SideFrame.Equip.Visible = false
end

SideFrame.Delete.Click.MouseButton1Click:Connect(function()
	if not CanDeletePets then return end
	Remotes.Pet:FireServer("Delete", CurrentlySelected)
	PetFrame.SideFrameBlocker.Visible = true
	Utilities.Audio.PlayAudio("Click")
end)

-- Bottom Buttons
for _, Button in PetFrame.Buttons:GetChildren() do
	if not Button:IsA("Frame") then continue end
	Utilities.ButtonAnimations.Create(Button)
end

PetFrame.Buttons.MultiDelete.Click.MouseButton1Click:Connect(function()	
	if not CanDeletePets then return end
	IsMultiDeleting = not IsMultiDeleting

	if not IsMultiDeleting then
		PetFrame.Buttons.MultiDelete.Title.Text = "Multi Delete"
		Remotes.Pet:FireServer("Delete", SelectedForDelete)
		for _,v in SelectedForDelete do
			local PetFrame = PetFrame.MainFrame.ObjectHolder[v]
			PetFrame.Delete.Visible = false
		end
		SelectedForDelete = {}
	else
		PetFrame.Buttons.MultiDelete.Title.Text = "Confirm"
	end
	Utilities.Audio.PlayAudio("Click")
end)

if PetFrame.Buttons:FindFirstChild("EquipBest") then
	PetFrame.Buttons.EquipBest.Visible = false
end

if PetFrame.InventoryCounters:FindFirstChild("Equipped") then
	PetFrame.InventoryCounters.Equipped.Visible = false
end

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
