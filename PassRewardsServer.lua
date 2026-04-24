--!strict
-- Server-authoritative Pass system (Rewards + Quests + Shop).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PassRewardsConfig = require(modulesFolder:WaitForChild("PassRewardsConfig"))

type RewardStateItem = {
	Id: number,
	Type: string,
	RewardText: string,
	RewardImage: string,
	Claimed: boolean,
	CanClaim: boolean,
}

type QuestStateItem = {
	Id: number,
	Slot: number,
	Category: string,
	QuestText: string,
	QuestReward: string,
	QuestImage: string,
	Progress: number,
	Target: number,
	Completed: boolean,
	Claimed: boolean,
	StatusText: string,
}

type ShopStateItem = {
	Id: number,
	Type: string,
	ItemText: string,
	ItemImage: string,
	PriceText: string,
	PriceCurrency: string,
	PriceAmount: number,
}

type ClaimResponse = { Success: boolean, Error: string?, RewardId: number?, NewState: {RewardStateItem}? }
type BuyResponse = { Success: boolean, Error: string?, ShopState: {ShopStateItem}? }
type NumericValue = IntValue | NumberValue

type PersistedPassData = {
	ClaimedRewardsCsv: string,
	QuestProgressJson: string,
	QuestClaimedCsv: string,
}

local PASS_DATASTORE_NAME = "PassRewardsData_v1"
local passDataStore = DataStoreService:GetDataStore(PASS_DATASTORE_NAME)
local loadedFromDataStore: {[number]: boolean} = {}
local saveInFlight: {[number]: boolean} = {}

local function ensureRemoteFunction(name: string): RemoteFunction
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then return existing end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

local function ensureBindableEvent(name: string): BindableEvent
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("BindableEvent") then return existing end
	local bridge = Instance.new("BindableEvent")
	bridge.Name = name
	bridge.Parent = ReplicatedStorage
	return bridge
end

local function ensureRemoteEvent(name: string): RemoteEvent
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

local claimRemote = ensureRemoteFunction(PassRewardsConfig.ClaimRemoteName)
local rewardsStateRemote = ensureRemoteFunction(PassRewardsConfig.StateRemoteName)
local questsStateRemote = ensureRemoteFunction(PassRewardsConfig.GetQuestStateRemoteName)
local shopStateRemote = ensureRemoteFunction(PassRewardsConfig.GetShopStateRemoteName)
local buyShopRemote = ensureRemoteFunction(PassRewardsConfig.BuyShopItemRemoteName)
local questProgressBridge = ensureBindableEvent(PassRewardsConfig.QuestProgressBridgeName)
local questStateUpdatedRemote = ensureRemoteEvent("PassQuestStateUpdated")

local rewardsById: {[number]: any} = {}
for _, reward in ipairs(PassRewardsConfig.Rewards) do rewardsById[reward.Id] = reward end

local shopItemsById: {[number]: any} = {}
for _, item in ipairs(PassRewardsConfig.ShopItems) do shopItemsById[item.Id] = item end

local questGrantLocks: {[number]: {[number]: boolean}} = {}

local function getPlayerServerFolder(player: Player): Folder?
	local root = ServerStorage:FindFirstChild("PlayerData")
	if not root then return nil end
	return root:FindFirstChild(tostring(player.UserId)) :: Folder?
end

local function waitForPlayerServerFolder(player: Player, timeoutSeconds: number): Folder?
	local started = os.clock()
	while os.clock() - started < timeoutSeconds do
		local folder = getPlayerServerFolder(player)
		if folder then return folder end
		task.wait(0.1)
	end
	return nil
end

local function parseCsvToSet(csv: string): {[number]: boolean}
	local set: {[number]: boolean} = {}
	for token in string.gmatch(csv, "[^,]+") do
		local cleaned = string.gsub(token, "%s+", "")
		local id = tonumber(cleaned)
		if id then set[id] = true end
	end
	return set
end

local function encodeSetToCsv(set: {[number]: boolean}): string
	local ids: {number} = {}
	for id, enabled in pairs(set) do if enabled then table.insert(ids, id) end end
	table.sort(ids)
	local text: {string} = {}
	for _, id in ipairs(ids) do table.insert(text, tostring(id)) end
	return table.concat(text, ",")
end

local function decodeProgress(raw: string): {[string]: number}
	if raw == "" then return {} end
	local ok, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or type(decoded) ~= "table" then return {} end
	local out: {[string]: number} = {}
	for k, v in pairs(decoded) do
		if type(k) == "string" then out[k] = math.max(0, math.floor(tonumber(v) or 0)) end
	end
	return out
end

local function encodeProgress(progress: {[string]: number}): string
	return HttpService:JSONEncode(progress)
end

