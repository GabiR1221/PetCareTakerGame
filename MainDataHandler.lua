--DataHandler Script in ServerScriptService-DataStore(folder)
--// Services

local Players = game:GetService("Players")

--// Server Modules

local MainFolder = script.Parent
local Datastore = require(MainFolder.Datastore)
local Values = require(MainFolder.Datastore.Values)

if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then return end

--// Player Join

Players.PlayerAdded:Connect(function(plr)		
	Datastore.LoadData(plr)
	
	task.wait(1)
	
	local Loaded = Instance.new("BoolValue")
	Loaded.Name = "Loaded"
	Loaded.Value = true
	Loaded.Parent = plr
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
local AutoSaveTime = 1 -- change this if you want faster/slower autosaves!

while task.wait(AutoSaveTime) do
	for _, plr in (Players:GetChildren()) do
		if not plr:FindFirstChild("Loaded") or not plr.Loaded.Value then continue end

		pcall(function()
			Datastore.SaveData(plr, false)
		end)
		
		plr.Loaded.Value = true
	end
end
