--!strict
-- Client binder for Playtime UI.
-- Expected hierarchy:
-- Playtime(Frame)
--   RewardsHolder(Frame)
--     1(Frame)
--     2(Frame)
--     ...
--       RewardButton(TextButton/TextLabel-backed button)
--       RewardText(TextLabel)
--       RewardImage(ImageLabel/ImageButton)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PlaytimeRewardsConfig = require(modulesFolder:WaitForChild("PlaytimeRewardsConfig"))

local playtimeFrame = script.Parent
local rewardsHolder = playtimeFrame:WaitForChild("RewardsHolder") :: GuiObject

local getStateRemote = ReplicatedStorage:WaitForChild(PlaytimeRewardsConfig.GetStateRemoteName) :: RemoteFunction
local claimRemote = ReplicatedStorage:WaitForChild(PlaytimeRewardsConfig.ClaimRemoteName) :: RemoteFunction

type PlaytimeStateItem = {
	Id: number,
	Type: string,
	RequiredPlaytimeSeconds: number,
	RemainingSeconds: number,
	RewardText: string,
	RewardImage: string,
	Claimed: boolean,
	CanClaim: boolean,
}

type StateResponse = {
	Rewards: {PlaytimeStateItem},
	ElapsedPlaytimeSeconds: number,
}

type ClaimResponse = {
	Success: boolean,
	Error: string?,
	RewardId: number?,
	NewState: StateResponse?,
}

local claimLocks: {[number]: boolean} = {}
local activeStateById: {[number]: PlaytimeStateItem} = {}
local applyState: (state: StateResponse) -> ()

local function formatSeconds(totalSeconds: number): string
	local safe = math.max(0, math.floor(totalSeconds))
	local minutes = math.floor(safe / 60)
	local seconds = safe % 60
	return string.format("%02d:%02d", minutes, seconds)
end

local function getRewardFrameById(id: number): Frame?
	local frame = rewardsHolder:FindFirstChild(tostring(id))
	if frame and frame:IsA("Frame") then
		return frame
	end
	return nil
end

local function setButtonVisual(button: TextButton, stateItem: PlaytimeStateItem)
	if stateItem.Claimed then
		button.Text = "Claimed ✓"
		button.Active = false
		button.AutoButtonColor = false
	elseif stateItem.CanClaim then
		button.Text = "Claim"
		button.Active = true
		button.AutoButtonColor = true
	else
		button.Text = string.format("Locked (%s)", formatSeconds(stateItem.RemainingSeconds))
		button.Active = false
		button.AutoButtonColor = false
	end
end

local function bindClaimButtonIfNeeded(button: TextButton)
	if button:GetAttribute("PlaytimeBound") == true then
		return
	end
	button:SetAttribute("PlaytimeBound", true)

	button.MouseButton1Click:Connect(function()
		local rewardId = math.floor(tonumber(button:GetAttribute("PlaytimeRewardId")) or 0)
		if rewardId <= 0 then return end
		if claimLocks[rewardId] then return end
		local stateItem = activeStateById[rewardId]
		if not stateItem or not stateItem.CanClaim or stateItem.Claimed then return end

		claimLocks[rewardId] = true
		local ok, result = pcall(function()
			return claimRemote:InvokeServer(rewardId)
		end)
		claimLocks[rewardId] = nil

		if not ok then
			warn("[PlaytimeRewards] Claim request failed:", tostring(result))
			return
		end

		local response = result :: ClaimResponse
		if response.Success and response.NewState then
			-- Apply latest authoritative state from server.
			applyState(response.NewState)
		else
			warn("[PlaytimeRewards] Claim rejected:", tostring(response.Error))
		end
	end)
end

function applyState(state: StateResponse)
	activeStateById = {}
	for _, item in ipairs(state.Rewards) do
		activeStateById[item.Id] = item

		local rewardFrame = getRewardFrameById(item.Id)
		if not rewardFrame then
			continue
		end

		local rewardText = rewardFrame:FindFirstChild("RewardText")
		if rewardText and rewardText:IsA("TextLabel") then
			rewardText.Text = item.RewardText
		end

		local rewardImage = rewardFrame:FindFirstChild("RewardImage")
		if rewardImage and rewardImage:IsA("ImageLabel") then
			rewardImage.Image = item.RewardImage
		elseif rewardImage and rewardImage:IsA("ImageButton") then
			rewardImage.Image = item.RewardImage
		end

		local rewardButton = rewardFrame:FindFirstChild("RewardButton")
		if rewardButton and rewardButton:IsA("TextButton") then
			rewardButton:SetAttribute("PlaytimeRewardId", item.Id)
			setButtonVisual(rewardButton, item)
			bindClaimButtonIfNeeded(rewardButton)
		end
	end
end

local function fetchAndApplyState()
	local ok, result = pcall(function()
		return getStateRemote:InvokeServer()
	end)
	if not ok then
		warn("[PlaytimeRewards] Failed to fetch state:", tostring(result))
		return
	end
	applyState(result :: StateResponse)
end

fetchAndApplyState()

while playtimeFrame.Parent do
	task.wait(1)
	fetchAndApplyState()
end
