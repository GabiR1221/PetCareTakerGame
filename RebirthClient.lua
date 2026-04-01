
--// Rebirth
local RebirthPrice, RebirthMulti = GameSettings.RebirthBasePrice.Value, GameSettings.RebirthMultiplier.Value

function UpdateRebirthInfo()
	Frames.Rebirth.Counter.Text = "You have "..Utilities.Short.en(PlayerData.Rebirth.Value).." Rebirths"
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
	Utilities.Audio.PlayAudio("Click")
end)
