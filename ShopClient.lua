--// Shop
for _,Gamepass in ReplicatedStorage.Gamepasses:GetChildren() do
	local NewGamepass = script.GamepassTemplate:Clone()

	local GamepassInfo

	local Succes, Error = pcall(function()
		GamepassInfo = MarketPlaceService:GetProductInfo(Gamepass.Value, Enum.InfoType.GamePass)
	end)

	if Error then 
		warn("An error as occured while gathering gamepass data: "..Error) 
		NewGamepass:Destroy() continue 
	else
		NewGamepass.InnerPart.ImageLabel.Image = "rbxassetid://"..(GamepassInfo.IconImageAssetId or 666669321)
		NewGamepass.InnerPart.Description.Text = GamepassInfo.Description 
		NewGamepass.InnerPart.GPName.Text = GamepassInfo.Name
		NewGamepass.InnerPart.Price.Text = Data.Gamepasses[Gamepass.Name].Value and "Owned ✅" or "\u{E002}"..(GamepassInfo.PriceInRobux or 10000)

		Data.Gamepasses[Gamepass.Name].Changed:Connect(function()
			NewGamepass.InnerPart.Price.Text = Data.Gamepasses[Gamepass.Name].Value and "Owned ✅" or "\u{E002}"..GamepassInfo.PriceInRobux
		end)

		NewGamepass.InnerPart.Button.MouseButton1Click:Connect(function()
			MarketPlaceService:PromptGamePassPurchase(Player, Gamepass.Value)
			Utilities.Audio.PlayAudio("Click")
		end)

		NewGamepass.Parent = Frames.Shop.Gamepasses
	end
end

