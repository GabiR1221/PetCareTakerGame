--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

--// Variables
local GameSettings = ReplicatedStorage["Game Settings"]
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameNotificationEvent = ReplicatedStorage:FindFirstChild("GameNotificationEvent")
local Modules = ReplicatedStorage.Modules
local TycoonUtils
do
	local ok, result = pcall(function()
		return require(script.Parent:WaitForChild("PetSystem"):WaitForChild("Modules"):WaitForChild("TycoonUtils"))
	end)
	if ok then
		TycoonUtils = result
	end
end

local Multipliers = require(Modules.Multipliers)
local PetMultipliers = require(Modules.PetMultipliers)

local Cooldowns = {}
local SELL_RING_MAX_DISTANCE = 12
local PetSellRequestBridgeName = "PetSellRequestBridge"
local PetRuntimeStateBridgeName = "PetRuntimeStateBridge"
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

local function canSellPetFromSource(player, options)
	options = options or {}
	if options.allowOffRing == true then
		return true
	end
	return canDeleteFromSellRing(player)
end

local function isPetCurrentlySpawnedForPlayer(player, petFolder)
	if not player or not petFolder then return false end

	local mirroredLocation = petFolder:FindFirstChild("RuntimeLocation")
	local mirroredLocationName = mirroredLocation and tostring(mirroredLocation.Value or "") or ""
	if mirroredLocationName == "free" or mirroredLocationName == "petground" or mirroredLocationName == "player_wild" or mirroredLocationName == "player" then
		return true
	end

	local uidValue = petFolder:FindFirstChild("PetUID")
	local uid = uidValue and tostring(uidValue.Value) or ""
	if uid == "" then
		if player:GetAttribute("OwnedPetsRuntimeReady") ~= true then
			return true
		end
		return false
	end


	local runtimeBridge = ReplicatedStorage:FindFirstChild(PetRuntimeStateBridgeName)
	if runtimeBridge and runtimeBridge:IsA("BindableFunction") then
		local ok, state = pcall(function()
			return runtimeBridge:Invoke(player, uid)
		end)
		if ok and type(state) == "table" then
			local location = tostring(state.location or "")
			if state.wild == true then
				return true
			end
			return (location == "free" or location == "petground" or location == "player_wild" or location == "player")
		end
	end

	if player:GetAttribute("OwnedPetsRuntimeReady") ~= true then
		return true
	end
	return false
end

local function getToysFolder(player)
	if not player then return nil end
	local data = player:FindFirstChild("Data")
	if not data then return nil end
	local toysFolder = data:FindFirstChild("Toys")
	if not toysFolder then
		toysFolder = Instance.new("Folder")
		toysFolder.Name = "Toys"
		toysFolder.Parent = data
	end
	return toysFolder
end

local function getAccessoriesFolder(player)
	if not player then return nil end
	local data = player:FindFirstChild("Data")
	if not data then return nil end
	local accessoriesFolder = data:FindFirstChild("Accessories")
	if not accessoriesFolder then
		accessoriesFolder = Instance.new("Folder")
		accessoriesFolder.Name = "Accessories"
		accessoriesFolder.Parent = data
	end
	return accessoriesFolder
end

local function ensureToyEquippedValue(toyFolder)
	if not toyFolder then return nil end
	local equipped = toyFolder:FindFirstChild("Equipped")
	if not equipped then
		equipped = Instance.new("BoolValue")
		equipped.Name = "Equipped"
		equipped.Value = false
		equipped.Parent = toyFolder
	end
	return equipped
end

local function getToyNameFromFolder(toyFolder)
	if not toyFolder then return nil end
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

local function getToyInventoryJsonValue(player)
	local data = player and player:FindFirstChild("Data")
	local playerData = data and data:FindFirstChild("PlayerData")
	if not playerData then return nil end

	local jsonValue = playerData:FindFirstChild("ToyInventoryJson")
	if not jsonValue then
		jsonValue = Instance.new("StringValue")
		jsonValue.Name = "ToyInventoryJson"
		jsonValue.Value = ""
		jsonValue.Parent = playerData
	end

	return jsonValue
