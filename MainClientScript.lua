--[[
	This script handles the client. 
	
	Contents:
	- ClickButton
	- Overlay (Currency counter)
	- Popups
	- Close Buttons of Frames
	- Buttons on the side
	- Settings
	- Rebirth
	- Shop
	- Pet Inventory
	- Egg Preview (Frame that shows the price etc)
	- Egg Hatching
	- Pet Follow
	- Areas
	- Trading
	- Gem Shop
	- Codes
	- Stats
	- Functions
	
	Only edit if you know what you're doing!
]]

--// Services
local MarketPlaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

--// Loading
local Player = Players.LocalPlayer
repeat wait() until Player:FindFirstChild("Loaded") and Player.Loaded.Value or Player.Parent == nil

if Player.Parent == nil then return end

--// Variables
local Data = Player.Data
local PlayerData = Data.PlayerData

local GameSettings = ReplicatedStorage["Game Settings"]
local Modules = ReplicatedStorage.Modules

local PetMultipliers = require(Modules.PetMultipliers)
local Multipliers = require(Modules.Multipliers)
local Utilities = require(Modules.Utilities)

local UI = Player.PlayerGui:WaitForChild("GameUI")
local Frames = UI.Frames

local Remotes = ReplicatedStorage.Remotes

--// Clicker
if GameSettings.GameType.Value == "Clicker" then
	Utilities.ButtonAnimations.Create(UI.Clicker)

	UI.Clicker.Click.MouseButton1Click:Connect(function()
		Remotes.Clicker:FireServer()
		Utilities.Audio.PlayAudio("Click")
	end, function(itemFolder, template)
		local info = template and template:GetAttribute("Info")
		if type(info) ~= "string" or info == "" then info = itemFolder and itemFolder:GetAttribute("Info") end
		return (type(info) == "string" and info ~= "") and info or "Info unavailable"
	end)

	if GameSettings.ClickingAnywhere.Value then
		UserInputService.InputBegan:Connect(function(Input, Processed)
			if Processed then return end
			if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end -- not a left mouse click
			Remotes.Clicker:FireServer()
			Utilities.Audio.PlayAudio("Click")
		end)
	end
end

--// Overlay
local CurrencySide = UI[GameSettings.CurrencySide.Value]
CurrencySide.CurrencyLabel.Amount.Text = Utilities.Short.en(PlayerData.Currency.Value)
PlayerData.Currency.Changed:Connect(function()
	CurrencySide.CurrencyLabel.Amount.Text = Utilities.Short.en(PlayerData.Currency.Value)
end)

CurrencySide.CurrencyLabel2.Amount.Text = Utilities.Short.en(PlayerData.Currency2.Value)
PlayerData.Currency2.Changed:Connect(function()
	CurrencySide.CurrencyLabel2.Amount.Text = Utilities.Short.en(PlayerData.Currency2.Value)
end)


--// Popups
local CurrencyOld = PlayerData.Currency.Value
PlayerData.Currency.Changed:Connect(function(NewValue)
	task.spawn(function()
		if NewValue > CurrencyOld then
			local NewPopup = script.Popup:Clone()
			NewPopup.Size = UDim2.new(0,0,0,0)
			NewPopup.Currency.Image = CurrencySide.CurrencyLabel.Currency.Image
			NewPopup.Amount.Text = "+"..Utilities.Short.en(NewValue - CurrencyOld)
			NewPopup.Position = UDim2.new(math.random(40, 60) / 100, 0, math.random(40, 60) / 100, 0) -- sets it in a random position in the middle square
			NewPopup.Parent = UI.Popups
			NewPopup:TweenSize(UDim2.new(0.176,0,0.105,0), Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.5)
			task.wait(1)
			NewPopup:TweenPosition(CurrencySide.Position, Enum.EasingDirection.InOut, Enum.EasingStyle.Quad, 2)
			NewPopup:TweenSize(UDim2.new(0.1,0,0.05,0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 2)
			task.wait(1.4)
			NewPopup:Destroy()
		end
	end)

	CurrencyOld = NewValue
end)

--// Frames
local BaseSize = {}
for _,Frame in Frames:GetChildren() do
	if not Frame:IsA("Frame") then continue end

	BaseSize[Frame.Name] = Frame.Size

	if Frame:FindFirstChild("Close") then
		Utilities.ButtonAnimations.Create(Frame.Close)
		Frame.Close.Click.MouseButton1Click:Connect(function()
			Utilities.ButtonHandler.OnClick(Frame, UDim2.new(0,0,0,0))
			Utilities.Audio.PlayAudio("Click")
		end)
	end
end

--// Buttons
local ButtonSide = UI[GameSettings.ButtonSide.Value]
for _,Button in ButtonSide.Buttons:GetChildren() do
	if not Button:IsA("Frame") then continue end
	Utilities.ButtonAnimations.Create(Button)
	Button.Click.MouseButton1Click:Connect(function()
		Utilities.ButtonHandler.OnClick(UI.Frames[Button.Name], BaseSize[Button.Name])
		Utilities.Audio.PlayAudio("Click")
	end)
end

--// Settings
local SettingsScroll = Frames.Settings.ObjectHolder

-- Music Setting
local MusicSetting = SettingsScroll.Music
Utilities.ButtonAnimations.Create(MusicSetting.Toggle.On)
Utilities.ButtonAnimations.Create(MusicSetting.Toggle.Off)

MusicSetting.Toggle.On.Click.MouseButton1Click:Connect(function()
	ReplicatedStorage.Remotes.Setting:FireServer("Music", true)
	Utilities.Audio.PlayAudio("Click")
end)

MusicSetting.Toggle.Off.Click.MouseButton1Click:Connect(function()
	ReplicatedStorage.Remotes.Setting:FireServer("Music", false)
	Utilities.Audio.PlayAudio("Click")
end)

SoundService.Music.PlaybackSpeed = PlayerData.Music.Value and 1 or 0
PlayerData.Music.Changed:Connect(function()
	SoundService.Music.PlaybackSpeed = PlayerData.Music.Value and 1 or 0
end)

-- ShowOtherPets
local ShowOtherPetsSetting = SettingsScroll.ShowOtherPets
Utilities.ButtonAnimations.Create(ShowOtherPetsSetting.Toggle.On)
Utilities.ButtonAnimations.Create(ShowOtherPetsSetting.Toggle.Off)

ShowOtherPetsSetting.Toggle.On.Click.MouseButton1Click:Connect(function()
	ReplicatedStorage.Remotes.Setting:FireServer("ShowOtherPets", true)
	Utilities.Audio.PlayAudio("Click")
end)

ShowOtherPetsSetting.Toggle.Off.Click.MouseButton1Click:Connect(function()
	ReplicatedStorage.Remotes.Setting:FireServer("ShowOtherPets", false)
	Utilities.Audio.PlayAudio("Click")
end)

--// Rebirth
local RebirthPrice, RebirthMulti = GameSettings.RebirthBasePrice.Value, GameSettings.RebirthMultiplier.Value
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TycoonRebirthEvent = ReplicatedStorage:WaitForChild("TycoonRebirthEvent")
local GetTycoonRebirthRequirements = ReplicatedStorage:WaitForChild("TycoonGetRebirthRequirementsFunction")

local LocalNotifyBridge = ReplicatedStorage:FindFirstChild("ClientNotificationEvent")
if not LocalNotifyBridge or not LocalNotifyBridge:IsA("BindableEvent") then
	LocalNotifyBridge = Instance.new("BindableEvent")
	LocalNotifyBridge.Name = "ClientNotificationEvent"
	LocalNotifyBridge.Parent = ReplicatedStorage
end

local function notifyLocal(notificationType, message)
	if LocalNotifyBridge and LocalNotifyBridge:IsA("BindableEvent") then
		LocalNotifyBridge:Fire(notificationType, message)
	end
end

local RebirthCanBuy = true
local RebirthRequirementsHolder = nil
local RebirthPetSlots = {}

local LOCKED_BUTTON_COLOR = Color3.fromRGB(115, 115, 115)
local UNLOCKED_BUTTON_COLOR = Color3.fromRGB(44, 202, 100)

local function clearRequirementSlot(slot)
	if not slot then return end
	local viewport = slot:FindFirstChild("Display")
	if viewport and viewport:IsA("ViewportFrame") then
		for _, child in ipairs(viewport:GetChildren()) do
			child:Destroy()
		end
	end
end

local function ensureRequirementsHolder()
	if RebirthRequirementsHolder and RebirthRequirementsHolder.Parent then
		return RebirthRequirementsHolder
	end

	local existing = Frames.Rebirth:FindFirstChild("PetRequirementsHolder")
	if existing and existing:IsA("Frame") then
		RebirthRequirementsHolder = existing
	else
		local holder = Instance.new("Frame")
		holder.Name = "PetRequirementsHolder"
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(1, -20, 0, 105)
		holder.Position = UDim2.new(0, 10, 0, 112)
		holder.ClipsDescendants = true
		holder.Parent = Frames.Rebirth
		RebirthRequirementsHolder = holder
	end

	local layout = RebirthRequirementsHolder:FindFirstChild("RequirementsLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.Name = "RequirementsLayout"
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = RebirthRequirementsHolder
	end

	return RebirthRequirementsHolder
end

local function ensurePetRequirementSlot(slotId)
	local holder = ensureRequirementsHolder()
	local key = tostring(slotId)
	local slot = RebirthPetSlots[key]
	if slot and slot.Parent == holder then
		return slot
	end

	local frame = Instance.new("Frame")
	frame.Name = key
	frame.Size = UDim2.new(0, 76, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
	frame.BorderSizePixel = 0
	frame.Parent = holder

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(62, 62, 62)
	stroke.Parent = frame

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Display"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.new(1, -8, 0, 58)
	viewport.Position = UDim2.new(0, 4, 0, 4)
	viewport.Parent = frame

	local check = Instance.new("TextLabel")
	check.Name = "Check"
	check.BackgroundTransparency = 1
	check.Size = UDim2.new(0, 18, 0, 18)
	check.Position = UDim2.new(1, -21, 0, 2)
	check.Font = Enum.Font.GothamBold
	check.TextScaled = true
	check.Text = "✓"
	check.TextColor3 = Color3.fromRGB(85, 255, 127)
	check.Visible = false
	check.Parent = frame

	local petName = Instance.new("TextLabel")
	petName.Name = "PetName"
	petName.BackgroundTransparency = 1
	petName.Size = UDim2.new(1, -8, 0, 35)
	petName.Position = UDim2.new(0, 4, 1, -35)
	petName.TextColor3 = Color3.fromRGB(255, 255, 255)
	petName.TextSize = 12
	petName.TextWrapped = true
	petName.TextYAlignment = Enum.TextYAlignment.Top
	petName.TextXAlignment = Enum.TextXAlignment.Center
	petName.Parent = frame

	RebirthPetSlots[key] = frame
	return frame
end

local function renderPetInSlot(slot, petName, isOwned)
	if not slot then return end
	clearRequirementSlot(slot)

	local display = slot:FindFirstChild("Display")
	local check = slot:FindFirstChild("Check")
	local label = slot:FindFirstChild("PetName")
	if label then
		label.Text = tostring(petName)
	end
	if check then
		check.Visible = isOwned and true or false
	end
	slot.BackgroundColor3 = isOwned and Color3.fromRGB(30, 62, 34) or Color3.fromRGB(38, 38, 38)

	if not (display and display:IsA("ViewportFrame")) then return end

	local template = ReplicatedStorage:FindFirstChild("Pets") and ReplicatedStorage.Pets:FindFirstChild(tostring(petName))
	if not template then return end

	local model = template:Clone()
	model.Parent = display
	local mainPart = model:FindFirstChild("MainPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not mainPart then
		model:Destroy()
		return
	end

	model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(180), 0))
	local cam = Instance.new("Camera")
	cam.Parent = display
	display.CurrentCamera = cam
	local pos = mainPart.Position
	cam.CFrame = CFrame.new(Vector3.new(pos.X + model:GetExtentsSize().X * 1.5, pos.Y, pos.Z + 1), pos)
end

local function updateBuyButtonState(isUnlocked)
	RebirthCanBuy = isUnlocked and true or false
	local clickButton = Frames.Rebirth.Buy.Click
	clickButton.Active = RebirthCanBuy
	clickButton.AutoButtonColor = RebirthCanBuy
	Frames.Rebirth.Buy.BackgroundColor3 = RebirthCanBuy and UNLOCKED_BUTTON_COLOR or LOCKED_BUTTON_COLOR
	if Frames.Rebirth.Buy:FindFirstChild("Title") then
		Frames.Rebirth.Buy.Title.Text = RebirthCanBuy and "Rebirth" or "Locked"
	end
end

local function FormatCurrencyRequirements(requiredCurrency)
	local formatted = {}
	for currencyName, amount in pairs(requiredCurrency or {}) do
		local cleanName = tostring(currencyName)
		table.insert(formatted, Utilities.Short.en(tonumber(amount) or 0).." "..cleanName)
	end
	table.sort(formatted)
	return table.concat(formatted, ", ")
end

local function UpdatePetRequirementsUi(requiredPets, requiredPetStatus)
	local holder = ensureRequirementsHolder()
	local activeSlots = {}

	if type(requiredPets) ~= "table" or #requiredPets == 0 then
		holder.Visible = false
		for _, slot in pairs(RebirthPetSlots) do
			clearRequirementSlot(slot)
			slot.Visible = false
		end
		return
	end

	holder.Visible = true
	for order, petName in ipairs(requiredPets) do
		local slot = ensurePetRequirementSlot(order)
		local owned = type(requiredPetStatus) == "table" and requiredPetStatus[tostring(petName)] == true
		slot.LayoutOrder = order
		slot.Visible = true
		renderPetInSlot(slot, petName, owned)
		activeSlots[tostring(order)] = true
	end

	for key, slot in pairs(RebirthPetSlots) do
		if not activeSlots[key] then
			clearRequirementSlot(slot)
			slot.Visible = false
		end
	end
	return table.concat(requiredPets, ", ")
end

function UpdateRebirthInfo()
	Frames.Rebirth.Counter.Text = "You have "..Utilities.Short.en(PlayerData.Rebirth.Value).." Rebirths"
	local success, requirements = pcall(function()
		return GetTycoonRebirthRequirements:InvokeServer()
	end)

	if success and type(requirements) == "table" then
		local limit = tonumber(requirements.RebirthLimit) or 0
		local current = tonumber(requirements.RebirthCount) or 0
		local nextTier = tonumber(requirements.NextTier) or (current + 1)
		local completion = tonumber(requirements.CompletionPercentage) or 100
		local currentCompletion = tonumber(requirements.CurrentCompletionPercentage) or 0
		local requiredCurrencyText = FormatCurrencyRequirements(requirements.RequiredCurrency)
		local requiredPetsCount = type(requirements.RequiredPets) == "table" and #requirements.RequiredPets or 0
		local hasRequiredPets = requirements.HasRequiredPets == true
		local hasRequiredCurrency = requirements.HasRequiredCurrency == true
		local completionMet = currentCompletion >= completion
		local canRebirthNow = requirements.IsEligible == true
		if limit > 0 and current >= limit then
			canRebirthNow = false
		end

		UpdatePetRequirementsUi(requirements.RequiredPets, requirements.RequiredPetStatus)

		if limit > 0 and current >= limit then
			Frames.Rebirth.Description.Text = "Tycoon rebirth limit reached ("..current.."/"..limit..")"
			Frames.Rebirth.Cost.Text = "No more rebirths available"
			updateBuyButtonState(false)
		else
			local petStatusText = requiredPetsCount > 0 and (hasRequiredPets and "pets ✅" or "pets ❌") or "pets: none"
			local currencyStatusText = hasRequiredCurrency and "currency ✅" or "currency ❌"
			Frames.Rebirth.Description.Text = "Tycoon Rebirth "..nextTier.." | Progress "..math.floor(currentCompletion).."% / "..math.floor(completion).."% | "..petStatusText.." | "..currencyStatusText
			Frames.Rebirth.Cost.Text = "Required Currency: "..(requiredCurrencyText ~= "" and requiredCurrencyText or "None")
			updateBuyButtonState(canRebirthNow and completionMet and hasRequiredCurrency and hasRequiredPets)
		end
		return
	end

	updateBuyButtonState(true)
	if GameSettings.RebirthType.Value == "Linear" then
		Frames.Rebirth.Description.Text = "Buying a Rebirth will increase your "..GameSettings.CurrencyName.Value.." Multiplier with x"..RebirthMulti
		Frames.Rebirth.Cost.Text = "You need atleast "..Utilities.Short.en(RebirthPrice * (PlayerData.Rebirth.Value + 1)).." "..GameSettings.CurrencyName.Value
	elseif GameSettings.RebirthType.Value == "Exponential" then
		Frames.Rebirth.Description.Text = "Buying a Rebirth will increase your "..GameSettings.CurrencyName.Value.." Multiplier with ^"..(RebirthMulti+0.5)
		Frames.Rebirth.Cost.Text = "You need atleast "..Utilities.Short.en(RebirthPrice * ((RebirthMulti+1.25) ^ PlayerData.Rebirth.Value)).." "..GameSettings.CurrencyName.Value
	end
end

UpdateRebirthInfo()

PlayerData.Rebirth.Changed:Connect(function()
	UpdateRebirthInfo()
end)

Utilities.ButtonAnimations.Create(Frames.Rebirth.Buy)

Frames.Rebirth.Buy.Click.MouseButton1Click:Connect(function()
	if not RebirthCanBuy then
		notifyLocal("error", "❌ You can't rebirth yet. Complete the listed requirements first.")
		Utilities.Audio.PlayAudio("Click")
		return
	end
	Remotes.Rebirth:FireServer()
	if TycoonRebirthEvent then
		TycoonRebirthEvent:FireServer()
	end
	notifyLocal("info", "⏳ Rebirth request sent...")
	Utilities.Audio.PlayAudio("Click")
end)

task.spawn(function()
	while true do
		task.wait(2)
		if Frames and Frames.Rebirth and Frames.Rebirth.Visible then
			UpdateRebirthInfo()
		end
	end
end)

--// Shop
local canPromptPetPurchase = ReplicatedStorage:WaitForChild("CanPromptPetPurchase")
local localNotifyBridge = ReplicatedStorage:FindFirstChild("ClientNotificationEvent")
if not localNotifyBridge or not localNotifyBridge:IsA("BindableEvent") then
	localNotifyBridge = Instance.new("BindableEvent")
	localNotifyBridge.Name = "ClientNotificationEvent"
	localNotifyBridge.Parent = ReplicatedStorage
end

local function notifyPlayer(notificationType, message)
	if localNotifyBridge and localNotifyBridge:IsA("BindableEvent") then
		localNotifyBridge:Fire(notificationType, message)
	end
end

local function parseColorAttribute(value)
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) ~= "string" then
		return nil
	end

	local r, g, b = string.match(value, "^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
	if not r then return nil end
	r, g, b = tonumber(r), tonumber(g), tonumber(b)
	if not r or not g or not b then return nil end

	return Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255))
