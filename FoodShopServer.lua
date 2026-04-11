--FoodShopServerScript
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

-- Remotes
local RemoteFolder = Instance.new("Folder")
RemoteFolder.Name = "ShopRemotes"
RemoteFolder.Parent = ReplicatedStorage

local RequestItems = ReplicatedStorage:WaitForChild("FoodShopRemotes"):WaitForChild("RequestItems")

local BuyItem = ReplicatedStorage:WaitForChild("FoodShopRemotes"):WaitForChild("BuyItem")

local TimerEvent = ReplicatedStorage:WaitForChild("FoodShopRemotes"):WaitForChild("TimerEvent")

local RestockShop = ReplicatedStorage:WaitForChild("FoodShopRemotes"):WaitForChild("RestockShop")

local UpdateShop = ReplicatedStorage:WaitForChild("FoodShopRemotes"):WaitForChild("UpdateShop")

-- Shop Items
local ShopItems = ReplicatedStorage:WaitForChild("ShopItems")

-- Shop Settings
local MAX_STOCK = 7
local RESTOCK_INTERVAL = 600 -- 10 minutes
local RESTOCK_PRODUCT_ID = 3561013506
local timeLeft = RESTOCK_INTERVAL

-- Track last out-of-stock indices
local lastOutOfStock = {}

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

-- Initialize stock randomly
local function InitializeStock()
	local folders = {}
	for _, folder in ipairs(ShopItems:GetChildren()) do
		if folder:IsA("Folder") then
			table.insert(folders, folder)
		end
	end

	local outOfStock = {}
	while #outOfStock < 3 and #folders >= 3 do
		local idx = math.random(1, #folders)
		if not table.find(outOfStock, idx) then
			table.insert(outOfStock, idx)
		end
	end

	for i, folder in ipairs(folders) do
		local stock = folder:FindFirstChild("Stock")
		local chance = folder:FindFirstChild("StockChance") and folder.StockChance.Value or 100
		if stock then
			if table.find(outOfStock, i) then
				stock.Value = 0
			else
				if math.random(1,100) <= chance then
					stock.Value = math.random(1, MAX_STOCK)
				else
					stock.Value = 0
				end
			end
		end
	end

	lastOutOfStock = outOfStock
end
InitializeStock()

-- Build data for client
local function GetItemData()
	local items = {}
	for _, folder in ipairs(ShopItems:GetChildren()) do
		if folder:IsA("Folder") then
			table.insert(items, {
				Name = folder.Name,
				Description = folder:FindFirstChild("Description") and folder.Description.Value or "",
				Image = folder:FindFirstChild("Image") and folder.Image.Value or "",
				Stock = folder:FindFirstChild("Stock") and folder.Stock.Value or 0,
				Price = folder:FindFirstChild("Price") and folder.Price.Value or 0,
				DevProductId = folder:FindFirstChild("DevProductId") and folder.DevProductId.Value or nil
			})
		end
	end
	return items
end

-- Restock logic
local function Restock(force)
	local folders = {}
	for _, folder in ipairs(ShopItems:GetChildren()) do
		if folder:IsA("Folder") then
			table.insert(folders, folder)
		end
	end

	if #folders == 0 then return end

	-- Pick 3 items to be out of stock (cannot repeat last time)
	local outOfStock = {}
	while #outOfStock < 3 and #folders >= 3 do
		local idx = math.random(1, #folders)
		if not table.find(outOfStock, idx) and not table.find(lastOutOfStock, idx) then
			table.insert(outOfStock, idx)
		end
	end

	-- Randomize stock for all items
	for i, folder in ipairs(folders) do
		local stock = folder:FindFirstChild("Stock")
		local chance = folder:FindFirstChild("StockChance") and folder.StockChance.Value or 100
		if stock then
			if table.find(outOfStock, i) then
				stock.Value = 0
			else
				if math.random(1,100) <= chance then
					stock.Value = math.random(1, MAX_STOCK)
				else
					stock.Value = 0
				end
			end
		end
	end

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
		Restock(false)
		UpdateShop:FireAllClients()
	end
end)

-- Request items
RequestItems.OnServerInvoke = function(player)
	return GetItemData()
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
	local folder = ShopItems:FindFirstChild(itemName)
	if not folder then return false, "Item not found" end

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
		return false, "Item not configured properly"
	end
	if stock.Value <= 0 then
		return false, "Out of stock"
	end

	local coins = player:FindFirstChild("Data"):FindFirstChild("PlayerData"):FindFirstChild("Currency")
	if not coins then return false, "No Coins stat found" end
	if coins.Value < price.Value then
		return false, "Not enough Coins"
	end

	coins.Value -= price.Value
	stock.Value -= 1
	GiveItem(player, itemName)

	UpdateShop:FireAllClients()
	return true, "Purchased " .. itemName
end

-- Robux purchases
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessed
	end

	local productId = receiptInfo.ProductId

	if productId == RESTOCK_PRODUCT_ID then
		Restock(true)
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
		else
			return Enum.ProductPurchaseDecision.NotProcessed
		end
	end

	return Enum.ProductPurchaseDecision.NotProcessed
end