end

local function serializeToyInventory(player)
	local toysFolder = getToysFolder(player)
	local accessoriesFolder = getAccessoriesFolder(player)
	if not toysFolder and not accessoriesFolder then return "[]" end

	local payload = {}
	local function appendFolder(folder, itemType)
		if not folder then return end
		for _, itemFolder in ipairs(folder:GetChildren()) do
			local toyName = getToyNameFromFolder(itemFolder)
			if toyName and toyName ~= "" then
				local equipped = ensureToyEquippedValue(itemFolder)
				table.insert(payload, {
					id = tostring(itemFolder.Name),
					itemName = tostring(toyName),
					itemType = itemType,
					equipped = equipped and equipped.Value == true or false,
				})
			end
		end
	end

	appendFolder(toysFolder, "Toy")
	appendFolder(accessoriesFolder, "Accessory")

	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if not ok then
		warn("[PetServer] Failed to encode ToyInventoryJson:", tostring(encoded))
		return "[]"
	end

	return encoded
end

local function resolveInventoryTargetFolder(player, itemName, rawItemType)
	local itemType = tostring(rawItemType or "")
	if itemType == "Accessory" then
		return getAccessoriesFolder(player), "Accessory"
	end
	if itemType == "Toy" then
		return getToysFolder(player), "Toy"
	end

	local accessoriesFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Accessories")
	if accessoriesFolder and itemName and accessoriesFolder:FindFirstChild(tostring(itemName)) then
		return getAccessoriesFolder(player), "Accessory"
	end
	return getToysFolder(player), "Toy"
end

local function hydrateToyInventoryFromJson(player)
	local toysFolder = getToysFolder(player)
	local accessoriesFolder = getAccessoriesFolder(player)
	local jsonValue = getToyInventoryJsonValue(player)
	if not toysFolder or not accessoriesFolder or not jsonValue then return end
	if type(jsonValue.Value) ~= "string" or jsonValue.Value == "" then return end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(jsonValue.Value)
	end)
	if not ok or type(decoded) ~= "table" then
		warn("[PetServer] Invalid ToyInventoryJson for", player.Name)
		return
	end

	if #toysFolder:GetChildren() > 0 or #accessoriesFolder:GetChildren() > 0 then
		return -- existing folder data already loaded by datastore; don't overwrite
	end

	for _, entry in ipairs(decoded) do
		if type(entry) == "table" and type(entry.itemName) == "string" and entry.itemName ~= "" then
			local targetFolder, itemType = resolveInventoryTargetFolder(player, entry.itemName, entry.itemType)
			if not targetFolder then
				continue
			end
			local toyFolder = Instance.new("Folder")
			toyFolder.Name = tostring(entry.id or tostring(math.random(10000, 99999)))
			toyFolder.Parent = targetFolder

			local itemName = Instance.new("StringValue")
			itemName.Name = "ItemName"
			itemName.Value = entry.itemName
			itemName.Parent = toyFolder

			local itemTypeValue = Instance.new("StringValue")
			itemTypeValue.Name = "ItemType"
			itemTypeValue.Value = itemType
			itemTypeValue.Parent = toyFolder

			local equipped = ensureToyEquippedValue(toyFolder)
			equipped.Value = (itemType == "Toy") and entry.equipped == true or false
		end
	end
end

local function saveToyInventoryJson(player)
	local jsonValue = getToyInventoryJsonValue(player)
	if not jsonValue then return end
	jsonValue.Value = serializeToyInventory(player)
end

