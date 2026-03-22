local PetSaveManager = {}
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

function PetSaveManager:Initialize(dataStoreName, stateTable, carryingTable)
	self.petState = stateTable or {}
	self.carryingPetByUserId = carryingTable or {}
	self.dataStore = DataStoreService:GetDataStore("PetData1")
	self.saveQueue = {} -- userId -> data to save
	return self  -- ← ADD THIS LINE
end

-- Save all of a player's pets
function PetSaveManager:SavePlayerPets(player, pets)
	local userId = tostring(player.UserId)
	local petData = {}

	for pet, state in pairs(self.petState) do
		if state.ownerUserId == player.UserId and not state.wild then
			-- Save relevant pet data
			local templateName = pet:GetAttribute("TemplateName") or pet.Name
			local petInfo = {
				modelName = templateName,
				xp = state.xp or 0,
				level = state.level or 1,
				scale = state.scale or 1,
				dirtiness = state.dirtiness or 0,
				wetness = state.wetness or 0,
				showered = state.showered or false,
				dried = state.dried or false,
				accessories = state.accessories or {A = false, B = false},
				position = {x = 0, y = 0, z = 0},
				power = state.power or 1,
				rarityMultiplier = state.rarityMultiplier or 1,
			}
			table.insert(petData, petInfo)
		end
	end

	-- Save to DataStore
	local success, err = pcall(function()
		self.dataStore:SetAsync(userId, petData)
	end)

	if success then
		print(("[PetSaveManager] Saved %d pets for %s"):format(#petData, player.Name))
	else
		warn(("[PetSaveManager] Failed to save for %s: %s"):format(player.Name, err))
	end
end

-- Load pets for a player
function PetSaveManager:LoadPlayerPets(player)
	local userId = tostring(player.UserId)
	local success, petData = pcall(function()
		return self.dataStore:GetAsync(userId)
	end)

	if success and petData then
		print(("[PetSaveManager] Loaded %d pets for %s"):format(#petData, player.Name))
		return petData
	else
		print(("[PetSaveManager] No data found for %s"):format(player.Name))
		return {}
	end
end

-- Schedule a save for a player (debounced)
function PetSaveManager:ScheduleSave(player)
	if self.saveQueue[player] then
		return
	end

	self.saveQueue[player] = true
	task.delay(5, function()
		self:SavePlayerPets(player)
		self.saveQueue[player] = nil
	end)
end

return PetSaveManager