end

local function getGamepassTemplate(entry)
	local templateName = entry:GetAttribute("TemplateName")
	if type(templateName) == "string" and templateName ~= "" then
		local customTemplate = script:FindFirstChild(templateName)
		if customTemplate and customTemplate:IsA("Frame") then
			return customTemplate
		end
	end
	return script.GamepassTemplate
end

local function getGamepassContainer()
	local shop = Frames and Frames:FindFirstChild("Shop")
	if not shop then return nil end

	local holder = shop:FindFirstChild("GamepassesHolder")
	if holder then
		local nestedGamepasses = holder:FindFirstChild("Gamepasses")
		if nestedGamepasses then
			return nestedGamepasses
		end
	end

	return shop:FindFirstChild("Gamepasses")
end

local function getExistingShopCard(entry)
	local container = getGamepassContainer()
	if not container then return nil end

	local explicitCardName = entry:GetAttribute("ShopCardName")
	if type(explicitCardName) == "string" and explicitCardName ~= "" then
		local explicitCard = container:FindFirstChild(explicitCardName)
		if explicitCard and explicitCard:IsA("Frame") then
			return explicitCard
		end
	end

	local cardByEntryName = container:FindFirstChild(entry.Name)
	if cardByEntryName and cardByEntryName:IsA("Frame") then
		return cardByEntryName
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("Frame") and descendant.Name == entry.Name then
			return descendant
		end
	end

	return nil
end

local function applyVisualOverrides(card, entry)
	if not card or not entry then return end
	local inner = card:FindFirstChild("InnerPart")
	if not inner then return end

	local cardColor = parseColorAttribute(entry:GetAttribute("CardColor"))
	if cardColor and inner:IsA("GuiObject") then
		inner.BackgroundColor3 = cardColor
	end

	local titleColor = parseColorAttribute(entry:GetAttribute("TitleColor"))
	if titleColor and inner:FindFirstChild("GPName") then
		inner.GPName.TextColor3 = titleColor
	end

	local descriptionColor = parseColorAttribute(entry:GetAttribute("DescriptionColor"))
	if descriptionColor and inner:FindFirstChild("Description") then
		inner.Description.TextColor3 = descriptionColor
	end

	local priceColor = parseColorAttribute(entry:GetAttribute("PriceColor"))
	if priceColor and inner:FindFirstChild("Price") then
		inner.Price.TextColor3 = priceColor
	end

	local strokeColor = parseColorAttribute(entry:GetAttribute("StrokeColor"))
	local stroke = inner:FindFirstChildOfClass("UIStroke")
	if stroke and strokeColor then
		stroke.Color = strokeColor
	end

	local customImageAssetId = tonumber(entry:GetAttribute("ImageAssetId"))
	if customImageAssetId and inner:FindFirstChild("ImageLabel") then
		inner.ImageLabel.Image = "rbxassetid://"..customImageAssetId
	end
end

local function isValidShopCard(card)
	if not card then return false end
	local inner = card:FindFirstChild("InnerPart")
	local button = inner and inner:FindFirstChild("Button")
	local hasPrice = inner and inner:FindFirstChild("Price")
	return inner and button and hasPrice
end

local function isSectionNavigableShopCard(card)
	if not card then return false end
	local inner = card:FindFirstChild("InnerPart")
	local button = inner and inner:FindFirstChild("Button")
	return inner and button
end

local function trimText(value)
	local asString = tostring(value or "")
	return string.match(asString, "^%s*(.-)%s*$") or ""
end

local function normalizeSectionName(value)
	local sectionName = trimText(value)
	if sectionName == "" then
		sectionName = "Gamepasses"
	end
	return sectionName
end

local function sectionToKey(value)
	local normalized = string.lower(normalizeSectionName(value))
	normalized = string.gsub(normalized, "%s+", "")
	return normalized
end

local function getShopSectionsButtonMap(shopFrame)
	local result = {}
	local buttonsFrame = shopFrame and shopFrame:FindFirstChild("Buttons")
	if not buttonsFrame then
		return result
	end

	for _, button in ipairs(buttonsFrame:GetChildren()) do
		if button:IsA("GuiButton") then
			local sectionName = button.Name:gsub("Button$", "")
			local sectionKey = sectionToKey(sectionName)
			result[sectionKey] = button
			if sectionKey == "codesbutton" then
				result["codes"] = button
			end
		end
	end

	return result
end

local function scrollShopToSection(container, targetFrame)
	if not (container and container:IsA("ScrollingFrame")) then
		return
	end
	if not (targetFrame and targetFrame:IsA("GuiObject")) then
		return
	end

	local targetY = targetFrame.AbsolutePosition.Y - container.AbsolutePosition.Y + container.CanvasPosition.Y
	local maxY = math.max(0, container.AbsoluteCanvasSize.Y - container.AbsoluteWindowSize.Y)
	targetY = math.clamp(targetY, 0, maxY)
	TweenService:Create(container, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CanvasPosition = Vector2.new(container.CanvasPosition.X, targetY)
	}):Play()
end

local function getProductInfoWithType(productId)
	local info
	local success, err = pcall(function()
		info = MarketPlaceService:GetProductInfo(productId, Enum.InfoType.GamePass)
	end)

	if success and info then
		return info, "GamePass"
	end

	local fallbackInfo
	local fallbackSuccess, fallbackErr = pcall(function()
		fallbackInfo = MarketPlaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)
	if fallbackSuccess and fallbackInfo then
		return fallbackInfo, "DeveloperProduct"
	end

	return nil, nil, err or fallbackErr
end

local usedExistingShopCards = {}

for _,Gamepass in ReplicatedStorage.Gamepasses:GetChildren() do
	local gamepassContainer = getGamepassContainer()
	if not gamepassContainer then
		warn("[ShopClient] Missing Shop.Gamepasses container. Expected Shop.GamepassesHolder.Gamepasses or Shop.Gamepasses.")
		break
	end

	local ExistingCard = getExistingShopCard(Gamepass)
	if ExistingCard and usedExistingShopCards[ExistingCard] then
		ExistingCard = nil
	end
	local isCustomCard = ExistingCard ~= nil
	local NewGamepass = ExistingCard or getGamepassTemplate(Gamepass):Clone()
	local sectionName = normalizeSectionName(Gamepass:GetAttribute("ShopSection"))
	if not isValidShopCard(NewGamepass) then
		warn(("[ShopClient] Invalid shop card for '%s'. Card must include InnerPart > Button and InnerPart > Price."):format(Gamepass.Name))
		if not isCustomCard and NewGamepass then
			NewGamepass:Destroy()
		end
		continue
	end
	if not isCustomCard then
		NewGamepass.Parent = gamepassContainer
	else
		usedExistingShopCards[ExistingCard] = true
	end
	NewGamepass:SetAttribute("ShopSection", sectionName)

	local GamepassInfo
	local purchaseType
	local _, Error
	GamepassInfo, purchaseType, Error = getProductInfoWithType(Gamepass.Value)


	if Error then
		warn(("[ShopClient] Product info failed for '%s' (id=%s): %s. Using fallback UI values.")
			:format(Gamepass.Name, tostring(Gamepass.Value), tostring(Error)))
		GamepassInfo = {
			Name = tostring(Gamepass:GetAttribute("DisplayName") or Gamepass.Name),
			Description = tostring(Gamepass:GetAttribute("Description") or "Premium purchase"),
			PriceInRobux = tonumber(Gamepass:GetAttribute("PriceInRobux")) or 0,
			IconImageAssetId = tonumber(Gamepass:GetAttribute("ImageAssetId")) or nil,
		}
		purchaseType = tostring(Gamepass:GetAttribute("PurchaseType")) == "DeveloperProduct" and "DeveloperProduct" or "GamePass"
	end

	do
		local autoFillInfo = Gamepass:GetAttribute("AutoFillInfo")
		if autoFillInfo == nil then
			autoFillInfo = not isCustomCard
		end

		if autoFillInfo then
			NewGamepass.InnerPart.ImageLabel.Image = "rbxassetid://"..(GamepassInfo.IconImageAssetId or 666669321)
			NewGamepass.InnerPart.Description.Text = GamepassInfo.Description 
			NewGamepass.InnerPart.GPName.Text = GamepassInfo.Name
		end

		local dataValue = Data.Gamepasses:FindFirstChild(Gamepass.Name)
		if purchaseType == "DeveloperProduct" then
			NewGamepass.InnerPart.Price.Text = "\u{E002}"..(GamepassInfo.PriceInRobux or 10000)
		else
			NewGamepass.InnerPart.Price.Text = (dataValue and dataValue.Value) and "Owned ✅" or "\u{E002}"..(GamepassInfo.PriceInRobux or 10000)
		end

		if dataValue and purchaseType ~= "DeveloperProduct" then
			dataValue.Changed:Connect(function()
				NewGamepass.InnerPart.Price.Text = dataValue.Value and "Owned ✅" or "\u{E002}"..(GamepassInfo.PriceInRobux or 10000)
			end)
		end

		local applyOverrides = Gamepass:GetAttribute("ApplyVisualOverrides")
		if applyOverrides == nil then
			applyOverrides = not isCustomCard
		end
		if applyOverrides then
			applyVisualOverrides(NewGamepass, Gamepass)
		end


		NewGamepass.InnerPart.Button.MouseButton1Click:Connect(function()
			local canPrompt, reason = true, "Allowed"
			if canPromptPetPurchase and canPromptPetPurchase:IsA("RemoteFunction") then
				local ok, allowed, denyReason = pcall(function()
					return canPromptPetPurchase:InvokeServer(Gamepass.Name)
				end)
				if ok then
					canPrompt = allowed == true
					reason = tostring(denyReason or "")
				end
			end
			if not canPrompt then
				if reason == "InventoryFull" then
					notifyPlayer("error", "❌ Inventory full. Free slots before buying pet packs.")
				else
					notifyPlayer("error", "❌ Purchase unavailable right now. Try again in a moment.")
				end
				Utilities.Audio.PlayAudio("Click")
				return
			end

			if purchaseType == "DeveloperProduct" then
				MarketPlaceService:PromptProductPurchase(Player, Gamepass.Value)
			else
				MarketPlaceService:PromptGamePassPurchase(Player, Gamepass.Value)
			end
			Utilities.Audio.PlayAudio("Click")
		end)
	end
end

local function setupShopSectionLayoutAndButtons()
	local shopFrame = Frames and Frames:FindFirstChild("Shop")
	local gamepassContainer = getGamepassContainer()
	if not shopFrame or not gamepassContainer then
		return
	end

	local function collectSections()
		local sectionMap = {}
		local sectionMeta = {}
		for _, card in ipairs(gamepassContainer:GetDescendants()) do
			if card:IsA("Frame") and isSectionNavigableShopCard(card) then
				local sectionName = normalizeSectionName(card:GetAttribute("ShopSection"))
				if card.Name == "Codes" and (card:GetAttribute("ShopSection") == nil or trimText(card:GetAttribute("ShopSection")) == "") then
					sectionName = "Codes"
				end
				local key = sectionToKey(sectionName)
				if not sectionMap[key] then
					sectionMap[key] = card
					sectionMeta[key] = {Name = sectionName, Card = card}
				else
					local current = sectionMap[key]
					if card.AbsolutePosition.Y < current.AbsolutePosition.Y then
						sectionMap[key] = card
						sectionMeta[key] = {Name = sectionName, Card = card}
					end
				end
			end
		end
		return sectionMap, sectionMeta
	end

	local sectionMap, sectionMeta = collectSections()

	for _, child in ipairs(gamepassContainer:GetChildren()) do
		if child:IsA("TextLabel") and string.sub(child.Name, 1, #"__SectionHeader_") == "__SectionHeader_" then
			child:Destroy()
		end
	end

	for key, meta in pairs(sectionMeta) do
		local targetCard = meta.Card
		if targetCard then
			local header = Instance.new("TextLabel")
			header.Name = "__SectionHeader_" .. key
			header.BackgroundTransparency = 1
			header.Text = meta.Name
			header.TextXAlignment = Enum.TextXAlignment.Left
			header.TextYAlignment = Enum.TextYAlignment.Center
			header.Font = Enum.Font.GothamBold
			header.TextSize = 20
			header.TextColor3 = Color3.fromRGB(255, 255, 255)
			header.ZIndex = math.max(targetCard.ZIndex + 1, 10)
			header.Active = false
			header.Selectable = false

			local headerHeight = 28
			local yPos = math.max(0, targetCard.AbsolutePosition.Y - gamepassContainer.AbsolutePosition.Y + gamepassContainer.CanvasPosition.Y - headerHeight - 6)
			header.Position = UDim2.new(0, 12, 0, yPos)
			header.Size = UDim2.new(targetCard.Size.X.Scale, targetCard.Size.X.Offset, 0, headerHeight)
			header.Parent = gamepassContainer
		end
	end

	local sectionButtons = getShopSectionsButtonMap(shopFrame)
	for key, button in pairs(sectionButtons) do
		if button:GetAttribute("ShopSectionBound") ~= true then
			button:SetAttribute("ShopSectionBound", true)
			button.MouseButton1Click:Connect(function()
				sectionMap = collectSections()
				local targetCard = sectionMap[key]
				if targetCard then
					scrollShopToSection(gamepassContainer, targetCard)
				end
			end)
		end
	end
end

setupShopSectionLayoutAndButtons()

--// Pet Inventory
local PetInventory = {} -- all pets will be added in this table

local PetFrame = Frames.Pets
local SideFrame = PetFrame.SideFrame
local SellShopFrame = Frames:FindFirstChild("SellShop")
local SellObjectHolder = SellShopFrame and SellShopFrame:FindFirstChild("PetsHolder") and SellShopFrame.PetsHolder:FindFirstChild("ObjectHolder")
PetFrame.SideFrameBlocker.Visible = true
local PetStateEvent = ReplicatedStorage:FindFirstChild("PetStateEvent")
local PetSellQuoteRemote = Remotes:FindFirstChild("PetSellQuote")

local IsMultiDeleting = false
local SelectedForDelete = {}
local CanDeletePets = false
local CachedPetStateByKey = {}
local SellSlotByPetId = {}
local OpenSellFramePetId = nil

local function getPetTemplate(petInstance)
	if not petInstance then return nil end
	local petNameValue = petInstance:FindFirstChild("PetName")
	if not petNameValue then return nil end
	return ReplicatedStorage.Pets:FindFirstChild(petNameValue.Value)
end

local HoverGuiController = (function()
	local playerGui = Player:FindFirstChildOfClass("PlayerGui")
	local hoverScreenGui = playerGui and playerGui:FindFirstChild("HoverGui")
	local hoverFrame = hoverScreenGui and hoverScreenGui:FindFirstChild("Hover1")
	local nameLabel = hoverFrame and hoverFrame:FindFirstChild("NameFrame") and hoverFrame.NameFrame:FindFirstChild("Name")
	local powerLabel = hoverFrame and hoverFrame:FindFirstChild("PowerFrame") and hoverFrame.PowerFrame:FindFirstChild("Power")

	if hoverFrame then
		hoverFrame.Visible = false
	end

	local activeHoverFrame = nil
	local activeTouchInput = nil
	local activePointerPosition = nil
	local currentHoverFrame = hoverFrame

	local function getPetDisplayName(petInstance)
		if not petInstance then
			return "Unknown Pet"
		end

		local templateName = tostring(petInstance:GetAttribute("TemplateName") or "")
		if templateName ~= "" then
			return templateName
		end

		local folderName = tostring(petInstance.Name or "")
		local asNumber = tonumber(folderName)
		if asNumber ~= nil then
			local nickValue = petInstance:FindFirstChild("PetName")
			if nickValue and nickValue:IsA("StringValue") and nickValue.Value ~= "" then
				return nickValue.Value
			end
			local petTemplate = getPetTemplate(petInstance)
			if petTemplate and petTemplate.Name ~= "" then
				return petTemplate.Name
			end
		end

		return folderName ~= "" and folderName or "Unknown Pet"
	end

	local function getPetPowerText(petInstance)
		if not petInstance then
			return "Power: ?"
		end

		local powerFromValue = petInstance:FindFirstChild("Power")
		local power = powerFromValue and powerFromValue:IsA("NumberValue") and powerFromValue.Value
		if power == nil then
			power = petInstance:GetAttribute("Power")
		end
		if power == nil then
			local petTemplate = getPetTemplate(petInstance)
			power = petTemplate and petTemplate:GetAttribute("Power")
		end
		power = tonumber(power) or 0
		return ("Power: %s"):format(Utilities.Short.en(power))
	end

	local function updateHoverPosition(inputObject)
		if not currentHoverFrame or not currentHoverFrame.Visible then return end
		local mousePos = inputObject
		if typeof(inputObject) == "InputObject" then
			mousePos = inputObject.Position
		end
		if not mousePos then return end
		local camera = workspace.CurrentCamera
		if not camera then return end

		local x = math.clamp(mousePos.X + 16, 0, camera.ViewportSize.X - currentHoverFrame.AbsoluteSize.X)
		local y = math.clamp(mousePos.Y + 16, 0, camera.ViewportSize.Y - currentHoverFrame.AbsoluteSize.Y)
		currentHoverFrame.Position = UDim2.fromOffset(x, y)
	end

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			activePointerPosition = input.Position
			updateHoverPosition(input)
		elseif input.UserInputType == Enum.UserInputType.Touch and activeTouchInput == input then
			activePointerPosition = input.Position
			updateHoverPosition(input)
		end
	end)
	RunService.RenderStepped:Connect(function()
		if currentHoverFrame and currentHoverFrame.Visible then
			if activePointerPosition then
				updateHoverPosition(activePointerPosition)
			else
				updateHoverPosition(UserInputService:GetMouseLocation())
			end
		end
	end)

	local function bind(guiObject, petInstance, hoverFrameName, customNameResolver, customDetailResolver)
		if not guiObject or not guiObject:IsA("GuiObject") then return end
		local function showHover()
			local frameToUse = hoverFrame
			if hoverFrameName and hoverScreenGui then
				frameToUse = hoverScreenGui:FindFirstChild(hoverFrameName) or hoverFrame
			end
			if not frameToUse then return end
			activeHoverFrame = guiObject
			local localNameLabel = frameToUse:FindFirstChild("NameFrame") and frameToUse.NameFrame:FindFirstChild("Name")
			local localPowerLabel = frameToUse:FindFirstChild("PowerFrame") and frameToUse.PowerFrame:FindFirstChild("Power")
			if localNameLabel then
				localNameLabel.Text = customNameResolver and customNameResolver(petInstance, getPetTemplate(petInstance)) or getPetDisplayName(petInstance)
			end
			if localPowerLabel then
				localPowerLabel.Text = customDetailResolver and customDetailResolver(petInstance, getPetTemplate(petInstance)) or getPetPowerText(petInstance)
			end
			frameToUse.Visible = true
			currentHoverFrame = frameToUse
			activePointerPosition = UserInputService:GetMouseLocation()
			updateHoverPosition(activePointerPosition)
		end

		local function hideHover()
			if activeHoverFrame ~= guiObject then return end
			activeHoverFrame = nil
			activeTouchInput = nil
			activePointerPosition = nil
			currentHoverFrame = hoverFrame
			if hoverScreenGui then
				for _, child in ipairs(hoverScreenGui:GetChildren()) do
					if child:IsA("GuiObject") and child.Name:match("^Hover") then
						child.Visible = false
					end
				end
			end
		end

		guiObject.MouseEnter:Connect(function()
			showHover()
		end)

		guiObject.MouseLeave:Connect(function()
			hideHover()
		end)

		guiObject.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				activeTouchInput = input
				activePointerPosition = input.Position
				showHover()
			end
		end)

		guiObject.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch and activeTouchInput == input and currentHoverFrame and currentHoverFrame.Visible then
				activePointerPosition = input.Position
				updateHoverPosition(input)
			end
		end)

		guiObject.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch and activeTouchInput == input then
				hideHover()
			end
		end)
	end

	return {
		bind = bind,
	}
