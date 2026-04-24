--!strict
-- Client binder for Pass UI (Rewards + Quests + Shop).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PassRewardsConfig = require(modulesFolder:WaitForChild("PassRewardsConfig"))

local passFrame = script.Parent
local rewardsHolder = passFrame:WaitForChild("RewardsHolder") :: GuiObject
local rewardsScrolling = rewardsHolder:WaitForChild("Rewards")
local questsHolder = passFrame:WaitForChild("QuestsHolder") :: GuiObject
local questsScrolling = questsHolder:WaitForChild("Quests")
local shopHolder = passFrame:WaitForChild("ShopHolder") :: GuiObject
local shopItemsScrolling = shopHolder:WaitForChild("Items")
local otherMenusHolder = passFrame:WaitForChild("OtherMenusHolder")

local claimRemote = ReplicatedStorage:WaitForChild(PassRewardsConfig.ClaimRemoteName) :: RemoteFunction
local rewardsStateRemote = ReplicatedStorage:WaitForChild(PassRewardsConfig.StateRemoteName) :: RemoteFunction
local questsStateRemote = ReplicatedStorage:WaitForChild(PassRewardsConfig.GetQuestStateRemoteName) :: RemoteFunction
local shopStateRemote = ReplicatedStorage:WaitForChild(PassRewardsConfig.GetShopStateRemoteName) :: RemoteFunction
local buyShopRemote = ReplicatedStorage:WaitForChild(PassRewardsConfig.BuyShopItemRemoteName) :: RemoteFunction
local questStateUpdatedRemote = ReplicatedStorage:WaitForChild("PassQuestStateUpdated") :: RemoteEvent

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

type ClaimResponse = {
	Success: boolean,
	Error: string?,
	RewardId: number?,
	NewState: {RewardStateItem}?,
}

type BuyResponse = {
	Success: boolean,
	Error: string?,
	ShopState: {ShopStateItem}?,
}

type TabSpec = {
	Key: string,
	Holder: GuiObject,
	ContainerNames: {string},
	ButtonNames: {string},
}

local rewardsById: {[number]: RewardStateItem} = {}
local rewardClaimLocks: {[number]: boolean} = {}
local shopBuyLocks: {[number]: boolean} = {}

local tabSpecs: {TabSpec} = {
	{
		Key = "Rewards",
		Holder = rewardsHolder,
		ContainerNames = {"RewardsFrameButton", "Rewards"},
		ButtonNames = {"RewardsButton", "Rewards"},
	},
	{
		Key = "Shop",
		Holder = shopHolder,
		ContainerNames = {"ShopFrameButton", "Shop"},
		ButtonNames = {"ShopButton", "Shop"},
	},
	{
		Key = "Quests",
		Holder = questsHolder,
		ContainerNames = {"QuestsFrameButton", "Quests"},
		ButtonNames = {"QuestsButton", "QuestsFrameButton", "Quests"},
	},
}

local function showHolder(holderKey: string)
	for _, spec in ipairs(tabSpecs) do
		spec.Holder.Visible = spec.Key == holderKey
	end
end

local function findNamedGuiButton(root: Instance, names: {string}): GuiButton?
	local wanted: {[string]: boolean} = {}
	for _, name in ipairs(names) do
		wanted[name] = true
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiButton") and wanted[descendant.Name] then
			return descendant
		end
	end
	return nil
end

local function resolveTabButton(spec: TabSpec): GuiButton?
	for _, containerName in ipairs(spec.ContainerNames) do
		local container = otherMenusHolder:FindFirstChild(containerName)
		if container then
			local insideContainer = findNamedGuiButton(container, spec.ButtonNames)
			if insideContainer then
				return insideContainer
			end
			for _, descendant in ipairs(container:GetDescendants()) do
				if descendant:IsA("GuiButton") then
					return descendant
				end
			end
		end
	end

	return findNamedGuiButton(otherMenusHolder, spec.ButtonNames)
end

