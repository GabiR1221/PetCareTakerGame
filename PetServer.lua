--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

--// Variables
local GameSettings = ReplicatedStorage["Game Settings"]
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Modules = ReplicatedStorage.Modules

local Multipliers = require(Modules.Multipliers)
local PetMultipliers = require(Modules.PetMultipliers)

local Cooldowns = {}
local SELL_RING_MAX_DISTANCE = 12
local PetSellQuoteRemote = Remotes:FindFirstChild("PetSellQuote")
if not PetSellQuoteRemote or not PetSellQuoteRemote:IsA("RemoteFunction") then
	PetSellQuoteRemote = Instance.new("RemoteFunction")
	PetSellQuoteRemote.Name = "PetSellQuote"
	PetSellQuoteRemote.Parent = Remotes
end

local RARITY_MULTIPLIERS = {
	Common = 1,
	Uncommon = 1.25,
	Rare = 1.6,
	Epic = 2.1,
	Legendary = 3,
	Mythical = 4.5,
	Secret = 8,
}

local function disableAllEquipsForPlayer(player)
	if not player then return end
	local data = player:FindFirstChild("Data")
	local petsFolder = data and data:FindFirstChild("Pets")
	if petsFolder then
		for _, pet in ipairs(petsFolder:GetChildren()) do
			local equippedValue = pet:FindFirstChild("Equipped")
			if equippedValue then
				equippedValue.Value = false
			end
		end
	end

	PetMultipliers.Multipliers[player.Name] = {}

	local nonSave = player:FindFirstChild("NonSaveValues")
	if nonSave and nonSave:FindFirstChild("PetsEquipped") then
		nonSave.PetsEquipped.Value = 0
	end

	local playerPetFolder = workspace:FindFirstChild("PlayerPets") and workspace.PlayerPets:FindFirstChild(player.Name)
	if playerPetFolder then
		playerPetFolder:ClearAllChildren()
	end
end


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

local function resolvePetTemplate(petFolder)
	if not petFolder then return nil end
	local petNameValue = petFolder:FindFirstChild("PetName")
	if not petNameValue or type(petNameValue.Value) ~= "string" then return nil end
	local petsContainer = ReplicatedStorage:FindFirstChild("Pets")
	return petsContainer and petsContainer:FindFirstChild(petNameValue.Value)
end

local function resolveSellBasePrice(petFolder, petTemplate)
	local settings = petTemplate and petTemplate:FindFirstChild("Settings")
	local sellValue = settings and (settings:FindFirstChild("Sellprice") or settings:FindFirstChild("SellPrice"))
	local sellPrice = sellValue and tonumber(sellValue.Value)
	if not sellPrice then
		sellPrice = tonumber((petTemplate and (petTemplate:GetAttribute("Sellprice") or petTemplate:GetAttribute("SellPrice"))) or 0)
	end
	return math.max(0, math.floor(sellPrice or 0))
end

local function resolveRarityMultiplier(petTemplate)
	local settings = petTemplate and petTemplate:FindFirstChild("Settings")
	local rawRarity = settings and settings:FindFirstChild("Rarity")
	local explicitMultiplier = settings and settings:FindFirstChild("RarityMultiplier")
	local rarityMultiplier = explicitMultiplier and tonumber(explicitMultiplier.Value) or nil
	if rarityMultiplier then
		return math.max(0, rarityMultiplier)
	end

	local rarityName = rawRarity and tostring(rawRarity.Value) or "Common"
	return RARITY_MULTIPLIERS[rarityName] or 1
end

local function resolvePetLevel(petFolder)
	local levelValue = petFolder and petFolder:FindFirstChild("Level")
	local level = levelValue and tonumber(levelValue.Value) or 1
	return math.max(1, math.floor(level))
end

local function calculatePetSellPrice(player, petFolder)
	if not player or not petFolder then return 0 end
	if not canDeleteFromSellRing(player) then return 0 end

	local petTemplate = resolvePetTemplate(petFolder)
	local basePrice = resolveSellBasePrice(petFolder, petTemplate)
	if basePrice <= 0 then return 0 end

	local level = resolvePetLevel(petFolder)
	local levelMultiplier = 1 + ((level - 1) * 0.15)
	local rarityMultiplier = resolveRarityMultiplier(petTemplate)

	local totalPrice = basePrice * levelMultiplier * rarityMultiplier
	return math.max(0, math.floor(totalPrice))
end




