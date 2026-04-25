--!strict
-- Server-authoritative, session-only Playtime rewards.
-- No DataStore: rewards reset when player leaves/rejoins.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PlaytimeRewardsConfig = require(modulesFolder:WaitForChild("PlaytimeRewardsConfig"))

type PlaytimeStateItem = {
	Id: number,
	Type: string,
	RequiredPlaytimeSeconds: number,
	RemainingSeconds: number,
	RewardText: string,
	RewardImage: string,
	Claimed: boolean,
	CanClaim: boolean,
}

type StateResponse = {
	Rewards: {PlaytimeStateItem},
	ElapsedPlaytimeSeconds: number,
}

type ClaimResponse = {
	Success: boolean,
	Error: string?,
	RewardId: number?,
	NewState: StateResponse?,
}

type NumericValue = IntValue | NumberValue

local function ensureRemoteFunction(name: string): RemoteFunction
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	local created = Instance.new("RemoteFunction")
	created.Name = name
	created.Parent = ReplicatedStorage
	return created
end

local getStateRemote = ensureRemoteFunction(PlaytimeRewardsConfig.GetStateRemoteName)
local claimRemote = ensureRemoteFunction(PlaytimeRewardsConfig.ClaimRemoteName)

local rewardsById: {[number]: any} = {}
for _, reward in ipairs(PlaytimeRewardsConfig.Rewards) do
	rewardsById[reward.Id] = reward
end

local sessionStartByUserId: {[number]: number} = {}
local claimedByUserId: {[number]: {[number]: boolean}} = {}

local function getElapsedSeconds(player: Player): number
	local startedAt = sessionStartByUserId[player.UserId]
	if not startedAt then
		startedAt = time()
		sessionStartByUserId[player.UserId] = startedAt
	end
	return math.max(0, math.floor(time() - startedAt))
end

local function findNumericValue(parent: Instance?, name: string): NumericValue?
	if not parent then return nil end
	local candidate = parent:FindFirstChild(name)
	if candidate and (candidate:IsA("IntValue") or candidate:IsA("NumberValue")) then
		return candidate :: NumericValue
	end
	return nil
end

local function countPets(player: Player): number
	local data = player:FindFirstChild("Data")
	local pets = data and data:FindFirstChild("Pets")
	if not pets then return -1 end
	return #pets:GetChildren()
end

local function grantCurrency(player: Player, currencyName: string, amount: number): (boolean, string?)
	if amount <= 0 then return false, "InvalidAmount" end
	if currencyName == "" then return false, "InvalidCurrency" end

	local data = player:FindFirstChild("Data")
	local playerData = data and data:FindFirstChild("PlayerData")
	local valueObj = findNumericValue(playerData, currencyName)
	if not valueObj then return false, "CurrencyNotFound" end

	valueObj.Value += amount
	return true, nil
end

local function grantPetOnce(player: Player, petName: string): (boolean, string?)
	if petName == "" then return false, "InvalidPet" end

	local petsLibrary = ReplicatedStorage:FindFirstChild("Pets")
	if not petsLibrary or not petsLibrary:FindFirstChild(petName) then
		return false, "PetTemplateMissing"
	end

	local inventoryBridge = ReplicatedStorage:FindFirstChild(PlaytimeRewardsConfig.PetGrantBridgeName)
	local gamepassBridge = ReplicatedStorage:FindFirstChild("PetGamepassGrantBridge")
	if (not inventoryBridge or not inventoryBridge:IsA("BindableEvent"))
		and (not gamepassBridge or not gamepassBridge:IsA("BindableEvent")) then
		return false, "PetBridgeMissing"
	end

	local before = countPets(player)
	if gamepassBridge and gamepassBridge:IsA("BindableEvent") then
		(gamepassBridge :: BindableEvent):Fire(player, "PlaytimeRewardPet", {petName})
	elseif inventoryBridge and inventoryBridge:IsA("BindableEvent") then
		(inventoryBridge :: BindableEvent):Fire(player, petName)
	end

	for _ = 1, 20 do
		task.wait(0.1)
		local after = countPets(player)
		if before >= 0 and after > before then
			return true, nil
		end
	end

	return false, "PetGrantFailed"
