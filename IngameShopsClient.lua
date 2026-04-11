--// Gem Shop
local Gemshop = ReplicatedStorage.GemShop
local Defaultwalkspeed = Player.Character.Humanoid.WalkSpeed
local MarketplaceService = game:GetService("MarketplaceService")

local BANK_OPEN_POSITION = UDim2.new(0.359, 0, 0.414, 0)
local PETS_WHILE_BANK_OPEN_POSITION = UDim2.new(0.095, 0, 0.414, 0)
local SELL_OPEN_POSITION = UDim2.new(0.359, 0, 0.414, 0)
local FOOD_OPEN_POSITION = UDim2.new(0.359, 0, 0.414, 0)

local openedPetFrameFromBank = false
local defaultPetsPosition = Frames.Pets.Position
local SellShopFrame = Frames:FindFirstChild("SellShop")
local FoodShopFrame = Frames:FindFirstChild("FoodShop")
local defaultSellPosition = SellShopFrame and SellShopFrame.Position or SELL_OPEN_POSITION
local defaultFoodShopPosition = FoodShopFrame and FoodShopFrame.Position or FOOD_OPEN_POSITION

local FoodShopRemotes = ReplicatedStorage:FindFirstChild("FoodShopRemotes")
local FoodRequestItems = FoodShopRemotes and FoodShopRemotes:FindFirstChild("RequestItems")
local FoodBuyItem = FoodShopRemotes and FoodShopRemotes:FindFirstChild("BuyItem")
local FoodTimerEvent = FoodShopRemotes and FoodShopRemotes:FindFirstChild("TimerEvent")
local FoodRestockShop = FoodShopRemotes and FoodShopRemotes:FindFirstChild("RestockShop")
local FoodUpdateShop = FoodShopRemotes and FoodShopRemotes:FindFirstChild("UpdateShop")

local foodProductInfoCache = {}
local ringDismissedWhileInside = {
	Gem = false,
	Bank = false,
	Sell = false,
	Food = false,
}

local function findDescendant(parent, childName)
	if not parent then return nil end
	return parent:FindFirstChild(childName, true)
end

local function shortenNumber(num)
	if num >= 1e12 then return string.format("%.2ft", num / 1e12)
	elseif num >= 1e9 then return string.format("%.2fb", num / 1e9)
	elseif num >= 1e6 then return string.format("%.2fm", num / 1e6)
	elseif num >= 1e3 then return string.format("%.2fk", num / 1e3)
	else return tostring(num)
	end
end

local function showPetsNextToBank()
	if not Frames.Pets.Visible then
		openedPetFrameFromBank = true
	end

	-- IMPORTANT: direct control, do NOT use ButtonHandler.OnClick for Pets here
	Frames.Pets:SetAttribute("CanDeletePets", false)
	Frames.Pets.Position = PETS_WHILE_BANK_OPEN_POSITION
	Frames.Pets.Visible = true
end

local function hideBankOpenedPets()
	if not openedPetFrameFromBank then return end
	openedPetFrameFromBank = false

	Frames.Pets.Visible = false
	Frames.Pets.Position = defaultPetsPosition
	Frames.Pets:SetAttribute("CanDeletePets", false)	
end

local function showPetsForSell()
	if SellShopFrame and not SellShopFrame.Visible then
		Utilities.ButtonHandler.OnClick(SellShopFrame, SELL_OPEN_POSITION)
	end

	Frames.Pets:SetAttribute("CanDeletePets", false)
end

local function hideSellShop()
	if not SellShopFrame or not SellShopFrame.Visible then return end
	Utilities.ButtonHandler.OnClick(SellShopFrame, SELL_OPEN_POSITION)
end

local function getFoodShopUi()
	if not FoodShopFrame then return nil end

	local scroll = findDescendant(FoodShopFrame, "ScrollArea")
	local template = scroll and findDescendant(scroll, "Template")
	if not scroll or not template then
		warn("[IngameShopsClient] FoodShop is missing ScrollArea/Template.")
		return nil
	end

	return {
		exitButton = findDescendant(FoodShopFrame, "ExitButton"),
		restockButton = findDescendant(FoodShopFrame, "RestockButton"),
		timerLabel = findDescendant(FoodShopFrame, "TimerLabel"),
		scroll = scroll,
		template = template,
	}
end

local foodUi = getFoodShopUi()

local function getCachedRobuxPrice(productId)
	if not productId then return nil end
	if foodProductInfoCache[productId] ~= nil then
		return foodProductInfoCache[productId]
	end

	local success, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)
	local robuxPrice = success and info and info.PriceInRobux or nil
	foodProductInfoCache[productId] = robuxPrice or false
	return robuxPrice
