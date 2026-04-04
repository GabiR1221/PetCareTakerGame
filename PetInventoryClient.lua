--// Pet Inventory
local PetInventory = {} -- all pets will be added in this table

local PetFrame = Frames.Pets
local SideFrame = PetFrame.SideFrame
PetFrame.SideFrameBlocker.Visible = true

local IsMultiDeleting = false
local SelectedForDelete = {}

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
			PetFrame.MainFrame.ObjectHolder[PetInfo.ID].LayoutOrder = Order + (Data.Pets[PetInfo.ID].Equipped.Value and 0 or 1000) -- order + 1000 if equipped
		else
			ObjectHolder[PetInfo.ID].LayoutOrder = Order + (Data.Pets[PetInfo.ID].Equipped.Value and 0 or 1000) -- order + 1000 if equipped
		end
	end
end

local CurrentlySelected = 0

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
		NewPet.Equipped.Visible = PetInstance.Equipped.Value

		PetInstance.Equipped.Changed:Connect(function()
			NewPet.Equipped.Visible = PetInstance.Equipped.Value

			if CurrentlySelected == tonumber(PetInstance.Name) then
				UpdateSideFrame(PetInstance)
			end

			SortInventory()
		end)

		NewPet.Button.MouseButton1Click:Connect(function()
			if not IsMultiDeleting then
				UpdateSideFrame(PetInstance)
			else
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

	SideFrame.Title.Text = PetInstance.PetName.Value
	SideFrame.Equip.Title.Text = PetInstance.Equipped.Value and "Unequip" or "Equip"
	SideFrame.Equip.BackgroundColor3 = PetInstance.Equipped.Value and Color3.fromRGB(36, 136, 2) or Color3.fromRGB(56, 218, 3) 

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
Utilities.ButtonAnimations.Create(SideFrame.Equip, 1.04)
Utilities.ButtonAnimations.Create(SideFrame.Delete, 1.04)

SideFrame.Equip.Click.MouseButton1Click:Connect(function()
	Remotes.Pet:FireServer("Equip", CurrentlySelected)
	Utilities.Audio.PlayAudio("Click")
end)

SideFrame.Delete.Click.MouseButton1Click:Connect(function()
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

PetFrame.Buttons.EquipBest.Click.MouseButton1Click:Connect(function()
	local EquipBest = {}

	for i = 1, Multipliers.GetMaxPetsEquipped(Player) do -- find best equips
		if not PetInventory[i] then break end
		table.insert(EquipBest, PetInventory[i].ID)
	end

	for _, Pet in Data.Pets:GetChildren() do
		local Pos = table.find(EquipBest, Pet.Name)
		if Pet.Equipped.Value and Pos ~= nil then -- pet is already equipped
			table.remove(EquipBest, Pos)
		elseif Pet.Equipped.Value and Pos == nil then -- pet is equipped but should be unequipped
			table.insert(EquipBest, 1, Pet.Name)
		end
	end

	Remotes.Pet:FireServer("Equip", EquipBest)	
	Utilities.Audio.PlayAudio("Click")
end)