end)()

local function bindPetHoverByResolver(container, hoverFrameName, resolvePetName, followPointer)
	if not container then return end
	local playerGui = Player:FindFirstChildOfClass("PlayerGui")
	local hoverRoot = playerGui and playerGui:FindFirstChild("HoverGui")
	local hoverFrame = hoverRoot and hoverRoot:FindFirstChild(hoverFrameName)
	if not hoverFrame then return end

	local nameLabel = hoverFrame:FindFirstChild("NameFrame") and hoverFrame.NameFrame:FindFirstChild("Name")
	local powerLabel = hoverFrame:FindFirstChild("PowerFrame") and hoverFrame.PowerFrame:FindFirstChild("Power")
	local petsFolder = ReplicatedStorage:FindFirstChild("Pets")
	hoverFrame.Visible = false

	local activeTouch = nil
	local activePointerPosition = nil

	local function setHoverPosition(gui, pointerPos)
		if followPointer then
			local pos = pointerPos or UserInputService:GetMouseLocation()
			local camera = workspace.CurrentCamera
			if not pos or not camera then return end
			local x = math.clamp(pos.X + 16, 0, camera.ViewportSize.X - hoverFrame.AbsoluteSize.X)
			local y = math.clamp(pos.Y + 16, 0, camera.ViewportSize.Y - hoverFrame.AbsoluteSize.Y)
			hoverFrame.Position = UDim2.fromOffset(x, y)
		else
			hoverFrame.Position = UDim2.fromOffset(gui.AbsolutePosition.X, gui.AbsolutePosition.Y - hoverFrame.AbsoluteSize.Y - 6)
		end
	end


	local function tryBind(gui)
		if not (gui:IsA("ImageLabel") or gui:IsA("ImageButton")) then return end
		local petName = resolvePetName(gui)
		if not petName or petName == "" then return end
		local function show()
			local template = petsFolder and petsFolder:FindFirstChild(petName) or nil
			if nameLabel then nameLabel.Text = template and template.Name or petName end
			if powerLabel then powerLabel.Text = ("Power: %s"):format(Utilities.Short.en(tonumber(template and template:GetAttribute("Power")) or 0)) end
			setHoverPosition(gui, activePointerPosition)
			hoverFrame.Visible = true
		end
		local function hide() activeTouch=nil activePointerPosition=nil hoverFrame.Visible=false end
		gui.MouseEnter:Connect(function() activePointerPosition=UserInputService:GetMouseLocation() show() end)
		gui.MouseLeave:Connect(hide)
		gui.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.Touch then activeTouch=input activePointerPosition=input.Position show() end end)
		gui.InputChanged:Connect(function(input) if followPointer and input.UserInputType==Enum.UserInputType.Touch and activeTouch==input and hoverFrame.Visible then activePointerPosition=input.Position setHoverPosition(gui,activePointerPosition) end end)
		gui.InputEnded:Connect(function(input) if input.UserInputType==Enum.UserInputType.Touch and activeTouch==input then hide() end end)
	end

	for _, gui in ipairs(container:GetDescendants()) do
		tryBind(gui)
	end
	container.DescendantAdded:Connect(tryBind)
	if followPointer then
		UserInputService.InputChanged:Connect(function(input)
			if not hoverFrame.Visible then return end
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				activePointerPosition = input.Position
				local hovered = UserInputService:GetMouseLocation()
				setHoverPosition(container, hovered)
			end
		end)
	end
end

local function bindStaticPetHoverByAttribute(container, hoverFrameName, followPointer)
	bindPetHoverByResolver(container, hoverFrameName, function(gui)
		return tostring(gui:GetAttribute("HoverPet") or gui:GetAttribute("HoverPetName") or gui:GetAttribute("HoverPetTemplate") or "")
	end, followPointer)
end

local function bindPassRewardHoverFromConfig(passFrame)
	local modulesFolder = ReplicatedStorage:FindFirstChild("Modules")
	local passConfigModule = (modulesFolder and modulesFolder:FindFirstChild("PassRewardsConfig")) or ReplicatedStorage:FindFirstChild("PassRewardsConfig")
	if not passConfigModule then return end
	local passConfig = require(passConfigModule)
	local rewardPetByLevelAndTier = {}
	for _, reward in ipairs(passConfig.Rewards or {}) do
		if reward.Type == "Pet" and reward.PetName and reward.Level and reward.Tier then
			rewardPetByLevelAndTier[tostring(reward.Level)..":"..tostring(reward.Tier)] = reward.PetName
		end
	end
	bindPetHoverByResolver(passFrame, "Hover5", function(gui)
		local direct = tostring(gui:GetAttribute("HoverPet") or "")
		if direct ~= "" then return direct end
		local level = gui:GetAttribute("Level") or gui:GetAttribute("RewardLevel")
		local tier = gui:GetAttribute("Tier") or gui:GetAttribute("RewardTier")
		local rewardFrame = gui:FindFirstAncestorWhichIsA("Frame")
		while rewardFrame do
			if level == nil then
				level = rewardFrame:GetAttribute("Level") or rewardFrame:GetAttribute("RewardLevel") or tonumber(rewardFrame.Name:match("%d+"))
			end
			if tier == nil then
				tier = rewardFrame:GetAttribute("Tier") or rewardFrame:GetAttribute("RewardTier")
			end
			if level and tier then break end
			rewardFrame = rewardFrame.Parent and rewardFrame.Parent:IsA("Frame") and rewardFrame.Parent or nil
		end
		if level and tier then
			return rewardPetByLevelAndTier[tostring(level)..":"..tostring(tier)] or tostring(gui:GetAttribute("PetName") or "")
		end
		return tostring(gui:GetAttribute("PetName") or "")
	end, false)
end

task.defer(function()
	local shopFrame = Frames and Frames:FindFirstChild("Shop")
	local passFrame = Frames and (Frames:FindFirstChild("PassFrame") or Frames:FindFirstChild("PassRewards") or Frames:FindFirstChild("Pass"))
	if shopFrame then
		bindStaticPetHoverByAttribute(shopFrame, "Hover3", true)
	end
	if passFrame then
		bindPassRewardHoverFromConfig(passFrame)
	end
end)
local SideFramePetBarsVisible = true

local function setSideFrameOpen(isOpen)
	if not SideFrame then return end
	SideFrame.Visible = isOpen and true or false
	PetFrame.SideFrameBlocker.Visible = not isOpen

	if not isOpen then
		if SideFrame.Display and SideFrame.Display:FindFirstChild("PetModel") then
			SideFrame.Display.PetModel:Destroy()
		end
		if SideFrame:FindFirstChild("Title") then
			SideFrame.Title.Visible = true
		end
	end
end


setSideFrameOpen(false)

if PetFrame:GetAttribute("CanDeletePets") == nil then
	PetFrame:SetAttribute("CanDeletePets", false)
end

PetFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if not PetFrame.Visible and PetFrame:GetAttribute("CanDeletePets") then
		PetFrame:SetAttribute("CanDeletePets", false)
	end
end)



local function getPetMultiplier(petInstance)
	local template = getPetTemplate(petInstance)
	local settings = template and template:FindFirstChild("Settings")
	local multiplier = settings and settings:FindFirstChild("Multiplier")
	return (multiplier and tonumber(multiplier.Value)) or 1
end

local function getPetUidFromFolder(petFolder)
	local uidValue = petFolder and petFolder:FindFirstChild("PetUID")
	local uid = uidValue and uidValue.Value or nil
	if type(uid) ~= "string" or uid == "" then
		return nil
	end
	return uid
end


function SortInventory(SortTable, ObjectHolder)
	local TableToSort = SortTable ~= nil and SortTable or PetInventory -- so it can differentiate between trade and normal inventories

	table.sort(TableToSort, function(a,b)
		if not a or not b then return end

		if a.Multiplier ~= b.Multiplier then
			return a.Multiplier > b.Multiplier
		else
			return a.ID > b.ID
		end
	end)

	for Order,PetInfo in TableToSort do
		if not Data.Pets:FindFirstChild(PetInfo.ID) then
			table.remove(TableToSort, Order)
			continue
		end

		if not ObjectHolder then
			PetFrame.MainFrame.ObjectHolder[PetInfo.ID].LayoutOrder = Order
		else
			ObjectHolder[PetInfo.ID].LayoutOrder = Order
		end
	end
end

local CurrentlySelected = 0

local getSelectedPetKeys
local updateSideFrameState
local findSideFrameObject
local getPrimaryPartForDisplay
local getDisplaySize

local function clearSideFrameDisplayModel()
	if not SideFrame or not SideFrame:FindFirstChild("Display") then return end
	for _, child in ipairs(SideFrame.Display:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") then
			child:Destroy()
		end
	end
end

local function setPetBarsVisible(visible)
	if SideFramePetBarsVisible == visible then return end
	SideFramePetBarsVisible = visible
	for _, name in ipairs({
		"hungerbarfill", "wetbarfill", "dirtbarfill", "happinessbarfill", "xpbarfill",
		"HungerBarFill", "WetBarFill", "DirtBarFill", "HappinessBarFill", "XPBarFill",
		"hungerbar", "wetbar", "dirtbar", "happinessbar", "xpbar",
		"HungerBar", "WetBar", "DirtBar", "HappinessBar", "XPBar",
		"Multiplier",
		}) do
		local obj = findSideFrameObject(name)
		if obj and obj:IsA("GuiObject") then
			obj.Visible = visible
		end
	end
end

local function setSideFrameInfoLabel(text)
	local info = findSideFrameObject("InfoLabelExtra")
	if info and info:IsA("TextLabel") then
		info.Text = tostring(text or "")
		info.Visible = info.Text ~= ""
	end
end

local function getItemInfoText(itemFolder, template)
	local folderInfoValue = itemFolder and (itemFolder:FindFirstChild("Info") or itemFolder:FindFirstChild("Description"))
	if folderInfoValue and folderInfoValue:IsA("StringValue") and folderInfoValue.Value ~= "" then
		return folderInfoValue.Value
	end
	local folderAttrInfo = itemFolder and (itemFolder:GetAttribute("InfoLabelExtra") or itemFolder:GetAttribute("Info") or itemFolder:GetAttribute("Description"))
	if type(folderAttrInfo) == "string" and folderAttrInfo ~= "" then
		return folderAttrInfo
	end
	local templateInfo = template and (template:GetAttribute("InfoLabelExtra") or template:GetAttribute("Info") or template:GetAttribute("Description"))
	if type(templateInfo) == "string" and templateInfo ~= "" then
		return templateInfo
	end
	return ""
end

local function showInventoryItemSideFrame(itemName, template, infoText)
	setSideFrameOpen(true)
	setPetBarsVisible(false)
	clearSideFrameDisplayModel()

	if SideFrame:FindFirstChild("Title") then
		SideFrame.Title.Visible = true
	end
	if SideFrame:FindFirstChild("Multiplier") and SideFrame.Multiplier:FindFirstChild("Amount") then
		SideFrame.Multiplier.Amount.Text = ""
	end
	setSideFrameInfoLabel(infoText)

	local titleLabel = findSideFrameObject("Title")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = tostring(itemName or "Item")
	end

	if not template or not SideFrame:FindFirstChild("Display") then
		return
	end

	local model = template:Clone()
	model.Name = "PetModel"
	model.Parent = SideFrame.Display
	local mainPart = getPrimaryPartForDisplay(model)
	if not mainPart then
		model:Destroy()
		return
	end
	local pos = mainPart.Position
	local camera = Instance.new("Camera")
	SideFrame.Display.CurrentCamera = camera
	if model:IsA("Model") then
		model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(180), 0))
	else
		model.CFrame = model.CFrame * CFrame.Angles(0, math.rad(180), 0)
	end
	camera.CFrame = CFrame.new(Vector3.new(pos.X + getDisplaySize(model).X * 1.5, pos.Y, pos.Z + 1), pos)
end

local function findDescendantByNameInsensitive(root, targetName)
	if not root or not targetName then return nil end
	local lowerTarget = string.lower(targetName)
	for _, desc in ipairs(root:GetDescendants()) do
		if string.lower(desc.Name) == lowerTarget then
			return desc
		end
	end
	return nil
end

findSideFrameObject = function(name)
	return SideFrame:FindFirstChild(name) or findDescendantByNameInsensitive(SideFrame, name)
end

local function getCachedStateForPetFolder(petFolder)
	if not petFolder then return nil end
	local petId = tostring(petFolder.Name)
	local petName = petFolder:FindFirstChild("PetName") and petFolder.PetName.Value or nil
	local petUid = getPetUidFromFolder(petFolder)

	return (petUid and CachedPetStateByKey[petUid])
		or CachedPetStateByKey[petId]
		or (petUid and CachedPetStateByKey["inv:"..petUid])
		or CachedPetStateByKey["invId:"..petId]
		or (petName and CachedPetStateByKey[tostring(petName)])
end

local function getSellFrameParts(slotFrame)
	if not slotFrame then return nil, nil, nil end
	local sellFrame = slotFrame:FindFirstChild("SellFrame") or findDescendantByNameInsensitive(slotFrame, "SellFrame")
	if not sellFrame then return nil, nil, nil end

	local sellButton = sellFrame:FindFirstChild("SellButton")
		or sellFrame:FindFirstChild("Sell")
		or findDescendantByNameInsensitive(sellFrame, "SellButton")
	local titleLabel = sellFrame:FindFirstChild("TitleLabel")
		or sellFrame:FindFirstChild("Title")
		or findDescendantByNameInsensitive(sellFrame, "TitleLabel")
	return sellFrame, sellButton, titleLabel
end

local function getSellFrameTemplate()
	if not SellShopFrame then return nil end
	local template = SellShopFrame:FindFirstChild("SellFrame") or findDescendantByNameInsensitive(SellShopFrame, "SellFrame")
	if template and template:IsA("GuiObject") then
		template.Visible = false
	end
	return template
end

local function ensureSellFrameExists(slotFrame)
	if not slotFrame then return nil, nil, nil end
	local sellFrame, sellButton, titleLabel = getSellFrameParts(slotFrame)
	if sellFrame then
		return sellFrame, sellButton, titleLabel
	end

	local template = getSellFrameTemplate()
	if not template then
		return nil, nil, nil
	end

	local cloned = template:Clone()
	cloned.Name = "SellFrame"
	cloned.Visible = false
	cloned.Parent = slotFrame
	return getSellFrameParts(slotFrame)
end

local function requestSellPriceFromServer(petId)
	if not PetSellQuoteRemote then return 0 end
	local ok, result = pcall(function()
		return PetSellQuoteRemote:InvokeServer(tostring(petId))
	end)
	if not ok then return 0 end
	return math.max(0, math.floor(tonumber(result) or 0))
end

local function updateSellSlotText(petFolder, slotFrame)
	if not petFolder or not slotFrame then return end
	local sellFrame, _, titleLabel = getSellFrameParts(slotFrame)
	if not sellFrame or not titleLabel then return end

	local petId = tostring(petFolder.Name)
	local cachedState = getCachedStateForPetFolder(petFolder)
	local levelValue = petFolder:FindFirstChild("Level")
	local level = (levelValue and levelValue.Value) or (cachedState and cachedState.level) or 1

	local quotedPrice = requestSellPriceFromServer(petId)
	titleLabel.Text = ("Sell for %s (Lv.%s)"):format(Utilities.Short.en(quotedPrice), tostring(math.max(1, math.floor(tonumber(level) or 1))))
end

local function closeAllSellFrames(exceptPetId)
	for petId, slotFrame in pairs(SellSlotByPetId) do
		if exceptPetId ~= nil and tostring(petId) == tostring(exceptPetId) then
			continue
		end
		local sellFrame = slotFrame and (slotFrame:FindFirstChild("SellFrame") or findDescendantByNameInsensitive(slotFrame, "SellFrame"))
		if sellFrame then
			sellFrame.Visible = false
		end
	end