end

local function refreshFoodShop()
	if not foodUi or not FoodRequestItems or not FoodRequestItems:IsA("RemoteFunction") then return end

	for _, child in ipairs(foodUi.scroll:GetChildren()) do
		if child:IsA("Frame") and child ~= foodUi.template then
			child:Destroy()
		end
	end

	local ok, items = pcall(function()
		return FoodRequestItems:InvokeServer()
	end)
	if not ok or type(items) ~= "table" then
		warn("[IngameShopsClient] Food shop item request failed.")
		return
	end

	local y = 0
	for _, data in ipairs(items) do
		local clone = foodUi.template:Clone()
		clone.Visible = true
		clone.Parent = foodUi.scroll
		clone.Position = UDim2.new(0, 0, 0, y)

		local nameLabel = findDescendant(clone, "NameLabel")
		local descLabel = findDescendant(clone, "DescLabel")
		local stockLabel = findDescendant(clone, "StockLabel")
		local buyButton = findDescendant(clone, "BuyButton")
		local imageLabel = findDescendant(clone, "ImageLabel")
		local robuxButton = findDescendant(clone, "RobuxButton")
		local priceLabel = findDescendant(clone, "PriceLabel")

		if nameLabel then nameLabel.Text = tostring(data.Name or "") end
		if descLabel then descLabel.Text = tostring(data.Description or "") end
		if imageLabel then imageLabel.Image = tostring(data.Image or "") end

		local stock = tonumber(data.Stock) or 0
		if stockLabel then
			stockLabel.Text = (stock <= 0) and "Out of Stock" or ("Stock: " .. shortenNumber(stock))
		end

		if buyButton and FoodBuyItem and FoodBuyItem:IsA("RemoteFunction") then
			buyButton.Text = shortenNumber(tonumber(data.Price) or 0)
			buyButton.MouseButton1Click:Connect(function()
				local success, msg = FoodBuyItem:InvokeServer(data.Name)
				if not success then
					warn(msg)
				else
					refreshFoodShop()
				end
			end)
		end

		if robuxButton and data.DevProductId then
			local productId = tonumber(data.DevProductId)
			local price = getCachedRobuxPrice(productId)
			robuxButton.Text = price and (tostring(price) .. " R$") or "R$ ???"
			robuxButton.MouseButton1Click:Connect(function()
				if productId then
					MarketplaceService:PromptProductPurchase(Player, productId)
				end
			end)
		end

		if priceLabel then
			priceLabel.Visible = false
		end

		y += foodUi.template.Size.Y.Offset + 10
	end

	foodUi.scroll.CanvasSize = UDim2.new(0, 0, 0, y)
end

local function openFoodShop()
	if not FoodShopFrame then return end
	if not FoodShopFrame.Visible then
		Utilities.ButtonHandler.OnClick(FoodShopFrame, FOOD_OPEN_POSITION)
	end
end

local function closeFoodShop()
	if not FoodShopFrame or not FoodShopFrame.Visible then return end
	Utilities.ButtonHandler.OnClick(FoodShopFrame, FOOD_OPEN_POSITION)
end

if foodUi then
	if foodUi.exitButton then
		foodUi.exitButton.MouseButton1Click:Connect(function()
			ringDismissedWhileInside.Food = true
			closeFoodShop()
		end)
	end

	if foodUi.restockButton and FoodRestockShop and FoodRestockShop:IsA("RemoteEvent") then
		foodUi.restockButton.MouseButton1Click:Connect(function()
			FoodRestockShop:FireServer()
		end)
	end

	if foodUi.timerLabel and FoodTimerEvent and FoodTimerEvent:IsA("RemoteEvent") then
		FoodTimerEvent.OnClientEvent:Connect(function(timeLeft)
			local mins = math.floor(timeLeft / 60)
			local secs = timeLeft % 60
			foodUi.timerLabel.Text = string.format("Restock in: %02d:%02d", mins, secs)
		end)
	end

	if FoodUpdateShop and FoodUpdateShop:IsA("RemoteEvent") then
		FoodUpdateShop.OnClientEvent:Connect(refreshFoodShop)
	end
end


Frames.Bank:GetPropertyChangedSignal("Visible"):Connect(function()
	if Frames.Bank.Visible then
		showPetsNextToBank()
	else
		hideBankOpenedPets()
	end
end)

