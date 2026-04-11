local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local rewardEvent = ReplicatedStorage:WaitForChild("ClaimSpinReward")
local startSpinEvent = ReplicatedStorage:WaitForChild("StartSpinAnimation")

-- UI References
local mainFrame = script.Parent
local wheel = mainFrame:WaitForChild("WheelContainer"):WaitForChild("Wheel")
local spinButton = mainFrame:WaitForChild("SpinButton") 
local buy3Button = mainFrame:WaitForChild("Buy3Button") 

-- Navigation/Reward Refs
local rewardFrame = mainFrame:WaitForChild("RewardFrame")
local prizeText = rewardFrame:WaitForChild("PrizeText")
local rewardIcon = rewardFrame:WaitForChild("RewardIcon") 
local rewardClose = rewardFrame:WaitForChild("CloseButton")

-- PRODUCT CONFIG
local ID_SINGLE = 3546187801 
local ID_TRIPLE = 3546187800 

local isSpinning = false
local totalSegments = 8 
local segmentAngle = 360 / totalSegments

-- 1. BUTTON VISUALS SETUP (HOVER & CLICK)
local function setupButtonVisuals(button)
	local originalSize = button.Size
	local hoverSize = UDim2.new(originalSize.X.Scale * 1.05, originalSize.X.Offset, originalSize.Y.Scale * 1.05, originalSize.Y.Offset)
	local clickSize = UDim2.new(originalSize.X.Scale * 0.95, originalSize.X.Offset, originalSize.Y.Scale * 0.95, originalSize.Y.Offset)

	-- Hover In
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.2, Enum.EasingStyle.Quart), {Size = hoverSize}):Play()
	end)

	-- Hover Out
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.2, Enum.EasingStyle.Quart), {Size = originalSize}):Play()
	end)

	-- Click Down
	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.1, Enum.EasingStyle.Back), {Size = clickSize}):Play()
	end)

	-- Click Up
	button.MouseButton1Up:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.1, Enum.EasingStyle.Back), {Size = hoverSize}):Play()
	end)
end

-- Apply to all buttons
setupButtonVisuals(spinButton)
setupButtonVisuals(buy3Button)

setupButtonVisuals(rewardClose)

-- PRIZES
local prizes = {
	{Name = "100 Gem", Image = "rbxassetid://6995306743"},
	{Name = "200 Gem", Image = "rbxassetid://6995306743"},
	{Name = "500 Gem", Image = "rbxassetid://6995306743"},
	{Name = "1000 Gem", Image = "rbxassetid://6995306743"},
	{Name = "1000 Cash", Image = "rbxassetid://18885492705"},
	{Name = "500 Cash", Image = "rbxassetid://18885492705"},
	{Name = "200 Cash", Image = "rbxassetid://18885492705"},
	{Name = "100 Cash", Image = "rbxassetid://18885492705"}
}

local SoundSettings = {
	["Open"] = {ID = "rbxassetid://115591684874922", Volume = 0.5},   
	["Close"] = {ID = "rbxassetid://129356016246166", Volume = 0.4},  
	["SpinClick"] = {ID = "rbxassetid://88389157974523", Volume = 1}, 
	["Win"] = {ID = "rbxassetid://132919665409307", Volume = 0.6},    
}

local function playSound(name)
	local data = SoundSettings[name]
	if data then
		local sound = Instance.new("Sound")
		sound.SoundId = data.ID; sound.Volume = data.Volume
		sound.Parent = mainFrame; sound:Play()
		Debris:AddItem(sound, 2) 
	end
end

-- FUNCTION: CORE SPIN LOGIC
local function executeSpin()
	isSpinning = true
	rewardFrame.Visible = false 
	playSound("SpinClick")

	local winningIndex = math.random(1, totalSegments)
	local extraSpins = math.random(5, 8) * 360 
	local targetAngle = extraSpins + (winningIndex * segmentAngle) - (segmentAngle / 2)

	local spinTween = TweenService:Create(wheel, TweenInfo.new(5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Rotation = targetAngle})
	spinTween:Play()

	task.spawn(function()
		for i = 1, 15 do
			if not isSpinning then break end
			task.wait(0.2 + (i * 0.05))
			playSound("SpinClick")
		end
	end)

	spinTween.Completed:Wait()

	-- Impact Flash & Dim
	playSound("Win")
	local flash = Instance.new("Frame", mainFrame)
	flash.Size = UDim2.new(1, 0, 1, 0); flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255); flash.ZIndex = 30
	TweenService:Create(flash, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
	Debris:AddItem(flash, 0.3)

	-- Show Reward
	wheel.Rotation = wheel.Rotation % 360
	local wonPrize = prizes[winningIndex]
	prizeText.Text = "YOU WON: " .. wonPrize.Name
	rewardIcon.Image = wonPrize.Image
	rewardEvent:FireServer(wonPrize.Name)

	rewardFrame.Visible = true
	rewardFrame.Size = UDim2.new(0, 0, 0, 0)
	local pop = TweenService:Create(rewardFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 350, 0, 250)})
	pop:Play()
	pop.Completed:Wait()

	isSpinning = false
end

-- BUTTON CLICK PROMPTS
spinButton.MouseButton1Click:Connect(function()
	if isSpinning then return end
	MarketplaceService:PromptProductPurchase(game.Players.LocalPlayer, ID_SINGLE)
end)

buy3Button.MouseButton1Click:Connect(function()
	if isSpinning then return end
	MarketplaceService:PromptProductPurchase(game.Players.LocalPlayer, ID_TRIPLE)
end)

-- START SPIN UPON SUCCESSFUL PURCHASE
startSpinEvent.OnClientEvent:Connect(function(amount)
	for i = 1, amount do
		executeSpin()
		if amount > 1 and i < amount then task.wait(1.5) end
	end
end)


rewardClose.MouseButton1Click:Connect(function()
	playSound("Close")
	rewardFrame.Visible = false; task.wait(0.3); backScreen.Visible = false
end)
