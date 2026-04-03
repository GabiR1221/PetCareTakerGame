-- ServerMain.TYCOONSCRIPT Serverscript in Tycoon folder in workspace
-- Services
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")
local CurrencyBridge = require(Workspace:FindFirstChild("Tycoon"):FindFirstChild("CurrencyBridge"))

-- Variables
local tycoons = {}
local playerData = Instance.new("Folder", ServerStorage)
playerData.Name = "PlayerData"
local dropsFolder = Instance.new("Folder", workspace)
dropsFolder.Name = "Drops"

-- Events
local rebirthEvent = Instance.new("RemoteEvent")
rebirthEvent.Name = "TycoonRebirthEvent"
rebirthEvent.Parent = ReplicatedStorage

local soundEvent = Instance.new("RemoteEvent")
soundEvent.Name = "TycoonSoundEvent"
soundEvent.Parent = ReplicatedStorage

local animationEvent = Instance.new("RemoteEvent")
animationEvent.Name = "TycoonObjectAnimationEvent"
animationEvent.Parent = ReplicatedStorage

local getAnimationsFunction = Instance.new("RemoteFunction")
getAnimationsFunction.Name = "TycoonGetObjectAnimationsFunction"
getAnimationsFunction.Parent = ReplicatedStorage

local getRebirthRequirementsFunction = Instance.new("RemoteFunction")
getRebirthRequirementsFunction.Name = "TycoonGetRebirthRequirementsFunction"
getRebirthRequirementsFunction.Parent = ReplicatedStorage


-- Modules
local configModule = require(script.Parent.Settings)
local dataModule = require(script.DataModule)
local tycoonModule = require(script.TycoonModule)

-- Returns the ObjectAnimationsModule to the client
getAnimationsFunction.OnServerInvoke = function()
	return script.ObjectAnimationsModule
end

local function cloneArray(arrayValue)
	local out = {}
	if type(arrayValue) ~= "table" then return out end
	for _, value in ipairs(arrayValue) do
		table.insert(out, tostring(value))
	end
	return out
end

local function cloneDictionary(dictValue)
	local out = {}
	if type(dictValue) ~= "table" then return out end
	for key, value in pairs(dictValue) do
		out[tostring(key)] = tonumber(value) or 0
	end
	return out
end

getRebirthRequirementsFunction.OnServerInvoke = function(player)
	local rebirthsName = configModule.RebirthsName or "Rebirths"
	local rebirthCount = 0

	local serverPlayerData = ServerStorage:FindFirstChild("PlayerData")
	local playerFolder = serverPlayerData and serverPlayerData:FindFirstChild(tostring(player.UserId))
	if playerFolder then
		rebirthCount = tonumber(playerFolder:GetAttribute(rebirthsName)) or 0
	end

	local nextTier = rebirthCount + 1
	local tierRequirements = nil
	if type(configModule.RebirthRequirementsByTier) == "table" then
		tierRequirements = configModule.RebirthRequirementsByTier[nextTier]
	end
	tierRequirements = tierRequirements or {}

	return {
		RebirthCount = rebirthCount,
		NextTier = nextTier,
		RebirthLimit = tonumber(configModule.RebirthLimit) or 0,
		CompletionPercentage = tonumber(configModule.RebirthCompletionPercentage) or 100,
		RequiredPets = cloneArray(tierRequirements.RequiredPets or configModule.RebirthRequiredPets or {}),
		RequiredCurrency = cloneDictionary(tierRequirements.RequiredCurrency or configModule.RebirthRequiredCurrency or {}),
	}
end


-- Set up a neutral team for players without a tycoon
if configModule.AutoAssignTycoons == false and configModule.TeamsEnabled == true then
	local neutralTeam = Instance.new("Team")
	neutralTeam.Name = configModule.NeutralTeamName
	neutralTeam.TeamColor = configModule.NeutralTeamColor
	neutralTeam.Parent = Teams
end

