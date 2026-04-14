local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ID_SINGLE_SPIN = 3574227749
local ID_TRIPLE_SPIN = 3574767447

local PRIZES = {
	{ Name = "100 Gem", Currency = "Currency2", Amount = 100 },
	{ Name = "200 Gem", Currency = "Currency2", Amount = 200 },
	{ Name = "500 Gem", Currency = "Currency2", Amount = 500 },
	{ Name = "1000 Gem", Currency = "Currency2", Amount = 1000 },
	{ Name = "1000 Cash", Currency = "Currency", Amount = 1000 },
	{ Name = "500 Cash", Currency = "Currency", Amount = 500 },
	{ Name = "200 Cash", Currency = "Currency", Amount = 200 },
	{ Name = "100 Cash", Currency = "Currency", Amount = 100 },
}

local startSpinEvent = ReplicatedStorage:FindFirstChild("StartSpinAnimation") or Instance.new("RemoteEvent")
startSpinEvent.Name = "StartSpinAnimation"
startSpinEvent.Parent = ReplicatedStorage

local requestSpinReward = ReplicatedStorage:FindFirstChild("RequestSpinReward") or Instance.new("RemoteFunction")
requestSpinReward.Name = "RequestSpinReward"
requestSpinReward.Parent = ReplicatedStorage

local legacyRewardEvent = ReplicatedStorage:FindFirstChild("ClaimSpinReward") or Instance.new("RemoteEvent")
legacyRewardEvent.Name = "ClaimSpinReward"
legacyRewardEvent.Parent = ReplicatedStorage

local pendingSpinsByUserId = {}

local function getNumericValue(parent, name)
	if not parent then return nil end
	local obj = parent:FindFirstChild(name)
	if obj and (obj:IsA("IntValue") or obj:IsA("NumberValue")) then
		return obj
	end
	return nil
end

local function addPlayerCurrency(player, currencyName, amount)
	if amount <= 0 then return false end

	local data = player:FindFirstChild("Data")
	local playerData = data and data:FindFirstChild("PlayerData")
	local valueObject = getNumericValue(playerData, currencyName)
	if valueObject then
		valueObject.Value += amount
		return true
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		if currencyName == "Currency2" then
			local gems = getNumericValue(leaderstats, "Gems") or getNumericValue(leaderstats, "Currency2")
			if gems then
				gems.Value += amount
				return true
			end
		elseif currencyName == "Currency" then
			local cash = getNumericValue(leaderstats, "Cash") or getNumericValue(leaderstats, "Currency")
			if cash then
				cash.Value += amount
				return true
			end
		end
	end

	return false
end

local function queueSpins(player, amount)
	if amount <= 0 then return end
	pendingSpinsByUserId[player.UserId] = (pendingSpinsByUserId[player.UserId] or 0) + amount
	startSpinEvent:FireClient(player, amount)
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if receiptInfo.ProductId == ID_SINGLE_SPIN then
		queueSpins(player, 1)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif receiptInfo.ProductId == ID_TRIPLE_SPIN then
		queueSpins(player, 3)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

requestSpinReward.OnServerInvoke = function(player)
	if not player then return nil end

	local pending = pendingSpinsByUserId[player.UserId] or 0
	if pending <= 0 then
		return nil
	end

	pendingSpinsByUserId[player.UserId] = pending - 1

	local winningIndex = math.random(1, #PRIZES)
	local prize = PRIZES[winningIndex]
	if not prize then
		return nil
	end

	addPlayerCurrency(player, prize.Currency, prize.Amount)

	return {
		winningIndex = winningIndex,
		name = prize.Name,
		currency = prize.Currency,
		amount = prize.Amount,
	}
end

legacyRewardEvent.OnServerEvent:Connect(function(player)
	warn(("[SpinWheel] Ignored legacy reward claim from %s; rewards are server-authoritative now."):format(player.Name))
end)

Players.PlayerRemoving:Connect(function(player)
	pendingSpinsByUserId[player.UserId] = nil
end)
