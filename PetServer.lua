--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--// Variables
local GameSettings = ReplicatedStorage["Game Settings"]
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Modules = ReplicatedStorage.Modules

local Multipliers = require(Modules.Multipliers)
local PetMultipliers = require(Modules.PetMultipliers)

local Cooldowns = {}
local SELL_RING_MAX_DISTANCE = 12

local function canDeleteFromSellRing(player)
	if not player then return false end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local map = workspace:FindFirstChild("Map")
	local rings = map and map:FindFirstChild("Rings")
	local sellRing = rings and rings:FindFirstChild("Sell")
	local sellMainPart = sellRing and sellRing:FindFirstChild("MainPart")
	if not sellMainPart or not sellMainPart:IsA("BasePart") then
		return false
	end

	return (hrp.Position - sellMainPart.Position).Magnitude <= SELL_RING_MAX_DISTANCE
end

--// Script

Players.PlayerAdded:Connect(function(Player)
	Cooldowns[Player.Name] = false

	local PetFolder = Instance.new("Folder")
	PetFolder.Name = Player.Name
	PetFolder.Parent = workspace.PlayerPets

	repeat wait() until Player:FindFirstChild("Loaded") and Player.Loaded.Value or Player.Parent == nil
	if Player.Parent == nil then return end

	LoadEquipped(Player)
end)

Players.PlayerRemoving:Connect(function(Player)
	Cooldowns[Player.Name] = nil
	workspace.PlayerPets[Player.Name]:Destroy()
end)

local InventoryBridgeName = "PetInventoryAdoptionBridge"

local function getPetsFolder(player)
	if not player then return nil end
	local data = player:FindFirstChild("Data")
	if not data then return nil end
	return data:FindFirstChild("Pets")
end

local function getNextPetId(petsFolder)
	local nextId = 1
	for _, child in ipairs(petsFolder:GetChildren()) do
		local numericId = tonumber(child.Name)
		if numericId and numericId >= nextId then
			nextId = numericId + 1
		end
	end
	return tostring(nextId)
end

local function createInventoryPet(player, petName)
	if type(petName) ~= "string" then return nil end
	if not ReplicatedStorage:FindFirstChild("Pets") then return nil end
	if not ReplicatedStorage.Pets:FindFirstChild(petName) then
		warn(("[PetServer] Could not grant '%s' to %s because ReplicatedStorage.Pets entry is missing"):format(tostring(petName), player.Name))
		return nil
	end

	local petsFolder = getPetsFolder(player)
	if not petsFolder then
		warn(("[PetServer] Could not grant '%s' to %s because Player.Data.Pets is missing"):format(tostring(petName), player.Name))
		return nil
	end

	if Multipliers.GetMaxPetsStorage(player) <= #petsFolder:GetChildren() then
		warn(("[PetServer] Could not grant '%s' to %s because storage is full"):format(tostring(petName), player.Name))
		return nil
	end

	local petFolder = Instance.new("Folder")
	petFolder.Name = getNextPetId(petsFolder)
	petFolder.Parent = petsFolder

	local petNameValue = Instance.new("StringValue")
	petNameValue.Name = "PetName"
	petNameValue.Value = petName
	petNameValue.Parent = petFolder

	local equippedValue = Instance.new("BoolValue")
	equippedValue.Name = "Equipped"
	equippedValue.Value = false
	equippedValue.Parent = petFolder

	return petFolder
end

local inventoryBridge = ReplicatedStorage:FindFirstChild(InventoryBridgeName)
if not inventoryBridge or not inventoryBridge:IsA("BindableEvent") then
	inventoryBridge = Instance.new("BindableEvent")
	inventoryBridge.Name = InventoryBridgeName
	inventoryBridge.Parent = ReplicatedStorage
end

inventoryBridge.Event:Connect(function(player, petName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	createInventoryPet(player, petName)
end)


-- Pet
function LoadEquipped(Player)
	local EquippedPets = PetMultipliers.Multipliers[Player.Name]

	for PetId, Value in EquippedPets do
		local PetModel = workspace.PlayerPets[Player.Name]:FindFirstChild(PetId)

		if not PetModel then
			local PetInstance = Player.Data.Pets[PetId]
			local NewPet = ReplicatedStorage.Pets[PetInstance.PetName.Value]:Clone()
			NewPet.Name = PetId

			for _, Part in NewPet:GetChildren() do
				if Part:IsA("BasePart") then
					Part.Anchored = true
				end
			end

			local Billboard = script.BillboardGui:Clone()
			Billboard.PetName.Text = PetInstance.PetName.Value
			Billboard.PetRarity.Text = ReplicatedStorage.Pets[PetInstance.PetName.Value].Settings.Rarity.Value
			Billboard.StudsOffset = Vector3.new(0, NewPet.MainPart.Size.Y, 0)
			Billboard.Parent = NewPet

			NewPet:PivotTo(Player.Character.HumanoidRootPart.CFrame)			
			NewPet.Parent = workspace.PlayerPets[Player.Name]
		end
	end

	for _,PlayerPet in workspace.PlayerPets[Player.Name]:GetChildren() do
		if not EquippedPets[tonumber(PlayerPet.Name)] then
			PlayerPet:Destroy()
		end
	end
end

function EquipPet(Player, Pet)
	if Pet.Equipped.Value then return end -- Already equipped
	if Multipliers.GetMaxPetsEquipped(Player) <= Player.NonSaveValues.PetsEquipped.Value then return end -- Too many pets equipped
	Pet.Equipped.Value = true
	PetMultipliers.AddPet(Player.Name, Pet)
	Player.NonSaveValues.PetsEquipped.Value = PetMultipliers.GetPetsEquipped(Player.Name)
end

function UnequipPet(Player, Pet)
	if not Pet.Equipped.Value then return end -- Already unequipped
	Pet.Equipped.Value = false
	PetMultipliers.RemovePet(Player.Name, tonumber(Pet.Name))
	Player.NonSaveValues.PetsEquipped.Value = PetMultipliers.GetPetsEquipped(Player.Name)
end

function EquipAction(Player, Pet) -- this is the action for equipping a pet
	if Pet.Equipped.Value then
		UnequipPet(Player, Pet)
	else
		EquipPet(Player, Pet)
	end
end

function DeleteAction(Player, Pet) -- this is the action for deleting a pet
	if Pet.Equipped.Value then UnequipPet(Player, Pet) end -- unequip if it's equipped
	Pet:Destroy()
end

Remotes.Pet.OnServerEvent:Connect(function(Player, Action, Parameter)
	if type(Parameter) ~= "table" then -- so if this condition is true, then Parameter should be the id of the pet
		local Pet = Player.Data.Pets[Parameter]
		if not Pet then return end

		if Action == "Equip" then
			EquipAction(Player, Pet)
		elseif Action == "Delete" then
			if not canDeleteFromSellRing(Player) then return end
			DeleteAction(Player, Pet)
		end

		LoadEquipped(Player)
	else -- there are multiple ids
		if Action == "Equip" then -- equip all pets
			for _,PetId in Parameter do
				local Pet = Player.Data.Pets[PetId]
				if not Pet then continue end
				EquipAction(Player, Pet)
			end

		elseif Action == "Delete" then -- delete all pets
			if not canDeleteFromSellRing(Player) then return end
			for _,PetId in Parameter do
				local Pet = Player.Data.Pets[PetId]
				if not Pet then continue end
				DeleteAction(Player, Pet)				
			end
		end

		LoadEquipped(Player)
	end
end)