end

local function grantPet(player: Player, petName: string, amount: number): (boolean, string?)
	if amount <= 0 then return false, "InvalidAmount" end
	for _ = 1, amount do
		local ok, err = grantPetOnce(player, petName)
		if not ok then
			return false, err
		end
	end
	return true, nil
end

local function getOrCreateClaimedSet(player: Player): {[number]: boolean}
	local userId = player.UserId
	local existing = claimedByUserId[userId]
	if existing then return existing end
	local created: {[number]: boolean} = {}
	claimedByUserId[userId] = created
	return created
end

local function buildStateForPlayer(player: Player): StateResponse
	local elapsedSeconds = getElapsedSeconds(player)
	local claimed = getOrCreateClaimedSet(player)
	local rewards: {PlaytimeStateItem} = {}

	for _, reward in ipairs(PlaytimeRewardsConfig.Rewards) do
		local required = math.max(0, math.floor(tonumber(reward.RequiredPlaytimeSeconds) or 0))
		local wasClaimed = claimed[reward.Id] == true
		local canClaim = (not wasClaimed) and elapsedSeconds >= required
		local remaining = 0
		if not wasClaimed and elapsedSeconds < required then
			remaining = required - elapsedSeconds
		end

		table.insert(rewards, {
			Id = reward.Id,
			Type = reward.Type,
			RequiredPlaytimeSeconds = required,
			RemainingSeconds = remaining,
			RewardText = tostring(reward.RewardText or ""),
			RewardImage = tostring(reward.RewardImage or ""),
			Claimed = wasClaimed,
			CanClaim = canClaim,
		})
	end

	return {
		Rewards = rewards,
		ElapsedPlaytimeSeconds = elapsedSeconds,
	}
end

getStateRemote.OnServerInvoke = function(player: Player): StateResponse
	return buildStateForPlayer(player)
end

claimRemote.OnServerInvoke = function(player: Player, rewardId: any): ClaimResponse
	local id = tonumber(rewardId)
	if not id then return {Success = false, Error = "InvalidRewardId"} end

	local reward = rewardsById[id]
	if not reward then return {Success = false, Error = "RewardNotConfigured"} end

	local claimed = getOrCreateClaimedSet(player)
	if claimed[id] then
		return {Success = false, Error = "AlreadyClaimed"}
	end

	local elapsedSeconds = getElapsedSeconds(player)
	local required = math.max(0, math.floor(tonumber(reward.RequiredPlaytimeSeconds) or 0))
	if elapsedSeconds < required then
		return {Success = false, Error = "PlaytimeLocked"}
	end

	local granted: boolean
	local grantError: string?
	if reward.Type == "Currency" then
		granted, grantError = grantCurrency(player, tostring(reward.CurrencyName or ""), math.max(1, math.floor(tonumber(reward.Amount) or 1)))
	elseif reward.Type == "Pet" then
		granted, grantError = grantPet(player, tostring(reward.PetName or ""), math.max(1, math.floor(tonumber(reward.Amount) or 1)))
	else
		return {Success = false, Error = "UnsupportedRewardType"}
	end

	if not granted then
		return {Success = false, Error = grantError or "GrantFailed"}
	end

	claimed[id] = true
	return {
		Success = true,
		RewardId = id,
		NewState = buildStateForPlayer(player),
	}
end

Players.PlayerAdded:Connect(function(player)
	sessionStartByUserId[player.UserId] = time()
	claimedByUserId[player.UserId] = {}
end)

Players.PlayerRemoving:Connect(function(player)
	sessionStartByUserId[player.UserId] = nil
	claimedByUserId[player.UserId] = nil
end)
