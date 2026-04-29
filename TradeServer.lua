--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Variables
local Remotes = ReplicatedStorage.Remotes.Trading

local Modules = ReplicatedStorage.Modules

local PetMultipliers = require(Modules.PetMultipliers)
local Multipliers = require(Modules.Multipliers)

local TradeOffers = {} -- table with trade offers of the players inside

Remotes.RequestTrade.OnServerInvoke = function(Player, Player2)
	--// Player has clicked on "Send Trade" button
	Player2 = game.Players:FindFirstChild(Player2)

	if not Player2:FindFirstChild("Loaded") or not Player2.Loaded.Value then return "Player has not loaded" end
	if Player.NonSaveValues.IsTrading.Value or Player2.NonSaveValues.IsTrading.Value then return "Player is in trade" end
	-- You can also add requirements here for trading, such as 250 eggs opened

	--// Make a button pop up in their ui
	Remotes.RequestTrade:InvokeClient(Player2, Player.Name)	
end

Remotes.StartTrade.OnServerInvoke = function(Player, Player2)
	--// Starting trade
	Player2 = game.Players:FindFirstChild(Player2)

	if not Player2:FindFirstChild("Loaded") or not Player2.Loaded.Value then return end
	if Player.NonSaveValues.IsTrading.Value or Player2.NonSaveValues.IsTrading.Value then return end

	Player.NonSaveValues.IsTrading.Value = true
	Player2.NonSaveValues.IsTrading.Value = true

	TradeOffers[Player.Name] = {TradeTokens = 0, Pets = {}} -- creates the inventory during the trade
	TradeOffers[Player2.Name] = {TradeTokens = 0, Pets = {}}

	Remotes.StartTrade:InvokeClient(Player2,Player.Name) -- player 2 knows the trade started
	return true
end

Remotes.ChangeOffer.OnServerInvoke = function(Player, Player2, Args)
	Player2 = game.Players:FindFirstChild(Player2)
	
	if Args.OfferType == "Pet" then
		if not TradeOffers[Player.Name].Pets[Args.ID] then
			if Multipliers.GetMaxPetsStorage(Player2) <= #Player2.Data.Pets:GetChildren() + #TradeOffers[Player.Name].Pets then return "Max" end
			TradeOffers[Player.Name].Pets[Args.ID] = 1
			Remotes.ChangeOffer:InvokeClient(Player2,"PetAdded", Args.ID)
			Player.NonSaveValues.IsReady.Value = false
			return "Added"
		else
			TradeOffers[Player.Name].Pets[Args.ID] = nil
			Remotes.ChangeOffer:InvokeClient(Player2, "PetRemoved", Args.ID)
			Player.NonSaveValues.IsReady.Value = false
			return "Removed"
		end
	elseif Args.OfferType == "TradeTokens" then
		if tonumber(Args.Amount) and tonumber(Args.Amount) >= 0 then
			if not Player.Data.PlayerData:FindFirstChild("Currency2") then return end -- 
			if Player.Data.PlayerData.Currency2.Value < tonumber(Args.Amount) then return end -- not enough tokens

			TradeOffers[Player.Name].TradeTokens = tonumber(Args.Amount)
			Remotes.ChangeOffer:InvokeClient(Player2, "TradeTokens", tonumber(Args.Amount))
			Player.NonSaveValues.IsReady.Value = false
		end
	end
end

