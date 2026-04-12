-- In this module you can find things like Rebirth Multiplier. By using code such as Multipliers.RebirthMultiplier(Player) returns a number which is that player's multiplier. Useful if you have multipliers in multiple scripts

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameSettings = ReplicatedStorage["Game Settings"]

local PetMultipliers = require(ReplicatedStorage.Modules.PetMultipliers)

local Multipliers = {}
local FRIEND_BONUS_PER_FRIEND = 0.10
local PREMIUM_BONUS_MULTIPLIER = 1.40
local FRIEND_COUNT_CACHE_SECONDS = 10
local friendCountCache = {} -- [userId] = {count = number, expiresAt = time}

local function getFriendCountInServer(player)
	if not player then return 0 end

	local now = os.clock()
	local cacheEntry = friendCountCache[player.UserId]
	if cacheEntry and cacheEntry.expiresAt > now then
		return cacheEntry.count
	end

	local count = 0
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			local ok, isFriend = pcall(player.IsFriendsWith, player, otherPlayer.UserId)
			if ok and isFriend then
				count += 1
			end
		end
	end

	friendCountCache[player.UserId] = {
		count = count,
		expiresAt = now + FRIEND_COUNT_CACHE_SECONDS
	}
	return count
end

function Multipliers.RebirthMultiplier(Player)
	local Multi = 1
	
	if GameSettings.RebirthType.Value == "Linear" then
		Multi *= (Player.Data.PlayerData.Rebirth.Value * GameSettings.RebirthMultiplier.Value + 1) -- so multi = RebirthMulti + 1
	else
		Multi *= (GameSettings.RebirthMultiplier.Value + 0.5) ^ Player.Data.PlayerData.Rebirth.Value
	end
	
	return Multi	
end

function Multipliers.CurrencyMultiplier(Player)
	local Multi = GameSettings.CurrencyMultiplier.Value
	Multi *= (Player.Data.Gamepasses.DoubleCurrency.Value and 2 or 1)
	Multi *= Multipliers.RebirthMultiplier(Player)
	Multi *= PetMultipliers.ReadPlayerMultiplier(Player.Name)
	
	local R = ReplicatedStorage.GemShop["2"].Reward
	if R.Exponential.Value then
		Multi *= R.DefaultReward.Value + R.IncreasePer.Value ^ Player.Data.PlayerData.GemUpgrade2.Value
	else
		Multi *= R.DefaultReward.Value + R.IncreasePer.Value * Player.Data.PlayerData.GemUpgrade2.Value
	end

	local friendCount = getFriendCountInServer(Player)
	Multi *= (1 + (friendCount * FRIEND_BONUS_PER_FRIEND))
	
	if Player.MembershipType == Enum.MembershipType.Premium then
		Multi *= PREMIUM_BONUS_MULTIPLIER
	end
	
	return Multi
end

function Multipliers.GetFriendBoostPercent(Player)
	local friendCount = getFriendCountInServer(Player)
	return friendCount * (FRIEND_BONUS_PER_FRIEND * 100)
end

function Multipliers.GetPremiumBoostPercent(Player)
	if Player and Player.MembershipType == Enum.MembershipType.Premium then
		return (PREMIUM_BONUS_MULTIPLIER - 1) * 100
	end
	return 0
end


function Multipliers.GetMaxPetsEquipped(Player)
	return 5 + (Player.Data.Gamepasses["MorePets1"].Value and 3 or 0)
end

function Multipliers.GetMaxPetsStorage(Player)
	return 50 + (Player.Data.Gamepasses["MoreStorage1"].Value and 50 or 0) + (Player.Data.Gamepasses["MoreStorage2"].Value and 250 or 0)
end

function Multipliers.GetLuckMultiplier(Player)
	return 1 * (Player.Data.Gamepasses.Lucky.Value and 2 or 1)
end

return Multipliers
