--FoodShopServerScript
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

-- Remotes
local remotesFolder = ReplicatedStorage:WaitForChild("FoodShopRemotes")
local RequestItems = remotesFolder:WaitForChild("RequestItems")
local BuyItem = remotesFolder:WaitForChild("BuyItem")
local TimerEvent = remotesFolder:WaitForChild("TimerEvent")
local RestockShop = remotesFolder:WaitForChild("RestockShop")
local UpdateShop = remotesFolder:WaitForChild("UpdateShop")

-- Shop Items
local ShopItems = ReplicatedStorage:WaitForChild("ShopItems")

-- Shop Settings
local MAX_STOCK = 7
local RESTOCK_INTERVAL = 600 -- 10 minutes
local RESTOCK_PRODUCT_ID = 3561013506
local timeLeft = RESTOCK_INTERVAL

-- Track last out-of-stock indices
local lastOutOfStock = {}
local purchaseLocks = {}

-- Map DevProductId → ItemName
local ProductMap = {}
for _, folder in ipairs(ShopItems:GetChildren()) do
	if folder:IsA("Folder") and folder:FindFirstChild("DevProductId") then
		local id = tonumber(folder.DevProductId.Value)
		if id then
			ProductMap[id] = folder.Name
		end
	end
end

local foodReceiptBridge = ReplicatedStorage:FindFirstChild("FoodShopHandleReceipt")
if not foodReceiptBridge or not foodReceiptBridge:IsA("BindableFunction") then
	foodReceiptBridge = Instance.new("BindableFunction")
	foodReceiptBridge.Name = "FoodShopHandleReceipt"
	foodReceiptBridge.Parent = ReplicatedStorage
end


local function buildFolders()
	local folders = {}
	for _, folder in ipairs(ShopItems:GetChildren()) do
		if folder:IsA("Folder") then
			table.insert(folders, folder)
		end
	end
	table.sort(folders, function(a, b)
		return a.Name < b.Name
	end)
	return folders
end


local function getRandomOutOfStockIndices(totalItems)
	-- Keep at least one item eligible for stock so the shop never rolls fully empty.
	local maxOutOfStock = math.max(0, totalItems - 1)
	local targetOutOfStock = math.min(3, maxOutOfStock)
	local picks = {}
	local maxAttempts = math.max(20, totalItems * 3)
	local attempts = 0

	while #picks < targetOutOfStock and attempts < maxAttempts do
		attempts += 1
		local idx = math.random(1, totalItems)
		if not table.find(picks, idx) and not table.find(lastOutOfStock, idx) then
			table.insert(picks, idx)
		end
	end

	while #picks < targetOutOfStock do
		local idx = math.random(1, totalItems)
		if not table.find(picks, idx) then
			table.insert(picks, idx)
		end
	end

	return picks
end