end


function AddPet(PetInstance, SortTable, Parent) -- Creates a pet slot
	task.wait(0.1)
	local NewPet = script.PetTemplate:Clone()

	local PetTemplate = getPetTemplate(PetInstance)
	if not PetTemplate then
		warn(("[PetInventoryClient] Missing ReplicatedStorage.Pets model for inventory pet '%s'"):format(tostring(PetInstance.Name)))
		NewPet:Destroy()
		return nil
	end
	local PetModel = PetTemplate:Clone()
	PetModel.Parent = NewPet.Display

	local MainPart = PetModel:FindFirstChild("MainPart") or PetModel.PrimaryPart or PetModel:FindFirstChildWhichIsA("BasePart", true)
	local Pos

	if not MainPart then
		warn(PetModel.Name.." does not have a BasePart, could not render inventory slot")
		NewPet:Destroy()
		return nil
	end

	Pos = MainPart.Position
	local Camera = Instance.new("Camera")
	NewPet.Display.CurrentCamera = Camera
	PetModel:PivotTo(PetModel:GetPivot() * CFrame.Angles(0, math.rad(180), 0))
	Camera.CFrame = CFrame.new(Vector3.new(Pos.X + PetModel:GetExtentsSize().X * 1.5, Pos.Y, Pos.Z + 1), Pos)

	if not Parent then -- normal pet
		NewPet.Equipped.Visible = false

		NewPet.Button.MouseButton1Click:Connect(function()
			if not IsMultiDeleting then
				UpdateSideFrame(PetInstance)
			else
				if not CanDeletePets then return end
				if not table.find(SelectedForDelete, tonumber(PetInstance.Name)) then
					table.insert(SelectedForDelete, tonumber(PetInstance.Name))
				else
					table.remove(SelectedForDelete, table.find(SelectedForDelete, tonumber(PetInstance.Name)))
				end
			end
			Utilities.Audio.PlayAudio("Click")
		end)
	end
	HoverGuiController.bind(NewPet.Button, PetInstance)
	NewPet.Name = PetInstance.Name
	NewPet.Parent = Parent == nil and PetFrame.MainFrame.ObjectHolder or Parent
	
	if Parent == SellObjectHolder then
		SellSlotByPetId[PetInstance.Name] = NewPet
		closeAllSellFrames()

		local sellFrame, sellButton, _ = ensureSellFrameExists(NewPet)
		if sellFrame then
			sellFrame.Visible = false
		end
		updateSellSlotText(PetInstance, NewPet)

		NewPet.Button.MouseButton1Click:Connect(function()
			local myPetId = tostring(PetInstance.Name)
			local shouldOpen = OpenSellFramePetId ~= myPetId
			closeAllSellFrames(myPetId)
			local thisSellFrame = NewPet:FindFirstChild("SellFrame") or findDescendantByNameInsensitive(NewPet, "SellFrame")
			if thisSellFrame then
				thisSellFrame.Visible = shouldOpen
			end
			OpenSellFramePetId = shouldOpen and myPetId or nil
			updateSellSlotText(PetInstance, NewPet)
			Utilities.Audio.PlayAudio("Click")
		end)

		if sellButton and sellButton:IsA("GuiButton") then
			sellButton.MouseButton1Click:Connect(function()
				Remotes.Pet:FireServer("Sell", tonumber(PetInstance.Name))
				Utilities.Audio.PlayAudio("Click")
			end)
		end
	end

	local multiplier = getPetMultiplier(PetInstance)
	if Parent == nil and SortTable == nil then
		PetInventory[#PetInventory+1] = {ID = PetInstance.Name, Multiplier = multiplier}
	elseif SortTable ~= nil then
		SortTable[#SortTable+1] = {ID = PetInstance.Name, Multiplier = multiplier}
	end

	return NewPet
end

function UpdateSideFrame(PetInstance) -- PetInstance is the folder in Player.Pets
	CurrentlySelected = tonumber(PetInstance.Name)
	setPetBarsVisible(true)
	setSideFrameInfoLabel("")
	setSideFrameOpen(true)
	
	if SideFrame:FindFirstChild("Title") then
		SideFrame.Title.Visible = false
	end

	if SideFrame.Display:FindFirstChild("PetModel") then
		SideFrame.Display.PetModel:Destroy()
	end

	local PetTemplate = getPetTemplate(PetInstance)
	if not PetTemplate then
		SideFrame.Multiplier.Amount.Text = "x1"
		return
	end
	local PetModel = PetTemplate:Clone()
	PetModel.Name = "PetModel"
	PetModel.Parent = SideFrame.Display

	local MainPart = PetModel:FindFirstChild("MainPart") or PetModel.PrimaryPart or PetModel:FindFirstChildWhichIsA("BasePart", true)
	if not MainPart then
		SideFrame.Multiplier.Amount.Text = "x"..Utilities.Short.en(getPetMultiplier(PetInstance))
		return
	end
	local Pos = MainPart.Position
	local Camera = Instance.new("Camera")
	SideFrame.Display.CurrentCamera = Camera
	PetModel:PivotTo(PetModel:GetPivot() * CFrame.Angles(0, math.rad(180), 0))
	Camera.CFrame = CFrame.new(Vector3.new(Pos.X + PetModel:GetExtentsSize().X * 1.5, Pos.Y, Pos.Z + 1), Pos)

	SideFrame.Multiplier.Amount.Text = "x"..Utilities.Short.en(getPetMultiplier(PetInstance))
	local selectedPetId, selectedPetName, selectedPetUid = getSelectedPetKeys()
	local cachedState = selectedPetId and (
		(selectedPetUid and CachedPetStateByKey[selectedPetUid])
			or CachedPetStateByKey[selectedPetId]
			or (selectedPetUid and CachedPetStateByKey["inv:"..selectedPetUid])
			or (selectedPetId and CachedPetStateByKey["invId:"..selectedPetId])
			or (selectedPetName and CachedPetStateByKey[tostring(selectedPetName)])
	) or nil
	if cachedState then
		updateSideFrameState(cachedState)
	elseif PetStateEvent then
		pcall(function()
			PetStateEvent:FireServer("RequestOwnedPetsState")
		end)
	end
end

local function setBar(sideFrame, barName, value, maxValue)
	local barFill = sideFrame:FindFirstChild(barName) or findDescendantByNameInsensitive(sideFrame, barName)
	if not barFill then return end

	maxValue = maxValue and math.max(maxValue, 1) or 100
	local normalizedValue = math.clamp((tonumber(value) or 0) / maxValue, 0, 1)
	barFill.Size = UDim2.new(normalizedValue, 0, barFill.Size.Y.Scale, barFill.Size.Y.Offset)

	local textLabel = barFill:FindFirstChild("Text")
		or barFill:FindFirstChild("Amount")
		or barFill:FindFirstChildWhichIsA("TextLabel")
		or barFill.Parent and barFill.Parent:FindFirstChild(barName:gsub("Fill", "Text"))
		or (barFill.Parent and (barFill.Parent:FindFirstChild("Text") or barFill.Parent:FindFirstChild("Amount") or barFill.Parent:FindFirstChildWhichIsA("TextLabel")))
	if textLabel then
		textLabel.Text = ("%d / %d"):format(math.floor(tonumber(value) or 0), math.floor(maxValue))
	end
end

updateSideFrameState = function(payload)
	if not payload or not SideFrame or PetFrame.SideFrameBlocker.Visible then return end

	setBar(SideFrame, "hungerbarfill", payload.hunger, tonumber(payload.hungerMax) or 100)
	setBar(SideFrame, "wetbarfill", 0, 100)
	setBar(SideFrame, "dirtbarfill", payload.dirtiness, 100)
	setBar(SideFrame, "happinessbarfill", payload.happiness, tonumber(payload.happinessMax) or 100)

	local xpFill = findSideFrameObject("xpbarfill")
	if xpFill then
		local progress = math.clamp(tonumber(payload.levelProgress) or 0, 0, 1)
		xpFill.Size = UDim2.new(progress, 0, xpFill.Size.Y.Scale, xpFill.Size.Y.Offset)
		local xpText = xpFill:FindFirstChild("Text")
			or xpFill:FindFirstChild("Amount")
			or xpFill:FindFirstChildWhichIsA("TextLabel")
			or (xpFill.Parent and (xpFill.Parent:FindFirstChild("Text") or xpFill.Parent:FindFirstChild("Amount") or xpFill.Parent:FindFirstChildWhichIsA("TextLabel")))
		if xpText then
			if payload.xpInLevel and payload.xpForNext and payload.xpForNext ~= math.huge then
				xpText.Text = ("%d / %d XP"):format(math.max(0, payload.xpInLevel), math.max(1, math.floor(payload.xpForNext)))
			else
				xpText.Text = ("%d XP"):format(math.max(0, payload.xp or 0))
			end
		end
	end
end

getSelectedPetKeys = function()
	if CurrentlySelected == 0 then return nil, nil, nil end
	local selectedId = tostring(CurrentlySelected)
	local selectedPetFolder = Data.Pets:FindFirstChild(selectedId)
	local selectedPetName = selectedPetFolder and selectedPetFolder:FindFirstChild("PetName") and selectedPetFolder.PetName.Value or nil
	local selectedPetUid = getPetUidFromFolder(selectedPetFolder)
	return selectedId, selectedPetName, selectedPetUid
end

local function updateSideFrameState(payload)
	if not payload or not SideFrame or PetFrame.SideFrameBlocker.Visible then return end

	setBar(SideFrame, "hungerbarfill", payload.hunger, tonumber(payload.hungerMax) or 100)
	setBar(SideFrame, "wetbarfill", 0, 100)
	setBar(SideFrame, "dirtbarfill", payload.dirtiness, 100)
	setBar(SideFrame, "happinessbarfill", payload.happiness, tonumber(payload.happinessMax) or 100)

	local xpFill = findSideFrameObject("xpbarfill")
	if xpFill then
		local progress = math.clamp(tonumber(payload.levelProgress) or 0, 0, 1)
		xpFill.Size = UDim2.new(progress, 0, xpFill.Size.Y.Scale, xpFill.Size.Y.Offset)
		local xpText = xpFill:FindFirstChild("Text")
			or xpFill:FindFirstChild("Amount")
			or xpFill:FindFirstChildWhichIsA("TextLabel")
			or (xpFill.Parent and (xpFill.Parent:FindFirstChild("Text") or xpFill.Parent:FindFirstChild("Amount") or xpFill.Parent:FindFirstChildWhichIsA("TextLabel")))
		if xpText then
			if payload.xpInLevel and payload.xpForNext and payload.xpForNext ~= math.huge then
				xpText.Text = ("%d / %d XP"):format(math.max(0, payload.xpInLevel), math.max(1, math.floor(payload.xpForNext)))
			else
				xpText.Text = ("%d XP"):format(math.max(0, payload.xp or 0))
			end
		end
	end
end

local function getSelectedPetKeys()
	if CurrentlySelected == 0 then return nil, nil, nil end
	local selectedId = tostring(CurrentlySelected)
	local selectedPetFolder = Data.Pets:FindFirstChild(selectedId)
	local selectedPetName = selectedPetFolder and selectedPetFolder:FindFirstChild("PetName") and selectedPetFolder.PetName.Value or nil
	local selectedPetUid = getPetUidFromFolder(selectedPetFolder)
	return selectedId, selectedPetName, selectedPetUid
end



for _,v in Data.Pets:GetChildren() do -- load pets on join
	coroutine.wrap(function()
		AddPet(v)
	end)()
end


function UpdateCounters()
	PetFrame.InventoryCounters.Storage.Text = #Player.Data.Pets:GetChildren().."/"..Multipliers.GetMaxPetsStorage(Player)
end

UpdateCounters()

coroutine.wrap(function()
	task.wait(0.5)
	SortInventory() -- made it wait 0.5 seconds before it sorted inventory because the pets are not yet loaded
end)()

function OnPetAdded(Child) -- this function is ran when a pet is added, which updates the counters & adds a new pet ui instance
	UpdateCounters()
	AddPet(Child)
	if SellObjectHolder then
		AddPet(Child, nil, SellObjectHolder)
		SortInventory(nil, SellObjectHolder)
	end
	SortInventory()
end

function OnPetRemoved(Child)
	UpdateCounters()
	if tonumber(Child.Name) == tonumber(CurrentlySelected) then
		CurrentlySelected = 0
		setSideFrameOpen(false)
	end
	if PetFrame.MainFrame.ObjectHolder:FindFirstChild(Child.Name) then
		PetFrame.MainFrame.ObjectHolder[Child.Name]:Destroy()
	end
	if SellObjectHolder and SellObjectHolder:FindFirstChild(Child.Name) then
		SellObjectHolder[Child.Name]:Destroy()
	end
	SellSlotByPetId[Child.Name] = nil
	if OpenSellFramePetId == tostring(Child.Name) then
		OpenSellFramePetId = nil
	end
	SortInventory()
	if SellObjectHolder then
		SortInventory(nil, SellObjectHolder)
	end
end

Data.Pets.ChildAdded:Connect(OnPetAdded)
Data.Pets.ChildRemoved:Connect(OnPetRemoved)

if SellObjectHolder then
	for _, petFolder in Data.Pets:GetChildren() do
		coroutine.wrap(function()
			AddPet(petFolder, nil, SellObjectHolder)
		end)()
	end
	coroutine.wrap(function()
		task.wait(0.5)
		SortInventory(nil, SellObjectHolder)
	end)()
end


Player.NonSaveValues.PetsEquipped.Changed:Connect(UpdateCounters) -- if player equips a pet

-- Pet Sideframe scripts

if PetStateEvent then
	local function requestOwnedPetStates()
		pcall(function()
			PetStateEvent:FireServer("RequestOwnedPetsState")
		end)
	end
	
	requestOwnedPetStates()
	task.spawn(function()
		while true do
			task.wait(6)
			requestOwnedPetStates()
		end
	end)
	
	PetStateEvent.OnClientEvent:Connect(function(action, petModel, payload)
		if action ~= "UpdatePetState" or not payload then return end

		local payloadId = tostring(payload.petName or "")
		local modelName = petModel and tostring(petModel.Name) or ""
		local payloadUid = tostring(payload.petUid or "")
		local payloadInventoryId = tostring(payload.inventoryPetId or "")
		if payloadId ~= "" then
			CachedPetStateByKey[payloadId] = payload
		end
		if modelName ~= "" then
			CachedPetStateByKey[modelName] = payload
		end
		if payloadUid ~= "" then
			CachedPetStateByKey[payloadUid] = payload
			CachedPetStateByKey["inv:"..payloadUid] = payload
		end
		if payloadInventoryId ~= "" then
			CachedPetStateByKey[payloadInventoryId] = payload
			CachedPetStateByKey["invId:"..payloadInventoryId] = payload

			local petFolder = Data.Pets:FindFirstChild(payloadInventoryId)
			local sellSlot = SellSlotByPetId[payloadInventoryId]
			if petFolder and sellSlot then
				updateSellSlotText(petFolder, sellSlot)
			end
		end

		local selectedPetId, selectedPetName, selectedPetUid = getSelectedPetKeys()
		if not selectedPetId then return end
		
		if payloadInventoryId ~= "" then
			if payloadInventoryId ~= selectedPetId then return end
			updateSideFrameState(payload)
			return
		end
		if selectedPetUid and selectedPetUid ~= "" then
			if payloadUid ~= selectedPetUid then return end
			updateSideFrameState(payload)
			return
		end


		local payloadCompareId = tostring(payload.petName or (petModel and petModel.Name) or "")
		if payloadCompareId ~= selectedPetId
			and payloadCompareId ~= tostring(selectedPetName)
			and modelName ~= selectedPetId
			and modelName ~= tostring(selectedPetName) then
			return
		end

		updateSideFrameState(payload)
	end)
end

--// Toys Inventory + Pets/Toys menu switching
local function resolveToyFrameRoot()
	if not Frames then return nil end
	local petsFrame = Frames:FindFirstChild("Pets")
	if not petsFrame then return nil end
	return petsFrame
end

local ToySlotById = {}
local ToyFolderConnections = {}

local function getToyStorageFolder()
	if not Data then return nil end
	return Data:FindFirstChild("Toys")
end

local function getToyNameFromFolder(toyFolder)
	if not toyFolder then return nil end
	local itemType = toyFolder:FindFirstChild("ItemType")
	if itemType and tostring(itemType.Value) ~= "Toy" and toyFolder:FindFirstChild("ItemName") then
		return nil
	end
	local itemName = toyFolder:FindFirstChild("ItemName")
	if itemName and type(itemName.Value) == "string" and itemName.Value ~= "" then
		return itemName.Value
	end
	local petName = toyFolder:FindFirstChild("PetName")
	if petName and type(petName.Value) == "string" and petName.Value ~= "" then
		return petName.Value
	end
	return nil
end

local function getToyTemplate(toyName)
	if not toyName then return nil end
	local toysFolder = ReplicatedStorage:FindFirstChild("Toys")
	if toysFolder and toysFolder:FindFirstChild(toyName) then
		return toysFolder[toyName]
	end
	local accessoriesFolder = ReplicatedStorage:FindFirstChild("Accessories")
	if accessoriesFolder and accessoriesFolder:FindFirstChild(toyName) then
		return accessoriesFolder[toyName]
	end
	local petsFolder = ReplicatedStorage:FindFirstChild("Pets")
	if petsFolder and petsFolder:FindFirstChild(toyName) then
		return petsFolder[toyName]
	end
	return nil
end

local function getToysObjectHolder()
	local petsFrame = resolveToyFrameRoot()
	local toysMainFrame = petsFrame and petsFrame:FindFirstChild("ToysMainFrame")
	if not toysMainFrame then return nil end
	return toysMainFrame:FindFirstChild("ObjectHolder")
end

local function getAccessoriesObjectHolder()
	local petsFrame = resolveToyFrameRoot()
	local accessoriesMainFrame = petsFrame and petsFrame:FindFirstChild("AccessoriesMainFrame")
	if not accessoriesMainFrame then return nil end
	return accessoriesMainFrame:FindFirstChild("ObjectHolder")
end


getPrimaryPartForDisplay = function(instance)
	if not instance then return nil end
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance:FindFirstChild("MainPart") or instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

getDisplaySize = function(instance)
	if not instance then return Vector3.new(2, 2, 2) end
	if instance:IsA("Model") then
		return instance:GetExtentsSize()
	end
	if instance:IsA("BasePart") then
		return instance.Size
	end
	return Vector3.new(2, 2, 2)
end

local function createToySlot(toyFolder)
	local objectHolder = getToysObjectHolder()
	if not objectHolder or not toyFolder then return end
	if objectHolder:FindFirstChild(toyFolder.Name) then return end
	local itemType = toyFolder:FindFirstChild("ItemType")
	if itemType and tostring(itemType.Value) ~= "Toy" then return end

	local toyName = getToyNameFromFolder(toyFolder)
	if not toyName then return end
	local toyTemplate = getToyTemplate(toyName)
	if not toyTemplate then
		warn(("[ToyInventory] Missing toy template for '%s'"):format(tostring(toyName)))
		return
	end

	local slotTemplate = script:FindFirstChild("PetTemplate")
	if not slotTemplate then return end

	local newSlot = slotTemplate:Clone()
	newSlot.Name = toyFolder.Name
	newSlot.Parent = objectHolder
	ToySlotById[toyFolder.Name] = newSlot

	if newSlot:FindFirstChild("Equipped") then
		newSlot.Equipped.Visible = false
	end

	local titleLabel = newSlot:FindFirstChild("Name") or newSlot:FindFirstChild("Title")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = toyName or "Toy"
	end

	local model = toyTemplate:Clone()
	model.Parent = newSlot.Display
	local mainPart = getPrimaryPartForDisplay(model)
	if not mainPart then
		newSlot:Destroy()
		ToySlotById[toyFolder.Name] = nil
		return
	end

	local pos = mainPart.Position
	local camera = Instance.new("Camera")
	newSlot.Display.CurrentCamera = camera
	if model:IsA("Model") then
		model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(180), 0))
	else
		model.CFrame = model.CFrame * CFrame.Angles(0, math.rad(180), 0)
	end
	camera.CFrame = CFrame.new(Vector3.new(pos.X + getDisplaySize(model).X * 1.5, pos.Y, pos.Z + 1), pos)

	local equippedValue = toyFolder:FindFirstChild("Equipped")
	if equippedValue and newSlot:FindFirstChild("Equipped") then
		newSlot.Equipped.Visible = equippedValue.Value == true
		ToyFolderConnections[toyFolder] = ToyFolderConnections[toyFolder] or {}
		table.insert(ToyFolderConnections[toyFolder], equippedValue.Changed:Connect(function()
			if newSlot and newSlot.Parent and newSlot:FindFirstChild("Equipped") then
				newSlot.Equipped.Visible = equippedValue.Value == true
			end
		end))
	end

	if newSlot:FindFirstChild("Button") and newSlot.Button:IsA("GuiButton") then
		newSlot.Button.MouseButton1Click:Connect(function()
			Remotes.Pet:FireServer("EquipToy", tostring(toyFolder.Name))
			showInventoryItemSideFrame(toyName, toyTemplate, getItemInfoText(toyFolder, toyTemplate))
			Utilities.Audio.PlayAudio("Click")
		end)
		HoverGuiController.bind(newSlot.Button, toyFolder, "Hover5", function(itemFolder)
			return getToyNameFromFolder(itemFolder)
		end, function(itemFolder, template)
			return getItemInfoText(itemFolder, template)
		end)
	end
