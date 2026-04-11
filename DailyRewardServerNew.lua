local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local event = ReplicatedStorage:FindFirstChild("DailyRewardEvent")

------------------------------------------------
-- DATASTORE

local store = DataStoreService:GetDataStore("PlayerDataDailyReward_1")

------------------------------------------------
-- SETTINGS

local COOLDOWN = 86400

local rewards = {
	100,
	500,
	1000,
	2000,
	3000,
	5000,
	10000
}

------------------------------------------------

local sessionData = {}

------------------------------------------------
-- PLAYER JOIN

Players.PlayerAdded:Connect(function(player)

	-- Leaderstats
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats

	------------------------------------------------
	-- LOAD DATA

	local data

	local success,err = pcall(function()
		data = store:GetAsync(player.UserId)
	end)

	if not success then
		warn("LOAD FAILED",err)
	end

	if not data then
		data = {
			Coins = 0,
			Day = 1,
			LastClaim = 0
		}
	end

	coins.Value = data.Coins

	sessionData[player] = data

	event:FireClient(player,data.Day,data.LastClaim)

end)

------------------------------------------------
-- CLAIM REWARD

event.OnServerEvent:Connect(function(player)

	local data = sessionData[player]
	if not data then return end

	local now = os.time()

	if now - data.LastClaim < COOLDOWN then
		return
	end

	local reward = rewards[data.Day]

	local coins = player.leaderstats.Coins
	coins.Value += reward

	data.Coins = coins.Value

	data.LastClaim = now
	data.Day += 1

	if data.Day > #rewards then
		data.Day = 1
	end

	event:FireClient(player,data.Day,data.LastClaim)

end)

------------------------------------------------
-- SAVE PLAYER

local function savePlayer(player)

	local data = sessionData[player]
	if not data then return end

	local coins = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Coins")

	if coins then
		data.Coins = coins.Value
	end

	local success,err = pcall(function()

		store:SetAsync(player.UserId,data)

	end)

	if not success then
		warn("SAVE FAILED",err)
	end

end

------------------------------------------------

Players.PlayerRemoving:Connect(savePlayer)

game:BindToClose(function()

	for _,player in pairs(Players:GetPlayers()) do
		savePlayer(player)
	end

end)
