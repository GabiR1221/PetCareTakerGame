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

		if Action == "Equip" then
			EquipAction(Player, Pet)
		elseif Action == "Delete" then
			DeleteAction(Player, Pet)
		end

		LoadEquipped(Player)
	else -- there are multiple ids
		if Action == "Equip" then -- equip all pets
			for _,PetId in Parameter do
				local Pet = Player.Data.Pets[PetId]
				EquipAction(Player, Pet)
			end

		elseif Action == "Delete" then -- delete all pets
			for _,PetId in Parameter do
				local Pet = Player.Data.Pets[PetId]
				DeleteAction(Player, Pet)				
			end
		end

		LoadEquipped(Player)
	end
end)
