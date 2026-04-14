local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local startSpinEvent = ReplicatedStorage:WaitForChild("StartSpinAnimation")
local requestSpinReward = ReplicatedStorage:WaitForChild("RequestSpinReward")
local Modules = ReplicatedStorage.Modules
local Utilities = require(Modules.Utilities)

local mainFrame = script.Parent
local wheelContainer = mainFrame:WaitForChild("WheelContainer")
local wheel = wheelContainer:WaitForChild("Wheel")
local spinButton = mainFrame:WaitForChild("SpinButton")
local buy3Button = mainFrame:WaitForChild("Buy3Button")

local rewardFrame = mainFrame:WaitForChild("RewardFrame")
local prizeText = rewardFrame:WaitForChild("PrizeText")
local rewardIcon = rewardFrame:WaitForChild("RewardIcon")
local rewardClose = rewardFrame:WaitForChild("CloseButton")

local ID_SINGLE = 3574227749
local ID_TRIPLE = 3574767447

local totalSegments = 8
local segmentAngle = 360 / totalSegments
local isSpinning = false
local queuedSpinCount = 0
local mainFrameBaseSize = mainFrame.Size

local SoundSettings = {
	Open = { ID = "rbxassetid://115591684874922", Volume = 0.5 },
	Close = { ID = "rbxassetid://129356016246166", Volume = 0.4 },
	SpinClick = { ID = "rbxassetid://88389157974523", Volume = 1 },
	Win = { ID = "rbxassetid://132919665409307", Volume = 0.6 },
}

local PrizeImages = {
	["100 Gem"] = "rbxassetid://6995306743",
	["200 Gem"] = "rbxassetid://6995306743",
	["500 Gem"] = "rbxassetid://6995306743",
	["1000 Gem"] = "rbxassetid://6995306743",
	["1000 Cash"] = "rbxassetid://18885492705",
	["500 Cash"] = "rbxassetid://18885492705",
	["200 Cash"] = "rbxassetid://18885492705",
	["100 Cash"] = "rbxassetid://18885492705",
}

local function playSound(name)
	local data = SoundSettings[name]
	if not data then return end

	local sound = Instance.new("Sound")
	sound.SoundId = data.ID
	sound.Volume = data.Volume
	sound.Parent = mainFrame
	sound:Play()
	Debris:AddItem(sound, 2)
end

local function setupButtonVisuals(button)
	local originalSize = button.Size
	local hoverSize = UDim2.new(originalSize.X.Scale * 1.05, originalSize.X.Offset, originalSize.Y.Scale * 1.05, originalSize.Y.Offset)
	local clickSize = UDim2.new(originalSize.X.Scale * 0.95, originalSize.X.Offset, originalSize.Y.Scale * 0.95, originalSize.Y.Offset)

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.2, Enum.EasingStyle.Quart), { Size = hoverSize }):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.2, Enum.EasingStyle.Quart), { Size = originalSize }):Play()
	end)

	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.1, Enum.EasingStyle.Back), { Size = clickSize }):Play()
	end)

	button.MouseButton1Up:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.1, Enum.EasingStyle.Back), { Size = hoverSize }):Play()
	end)
end

local function hideMainFrame()
	local utilities = _G.Utilities or Utilities
	if utilities and utilities.ButtonHandler and utilities.ButtonHandler.OnClick then
		utilities.ButtonHandler.OnClick(mainFrame, mainFrameBaseSize)
		return
	end
	mainFrame.Visible = false
end

local function connectMainFrameClose()
	local closeContainer = mainFrame:FindFirstChild("Close")
	local closeButton = closeContainer and closeContainer:FindFirstChild("Click")
	if not (closeButton and closeButton:IsA("GuiButton")) then
		closeButton = mainFrame:FindFirstChild("CloseButton")
	end
	if closeButton and closeButton:IsA("GuiButton") then
		setupButtonVisuals(closeButton)
		closeButton.MouseButton1Click:Connect(function()
			playSound("Close")
			hideMainFrame()
		end)
	end
end

setupButtonVisuals(spinButton)
setupButtonVisuals(buy3Button)
setupButtonVisuals(rewardClose)
connectMainFrameClose()

local function showReward(prizeName)
	prizeText.Text = "YOU WON: " .. tostring(prizeName)
	rewardIcon.Image = PrizeImages[prizeName] or ""
	rewardFrame.Visible = true
	rewardFrame.Size = UDim2.new(0, 0, 0, 0)

	local pop = TweenService:Create(rewardFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 350, 0, 250) })
	pop:Play()
	pop.Completed:Wait()
end

local function executeSpin(winningIndex, prizeName)
	isSpinning = true
	rewardFrame.Visible = false
	playSound("SpinClick")

	local extraSpins = math.random(5, 8) * 360
	local targetAngle = extraSpins + (winningIndex * segmentAngle) - (segmentAngle / 2)

	local spinTween = TweenService:Create(wheel, TweenInfo.new(5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Rotation = targetAngle })
	spinTween:Play()

	task.spawn(function()
		for i = 1, 15 do
			if not isSpinning then break end
			task.wait(0.2 + (i * 0.05))
			playSound("SpinClick")
		end
	end)

	spinTween.Completed:Wait()
	wheel.Rotation = wheel.Rotation % 360

	playSound("Win")
	local flash = Instance.new("Frame")
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	flash.ZIndex = 30
	flash.Parent = mainFrame
	TweenService:Create(flash, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(flash, 0.3)

	showReward(prizeName)
	isSpinning = false
end

local function requestAndRunSingleSpin()
	local ok, result = pcall(function()
		return requestSpinReward:InvokeServer()
	end)
	if not ok or type(result) ~= "table" then
		warn("[SpinWheel] Failed to request reward from server.")
		return false
	end

	local winningIndex = tonumber(result.winningIndex)
	local prizeName = result.name
	if not winningIndex or winningIndex < 1 or winningIndex > totalSegments or type(prizeName) ~= "string" then
		warn("[SpinWheel] Invalid reward payload from server.")
		return false
	end

	executeSpin(winningIndex, prizeName)
	return true
end

local function flushQueuedSpins()
	if isSpinning then return end
	while queuedSpinCount > 0 do
		queuedSpinCount -= 1
		local success = requestAndRunSingleSpin()
		if not success then
			queuedSpinCount = 0
			break
		end
		if queuedSpinCount > 0 then
			task.wait(1.5)
		end
	end
end

spinButton.MouseButton1Click:Connect(function()
	if isSpinning then return end
	MarketplaceService:PromptProductPurchase(game.Players.LocalPlayer, ID_SINGLE)
end)

buy3Button.MouseButton1Click:Connect(function()
	if isSpinning then return end
	MarketplaceService:PromptProductPurchase(game.Players.LocalPlayer, ID_TRIPLE)
end)

startSpinEvent.OnClientEvent:Connect(function(amount)
	local spinAmount = math.max(0, math.floor(tonumber(amount) or 0))
	if spinAmount <= 0 then return end
	queuedSpinCount += spinAmount
	task.spawn(flushQueuedSpins)
end)

rewardClose.MouseButton1Click:Connect(function()
	playSound("Close")
	rewardFrame.Visible = false
end)

mainFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if mainFrame.Visible then
		playSound("Open")
	end
end)