local function buildPersistedPayloadFromFolder(folder: Folder): PersistedPassData
	return {
		ClaimedRewardsCsv = tostring(folder:GetAttribute(PassRewardsConfig.ClaimedAttributeName) or ""),
		QuestProgressJson = tostring(folder:GetAttribute(PassRewardsConfig.QuestProgressAttributeName) or ""),
		QuestClaimedCsv = tostring(folder:GetAttribute(PassRewardsConfig.QuestClaimedAttributeName) or ""),
	}
end

local function savePassDataForPlayer(player: Player)
	local userId = player.UserId
	if saveInFlight[userId] then return end
	local folder = getPlayerServerFolder(player)
	if not folder then return end

	saveInFlight[userId] = true
	local payload = buildPersistedPayloadFromFolder(folder)
	local key = tostring(userId)
	task.spawn(function()
		for attempt = 1, 3 do
			local ok, err = pcall(function()
				passDataStore:SetAsync(key, payload)
			end)
			if ok then
				saveInFlight[userId] = nil
				return
			end
			if attempt == 3 then
				warn(string.format("[PassRewards] Failed to save pass data for %s: %s", tostring(userId), tostring(err)))
			end
			task.wait(0.5 * attempt)
		end
		saveInFlight[userId] = nil
	end)
end

local function ensurePassDataLoaded(player: Player)
	if loadedFromDataStore[player.UserId] then return end
	loadedFromDataStore[player.UserId] = true

	local folder = waitForPlayerServerFolder(player, 8)
	if not folder then
		warn(string.format("[PassRewards] Missing PlayerData folder for %s", player.Name))
		return
	end

	folder:SetAttribute(PassRewardsConfig.ClaimedAttributeName, tostring(folder:GetAttribute(PassRewardsConfig.ClaimedAttributeName) or ""))
	folder:SetAttribute(PassRewardsConfig.QuestProgressAttributeName, tostring(folder:GetAttribute(PassRewardsConfig.QuestProgressAttributeName) or "{}"))
	folder:SetAttribute(PassRewardsConfig.QuestClaimedAttributeName, tostring(folder:GetAttribute(PassRewardsConfig.QuestClaimedAttributeName) or ""))

	local key = tostring(player.UserId)
	local ok, data = pcall(function()
		return passDataStore:GetAsync(key)
	end)
	if not ok then
		warn(string.format("[PassRewards] Failed to load pass data for %s", player.Name))
		return
	end
	if type(data) ~= "table" then
		return
	end

	local claimedCsv = data.ClaimedRewardsCsv
	if type(claimedCsv) == "string" then
		folder:SetAttribute(PassRewardsConfig.ClaimedAttributeName, claimedCsv)
	end

	local progressJson = data.QuestProgressJson
	if type(progressJson) == "string" then
		folder:SetAttribute(PassRewardsConfig.QuestProgressAttributeName, progressJson)
	end

	local questClaimedCsv = data.QuestClaimedCsv
	if type(questClaimedCsv) == "string" then
		folder:SetAttribute(PassRewardsConfig.QuestClaimedAttributeName, questClaimedCsv)
	end
end

local function getClaimedRewards(player: Player): {[number]: boolean}
	ensurePassDataLoaded(player)
	local folder = getPlayerServerFolder(player)
	if not folder then return {} end
	local raw = tostring(folder:GetAttribute(PassRewardsConfig.ClaimedAttributeName) or "")
	if raw == "" then return {} end
	return parseCsvToSet(raw)
end

local function setClaimedReward(player: Player, rewardId: number)
	ensurePassDataLoaded(player)
	local folder = getPlayerServerFolder(player)
	if not folder then return end
	local claimed = getClaimedRewards(player)
	claimed[rewardId] = true
	folder:SetAttribute(PassRewardsConfig.ClaimedAttributeName, encodeSetToCsv(claimed))
	savePassDataForPlayer(player)
end

local function getClaimedQuests(player: Player): {[number]: boolean}
	ensurePassDataLoaded(player)
	local folder = getPlayerServerFolder(player)
	if not folder then return {} end
	local raw = tostring(folder:GetAttribute(PassRewardsConfig.QuestClaimedAttributeName) or "")
	if raw == "" then return {} end
	return parseCsvToSet(raw)
end

local function setClaimedQuest(player: Player, questId: number)
	ensurePassDataLoaded(player)
	local folder = getPlayerServerFolder(player)
	if not folder then return end
	local claimed = getClaimedQuests(player)
	claimed[questId] = true
	folder:SetAttribute(PassRewardsConfig.QuestClaimedAttributeName, encodeSetToCsv(claimed))
	savePassDataForPlayer(player)
end

local function getQuestProgress(player: Player): {[string]: number}
	ensurePassDataLoaded(player)
	local folder = getPlayerServerFolder(player)
	if not folder then return {} end
	return decodeProgress(tostring(folder:GetAttribute(PassRewardsConfig.QuestProgressAttributeName) or ""))