local function applyStockRoll(folders, outOfStock)
	local inStockCount = 0
	local eligibleFallback = {}
	for i, folder in ipairs(folders) do
		local stock = folder:FindFirstChild("Stock")
		local chance = folder:FindFirstChild("StockChance") and folder.StockChance.Value or 100
		if stock then
			if table.find(outOfStock, i) then
				stock.Value = 0
			else
				table.insert(eligibleFallback, stock)
				if math.random(1, 100) <= chance then
					stock.Value = math.random(1, MAX_STOCK)
				else
					stock.Value = 0
				end
				if stock.Value > 0 then
					inStockCount += 1
				end
			end
		end
	end

	if inStockCount <= 0 and #eligibleFallback > 0 then
		local targetStock = eligibleFallback[math.random(1, #eligibleFallback)]
		if targetStock then
			targetStock.Value = math.random(1, MAX_STOCK)
		end
	end
end

-- Initialize stock randomly
local function initializeStock()
	local folders = buildFolders()
	if #folders == 0 then return end

	local outOfStock = getRandomOutOfStockIndices(#folders)
	applyStockRoll(folders, outOfStock)
	lastOutOfStock = outOfStock
end
initializeStock()

local function getPlayerCurrencyValue(player)
	local data = player:FindFirstChild("Data")
	local playerData = data and data:FindFirstChild("PlayerData")
	local coins = playerData and playerData:FindFirstChild("Currency")
	if coins and (coins:IsA("NumberValue") or coins:IsA("IntValue")) then
		return coins
	end
	return nil
end

-- Build data for client
local function getItemData()
	local items = {}
	for _, folder in ipairs(buildFolders()) do
		table.insert(items, {
			Name = folder.Name,
			Description = folder:FindFirstChild("Description") and folder.Description.Value or "",
			Image = folder:FindFirstChild("Image") and folder.Image.Value or "",
			Stock = folder:FindFirstChild("Stock") and folder.Stock.Value or 0,
			Price = folder:FindFirstChild("Price") and folder.Price.Value or 0,
			DevProductId = folder:FindFirstChild("DevProductId") and folder.DevProductId.Value or nil,
		})
	end
	return items
end

-- Restock logic
local function Restock()
	local folders = buildFolders()
	if #folders == 0 then return end

	local outOfStock = getRandomOutOfStockIndices(#folders)
	applyStockRoll(folders, outOfStock)
	lastOutOfStock = outOfStock
end

-- Handle restock button
RestockShop.OnServerEvent:Connect(function(player)
	MarketplaceService:PromptProductPurchase(player, RESTOCK_PRODUCT_ID)
end)

-- Timer + Auto restock
task.spawn(function()
	while true do
		timeLeft = RESTOCK_INTERVAL
		while timeLeft > 0 do
			TimerEvent:FireAllClients(timeLeft)
			task.wait(1)
			timeLeft -= 1
		end
		Restock()
		UpdateShop:FireAllClients()
	end
end)

-- Request items
RequestItems.OnServerInvoke = function()
	return getItemData()
end

-- Give item
local function GiveItem(player, itemName)
	local folder = ShopItems:FindFirstChild(itemName)
	if not folder then return false end

	local tool
	for _, obj in ipairs(folder:GetChildren()) do
		if obj:IsA("Tool") or obj:IsA("Model") then
			tool = obj
			break
		end
	end

	if tool then
		local clone = tool:Clone()
		if clone:IsA("Tool") then
			clone:SetAttribute("InventoryCategory", "Food")
			clone:SetAttribute("FoodTool", true)
			clone.Parent = player.Backpack
		else
			clone.Parent = player:WaitForChild("StarterGear")
		end
		return true
	end
	return false
end

-- Buy with Coins
BuyItem.OnServerInvoke = function(player, itemName)
	if type(itemName) ~= "string" then
		return false, "Invalid item request"
	end

	if purchaseLocks[itemName] then
		return false, "Please try again"
	end
	purchaseLocks[itemName] = true

	local folder = ShopItems:FindFirstChild(itemName)
	if not folder then
		purchaseLocks[itemName] = nil
		return false, "Item not found"
	end

	local stock = folder:FindFirstChild("Stock")
	local price = folder:FindFirstChild("Price")
	local tool
	for _, obj in ipairs(folder:GetChildren()) do
		if obj:IsA("Tool") or obj:IsA("Model") then
			tool = obj
			break
		end
	end

	if not stock or not price or not tool then
		purchaseLocks[itemName] = nil
		return false, "Item not configured properly"
	end
	if stock.Value <= 0 then
		purchaseLocks[itemName] = nil
		return false, "Out of stock"
	end

	local coins = getPlayerCurrencyValue(player)
	if not coins then
		purchaseLocks[itemName] = nil
		return false, "No Coins stat found"
	end
	if coins.Value < price.Value then
		purchaseLocks[itemName] = nil
		return false, "Not enough Coins"
	end

	coins.Value -= price.Value
	stock.Value = math.max(0, stock.Value - 1)
	GiveItem(player, itemName)

	purchaseLocks[itemName] = nil
	UpdateShop:FireAllClients()
	return true, "Purchased " .. itemName
end

-- Robux purchases (handled via central receipt dispatcher)
foodReceiptBridge.OnInvoke = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local productId = receiptInfo.ProductId

	if productId == RESTOCK_PRODUCT_ID then
		Restock()
		timeLeft = RESTOCK_INTERVAL
		TimerEvent:FireAllClients(timeLeft)
		UpdateShop:FireAllClients()
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local itemName = ProductMap[productId]
	if itemName then
		local success = GiveItem(player, itemName)
		if success then
			UpdateShop:FireAllClients()
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end