local function bindMenuButtons()
	for _, spec in ipairs(tabSpecs) do
		local button = resolveTabButton(spec)
		if button then
			button.MouseButton1Click:Connect(function()
				showHolder(spec.Key)
			end)
		else
			warn(string.format("[PassRewards] Missing tab button for %s", spec.Key))
		end
	end
	showHolder("Rewards")
end

local function getRewardFrameById(id: number): Frame?
	local frame = rewardsScrolling:FindFirstChild(tostring(id))
	if frame and frame:IsA("Frame") then return frame end
	return nil
end

local function getQuestFrame(category: string, slot: number, id: number): Frame?
	local categoryFolder = questsScrolling:FindFirstChild(category)
	if not categoryFolder then return nil end
	local bySlot = categoryFolder:FindFirstChild(tostring(slot))
	if bySlot and bySlot:IsA("Frame") then return bySlot end
	local byId = categoryFolder:FindFirstChild(tostring(id))
	if byId and byId:IsA("Frame") then return byId end
	return nil
end

local function getShopItemFrame(id: number): Frame?
	local frame = shopItemsScrolling:FindFirstChild(tostring(id))
	if frame and frame:IsA("Frame") then return frame end
	return nil
end

local function setRewardButtonVisual(button: TextButton, canClaim: boolean, claimed: boolean)
	if claimed then
		button.Text = "Claimed"
		button.Active = false
		button.AutoButtonColor = false
	elseif canClaim then
		button.Text = "Ready to Claim"
		button.Active = true
		button.AutoButtonColor = true
	else
		button.Text = "Locked"
		button.Active = false
		button.AutoButtonColor = false
	end
end

local function bindRewardClaimButton(rewardId: number, button: TextButton)
	button.MouseButton1Click:Connect(function()
		if rewardClaimLocks[rewardId] then return end
		rewardClaimLocks[rewardId] = true
		local rewardState = rewardsById[rewardId]
		if not rewardState or rewardState.Claimed or not rewardState.CanClaim then
			rewardClaimLocks[rewardId] = false
			return
		end

		local oldText = button.Text
		button.Text = "Claiming..."
		button.Active = false
		local ok, result = pcall(function(): ClaimResponse
			return claimRemote:InvokeServer(rewardId)
		end)
		if not ok or type(result) ~= "table" or result.Success ~= true then
			button.Text = result and result.Error and tostring(result.Error) or "Failed"
			task.delay(1.4, function()
				if button.Parent then
					button.Text = oldText
					button.Active = true
				end
			end)
			rewardClaimLocks[rewardId] = false
			return
		end

		local newState = result.NewState
		if type(newState) == "table" then
			for _, entry in ipairs(newState :: {RewardStateItem}) do
				rewardsById[entry.Id] = entry
			end
		end
		local updated = rewardsById[rewardId]
		setRewardButtonVisual(button, updated ~= nil and updated.CanClaim == true, updated ~= nil and updated.Claimed == true)
		rewardClaimLocks[rewardId] = false
	end)
end

local function refreshRewards()
	local ok, result = pcall(function(): {RewardStateItem}
		return rewardsStateRemote:InvokeServer()
	end)
	if not ok or type(result) ~= "table" then return end
	table.clear(rewardsById)
	for _, reward in ipairs(result :: {RewardStateItem}) do
		rewardsById[reward.Id] = reward
		local frame = getRewardFrameById(reward.Id)
		if frame then
			local rewardImage = frame:FindFirstChild("RewardImage")
			local rewardText = frame:FindFirstChild("RewardText")
			local rewardButton = frame:FindFirstChild("RewardButton")
			if rewardImage and rewardImage:IsA("ImageLabel") and rewardText and rewardText:IsA("TextLabel") and rewardButton and rewardButton:IsA("TextButton") then
				rewardImage.Image = tostring(reward.RewardImage)
				rewardText.Text = tostring(reward.RewardText)
				setRewardButtonVisual(rewardButton, reward.CanClaim, reward.Claimed)
				if rewardButton:GetAttribute("PassRewardBound") ~= true then
					rewardButton:SetAttribute("PassRewardBound", true)
					bindRewardClaimButton(reward.Id, rewardButton)
				end
			end
		end
	end
