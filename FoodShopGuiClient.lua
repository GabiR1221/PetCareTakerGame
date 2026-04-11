--FoodShopguiLocalScript
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local ShopRemotes = ReplicatedStorage:WaitForChild("FoodShopRemotes")
local RequestItems = ShopRemotes:WaitForChild("RequestItems")
local BuyItem = ShopRemotes:WaitForChild("BuyItem")
local TimerEvent = ShopRemotes:WaitForChild("TimerEvent")
local RestockShop = ShopRemotes:WaitForChild("RestockShop")
local UpdateShop = ShopRemotes:WaitForChild("UpdateShop")

-- GUI references
local gui = player:WaitForChild("PlayerGui"):WaitForChild("ShopGui")
local frame = gui:WaitForChild("MainFrame")
local exitButton = frame:WaitForChild("ExitButton")
local restockButton = frame:WaitForChild("RestockButton")
local timerLabel = frame:WaitForChild("TimerLabel")
local scroll = frame:WaitForChild("ScrollArea")
local template = scroll:WaitForChild("Template")

-- Number shortener
local function ShortenNumber(num)
	if num >= 1e12 then return string.format("%.2ft", num / 1e12)
	elseif num >= 1e9 then return string.format("%.2fb", num / 1e9)
	elseif num >= 1e6 then return string.format("%.2fm", num / 1e6)
	elseif num >= 1e3 then return string.format("%.2fk", num / 1e3)
	else return tostring(num)
	end
end

-- Exit button
exitButton.MouseButton1Click:Connect(function()
	frame.Visible = false
end)

-- Restock button (Robux)
restockButton.MouseButton1Click:Connect(function()
	RestockShop:FireServer()
end)

-- Refresh Shop UI
local function RefreshShop()
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") and child ~= template then
			child:Destroy()
		end
	end

	local items = RequestItems:InvokeServer()
	local y = 0

	for _, data in ipairs(items) do
		local clone = template:Clone()
		clone.Visible = true
		clone.Parent = scroll
		clone.Position = UDim2.new(0,0,0,y)

		-- Name and description
		clone:WaitForChild("NameLabel").Text = data.Name
		clone:WaitForChild("DescLabel").Text = data.Description

		-- Stock
		local stockLabel = clone:WaitForChild("StockLabel")
		stockLabel.Text = (data.Stock <= 0) and "Out of Stock" or "Stock: "..ShortenNumber(data.Stock)

		-- Image
		local imageLabel = clone:FindFirstChild("ImageLabel", true) -- recursive search
		if imageLabel then
			imageLabel.Image = data.Image or ""
		end

		-- Coins Buy Button
		local buyButton = clone:WaitForChild("BuyButton")
		buyButton.Text = ShortenNumber(data.Price)
		buyButton.MouseButton1Click:Connect(function()
			local success, msg = BuyItem:InvokeServer(data.Name)
			warn(msg)
		end)

		-- Robux Buy Button
		local robuxButton = clone:FindFirstChild("RobuxButton")
		if robuxButton and data.DevProductId then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(tonumber(data.DevProductId), Enum.InfoType.Product)
			end)
			if ok and info then
				robuxButton.Text = info.PriceInRobux .. " R$"
			else
				robuxButton.Text = "R$ ???"
			end

			robuxButton.MouseButton1Click:Connect(function()
				MarketplaceService:PromptProductPurchase(player, tonumber(data.DevProductId))
			end)
		end

		-- Hide PriceLabel if exists
		local priceLabel = clone:FindFirstChild("PriceLabel")
		if priceLabel then priceLabel.Visible = false end

		y += template.Size.Y.Offset + 10
	end

	scroll.CanvasSize = UDim2.new(0,0,0,y)
end

-- Timer countdown
TimerEvent.OnClientEvent:Connect(function(timeLeft)
	local mins = math.floor(timeLeft/60)
	local secs = timeLeft % 60
	timerLabel.Text = string.format("Restock in: %02d:%02d", mins, secs)
end)

-- Auto refresh shop
UpdateShop.OnClientEvent:Connect(RefreshShop)

-- Open GUI
workspace:WaitForChild("ShopBlock"):WaitForChild("ProximityPrompt").Triggered:Connect(function()
	RefreshShop()
	frame.Visible = true
end)