local function setEquippedToy(player, toyId)
	local toysFolder = getToysFolder(player)
	if not toysFolder then return end

	local targetToyFolder = toysFolder:FindFirstChild(tostring(toyId))
	if targetToyFolder then
		local itemType = targetToyFolder:FindFirstChild("ItemType")
		if itemType and tostring(itemType.Value) ~= "Toy" then
			return
		end
	end

	local equippedToyName = ""
	for _, toyFolder in ipairs(toysFolder:GetChildren()) do
		local equipped = ensureToyEquippedValue(toyFolder)
		local shouldEquip = tostring(toyFolder.Name) == tostring(toyId)
		equipped.Value = shouldEquip
		if shouldEquip then
			equippedToyName = tostring(getToyNameFromFolder(toyFolder) or "")
		end
	end

	player:SetAttribute("EquippedToyName", equippedToyName)
	saveToyInventoryJson(player)
end

local function restoreEquippedToyAttribute(player)
	local toysFolder = getToysFolder(player)
	if not toysFolder then return end

	local equippedToyName = ""
	for _, toyFolder in ipairs(toysFolder:GetChildren()) do
		local equipped = ensureToyEquippedValue(toyFolder)
		if equipped.Value == true and equippedToyName == "" then
			equippedToyName = tostring(getToyNameFromFolder(toyFolder) or "")
		else
			equipped.Value = false
		end
	end

	player:SetAttribute("EquippedToyName", equippedToyName)
	saveToyInventoryJson(player)
end

local function resolvePlayerTycoon(player)
	if not player then return nil end
	if TycoonUtils and TycoonUtils.FindTycoonByOwnerId then
		local ok, tycoonFromUtils = pcall(function()
			return TycoonUtils:FindTycoonByOwnerId(player.UserId)
		end)
		if ok and tycoonFromUtils and tycoonFromUtils:IsA("Model") then
			return tycoonFromUtils
		end
	end

	local serverPlayerData = ServerStorage:FindFirstChild("PlayerData")
	local playerFolder = serverPlayerData and serverPlayerData:FindFirstChild(tostring(player.UserId))
	local tycoonValue = playerFolder and playerFolder:FindFirstChild("Tycoon")
	if tycoonValue and tycoonValue:IsA("ObjectValue") and tycoonValue.Value and (tycoonValue.Value:IsA("Model") or tycoonValue.Value:IsA("Folder")) then
		return tycoonValue.Value
	end

	for _, containerName in ipairs({"Tycoons", "Tycoon"}) do
		local root = workspace:FindFirstChild(containerName)
		if root then
			for _, model in ipairs(root:GetDescendants()) do
				if not (model:IsA("Model") or model:IsA("Folder")) then continue end
				if not model:FindFirstChild("Essentials") then continue end
				local ownerAttr = model:GetAttribute("OwnerId") or model:GetAttribute("Owner") or model:GetAttribute("OwnerUserId")
				if ownerAttr and tostring(ownerAttr) == tostring(player.UserId) then
					return model
				end
				for _, key in ipairs({"OwnerId", "Owner", "OwnerUserId"}) do
					local v = model:FindFirstChild(key)
					if v then
						if v:IsA("ObjectValue") and v.Value == player then
							return model
						end
						if tostring(v.Value) == tostring(player.UserId) then
							return model
						end
					end
				end
			end
		end
	end
	return nil
end

