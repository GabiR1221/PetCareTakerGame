-- Egg
function RandomID(Folder)
	local Chance = math.random(1,10000)
	if Folder:FindFirstChild(Chance) then
		return RandomID(Folder) -- reroll if exists
	end
	return Chance
end

local function getInventoryFolder(player, itemType)
	local data = player and player:FindFirstChild("Data")
	if not data then return nil end
	local folderName = (tostring(itemType) == "Accessory") and "Accessories" or "Toys"
	local inventoryFolder = data:FindFirstChild(folderName)
	if not inventoryFolder then
		inventoryFolder = Instance.new("Folder")
		inventoryFolder.Name = folderName
		inventoryFolder.Parent = data
	end
	return inventoryFolder
end

local function getTotalInventoryCount(player)
	local data = player and player:FindFirstChild("Data")
	if not data then return 0 end
	local toys = data:FindFirstChild("Toys")
	local accessories = data:FindFirstChild("Accessories")
	return (toys and #toys:GetChildren() or 0) + (accessories and #accessories:GetChildren() or 0)
end

local function resolveItemType(itemName)
	local accessoriesFolder = ReplicatedStorage:FindFirstChild("Accessories")
	if accessoriesFolder and accessoriesFolder:FindFirstChild(itemName) then
		return "Accessory"
	end
	return "Toy"
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

local function createInventoryItem(player, itemNameRaw, itemTypeRaw)
	local itemNameText = tostring(itemNameRaw or "")
	if itemNameText == "" then return end

	local itemType = tostring(itemTypeRaw or "")
	if itemType == "" then
		itemType = resolveItemType(itemNameText)
	end

	local inventoryFolder = getInventoryFolder(player, itemType)
	if not inventoryFolder then return end

	local newItem = Instance.new("Folder")
	newItem.Name = tostring(RandomID(inventoryFolder))
	newItem.Parent = inventoryFolder

	local itemName = Instance.new("StringValue")
	itemName.Name = "ItemName"
	itemName.Value = itemNameText
	itemName.Parent = newItem

	local itemTypeValue = Instance.new("StringValue")
	itemTypeValue.Name = "ItemType"
	itemTypeValue.Value = tostring(itemTypeRaw or resolveItemType(itemNameText))
	itemTypeValue.Parent = newItem

	local equipped = Instance.new("BoolValue")
	equipped.Name = "Equipped"
	equipped.Value = false
	equipped.Parent = newItem
end

function ChooseRandomPet(Egg, LuckMultiplier)
	local EggInfo = ReplicatedStorage.Eggs[Egg]
	local Pets, TotalWeight = {}, 0

	local dropsFolder = EggInfo and (EggInfo:FindFirstChild("Pets") or EggInfo:FindFirstChild("Items"))
	if not dropsFolder then
		return nil, nil
	end

	for _, Pet in dropsFolder:GetChildren() do
		local itemType = Pet:GetAttribute("ItemType")
		if not itemType and Pet:FindFirstChild("ItemType") then
			itemType = Pet.ItemType.Value
		end
		table.insert(Pets, {Pet.Name, Pet.Value, tostring(itemType or resolveItemType(Pet.Name))})
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
			return v[1], v[3]
		end
	end
end

Remotes.Egg.OnServerInvoke = function(Player, Egg, Amount)
	if Player.NonSaveValues.IsOpeningEgg.Value then return end -- cooldown
	if getTotalInventoryCount(Player) + Amount > getInventoryStorageLimit(Player) then return end -- max storage

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
			local itemName, itemType = ChooseRandomPet(Egg, LuckMultiplier)

			if itemName and not shouldAutoDelete(Player, itemName) then -- auto delete
				createInventoryItem(Player, itemName, itemType)
			end

			Results[i] = itemName
		end

		return Results
	end
end
