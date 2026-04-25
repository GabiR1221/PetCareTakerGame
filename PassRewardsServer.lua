--!strict
-- Server-authoritative Pass system (Rewards + Quests + Shop).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PassRewardsConfig = require(modulesFolder:WaitForChild("PassRewardsConfig"))

type RewardStateItem = {
	Id: number,
	Type: string,
	Tier: "Free" | "Premium",
	RequiredLevel: number,
	RewardText: string,
	RewardImage: string,
	Claimed: boolean,
	CanClaim: boolean,
}

type PremiumPurchaseState = {
	Enabled: boolean,
	EntryName: string,
	ProductId: number,
	PurchaseType: "GamePass" | "DeveloperProduct",
}

type RewardsStateResponse = {
	Rewards: {RewardStateItem},
	HasPremiumAccess: boolean,
	PlayerLevel: number,
	PremiumPurchase: PremiumPurchaseState,
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
	Version: number,
	ClaimedRewardsCsv: string,
	QuestProgressJson: string,
	QuestClaimedCsv: string,
	PassLevel: number,
	EventXp: number,
	EventCoins: number,
}

local PASS_DATASTORE_NAME = tostring(PassRewardsConfig.PassDataStoreName)
local passDataStore = DataStoreService:GetDataStore(PASS_DATASTORE_NAME)
local loadedFromDataStore: {[number]: boolean} = {}
local saveInFlight: {[number]: boolean} = {}
local premiumOwnershipCheckTimestamps: {[number]: number} = {}


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

local function findChildByNameInsensitive(parent: Instance?, expectedName: string): Instance?
	if not parent then return nil end
	local direct = parent:FindFirstChild(expectedName)
	if direct then return direct end
	local loweredExpected = string.lower(expectedName)
	for _, child in ipairs(parent:GetChildren()) do
		if string.lower(child.Name) == loweredExpected then
			return child
		end
	end
	return nil
end

local function getPlayerServerFolder(player: Player): Folder?
	local root = ServerStorage:FindFirstChild("PlayerData")
	if not root then return nil end
	return root:FindFirstChild(tostring(player.UserId)) :: Folder?
end

local function getPlayerDataValuesFolder(player: Player): Folder?
	local data = player:FindFirstChild("Data")
	local playerData = data and data:FindFirstChild("PlayerData")
	if playerData and playerData:IsA("Folder") then
		return playerData
	end
	return nil
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

local function getNumericValueInFolder(folder: Instance?, name: string): number?
	if not folder then return nil end
	local valueObj = folder:FindFirstChild(name)
	if valueObj and (valueObj:IsA("IntValue") or valueObj:IsA("NumberValue")) then
		return tonumber((valueObj :: NumericValue).Value)
	end
	return nil
end

local function findNumericValue(parent: Instance?, name: string): NumericValue?
	if not parent then return nil end
	local valueObj = parent:FindFirstChild(name)
	if valueObj and (valueObj:IsA("IntValue") or valueObj:IsA("NumberValue")) then
		return valueObj :: NumericValue
	end
	return nil
end

local function buildPersistedPayloadFromFolder(folder: Folder): PersistedPassData
	local player = Players:GetPlayerByUserId(tonumber(folder.Name) or 0)
	local valuesFolder = if player then getPlayerDataValuesFolder(player) else nil
	local passLevelName = tostring(PassRewardsConfig.ProgressionLevelValueName or "PassLevel")
	local passXpName = tostring(PassRewardsConfig.ProgressionXpValueName or "EventXp")
	local eventCoinsName = tostring(PassRewardsConfig.EventCoinsValueName or "EventCoins")
	local passLevel = 1
	local passXp = 0
	local eventCoins = 0
	local passLevelRaw = getNumericValueInFolder(valuesFolder, passLevelName)
	local passXpRaw = getNumericValueInFolder(valuesFolder, passXpName)
	local eventCoinsRaw = getNumericValueInFolder(valuesFolder, eventCoinsName)
	if passLevelRaw then passLevel = math.max(1, math.floor(passLevelRaw)) end
	if passXpRaw then passXp = math.max(0, math.floor(passXpRaw)) end
	if eventCoinsRaw then eventCoins = math.max(0, math.floor(eventCoinsRaw)) end

	return {
		Version = math.max(1, math.floor(tonumber(PassRewardsConfig.PassDataVersion) or 1)),
		ClaimedRewardsCsv = tostring(folder:GetAttribute(PassRewardsConfig.ClaimedAttributeName) or ""),
		QuestProgressJson = tostring(folder:GetAttribute(PassRewardsConfig.QuestProgressAttributeName) or ""),
		QuestClaimedCsv = tostring(folder:GetAttribute(PassRewardsConfig.QuestClaimedAttributeName) or ""),
		PassLevel = passLevel,
		EventXp = passXp,
		EventCoins = eventCoins,
	}