local function setToyAnchoredNoCollide(inst)
	if not inst then return end
	if inst:IsA("BasePart") then
		inst.Anchored = true
		inst.CanCollide = false
		return
	end
	for _, desc in ipairs(inst:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end
end

local function syncEquippedToyInTycoon(player)
	local tycoon = resolvePlayerTycoon(player)
	if not tycoon then return end
	local essentials = tycoon:FindFirstChild("Essentials")
	if not essentials then return end

	local runtime = essentials:FindFirstChild("EquippedToyRuntime")
	if runtime then
		runtime:Destroy()
	end

	local equippedToyName = tostring(player:GetAttribute("EquippedToyName") or "")
	if equippedToyName == "" then return end

	local toyTemplates = ReplicatedStorage:FindFirstChild("Toys")
	local toyTemplate = toyTemplates and toyTemplates:FindFirstChild(equippedToyName)
	if not toyTemplate and toyTemplates then
		for _, candidate in ipairs(toyTemplates:GetChildren()) do
			if string.lower(candidate.Name) == string.lower(equippedToyName) then
				toyTemplate = candidate
				break
			end
		end
	end
	if not toyTemplate then
		warn(("[PetServer] Could not spawn equipped toy '%s' for %s; missing ReplicatedStorage.Toys template")
			:format(equippedToyName, player.Name))
		return
	end

	local clone = toyTemplate:Clone()
	clone.Name = "EquippedToyRuntime"
	clone:SetAttribute("IsPetToy", true)
	clone:SetAttribute("ToyType", equippedToyName)
	setToyAnchoredNoCollide(clone)

	local spawnPart = essentials:FindFirstChild("ToySpawn", true) or essentials:FindFirstChild("PetWanderZone", true)
	if spawnPart and spawnPart:IsA("BasePart") then
		if clone:IsA("Model") then
			clone:PivotTo(spawnPart.CFrame + Vector3.new(0, 1.5, 0))
		elseif clone:IsA("BasePart") then
			clone.CFrame = spawnPart.CFrame + Vector3.new(0, 1.5, 0)
		end
	elseif clone:IsA("Model") then
		clone:PivotTo(essentials:GetPivot() + Vector3.new(0, 1.5, 0))
	elseif clone:IsA("BasePart") then
		clone.CFrame = essentials:GetPivot() + Vector3.new(0, 1.5, 0)
	end

	clone.Parent = essentials
end

local function scheduleToyRuntimeSync(player)
	task.spawn(function()
		for _ = 1, 30 do
			if not player or not player.Parent then return end
			syncEquippedToyInTycoon(player)
			local tycoon = resolvePlayerTycoon(player)
			local essentials = tycoon and tycoon:FindFirstChild("Essentials")
			local hasEquipped = tostring(player:GetAttribute("EquippedToyName") or "") ~= ""
			if not hasEquipped then
				return
			end
			if essentials and essentials:FindFirstChild("EquippedToyRuntime") then
				return
			end
			task.wait(1)
		end
	end)
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

local function calculatePetSellPrice(player, petFolder, options)
	if not player or not petFolder then return 0 end
	if not canSellPetFromSource(player, options) then return 0 end
	if isPetCurrentlySpawnedForPlayer(player, petFolder) then return 0 end

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

function SellAction(Player, Pet, options)
	local payout = calculatePetSellPrice(Player, Pet, options)
	if payout <= 0 then return end

	local currencyValue = Player:FindFirstChild("Data")
		and Player.Data:FindFirstChild("PlayerData")
		and Player.Data.PlayerData:FindFirstChild("Currency")
	if not currencyValue then return end

	local petUidValue = Pet:FindFirstChild("PetUID")
	local petUid = petUidValue and tostring(petUidValue.Value) or ""
	local petNameValue = Pet:FindFirstChild("PetName")
	local petName = petNameValue and tostring(petNameValue.Value) or ""

	currencyValue.Value += payout
	DeleteAction(Player, Pet)

	local sellBridge = ReplicatedStorage:FindFirstChild("PetSellBridge")
	if sellBridge and sellBridge:IsA("BindableEvent") then
		sellBridge:Fire(Player, petUid, petName)
	end
	
	return payout
end

PetSellQuoteRemote.OnServerInvoke = function(player, petId)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return 0 end
	local pet = player:FindFirstChild("Data")
		and player.Data:FindFirstChild("Pets")
		and player.Data.Pets:FindFirstChild(tostring(petId))
	if not pet then return 0 end
	return calculatePetSellPrice(player, pet)
end

local petSellRequestBridge = ReplicatedStorage:FindFirstChild(PetSellRequestBridgeName)
if not petSellRequestBridge or not petSellRequestBridge:IsA("BindableFunction") then
	petSellRequestBridge = Instance.new("BindableFunction")
	petSellRequestBridge.Name = PetSellRequestBridgeName
	petSellRequestBridge.Parent = ReplicatedStorage
end

petSellRequestBridge.OnInvoke = function(player, petId, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "InvalidPlayer", 0
	end

	local pets = player:FindFirstChild("Data") and player.Data:FindFirstChild("Pets")
	local pet = pets and pets:FindFirstChild(tostring(petId))
	if not pet then
		return false, "PetMissing", 0
	end

	local payout = SellAction(player, pet, options)
	if not payout or payout <= 0 then
		return false, "SellRejected", 0
	end

	return true, "Sold", payout
end


Remotes.Pet.OnServerEvent:Connect(function(Player, Action, Parameter)
	if Action == "EquipToy" then
		setEquippedToy(Player, tostring(Parameter or ""))
		scheduleToyRuntimeSync(Player)
		return
	end

	if type(Parameter) ~= "table" then -- so if this condition is true, then Parameter should be the id of the pet
		local Pet = Player.Data.Pets:FindFirstChild(tostring(Parameter))
		if not Pet then return end

		if Action == "Equip" then
			EquipAction(Player, Pet)
		elseif Action == "Delete" then
			if not canDeleteFromSellRing(Player) then return end
			DeleteAction(Player, Pet)
		elseif Action == "Sell" then
			local payout = SellAction(Player, Pet, { allowOffRing = true, source = "SellUI" })
			if (not payout or payout <= 0) and GameNotificationEvent and GameNotificationEvent:IsA("RemoteEvent") then
				GameNotificationEvent:FireClient(Player, "error", "❌ You can't sell wandering pets.")
			end
		end

		disableAllEquipsForPlayer(Player)
	else -- there are multiple ids
		if Action == "Equip" then -- equip all pets
			disableAllEquipsForPlayer(Player)

		elseif Action == "Delete" then -- delete all pets
			if not canDeleteFromSellRing(Player) then return end
			for _,PetId in Parameter do
				local Pet = Player.Data.Pets:FindFirstChild(tostring(PetId))
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
	hydrateToyInventoryFromJson(Player)
	restoreEquippedToyAttribute(Player)
	scheduleToyRuntimeSync(Player)
	local toysFolder = getToysFolder(Player)
	if toysFolder then
		toysFolder.ChildAdded:Connect(function()
			task.defer(saveToyInventoryJson, Player)
		end)
		toysFolder.ChildRemoved:Connect(function()
			task.defer(saveToyInventoryJson, Player)
		end)
	end
	local accessoriesFolder = getAccessoriesFolder(Player)
	if accessoriesFolder then
		accessoriesFolder.ChildAdded:Connect(function()
			task.defer(saveToyInventoryJson, Player)
		end)
		accessoriesFolder.ChildRemoved:Connect(function()
			task.defer(saveToyInventoryJson, Player)
		end)
	end
	disableAllEquipsForPlayer(Player)
end)

-- Clicker
Remotes.Clicker.OnServerEvent:Connect(function(Player)
	if GameSettings.GameType.Value ~= "Clicker" then return end

	if Cooldowns[Player.Name] == false then
		Cooldowns[Player.Name] = true
		Player.Data.PlayerData.Currency.Value += 1 * Multipliers.CurrencyMultiplier(Player)
		Player.Data.PlayerData.TotalCurrency.Value += 1 * Multipliers.CurrencyMultiplier(Player)
		task.wait(0.08)
		Cooldowns[Player.Name] = false
	end
end)

-- Music
Remotes.Setting.OnServerEvent:Connect(function(Player, SettingName, Toggled)
	Player.Data.PlayerData[SettingName].Value = Toggled
end)

-- Rebirth
function Rebirth(Player) -- this will run the action when you passed all requirements for rebirthing
	Player.Data.PlayerData.Currency.Value = 0
	Player.Data.PlayerData.Rebirth.Value += 1
	Player.Data.PlayerData.Currency2.Value += 10 -- gems
end

-- Egg
function RandomID(Folder)
	local Chance = math.random(1,10000)
	if Folder:FindFirstChild(Chance) then
		return RandomID(Folder) -- reroll if exists
	end
	return Chance
end

local function getInventoryFolder(player, itemType)
	local data = player and player:FindFirstChild("Data")
	if not data then return nil end
	local folderName = (tostring(itemType) == "Accessory") and "Accessories" or "Toys"
	local inventoryFolder = data:FindFirstChild(folderName)
	if not inventoryFolder then
		inventoryFolder = Instance.new("Folder")
		inventoryFolder.Name = folderName
		inventoryFolder.Parent = data
	end
	return inventoryFolder
end

local function getTotalInventoryCount(player)
	local data = player and player:FindFirstChild("Data")
	if not data then return 0 end
	local toys = data:FindFirstChild("Toys")
	local accessories = data:FindFirstChild("Accessories")
	return (toys and #toys:GetChildren() or 0) + (accessories and #accessories:GetChildren() or 0)
end

local function resolveItemType(itemName)
	local accessoriesFolder = ReplicatedStorage:FindFirstChild("Accessories")
	if accessoriesFolder and accessoriesFolder:FindFirstChild(itemName) then
		return "Accessory"
	end
	return "Toy"
end

local function getInventoryStorageLimit(player)
	if Multipliers and Multipliers.GetMaxPetsStorage then
		return tonumber(Multipliers.GetMaxPetsStorage(player)) or 0
	end
	return 0
end

local function shouldAutoDelete(player, itemName)
	local autoDeleteFolder = player and player:FindFirstChild("Data") and player.Data:FindFirstChild("AutoDelete")
	if not autoDeleteFolder then return false end
	local entry = autoDeleteFolder:FindFirstChild(tostring(itemName))
	return entry and entry:IsA("BoolValue") and entry.Value == true
end

local function createInventoryItem(player, itemNameRaw, itemTypeRaw)
	local itemNameText = tostring(itemNameRaw or "")
	if itemNameText == "" then return false end

	local itemType = string.lower(tostring(itemTypeRaw or ""))
	if itemType == "" then
		itemType = string.lower(resolveItemType(itemNameText))
	end
	local accessoriesRoot = ReplicatedStorage:FindFirstChild("Accessories")
	local toysRoot = ReplicatedStorage:FindFirstChild("Toys")
	if accessoriesRoot and accessoriesRoot:FindFirstChild(itemNameText) then
		itemType = "Accessory"
	elseif toysRoot and toysRoot:FindFirstChild(itemNameText) then
		itemType = "Toy"
	elseif itemType == "accessory" then
		itemType = "Accessory"
	else
		itemType = "Toy"
	end

	local inventoryFolder = getInventoryFolder(player, itemType)
	if not inventoryFolder then return false end

	local newItem = Instance.new("Folder")
	newItem.Name = tostring(RandomID(inventoryFolder))
	newItem.Parent = inventoryFolder

	local itemName = Instance.new("StringValue")
	itemName.Name = "ItemName"
	itemName.Value = itemNameText
	itemName.Parent = newItem

	local itemTypeValue = Instance.new("StringValue")
	itemTypeValue.Name = "ItemType"
	itemTypeValue.Value = itemType
	itemTypeValue.Parent = newItem

	local equipped = Instance.new("BoolValue")
	equipped.Name = "Equipped"
	equipped.Value = false
	equipped.Parent = newItem
	return true
end

_G.createInventoryItem = createInventoryItem

function ChooseRandomPet(Egg, LuckMultiplier)
	local EggInfo = ReplicatedStorage.Eggs[Egg]
	local Pets, TotalWeight = {}, 0

	local dropsFolder = EggInfo and (EggInfo:FindFirstChild("Pets") or EggInfo:FindFirstChild("Items"))
	if not dropsFolder then
		return nil, nil
	end

	for _, Pet in dropsFolder:GetChildren() do
		local itemType = Pet:GetAttribute("ItemType")
		if not itemType and Pet:FindFirstChild("ItemType") then
			itemType = Pet.ItemType.Value
		end
		table.insert(Pets, {Pet.Name, Pet.Value, tostring(itemType or resolveItemType(Pet.Name))})
	end

	table.sort(Pets, function(a,b)
		return a[2] > b[2]
	end)

	local BaseChance = Pets[1][2] -- this is the most common pet

	for _,v in Pets do
		local Chance = math.min(v[2] * LuckMultiplier, BaseChance) -- so if the easiest pet is 70%, all pets will go towards 70% 
		TotalWeight += Chance
		v[2] = Chance
	end

	local Chance = Random.new():NextNumber(0,TotalWeight)

	local Counter = 0
	for _,v in Pets do	
		Counter += v[2]

		if Counter >= Chance then
			return v[1], v[3]
		end
	end
end

Remotes.Egg.OnServerInvoke = function(Player, Egg, Amount)
	if Player.NonSaveValues.IsOpeningEgg.Value then return end -- cooldown
	if getTotalInventoryCount(Player) + Amount > getInventoryStorageLimit(Player) then return end -- max storage

	local EggInfo = ReplicatedStorage.Eggs:FindFirstChild(Egg)

	if not EggInfo then print(Egg.." does not exist!") return end -- egg does not exist!
	if EggInfo:FindFirstChild("ProductId") then return end -- robux egg

	if Amount == 3 and ReplicatedStorage.Gamepasses:FindFirstChild("TripleEgg") and not Player.Data.Gamepasses.TripleEgg.Value then
		return -- if this is true, it means the player is trying to open a triple egg while there is a gamepass which they don't own
	end

	if Player.Data.PlayerData.Currency.Value >= EggInfo.Cost.Value * Amount then
		Player.Data.PlayerData.Currency.Value -= EggInfo.Cost.Value * Amount
		Player.Data.PlayerData.EggsHatched.Value += Amount
		Player.NonSaveValues.IsOpeningEgg.Value = true

		coroutine.wrap(function()
			task.wait(3)
			Player.NonSaveValues.IsOpeningEgg.Value = false
		end)()

		local Results = {}

		local LuckMultiplier = Multipliers.GetLuckMultiplier(Player)

		for i = 1, Amount do
			local itemName, itemType = ChooseRandomPet(Egg, LuckMultiplier)

			if itemName and not shouldAutoDelete(Player, itemName) then -- auto delete
				createInventoryItem(Player, itemName, itemType)
			end

			Results[i] = itemName
		end

		return Results
	end
end

--// Auto Delete
Remotes.AutoDelete.OnServerInvoke = function(Player, Pet)
	Player.Data.AutoDelete[Pet].Value = not Player.Data.AutoDelete[Pet].Value
	return Player.Data.AutoDelete[Pet].Value
end

--// Area
Remotes.Area.OnServerEvent:Connect(function(Player)
	if Cooldowns[Player.Name] == true then return end
	Cooldowns[Player.Name] = true

	coroutine.wrap(function()
		task.wait(0.08)
		Cooldowns[Player.Name] = false
	end)()

	local NextArea = ReplicatedStorage.Areas:FindFirstChild(Player.Data.PlayerData.BestZone.Value + 1)
	if not NextArea then return end


	if Player.Data.PlayerData.Currency.Value < NextArea.Cost.Value then return end

	if NextArea.Cost.Value == -1 then return end -- max area

	Player.Data.PlayerData.Currency.Value -= NextArea.Cost.Value
	Player.Data.PlayerData.BestZone.Value = tonumber(NextArea.Name)
end)

--// Gemshop
local GemUpgradePurchaseBridgeName = "GemUpgradePurchaseBridge"
local GemUpgradePurchaseBridge = ReplicatedStorage:FindFirstChild(GemUpgradePurchaseBridgeName)
if not GemUpgradePurchaseBridge or not GemUpgradePurchaseBridge:IsA("BindableEvent") then
	GemUpgradePurchaseBridge = Instance.new("BindableEvent")
	GemUpgradePurchaseBridge.Name = GemUpgradePurchaseBridgeName
	GemUpgradePurchaseBridge.Parent = ReplicatedStorage
end

local function resolveGemUpgrade(player, upgradeName)
	local gemShopFolder = ReplicatedStorage:FindFirstChild("GemShop")
	local playerData = player and player:FindFirstChild("Data") and player.Data:FindFirstChild("PlayerData")
	if not gemShopFolder or not playerData then return nil, nil end

	local key = tostring(upgradeName or "")
	local gemUpgrade = gemShopFolder:FindFirstChild(key)
	local upgradeTier = playerData:FindFirstChild("GemUpgrade" .. key)
	if not gemUpgrade or not upgradeTier or not upgradeTier:IsA("IntValue") then
		return nil, nil
	end

	return gemUpgrade, upgradeTier
end

local function calculateUpgradePrice(gemUpgrade, currentTier)
	if not gemUpgrade then return nil end
	local priceConfig = gemUpgrade:FindFirstChild("Price")
	if not priceConfig then return nil end

	local defaultPrice = priceConfig:FindFirstChild("DefaultPrice")
	local increasePer = priceConfig:FindFirstChild("IncreasePer")
	local exponential = priceConfig:FindFirstChild("Exponential")
	if not defaultPrice or not increasePer or not exponential then return nil end

	if exponential.Value then
		return defaultPrice.Value * (increasePer.Value ^ currentTier)
	end
	return defaultPrice.Value + increasePer.Value * (currentTier + 1)
end

local function getBulkPurchaseCost(gemUpgrade, currentTier, purchaseCount)
	local maxValue = gemUpgrade and gemUpgrade:FindFirstChild("Max")
	if not maxValue then return nil, 0 end

	local remaining = math.max(maxValue.Value - currentTier, 0)
	local requested = math.max(math.floor(tonumber(purchaseCount) or 0), 0)
	if requested <= 0 then
		return 0, 0
	end
	if requested > remaining then
		return nil, 0
	end
	local canBuy = requested
	if canBuy <= 0 then
		return 0, 0
	end

	local totalCost = 0
	for offset = 0, canBuy - 1 do
		local cost = calculateUpgradePrice(gemUpgrade, currentTier + offset)
		if not cost then
			return nil, 0
		end
		totalCost += cost
	end

	return totalCost, canBuy
end

local function buyGemUpgrade(player, upgradeName, purchaseCount)
	local gemUpgrade, upgradeTier = resolveGemUpgrade(player, upgradeName)
	if not gemUpgrade or not upgradeTier then return false end
	local allowedCounts = {
		[1] = true,
		[5] = true,
		[10] = true,
	}
	local requested = math.floor(tonumber(purchaseCount) or 0)
	if not allowedCounts[requested] then
		return false
	end

	local playerData = player.Data.PlayerData
	local currency = playerData:FindFirstChild("Currency")
	if not currency then return false end

	local totalCost, grantedLevels = getBulkPurchaseCost(gemUpgrade, upgradeTier.Value, requested)
	if not totalCost or grantedLevels <= 0 then return false end
	if currency.Value < totalCost then return false end

	currency.Value -= totalCost
	upgradeTier.Value += grantedLevels
	return true
end

local function grantGemUpgradeLevels(player, upgradeName, amount)
	local gemUpgrade, upgradeTier = resolveGemUpgrade(player, upgradeName)
	if not gemUpgrade or not upgradeTier then return false end

	local maxValue = gemUpgrade:FindFirstChild("Max")
	if not maxValue then return false end

	local levelsToAdd = math.max(math.floor(tonumber(amount) or 0), 0)
	if levelsToAdd <= 0 then return false end

	local remaining = math.max(maxValue.Value - upgradeTier.Value, 0)
	if levelsToAdd > remaining then return false end
	upgradeTier.Value += levelsToAdd
	return true
end

Remotes.GemUpgrade.OnServerEvent:Connect(function(player, upgradeName, purchaseCount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end	
	buyGemUpgrade(player, upgradeName, purchaseCount or 1)
end)

GemUpgradePurchaseBridge.Event:Connect(function(player, upgradeName, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	grantGemUpgradeLevels(player, upgradeName, amount)
end)