local function GemRing()
	local wasInRange = false
	local wasVisible = Frames.GemShop.Visible
	while task.wait(0.1) do
		local character = Player.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		local gemPart = workspace.Map.Rings.GemShop.MainPart
		local inRange = humanoidRootPart and (humanoidRootPart.Position - gemPart.Position).Magnitude < 10

		if inRange then
			if not Frames.GemShop.Visible and not ringDismissedWhileInside.Gem then
				Utilities.ButtonHandler.OnClick(Frames.GemShop, UDim2.new(0.359,0,0.414,0))
			end
		else
			if Frames.GemShop.Visible then
				Utilities.ButtonHandler.OnClick(Frames.GemShop, UDim2.new(0.359,0,0.414,0))
			end
			ringDismissedWhileInside.Gem = false
		end

		if wasInRange and wasVisible and not Frames.GemShop.Visible then
			ringDismissedWhileInside.Gem = true
		end
		
		wasInRange = inRange and true or false
		wasVisible = Frames.GemShop.Visible

		if Player.Character then
			local Walkspeed = Defaultwalkspeed + Gemshop["1"].Reward.DefaultReward.Value + Gemshop["1"].Reward.IncreasePer.Value * (PlayerData.GemUpgrade1.Value+1)
			Player.Character.Humanoid.WalkSpeed = Walkspeed
		end
	end
end

local function BankRing()
	local wasInRange = false
	local wasVisible = Frames.Bank.Visible
	while task.wait(0.1) do
		local character = Player.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		local bankPart = workspace.Map.Rings.Bank.MainPart
		local inRange = humanoidRootPart and (humanoidRootPart.Position - bankPart.Position).Magnitude < 10

		if inRange then
			if not Frames.Bank.Visible and not ringDismissedWhileInside.Bank then
				Utilities.ButtonHandler.OnClick(Frames.Bank, BANK_OPEN_POSITION)
			elseif Frames.Bank.Visible then
				showPetsNextToBank()
			end
		else
			if Frames.Bank.Visible then
				Utilities.ButtonHandler.OnClick(Frames.Bank, BANK_OPEN_POSITION)
			end
			ringDismissedWhileInside.Bank = false
		end

		if wasInRange and wasVisible and not Frames.Bank.Visible then
			ringDismissedWhileInside.Bank = true
		end
	end
end

local function SellRing()
	local wasInRange = false
	local wasVisible = SellShopFrame and SellShopFrame.Visible or false

	while task.wait(0.1) do
		local character = Player.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		local rings = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Rings")
		local sellPart = rings and rings:FindFirstChild("Sell") and rings.Sell:FindFirstChild("MainPart")
		local inRange = humanoidRootPart and sellPart and (humanoidRootPart.Position - sellPart.Position).Magnitude < 10

		if inRange then
			if not ringDismissedWhileInside.Sell then
				showPetsForSell()
			end
		else
			if SellShopFrame and SellShopFrame.Visible then
				hideSellShop()
			end
			ringDismissedWhileInside.Sell = false
		end

		if wasInRange and wasVisible and SellShopFrame and not SellShopFrame.Visible then
			ringDismissedWhileInside.Sell = true
		end

		wasInRange = inRange and true or false
		wasVisible = SellShopFrame and SellShopFrame.Visible or false
	end
end

local function FoodRing()
	local wasInRange = false
	local wasVisible = FoodShopFrame and FoodShopFrame.Visible or false

	while task.wait(0.1) do
		local character = Player.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		local rings = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Rings")
		local foodRing = rings and (rings:FindFirstChild("FoodShop") or rings:FindFirstChild("Food") or rings:FindFirstChild("Shop"))
		local foodPart = foodRing and foodRing:FindFirstChild("MainPart")
		local inRange = humanoidRootPart and foodPart and (humanoidRootPart.Position - foodPart.Position).Magnitude < 10

		if inRange then
			if not wasInRange and not ringDismissedWhileInside.Food then
				openFoodShop()
				task.spawn(refreshFoodShop)
			end
		else
			if FoodShopFrame and FoodShopFrame.Visible then
				closeFoodShop()
			end
			ringDismissedWhileInside.Food = false
		end

		if wasInRange and wasVisible and FoodShopFrame and not FoodShopFrame.Visible then
			ringDismissedWhileInside.Food = true
		end

		wasInRange = inRange and true or false
		wasVisible = FoodShopFrame and FoodShopFrame.Visible or false
	end
end

coroutine.wrap(GemRing)()
coroutine.wrap(BankRing)()
coroutine.wrap(SellRing)()
coroutine.wrap(FoodRing)()