Remotes.TradeAction.OnServerInvoke = function(Player, Player2, Args)
	Player2 = game.Players:FindFirstChild(Player2)

	if Args.Option == "Cancel" then
		Player.NonSaveValues.IsTrading.Value = false
		Player.NonSaveValues.IsReady.Value = false
		TradeOffers[Player.Name] = nil -- remove all trade data to free up space
		TradeOffers[Player2.Name] = nil -- remove all trade data, if the player left it does not matter as it should still be removed

		if Player2 then -- incase the player left, you dont edit the data. If they did not, edit the data
			Player2.NonSaveValues.IsTrading.Value = false
			Player2.NonSaveValues.IsReady.Value = false
			Remotes.TradeAction:InvokeClient(Player2, {Option = "Cancel"})
		end

		return true
	elseif Args.Option == "Ready" then
		if not Player.NonSaveValues.IsReady.Value then -- makes player ready
			Player.NonSaveValues.IsReady.Value = true

			if Player2.NonSaveValues.IsReady.Value then -- both are ready
				local Active = true

				--// Countdown Timer
				Remotes.TradeAction:InvokeClient(Player2, {Option = "Countdown", Count = 3})
				Remotes.TradeAction:InvokeClient(Player, {Option = "Countdown", Count = 3})
				
				local function BothReady()
					return Player2.NonSaveValues.IsReady.Value and Player.NonSaveValues.IsReady.Value
				end
				
				local function CancelCountdown()
					Active = false 
					Remotes.TradeAction:InvokeClient(Player2, {Option = "CountdownEnded"})
					Remotes.TradeAction:InvokeClient(Player, {Option = "CountdownEnded"})
				end
				
				for i = 10, 1, -1 do
					if not BothReady() then 
						CancelCountdown()
						break 
					end
					task.wait(0.3)	
				end
				
				if not BothReady() then
					CancelCountdown()
				end
			
				if not Active then return end
				
				print("Completing Trade")
				CompleteTrade(Player, Player2)
				Remotes.TradeAction:InvokeClient(Player2, {Option = "Countdown", Count = 0})
				Remotes.TradeAction:InvokeClient(Player, {Option = "Countdown", Count = 0})
			else
				Remotes.TradeAction:InvokeClient(Player2, {Option = "Ready"})
				return "Ready"
			end
		else --// unready
			Player.NonSaveValues.IsReady.Value = false
			Remotes.TradeAction:InvokeClient(Player2, {Option = "Unready"})
			return "Unready"
		end		
	end
end

function UnequipPet(Player, Pet)
	if not Pet.Equipped.Value then return end -- Already unequipped
	Pet.Equipped.Value = false
	PetMultipliers.RemovePet(Player.Name, tonumber(Pet.Name))
	Player.NonSaveValues.PetsEquipped.Value = PetMultipliers.GetPetsEquipped(Player.Name)
end

function LoadEquipped(Player)
	local EquippedPets = PetMultipliers.Multipliers[Player.Name]

	for PetId, Value in EquippedPets do
		local PetModel = workspace.PlayerPets[Player.Name]:FindFirstChild(PetId)

		if not PetModel then
			local PetInstance = Player.Data.Pets[PetId]
			local NewPet = ReplicatedStorage.Pets[PetInstance.PetName.Value]:Clone()
			NewPet.Name = PetId

			for _, Part in NewPet:GetChildren() do
				if Part:IsA("BasePart") then
					Part.Anchored = true
				end
			end

			local Billboard = script.BillboardGui:Clone()
			Billboard.PetName.Text = PetInstance.PetName.Value
			Billboard.PetRarity.Text = ReplicatedStorage.Pets[PetInstance.PetName.Value].Settings.Rarity.Value
			Billboard.StudsOffset = Vector3.new(0, NewPet.MainPart.Size.Y, 0)
			Billboard.Parent = NewPet

			NewPet:PivotTo(Player.Character.HumanoidRootPart.CFrame)			
			NewPet.Parent = workspace.PlayerPets[Player.Name]
		end
	end

	for _,PlayerPet in workspace.PlayerPets[Player.Name]:GetChildren() do
		if not EquippedPets[tonumber(PlayerPet.Name)] then
			PlayerPet:Destroy()
		end
	end
end

function CompleteTrade(Player, Player2)
	Player.NonSaveValues.IsTrading.Value = false
	Player2.NonSaveValues.IsTrading.Value = false
	Player.NonSaveValues.IsReady.Value = false
	Player2.NonSaveValues.IsReady.Value = false

	--// Player 1 to Player 2
	for i, v in TradeOffers[Player.Name].Pets do
		local ClonedPet = Player.Data.Pets[i]

		if ClonedPet.Equipped.Value then
			UnequipPet(Player, ClonedPet)
		end
		
		ClonedPet.Parent = Player2.Data.Pets
	end

	--// Player 2 to Player 1
	for i, v in TradeOffers[Player2.Name].Pets do
		local ClonedPet = Player2.Data.Pets[i]

		if ClonedPet.Equipped.Value then
			UnequipPet(Player2, ClonedPet)
		end

		ClonedPet.Parent = Player.Data.Pets
	end
	
	LoadEquipped(Player)
	LoadEquipped(Player2)

	if Player.Data.PlayerData:FindFirstChild("Currency2") then -- like gems or smth exist
		Player2.Data.PlayerData.Currency2.Value += TradeOffers[Player.Name].TradeTokens - TradeOffers[Player2.Name].TradeTokens -- for example u get 400 u give 150
		Player.Data.PlayerData.Currency2.Value += TradeOffers[Player2.Name].TradeTokens - TradeOffers[Player.Name].TradeTokens
	end
end
