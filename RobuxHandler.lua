----RobuxHandler/GamepassHandler
--// Services
local MarketPlaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--// Variables

local GamepassFolder = ReplicatedStorage.Gamepasses
local PassRewardsConfig = require(ReplicatedStorage.Modules.PassRewardsConfig)
local PetGrantBridgeName = "PetGamepassGrantBridge"
local PetGrantBridge = ReplicatedStorage:FindFirstChild(PetGrantBridgeName)
local NotifyEvent = ReplicatedStorage:FindFirstChild("GameNotificationEvent")

if not PetGrantBridge or not PetGrantBridge:IsA("BindableEvent") then
	PetGrantBridge = Instance.new("BindableEvent")
	PetGrantBridge.Name = PetGrantBridgeName
	PetGrantBridge.Parent = ReplicatedStorage
end

--[[
	Optional fallback configuration for pet-pack gamepasses.
	Preferred setup is configuring each ReplicatedStorage.Gamepasses.<Gamepass> with:
	- Attribute "GrantedPetsCsv" (example: "Dog, Cat, Bunny")
]]
local PET_GAMEPASS_CONFIG = {
	-- Example:
	-- ["StarterPetPack"] = {"Dog", "Cat"},
}

local function splitAndTrimCsv(csvText)
	local pets = {}
	if type(csvText) ~= "string" then return pets end

	for rawName in string.gmatch(csvText, "([^,]+)") do
		local cleanName = tostring(rawName):gsub("^%s+", ""):gsub("%s+$", "")
		if cleanName ~= "" then
			table.insert(pets, cleanName)
		end
	end

	return pets
end

local function getGrantedPetsForGamepass(gamepassValueObject)
	if not gamepassValueObject then return {} end

	local configuredCsv = gamepassValueObject:GetAttribute("GrantedPetsCsv")
	local petsFromAttributes = splitAndTrimCsv(configuredCsv)
	if #petsFromAttributes > 0 then
		return petsFromAttributes
	end

	local fallbackPets = PET_GAMEPASS_CONFIG[gamepassValueObject.Name]
	if type(fallbackPets) == "table" and #fallbackPets > 0 then
		return fallbackPets
	end

	return {}
end

local function getPurchaseType(valueObject)
	if not valueObject then return "GamePass" end
	local configuredType = tostring(valueObject:GetAttribute("PurchaseType") or "")
	configuredType = string.lower(configuredType)
	if configuredType == "developerproduct" or configuredType == "devproduct" or configuredType == "product" then
		return "DeveloperProduct"
	end
	return "GamePass"
end

local function grantsPermanentOwnership(valueObject)
	if not valueObject then return false end
	return valueObject:GetAttribute("GrantsPermanentOwnership") == true
end

local function isPremiumPassEntry(valueObject)
	if not valueObject then return false end
	local configuredPremiumName = tostring(PassRewardsConfig.PremiumAccessEntryName or "")
	if configuredPremiumName == "" then return false end
	return string.lower(valueObject.Name) == string.lower(configuredPremiumName)
end

local function markOwnedInData(player, purchaseEntry)
	if not player or not purchaseEntry then return end
	local data = player:FindFirstChild("Data")
	local gamepasses = data and data:FindFirstChild("Gamepasses")
	if not gamepasses or not gamepasses:IsA("Folder") then return end
	local ownedFlag = gamepasses:FindFirstChild(purchaseEntry.Name)
	if ownedFlag and ownedFlag:IsA("BoolValue") then
		ownedFlag.Value = true
		return
	end
	if not ownedFlag then
		local created = Instance.new("BoolValue")
		created.Name = purchaseEntry.Name
		created.Value = true
		created.Parent = gamepasses
	end
end