end

local function setQuestProgress(player: Player, progress: {[string]: number})
	ensurePassDataLoaded(player)
	local folder = getPlayerServerFolder(player)
	if not folder then return end
	folder:SetAttribute(PassRewardsConfig.QuestProgressAttributeName, encodeProgress(progress))
	savePassDataForPlayer(player)
end

local function findNumericValue(parent: Instance?, name: string): NumericValue?
	if not parent then return nil end
	local valueObj = parent:FindFirstChild(name)
	if valueObj and (valueObj:IsA("IntValue") or valueObj:IsA("NumberValue")) then
		return valueObj :: NumericValue
	end
	return nil
end

local function grantCurrency(player: Player, currencyName: string, amount: number): (boolean, string?)
	if amount <= 0 then return false, "InvalidAmount" end
	local data = player:FindFirstChild("Data")
	local playerData = data and data:FindFirstChild("PlayerData")
	local valueObj = findNumericValue(playerData, currencyName)
	if not valueObj then return false, "CurrencyNotFound" end
	valueObj.Value += amount
	return true, nil
end

local function chargeCurrency(player: Player, currencyName: string, amount: number): (boolean, string?)
	if amount < 0 then return false, "InvalidPrice" end
	if amount == 0 then return true, nil end
	local data = player:FindFirstChild("Data")
	local playerData = data and data:FindFirstChild("PlayerData")
	local valueObj = findNumericValue(playerData, currencyName)
	if not valueObj then return false, "CurrencyNotFound" end
	if valueObj.Value < amount then return false, "NotEnoughCurrency" end
	valueObj.Value -= amount
	return true, nil
end

local function refundCurrency(player: Player, currencyName: string, amount: number)
	if amount <= 0 then return end
	local data = player:FindFirstChild("Data")
	local playerData = data and data:FindFirstChild("PlayerData")
	local valueObj = findNumericValue(playerData, currencyName)
	if valueObj then valueObj.Value += amount end
end

local function countPets(player: Player): number
	local data = player:FindFirstChild("Data")
	local pets = data and data:FindFirstChild("Pets")
	if not pets then return -1 end
	return #pets:GetChildren()
end

local function grantPet(player: Player, petName: string): (boolean, string?)
	if petName == "" then return false, "InvalidPet" end
	local petsLibrary = ReplicatedStorage:FindFirstChild("Pets")
	if not petsLibrary or not petsLibrary:FindFirstChild(petName) then
		return false, "PetTemplateMissing"
	end

	local inventoryBridge = ReplicatedStorage:FindFirstChild(PassRewardsConfig.PetGrantBridgeName)
	local gamepassBridge = ReplicatedStorage:FindFirstChild("PetGamepassGrantBridge")
	if (not inventoryBridge or not inventoryBridge:IsA("BindableEvent"))
		and (not gamepassBridge or not gamepassBridge:IsA("BindableEvent")) then
		return false, "PetBridgeMissing"
	end

	local before = countPets(player)
	if gamepassBridge and gamepassBridge:IsA("BindableEvent") then
		(gamepassBridge :: BindableEvent):Fire(player, "PassRewardPet", {petName})
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

local function grantQuestReward(player: Player, quest: any): (boolean, string?)
	if quest.RewardType == "Currency" then
		return grantCurrency(player, tostring(quest.RewardCurrencyName or ""), tonumber(quest.RewardAmount) or 0)
	end
	if quest.RewardType == "Pet" then
		return grantPet(player, tostring(quest.RewardPetName or ""))
	end
	return false, "UnsupportedQuestReward"
end

local function getRewardStateForPlayer(player: Player): {RewardStateItem}
	local claimed = getClaimedRewards(player)
	local out: {RewardStateItem} = {}
	for _, reward in ipairs(PassRewardsConfig.Rewards) do
		table.insert(out, {
			Id = reward.Id,
			Type = reward.Type,
			RewardText = reward.RewardText,
			RewardImage = reward.RewardImage,
			Claimed = claimed[reward.Id] == true,
			CanClaim = claimed[reward.Id] ~= true,
		})
	end
	return out
end

local function getQuestStateForPlayer(player: Player): {QuestStateItem}
	local progress = getQuestProgress(player)
	local claimed = getClaimedQuests(player)
	local out: {QuestStateItem} = {}
	for _, quest in ipairs(PassRewardsConfig.Quests) do
		local current = math.max(0, math.floor(progress[quest.Action] or 0))
		local target = math.max(1, math.floor(quest.Target))
		local completed = current >= target
		local wasClaimed = claimed[quest.Id] == true
		local statusText = "0/0"
		if wasClaimed then
			statusText = "Completed + Claimed"
		elseif completed then
			statusText = "Completed"
		else
			statusText = string.format("%d/%d", current, target)
		end
		table.insert(out, {
			Id = quest.Id,
			Slot = quest.Slot,
			Category = quest.Category,
			QuestText = quest.QuestText,
			QuestReward = quest.QuestReward,
			QuestImage = quest.QuestImage,
			Progress = current,
			Target = target,
			Completed = completed,
			Claimed = wasClaimed,
			StatusText = statusText,
		})
	end
	return out
