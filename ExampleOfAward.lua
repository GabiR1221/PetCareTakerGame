function SpawnObject(v)
	if #v:GetChildren() < GameSettings.MaxDrops.Value then
		local NewDrop = CurrenyDrop:Clone()

		local X,Y,Z = math.random(v.Size.X) - v.Size.X/2 + v.Position.X, v.Position.Y + 5, math.random(v.Size.Z) - v.Size.Z/2 + v.Position.Z
		local RandomPosition = Vector3.new(X,Y,Z)

		NewDrop.Position = RandomPosition 
		NewDrop.Parent = v

		local Hit = false

		NewDrop.Touched:Connect(function(HitPart)
			if Hit then return end

			if HitPart.Parent:FindFirstChild("Humanoid") then
				Hit = true
				local Character = HitPart.Parent
				local Player = Players:GetPlayerFromCharacter(Character)
				Player.Data.PlayerData.Currency.Value += 1 * Multipliers.CurrencyMultiplier(Player)
				Player.Data.PlayerData.TotalCurrency.Value += 1 * Multipliers.CurrencyMultiplier(Player)
				NewDrop:Destroy()
			end			
		end)

		NewDrop.CanCollide = true
		task.wait(2.5)

		pcall(function()
			NewDrop.Anchored = true
			NewDrop.CanCollide = false
		end)
	end
end