-- Helper function to get a tycoon by its owner
local function GetTycoonFromOwner(owner)
	for _, tycoon in ipairs(tycoons) do
		if tycoon.Tycoon:GetAttribute("OwnerId") == owner.UserId then
			return tycoon
		end
	end
end

-- Function to set up leaderstats for joining players
local function SetUpLeaderstats(player)
	local playerFolder = Instance.new("Folder", playerData)
	playerFolder.Name = player.UserId
	
	local tycoonValue = Instance.new("ObjectValue", playerFolder)
	tycoonValue.Name = "Tycoon"
	
	local leaderstats = Instance.new("Folder", player)
	leaderstats.Name = "leaderstats"
	
	for _, currencyName in ipairs(CurrencyBridge.GetCurrencyNames()) do
		-- only create a leaderboard entry if the player's data has that value or fallback attribute exists
		local valObj = nil
		if player:FindFirstChild("Data") and player.Data:FindFirstChild("PlayerData") then
			valObj = player.Data.PlayerData:FindFirstChild(currencyName)
		end

		-- if neither a value object nor a server attribute exists, skip it
		local serverAttr = nil
		local serverFolder = ServerStorage:FindFirstChild("PlayerData")
		if serverFolder then
			local pf = serverFolder:FindFirstChild(tostring(player.UserId))
			if pf then
				serverAttr = pf:GetAttribute(currencyName)
			end
		end

		if not valObj and serverAttr == nil then
			-- player doesn't have this currency available; skip showing it
			continue
		end

		local clientCurrency = Instance.new("IntValue")
		clientCurrency.Name = currencyName
		clientCurrency.Parent = leaderstats

		if valObj then
			clientCurrency.Value = valObj.Value
			valObj:GetPropertyChangedSignal("Value"):Connect(function()
				clientCurrency.Value = valObj.Value
			end)
		else
			clientCurrency.Value = tonumber(serverAttr) or 0
		end
	end


	
	if configModule.RebirthsEnabled == true then
		playerFolder:SetAttribute(configModule.RebirthsName, 0)
		
		if configModule.DisplayRebirthsOnLeaderboard == true then
			local clientRebirths = Instance.new("IntValue")
			clientRebirths.Name = configModule.RebirthsName
			clientRebirths.Value = 0
			clientRebirths.Parent = leaderstats
			
			-- Update the client rebirths value when one of the values is changed
			local function updateRebirths()
				clientRebirths.Value = playerFolder:GetAttribute(configModule.RebirthsName)
			end
			playerFolder:GetAttributeChangedSignal(configModule.RebirthsName):Connect(updateRebirths)
			clientRebirths:GetPropertyChangedSignal("Value"):Connect(updateRebirths)
		end
	end
	
	if configModule.AutoAssignTycoons == true then
		for i, tycoon in ipairs(script.Parent.Tycoons:GetChildren()) do
			if tycoon:GetAttribute("OwnerId") == 0 then
				tycoon:SetAttribute("OwnerId", player.UserId)
				break
			end
		end
	end
	
	if configModule.LoadLeaderstatsOnJoin == true then
		dataModule:LoadLeaderstats(player)
	end
end

-- Function to save data and remove a player's data folder when leaving the game
local function OnPlayerRemoving(player)
	local tycoon = GetTycoonFromOwner(player)
	if tycoon then
		dataModule:SaveLeaderstats(player.UserId)
		dataModule:SaveTycoon(tycoon)
		tycoon.Tycoon:SetAttribute("OwnerId", 0)
		tycoon:ResetTycoon()
	elseif configModule.LoadStatsOnJoin == true then
		dataModule:SaveLeaderstats(player.UserId)
	end

	local playerFolder = playerData:FindFirstChild(tostring(player.UserId))
	if playerFolder then
		playerFolder:Destroy()
	end
end

