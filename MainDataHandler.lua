--DataHandler Script in ServerScriptService-DataStore(folder)
--// Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
--// Server Modules

local MainFolder = script.Parent
local Datastore = require(MainFolder.Datastore)
local Values = require(MainFolder.Datastore.Values)

if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then return end

local function waitForSaveBudget()
	while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) < 1 do
		task.wait(0.25)
	end
end

local function trySavePlayerData(plr, isFinalSave)
	if not plr or not plr.Parent then return end
	if not plr:FindFirstChild("Loaded") or plr.Loaded.Value ~= true then return end
	local now = os.clock()
	local lastSavedAt = plr:GetAttribute("LastMainDataSaveAt")
	if type(lastSavedAt) == "number" and (now - lastSavedAt) < 8 then
		return
	end
	waitForSaveBudget()
	pcall(function()
		Datastore.SaveData(plr, isFinalSave == true)
	end)
	pcall(function()
		plr:SetAttribute("LastMainDataSaveAt", now)
	end)
end

local forcePlayerDataSaveFunction = ReplicatedStorage:FindFirstChild("ForcePlayerDataSave")
if not forcePlayerDataSaveFunction or not forcePlayerDataSaveFunction:IsA("BindableFunction") then
	forcePlayerDataSaveFunction = Instance.new("BindableFunction")
	forcePlayerDataSaveFunction.Name = "ForcePlayerDataSave"
	forcePlayerDataSaveFunction.Parent = ReplicatedStorage
end

forcePlayerDataSaveFunction.OnInvoke = function(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if not player:FindFirstChild("Loaded") or player.Loaded.Value ~= true then
		return false
	end
	local ok, err = pcall(function()
		Datastore.SaveData(player, false)
	end)
	if not ok then
		warn(("[DataHandler] Forced save failed for %s: %s"):format(player.Name, tostring(err)))
	end
	return ok
end

--// Player Join

Players.PlayerAdded:Connect(function(plr)
	plr:SetAttribute("DataLoaded", false)
	plr:SetAttribute("SavingData", false)

	local Loaded = Instance.new("BoolValue")
	Loaded.Name = "Loaded"
	Loaded.Value = false
	Loaded.Parent = plr

	Datastore.LoadData(plr)

	if plr.Parent then
		Loaded.Value = true
		plr:SetAttribute("DataLoaded", true)
	end
end)

--// Save data when a player leaves
Players.PlayerRemoving:Connect(function(plr)
	trySavePlayerData(plr, true)
end)

game:BindToClose(function()
	for _,v in Players:GetPlayers() do
		trySavePlayerData(v, true)
		task.wait(0.2)
	end
end)


--// Autosave
local AutoSaveTime = 180 -- spread datastore pressure over time to avoid queue spikes

while task.wait(AutoSaveTime) do
	for _, plr in (Players:GetChildren()) do
		trySavePlayerData(plr, false)
		task.wait(0.35)
	end
end
