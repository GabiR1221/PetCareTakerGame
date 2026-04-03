--// Rebirth
local RebirthPrice, RebirthMulti = GameSettings.RebirthBasePrice.Value, GameSettings.RebirthMultiplier.Value
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TycoonRebirthEvent = ReplicatedStorage:WaitForChild("TycoonRebirthEvent")
local GetTycoonRebirthRequirements = ReplicatedStorage:WaitForChild("TycoonGetRebirthRequirementsFunction")

local function FormatCurrencyRequirements(requiredCurrency)
	local formatted = {}
	for currencyName, amount in pairs(requiredCurrency or {}) do
		local cleanName = tostring(currencyName)
		table.insert(formatted, Utilities.Short.en(tonumber(amount) or 0).." "..cleanName)
	end
	table.sort(formatted)
	return table.concat(formatted, ", ")
end

local function FormatPetRequirements(requiredPets)
	if type(requiredPets) ~= "table" or #requiredPets == 0 then
		return "None"
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
		local requiredCurrencyText = FormatCurrencyRequirements(requirements.RequiredCurrency)
		local requiredPetsText = FormatPetRequirements(requirements.RequiredPets)

		if limit > 0 and current >= limit then
			Frames.Rebirth.Description.Text = "Tycoon rebirth limit reached ("..current.."/"..limit..")"
			Frames.Rebirth.Cost.Text = "No more rebirths available"
		else
			Frames.Rebirth.Description.Text = "Tycoon Rebirth "..nextTier.." Requirements: "..completion.."% completion | Pets: "..requiredPetsText
			Frames.Rebirth.Cost.Text = "Required Currency: "..(requiredCurrencyText ~= "" and requiredCurrencyText or "None")
		end
		return
	end

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
	Remotes.Rebirth:FireServer()
	if TycoonRebirthEvent then
		TycoonRebirthEvent:FireServer()
	end
	Utilities.Audio.PlayAudio("Click")
end)