end

local function savePassDataForPlayer(player: Player, blocking: boolean?)
	local userId = player.UserId
	if saveInFlight[userId] then return end
	local folder = getPlayerServerFolder(player)
	if not folder then return end

	saveInFlight[userId] = true
	local payload = buildPersistedPayloadFromFolder(folder)
	local key = tostring(userId)
	local function runSave()
		for attempt = 1, 3 do
			local ok, err = pcall(function()
				passDataStore:UpdateAsync(key, function(_old)
					return payload
				end)
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
	end
	if blocking then
		runSave()
	else
		task.spawn(runSave)
	end
end

local function ensurePassDataLoaded(player: Player)
	if loadedFromDataStore[player.UserId] then return end

	local folder = waitForPlayerServerFolder(player, 8)
	if not folder then
		warn(string.format("[PassRewards] Missing PlayerData folder for %s", player.Name))
		return
	end
	loadedFromDataStore[player.UserId] = true

	-- Always reset to pass-defaults first so an empty/new datastore key starts from a clean slate.
	-- We intentionally do NOT preserve any pre-existing attribute values here because those may come
	-- from unrelated save systems and can leak stale pass progress into a "new" pass datastore.
	folder:SetAttribute(PassRewardsConfig.ClaimedAttributeName, "")
	folder:SetAttribute(PassRewardsConfig.QuestProgressAttributeName, "{}")
	folder:SetAttribute(PassRewardsConfig.QuestClaimedAttributeName, "")
	local valuesFolder = getPlayerDataValuesFolder(player)
	local passLevelName = tostring(PassRewardsConfig.ProgressionLevelValueName or "PassLevel")
	local passXpName = tostring(PassRewardsConfig.ProgressionXpValueName or "EventXp")
	local eventCoinsName = tostring(PassRewardsConfig.EventCoinsValueName or "EventCoins")
	local passLevelValue = findNumericValue(valuesFolder, passLevelName)
	local passXpValue = findNumericValue(valuesFolder, passXpName)
	local eventCoinsValue = findNumericValue(valuesFolder, eventCoinsName)
	if passLevelValue then passLevelValue.Value = 1 end
	if passXpValue then passXpValue.Value = 0 end
	if eventCoinsValue then eventCoinsValue.Value = 0 end

	local key = tostring(player.UserId)
	local ok, data = pcall(function()
		return passDataStore:GetAsync(key)
	end)
	if not ok then
		warn(string.format("[PassRewards] Failed to load pass data for %s", player.Name))
		return
	end
	if type(data) ~= "table" then return end

	local savedVersion = math.max(0, math.floor(tonumber(data.Version) or 0))
	local expectedVersion = math.max(1, math.floor(tonumber(PassRewardsConfig.PassDataVersion) or 1))
	if savedVersion ~= expectedVersion then
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

	if passLevelValue and tonumber(data.PassLevel) then
		passLevelValue.Value = math.max(1, math.floor(tonumber(data.PassLevel) or 1))
	end
	if passXpValue and tonumber(data.EventXp) then
		passXpValue.Value = math.max(0, math.floor(tonumber(data.EventXp) or 0))
	end
	if eventCoinsValue and tonumber(data.EventCoins) then
		eventCoinsValue.Value = math.max(0, math.floor(tonumber(data.EventCoins) or 0))
	end
end


local function normalizeClaimedRewards(claimedSet: {[number]: boolean}): {[number]: boolean}
	local normalized: {[number]: boolean} = {}
	for rewardId, isClaimed in pairs(claimedSet) do
		if isClaimed and rewardsById[rewardId] ~= nil then
			normalized[rewardId] = true
		end
	end
	return normalized
end

local function getClaimedRewards(player: Player): {[number]: boolean}
	ensurePassDataLoaded(player)
	local folder = getPlayerServerFolder(player)
	if not folder then return {} end
	local raw = tostring(folder:GetAttribute(PassRewardsConfig.ClaimedAttributeName) or "")
	if raw == "" then return {} end
	local claimed = normalizeClaimedRewards(parseCsvToSet(raw))
	local normalizedCsv = encodeSetToCsv(claimed)
	if normalizedCsv ~= raw then
		folder:SetAttribute(PassRewardsConfig.ClaimedAttributeName, normalizedCsv)
		savePassDataForPlayer(player)
	end
	return claimed
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

local function getPassXpValue(player: Player): NumericValue?
	local data = player:FindFirstChild("Data")
	local playerData = data and data:FindFirstChild("PlayerData")
	local xpName = tostring(PassRewardsConfig.ProgressionXpValueName or "EventXp")
	return findNumericValue(playerData, xpName)
end

local function getPassLevelValue(player: Player): NumericValue?
	local data = player:FindFirstChild("Data")
	local playerData = data and data:FindFirstChild("PlayerData")
	local levelName = tostring(PassRewardsConfig.ProgressionLevelValueName or "PassLevel")
	return findNumericValue(playerData, levelName)
end

local function awardPassXpAndLevels(player: Player, amount: number): (boolean, string?)
	if amount <= 0 then return false, "InvalidAmount" end
	local xpValue = getPassXpValue(player)
	if not xpValue then return false, "PassXpNotFound" end
	local levelValue = getPassLevelValue(player)
	if not levelValue then return false, "PassLevelNotFound" end

	local requiredPerLevel = math.max(1, math.floor(tonumber(PassRewardsConfig.ProgressionXpPerLevel) or 10))
	local totalXp = math.max(0, math.floor(xpValue.Value)) + amount
	local levelUps = math.floor(totalXp / requiredPerLevel)
	xpValue.Value = totalXp % requiredPerLevel
	if levelUps > 0 then
		levelValue.Value = math.max(0, math.floor(levelValue.Value)) + levelUps
	end
	savePassDataForPlayer(player)
	return true, nil
end

local function grantCurrency(player: Player, currencyName: string, amount: number): (boolean, string?)
	if amount <= 0 then return false, "InvalidAmount" end
	local xpName = tostring(PassRewardsConfig.ProgressionXpValueName or "EventXp")
	local eventCoinsName = tostring(PassRewardsConfig.EventCoinsValueName or "EventCoins")
	if currencyName == xpName then
		return awardPassXpAndLevels(player, amount)
	end

	local data = player:FindFirstChild("Data")
	local playerData = data and data:FindFirstChild("PlayerData")
	local valueObj = findNumericValue(playerData, currencyName)
	if not valueObj then return false, "CurrencyNotFound" end
	valueObj.Value += amount
	if currencyName == eventCoinsName then
		savePassDataForPlayer(player)
	end
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
	if currencyName == tostring(PassRewardsConfig.EventCoinsValueName or "EventCoins") then
		savePassDataForPlayer(player)
	end
	return true, nil
end

local function refundCurrency(player: Player, currencyName: string, amount: number)
	if amount <= 0 then return end
	local data = player:FindFirstChild("Data")
	local playerData = data and data:FindFirstChild("PlayerData")
	local valueObj = findNumericValue(playerData, currencyName)
	if valueObj then
		valueObj.Value += amount
		if currencyName == tostring(PassRewardsConfig.EventCoinsValueName or "EventCoins") then
			savePassDataForPlayer(player)
		end
	end
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

local function getPurchaseTypeFromEntry(entry: Instance?): "GamePass" | "DeveloperProduct"
	if not entry then return "GamePass" end
	local configuredType = string.lower(tostring(entry:GetAttribute("PurchaseType") or ""))
	if configuredType == "developerproduct" or configuredType == "devproduct" or configuredType == "product" then
		return "DeveloperProduct"
	end
	return "GamePass"
end

local function getPremiumPurchaseConfig(): PremiumPurchaseState
	local entryName = tostring(PassRewardsConfig.PremiumAccessEntryName or "")
	local gamepassesFolder = ReplicatedStorage:FindFirstChild("Gamepasses")
	local entry = findChildByNameInsensitive(gamepassesFolder, entryName)
	local purchaseType = getPurchaseTypeFromEntry(entry)
	if PassRewardsConfig.PremiumAccessPurchaseType == "GamePass" then
		purchaseType = "GamePass"
	elseif PassRewardsConfig.PremiumAccessPurchaseType == "DeveloperProduct" then
		purchaseType = "DeveloperProduct"
	end

	local productId = 0
	if entry and (entry:IsA("IntValue") or entry:IsA("NumberValue")) then
		productId = math.floor(tonumber(entry.Value) or 0)
	end

	return {
		Enabled = entry ~= nil and productId > 0,
		EntryName = entryName,
		ProductId = productId,
		PurchaseType = purchaseType,
	}
end

local function getPremiumFlag(player: Player): BoolValue?
	local data = player:FindFirstChild("Data")
	local gamepasses = data and data:FindFirstChild("Gamepasses")
	if not gamepasses or not gamepasses:IsA("Folder") then return nil end
	local flagName = tostring(PassRewardsConfig.PremiumAccessEntryName or "")
	if flagName == "" then return nil end
	local flag = findChildByNameInsensitive(gamepasses, flagName)
	if flag and flag:IsA("BoolValue") then
		return flag
	end
	if not flag then
		local created = Instance.new("BoolValue")
		created.Name = flagName
		created.Value = false
		created.Parent = gamepasses
		return created
	end
	return nil
end

local function playerHasPremiumAccess(player: Player): boolean
	local premiumFlag = getPremiumFlag(player)
	return premiumFlag ~= nil and premiumFlag.Value == true
end

local function syncPremiumOwnershipIfNeeded(player: Player, forceCheck: boolean?)
	local purchaseCfg = getPremiumPurchaseConfig()
	if not purchaseCfg.Enabled then return end
	if purchaseCfg.PurchaseType ~= "GamePass" then return end
	local premiumFlag = getPremiumFlag(player)
	if not premiumFlag or premiumFlag.Value then return end

	local now = os.clock()
	local last = premiumOwnershipCheckTimestamps[player.UserId] or 0
	if not forceCheck and (now - last) < 2 then
		return
	end
	premiumOwnershipCheckTimestamps[player.UserId] = now

	local ok, ownsPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, purchaseCfg.ProductId)
	end)
	if ok and ownsPass == true then
		premiumFlag.Value = true
	end
