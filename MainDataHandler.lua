--DataHandler Script in ServerScriptService-DataStore(folder)
--// Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
--// Server Modules

local MainFolder = script.Parent
local Datastore = require(MainFolder.Datastore)
local Values = require(MainFolder.Datastore.Values)

if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then return end

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
	pcall(function() Datastore.SaveData(plr, true) end)
end)

game:BindToClose(function()
	for _,v in Players:GetPlayers() do
		pcall(function() Datastore.SaveData(v, true) end)
	end
end)


--// Autosave
local AutoSaveTime = 60 -- autosave once per minute; 1-second datastore writes cause load/save contention and lag

while task.wait(AutoSaveTime) do
	for _, plr in (Players:GetChildren()) do
		if not plr:FindFirstChild("Loaded") or not plr.Loaded.Value then continue end

		pcall(function()
			Datastore.SaveData(plr, false)
		end)
	end
end
