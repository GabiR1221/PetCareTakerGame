--// Shop
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

local function getExistingShopCard(entry)
	local holder = Frames and Frames:FindFirstChild("Shop") and Frames.Shop:FindFirstChild("Gamepasses")
	if not holder then return nil end

	local explicitCardName = entry:GetAttribute("ShopCardName")
	if type(explicitCardName) == "string" and explicitCardName ~= "" then
		local explicitCard = holder:FindFirstChild(explicitCardName)
		if explicitCard and explicitCard:IsA("Frame") then
			return explicitCard
		end
	end

	local cardByEntryName = holder:FindFirstChild(entry.Name)
	if cardByEntryName and cardByEntryName:IsA("Frame") then
		return cardByEntryName
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

for _,Gamepass in ReplicatedStorage.Gamepasses:GetChildren() do
	local ExistingCard = getExistingShopCard(Gamepass)
	local isCustomCard = ExistingCard ~= nil
	local NewGamepass = ExistingCard or getGamepassTemplate(Gamepass):Clone()
	if not isValidShopCard(NewGamepass) then
		warn(("[ShopClient] Invalid shop card for '%s'. Card must include InnerPart > Button and InnerPart > Price."):format(Gamepass.Name))
		if not isCustomCard and NewGamepass then
			NewGamepass:Destroy()
		end
		continue
	end
	if not isCustomCard then
		NewGamepass.Parent = Frames.Shop.Gamepasses
	end

	local GamepassInfo
	local purchaseType
	local _, Error
	GamepassInfo, purchaseType, Error = getProductInfoWithType(Gamepass.Value)


	if Error then 
		warn("An error as occured while gathering gamepass data: "..Error) 
		if not isCustomCard then
			NewGamepass:Destroy()
		end
		continue 
	else
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
			if purchaseType == "DeveloperProduct" then
				MarketPlaceService:PromptProductPurchase(Player, Gamepass.Value)
			else
				MarketPlaceService:PromptGamePassPurchase(Player, Gamepass.Value)
			end
			Utilities.Audio.PlayAudio("Click")
		end)
	end
end
