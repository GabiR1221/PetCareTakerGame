local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gameUI = playerGui:WaitForChild("GameUI")
local notificationsFrame = gameUI:WaitForChild("Notifications")

local notificationRemote = ReplicatedStorage:FindFirstChild("GameNotificationEvent")
local localNotifyBridge = ReplicatedStorage:FindFirstChild("ClientNotificationEvent")

if not localNotifyBridge or not localNotifyBridge:IsA("BindableEvent") then
	localNotifyBridge = Instance.new("BindableEvent")
	localNotifyBridge.Name = "ClientNotificationEvent"
	localNotifyBridge.Parent = ReplicatedStorage
end

local layout = notificationsFrame:FindFirstChildOfClass("UIListLayout")
if not layout then
	layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = notificationsFrame
end

local TYPE_COLORS = {
	error = Color3.fromRGB(185, 54, 54),
	success = Color3.fromRGB(37, 140, 77),
	info = Color3.fromRGB(59, 91, 165),
}

local function createNotification(notificationType, message)
	if type(message) ~= "string" or message == "" then return end

	local card = Instance.new("TextLabel")
	card.Name = "Notification"
	card.Size = UDim2.new(1, -12, 0, 38)
	card.BackgroundColor3 = TYPE_COLORS[string.lower(tostring(notificationType))] or TYPE_COLORS.info
	card.BackgroundTransparency = 0.05
	card.BorderSizePixel = 0
	card.TextColor3 = Color3.new(1, 1, 1)
	card.TextWrapped = true
	card.TextScaled = false
	card.TextSize = 16
	card.TextXAlignment = Enum.TextXAlignment.Left
	card.Text = "  " .. message
	card.Parent = notificationsFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.7
	stroke.Parent = card

	card.TextTransparency = 1
	card.BackgroundTransparency = 1
	TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		BackgroundTransparency = 0.05,
	}):Play()

	task.delay(4, function()
		if not card or not card.Parent then return end
		local tween = TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			if card and card.Parent then
				card:Destroy()
			end
		end)
	end)
end

localNotifyBridge.Event:Connect(createNotification)
if notificationRemote and notificationRemote:IsA("RemoteEvent") then
	notificationRemote.OnClientEvent:Connect(createNotification)
end
