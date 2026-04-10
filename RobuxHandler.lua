----RobuxHandler/GamepassHandler
--// Services
local MarketPlaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--// Variables

local GamepassFolder = ReplicatedStorage.Gamepasses
local PetGrantBridgeName = "PetGamepassGrantBridge"
local PetGrantBridge = ReplicatedStorage:FindFirstChild(PetGrantBridgeName)

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
	if not GP then warn("Gamepass: "..GamepassType.Name.." does not exist in Player.Data.Gamepasses! Edit Datastore.Datastore.Values to add it!") return end
	
	local wasOwned = GP.Value
	
	GP.Value = true
	
	if not wasOwned then
		local petsToGrant = getGrantedPetsForGamepass(GamepassType)
		if #petsToGrant > 0 then
			PetGrantBridge:Fire(Player, GamepassType.Name, petsToGrant)
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

local function GetRobuxEgg(Player, Egg)
	local EggInfo = ReplicatedStorage.Eggs[Egg]
	local ChosenPet = GetPet(EggInfo.Pets)
	if ChosenPet ~= nil then
		Player.NonSaveValues.IsOpeningEgg.Value = true
		coroutine.wrap(function()
			task.wait(3)
			Player.NonSaveValues.IsOpeningEgg.Value = false
		end)()
		ReplicatedStorage.Remotes.Egg:InvokeClient(Player, Egg, ChosenPet, 0)
		return ChosenPet
	end
end

function RandomID(Folder)
	local Chance = math.random(1,10000)
	if Folder:FindFirstChild(Chance) then
		return RandomID(Folder) -- reroll if exists
	end
	return Chance
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
		if explicitType ~= "DeveloperProduct" and not hasPetGrantConfig then continue end

		if #petsToGrant > 0 then
			PetGrantBridge:Fire(Player, purchaseEntry.Name, petsToGrant)
		end

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	for _, EggInfo in ReplicatedStorage.Eggs:GetChildren() do
		if not EggInfo:FindFirstChild("ProductId") then continue end

		if tonumber(EggInfo.ProductId.Value) == ReceiptInfo.ProductId then
			local PetChosen = GetRobuxEgg(Player, EggInfo.Name)	-- this selects a random pet from the egg

			--// Create Pet
			local NewPet = game.ReplicatedStorage.Assets.PetTemplate:Clone()
			NewPet.Name = RandomID(Player.Data.Pets)
			NewPet.PetName.Value = PetChosen
			NewPet.Parent = Player.Data.Pets

			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end	
end