end

local function refreshQuests()
	local ok, result = pcall(function(): {QuestStateItem}
		return questsStateRemote:InvokeServer()
	end)
	if not ok or type(result) ~= "table" then return end

	for _, quest in ipairs(result :: {QuestStateItem}) do
		local frame = getQuestFrame(quest.Category, quest.Slot, quest.Id)
		if frame then
			local questImage = frame:FindFirstChild("QuestImage")
			local questText = frame:FindFirstChild("QuestText")
			local status = frame:FindFirstChild("Status")
			local questReward = frame:FindFirstChild("QuestReward")
			if questImage and questImage:IsA("ImageLabel") then questImage.Image = tostring(quest.QuestImage) end
			if questText and questText:IsA("TextLabel") then questText.Text = tostring(quest.QuestText) end
			if status and status:IsA("TextLabel") then status.Text = tostring(quest.StatusText) end
			if questReward and questReward:IsA("TextLabel") then questReward.Text = tostring(quest.QuestReward) end
		end
	end
end

local function bindShopButton(itemId: number, itemButton: TextButton)
	itemButton.MouseButton1Click:Connect(function()
		if shopBuyLocks[itemId] then return end
		shopBuyLocks[itemId] = true
		local old = itemButton.Text
		itemButton.Text = "Buying..."
		itemButton.Active = false
		local ok, result = pcall(function(): BuyResponse
			return buyShopRemote:InvokeServer(itemId)
		end)
		if not ok or type(result) ~= "table" or result.Success ~= true then
			itemButton.Text = result and result.Error and tostring(result.Error) or "Failed"
			task.delay(1.2, function()
				if itemButton.Parent then
					itemButton.Text = old
					itemButton.Active = true
				end
			end)
			shopBuyLocks[itemId] = false
			return
		end
		itemButton.Text = "Bought"
		task.delay(0.8, function()
			if itemButton.Parent then
				itemButton.Text = old
				itemButton.Active = true
			end
		end)
		refreshQuests()
		shopBuyLocks[itemId] = false
	end)
end

local function refreshShop()
	local ok, result = pcall(function(): {ShopStateItem}
		return shopStateRemote:InvokeServer()
	end)
	if not ok or type(result) ~= "table" then return end
	for _, item in ipairs(result :: {ShopStateItem}) do
		local frame = getShopItemFrame(item.Id)
		if frame then
			local itemImage = frame:FindFirstChild("ItemImage")
			local itemText = frame:FindFirstChild("ItemText")
			local itemPrice = frame:FindFirstChild("ItemPrice")
			local itemButton = frame:FindFirstChild("ItemButton")
			if itemImage and itemImage:IsA("ImageLabel") then itemImage.Image = tostring(item.ItemImage) end
			if itemText and itemText:IsA("TextLabel") then itemText.Text = tostring(item.ItemText) end
			if itemPrice and itemPrice:IsA("TextLabel") then itemPrice.Text = tostring(item.PriceText) end
			if itemButton and itemButton:IsA("TextButton") then
				itemButton.Text = "Buy"
				itemButton.Active = true
				if itemButton:GetAttribute("PassShopBound") ~= true then
					itemButton:SetAttribute("PassShopBound", true)
					bindShopButton(item.Id, itemButton)
				end
			end
		end
	end
end

bindMenuButtons()
refreshRewards()
refreshQuests()
refreshShop()

task.spawn(function()
	while passFrame.Parent do
		task.wait(2)
		if passFrame.Visible and questsHolder.Visible then
			refreshQuests()
		end
	end
end)

questStateUpdatedRemote.OnClientEvent:Connect(function()
	refreshQuests()
end)
