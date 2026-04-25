--SavingModule as child of DataStoreModule
local DS = game:GetService("DataStoreService")
local RS = game:GetService("ReplicatedStorage")

local SavingFunctions = {}

local SaveStoreName = RS["Game Settings"].DataSave.Value
local SaveStore = DS:GetDataStore(SaveStoreName)
local SessionLock = require(script.Parent:WaitForChild("SessionLock"))

SavingFunctions.SaveData = function(Player, AutoSave)
	local Folder = Player.Data

	if Player:FindFirstChild("Loaded") == nil or Player.Loaded.Value == false then
		return
	end

	Player.Loaded.Value = false

	local Save = {}

	for FolderName,FolderInfo in require(script.Parent.Values).SaveValues do
		Save[FolderName] = {}

		for _,Info in FolderInfo do
			Save[FolderName][Info.ID] = Folder[FolderName][Info.Name].Value
		end
	end

	Save["Pets"] = {}
	for _,Pet in Folder.Pets:GetChildren() do
		Save["Pets"][tonumber(Pet.Name)] = {
			PetName = Pet.PetName.Value,
			Equipped = Pet.Equipped.Value,
		}
	end

	Save["AutoDelete"] = {}
	for _,Pet in Folder.AutoDelete:GetChildren() do
		if Pet.Value then
			Save["AutoDelete"][Pet.Name] = true
		end
	end

	if AutoSave then
		Save.SessionId = game.JobId
		Save.LastInGame = os.time()
	end

	-- Use UpdateAsync to atomically write the player's data (less chance of stomping)
	local suc, er = pcall(function()
		SaveStore:UpdateAsync(tostring(Player.UserId), function(old)
			-- Optionally merge old and Save if you want to preserve some fields; here we replace
			return Save
		end)
	end)

	if not suc then
		warn("error with saving data for "..Player.Name.." : "..tostring(er))
	end

	-- If this was the final save on leave (AutoSave), release the session lock
	if AutoSave then
		pcall(function()
			SessionLock.Release(Player.UserId)
		end)
	end
	-- restore Loaded if player still present and not leaving
	pcall(function()
		if Player and Player.Parent and Player:FindFirstChild("Loaded") then
			Player.Loaded.Value = true
		end
	end)
end


return SavingFunctions