Remotes.Rebirth.OnServerEvent:Connect(function(Player)
	if Cooldowns[Player.Name] == false then
		Cooldowns[Player.Name] = true	
		if GameSettings.RebirthType.Value == "Linear" then
			if Player.Data.PlayerData.Currency.Value >= GameSettings.RebirthBasePrice.Value * (Player.Data.PlayerData.Rebirth.Value + 1) then
				Rebirth(Player)
			end
		else
			if Player.Data.PlayerData.Currency.Value >= GameSettings.RebirthBasePrice.Value * (GameSettings.RebirthMultiplier.Value + 1.25) ^ Player.Data.PlayerData.Rebirth.Value then
				Rebirth(Player)
			end
		end
		task.wait(0.08)
		Cooldowns[Player.Name] = false
	end
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

local function ensurePetUidValue(petFolder, desiredUid)
	if not petFolder then return nil end
	local uidValue = petFolder:FindFirstChild("PetUID")
	if not uidValue then
		uidValue = Instance.new("StringValue")
		uidValue.Name = "PetUID"
		uidValue.Parent = petFolder
	end

	if type(desiredUid) == "string" and desiredUid ~= "" then
		uidValue.Value = desiredUid
	elseif uidValue.Value == "" then
		uidValue.Value = HttpService:GenerateGUID(false)
	end

	return uidValue.Value
end

local function ensureAllPlayerPetUids(player)
	local petsFolder = getPetsFolder(player)
	if not petsFolder then return end

	for _, petFolder in ipairs(petsFolder:GetChildren()) do
		ensurePetUidValue(petFolder)
	end
end

local function createInventoryPet(player, petName, petUid)
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
	ensurePetUidValue(petFolder, petUid)

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

inventoryBridge.Event:Connect(function(player, petName, petUid)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	createInventoryPet(player, petName, petUid)
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
	disableAllEquipsForPlayer(Player)
	return
end

function DeleteAction(Player, Pet) -- this is the action for deleting a pet
	if Pet.Equipped.Value then UnequipPet(Player, Pet) end -- unequip if it's equipped
	Pet:Destroy()
end

function SellAction(Player, Pet)
	local payout = calculatePetSellPrice(Player, Pet)
	if payout <= 0 then return end

	local currencyValue = Player:FindFirstChild("Data")
		and Player.Data:FindFirstChild("PlayerData")
		and Player.Data.PlayerData:FindFirstChild("Currency")
	if not currencyValue then return end

	local petUidValue = Pet:FindFirstChild("PetUID")
	local petUid = petUidValue and tostring(petUidValue.Value) or ""

	currencyValue.Value += payout
	DeleteAction(Player, Pet)

	local sellBridge = ReplicatedStorage:FindFirstChild("PetSellBridge")
	if petUid ~= "" and sellBridge and sellBridge:IsA("BindableEvent") then
		sellBridge:Fire(Player, petUid)
	end
end

PetSellQuoteRemote.OnServerInvoke = function(player, petId)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return 0 end
	local pet = player:FindFirstChild("Data")
		and player.Data:FindFirstChild("Pets")
		and player.Data.Pets:FindFirstChild(tostring(petId))
	if not pet then return 0 end
	return calculatePetSellPrice(player, pet)
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
		elseif Action == "Sell" then
			if not canDeleteFromSellRing(Player) then return end
			SellAction(Player, Pet)
		end

		disableAllEquipsForPlayer(Player)
	else -- there are multiple ids
		if Action == "Equip" then -- equip all pets
			disableAllEquipsForPlayer(Player)

		elseif Action == "Delete" then -- delete all pets
			if not canDeleteFromSellRing(Player) then return end
			for _,PetId in Parameter do
				local Pet = Player.Data.Pets[PetId]
				if not Pet then continue end
				DeleteAction(Player, Pet)				
			end
		end

		disableAllEquipsForPlayer(Player)
	end
end)

Players.PlayerRemoving:Connect(function(Player)
	Cooldowns[Player.Name] = nil
	workspace.PlayerPets[Player.Name]:Destroy()
end)

--// Script

Players.PlayerAdded:Connect(function(Player)
	Cooldowns[Player.Name] = false

	local PetFolder = Instance.new("Folder")
	PetFolder.Name = Player.Name
	PetFolder.Parent = workspace.PlayerPets

	repeat wait() until Player:FindFirstChild("Loaded") and Player.Loaded.Value or Player.Parent == nil
	if Player.Parent == nil then return end
	
	ensureAllPlayerPetUids(Player)
	disableAllEquipsForPlayer(Player)
end)
