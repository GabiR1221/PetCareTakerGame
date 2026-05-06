local PetSaveManager = {}

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local SAVE_DEBOUNCE_SECONDS = 8
local FORCE_SAVE_AFTER_SECONDS = 60
local AUTOSAVE_INTERVAL_SECONDS = 120
local MAX_SAVE_RETRIES = 3
local MIN_SECONDS_BETWEEN_SAVES = 20
local WRITE_BUDGET_MINIMUM = 1

local function waitForWriteBudget()
	while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync) < WRITE_BUDGET_MINIMUM do
		task.wait(0.25)
	end
end

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
	self.dataStore = DataStoreService:GetDataStore(tostring(dataStoreName))

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
				baseScale = state.baseScale or state.scale or 1,
				dirtiness = state.dirtiness or 0,
				wetness = 0,
				hunger = state.hunger == nil and 100 or state.hunger,
				happiness = state.happiness == nil and 100 or state.happiness,
				fame = tonumber(state.fame) or 50,
				maxHunger = tonumber(state.maxHunger) or 100,
				maxHappiness = tonumber(state.maxHappiness) or 100,
				showered = state.showered or false,
				dried = true,
				accessories = state.accessories or { A = false, B = false },
				accessorySlots = state.accessorySlots or { A = nil, B = nil },
				equippedAccessoryName = state.equippedAccessoryName,
				accessoryBuffs = state.accessoryBuffs or { incomePercent = 0 },
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
		waitForWriteBudget()
		local success, err = pcall(function()
			self.dataStore:SetAsync(userId, petData)
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
	local now = os.clock()

	if not forceSave then
		local lastSaveAt = self.lastSaveAtByUserId[userId]
		if lastSaveAt and (now - lastSaveAt) < MIN_SECONDS_BETWEEN_SAVES then
			self.dirtyByUserId[userId] = true
			self:ScheduleSave(player, { force = false, bypassMinInterval = true })
			return true
		end
	end

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

	self.lastSaveAtByUserId[userId] = now
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
	options = type(options) == "table" and options or {}
	self.dirtyByUserId[userId] = true

	if self.pendingByUserId[userId] then
		return
	end

	self.pendingByUserId[userId] = true
	local delaySeconds = SAVE_DEBOUNCE_SECONDS
	local lastSaveAt = self.lastSaveAtByUserId[userId]
	if options.force ~= true and options.bypassMinInterval ~= true and lastSaveAt then
		local elapsed = os.clock() - lastSaveAt
		if elapsed < MIN_SECONDS_BETWEEN_SAVES then
			delaySeconds = math.max(delaySeconds, MIN_SECONDS_BETWEEN_SAVES - elapsed)
		end
	end
	task.delay(delaySeconds, function()
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