end

local function getShopStateForPlayer(_player: Player): {ShopStateItem}
	local out: {ShopStateItem} = {}
	for _, item in ipairs(PassRewardsConfig.ShopItems) do
		table.insert(out, {
			Id = item.Id,
			Type = item.Type,
			ItemText = item.ItemText,
			ItemImage = item.ItemImage,
			PriceText = item.ItemPriceText,
			PriceCurrency = item.PriceCurrency,
			PriceAmount = item.PriceAmount,
		})
	end
	return out
end

local function processQuestCompletions(player: Player)
	local progress = getQuestProgress(player)
	local claimed = getClaimedQuests(player)
	local playerLocks = questGrantLocks[player.UserId]
	if not playerLocks then
		playerLocks = {}
		questGrantLocks[player.UserId] = playerLocks
	end

	for _, quest in ipairs(PassRewardsConfig.Quests) do
		if claimed[quest.Id] then continue end
		if playerLocks[quest.Id] then continue end

		local current = math.max(0, math.floor(progress[quest.Action] or 0))
		if current >= quest.Target then
			playerLocks[quest.Id] = true
			local ok = select(1, grantQuestReward(player, quest))
			if ok then
				setClaimedQuest(player, quest.Id)
				claimed[quest.Id] = true
			end
			playerLocks[quest.Id] = nil
		end
	end
end

local function incrementQuestProgress(player: Player, action: string, amount: number)
	if amount <= 0 then return end
	local progress = getQuestProgress(player)
	progress[action] = math.max(0, (progress[action] or 0) + amount)
	setQuestProgress(player, progress)
	processQuestCompletions(player)
	questStateUpdatedRemote:FireClient(player)
end

rewardsStateRemote.OnServerInvoke = function(player: Player)
	return getRewardStateForPlayer(player)
end

questsStateRemote.OnServerInvoke = function(player: Player)
	return getQuestStateForPlayer(player)
end

shopStateRemote.OnServerInvoke = function(player: Player)
	return getShopStateForPlayer(player)
end

claimRemote.OnServerInvoke = function(player: Player, rewardId: any): ClaimResponse
	local id = tonumber(rewardId)
	if not id then return {Success = false, Error = "InvalidRewardId"} end
	local reward = rewardsById[id]
	if not reward then return {Success = false, Error = "RewardNotConfigured"} end
	if getClaimedRewards(player)[id] then return {Success = false, Error = "AlreadyClaimed"} end

	local ok: boolean
	local err: string?
	if reward.Type == "Currency" then
		ok, err = grantCurrency(player, reward.CurrencyName, reward.Amount)
	else
		ok, err = grantPet(player, reward.PetName)
	end
	if not ok then return {Success = false, Error = err or "GrantFailed"} end

	setClaimedReward(player, id)
	return {Success = true, RewardId = id, NewState = getRewardStateForPlayer(player)}
end

buyShopRemote.OnServerInvoke = function(player: Player, itemId: any): BuyResponse
	local id = tonumber(itemId)
	if not id then return {Success = false, Error = "InvalidItemId"} end
	local item = shopItemsById[id]
	if not item then return {Success = false, Error = "ItemNotConfigured"} end

	local charged, chargeErr = chargeCurrency(player, item.PriceCurrency, item.PriceAmount)
	if not charged then return {Success = false, Error = chargeErr or "ChargeFailed"} end

	local granted: boolean
	local grantErr: string?
	if item.Type == "Pet" then
		granted, grantErr = grantPet(player, tostring(item.PetName or ""))
	else
		granted, grantErr = grantCurrency(player, tostring(item.CurrencyName or ""), tonumber(item.Amount) or 0)
	end
	if not granted then
		refundCurrency(player, item.PriceCurrency, item.PriceAmount)
		return {Success = false, Error = grantErr or "GrantFailed"}
	end

	return {Success = true, ShopState = getShopStateForPlayer(player)}
end

questProgressBridge.Event:Connect(function(player: Player, action: string, amount: number?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	incrementQuestProgress(player, action, math.max(1, math.floor(tonumber(amount) or 1)))
end)

Players.PlayerAdded:Connect(function(player)
	ensurePassDataLoaded(player)
end)

Players.PlayerRemoving:Connect(function(player)
	savePassDataForPlayer(player)
	loadedFromDataStore[player.UserId] = nil
	saveInFlight[player.UserId] = nil
	questGrantLocks[player.UserId] = nil
end)
