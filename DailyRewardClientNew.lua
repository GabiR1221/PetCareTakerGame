local player = game.Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local event = ReplicatedStorage:WaitForChild("DailyRewardEvent")

local main = script.Parent


local rewardsFrame = main.RewardsFrame
local day7Frame = main:WaitForChild("Day7")

local defaultSize = main.Size

------------------------------------------------
-- REWARD DATA

local rewards = {100,500,1000,2000,3000,5000,10000}
local COOLDOWN = 86400

local currentDay = 1
local lastClaimTime = 0
local notifiedReady = false

main.Visible = false

------------------------------------------------
-- TIME FORMAT

local function formatTime(seconds)

	local h = math.floor(seconds/3600)
	local m = math.floor((seconds%3600)/60)
	local s = seconds%60

	return string.format("%02d:%02d:%02d",h,m,s)

end

------------------------------------------------
-- FLOATING COIN POPUP

local function showCoins(amount)

	local label = Instance.new("TextLabel")

	label.Text = "+"..amount.." Coins"
	label.Size = UDim2.new(0,200,0,50)
	label.Position = UDim2.new(.5,-100,.5,0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255,221,0)
	label.Font = Enum.Font.GothamBold

	label.Parent = main

	local tween = TweenService:Create(
		label,
		TweenInfo.new(1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
		{
			Position = label.Position - UDim2.new(0,0,0,100),
			TextTransparency = 1
		}
	)

	tween:Play()

	tween.Completed:Connect(function()
		label:Destroy()
	end)

end

------------------------------------------------
-- DAY7 RAINBOW LEGENDARY

local rainbowStroke = Instance.new("UIStroke")
rainbowStroke.Thickness = 3
rainbowStroke.Parent = day7Frame

task.spawn(function()

	local hue = 0

	while true do

		rainbowStroke.Color = Color3.fromHSV(hue,1,1)

		hue += 0.01
		if hue > 1 then
			hue = 0
		end

		task.wait(0.05)

	end

end)

------------------------------------------------
-- GET DAY FRAMES

local function getAllDays()

	local days = {}

	for _,v in pairs(rewardsFrame:GetChildren()) do
		if v:IsA("Frame") then
			table.insert(days,v)
		end
	end

	table.insert(days,day7Frame)

	return days

end

------------------------------------------------
-- SAFE DAY NUMBER

local function getDayNumber(frame)

	local number = frame.Name:match("%d+")

	if number then
		return tonumber(number)
	end

	return nil

end

------------------------------------------------
-- GLOW EFFECT

local glow = {}

local function addGlow(frame)

	if glow[frame] then return end

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255,221,87)
	stroke.Thickness = 2
	stroke.Parent = frame

	local tween = TweenService:Create(
		stroke,
		TweenInfo.new(.8,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),
		{Thickness = 5}
	)

	tween:Play()

	glow[frame] = {stroke,tween}

end

local function removeGlow(frame)

	if glow[frame] then
		glow[frame][2]:Cancel()
		glow[frame][1]:Destroy()
		glow[frame] = nil
	end

end

-- UPDATE UI

local function updateUI()

	for _,frame in pairs(getAllDays()) do

		local day = getDayNumber(frame)
		if not day then continue end

		local button = frame:FindFirstChild("StatusButton")
		if not button then continue end

		if day == currentDay then

			local remaining = COOLDOWN - (os.time() - lastClaimTime)

			if remaining <= 0 then

				button.Text = "CLAIM"
				button.BackgroundColor3 = Color3.fromRGB(0,255,120)

				addGlow(frame)

				if not notifiedReady then
					notifiedReady = true
					main.Visible = true
				end

			else

				button.Text = formatTime(remaining)
				button.BackgroundColor3 = Color3.fromRGB(255,170,0)

				removeGlow(frame)

				notifiedReady = false

			end

		elseif day < currentDay then

			button.Text = "CLAIMED"
			button.BackgroundColor3 = Color3.fromRGB(120,120,120)

			removeGlow(frame)

		else

			button.Text = "LOCKED"
			button.BackgroundColor3 = Color3.fromRGB(70,70,70)

			removeGlow(frame)

		end

	end

end

------------------------------------------------
-- CLAIM BUTTONS

for _,frame in pairs(getAllDays()) do

	local day = getDayNumber(frame)
	local button = frame:FindFirstChild("StatusButton")

	if button and day then

		button.MouseButton1Click:Connect(function()

			if day ~= currentDay then return end

			local remaining = COOLDOWN - (os.time() - lastClaimTime)

			if remaining <= 0 then

				event:FireServer()
				showCoins(rewards[day])

			end

		end)

	end

end

------------------------------------------------
-- SERVER UPDATE

event.OnClientEvent:Connect(function(day,lastClaim)

	currentDay = day
	lastClaimTime = lastClaim

	updateUI()

end)


task.spawn(function()
	while task.wait(1) do
		updateUI()
	end
end)
