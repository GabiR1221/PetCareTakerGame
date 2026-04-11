local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- REPLACE THESE WITH YOUR ACTUAL IDS FROM THE DASHBOARD
local ID_SINGLE_SPIN = 3546187801 
local ID_TRIPLE_SPIN = 3546187800 

-- RemoteEvents setup
local rewardEvent = ReplicatedStorage:FindFirstChild("ClaimSpinReward") or Instance.new("RemoteEvent")
rewardEvent.Name = "ClaimSpinReward"
rewardEvent.Parent = ReplicatedStorage

local startSpinEvent = ReplicatedStorage:FindFirstChild("StartSpinAnimation") or Instance.new("RemoteEvent")
startSpinEvent.Name = "StartSpinAnimation"
startSpinEvent.Parent = ReplicatedStorage

-- 1. LEADERSTATS SETUP
game.Players.PlayerAdded:Connect(function(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local gems = Instance.new("IntValue")
	gems.Name = "Gems"
	gems.Value = 0
	gems.Parent = leaderstats

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = 0
	cash.Parent = leaderstats
end)

-- 2. DEVELOPER PRODUCT PURCHASE HANDLER
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = game.Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then 
		return Enum.ProductPurchaseDecision.NotProcessedYet 
	end

	-- Check which product was bought
	if receiptInfo.ProductId == ID_SINGLE_SPIN then
		-- Tell the client to spin 1 time
		startSpinEvent:FireClient(player, 1)
		return Enum.ProductPurchaseDecision.PurchaseGranted

	elseif receiptInfo.ProductId == ID_TRIPLE_SPIN then
		-- Tell the client to spin 3 times
		startSpinEvent:FireClient(player, 3)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- 3. SECURE REWARD RECEIVER
rewardEvent.OnServerEvent:Connect(function(player, prizeName)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	-- Extract the number from the string (e.g., "100 Gem" -> 100)
	local amount = tonumber(string.match(prizeName, "%d+"))
	if not amount then return end

	if string.find(prizeName, "Gem") then
		leaderstats.Gems.Value += amount
	elseif string.find(prizeName, "Cash") then
		leaderstats.Cash.Value += amount
	end

	print("Verified Reward for " .. player.Name .. ": " .. prizeName)
end)