end

local function removeToySlot(toyFolder)
	if not toyFolder then return end
	if ToyFolderConnections[toyFolder] then
		for _, conn in ipairs(ToyFolderConnections[toyFolder]) do
			if conn and conn.Disconnect then
				conn:Disconnect()
			end
		end
		ToyFolderConnections[toyFolder] = nil
	end
	local holder = getToysObjectHolder()
	if holder and holder:FindFirstChild(toyFolder.Name) then
		holder[toyFolder.Name]:Destroy()
	end
	ToySlotById[toyFolder.Name] = nil
end

local AccessorySlotById = {}
local AccessoryFolderConnections = {}

local function getAccessoryStorageFolder()
	if not Data then return nil end
	return Data:FindFirstChild("Accessories")
end

local function getAccessoryTemplate(itemName)
	if not itemName then return nil end
	local accessoriesFolder = ReplicatedStorage:FindFirstChild("Accessories")
	if accessoriesFolder and accessoriesFolder:FindFirstChild(itemName) then
		return accessoriesFolder[itemName]
	end
	return nil
end

local function createAccessorySlot(accessoryFolder)
	local objectHolder = getAccessoriesObjectHolder()
	if not objectHolder or not accessoryFolder then return end
	if objectHolder:FindFirstChild(accessoryFolder.Name) then return end
	local itemType = accessoryFolder:FindFirstChild("ItemType")
	if itemType and tostring(itemType.Value) ~= "Accessory" then return end

	local itemNameValue = accessoryFolder:FindFirstChild("ItemName")
	local itemName = itemNameValue and tostring(itemNameValue.Value) or ""
	if itemName == "" then return end

	local template = getAccessoryTemplate(itemName)
	if not template then
		warn(("[AccessoryInventory] Missing accessory template for '%s'"):format(itemName))
		return
	end

	local slotTemplate = script:FindFirstChild("PetTemplate")
	if not slotTemplate then return end

	local newSlot = slotTemplate:Clone()
	newSlot.Name = accessoryFolder.Name
	newSlot.Parent = objectHolder
	AccessorySlotById[accessoryFolder.Name] = newSlot

	local titleLabel = newSlot:FindFirstChild("Name") or newSlot:FindFirstChild("Title")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = itemName
	end

	local model = template:Clone()
	model.Parent = newSlot.Display
	local mainPart = getPrimaryPartForDisplay(model)
	if not mainPart then
		newSlot:Destroy()
		AccessorySlotById[accessoryFolder.Name] = nil
		return
	end

	local pos = mainPart.Position
	local camera = Instance.new("Camera")
	newSlot.Display.CurrentCamera = camera
	if model:IsA("Model") then
		model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(180), 0))
	else
		model.CFrame = model.CFrame * CFrame.Angles(0, math.rad(180), 0)
	end
	camera.CFrame = CFrame.new(Vector3.new(pos.X + getDisplaySize(model).X * 1.5, pos.Y, pos.Z + 1), pos)

	local equippedValue = accessoryFolder:FindFirstChild("Equipped")
	if equippedValue and newSlot:FindFirstChild("Equipped") then
		newSlot.Equipped.Visible = equippedValue.Value == true
		AccessoryFolderConnections[accessoryFolder] = AccessoryFolderConnections[accessoryFolder] or {}
		table.insert(AccessoryFolderConnections[accessoryFolder], equippedValue.Changed:Connect(function()
			if newSlot and newSlot.Parent and newSlot:FindFirstChild("Equipped") then
				newSlot.Equipped.Visible = equippedValue.Value == true
			end
		end))
	elseif newSlot:FindFirstChild("Equipped") then
		newSlot.Equipped.Visible = false
	end
	if newSlot:FindFirstChild("Button") and newSlot.Button:IsA("GuiButton") then
		newSlot.Button.MouseButton1Click:Connect(function()
			showInventoryItemSideFrame(itemName, template, getItemInfoText(accessoryFolder, template))
			Utilities.Audio.PlayAudio("Click")
		end)
		HoverGuiController.bind(newSlot.Button, accessoryFolder, "Hover5", function()
			return itemName
		end, function(itemFolder, template)
			return getItemInfoText(itemFolder, template)
		end)
	end
end

local function removeAccessorySlot(accessoryFolder)
	if not accessoryFolder then return end
	if AccessoryFolderConnections[accessoryFolder] then
		for _, conn in ipairs(AccessoryFolderConnections[accessoryFolder]) do
			if conn and conn.Disconnect then
				conn:Disconnect()
			end
		end
		AccessoryFolderConnections[accessoryFolder] = nil
	end
	local holder = getAccessoriesObjectHolder()
	if holder and holder:FindFirstChild(accessoryFolder.Name) then
		holder[accessoryFolder.Name]:Destroy()
	end
	AccessorySlotById[accessoryFolder.Name] = nil
end

local function wirePetsToysMenu()
	local petsFrame = resolveToyFrameRoot()
	if not petsFrame then return end

	local mainFrame = petsFrame:FindFirstChild("MainFrame")
	local toysFrame = petsFrame:FindFirstChild("ToysMainFrame")
	local accessoriesFrame = petsFrame:FindFirstChild("AccessoriesMainFrame")
	local menusHolder = petsFrame:FindFirstChild("OtherMenusHolder")
	if not mainFrame or not toysFrame or not menusHolder then return end

	local titleFrameLabel = petsFrame:FindFirstChild("TitleFrame")

	local function resolveMenuButton(container, legacyName, frameName)
		if not container then return nil end
		local button = container:FindFirstChild(legacyName)
		if button and button:IsA("GuiButton") then
			return button
		end

		local frameButtonContainer = container:FindFirstChild(frameName .. "FrameButton")
		if frameButtonContainer then
			if frameButtonContainer:IsA("GuiButton") then
				return frameButtonContainer
			end

			for _, desc in ipairs(frameButtonContainer:GetDescendants()) do
				if desc:IsA("GuiButton") then
					return desc
				end
			end
		end

		return nil
	end

	local petsButton = resolveMenuButton(menusHolder, "PetsButton", "Pets")
	local toysButton = resolveMenuButton(menusHolder, "ToysButton", "Toys")
	local accessoriesButton = resolveMenuButton(menusHolder, "AccessoriesButton", "Accessories")

	local function showFrame(frameName)
		CurrentlySelected = 0
		setSideFrameOpen(false)

		if frameName == "Pets" then
			setPetBarsVisible(true)
		end

		setSideFrameInfoLabel("")

		if titleFrameLabel and titleFrameLabel:IsA("TextLabel") then
			if frameName == "Toys" then
				titleFrameLabel.Text = "Toys"
			elseif frameName == "Accessories" then
				titleFrameLabel.Text = "Accessories"
			else
				titleFrameLabel.Text = "Brainrots"
			end
		end

		mainFrame.Visible = frameName == "Pets"
		toysFrame.Visible = frameName == "Toys"
		if accessoriesFrame then
			accessoriesFrame.Visible = frameName == "Accessories"
		end
	end

	showFrame("Pets") -- default view

	if petsButton and petsButton:IsA("GuiButton") and not petsButton:GetAttribute("_Wired") then
		petsButton:SetAttribute("_Wired", true)
		petsButton.MouseButton1Click:Connect(function()
			showFrame("Pets")
			Utilities.Audio.PlayAudio("Click")
		end)
	end

	if toysButton and toysButton:IsA("GuiButton") and not toysButton:GetAttribute("_Wired") then
		toysButton:SetAttribute("_Wired", true)
		toysButton.MouseButton1Click:Connect(function()
			showFrame("Toys")
			Utilities.Audio.PlayAudio("Click")
		end)
	end

	if accessoriesButton and accessoriesButton:IsA("GuiButton") and not accessoriesButton:GetAttribute("_Wired") then
		accessoriesButton:SetAttribute("_Wired", true)
		accessoriesButton.MouseButton1Click:Connect(function()
			showFrame("Accessories")
			Utilities.Audio.PlayAudio("Click")
		end)
	end
end

local function bindToysFolder(toysFolder)
	if not toysFolder then return end
	for _, toyFolder in ipairs(toysFolder:GetChildren()) do
		coroutine.wrap(function()
			createToySlot(toyFolder)
		end)()
	end

	toysFolder.ChildAdded:Connect(function(child)
		createToySlot(child)
	end)

	toysFolder.ChildRemoved:Connect(function(child)
		removeToySlot(child)
	end)
end

local function bindAccessoriesFolder(accessoriesFolder)
	if not accessoriesFolder then return end
	for _, accessoryFolder in ipairs(accessoriesFolder:GetChildren()) do
		coroutine.wrap(function()
			createAccessorySlot(accessoryFolder)
		end)()
	end

	accessoriesFolder.ChildAdded:Connect(function(child)
		createAccessorySlot(child)
	end)

	accessoriesFolder.ChildRemoved:Connect(function(child)
		removeAccessorySlot(child)
	end)
end

local toysFolder = getToyStorageFolder()
if toysFolder then
	bindToysFolder(toysFolder)
elseif Data then
	Data.ChildAdded:Connect(function(child)
		if child and child.Name == "Toys" and child:IsA("Folder") then
			bindToysFolder(child)
		end
	end)
end

local accessoriesFolder = getAccessoryStorageFolder()
if accessoriesFolder then
	bindAccessoriesFolder(accessoriesFolder)
elseif Data then
	Data.ChildAdded:Connect(function(child)
		if child and child.Name == "Accessories" and child:IsA("Folder") then
			bindAccessoriesFolder(child)
		end
	end)
end

wirePetsToysMenu()

--// Egg Preview
local PreviewFrame = UI.PreviewFrame
local DefaultSize = PreviewFrame.Size
local CurrentTarget = PreviewFrame.CurrentTarget
PreviewFrame.Size = UDim2.new(0.2,0,0.2,0)

function FindClosestEgg(EggsAvailable)
	local CurrentClosest, ClosestDistance = nil, 100

	for _,Egg in EggsAvailable do
		local EggModel = workspace.Map.Eggs[Egg]
		local mag = (EggModel:GetPivot().Position-Player.Character.HumanoidRootPart.Position).Magnitude
		if mag <= ClosestDistance then
			CurrentClosest = EggModel
			ClosestDistance = mag
		end
	end
	return CurrentClosest
end

local IsClosing = false -- so it doesnt ruin the animation

local function getDisplayTemplate(itemName)
	local accessories = ReplicatedStorage:FindFirstChild("Accessories")
	if accessories and accessories:FindFirstChild(itemName) then
		return accessories[itemName]
	end

	local toys = ReplicatedStorage:FindFirstChild("Toys")
	if toys and toys:FindFirstChild(itemName) then
		return toys[itemName]
	end

	local pets = ReplicatedStorage:FindFirstChild("Pets")
	if pets and pets:FindFirstChild(itemName) then
		return pets[itemName]
	end

	return nil
end

local function getTemplateRarity(itemName)
	local template = getDisplayTemplate(itemName)
	local settings = template and template:FindFirstChild("Settings")
	local rarity = settings and settings:FindFirstChild("Rarity")
	return rarity and tostring(rarity.Value) or "Common"
end

local function getPrimaryPart(instance)
	if not instance then return nil end
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance:FindFirstChild("MainPart") or instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function getExtentsSize(instance)
	if not instance then return Vector3.new(2, 2, 2) end
	if instance:IsA("Model") then
		return instance:GetExtentsSize()
	end
	if instance:IsA("BasePart") then
		return instance.Size
	end
	return Vector3.new(2, 2, 2)
end

local function rotateForViewport(instance, yawDegrees)
	local primary = getPrimaryPart(instance)
	if not primary then return end
	if instance:IsA("Model") then
		instance:PivotTo(instance:GetPivot() * CFrame.Angles(0, math.rad(yawDegrees), 0))
	else
		instance.CFrame = instance.CFrame * CFrame.Angles(0, math.rad(yawDegrees), 0)
	end
end

local function pivotToCamera(instance, camera, xValue, yValue, zValue, yawDegrees, rollDegrees)
	if not instance or not camera then return end
	local offset = CFrame.new(xValue, yValue, zValue)
	local rotation = CFrame.Angles(math.rad(0), math.rad(yawDegrees or 0), math.rad(rollDegrees or 0))
	if instance:IsA("Model") then
		instance:PivotTo(camera:GetRenderCFrame() * offset * rotation)
	else
		local primary = getPrimaryPart(instance)
		if primary then
			primary.CFrame = camera:GetRenderCFrame() * offset * rotation
		end
	end
end