-- Function to update and load a tycoon when its owner is changed
local function TycoonOwnerChanged(tycoon)
	if tycoon.Tycoon:GetAttribute("OwnerId") == 0 then return end

	local owner = Players:GetPlayerByUserId(tycoon.Tycoon:GetAttribute("OwnerId"))
	if owner == nil then return end

	if configModule.TeamsEnabled == true then
		owner.Team = Teams:FindFirstChild(tycoon.Tycoon.Name) or owner.Team
	end

	if configModule.AutoAssignTycoons == true then
		tycoon:AssignTycoon(owner)

		local function ToTycoon()
			if tycoon.Tycoon.Essentials:FindFirstChild("SpawnLocation") then
				owner.Character.PrimaryPart.CFrame = tycoon.Tycoon.Essentials.SpawnLocation.CFrame
					+ Vector3.new(0, owner.Character.PrimaryPart.Size.Y, 0)
			else
				owner.Character.PrimaryPart.CFrame = tycoon.Tycoon.Essentials.Gate:FindFirstChildWhichIsA("Model").Head.CFrame
			end
		end
		if owner.Character then
			ToTycoon()
		else
			owner.CharacterAdded:Once(ToTycoon)
		end
	end
	
	if configModule.LoadLeaderstatsOnJoin ~= true then
		dataModule:LoadLeaderstats(owner)
	end
	dataModule:LoadTycoon(tycoon)
	tycoon:UpdateAutoCollect()

	if configModule.RebirthsEnabled == true then
		local percentComplete = tycoon:GetCompletionPercentage()
		if percentComplete >= configModule.RebirthCompletionPercentage then
			rebirthEvent:FireClient(owner)
		end
	end

	for _, object in ipairs(tycoon.Tycoon.PurchasedObjects:GetChildren()) do
		tycoon:SetUpObject(object)
	end
end

-- Function to save all player data
local function SaveAllData()
	for _, player in ipairs(Players:GetPlayers()) do
		local tycoon = GetTycoonFromOwner(player)
		if not tycoon then
			if configModule.LoadLeaderstatsOnJoin == true then
				dataModule:SaveLeaderstats(player.UserId)
			end
			continue
		end

		dataModule:SaveLeaderstats(player.UserId)
		dataModule:SaveTycoon(tycoon)
	end
end

-- Function to attempt a rebirth from the client's event
local function OnRebirth(player)
	local tycoon = GetTycoonFromOwner(player)
	if not tycoon then return end
	if player.UserId == tycoon.Tycoon:GetAttribute("OwnerId") then
		tycoon:Rebirth()
	end
end

-- Function to update AutoCollect for a player purchasing the game pass
local function OnGamePassPurchased(player, gamePassId, wasPurchased)
	if not wasPurchased then return end
	
	local tycoon = GetTycoonFromOwner(player)
	if not tycoon then return end
	
	if player.UserId == tycoon.Tycoon:GetAttribute("OwnerId") and gamePassId == configModule.AutoCollect then
		tycoon.Tycoon:SetAttribute("AutoCollectEnabled", true)
	end
end

-- Set up connections
Players.PlayerAdded:Connect(SetUpLeaderstats)
Players.PlayerRemoving:Connect(OnPlayerRemoving)
rebirthEvent.OnServerEvent:Connect(OnRebirth)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(OnGamePassPurchased)

-- Set up tycoons
for _, tycoonFolder in ipairs(script.Parent.Tycoons:GetChildren()) do
	local tycoon = tycoonModule.new(tycoonFolder)
	table.insert(tycoons, tycoon)
	
	tycoon:Initialize()
	
	if configModule.TeamsEnabled == true then
		local team = Instance.new("Team")
		team.Name = tycoonFolder.Name
		team.TeamColor = tycoonFolder:GetAttribute("TycoonColor")
		team.AutoAssignable = false
		team.Parent = Teams
	end
	
	tycoon.Tycoon:GetAttributeChangedSignal("OwnerId"):Connect(function()
		TycoonOwnerChanged(tycoon)
	end)
end

if RunService:IsStudio() == false then
	game:BindToClose(function()
		SaveAllData()
	end)
end

if configModule.AutoSaveIntervalMinutes > 0 then
	while task.wait(configModule.AutoSaveIntervalMinutes * 60) do
		SaveAllData()
	end
end