end

local function getPlayerPassLevel(player: Player): number
	local configuredName = tostring(PassRewardsConfig.ProgressionLevelValueName or "PassLevel")
	local data = player:FindFirstChild("Data")
	local playerData = data and data:FindFirstChild("PlayerData")
	local valueObj = playerData and playerData:FindFirstChild(configuredName)
	if valueObj and (valueObj:IsA("IntValue") or valueObj:IsA("NumberValue")) then
		return math.max(0, math.floor((valueObj :: NumericValue).Value))
	end
	return 1
end

local function getRewardStateForPlayer(player: Player): RewardsStateResponse
	syncPremiumOwnershipIfNeeded(player)
	local claimed = getClaimedRewards(player)
	local out: {RewardStateItem} = {}
	local hasPremiumAccess = playerHasPremiumAccess(player)
	local playerLevel = getPlayerPassLevel(player)
	for _, reward in ipairs(PassRewardsConfig.Rewards) do
		local tier: "Free" | "Premium" = reward.Tier == "Premium" and "Premium" or "Free"
		local requiredLevel = math.max(1, math.floor(tonumber(reward.Level) or reward.Id))
		local canClaim = claimed[reward.Id] ~= true
		if playerLevel < requiredLevel then
			canClaim = false
		end
		if tier == "Premium" and not hasPremiumAccess then
			canClaim = false
		end
		table.insert(out, {
			Id = reward.Id,
			Type = reward.Type,
			Tier = tier,
			RequiredLevel = requiredLevel,
			RewardText = reward.RewardText,
			RewardImage = reward.RewardImage,
			Claimed = claimed[reward.Id] == true,
			CanClaim = canClaim,
		})
	end
	return {
		Rewards = out,
		HasPremiumAccess = hasPremiumAccess,
		PlayerLevel = playerLevel,
		PremiumPurchase = getPremiumPurchaseConfig(),
	}
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
	local requiredLevel = math.max(1, math.floor(tonumber(reward.Level) or reward.Id))
	if getPlayerPassLevel(player) < requiredLevel then
		return {Success = false, Error = "LevelLocked"}
	end
	if reward.Tier == "Premium" and not playerHasPremiumAccess(player) then
		return {Success = false, Error = "PremiumRequired"}
	end

	local ok: boolean
	local err: string?
	if reward.Type == "Currency" then
		ok, err = grantCurrency(player, reward.CurrencyName, reward.Amount)
	else
		ok, err = grantPet(player, reward.PetName)
	end
	if not ok then return {Success = false, Error = err or "GrantFailed"} end

	setClaimedReward(player, id)
	return {Success = true, RewardId = id, NewState = getRewardStateForPlayer(player).Rewards}
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

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(playerWhoPurchased, gamePassId, wasPurchased)
	if not wasPurchased then return end
	if typeof(playerWhoPurchased) ~= "Instance" or not playerWhoPurchased:IsA("Player") then return end
	local purchaseCfg = getPremiumPurchaseConfig()
	if purchaseCfg.PurchaseType ~= "GamePass" or purchaseCfg.ProductId <= 0 then return end
	if tonumber(gamePassId) ~= purchaseCfg.ProductId then return end

	local premiumFlag = getPremiumFlag(playerWhoPurchased)
	if premiumFlag then
		premiumFlag.Value = true
	end
	premiumOwnershipCheckTimestamps[playerWhoPurchased.UserId] = os.clock()
end)

Players.PlayerAdded:Connect(function(player)
	ensurePassDataLoaded(player)
	syncPremiumOwnershipIfNeeded(player)
end)

Players.PlayerRemoving:Connect(function(player)
	savePassDataForPlayer(player, true)
	loadedFromDataStore[player.UserId] = nil
	saveInFlight[player.UserId] = nil
	questGrantLocks[player.UserId] = nil
	premiumOwnershipCheckTimestamps[player.UserId] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePassDataForPlayer(player, true)
	end
end)
