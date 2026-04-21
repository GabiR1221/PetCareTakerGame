-- Egg
function RandomID(Folder)
	local Chance = math.random(1,10000)
	if Folder:FindFirstChild(Chance) then
		return RandomID(Folder) -- reroll if exists
	end
	return Chance
end

local function getInventoryFolder(player)
	local data = player and player:FindFirstChild("Data")
	if not data then return nil end
	local toysFolder = data:FindFirstChild("Toys")
	if not toysFolder then
		toysFolder = Instance.new("Folder")
		toysFolder.Name = "Toys"
		toysFolder.Parent = data
	end
	return toysFolder
end

local function getInventoryStorageLimit(player)
	if Multipliers and Multipliers.GetMaxPetsStorage then
		return tonumber(Multipliers.GetMaxPetsStorage(player)) or 0
	end
	return 0
end

local function shouldAutoDelete(player, itemName)
	local autoDeleteFolder = player and player:FindFirstChild("Data") and player.Data:FindFirstChild("AutoDelete")
	if not autoDeleteFolder then return false end
	local entry = autoDeleteFolder:FindFirstChild(tostring(itemName))
	return entry and entry:IsA("BoolValue") and entry.Value == true
end

local function createInventoryToy(player, toyName)
	local inventoryFolder = getInventoryFolder(player)
	if not inventoryFolder then return end

	local newItem = Instance.new("Folder")
	newItem.Name = tostring(RandomID(inventoryFolder))
	newItem.Parent = inventoryFolder

	local itemName = Instance.new("StringValue")
	itemName.Name = "ItemName"
	itemName.Value = tostring(toyName)
	itemName.Parent = newItem

	local itemType = Instance.new("StringValue")
	itemType.Name = "ItemType"
	itemType.Value = "Toy"
	itemType.Parent = newItem

	local equipped = Instance.new("BoolValue")
	equipped.Name = "Equipped"
	equipped.Value = false
	equipped.Parent = newItem

	local playerData = player and player:FindFirstChild("Data") and player.Data:FindFirstChild("PlayerData")
	local jsonValue = playerData and playerData:FindFirstChild("ToyInventoryJson")
	if jsonValue and jsonValue:IsA("StringValue") then
		local httpService = game:GetService("HttpService")
		task.defer(function()
			local payload = {}
			for _, toyFolder in ipairs(inventoryFolder:GetChildren()) do
				local itemName = toyFolder:FindFirstChild("ItemName")
				if itemName and itemName.Value ~= "" then
					local equippedValue = toyFolder:FindFirstChild("Equipped")
					table.insert(payload, {
						id = tostring(toyFolder.Name),
						itemName = tostring(itemName.Value),
						itemType = "Toy",
						equipped = equippedValue and equippedValue.Value == true or false,
					})
				end
			end
			local ok, encoded = pcall(function()
				return httpService:JSONEncode(payload)
			end)
			if ok then
				jsonValue.Value = encoded
			end
		end)
	end
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
	local inventoryFolder = getInventoryFolder(Player)
	if not inventoryFolder then return end
	if #inventoryFolder:GetChildren() + Amount > getInventoryStorageLimit(Player) then return end -- max storage

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
			local itemName = ChooseRandomPet(Egg, LuckMultiplier)

			if not shouldAutoDelete(Player, itemName) then -- auto delete
				createInventoryToy(Player, itemName)
			end

			Results[i] = itemName
		end

		return Results
	end
end
