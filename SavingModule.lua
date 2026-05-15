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

	if Player:GetAttribute("SavingData") == true then
		if not AutoSave then
			return
		end
		local deadline = os.clock() + 5
		while Player:GetAttribute("SavingData") == true and os.clock() < deadline do
			task.wait(0.1)
		end
		if Player:GetAttribute("SavingData") == true then
			warn("[SavingModule] Final save skipped because another save is still running for "..Player.Name)
			return
		end
	end
	Player:SetAttribute("SavingData", true)

	local Save = {}

	for FolderName,FolderInfo in require(script.Parent.Values).SaveValues do
		Save[FolderName] = {}

		for _,Info in FolderInfo do
			Save[FolderName][Info.ID] = Folder[FolderName][Info.Name].Value
		end
	end

	Save["Pets"] = {}
	for _,Pet in Folder.Pets:GetChildren() do
		local petUidValue = Pet:FindFirstChild("PetUID")
		Save["Pets"][tonumber(Pet.Name)] = {
			PetName = Pet.PetName.Value,
			Equipped = Pet.Equipped.Value,
			PetUID = petUidValue and tostring(petUidValue.Value or "") or "",
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
	-- mark this save complete without flipping Loaded/DataLoaded; those represent load readiness.
	pcall(function()
		if Player then
			Player:SetAttribute("SavingData", false)
		end
	end)
end


return SavingFunctions
