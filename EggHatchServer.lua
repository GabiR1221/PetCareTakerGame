-- Egg
function RandomID(Folder)
	local Chance = math.random(1,10000)
	if Folder:FindFirstChild(Chance) then
		return RandomID(Folder) -- reroll if exists
	end
	return Chance
end

function ChooseRandomPet(Egg, LuckMultiplier)
	local EggInfo = ReplicatedStorage.Eggs[Egg]
	local Pets, TotalWeight = {}, 0

	for _, Pet in EggInfo.Pets:GetChildren() do
		table.insert(Pets, {Pet.Name, Pet.Value})
	end

	table.sort(Pets, function(a,b)
		return a[2] > b[2]
	end)

	local BaseChance = Pets[1][2] -- this is the most common pet

	for _,v in Pets do
		local Chance = math.min(v[2] * LuckMultiplier, BaseChance) -- so if the easiest pet is 70%, all pets will go towards 70% 
		TotalWeight += Chance
		v[2] = Chance
	end

	local Chance = Random.new():NextNumber(0,TotalWeight)

	local Counter = 0
	for _,v in Pets do	
		Counter += v[2]

		if Counter >= Chance then
			return v[1]
		end
	end
end

Remotes.Egg.OnServerInvoke = function(Player, Egg, Amount)
	if Player.NonSaveValues.IsOpeningEgg.Value then return end -- cooldown
	if #Player.Data.Pets:GetChildren() + Amount > Multipliers.GetMaxPetsStorage(Player) then return end -- max storage

	local EggInfo = ReplicatedStorage.Eggs:FindFirstChild(Egg)

	if not EggInfo then print(Egg.." does not exist!") return end -- egg does not exist!
	if EggInfo:FindFirstChild("ProductId") then return end -- robux egg

	if Amount == 3 and ReplicatedStorage.Gamepasses:FindFirstChild("TripleEgg") and not Player.Data.Gamepasses.TripleEgg.Value then
		return -- if this is true, it means the player is trying to open a triple egg while there is a gamepass which they don't own
	end

	if Player.Data.PlayerData.Currency.Value >= EggInfo.Cost.Value * Amount then
		Player.Data.PlayerData.Currency.Value -= EggInfo.Cost.Value * Amount
		Player.Data.PlayerData.EggsHatched.Value += Amount
		Player.NonSaveValues.IsOpeningEgg.Value = true

		coroutine.wrap(function()
			task.wait(3)
			Player.NonSaveValues.IsOpeningEgg.Value = false
		end)()

		local Results = {}

		local LuckMultiplier = Multipliers.GetLuckMultiplier(Player)

		for i = 1, Amount do
			local PetName = ChooseRandomPet(Egg, LuckMultiplier) 

			if not Player.Data.AutoDelete[PetName].Value then -- auto delete
				local NewPet = game.ReplicatedStorage.Assets.PetTemplate:Clone()
				NewPet.Name = RandomID(Player.Data.Pets)
				NewPet.PetName.Value = PetName
				NewPet.Parent = Player.Data.Pets
			end

			Results[i] = PetName
		end

		return Results
	end
end