function FindEgg()
	if not Player.Character:FindFirstChild("HumanoidRootPart") or not Player.Character:FindFirstChild("Humanoid") or Player.Character.Humanoid.Health == 0 then return end

	local Camera = workspace.CurrentCamera
	local EggsAvailable = {}
	local CameraRatio = ((Camera.CFrame.Position - Camera.Focus.Position).Magnitude)/11

	for _,Egg in workspace.Map.Eggs:GetChildren() do
		if Egg == nil then continue end
		if not Egg:FindFirstChild("EggModel") then warn(Egg.Name.." does not have an EggModel") end

		local mag = (Egg:GetPivot().Position-Player.Character.HumanoidRootPart.Position).Magnitude
		if mag <= 12 then
			EggsAvailable[#EggsAvailable + 1] = Egg.Name
		end
	end

	local SetVisibility = #EggsAvailable >= 1 -- if its 0 then its already false

	if SetVisibility then -- a egg(s) is in distance
		local Egg = #EggsAvailable > 1 and FindClosestEgg(EggsAvailable) or workspace.Map.Eggs[EggsAvailable[1]]
		local WSP = workspace.CurrentCamera:WorldToScreenPoint(Egg:GetPivot().Position)
		PreviewFrame.Position = UDim2.new(0,WSP.X,0,WSP.Y)
		CurrentTarget.Value = Egg.Name
	else
		CurrentTarget.Value = "None"
	end

	if Player.NonSaveValues.IsOpeningEgg.Value then
		SetVisibility = false -- if you are opening an egg itll auto close the previewframe
	end

	--// Make the previewframe visible
	if SetVisibility and not PreviewFrame.Visible then
		PreviewFrame.Visible = true
		Utilities.Tween.Tween(PreviewFrame, {Speed = 0.15}, {Size = UDim2.new(DefaultSize.X.Scale/CameraRatio, DefaultSize.X.Offset, DefaultSize.Y.Scale/CameraRatio, DefaultSize.Y.Offset)})	
	elseif not SetVisibility and PreviewFrame.Visible and not IsClosing then -- set to invisible, while is visible & isnt closing
		IsClosing = true
		Utilities.Tween.Tween(PreviewFrame, {Speed = 0.15}, {Size = UDim2.new(0.2,0,0.2,0)})	
		task.wait(0.15)
		PreviewFrame.Visible = false
		IsClosing = false
	end
end

function UpdatePreviewFrame()
	if CurrentTarget.Value ~= "None" then
		local Egg = CurrentTarget.Value
		PreviewFrame.EggInfo.EggName.Text = Egg

		if not ReplicatedStorage.Eggs:FindFirstChild(Egg) then print(Egg.." does not have settings in ReplicatedStorage.Eggs!") return end

		local EggInfo = ReplicatedStorage.Eggs[Egg]

		local IsRobuxEgg = EggInfo:FindFirstChild("ProductId")
		if IsRobuxEgg then
			PreviewFrame.EggInfo.Price.Text = "Costs \u{E002}"..Utilities.Short.en(EggInfo.Cost.Value)
		else
			PreviewFrame.EggInfo.Price.Text = "Costs "..Utilities.Short.en(EggInfo.Cost.Value)
		end

		PreviewFrame.Buttons.Triple.Visible = not IsRobuxEgg
		PreviewFrame.Buttons.Auto.Visible = not IsRobuxEgg

		--// This part gets the item chances
		local Pets, TotalWeight = {}, 0

		for _, Pet in EggInfo.Pets:GetChildren() do
			table.insert(Pets, {Pet.Name, Pet.Value})
		end

		table.sort(Pets, function(a,b)
			return a[2] > b[2]
		end)

		local BaseChance = Pets[1][2] -- this is the most common pet

		local LuckMultiplier = Multipliers.GetLuckMultiplier(Player)

		for _,v in Pets do
			local Chance = math.min(v[2] * LuckMultiplier, BaseChance) -- so if the easiest pet is 70%, all pets will go towards 70% 
			TotalWeight += Chance
			v[2] = Chance
		end

		for i = 1,9 do
			local PetInfo = Pets[i]
			local PetSlot = PreviewFrame.PetChances.List["Pet"..i]
			PetSlot.Visible = PetInfo ~= nil

			if PetInfo == nil then continue end

			PetSlot.Rarity.Text = getTemplateRarity(PetInfo[1])
			PetSlot.Percentage.Text = Utilities.Short.en(100/TotalWeight * PetInfo[2]).."%"
			PetSlot.PetName.Value = PetInfo[1]

			local displayTemplate = getDisplayTemplate(PetInfo[1])
			if not displayTemplate then
				PetSlot.Visible = false
				continue
			end

			local PetModel = displayTemplate:Clone()
			PetModel.Parent = PetSlot.Pet

			local mainPart = getPrimaryPart(PetModel)
			if not mainPart then
				PetSlot.Visible = false
				PetModel:Destroy()
				continue
			end

			local Pos = mainPart.Position
			local Camera = Instance.new("Camera")
			PetSlot.Pet.CurrentCamera = Camera
			rotateForViewport(PetModel, 180)
			Camera.CFrame = CFrame.new(Vector3.new(Pos.X + getExtentsSize(PetModel).X * 1.5, Pos.Y, Pos.Z + 1), Pos)
		end
	end
end

CurrentTarget.Changed:Connect(UpdatePreviewFrame)

--// Egg Hatching and VIEWPORT
local IsAutoOpening = false

function HatchEgg(Egg: string, Result: string, Offset:number)
	local OpeningTime = 3

	local NewViewport = script.EggViewport:Clone()
	NewViewport.Parent = UI.OpenEgg

	Player.CameraMinZoomDistance = 15
	Frames.Visible = false
	UI[GameSettings.ButtonSide.Value].Buttons.Visible = false

	local Clone = workspace.Map.Eggs[Egg].EggModel:Clone()
	Clone:ScaleTo(0.5)
	Clone.Parent = workspace

	local Rot, X, Y, Z = Instance.new("NumberValue"), Instance.new("NumberValue"), Instance.new("NumberValue"), Instance.new("NumberValue")
	Rot.Value = 30 Z.Value = -4 X.Value = 10

	local Camera = workspace.CurrentCamera
	local PL = Instance.new("PointLight")
	PL.Shadows = false PL.Range = 4 PL.Brightness *= 1.5
	PL.Parent = Clone.Egg

	Clone:PivotTo(Camera:GetRenderCFrame()*CFrame.new(X,Y,Z))
	local CameraConnection1 = RunService.Heartbeat:Connect(function()
		local X, Y, Z = X.Value, Y.Value, Z.Value
		Clone:PivotTo(Camera:GetRenderCFrame()*CFrame.new(X,Y,Z)*CFrame.Angles(0,0,math.rad(Rot.Value)))
	end)

	local CameraConnection2 = Camera:GetPropertyChangedSignal("CFrame"):Connect(function()
		local X, Y, Z = X.Value, Y.Value, Z.Value
		Clone:PivotTo(Camera:GetRenderCFrame()*CFrame.new(X,Y,Z)*CFrame.Angles(0,0,math.rad(Rot.Value)))
	end)

	local TweenIn = TweenService:Create(X, TweenInfo.new(OpeningTime*0.2, Enum.EasingStyle.Back), {Value = Offset})
	TweenIn:Play()

	local RotTweenIn = TweenService:Create(Rot, TweenInfo.new(OpeningTime*0.2, Enum.EasingStyle.Back), {Value = 0})
	RotTweenIn:Play()

	-- add an audio for the egg flying in
	TweenIn.Completed:Wait()

	local Eggdelay = 0.075
	for i = 1,(OpeningTime * 1.5) + 1 do
		local Tween = TweenService:Create(Rot, TweenInfo.new(Eggdelay, Enum.EasingStyle.Back), {Value = -6})
		-- add an audio for rotating here
		Tween:Play()
		Tween.Completed:Wait()

		Eggdelay -= .005
	end

	CameraConnection1:Disconnect()
	CameraConnection2:Disconnect()	
	Clone:Destroy()	

	-- Now we're going to show the hatched item

	local hatchedTemplate = getDisplayTemplate(Result)
	if not hatchedTemplate then
		warn(("[EggHatchClient] Missing toy/pet template for '%s'"):format(tostring(Result)))
		NewViewport:Destroy()
		Player.CameraMinZoomDistance = 0.5
		UI[GameSettings.ButtonSide.Value].Buttons.Visible = true
		Frames.Visible = true
		return
	end

	local PetModel = hatchedTemplate:Clone()
	if PetModel:IsA("Model") then
		PetModel:ScaleTo(0.6)
	end
	PetModel.Parent = workspace
	local petMainPart = getPrimaryPart(PetModel)
	if not petMainPart then
		warn(("[EggHatchClient] Hatched toy '%s' has no BasePart/MainPart"):format(tostring(Result)))
		PetModel:Destroy()
		NewViewport:Destroy()
		Player.CameraMinZoomDistance = 0.5
		UI[GameSettings.ButtonSide.Value].Buttons.Visible = true
		Frames.Visible = true
		return
	end

	local autoDeleteValue = Data.AutoDelete:FindFirstChild(Result)
	NewViewport.Deleted.Visible = autoDeleteValue and autoDeleteValue.Value or false
	NewViewport.PetName.Text = Result
	NewViewport.PetName.Visible = true
	NewViewport.PetRarity.Text = getTemplateRarity(Result)
	NewViewport.PetRarity.Visible = true

	local PL = Instance.new("PointLight")
	PL.Shadows = false PL.Range = 4 PL.Brightness *= 2
	PL.Parent = petMainPart

	X.Value = Offset Y.Value = 0 Z.Value = -4 Rot.Value = 175
	local CameraConnection1 = RunService.Heartbeat:Connect(function()
		local X, Y, Z = X.Value, Y.Value, Z.Value
		pivotToCamera(PetModel, Camera, X, Y, Z, Rot.Value, 0)
	end)

	local CameraConnection2 = Camera:GetPropertyChangedSignal("CFrame"):Connect(function()
		local X, Y, Z = X.Value, Y.Value, Z.Value
		pivotToCamera(PetModel, Camera, X, Y, Z, Rot.Value, 0)
	end)

	task.wait(OpeningTime*0.25)

	NewViewport:TweenPosition(UDim2.new(NewViewport.Position.X.Scale, 0, NewViewport.Position.Y.Scale + 10, 0), Enum.EasingDirection.InOut, Enum.EasingStyle.Quad, OpeningTime * 0.1)
	TweenService:Create(Y, TweenInfo.new(OpeningTime*0.15, Enum.EasingStyle.Back), {Value = -5}):Play()
	NewViewport.Deleted.Visible = false
	NewViewport.PetName.Visible = false
	NewViewport.PetRarity.Visible = false
	task.wait(OpeningTime * 0.15)

	CameraConnection1:Disconnect()
	CameraConnection2:Disconnect()
	X:Destroy() Y:Destroy() Z:Destroy() Rot:Destroy()

	PetModel:Destroy()
	NewViewport:Destroy()

	Player.CameraMinZoomDistance = 0.5
	UI[GameSettings.ButtonSide.Value].Buttons.Visible = true
	Frames.Visible = true	
end

Remotes.Egg.OnClientInvoke = HatchEgg

function SingleEgg()
	local Egg = CurrentTarget.Value

	local EggInfo = ReplicatedStorage.Eggs[Egg]

	if not EggInfo:FindFirstChild("ProductId") then
		local Result = Remotes.Egg:InvokeServer(Egg, 1)

		if Result ~= nil then
			HatchEgg(Egg, Result[1], 0)
		end
	else
		MarketPlaceService:PromptProductPurchase(Player, EggInfo.ProductId.Value)
	end
end

function TripleEgg()
	local Egg = CurrentTarget.Value

	local Result = Remotes.Egg:InvokeServer(Egg, 3)

	if Result ~= nil then
		for i = 1,#Result do
			coroutine.wrap(function()
				local Position = (i - 2) * 3
				HatchEgg(Egg, Result[i], Position)
			end)()
		end
	end
end

local function ChooseEggAmount(Egg)
	local EggInfo = ReplicatedStorage.Eggs[Egg]

	local EggAmount = 1

	if ReplicatedStorage.Gamepasses:FindFirstChild("TripleEgg") and not Player.Data.Gamepasses.TripleEgg.Value then 
		return EggAmount
	end -- triple egg is a gamepass that the player doesn't own, so open 1 egg

	if PlayerData.Currency.Value >= EggInfo.Cost.Value * 3 then
		EggAmount = 3
	end

	return EggAmount
end

function AutoEgg()
	if IsAutoOpening then return end

	if ReplicatedStorage.Gamepasses:FindFirstChild("AutoEgg") and not Player.Data.Gamepasses.AutoEgg.Value then 
		MarketPlaceService:PromptGamePassPurchase(ReplicatedStorage.Gamepasses.AutoEgg.Value)
		return
	end

	local Egg = CurrentTarget.Value	
	IsAutoOpening = true

	while true do
		if Player.NonSaveValues.IsOpeningEgg.Value then task.wait(0.1) continue end -- player is already opening an egg

		if CurrentTarget.Value == "None" or CurrentTarget.Value ~= Egg then
			IsAutoOpening = false
			break
		end

		local Result = Remotes.Egg:InvokeServer(Egg, ChooseEggAmount(Egg))

		if Result == nil then
			IsAutoOpening = false
			break
		end

		if #Result > 1 then
			for i = 1,#Result do
				coroutine.wrap(function()
					local Position = (i - 2) * 3
					HatchEgg(Egg, Result[i], Position)
				end)()
			end
		else
			HatchEgg(Egg, Result[1], 0)
		end

		task.wait(0.1)
	end
end

PreviewFrame.Buttons.Single.Click.MouseButton1Click:Connect(SingleEgg)
PreviewFrame.Buttons.Triple.Click.MouseButton1Click:Connect(TripleEgg)
PreviewFrame.Buttons.Auto.Click.MouseButton1Click:Connect(AutoEgg)

UserInputService.InputBegan:Connect(function(Input)
	if UserInputService:GetFocusedTextBox() ~= nil then return end

	if Input.KeyCode == Enum.KeyCode.E then SingleEgg() end
	if Input.KeyCode == Enum.KeyCode.R then TripleEgg() end
	if Input.KeyCode == Enum.KeyCode.T then AutoEgg() end
end)

--// Pet Follow
-- Credits to azypro777 for helping out with this part!
local Spacing, PetSize, MaxClimbHeight = 5, 3, 6

local RayParams = RaycastParams.new()
local RayDirection = Vector3.new(0, -500, 0)

local TempPets = Instance.new("Folder")
TempPets.Name = "PlayerPets"
TempPets.Parent = ReplicatedStorage

local function RearrangeTables(Pets, Rows, MaxRowCapacity)
	table.clear(Rows)
	local AmountOfRows = math.ceil(#Pets / MaxRowCapacity)
	for i = 1, AmountOfRows do
		table.insert(Rows, {})
	end
	for i, v in Pets do
		local Row = Rows[math.ceil(i / MaxRowCapacity)]
		table.insert(Row, v)
	end
end

local function GetRowWidth(Row, Pet)
	if Pet ~= nil then
		local MainPart = Pet:FindFirstChild("MainPart")

		if not MainPart then print("A pet equipped does not have a part called 'MainPart'") return end

		Pet.PrimaryPart = MainPart

		local SpacingBetweenPets = Spacing - MainPart.Size.X
		local RowWidth = 0

		if #Row == 1 then
			return 0
		end

		for i, v in Row do
			if i ~= #Row then
				RowWidth += MainPart.Size.X + SpacingBetweenPets
			else
				RowWidth += MainPart.Size.X
			end
		end

		return RowWidth
	end
end

function PetMovement()
	if not PlayerData.ShowOtherPets.Value then -- Show pets is false
		-- put the pets in "TempPets"
		for _, PetFolder in workspace.PlayerPets:GetChildren() do
			if PetFolder.Name == Player.Name then continue end 
			PetFolder.Parent = TempPets
		end
	else
		for _,v in TempPets:GetChildren() do
			v.Parent = workspace.PlayerPets
		end
	end

	for _, PlayerPets in workspace.PlayerPets:GetChildren() do
		local Character = Players[PlayerPets.Name].Character or Players[PlayerPets.Name].CharacterAdded:Wait()
		local HumanoidRootPart = Character.HumanoidRootPart

		local Pets, Rows = {}, {}		
		for _,Pet in PlayerPets:GetChildren() do
			table.insert(Pets, Pet)
		end

		RayParams.FilterDescendantsInstances = {workspace.PlayerPets, Character}
		local MaxRowCapacity = math.ceil(math.sqrt(#Pets))
		RearrangeTables(Pets, Rows, MaxRowCapacity)

		for i, Pet in Pets do
			local RowIndex = math.ceil(i / MaxRowCapacity)
			local Row = Rows[RowIndex]
			local RowWidth = GetRowWidth(Row, Pet)

			local XOffset = #Row == 1 and 0 or RowWidth/2 - Pet.PrimaryPart.Size.X/2
			local X = (table.find(Row, Pet) - 1) * Spacing
			local Z = RowIndex * Spacing
			local Y = 0

			local RayResult = workspace:Blockcast(Pet.PrimaryPart.CFrame + Vector3.new(0, MaxClimbHeight, 0), Pet.PrimaryPart.Size, RayDirection, RayParams)

			if RayResult then
				Y = RayResult.Position.Y + Pet.PrimaryPart.Size.Y/2
			end

			local TargetCFrame = CFrame.new(HumanoidRootPart.CFrame.X, 0, HumanoidRootPart.CFrame.Z) * HumanoidRootPart.CFrame.Rotation * CFrame.new(X - XOffset, Y, Z)
			local LerpedCFrame = Pet:GetPivot():Lerp(TargetCFrame, 0.1)
			Pet:PivotTo(LerpedCFrame)
		end
	end
end

--// Areas
function AreaDetection()
	while task.wait(0.1) do
		local Door = workspace.Map.Doors:FindFirstChild(tostring(PlayerData.BestZone.Value + 1))
		if not Door then task.wait(1) continue end -- Either max area or something went wrong

		local BoundBox = workspace:GetPartBoundsInBox(Door.CFrame, Door.Size + Vector3.new(2,2,2))

		for _,Part in BoundBox do
			if Part.Parent == Player.Character then
				if not Frames.Area.Visible then
					Utilities.ButtonHandler.OnClick(Frames.Area, UDim2.new(0.262,0,0.391,0))

					if ReplicatedStorage.Areas[Door.Name].Cost.Value ~= -1 then
						Frames.Area.Cost.Text = Utilities.Short.en(ReplicatedStorage.Areas[Door.Name].Cost.Value).." "..GameSettings.CurrencyName.Value
					else
						Frames.Area.Cost.Text = "Maxed"
					end
				end
				break
			end
		end
	end
end

coroutine.wrap(AreaDetection)()

function UpdateAllDoors()
	for _,Door in workspace.Map.Doors:GetChildren() do
		local IsVisible = PlayerData.BestZone.Value < tonumber(Door.Name)
		Door.Transparency = IsVisible and 0.35 or 1
		Door.CanCollide = IsVisible

		for _, Object in Door:GetDescendants() do
			if Object:IsA("TextLabel") then
				Object.TextTransparency = IsVisible and 0 or 1
			elseif Object:IsA("UIStroke") then
				Object.Transparency = IsVisible and 0 or 1
			end
		end
	end
end

UpdateAllDoors()
workspace.Map.Doors.ChildAdded:Connect(UpdateAllDoors)
PlayerData.BestZone.Changed:Connect(UpdateAllDoors)

-- Area Frame
Utilities.ButtonAnimations.Create(Frames.Area.Buy)

Frames.Area.Buy.Click.MouseButton1Click:Connect(function()
	Remotes.Area:FireServer()
	Utilities.Audio.PlayAudio("Click")
	task.wait(0.05)

	if Frames.Area.Visible then
		Utilities.ButtonHandler.OnClick(Frames.Area, UDim2.new(0,0,0,0))
	end 
end)

--// Tradng
local PlayerTradeTemplate = Frames.Trading.PlayerList.ObjectHolder.Template
PlayerTradeTemplate.Parent = script
PlayerTradeTemplate.Name = "PlayerTradeTemplate" -- this moves the template from the ui to the script (easier for people to edit :) 
local SendDefaultColor = PlayerTradeTemplate.Send.BackgroundColor3 -- the color of the button's default (incase a player changes the ui of it)

local TradeFrame = Frames.Trading
local PlayerTrade = TradeFrame.PlayerTrade

local TradeInfo = {}

local function AddPlayerToList(TargetPlayer)
	if Player ~= TargetPlayer then
		local Template = PlayerTradeTemplate:Clone()
		Utilities.ButtonAnimations.Create(Template.Send)

		if TargetPlayer.DisplayName == TargetPlayer.Name then
			Template.Title.Text = TargetPlayer.Name
		else
			Template.Title.Text = TargetPlayer.DisplayName .. " (@".. TargetPlayer.Name .. ")"
		end
		Template.Send.Click.MouseButton1Click:Connect(function()
			if Template.Send.Title.Text ~= "Sent" then
				Template.Send.Title.Text = "Sent"
				Template.Send.BackgroundColor3 = Color3.fromRGB(67, 130, 88)
				Remotes.Trading.RequestTrade:InvokeServer(TargetPlayer.Name)
				task.wait(2)
				Template.Send.Title.Text = "Send" -- change this if u have a different default text, such as "Request" instead of "Send"
				Template.Send.BackgroundColor3 = SendDefaultColor
			end
		end)

		Template.Name = TargetPlayer.Name
		Template.Parent = TradeFrame.PlayerList.ObjectHolder
	end
end

for _, TargetPlayer in Players:GetChildren() do
	AddPlayerToList(TargetPlayer)
end

Players.PlayerAdded:Connect(AddPlayerToList)

Players.PlayerRemoving:Connect(function(TargetPlayer)
	if Frames.Trading.PlayerList.ObjectHolder:FindFirstChild(TargetPlayer.Name) then
		Frames.Trading.PlayerList.ObjectHolder[TargetPlayer.Name]:Destroy()
	end
end)

Remotes.Trading.RequestTrade.OnClientInvoke = function(OtherPlayer) -- function is ran when someone sent you a trade request
	local NewTemplate = UI.TradeRequest:Clone()
	NewTemplate.TextLabel.Text = OtherPlayer.." has sent you a trade request!"

	Utilities.ButtonAnimations.Create(NewTemplate.Accept)
	NewTemplate.Accept.Button.MouseButton1Click:Connect(function()
		Utilities.Audio.PlayAudio("Click", 1)
		local Accepted = Remotes.Trading.StartTrade:InvokeServer(OtherPlayer)
		if Accepted then
			StartTrade(OtherPlayer)
			NewTemplate:Destroy()
		end
	end)

	Utilities.ButtonAnimations.Create(NewTemplate.Cancel)
	NewTemplate.Cancel.Button.MouseButton1Click:Connect(function()
		Utilities.Audio.PlayAudio("Click", 1)
		NewTemplate:Destroy()
	end)

	NewTemplate.Visible = true
	NewTemplate.Name = OtherPlayer
	NewTemplate.Parent = UI

	task.wait(10)
	NewTemplate:Destroy()
end

function StartTrade(OtherPlayer)	
	if not TradeFrame.Visible then
		Utilities.ButtonHandler.OnClick(TradeFrame, UDim2.new(0.359, 0, 0.414, 0))
	end

	TradeFrame.PlayerList.Visible = false
	PlayerTrade.Visible = true

	PlayerTrade.OtherPlayer.PlayerName.Text = OtherPlayer
	TradeInfo.OtherPlayer = OtherPlayer

	PlayerTrade.OtherPlayer.ReadyCover.Visible = false

	--// Clear Inventories Before Loading!
	for _, Frame in PlayerTrade.LocalPlayer.Inventory:GetChildren() do if Frame:IsA("Frame") then Frame:Destroy() end end
	for _, Frame in PlayerTrade.OtherPlayer.Inventory:GetChildren() do if Frame:IsA("Frame") then Frame:Destroy() end end
	PlayerTrade.OtherPlayer.Currency.TextLabel.Text = "0"

	--// Load Inventories
	local function PetClicked(Pet) -- whenever a pet in the inventory is clicked
		Pet.Button.MouseButton1Click:Connect(function()
			local Result = Remotes.Trading.ChangeOffer:InvokeServer(OtherPlayer, {OfferType = "Pet", ID = tonumber(Pet.Name)})
			print(Result)

			if Result == "Max" then 
				-- Max Storage, create a popup here
			elseif Result == "Added" then
				Pet.Equipped.Visible = true
			elseif Result == "Removed" then
				Pet.Equipped.Visible = false
			end
		end)
	end

	local SortTable1 = {}

	local function PetInfo(Player, Pet)
		local HoverUI = PlayerTrade.HoverDisplay

		Pet.MouseEnter:Connect(function()
			Utilities.Dropdown.Hover(Pet, HoverUI, PlayerTrade)

			local PetInstance = Player.Data.Pets[Pet.Name]
			HoverUI.Multiplier.Text = "x"..Utilities.Short.en(ReplicatedStorage.Pets[PetInstance.PetName.Value].Settings.Multiplier.Value)
			HoverUI.Rarity.Text = ReplicatedStorage.Pets[PetInstance.PetName.Value].Settings.Rarity.Value
			HoverUI.PetName.Text = PetInstance.PetName.Value
			HoverUI.ID.Text = "ID: "..Pet.Name
		end)
	end

	for _,v in Data.Pets:GetChildren() do -- load pets
		coroutine.wrap(function()
			local Pet = AddPet(v, SortTable1, PlayerTrade.LocalPlayer.Inventory)
			PetClicked(Pet)
			PetInfo(Player, Pet)
		end)()
	end

	SortInventory(SortTable1, PlayerTrade.LocalPlayer.Inventory)

	local SortTable2 = {}
	for _,v in Players[OtherPlayer].Data.Pets:GetChildren() do -- load pets
		coroutine.wrap(function()
			local Pet = AddPet(v, SortTable2, PlayerTrade.OtherPlayer.Inventory)
			PetInfo(Players[OtherPlayer], Pet)
		end)()
	end

	SortInventory(SortTable2, PlayerTrade.OtherPlayer.Inventory)
end

Remotes.Trading.StartTrade.OnClientInvoke = StartTrade

Remotes.Trading.TradeAction.OnClientInvoke = function(Args) -- function is ran when u add pets to a trade, add currency etc
	if Args.Option == "Cancel" then
		if TradeFrame.Visible then
			Utilities.ButtonHandler.OnClick(TradeFrame, TradeFrame.Size) --// close the trade
			PlayerTrade.Visible = false
			TradeFrame.PlayerList.Visible = true
		end
	elseif Args.Option == "Ready" then
		PlayerTrade.OtherPlayer.ReadyCover.Visible = Args.Option == "Ready" 
	elseif Args.Option == "Countdown" then
		PlayerTrade.OtherPlayer.ReadyCover.Visible = true

		if Args.Count == 0 then --// end trade
			PlayerTrade.TradeCountdown.Visible = false			

			if TradeFrame.Visible then
				Utilities.ButtonHandler.OnClick(TradeFrame, TradeFrame.Size) --// close the trade
				PlayerTrade.Visible = false
				TradeFrame.PlayerList.Visible = true
			end
		else
			PlayerTrade.TradeCountdown.Visible = true

			for i = Args.Count * 10, 1, -1 do
				if not Player.NonSaveValues.IsReady.Value then
					PlayerTrade.TradeCountdown.Visible = false
					break
				end
				PlayerTrade.TradeCountdown.Text = (i/10).." Seconds Left.."

				task.wait(0.1)
			end	

			PlayerTrade.TradeCountdown.Text = "Processing..."			
		end
	elseif Args.Option == "CountdownEnded" then
		PlayerTrade.TradeCountdown.Visible = false
	end
end

Remotes.Trading.ChangeOffer.OnClientInvoke = function(Action, Args) -- function is ran when u add pets to a trade, add currency etc
	if Action == "PetAdded" then
		PlayerTrade.OtherPlayer.Inventory[Args].Equipped.Visible = true
	elseif Action == "PetRemoved" then
		PlayerTrade.OtherPlayer.Inventory[Args].Equipped.Visible = false
	elseif Action == "TradeTokens" then
		PlayerTrade.OtherPlayer.Currency.TextLabel.Text = Args
	end
end

--// Cancel and Decline Buttons!
Utilities.ButtonAnimations.Create(PlayerTrade.OtherPlayer.Cancel)
PlayerTrade.OtherPlayer.Cancel.Button.MouseButton1Click:Connect(function()
	Utilities.Audio.PlayAudio("Click", 1)
	local Succes = Remotes.Trading.TradeAction:InvokeServer(TradeInfo.OtherPlayer, {Option = "Cancel"})
	if Succes and TradeFrame.Visible then
		Utilities.ButtonHandler.OnClick(TradeFrame, UDim2.new(TradeFrame.Size))
		PlayerTrade.Visible = false
		TradeFrame.PlayerList.Visible = true
	end	
end)

Utilities.ButtonAnimations.Create(PlayerTrade.OtherPlayer.Accept)
PlayerTrade.OtherPlayer.Accept.Button.MouseButton1Click:Connect(function()
	Utilities.Audio.PlayAudio("Click", 1)
	Remotes.Trading.TradeAction:InvokeServer(TradeInfo.OtherPlayer, {Option = "Ready"})
end)

Player.NonSaveValues.IsReady.Changed:Connect(function(Visible)
	PlayerTrade.LocalPlayer.ReadyCover.Visible = Visible
end)

--// Gem Shop
local Gemshop = ReplicatedStorage.GemShop
local Defaultwalkspeed = Player.Character.Humanoid.WalkSpeed
local MarketplaceService = game:GetService("MarketplaceService")

local BANK_OPEN_POSITION = UDim2.new(0.359, 0, 0.414, 0)
local PETS_WHILE_BANK_OPEN_POSITION = UDim2.new(0.095, 0, 0.414, 0)
local SELL_OPEN_POSITION = UDim2.new(0.359, 0, 0.414, 0)
local FOOD_OPEN_POSITION = UDim2.new(0.359, 0, 0.414, 0)

local openedPetFrameFromBank = false
local defaultPetsPosition = Frames.Pets.Position
local SellShopFrame = Frames:FindFirstChild("SellShop")
local FoodShopFrame = Frames:FindFirstChild("FoodShop")
local defaultSellPosition = SellShopFrame and SellShopFrame.Position or SELL_OPEN_POSITION
local defaultFoodShopPosition = FoodShopFrame and FoodShopFrame.Position or FOOD_OPEN_POSITION

local FoodShopRemotes = ReplicatedStorage:FindFirstChild("FoodShopRemotes")
local FoodRequestItems = FoodShopRemotes and FoodShopRemotes:FindFirstChild("RequestItems")
local FoodBuyItem = FoodShopRemotes and FoodShopRemotes:FindFirstChild("BuyItem")
local FoodTimerEvent = FoodShopRemotes and FoodShopRemotes:FindFirstChild("TimerEvent")
local FoodRestockShop = FoodShopRemotes and FoodShopRemotes:FindFirstChild("RestockShop")
local FoodUpdateShop = FoodShopRemotes and FoodShopRemotes:FindFirstChild("UpdateShop")

local foodProductInfoCache = {}
local ringDismissedWhileInside = {
	Gem = false,
	Bank = false,
	Sell = false,
	Food = false,
}

local function findDescendant(parent, childName)
	if not parent then return nil end
	return parent:FindFirstChild(childName, true)
end

local function shortenNumber(num)
	if num >= 1e12 then return string.format("%.2ft", num / 1e12)
	elseif num >= 1e9 then return string.format("%.2fb", num / 1e9)
	elseif num >= 1e6 then return string.format("%.2fm", num / 1e6)
	elseif num >= 1e3 then return string.format("%.2fk", num / 1e3)
	else return tostring(num)
	end
end

local function showPetsNextToBank()
	if not Frames.Pets.Visible then
		openedPetFrameFromBank = true
	end

	-- IMPORTANT: direct control, do NOT use ButtonHandler.OnClick for Pets here
	Frames.Pets:SetAttribute("CanDeletePets", false)
	Frames.Pets.Position = PETS_WHILE_BANK_OPEN_POSITION
	Frames.Pets.Visible = true
end

local function hideBankOpenedPets()
	if not openedPetFrameFromBank then return end
	openedPetFrameFromBank = false

	Frames.Pets.Visible = false
	Frames.Pets.Position = defaultPetsPosition
	Frames.Pets:SetAttribute("CanDeletePets", false)	
end

local function showPetsForSell()
	if SellShopFrame and not SellShopFrame.Visible then
		Utilities.ButtonHandler.OnClick(SellShopFrame, SELL_OPEN_POSITION)
	end

	Frames.Pets:SetAttribute("CanDeletePets", false)
end

local function hideSellShop()
	if not SellShopFrame or not SellShopFrame.Visible then return end
	Utilities.ButtonHandler.OnClick(SellShopFrame, SELL_OPEN_POSITION)
end

local function getFoodShopUi()
	if not FoodShopFrame then return nil end

	local scroll = findDescendant(FoodShopFrame, "ScrollArea")
	local template = scroll and findDescendant(scroll, "Template")
	if not scroll or not template then
		warn("[IngameShopsClient] FoodShop is missing ScrollArea/Template.")
		return nil
	end

	return {
		exitButton = findDescendant(FoodShopFrame, "ExitButton"),
		restockButton = findDescendant(FoodShopFrame, "RestockButton"),
		timerLabel = findDescendant(FoodShopFrame, "TimerLabel"),
		scroll = scroll,
		template = template,
	}
end

local foodUi = getFoodShopUi()

local function getCachedRobuxPrice(productId)
	if not productId then return nil end
	if foodProductInfoCache[productId] ~= nil then
		return foodProductInfoCache[productId]
	end

	local success, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)
	local robuxPrice = success and info and info.PriceInRobux or nil
	foodProductInfoCache[productId] = robuxPrice or false
	return robuxPrice
end

local function refreshFoodShop()
	if not foodUi or not FoodRequestItems or not FoodRequestItems:IsA("RemoteFunction") then return end

	for _, child in ipairs(foodUi.scroll:GetChildren()) do
		if child:IsA("Frame") and child ~= foodUi.template then
			child:Destroy()
		end
	end

	local ok, items = pcall(function()
		return FoodRequestItems:InvokeServer()
	end)
	if not ok or type(items) ~= "table" then
		warn("[IngameShopsClient] Food shop item request failed.")
		return
	end

	local y = 0
	for _, data in ipairs(items) do
		local clone = foodUi.template:Clone()
		clone.Visible = true
		clone.Parent = foodUi.scroll
		clone.Position = UDim2.new(0, 0, 0, y)

		local nameLabel = findDescendant(clone, "NameLabel")
		local descLabel = findDescendant(clone, "DescLabel")
		local stockLabel = findDescendant(clone, "StockLabel")
		local buyButton = findDescendant(clone, "BuyButton")
		local imageLabel = findDescendant(clone, "ImageLabel")
		local robuxButton = findDescendant(clone, "RobuxButton")
		local priceLabel = findDescendant(clone, "PriceLabel")

		if nameLabel then nameLabel.Text = tostring(data.Name or "") end
		if descLabel then descLabel.Text = tostring(data.Description or "") end
		if imageLabel then imageLabel.Image = tostring(data.Image or "") end

		local stock = tonumber(data.Stock) or 0
		if stockLabel then
			stockLabel.Text = (stock <= 0) and "Out of Stock" or ("Stock: " .. shortenNumber(stock))
		end

		if buyButton and FoodBuyItem and FoodBuyItem:IsA("RemoteFunction") then
			buyButton.Text = shortenNumber(tonumber(data.Price) or 0)
			buyButton.MouseButton1Click:Connect(function()
				local success, msg = FoodBuyItem:InvokeServer(data.Name)
				if not success then
					warn(msg)
				else
					refreshFoodShop()
				end
			end)
		end

		if robuxButton and data.DevProductId then
			local productId = tonumber(data.DevProductId)
			local price = getCachedRobuxPrice(productId)
			robuxButton.Text = price and (tostring(price) .. " R$") or "R$ ???"
			robuxButton.MouseButton1Click:Connect(function()
				if productId then
					MarketplaceService:PromptProductPurchase(Player, productId)
				end
			end)
		end

		if priceLabel then
			priceLabel.Visible = false
		end

		y += foodUi.template.Size.Y.Offset + 10
	end

	foodUi.scroll.CanvasSize = UDim2.new(0, 0, 0, y)
end

local function openFoodShop()
	if not FoodShopFrame then return end
	if not FoodShopFrame.Visible then
		Utilities.ButtonHandler.OnClick(FoodShopFrame, FOOD_OPEN_POSITION)
	end
end

local function closeFoodShop()
	if not FoodShopFrame or not FoodShopFrame.Visible then return end
	Utilities.ButtonHandler.OnClick(FoodShopFrame, FOOD_OPEN_POSITION)
end

if foodUi then
	if foodUi.exitButton then
		foodUi.exitButton.MouseButton1Click:Connect(function()
			ringDismissedWhileInside.Food = true
			closeFoodShop()
		end)
	end

	if foodUi.restockButton and FoodRestockShop and FoodRestockShop:IsA("RemoteEvent") then
		foodUi.restockButton.MouseButton1Click:Connect(function()
			FoodRestockShop:FireServer()
		end)
	end

	if foodUi.timerLabel and FoodTimerEvent and FoodTimerEvent:IsA("RemoteEvent") then
		FoodTimerEvent.OnClientEvent:Connect(function(timeLeft)
			local mins = math.floor(timeLeft / 60)
			local secs = timeLeft % 60
			foodUi.timerLabel.Text = string.format("Restock in: %02d:%02d", mins, secs)
		end)
	end

	if FoodUpdateShop and FoodUpdateShop:IsA("RemoteEvent") then
		FoodUpdateShop.OnClientEvent:Connect(refreshFoodShop)
	end
end


Frames.Bank:GetPropertyChangedSignal("Visible"):Connect(function()
	if Frames.Bank.Visible then
		showPetsNextToBank()
	else
		hideBankOpenedPets()
	end
end)

local function GemRing()
	local wasInRange = false
	local wasVisible = Frames.GemShop.Visible
	while task.wait(0.1) do
		local character = Player.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		local gemPart = workspace.Map.Rings.GemShop.MainPart
		local inRange = humanoidRootPart and (humanoidRootPart.Position - gemPart.Position).Magnitude < 10
		local isVisible = Frames.GemShop.Visible

		if wasInRange and wasVisible and not isVisible then
			ringDismissedWhileInside.Gem = true
		end

		if inRange then
			if not isVisible and not ringDismissedWhileInside.Gem then
				Utilities.ButtonHandler.OnClick(Frames.GemShop, UDim2.new(0.359,0,0.414,0))
			end
		else
			if isVisible then
				Utilities.ButtonHandler.OnClick(Frames.GemShop, UDim2.new(0.359,0,0.414,0))
			end
			ringDismissedWhileInside.Gem = false
		end

		wasInRange = inRange and true or false
		wasVisible = Frames.GemShop.Visible

	end
end

local function BankRing()
	local wasInRange = false
	local wasVisible = Frames.Bank.Visible
	while task.wait(0.1) do
		local character = Player.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		local bankPart = workspace.Map.Rings.Bank.MainPart
		local inRange = humanoidRootPart and (humanoidRootPart.Position - bankPart.Position).Magnitude < 10
		local isVisible = Frames.Bank.Visible

		if wasInRange and wasVisible and not isVisible then
			ringDismissedWhileInside.Bank = true
		end

		if inRange then
			if not isVisible and not ringDismissedWhileInside.Bank then
				Utilities.ButtonHandler.OnClick(Frames.Bank, BANK_OPEN_POSITION)
			elseif isVisible then
				showPetsNextToBank()
			end
		else
			if isVisible then
				Utilities.ButtonHandler.OnClick(Frames.Bank, BANK_OPEN_POSITION)
			end
			ringDismissedWhileInside.Bank = false
		end

		wasInRange = inRange and true or false
		wasVisible = Frames.Bank.Visible
	end
end

local function SellRing()
	local wasInRange = false
	local wasVisible = SellShopFrame and SellShopFrame.Visible or false

	while task.wait(0.1) do
		local character = Player.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		local rings = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Rings")
		local sellPart = rings and rings:FindFirstChild("Sell") and rings.Sell:FindFirstChild("MainPart")
		local inRange = humanoidRootPart and sellPart and (humanoidRootPart.Position - sellPart.Position).Magnitude < 10
		local isVisible = SellShopFrame and SellShopFrame.Visible or false

		if wasInRange and wasVisible and not isVisible then
			ringDismissedWhileInside.Sell = true
		end

		if inRange then
			if not ringDismissedWhileInside.Sell then
				showPetsForSell()
			end
		else
			if isVisible then
				hideSellShop()
			end
			ringDismissedWhileInside.Sell = false
		end

		wasInRange = inRange and true or false
		wasVisible = SellShopFrame and SellShopFrame.Visible or false
	end
end

local function FoodRing()
	local wasInRange = false
	local wasVisible = FoodShopFrame and FoodShopFrame.Visible or false

	while task.wait(0.1) do
		local character = Player.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		local rings = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Rings")
		local foodRing = rings and (rings:FindFirstChild("FoodShop") or rings:FindFirstChild("Food") or rings:FindFirstChild("Shop"))
		local foodPart = foodRing and foodRing:FindFirstChild("MainPart")
		local inRange = humanoidRootPart and foodPart and (humanoidRootPart.Position - foodPart.Position).Magnitude < 10
		local isVisible = FoodShopFrame and FoodShopFrame.Visible or false

		if wasInRange and wasVisible and not isVisible then
			ringDismissedWhileInside.Food = true
		end

		if inRange then
			if not wasInRange and not ringDismissedWhileInside.Food then
				openFoodShop()
				task.spawn(refreshFoodShop)
			end
		else
			if isVisible then
				closeFoodShop()
			end
			ringDismissedWhileInside.Food = false
		end

		wasInRange = inRange and true or false
		wasVisible = FoodShopFrame and FoodShopFrame.Visible or false
	end
end

coroutine.wrap(GemRing)()
coroutine.wrap(BankRing)()
coroutine.wrap(SellRing)()
coroutine.wrap(FoodRing)()

---upgradetemplates
local function initGemShopUpgrades()
	local GemUpgradeTemplate = Frames.GemShop.Upgrades.Template
	GemUpgradeTemplate.Parent = script
	GemUpgradeTemplate.Name = "GemUpgradeTemplate"

	local AFFORDABLE_COLOR = Color3.fromRGB(60, 190, 80)
	local UNAFFORDABLE_COLOR = Color3.fromRGB(190, 60, 60)
	local PRODUCT_PRICE_CACHE = {}

	local function getPurchaseType(entry)
		local configuredType = entry and tostring(entry:GetAttribute("PurchaseType") or ""):lower() or ""
		if configuredType == "developerproduct" or configuredType == "devproduct" or configuredType == "product" then
			return "DeveloperProduct"
		end
		return "GamePass"
	end


	local function getButtonActivator(frame)
		if not frame then return nil end
		if frame:IsA("GuiButton") then return frame end
		local namedClick = frame:FindFirstChild("Click")
		if namedClick and namedClick:IsA("GuiButton") then return namedClick end
		for _, descendant in ipairs(frame:GetDescendants()) do
			if descendant:IsA("GuiButton") then
				return descendant
			end
		end
		return nil
	end

	local function getGamepassEntryForUpgrade(upgradeFolder, currentLevel)
		local explicitName = upgradeFolder:GetAttribute("GamepassName")
		if explicitName and ReplicatedStorage.Gamepasses:FindFirstChild(tostring(explicitName)) then
			return ReplicatedStorage.Gamepasses[tostring(explicitName)]
		end

		local explicitId = tonumber(upgradeFolder:GetAttribute("GamepassId"))
		if explicitId then
			for _, entry in ipairs(ReplicatedStorage.Gamepasses:GetChildren()) do
				if tonumber(entry.Value) == explicitId then
					return entry
				end
			end
		end

		local bestEntry = nil
		local bestTierStart = -math.huge
		for _, entry in ipairs(ReplicatedStorage.Gamepasses:GetChildren()) do
			if tostring(entry:GetAttribute("GemUpgradeTarget")) == tostring(upgradeFolder.Name) then
				local tierStart = tonumber(entry:GetAttribute("GemUpgradeTierStart"))
				if tierStart == nil then
					tierStart = tonumber(entry:GetAttribute("GemUpgradeTierMin")) or 0
				end

				if tierStart <= currentLevel and tierStart >= bestTierStart then
					bestTierStart = tierStart
					bestEntry = entry
				end
			end
		end
		return bestEntry
	end

	local function getProductPrice(productId, purchaseType)
		local cacheKey = tostring(purchaseType) .. ":" .. tostring(productId)
		if PRODUCT_PRICE_CACHE[cacheKey] ~= nil then
			return PRODUCT_PRICE_CACHE[cacheKey] or nil
		end
		local success, info = pcall(function()
			if purchaseType == "DeveloperProduct" then
				return MarketPlaceService:GetProductInfo(productId, Enum.InfoType.Product)
			end
			return MarketPlaceService:GetProductInfo(productId, Enum.InfoType.GamePass)
		end)
		local robuxPrice = success and info and info.PriceInRobux or nil
		PRODUCT_PRICE_CACHE[cacheKey] = robuxPrice or false
		return robuxPrice
	end

	local function calcReward(rewardConfig, level)
		if rewardConfig.Exponential.Value then
			return rewardConfig.DefaultReward.Value + rewardConfig.IncreasePer.Value ^ level
		end
		return rewardConfig.DefaultReward.Value + rewardConfig.IncreasePer.Value * level
	end

	local function calcSingleCost(costConfig, level)
		if costConfig.Exponential.Value then
			return costConfig.DefaultPrice.Value * costConfig.IncreasePer.Value ^ level
		end
		return costConfig.DefaultPrice.Value + costConfig.IncreasePer.Value * (level + 1)
	end

	for _, upgradeFolder in Gemshop:GetChildren() do
		local upgradeId = upgradeFolder.Name
		local levelValue = PlayerData["GemUpgrade" .. upgradeId]
		if not levelValue then
			continue
		end

		local card = GemUpgradeTemplate:Clone()
		card.LayoutOrder = tonumber(upgradeId)
		card.Name = upgradeId
		card.Title.Text = upgradeFolder.UpgradeName.Value

		local tempImage = findDescendant(card, "TempImage")
		if tempImage and tempImage:IsA("ImageLabel") then
			local imageRaw = upgradeFolder:GetAttribute("TempImage") or upgradeFolder:GetAttribute("Image") or upgradeFolder:GetAttribute("ImageId")
			if imageRaw ~= nil then
				local imageIdNumber = tonumber(imageRaw)
				if imageIdNumber and not tostring(imageRaw):match("rbxassetid://") then
					tempImage.Image = "rbxassetid://" .. imageIdNumber
				else
					tempImage.Image = tostring(imageRaw)
				end
			end
		end

		local buttonFrames = {
			Buy1 = findDescendant(card, "Buy1"),
			Buy2 = findDescendant(card, "Buy2"),
			Buy3 = findDescendant(card, "Buy3"),
			Buy4 = findDescendant(card, "Buy4"),
		}

		local buttonAmounts = {
			Buy1 = buttonFrames.Buy1 and findDescendant(buttonFrames.Buy1, "Amount"),
			Buy2 = buttonFrames.Buy2 and findDescendant(buttonFrames.Buy2, "Amount"),
			Buy3 = buttonFrames.Buy3 and findDescendant(buttonFrames.Buy3, "Amount"),
			Buy4 = buttonFrames.Buy4 and findDescendant(buttonFrames.Buy4, "Amount"),
		}

		local buttonActivators = {
			Buy1 = getButtonActivator(buttonFrames.Buy1),
			Buy2 = getButtonActivator(buttonFrames.Buy2),
			Buy3 = getButtonActivator(buttonFrames.Buy3),
			Buy4 = getButtonActivator(buttonFrames.Buy4),
		}

		local rewardConfig = upgradeFolder.Reward
		local costConfig = upgradeFolder.Price
		local maxLevel = upgradeFolder.Max.Value
		local tierLabel = findDescendant(card, "Tier")

		local function setButtonColor(buttonName, enabled)
			local frame = buttonFrames[buttonName]
			if frame and frame:IsA("Frame") then
				frame.BackgroundColor3 = enabled and AFFORDABLE_COLOR or UNAFFORDABLE_COLOR
			end
		end

		local function setButtonVisible(buttonName, visible)
			local frame = buttonFrames[buttonName]
			if frame then
				frame.Visible = visible
			end
		end

		local function setAmount(buttonName, text)
			local label = buttonAmounts[buttonName]
			if label then
				label.Text = text
			end
		end

		local function calcBulkCost(currentLevel, requestedAmount)
			local amountToBuy = math.clamp(requestedAmount, 0, math.max(maxLevel - currentLevel, 0))
			if amountToBuy <= 0 then
				return 0, 0
			end

			local totalCost = 0
			for offset = 0, amountToBuy - 1 do
				totalCost += calcSingleCost(costConfig, currentLevel + offset)
			end
			return totalCost, amountToBuy
		end

		local function updateCard()
			local currentLevel = levelValue.Value
			local currency = PlayerData.Currency.Value
			local operator = upgradeFolder.Operator.Value
			local remaining = math.max(maxLevel - currentLevel, 0)
			local gamepassEntry = getGamepassEntryForUpgrade(upgradeFolder, currentLevel)
			local gamepassId = gamepassEntry and tonumber(gamepassEntry.Value) or nil
			local gamepassType = getPurchaseType(gamepassEntry)
			local gamepassAmount = tonumber(gamepassEntry and gamepassEntry:GetAttribute("GemUpgradeAmount")) or 10
			local displayBaseValue = tonumber(upgradeFolder:GetAttribute("DisplayBaseValue"))
			local displayPrefix = (displayBaseValue == nil) and operator or ""
			local function toDisplayValue(level)
				local raw = calcReward(rewardConfig, level)
				if displayBaseValue == nil then
					return raw
				end
				if operator == "+" then
					return displayBaseValue + raw
				end
				return displayBaseValue * raw
			end

			if currentLevel < maxLevel then
				card.Description.Text = displayPrefix .. Utilities.Short.en(toDisplayValue(currentLevel)) .. " > " .. displayPrefix .. Utilities.Short.en(toDisplayValue(currentLevel + 1))
			else
				card.Description.Text = displayPrefix .. Utilities.Short.en(toDisplayValue(currentLevel)) .. " > Max"
			end
			if tierLabel and tierLabel:IsA("TextLabel") then
				tierLabel.Text = "Tier: " .. tostring(currentLevel)
			end

			local cost1, buyable1 = calcBulkCost(currentLevel, 1)
			local cost5, buyable5 = calcBulkCost(currentLevel, 5)
			local cost10, buyable10 = calcBulkCost(currentLevel, 10)
			local canShowBuy1 = remaining >= 1
			local canShowBuy5 = remaining >= 5
			local canShowBuy10 = remaining >= 10
			local canShowGamepass = gamepassId ~= nil and remaining >= gamepassAmount and currentLevel < maxLevel

			setAmount("Buy1", buyable1 > 0 and Utilities.Short.en(cost1) or "Max")
			setAmount("Buy2", buyable5 > 0 and Utilities.Short.en(cost5) or "Max")
			setAmount("Buy3", buyable10 > 0 and Utilities.Short.en(cost10) or "Max")
			setButtonVisible("Buy1", canShowBuy1)
			setButtonVisible("Buy2", canShowBuy5)
			setButtonVisible("Buy3", canShowBuy10)
			setButtonVisible("Buy4", canShowGamepass)

			setButtonColor("Buy1", canShowBuy1 and buyable1 > 0 and currency >= cost1)
			setButtonColor("Buy2", canShowBuy5 and buyable5 > 0 and currency >= cost5)
			setButtonColor("Buy3", canShowBuy10 and buyable10 > 0 and currency >= cost10)

			if gamepassId then
				local robuxPrice = getProductPrice(gamepassId, gamepassType)
				setAmount("Buy4", robuxPrice and ("\u{E002}" .. tostring(robuxPrice)) or "R$ ?")
			else
				setAmount("Buy4", "No Pass")
			end
			setButtonColor("Buy4", canShowGamepass)
		end

		card.Parent = Frames.GemShop.Upgrades
		updateCard()
		levelValue.Changed:Connect(updateCard)
		PlayerData.Currency.Changed:Connect(updateCard)

		if buttonActivators.Buy1 then
			buttonActivators.Buy1.MouseButton1Click:Connect(function()
				Remotes.GemUpgrade:FireServer(upgradeId, 1)
			end)
		end
		if buttonActivators.Buy2 then
			buttonActivators.Buy2.MouseButton1Click:Connect(function()
				Remotes.GemUpgrade:FireServer(upgradeId, 5)
			end)
		end
		if buttonActivators.Buy3 then
			buttonActivators.Buy3.MouseButton1Click:Connect(function()
				Remotes.GemUpgrade:FireServer(upgradeId, 10)
			end)
		end
		if buttonActivators.Buy4 then
			buttonActivators.Buy4.MouseButton1Click:Connect(function()
				local currentLevel = levelValue.Value
				local gamepassEntry = getGamepassEntryForUpgrade(upgradeFolder, currentLevel)
				local gamepassId = gamepassEntry and tonumber(gamepassEntry.Value) or nil
				local gamepassType = getPurchaseType(gamepassEntry)
				local gamepassAmount = tonumber(gamepassEntry and gamepassEntry:GetAttribute("GemUpgradeAmount")) or 10
				if not gamepassId then return end
				if currentLevel + gamepassAmount > maxLevel then return end
				if gamepassType == "DeveloperProduct" then
					MarketPlaceService:PromptProductPurchase(Player, gamepassId)
					return
				end

				local hasPass = false
				local success = pcall(function()
					hasPass = MarketPlaceService:UserOwnsGamePassAsync(Player.UserId, gamepassId)
				end)
				if success and hasPass then return end
				MarketPlaceService:PromptGamePassPurchase(Player, gamepassId)
			end)
		end
	end
end

initGemShopUpgrades()

--// Codes
local CodesFrame = Frames.Codes


local function getCodeInputAndRedeemButton()
	local fallbackInput = CodesFrame and CodesFrame:FindFirstChild("CodesBox")
	local fallbackRedeem = CodesFrame and CodesFrame:FindFirstChild("Redeem")
	local shopContainer = getGamepassContainer()
	local shopCodesCard = shopContainer and shopContainer:FindFirstChild("Codes")
	local inner = shopCodesCard and shopCodesCard:FindFirstChild("InnerPart")
	local shopInput = inner and inner:FindFirstChild("CodesBox")
	local shopRedeem = inner and inner:FindFirstChild("Redeem")

	if shopInput and shopRedeem then
		return shopInput, shopRedeem
	end
	return fallbackInput, fallbackRedeem
end

local function redeemCodeFromInput(codeInput)
	if not (codeInput and codeInput:IsA("TextBox")) then return end
	local code = trimText(codeInput.Text)
	if code == "" then
		notifyPlayer("error", "❌ Enter a valid code first.")
		return
	end
	Remotes.RedeemCode:FireServer(string.upper(code))
end

do
	local codeInput, redeemButton = getCodeInputAndRedeemButton()
	if redeemButton then
		redeemButton.MouseButton1Click:Connect(function()
			redeemCodeFromInput(codeInput)
		end)
	end
	if codeInput and codeInput:IsA("TextBox") then
		codeInput.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				redeemCodeFromInput(codeInput)
			end
		end)
	end
end

--// Stats
local StatsFrame = Frames.Stats
StatsFrame.TotalCurrency.Description.Text = "Check how much Total "..GameSettings.CurrencyName.Value.." you have!"
StatsFrame.TotalCurrency.Title.Text = "Total "..GameSettings.CurrencyName.Value

-- Total Currency
StatsFrame.TotalCurrency.Stat.Amount.Text = Utilities.Short.en(PlayerData.TotalCurrency.Value)
PlayerData.TotalCurrency.Changed:Connect(function()
	StatsFrame.TotalCurrency.Stat.Amount.Text = Utilities.Short.en(PlayerData.TotalCurrency.Value)
end)

-- Eggs Hatched
StatsFrame.EggsHatched.Stat.Amount.Text = Utilities.Short.en(PlayerData.EggsHatched.Value)
PlayerData.EggsHatched.Changed:Connect(function()
	StatsFrame.EggsHatched.Stat.Amount.Text = Utilities.Short.en(PlayerData.EggsHatched.Value)
end)

--// Functions
function RenderStepped()
	PetMovement()
	FindEgg()
end

RunService.RenderStepped:Connect(RenderStepped)
