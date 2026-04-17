local PetSaveManager = {}

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local SAVE_DEBOUNCE_SECONDS = 8
local FORCE_SAVE_AFTER_SECONDS = 60
local AUTOSAVE_INTERVAL_SECONDS = 120
local MAX_SAVE_RETRIES = 3

local function safeEncodeSignature(payload)
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if not ok then
		return nil
	end
	return encoded
end

function PetSaveManager:Initialize(dataStoreName, stateTable, carryingTable)
	self.petState = stateTable or {}
	self.carryingPetByUserId = carryingTable or {}
	self.dataStore = DataStoreService:GetDataStore(tostring(dataStoreName or "PetData55"))

	self.pendingByUserId = {} -- userId(string) -> true while debounce timer exists
	self.dirtyByUserId = {} -- userId(string) -> true if data changed since last successful save
	self.lastSavedSignatureByUserId = {}
	self.lastSaveAtByUserId = {}
	self._autoSaveStarted = false
	self:_startAutoSaveLoop()
	return self
end

function PetSaveManager:_collectPetDataForPlayer(player)
	local petData = {}

	for pet, state in pairs(self.petState) do
		if state and state.ownerUserId == player.UserId and not state.wild then
			local templateName = pet:GetAttribute("TemplateName") or pet.Name

			local standRoot = state.petstandRoot
			local standId = nil
			local storedMoney = nil

			if standRoot then
				standId = standRoot:GetAttribute("StandId")
				local storedValue = standRoot:FindFirstChild("StoredMoney")
				if storedValue and storedValue:IsA("NumberValue") then
					storedMoney = storedValue.Value
				end
			end

			local petInfo = {
				modelName = templateName,
				petUid = state.petUid or pet:GetAttribute("PetUID"),
				xp = state.xp or 0,
				level = state.level or 1,
				scale = state.scale or 1,
				dirtiness = state.dirtiness or 0,
				wetness = state.wetness or 0,
				hunger = state.hunger == nil and 100 or state.hunger,
				showered = state.showered or false,
				dried = state.dried or false,
				accessories = state.accessories or { A = false, B = false },
				position = { x = 0, y = 0, z = 0 },
				power = state.power or 1,
				rarityMultiplier = state.rarityMultiplier or 1,
				location = state.location or "free",
				standId = standId,
				standStoredMoney = storedMoney or 0,
			}

			table.insert(petData, petInfo)
		end
	end

	table.sort(petData, function(a, b)
		local aUid = tostring(a.petUid or "")
		local bUid = tostring(b.petUid or "")
		if aUid == bUid then
			return tostring(a.modelName or "") < tostring(b.modelName or "")
		end
		return aUid < bUid
	end)

	return petData
end

function PetSaveManager:_savePayload(userId, petData)
	for attempt = 1, MAX_SAVE_RETRIES do
		local success, err = pcall(function()
			self.dataStore:UpdateAsync(userId, function(_old)
				return petData
			end)
		end)

		if success then
			return true
		end

		if attempt < MAX_SAVE_RETRIES then
			task.wait(1.5 * attempt)
		else
			warn(("[PetSaveManager] Failed to save userId %s after %d attempts: %s")
				:format(userId, MAX_SAVE_RETRIES, tostring(err)))
		end
	end

	return false
end

function PetSaveManager:SavePlayerPets(player, options)
	if not player or not player:IsA("Player") then return false end

	local userId = tostring(player.UserId)
	local forceSave = type(options) == "table" and options.force == true
	local petData = self:_collectPetDataForPlayer(player)
	local signature = safeEncodeSignature(petData)

	if not forceSave then
		local previousSignature = self.lastSavedSignatureByUserId[userId]
		local wasDirty = self.dirtyByUserId[userId] == true
		if not wasDirty and signature ~= nil and previousSignature ~= nil and signature == previousSignature then
			return true
		end
	end

	local saved = self:_savePayload(userId, petData)
	if not saved then
		self.dirtyByUserId[userId] = true
		return false
	end

	self.lastSaveAtByUserId[userId] = os.clock()
	self.dirtyByUserId[userId] = nil
	if signature ~= nil then
		self.lastSavedSignatureByUserId[userId] = signature
	end

	print(("[PetSaveManager] Saved %d pets for %s"):format(#petData, player.Name))
	return true
end

function PetSaveManager:LoadPlayerPets(player)
	local userId = tostring(player.UserId)
	local success, petData = pcall(function()
		return self.dataStore:GetAsync(userId)
	end)

	if success and petData then
		print(("[PetSaveManager] Loaded %d pets for %s"):format(#petData, player.Name))
		local signature = safeEncodeSignature(petData)
		if signature ~= nil then
			self.lastSavedSignatureByUserId[userId] = signature
		end
		self.lastSaveAtByUserId[userId] = os.clock()
		self.dirtyByUserId[userId] = nil
		return petData
	end

	if not success then
		warn(("[PetSaveManager] Load failed for %s (%s)"):format(player.Name, tostring(petData)))
	else
		print(("[PetSaveManager] No data found for %s"):format(player.Name))
	end
	return {}
end

function PetSaveManager:ScheduleSave(player, options)
	if not player or not player:IsA("Player") then return end

	local userId = tostring(player.UserId)
	self.dirtyByUserId[userId] = true

	if self.pendingByUserId[userId] then
		return
	end

	self.pendingByUserId[userId] = true
	task.delay(SAVE_DEBOUNCE_SECONDS, function()
		self.pendingByUserId[userId] = nil
		if not player.Parent then return end
		self:SavePlayerPets(player, options)
	end)
end

function PetSaveManager:_flushDirtyPlayers(force)
	for _, player in ipairs(Players:GetPlayers()) do
		local userId = tostring(player.UserId)
		local secondsSinceSave = os.clock() - (self.lastSaveAtByUserId[userId] or 0)
		if force or self.dirtyByUserId[userId] == true or secondsSinceSave >= FORCE_SAVE_AFTER_SECONDS then
			self:SavePlayerPets(player, { force = force })
		end
	end
end

function PetSaveManager:_startAutoSaveLoop()
	if self._autoSaveStarted == true then return end
	self._autoSaveStarted = true

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL_SECONDS)
			self:_flushDirtyPlayers(false)
		end
	end)

	game:BindToClose(function()
		self:_flushDirtyPlayers(true)
	end)
end

return PetSaveManager