local function hasInventorySpaceFor(player, requiredSlots)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
	local data = player:FindFirstChild("Data")
	local petsFolder = data and data:FindFirstChild("Pets")
	if not petsFolder then return false end
	local multipliersModule = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("Multipliers")
	if not multipliersModule then return true end
	local multipliers = require(multipliersModule)
	local maxStorage = tonumber(multipliers.GetMaxPetsStorage(player)) or 0
	return (#petsFolder:GetChildren() + math.max(requiredSlots or 0, 0)) <= maxStorage
end

local canPromptRemote = ReplicatedStorage:FindFirstChild("CanPromptPetPurchase")
if not canPromptRemote or not canPromptRemote:IsA("RemoteFunction") then
	canPromptRemote = Instance.new("RemoteFunction")
	canPromptRemote.Name = "CanPromptPetPurchase"
	canPromptRemote.Parent = ReplicatedStorage
end

canPromptRemote.OnServerInvoke = function(player, purchaseEntryName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "InvalidPlayer"
	end
	local purchaseEntry = GamepassFolder:FindFirstChild(tostring(purchaseEntryName or ""))
	if not purchaseEntry then
		return false, "EntryMissing"
	end
	local petsToGrant = getGrantedPetsForGamepass(purchaseEntry)
	if #petsToGrant <= 0 then
		return true, "NoPetGrant"
	end
	if not hasInventorySpaceFor(player, #petsToGrant) then
		return false, "InventoryFull"
	end
	return true, "Allowed"
end


function GetGamepassFromID(ID)
	for _, Gamepass in GamepassFolder:GetChildren() do
		if Gamepass.Value == ID then
			return Gamepass
		end
	end
	return nil
end

MarketPlaceService.PromptGamePassPurchaseFinished:Connect(function(Player, Gamepass, Succes)
	if not Succes then return end

	local GamepassType = GetGamepassFromID(Gamepass)
	if GamepassType == nil then return end -- Gamepass does not exist in the game!	

	local GP = Player.Data.Gamepasses:FindFirstChild(GamepassType.Name)
	if not GP then
		GP = Instance.new("BoolValue")
		GP.Name = GamepassType.Name
		GP.Value = false
		GP.Parent = Player.Data.Gamepasses
	end
	
	local wasOwned = GP.Value
	
	GP.Value = true
	
	if not wasOwned then
		local petsToGrant = getGrantedPetsForGamepass(GamepassType)
		if #petsToGrant > 0 then
			if not hasInventorySpaceFor(Player, #petsToGrant) then
				NotifyEvent:FireClient(Player, "error", "❌ Purchase blocked: free pet inventory slots before buying this pet pack.")
				return
			end
			PetGrantBridge:Fire(Player, GamepassType.Name, petsToGrant)
			NotifyEvent:FireClient(Player, "success", "✅ Purchase successful! Pet pack added to your inventory.")
		end
	end
end)

local function GetPet(SelectedEgg)
	local TotalWeight = 0
	for _,v in SelectedEgg:GetChildren() do
		TotalWeight += v.Value
	end

	local Chance = Random.new():NextNumber(0.0001,TotalWeight)
	local Counter = 0

	for _,v in SelectedEgg:GetChildren() do
		Counter += v.Value
		if Counter >= Chance then
			return v.Name
		end
	end
end

local function resolveRewardItemType(itemName)
	local accessoriesFolder = ReplicatedStorage:FindFirstChild("Accessories")
	if accessoriesFolder and accessoriesFolder:FindFirstChild(itemName) then
		return "Accessory"
	end
	return "Toy"
end

local function GetRobuxEgg(Player, Egg)
	local EggInfo = ReplicatedStorage.Eggs[Egg]
	local dropsFolder = EggInfo and (EggInfo:FindFirstChild("Pets") or EggInfo:FindFirstChild("Items"))
	local ChosenPet = dropsFolder and GetPet(dropsFolder) or nil
	if ChosenPet ~= nil then
		Player.NonSaveValues.IsOpeningEgg.Value = true
		coroutine.wrap(function()
			task.wait(3)
			Player.NonSaveValues.IsOpeningEgg.Value = false
		end)()
		ReplicatedStorage.Remotes.Egg:InvokeClient(Player, Egg, ChosenPet, 0)
		return ChosenPet, resolveRewardItemType(ChosenPet)
	end
end

function RandomID(Folder)
	local Chance = math.random(1,10000)
	if Folder:FindFirstChild(Chance) then
		return RandomID(Folder) -- reroll if exists
	end
	return Chance
end

local function createInventoryToy(player, toyName, itemTypeRaw)
	local data = player and player:FindFirstChild("Data")
	local itemType = tostring(itemTypeRaw or resolveRewardItemType(toyName))
	local folderName = itemType == "Accessory" and "Accessories" or "Toys"
	local inventoryFolder = data and data:FindFirstChild(folderName)
	if data and not inventoryFolder then
		inventoryFolder = Instance.new("Folder")
		inventoryFolder.Name = folderName
		inventoryFolder.Parent = data
	end
	if not inventoryFolder then return end

	local newItem = Instance.new("Folder")
	newItem.Name = tostring(RandomID(inventoryFolder))
	newItem.Parent = inventoryFolder

	local itemNameValue = Instance.new("StringValue")
	itemNameValue.Name = "ItemName"
	itemNameValue.Value = tostring(toyName)
	itemNameValue.Parent = newItem

	local itemTypeValue = Instance.new("StringValue")
	itemTypeValue.Name = "ItemType"
	itemTypeValue.Value = itemType
	itemTypeValue.Parent = newItem

	local equippedValue = Instance.new("BoolValue")
	equippedValue.Name = "Equipped"
	equippedValue.Value = false
	equippedValue.Parent = newItem
end

MarketPlaceService.ProcessReceipt = function(ReceiptInfo)
	local Player = Players:GetPlayerByUserId(ReceiptInfo.PlayerId)
	if not Player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	for _, purchaseEntry in GamepassFolder:GetChildren() do
		if tonumber(purchaseEntry.Value) ~= tonumber(ReceiptInfo.ProductId) then continue end
		local explicitType = getPurchaseType(purchaseEntry)
		local petsToGrant = getGrantedPetsForGamepass(purchaseEntry)
		local hasPetGrantConfig = #petsToGrant > 0
		local hasPermanentOwnershipGrant = explicitType == "DeveloperProduct" and (grantsPermanentOwnership(purchaseEntry) or isPremiumPassEntry(purchaseEntry))
		if explicitType ~= "DeveloperProduct" and not hasPetGrantConfig then continue end
		if explicitType == "DeveloperProduct" and not hasPetGrantConfig and not hasPermanentOwnershipGrant then continue end

		if #petsToGrant > 0 then
			if not hasInventorySpaceFor(Player, #petsToGrant) then
				NotifyEvent:FireClient(Player, "error", "❌ Inventory full. Purchase will be delivered after you free space.")
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			PetGrantBridge:Fire(Player, purchaseEntry.Name, petsToGrant)
			NotifyEvent:FireClient(Player, "success", "✅ Purchase successful! Pet pack added to your inventory.")
		end
		if hasPermanentOwnershipGrant then
			markOwnedInData(Player, purchaseEntry)
		end

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	for _, EggInfo in ReplicatedStorage.Eggs:GetChildren() do
		if not EggInfo:FindFirstChild("ProductId") then continue end

		if tonumber(EggInfo.ProductId.Value) == ReceiptInfo.ProductId then
			local PetChosen, itemType = GetRobuxEgg(Player, EggInfo.Name)	-- this selects a random item from the egg
			if not PetChosen then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end

			--// Create Toy Inventory Item
			createInventoryToy(Player, PetChosen, itemType)

			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	local spinReceiptBridge = ReplicatedStorage:FindFirstChild("SpinWheelHandleReceipt")
	if spinReceiptBridge and spinReceiptBridge:IsA("BindableFunction") then
		local ok, result = pcall(function()
			return spinReceiptBridge:Invoke(ReceiptInfo)
		end)
		if ok and result == Enum.ProductPurchaseDecision.PurchaseGranted then
			return result
		elseif not ok then
			warn("[RobuxHandler] SpinWheel receipt bridge failed: " .. tostring(result))
		end
	end

	local foodReceiptBridge = ReplicatedStorage:FindFirstChild("FoodShopHandleReceipt")
	if foodReceiptBridge and foodReceiptBridge:IsA("BindableFunction") then
		local ok, result = pcall(function()
			return foodReceiptBridge:Invoke(ReceiptInfo)
		end)
		if ok and result == Enum.ProductPurchaseDecision.PurchaseGranted then
			return result
		elseif not ok then
			warn("[RobuxHandler] FoodShop receipt bridge failed: " .. tostring(result))
		end
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end
