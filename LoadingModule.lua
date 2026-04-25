--LoadingModule as child of DataStoreModule
--// Configure
local LoadingFunctions = {}
local Values = require(script.Parent.Values)
local DS = game:GetService("DataStoreService")

local RS = game:GetService("ReplicatedStorage")
local PlayerData = DS:GetDataStore(RS["Game Settings"].DataSave.Value)
local SessionLock = require(script.Parent:WaitForChild("SessionLock"))
local MPS = game:GetService("MarketplaceService")

local PetMultipliers = require(RS.Modules.PetMultipliers)
local PassRewardsConfig = require(RS.Modules.PassRewardsConfig)

local function CreateFolder(Player,FolderName)
	local NewFolder = Instance.new("Folder")
	NewFolder.Name = FolderName
	NewFolder.Parent = Player
	return NewFolder
end

local function getSaveValueObject(playerDataFolder, folderName, valueName)
	local folder = playerDataFolder and playerDataFolder:FindFirstChild(folderName)
	if not folder then return nil end
	return folder:FindFirstChild(valueName)
end

LoadingFunctions.LoadData = function(Player)
	-- Attempt to atomically acquire a session lock
	local gotLock = false
	local success, err = pcall(function()
		gotLock = SessionLock.TryAcquire(Player.UserId)
	end)
	if not success then
		warn("[LoadData] SessionLock.TryAcquire pcall error for player", Player.Name, err)
		gotLock = true -- be permissive on DS error so players can join
	end

	if not gotLock then
		if SessionLock.Mode() == "strict" then
			Player:Kick("Session Locked")
			return
		else
			warn(("[LoadData] session lock held for player %s (allowing join in soft mode)."):format(Player.Name))
			-- we'll create a ConcurrentSession flag after NonSaveValues creation
		end
	end

	-- Create Data folder and subfolders
	local MainFolder = CreateFolder(Player,"Data")
	local Datastore

	local suc,er = pcall(function()
		-- Always use a string key to match SaveData/UpdateAsync writes.
		Datastore = PlayerData:GetAsync(tostring(Player.UserId))
	end)

	if er then
		warn(er)
		Player:Kick("Failed to load. Make sure to allow API Services in studio & publish your games in order to make datastores work")
		return
	end

	-- Create listed folders (NonSaveValues is placed directly under player)
	for _,FolderName in Values.Folders do
		if FolderName ~= "NonSaveValues" then
			CreateFolder(MainFolder,FolderName)
		else
			CreateFolder(Player,FolderName)
		end
	end

	-- If we are in soft-lock fallback (didn't get lock), create a flag so other scripts can see it
	if not gotLock then
		local flag = Instance.new("BoolValue")
		flag.Name = "ConcurrentSession"
		flag.Value = true
		flag.Parent = Player.NonSaveValues
		-- auto-clear after a safe delay as fallback (optional)
		task.delay(30, function()
			if flag and flag.Parent then flag:Destroy() end
		end)
	end

	-- Create NonSaveValues instances
	for _,Info in Values.NonSaveValues do
		local NewInstance = Instance.new(Info.Type)
		NewInstance.Name = Info.Name
		NewInstance.Value = Info.Value
		NewInstance.Parent = Player.NonSaveValues
	end

	-- Create SaveValues and copy from datastore if present
	for FolderName,FolderInfo in Values.SaveValues do	
		for _,Info in FolderInfo do
			local NewInstance = Instance.new(Info.Type)
			NewInstance.Name = Info.Name
			NewInstance.Value = Info.Value
			NewInstance.Parent = MainFolder[FolderName]

			if Datastore and Datastore[FolderName] then
				if Datastore[FolderName][Info.ID] ~= nil and Datastore[FolderName][Info.ID] ~= Info.Value then
					NewInstance.Value = Datastore[FolderName][Info.ID]
				end
			end
		end		
	end
	
	local passMarkerName = "PassDataStoreMarker"
	local expectedPassDataStoreName = tostring(PassRewardsConfig.PassDataStoreName or "")
	local passMarkerObj = getSaveValueObject(MainFolder, "PlayerData", passMarkerName)
	local previousPassDataStoreName = passMarkerObj and tostring(passMarkerObj.Value or "") or ""
	if expectedPassDataStoreName ~= "" and previousPassDataStoreName ~= expectedPassDataStoreName then
		local passLevelName = tostring(PassRewardsConfig.ProgressionLevelValueName or "PassLevel")
		local passXpName = tostring(PassRewardsConfig.ProgressionXpValueName or "EventXp")
		local eventCoinsName = tostring(PassRewardsConfig.EventCoinsValueName or "EventCoins")

		local passLevelObj = getSaveValueObject(MainFolder, "PlayerData", passLevelName)
		local passXpObj = getSaveValueObject(MainFolder, "PlayerData", passXpName)
		local eventCoinsObj = getSaveValueObject(MainFolder, "PlayerData", eventCoinsName)

		if passLevelObj and (passLevelObj:IsA("IntValue") or passLevelObj:IsA("NumberValue")) then
			passLevelObj.Value = 1
		end
		if passXpObj and (passXpObj:IsA("IntValue") or passXpObj:IsA("NumberValue")) then
			passXpObj.Value = 0
		end
		if eventCoinsObj and (eventCoinsObj:IsA("IntValue") or eventCoinsObj:IsA("NumberValue")) then
			eventCoinsObj.Value = 0
		end
		if passMarkerObj and passMarkerObj:IsA("StringValue") then
			passMarkerObj.Value = expectedPassDataStoreName
		end
	end

	-- Check Gamepasses
	for _,Gamepass in MainFolder.Gamepasses:GetChildren() do
		if Gamepass.Value then continue end -- only check if you DONT have it

		if RS.Gamepasses:FindFirstChild(Gamepass.Name) == nil then continue end

		local GPId = RS.Gamepasses[Gamepass.Name].Value
		Gamepass.Value = MPS:UserOwnsGamePassAsync(Player.UserId, GPId)
	end

	-- Pets	
	PetMultipliers.AddPlayer(Player.Name)

	if Datastore and Datastore.Pets then
		for PetId, PetInfo in Datastore.Pets do
			local NewPet = RS.Assets.PetTemplate:Clone()
			NewPet.Name = PetId
			NewPet.Equipped.Value = PetInfo.Equipped
			NewPet.PetName.Value = PetInfo.PetName
			NewPet.Parent = MainFolder.Pets

			if PetInfo.Equipped then
				PetMultipliers.AddPet(Player.Name, NewPet)
			end
		end
	end

	-- Auto Delete
	for _, Pet in RS.Pets:GetChildren() do
		local AutoDelete = Instance.new("BoolValue")

		if Datastore and Datastore.AutoDelete and Datastore.AutoDelete[Pet.Name] then
			AutoDelete.Value = Datastore.AutoDelete[Pet.Name]
		end

		AutoDelete.Name = Pet.Name
		AutoDelete.Parent = MainFolder.AutoDelete
	end

	Player.NonSaveValues.PetsEquipped.Value = PetMultipliers.GetPetsEquipped(Player.Name)
end

return LoadingFunctions
