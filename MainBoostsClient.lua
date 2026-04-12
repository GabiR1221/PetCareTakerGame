-- MainBoostsClient (LocalScript)
-- Displays active friend boost and opens Roblox invite prompt.

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local MarketplaceService = game:GetService("MarketplaceService")

local localPlayer = Players.LocalPlayer
local invitePromptOpen = false
local premiumPromptOpen = false
local lastInvitePromptAt = 0
local lastPremiumPromptAt = 0
local PROMPT_COOLDOWN_SECONDS = 1.0

local function safeIsFriend(otherUserId)
	local ok, result = pcall(localPlayer.IsFriendsWith, localPlayer, otherUserId)
	return ok and result == true
end

local function getFriendCountInServer()
	local count = 0
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= localPlayer and safeIsFriend(otherPlayer.UserId) then
			count += 1
		end
	end
	return count
end

local function resolveFriendBoostFrame()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gameUi = playerGui:WaitForChild("GameUI")
	return gameUi:WaitForChild("FriendBoost")
end

local function resolvePremiumBoostFrame()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gameUi = playerGui:WaitForChild("GameUI")
	return gameUi:FindFirstChild("PremiumBoost")
end

local friendBoostFrame = resolveFriendBoostFrame()
local boostLabel = friendBoostFrame:FindFirstChildWhichIsA("TextLabel", true)
local inviteButton = friendBoostFrame:FindFirstChildWhichIsA("TextButton", true)

if not boostLabel then
	warn("[FriendBoostClient] No TextLabel found inside GameUI.FriendBoost")
	return
end

if not inviteButton then
	warn("[FriendBoostClient] No TextButton found inside GameUI.FriendBoost")
	return
end

local function updateLabel()
	local friendCount = getFriendCountInServer()
	local percent = friendCount * 10
	boostLabel.Text = ("Friend Boost: +%d%%"):format(percent)
end

local premiumBoostFrame = resolvePremiumBoostFrame()
local premiumLabel = premiumBoostFrame and premiumBoostFrame:FindFirstChildWhichIsA("TextLabel", true)
local premiumButton = premiumBoostFrame and premiumBoostFrame:FindFirstChildWhichIsA("TextButton", true)

if premiumBoostFrame and not premiumLabel then
	warn("[FriendBoostClient] No TextLabel found inside GameUI.PremiumBoost")
end

if premiumBoostFrame and not premiumButton then
	warn("[FriendBoostClient] No TextButton found inside GameUI.PremiumBoost")
end

local function canOpenInvitePrompt()
	local now = os.clock()
	if invitePromptOpen or (now - lastInvitePromptAt) < PROMPT_COOLDOWN_SECONDS then
		return false
	end
	lastInvitePromptAt = now
	return true
end

local function promptInviteUi()
	if not canOpenInvitePrompt() then
		return
	end
	invitePromptOpen = true

	local okPrompt, err = pcall(SocialService.PromptGameInvite, SocialService, localPlayer)
	if not okPrompt then
		invitePromptOpen = false
		warn("[FriendBoostClient] Failed to open invite prompt:", err)
	end
end

local function updatePremiumLabel()
	if not premiumLabel then return end

	local isPremium = localPlayer.MembershipType == Enum.MembershipType.Premium
	if isPremium then
		premiumLabel.Text = "Premium Boost: +40% (Owned)"
	else
		premiumLabel.Text = "Premium Boost: +40%"
	end
end

inviteButton.MouseButton1Click:Connect(function()
	promptInviteUi()
end)

local function promptPremiumUi()
	local now = os.clock()
	if premiumPromptOpen or (now - lastPremiumPromptAt) < PROMPT_COOLDOWN_SECONDS then
		return
	end
	lastPremiumPromptAt = now
	premiumPromptOpen = true

	local okPrompt, err = pcall(MarketplaceService.PromptPremiumPurchase, MarketplaceService, localPlayer)
	if not okPrompt then
		premiumPromptOpen = false
		warn("[FriendBoostClient] Failed to open premium purchase prompt:", err)
	end
end

if premiumButton then
	premiumButton.MouseButton1Click:Connect(function()
		promptPremiumUi()
	end)
end

SocialService.GameInvitePromptClosed:Connect(function()
	invitePromptOpen = false
end)

MarketplaceService.PromptPremiumPurchaseFinished:Connect(function(_, purchaseCompleted)
	premiumPromptOpen = false
	if purchaseCompleted then
		task.defer(updatePremiumLabel)
	end
end)


Players.PlayerAdded:Connect(function()
	task.defer(updateLabel)
end)

Players.PlayerRemoving:Connect(function()
	task.defer(updateLabel)
end)

updateLabel()
updatePremiumLabel()

task.spawn(function()
	while friendBoostFrame.Parent do
		task.wait(15)
		updateLabel()
		updatePremiumLabel()
	end
end)
