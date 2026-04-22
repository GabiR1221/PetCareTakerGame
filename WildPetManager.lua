---WildPetManagerModule
local WildPetManager = {}
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local INVENTORY_BRIDGE_NAME = "PetInventoryAdoptionBridge"
local HttpService = game:GetService("HttpService")

local function normalizePetName(name)
	if not name then return "" end
	return string.lower((tostring(name):gsub("^%s+", ""):gsub("%s+$", "")))
end

local function buildOwnedPetCsv(nameSet)
	local list = {}
	for petName, _ in pairs(nameSet) do
		table.insert(list, petName)
	end
	table.sort(list)
	return table.concat(list, ",")
end

local function grantAdoptedPetToInventory(player, petModel)
	if not player or not petModel then return end
	local templateName = petModel:GetAttribute("TemplateName") or petModel.Name
	if type(templateName) ~= "string" or templateName == "" then return end
	local petUid = petModel:GetAttribute("PetUID")
	if type(petUid) ~= "string" or petUid == "" then
		petUid = HttpService:GenerateGUID(false)
		petModel:SetAttribute("PetUID", petUid)
	end

	local bridge = ReplicatedStorage:FindFirstChild(INVENTORY_BRIDGE_NAME)
	if bridge and bridge:IsA("BindableEvent") then
		bridge:Fire(player, templateName, petUid)
	end
end

local function ensurePetUid(modelOrStateCarrier)
	if not modelOrStateCarrier then return nil end
	local uid = modelOrStateCarrier:GetAttribute("PetUID")
	if type(uid) == "string" and uid ~= "" then
		return uid
	end

	uid = HttpService:GenerateGUID(false)
	modelOrStateCarrier:SetAttribute("PetUID", uid)
	return uid
end


function WildPetManager:Initialize(stateTable, carryingTable, playersService, petMovement, config, saveManager)
	self.petState = stateTable or {}
	self.carryingPetByUserId = carryingTable or {}
	self.Players = playersService
	self.PetMovement = petMovement
	self.Config = config or {}

	-- Load dependencies
	self.PetAttachmentManager = require(script.Parent.PetAttachmentManager)
	self.PetStateManager = require(script.Parent.PetStateManager)
	self.PetRigManager = require(script.Parent.PetRigManager)
	self.PetAnimationManager = require(script.Parent.PetAnimationManager)
	self.PetMoodVisualManager = require(script.Parent.PetMoodVisualManager)
	self.PromptManager = require(script.Parent.PromptManager)
	self.TycoonUtils = require(script.Parent.TycoonUtils)
	self.TycoonUtils:Initialize(config)  -- Initialize TycoonUtils with the config
	self.SaveManager = saveManager
	self.PetStandManager = require(script.Parent.PetStandManager)
	self.Multipliers = require(ReplicatedStorage.Modules.Multipliers)
	-- Settings
	self.WILD_PET_SPAWN_AREA_TAG = "WildPetSpawnArea"
	self.MAX_WILD_PETS = 20
	self.SPAWN_INTERVAL = 30 -- seconds
	self.MIN_SPAWN_INTERVAL = 12
	self.MAX_SPAWN_INTERVAL = 30
	self.INITIAL_SPAWN_PER_ZONE = 3
	self.MAX_WILD_PETS_PER_AREA = 3
	self.WANDER_RADIUS = 50
	self.WILD_PET_MODELS = ServerStorage:FindFirstChild("WildPetModels") or ServerStorage:FindFirstChild("PetModels")
	self.WILD_PET_ZONE_FOLDER = "Zones"

	-- Trackers
	self.wildPets = {} -- petModel -> spawnArea part
	self.wildPetPickupConns = {} -- petModel -> connection
	self.spawnAreas = {} -- spawn area parts
	self.adoptionMats = {} -- adoption mat parts
	self.ownedPetPickupConns = {}  -- petModel -> connection for owned pets
	self.petTemplates = {}

	-- Initialize
	self:FindSpawnAreas()
	self:FindAdoptionMats()
	self:RefreshPetTemplates()
	self:BindRebirthResetEvent()
	self:StartSpawning()
end

function WildPetManager:GetAdoptionMatForTycoon(tycoonModel)
	for mat, tModel in pairs(self.adoptionMats) do
		if tModel == tycoonModel then
			return mat
		end
	end
	return nil
end

function WildPetManager:GetOwnerWanderZonePart(ownerUserId)
	if not ownerUserId then return nil end
	local tycoonModel = self.TycoonUtils:FindTycoonByOwnerId(ownerUserId)
	if not tycoonModel then return nil end

	local zonePartName = tostring(tycoonModel:GetAttribute("PetWanderZonePartName") or "PetWanderZone")
	local zonePart = self.TycoonUtils:FindPartByNameInModel(tycoonModel, zonePartName)
	if zonePart and zonePart:IsA("BasePart") then
		return zonePart
	end

	return nil
end

function WildPetManager:CanGrantPetToInventory(player)
	if not player then return false end
	local data = player:FindFirstChild("Data")
	local petsFolder = data and data:FindFirstChild("Pets")
	if not petsFolder then return false end

	local maxStorage = self.Multipliers.GetMaxPetsStorage(player)
	return #petsFolder:GetChildren() < maxStorage
end

function WildPetManager:GrantOwnedPetFromTemplate(player, templateName)
	if not player or type(templateName) ~= "string" or templateName == "" then
		return false, "InvalidInput"
	end
	if not self:CanGrantPetToInventory(player) then
		return false, "InventoryFull"
	end

	local template = self:FindPetTemplateByName(templateName)
	if not template then
		return false, "TemplateMissing"
	end

	local tycoonModel, _ = self.TycoonUtils:FindTycoonByOwnerIdWithDesk(player.UserId)
	if not tycoonModel then
		return false, "TycoonMissing"
	end

	local adoptionMat = self:GetAdoptionMatForTycoon(tycoonModel)
	if not adoptionMat then
		return false, "AdoptionMatMissing"
	end

	local pet = template:Clone()
	pet.Name = templateName
	pet:SetAttribute("TemplateName", templateName)
	local petUid = ensurePetUid(pet)
	pet.Parent = workspace
	local detectedBaseScale = 1.0
	pcall(function()
		detectedBaseScale = tonumber(pet:GetScale()) or 1.0
	end)

	local power = template:GetAttribute("Power") or 1
	local rarityMult = template:GetAttribute("RarityMultiplier") or 1
	pet:SetAttribute("Power", power)
	pet:SetAttribute("RarityMultiplier", rarityMult)

	self.petState[pet] = {
		location = "free",
		wild = false,
		ownerUserId = player.UserId,
		xp = 0,
		level = 1,
		scale = detectedBaseScale,
		baseScale = detectedBaseScale,
		dirtiness = 0,
		wetness = 0,
		hunger = 100,
		happiness = 100,
		showered = true,
		dried = true,
		accessories = {A = false, B = false},
		power = power,
		rarityMultiplier = rarityMult,
		petUid = petUid,
	}

	pet:SetAttribute("WildPet", false)

	self.PetRigManager:EnsurePetRig(pet)
	self.PetAnimationManager:SetupAnimatorForPet(pet)
	self:PlacePetOnGround(pet, adoptionMat.Position)
	local wanderZone = self:GetOwnerWanderZonePart(player.UserId)
	self.PetMovement.StartWandering(pet, adoptionMat.Position, 20, player.UserId, wanderZone)
	self:AddOwnedPetPickupPrompt(pet, player.UserId)

	grantAdoptedPetToInventory(player, pet)
	self:UpdateOwnedPetRegistryForPlayer(player)
	if self.SaveManager then
		self.SaveManager:ScheduleSave(player)
	end

	return true, pet
end


function WildPetManager:CountWildPets()
	local count = 0
	for petModel, spawnArea in pairs(self.wildPets) do
		if petModel and petModel.Parent and spawnArea and spawnArea.Parent then
			count += 1
		end
	end
	return count
end

function WildPetManager:CountWildPetsInSpawnArea(spawnArea)
	if not spawnArea then return 0 end
	local count = 0
	for petModel, area in pairs(self.wildPets) do
		if petModel and petModel.Parent and area == spawnArea then
			count += 1
		end
	end
	return count
end

function WildPetManager:CleanupDestroyedWildPets()
	for pet, _ in pairs(self.wildPets) do
		if not pet or not pet.Parent then
			self.wildPets[pet] = nil
			if self.wildPetPickupConns[pet] then
				self.wildPetPickupConns[pet]:Disconnect()
				self.wildPetPickupConns[pet] = nil
			end
		end
	end
end

function WildPetManager:GetRandomSpawnInterval()
	local minInterval = tonumber(self.MIN_SPAWN_INTERVAL) or tonumber(self.SPAWN_INTERVAL) or 30
	local maxInterval = tonumber(self.MAX_SPAWN_INTERVAL) or minInterval
	if maxInterval < minInterval then
		minInterval, maxInterval = maxInterval, minInterval
	end
	return minInterval + math.random() * (maxInterval - minInterval)
end

function WildPetManager:FindSafeSpawnPosition(spawnArea, pet)
	if not spawnArea or not pet then return nil end

	local extents = pet:GetExtentsSize()
	local petHalfHeight = math.max(1, (extents.Y * 0.5))

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {pet}

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {pet, spawnArea}

	local halfSize = spawnArea.Size * 0.5
	local tries = 20
	for _ = 1, tries do
		local randomOffsetX = (math.random() - 0.5) * spawnArea.Size.X
		local randomOffsetZ = (math.random() - 0.5) * spawnArea.Size.Z
		local sampleOrigin = spawnArea.Position + Vector3.new(randomOffsetX, halfSize.Y + 25, randomOffsetZ)

		local rayResult = workspace:Raycast(sampleOrigin, Vector3.new(0, -80, 0), raycastParams)
		if rayResult and rayResult.Position then
			local candidatePos = Vector3.new(
				rayResult.Position.X,
				rayResult.Position.Y + petHalfHeight + 0.1,
				rayResult.Position.Z
			)

			local clearanceSize = extents + Vector3.new(0.75, 0.75, 0.75)
			local hits = workspace:GetPartBoundsInBox(CFrame.new(candidatePos), clearanceSize, overlapParams)
			local blocked = false
			for _, hit in ipairs(hits) do
				if hit and hit.CanCollide and hit:IsDescendantOf(workspace) then
					blocked = true
					break
				end
			end

			if not blocked then
				return candidatePos
			end
		end
	end

	return nil
end


function WildPetManager:_resetDirtVisualCache(pet)
	if not pet or not pet:IsA("Model") then return end
	local dirtFolder = pet:FindFirstChild("Dirt")
	if not dirtFolder then return end

	for _, item in ipairs(dirtFolder:GetDescendants()) do
		if item:IsA("BasePart") then
			item:SetAttribute("BaseDirtTransparency", nil)
			item:SetAttribute("ShowerStartTransparency", nil)
		end
	end
end


function WildPetManager:BindRebirthResetEvent()
	local resetEvent = ReplicatedStorage:FindFirstChild("PetSystemClearPlayerPets")
	if not resetEvent or not resetEvent:IsA("BindableEvent") then
		resetEvent = Instance.new("BindableEvent")
		resetEvent.Name = "PetSystemClearPlayerPets"
		resetEvent.Parent = ReplicatedStorage
	end

	if self._rebirthResetConn then
		pcall(function() self._rebirthResetConn:Disconnect() end)
		self._rebirthResetConn = nil
	end

	self._rebirthResetConn = resetEvent.Event:Connect(function(userId)
		local numericUserId = tonumber(userId)
		if not numericUserId then return end
		local player = self.Players:GetPlayerByUserId(numericUserId)
		if not player then return end
		self:ClearPlayerPetsForRebirth(player)
	end)
end

function WildPetManager:ClearPlayerPetsForRebirth(player)
	if not player then return end

	if self.carryingPetByUserId[player.UserId] then
		self.carryingPetByUserId[player.UserId] = nil
	end

	local petsToRemove = {}
	for petModel, state in pairs(self.petState) do
		if state and tostring(state.ownerUserId) == tostring(player.UserId) then
			table.insert(petsToRemove, petModel)
		end
	end

	for _, petModel in ipairs(petsToRemove) do
		local state = self.petState[petModel]
		if state and state.petstandRoot then
			local storedMoney = state.petstandRoot:FindFirstChild("StoredMoney")
			if storedMoney and storedMoney:IsA("NumberValue") then
				storedMoney.Value = 0
			end
		end

		if self.wildPetPickupConns[petModel] then
			pcall(function() self.wildPetPickupConns[petModel]:Disconnect() end)
			self.wildPetPickupConns[petModel] = nil
		end
		if self.ownedPetPickupConns[petModel] then
			pcall(function() self.ownedPetPickupConns[petModel]:Disconnect() end)
			self.ownedPetPickupConns[petModel] = nil
		end

		self.wildPets[petModel] = nil
		self.petState[petModel] = nil

		if petModel and petModel.Parent then
			pcall(function() petModel:Destroy() end)
		end
	end

	self:UpdateOwnedPetRegistryForPlayer(player)
	if self.SaveManager then
		self.SaveManager:ScheduleSave(player)
	end
end

function WildPetManager:RemoveOwnedPetByUid(player, petUid)
	if not player or type(petUid) ~= "string" or petUid == "" then
		return false, 0
	end

	local removedCount = 0
	local petsToRemove = {}

	for petModel, state in pairs(self.petState) do
		if petModel and state and not state.wild and tostring(state.ownerUserId) == tostring(player.UserId) then
			local stateUid = tostring(state.petUid or petModel:GetAttribute("PetUID") or "")
			if stateUid == petUid then
				table.insert(petsToRemove, petModel)
			end
		end
	end

	for _, petModel in ipairs(petsToRemove) do
		if self.carryingPetByUserId[player.UserId] == petModel then
			self.carryingPetByUserId[player.UserId] = nil
		end

		if self.wildPetPickupConns[petModel] then
			pcall(function() self.wildPetPickupConns[petModel]:Disconnect() end)
			self.wildPetPickupConns[petModel] = nil
		end
		if self.ownedPetPickupConns[petModel] then
			pcall(function() self.ownedPetPickupConns[petModel]:Disconnect() end)
			self.ownedPetPickupConns[petModel] = nil
		end

		self.wildPets[petModel] = nil
		self.petState[petModel] = nil

		if petModel.Parent then
			pcall(function() petModel:Destroy() end)
		end
		removedCount += 1
	end

	if removedCount > 0 then
		self:UpdateOwnedPetRegistryForPlayer(player)
		if self.SaveManager then
			self.SaveManager:ScheduleSave(player)
		end
	end

	return removedCount > 0, removedCount
end

function WildPetManager:RemoveOneOwnedPetByName(player, petName)
	if not player or type(petName) ~= "string" or petName == "" then
		return false
	end

	local normalizedTarget = normalizePetName(petName)
	local candidate = nil
	local carryingCandidate = self.carryingPetByUserId[player.UserId]

	for petModel, state in pairs(self.petState) do
		if petModel and state and not state.wild and tostring(state.ownerUserId) == tostring(player.UserId) then
			local templateName = tostring(petModel:GetAttribute("TemplateName") or petModel.Name or "")
			if normalizePetName(templateName) == normalizedTarget then
				if carryingCandidate and carryingCandidate == petModel then
					candidate = petModel
					break
				end
				candidate = candidate or petModel
			end
		end
	end

	if not candidate then
		return false
	end

	if self.carryingPetByUserId[player.UserId] == candidate then
		self.carryingPetByUserId[player.UserId] = nil
	end

	if self.wildPetPickupConns[candidate] then
		pcall(function() self.wildPetPickupConns[candidate]:Disconnect() end)
		self.wildPetPickupConns[candidate] = nil
	end
	if self.ownedPetPickupConns[candidate] then
		pcall(function() self.ownedPetPickupConns[candidate]:Disconnect() end)
		self.ownedPetPickupConns[candidate] = nil
	end

	self.wildPets[candidate] = nil
	self.petState[candidate] = nil

	if candidate.Parent then
		pcall(function() candidate:Destroy() end)
	end

	self:UpdateOwnedPetRegistryForPlayer(player)
	if self.SaveManager then
		self.SaveManager:ScheduleSave(player)
	end

	return true
end


function WildPetManager:UpdateOwnedPetRegistryForPlayer(player)
	if not player then return end
	local playerDataRoot = ServerStorage:FindFirstChild("PlayerData")
	if not playerDataRoot then return end
	local playerFolder = playerDataRoot:FindFirstChild(tostring(player.UserId))
	if not playerFolder then return end

	local ownedPetNames = {}
	for petModel, state in pairs(self.petState) do
		if petModel and petModel.Parent and state and not state.wild and tostring(state.ownerUserId) == tostring(player.UserId) then
			local templateName = petModel:GetAttribute("TemplateName") or petModel.Name
			local normalized = normalizePetName(templateName)
			if normalized ~= "" then
				ownedPetNames[normalized] = true
			end
		end
	end

	playerFolder:SetAttribute("OwnedPetNamesCsv", buildOwnedPetCsv(ownedPetNames))
end



function WildPetManager:FindSpawnAreas()
	print("[WildPetManager] Scanning for wild pet spawn areas...")

	-- Method 1: CollectionService tag
	for _, part in ipairs(CollectionService:GetTagged(self.WILD_PET_SPAWN_AREA_TAG)) do
		if part:IsA("BasePart") then
			table.insert(self.spawnAreas, part)
			print(("[WildPetManager] Found spawn area: %s"):format(part:GetFullName()))
		end
	end

	-- Method 2: Look for parts named "WildPetSpawnArea"
	for _, part in ipairs(workspace:GetDescendants()) do
		if part:IsA("BasePart") and part.Name == "WildPetSpawnArea" then
			if not table.find(self.spawnAreas, part) then
				table.insert(self.spawnAreas, part)
				print(("[WildPetManager] Found spawn area by name: %s"):format(part:GetFullName()))
			end
		end
	end

	-- Method 3: Look in a folder
	local spawnFolder = workspace:FindFirstChild("WildPetSpawns")
	if spawnFolder then
		for _, part in ipairs(spawnFolder:GetChildren()) do
			if part:IsA("BasePart") then
				if not table.find(self.spawnAreas, part) then
					table.insert(self.spawnAreas, part)
					print(("[WildPetManager] Found spawn area in folder: %s"):format(part:GetFullName()))
				end
			end
		end
	end
end

function WildPetManager:_CollectPetModels(rootFolder)
	local list = {}

	for _, child in ipairs(rootFolder:GetDescendants()) do
		if child:IsA("Model") and (child.Parent == rootFolder or not child.Parent:IsA("Model")) then
			local hasPhysicalPart = child.PrimaryPart ~= nil or child:FindFirstChildWhichIsA("BasePart", true) ~= nil
			if hasPhysicalPart then
				table.insert(list, child)
			end
		end
	end

	return list
end

function WildPetManager:RefreshPetTemplates()
	self.petTemplates = {}

	if not self.WILD_PET_MODELS then
		warn("[WildPetManager] WildPetModels/PetModels folder was not found in ServerStorage")
		return
	end

	for _, child in ipairs(self.WILD_PET_MODELS:GetChildren()) do
		if child:IsA("Model") then
			local hasPhysicalPart = child.PrimaryPart ~= nil or child:FindFirstChildWhichIsA("BasePart", true) ~= nil
			if hasPhysicalPart then
				table.insert(self.petTemplates, child)
			end
		elseif child:IsA("Folder") then
			for _, model in ipairs(self:_CollectPetModels(child)) do
				table.insert(self.petTemplates, model)
			end
		end
	end

	print(("[WildPetManager] Loaded %d pet templates for wild spawn"):format(#self.petTemplates))
end

function WildPetManager:GetWeightedRandomTemplate()
	if #self.petTemplates == 0 then
		return nil
	end

	local totalWeight = 0
	for _, model in ipairs(self.petTemplates) do
		local weight = tonumber(model:GetAttribute("SpawnWeight"))
			or tonumber(model:GetAttribute("Weight"))
			or tonumber(model:GetAttribute("RarityWeight"))
			or 1
		if weight > 0 then
			totalWeight = totalWeight + weight
		end
	end

	if totalWeight <= 0 then
		return self.petTemplates[math.random(1, #self.petTemplates)]
	end

	local pick = math.random() * totalWeight
	local running = 0
	for _, model in ipairs(self.petTemplates) do
		local weight = tonumber(model:GetAttribute("SpawnWeight"))
			or tonumber(model:GetAttribute("Weight"))
			or tonumber(model:GetAttribute("RarityWeight"))
			or 1
		if weight > 0 then
			running = running + weight
			if pick <= running then
				return model
			end
		end
	end

	return self.petTemplates[#self.petTemplates]
end

function WildPetManager:FindPetTemplateByName(templateName)
	if not self.WILD_PET_MODELS or not templateName then
		local replicatedPets = ReplicatedStorage:FindFirstChild("Pets")
		if replicatedPets then
			local fallback = replicatedPets:FindFirstChild(templateName)
			if fallback and fallback:IsA("Model") then
				return fallback
			end
		end
		return nil
	end

	local direct = self.WILD_PET_MODELS:FindFirstChild(templateName)
	if direct and direct:IsA("Model") then
		return direct
	end

	for _, candidate in ipairs(self.WILD_PET_MODELS:GetDescendants()) do
		if candidate:IsA("Model") and candidate.Name == templateName then
			return candidate
		end
	end

	local replicatedPets = ReplicatedStorage:FindFirstChild("Pets")
	if replicatedPets then
		local fallback = replicatedPets:FindFirstChild(templateName)
		if fallback and fallback:IsA("Model") then
			return fallback
		end
	end

	return nil
end

function WildPetManager:FindAdoptionMats()

	-- Look for parts named "AdoptionMat" in Essentials folders
	for _, model in ipairs(workspace:GetDescendants()) do
		if model:IsA("Model") then
			local ess = model:FindFirstChild("Essentials")
			if ess then
				local adoptionMat = ess:FindFirstChild("AdoptionMat")
				if adoptionMat and adoptionMat:IsA("BasePart") then
					self.adoptionMats[adoptionMat] = model
					print(("[WildPetManager] Found adoption mat: %s in tycoon: %s"):format(
						adoptionMat:GetFullName(), model.Name))
				end
			end
		end
	end

	-- Also look for standalone adoption mats
	for _, part in ipairs(workspace:GetDescendants()) do
		if part:IsA("BasePart") and part.Name == "AdoptionMat" then
			if not self.adoptionMats[part] then
				-- Find which tycoon it belongs to
				local tycoonModel = nil
				local current = part.Parent
				while current do
					if current:IsA("Model") or current:IsA("Folder") then
						local ess = current:FindFirstChild("Essentials")
						if ess then
							tycoonModel = current
							break
						end
					end
					current = current.Parent
				end

				self.adoptionMats[part] = tycoonModel
				print(("[WildPetManager] Found standalone adoption mat: %s"):format(part:GetFullName()))
			end
		end
	end
end



function WildPetManager:GetZoneIdForSpawnArea(spawnArea)
	if not spawnArea then return nil end
	local zone = spawnArea:GetAttribute("ZoneId") or spawnArea:GetAttribute("WildPetZone")
	if zone and tostring(zone) ~= "" then
		return tostring(zone)
	end
	local parentZone = spawnArea:FindFirstAncestor("WildPetZones")
	if parentZone then
		return spawnArea.Parent and spawnArea.Parent.Name or nil
	end
	return nil
end

function WildPetManager:LooksLikeZoneFolder(folder)
	if not folder or not folder:IsA("Folder") then
		return false
	end
	if folder.Name == self.WILD_PET_ZONE_FOLDER then
		return false
	end
	local hasZoneAttr = folder:GetAttribute("ZoneId") ~= nil or folder:GetAttribute("WildPetZone") ~= nil
	if hasZoneAttr then
		return true
	end
	return string.match(string.lower(folder.Name), "^zone%d*$") ~= nil
end

function WildPetManager:GetZoneFolder(zoneId)
	if not self.WILD_PET_MODELS or not zoneId then
		return nil
	end
	local zoneIdStr = tostring(zoneId)
	local numericZone = tonumber(zoneIdStr)
	local candidateNames = { zoneIdStr }
	if numericZone then
		table.insert(candidateNames, ("Zone%d"):format(numericZone))
	end
	if string.sub(string.lower(zoneIdStr), 1, 4) == "zone" then
		local suffix = string.sub(zoneIdStr, 5)
		if tonumber(suffix) then
			table.insert(candidateNames, tostring(tonumber(suffix)))
		end
	else
		table.insert(candidateNames, "Zone" .. zoneIdStr)
	end

	local zonesRoot = self.WILD_PET_MODELS:FindFirstChild(self.WILD_PET_ZONE_FOLDER)
	if zonesRoot then
		for _, name in ipairs(candidateNames) do
			local nested = zonesRoot:FindFirstChild(name)
			if nested and nested:IsA("Folder") then
				return nested
			end
		end
	end

	for _, name in ipairs(candidateNames) do
		local direct = self.WILD_PET_MODELS:FindFirstChild(name)
		if direct and direct:IsA("Folder") then
			return direct
		end
	end

	for _, child in ipairs(self.WILD_PET_MODELS:GetChildren()) do
		if child:IsA("Folder") and self:LooksLikeZoneFolder(child) then
			local lowerName = string.lower(child.Name)
			for _, name in ipairs(candidateNames) do
				if lowerName == string.lower(tostring(name)) then
					return child
				end
			end
		end
	end
	return nil
end

function WildPetManager:GetTemplatesForSpawnArea(spawnArea)
	if #self.petTemplates == 0 then
		self:RefreshPetTemplates()
	end

	if #self.petTemplates == 0 then
		return {}
	end

	local allowList = spawnArea and spawnArea:GetAttribute("AllowedPets")
	if allowList and tostring(allowList) ~= "" then
		local allowed = {}
		for token in string.gmatch(tostring(allowList), "[^,]+") do
			allowed[string.lower((token:gsub("^%s+",""):gsub("%s+$","")))] = true
		end
		local filtered = {}
		for _, model in ipairs(self.petTemplates) do
			if allowed[string.lower(model.Name)] then
				table.insert(filtered, model)
			end
		end
		if #filtered > 0 then
			return filtered
		end
	end

	local zoneId = self:GetZoneIdForSpawnArea(spawnArea)
	if not zoneId or not self.WILD_PET_MODELS then
		return self.petTemplates
	end

	local zoneFolder = self:GetZoneFolder(zoneId)
	if not zoneFolder then
		return self.petTemplates
	end

	local zoneTemplates = self:_CollectPetModels(zoneFolder)
	if #zoneTemplates > 0 then
		return zoneTemplates
	end

	return self.petTemplates
end

function WildPetManager:GetWeightedRandomTemplateFromList(templateList)
	if not templateList or #templateList == 0 then
		return nil
	end

	local totalWeight = 0
	for _, model in ipairs(templateList) do
		local weight = tonumber(model:GetAttribute("SpawnWeight"))
			or tonumber(model:GetAttribute("Weight"))
			or tonumber(model:GetAttribute("RarityWeight"))
			or 1
		if weight > 0 then
			totalWeight = totalWeight + weight
		end
	end

	if totalWeight <= 0 then
		return templateList[math.random(1, #templateList)]
	end

	local pick = math.random() * totalWeight
	local running = 0
	for _, model in ipairs(templateList) do
		local weight = tonumber(model:GetAttribute("SpawnWeight"))
			or tonumber(model:GetAttribute("Weight"))
			or tonumber(model:GetAttribute("RarityWeight"))
			or 1
		if weight > 0 then
			running = running + weight
			if pick <= running then
				return model
			end
		end
	end

	return templateList[#templateList]
end

function WildPetManager:_pickupWildPetForPlayer(pet, player, helper)
	if self.carryingPetByUserId[player.UserId] then
		return false
	end

	local state = self.petState[pet]
	if not state or not state.wild then
		return false
	end

	local opts = nil
	if player and player:GetAttribute("RunnerJumping") == true then
		opts = { attachToHand = true }
	end
	local ok, err = self.PetAttachmentManager:AttachWildPetToPlayer(pet, player, opts)
	if ok then
		self.petState[pet].location = "player_wild"
		self.petState[pet].carrierUserId = player.UserId
		self.PetMovement.StopWandering(pet)
		self.wildPets[pet] = nil

		if self.wildPetPickupConns[pet] then
			self.wildPetPickupConns[pet]:Disconnect()
			self.wildPetPickupConns[pet] = nil
		end
		if helper then
			pcall(function() helper:Destroy() end)
		end

		print(("[WildPetManager] Player %s picked up wild pet %s"):format(player.Name, pet.Name))
		return true
	else
		warn("[WildPetManager] Failed to attach wild pet:", err)
	end
	return false
end

function WildPetManager:TryAutoPickupWildPet(player, pet)
	if not player or not pet or not pet:IsA("Model") then return false end
	return self:_pickupWildPetForPlayer(pet, player, pet:FindFirstChild("WildPetPickupPart"))
end

function WildPetManager:NormalizeRunnerCaughtPetHold(player)
	if not player then return false end
	local pet = self.carryingPetByUserId[player.UserId]
	if not pet or not pet.Parent then return false end

	local state = self.petState[pet]
	if not state or not state.wild or state.location ~= "player_wild" then
		return false
	end
	if state.carrierUserId and tostring(state.carrierUserId) ~= tostring(player.UserId) then
		return false
	end

	local ok = self.PetAttachmentManager:AttachWildPetToPlayer(pet, player)
	if not ok then
		return false
	end

	state.location = "player_wild"
	state.carrierUserId = player.UserId
	return true
end

function WildPetManager:AutoAdoptCarriedWildPet(player, options)
	options = options or {}
	if not player then return false end
	local pet = self.carryingPetByUserId[player.UserId]
	if not pet or not pet.Parent then return false end

	local state = self.petState[pet]
	if not state or not state.wild then
		return false
	end

	state.ownerUserId = player.UserId
	state.wild = false
	state.location = "free"
	state.carrierUserId = nil
	state.petUid = ensurePetUid(pet)
	pet:SetAttribute("WildPet", false)
	self:_resetDirtVisualCache(pet)

	-- Ensure adopted pets do NOT remain attached to the player.
	-- We explicitly drop to world + re-rig + restart wander from adoption mat
	-- to avoid carry-state stutter and to make reload behavior consistent.
	self.PetAttachmentManager:DetachPetFromPlayer(pet)
	pet.Parent = workspace

	local dropPosition = nil
	if typeof(options.adoptionPosition) == "Vector3" then
		dropPosition = options.adoptionPosition
	else
		local tycoonModel, _ = self.TycoonUtils:FindTycoonByOwnerIdWithDesk(player.UserId)
		local adoptionMat = tycoonModel and self:GetAdoptionMatForTycoon(tycoonModel)
		dropPosition = adoptionMat and adoptionMat.Position or nil
	end

	pcall(function()
		self.PetRigManager:EnsurePetRig(pet)
		self.PetAnimationManager:SetupAnimatorForPet(pet)
	end)

	if dropPosition then
		self:PlacePetOnGround(pet, dropPosition)
		local wanderZone = self:GetOwnerWanderZonePart(player.UserId)
		self.PetMovement.StartWandering(pet, dropPosition, 20, player.UserId, wanderZone)
	else
		-- safe fallback if adoption mat can't be resolved
		local char = player.Character
		local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
		if root then
			self:PlacePetOnGround(pet, root.Position + (root.CFrame.LookVector * 3))
			local wanderZone = self:GetOwnerWanderZonePart(player.UserId)
			self.PetMovement.StartWandering(pet, root.Position, 20, player.UserId, wanderZone)
		else
			self.PetMovement.StartWandering(pet)
		end
	end
	self:AddOwnedPetPickupPrompt(pet, player.UserId)

	local adoptionEvent = ReplicatedStorage:FindFirstChild("PetAdoptionEvent")
	if adoptionEvent and adoptionEvent:IsA("RemoteEvent") then
		adoptionEvent:FireClient(player, "PetAdopted", pet)
	end

	grantAdoptedPetToInventory(player, pet)

	self:UpdateOwnedPetRegistryForPlayer(player)
	if self.SaveManager then
		self.SaveManager:ScheduleSave(player)
	end

	self.PetStateManager:AddXP(pet, 1)
	self.PetStateManager:SendStateToOwner(pet)
	if self.PetMoodVisualManager and self.PetMoodVisualManager.UpdatePetVisuals then
		task.defer(function()
			pcall(function()
				self.PetMoodVisualManager:UpdatePetVisuals(pet)
			end)
		end)
	end

	print(("[WildPetManager] Auto-adopted pet %s for %s"):format(pet.Name, player.Name))
	return true
end



function WildPetManager:SpawnWildPet(preferredSpawnArea)
	-- Check if we have spawn areas and haven't reached the limit
	if #self.spawnAreas == 0 then
		print("[WildPetManager] No spawn areas found")
		return
	end

	if self:CountWildPets() >= self.MAX_WILD_PETS then
		print(("[WildPetManager] Max wild pets reached (%d)"):format(self.MAX_WILD_PETS))
		return
	end

	-- Select a spawn area (preferred first, random fallback).
	local spawnArea = preferredSpawnArea
	if not spawnArea then
		spawnArea = self.spawnAreas[math.random(1, #self.spawnAreas)]
	end
	if not spawnArea or not spawnArea:IsA("BasePart") then return end
	local maxPerArea = tonumber(spawnArea:GetAttribute("MaxWildPets")) or self.MAX_WILD_PETS_PER_AREA
	if self:CountWildPetsInSpawnArea(spawnArea) >= maxPerArea then
		return
	end

	-- Get a random pet model
	if not self.WILD_PET_MODELS then
		print("[WildPetManager] No WildPetModels/PetModels folder found in ServerStorage")
		return
	end

	local templates = self:GetTemplatesForSpawnArea(spawnArea)
	if #templates == 0 then
		-- Refresh once in case templates were added after initialization.
		self:RefreshPetTemplates()
		templates = self:GetTemplatesForSpawnArea(spawnArea)
	end

	if #templates == 0 then
		local zoneId = self:GetZoneIdForSpawnArea(spawnArea)
		print(("[WildPetManager] No pet templates available for spawn area %s (zone=%s)"):format(
			spawnArea:GetFullName(),
			tostring(zoneId)
			))
		return
	end

	local selectedModel = self:GetWeightedRandomTemplateFromList(templates)
	if not selectedModel then
		return
	end
	local pet = selectedModel:Clone()

	local randomPos = self:FindSafeSpawnPosition(spawnArea, pet)
	if not randomPos then
		pet:Destroy()
		return
	end


	-- Position the pet
	pet:SetPrimaryPartCFrame(CFrame.new(randomPos))
	pet.Parent = workspace
	local petUid = ensurePetUid(pet)
	local displayId = string.sub(tostring(petUid or math.random(10000, 99999)), 1, 8)
	pet.Name = ("%s_%s"):format(selectedModel.Name, displayId)
	pet:SetAttribute("TemplateName", selectedModel.Name)
	if pet.PrimaryPart then
		pet:SetPrimaryPartCFrame(CFrame.new(randomPos))
	else
		pet:PivotTo(CFrame.new(randomPos))
	end

	-- Get power and rarity multiplier from the template
	local power = selectedModel:GetAttribute("Power") or 1
	local rarityMult = selectedModel:GetAttribute("RarityMultiplier") or 1

	-- Store as attributes on the pet (server‑side only)
	pet:SetAttribute("Power", power)
	pet:SetAttribute("RarityMultiplier", rarityMult)

	-- Initialize as wild pet
	self.petState[pet] = {
		location = "wild",
		wild = true,
		ownerUserId = nil,
		xp = 0,
		level = 1,
		scale = 1.0,
		dirtiness = math.random(30, 80),
		wetness = 0,
		dried = true,
		hunger = 100,
		happiness = 100,
		power = power,
		rarityMultiplier = rarityMult,
		petUid = petUid
	}
	
	pet:SetAttribute("WildPet", true)
	self.wildPets[pet] = spawnArea

	-- Set up pet rig and animation
	self.PetRigManager:EnsurePetRig(pet)
	self.PetAnimationManager:SetupAnimatorForPet(pet)

	-- Start wandering around the spawn area
	self.PetMovement.StartWandering(pet, spawnArea.Position, self.WANDER_RADIUS, nil, spawnArea)

	-- Add pickup prompt
	self:AddWildPetPickupPrompt(pet)

	print(("[WildPetManager] Spawned wild pet %s at %s"):format(pet.Name, spawnArea:GetFullName()))
	return pet
end

function WildPetManager:AddWildPetPickupPrompt(pet)
	if not pet or not pet:IsA("Model") then return end

	-- Create helper part for the prompt
	local helper = Instance.new("Part")
	helper.Name = "WildPetPickupPart"
	helper.Size = Vector3.new(1, 1, 1)
	helper.Anchored = false
	helper.Transparency = 1
	helper.CanCollide = false
	helper.Parent = pet

	-- Position above pet
	local pp = pet.PrimaryPart
	if pp then
		helper.CFrame = pp.CFrame * CFrame.new(0, pp.Size.Y/2 + 1, 0)
		local w = Instance.new("WeldConstraint")
		w.Part0 = helper
		w.Part1 = pp
		w.Parent = helper
	end

	-- Create prompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WildPetPrompt"
	prompt.ActionText = "Take Wild Pet"
	prompt.ObjectText = "Wild Pet"
	prompt.MaxActivationDistance = 6
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = helper

	local conn = prompt.Triggered:Connect(function(player)
		self:_pickupWildPetForPlayer(pet, player, helper)
	end)

	self.wildPetPickupConns[pet] = conn
end


function WildPetManager:PlacePetOnGround(pet, position)
	-- Raycast to find ground
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {pet}

	local rayOrigin = position + Vector3.new(0, 10, 0)
	local rayDirection = Vector3.new(0, -20, 0)

	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if result and result.Instance then
		local groundY = result.Position.Y
		pet:SetPrimaryPartCFrame(CFrame.new(position.X, groundY + 2, position.Z))
	else
		-- Fallback: place at original position but ensure it's above ground
		pet:SetPrimaryPartCFrame(CFrame.new(position + Vector3.new(0, 3, 0)))
	end
end

function WildPetManager:ConnectAdoptionMat(adoptionMat, tycoonModel)
	if not adoptionMat or not adoptionMat:IsA("BasePart") then return end

	local prompt = adoptionMat:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "AdoptionPrompt"
		prompt.ActionText = "Adopt Pet"
		prompt.ObjectText = "Adoption Mat"
		prompt.MaxActivationDistance = 8
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = adoptionMat
	end

	local conn = prompt.Triggered:Connect(function(player)
		-- Check if player is carrying a wild pet
		local pet = nil
		for pModel, state in pairs(self.petState) do
			if state.carrierUserId == player.UserId and state.wild and state.location == "player_wild" then
				pet = pModel
				break
			end
		end

		if not pet then
			-- Maybe the player is carrying through the regular system
			pet = self.carryingPetByUserId[player.UserId]
			if not pet or not self.petState[pet] or not self.petState[pet].wild then
				return
			end
		end

		-- Verify this is the player's tycoon
		local ownerMatch = false
		if tycoonModel then
			local ownerAttr = tycoonModel:GetAttribute("OwnerId") or tycoonModel:GetAttribute("Owner") or tycoonModel:GetAttribute("OwnerUserId")
			if ownerAttr and tostring(ownerAttr) == tostring(player.UserId) then
				ownerMatch = true
			else
				local candidateNames = {"OwnerId", "Owner", "OwnerUserId"}
				for _, nm in ipairs(candidateNames) do
					local child = tycoonModel:FindFirstChild(nm)
					if child and child.Value and tostring(child.Value) == tostring(player.UserId) then
						ownerMatch = true
						break
					end
				end
			end
		end

		if not ownerMatch then
			print("[WildPetManager] Adoption mat not in player's tycoon")
			return
		end

		local adopted = self:AutoAdoptCarriedWildPet(player, { adoptionPosition = adoptionMat.Position })
		if adopted then
			print(("[WildPetManager] Pet %s adopted by %s!"):format(pet.Name, player.Name))
		end
	end)

	return conn
end

function WildPetManager:AddOwnedPetPickupPrompt(pet, ownerUserId)
	if not pet or not pet.Parent then return end
	local existingHelper = pet:FindFirstChild("PetPickupPart")
	if existingHelper then
		pcall(function() existingHelper:Destroy() end)
	end
	if self.ownedPetPickupConns[pet] then
		pcall(function() self.ownedPetPickupConns[pet]:Disconnect() end)
		self.ownedPetPickupConns[pet] = nil
	end

	-- Create helper part and prompt
	local helper = Instance.new("Part")
	helper.Name = "PetPickupPart"
	helper.Size = Vector3.new(1, 1, 1)
	helper.Anchored = false
	helper.Transparency = 1
	helper.CanCollide = false
	helper.Parent = pet

	local pp = pet.PrimaryPart
	if pp then
		helper.CFrame = pp.CFrame * CFrame.new(0, pp.Size.Y/2 + 0.5, 0)
		local w = Instance.new("WeldConstraint")
		w.Part0 = helper
		w.Part1 = pp
		w.Parent = helper
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PetPrompt"
	prompt.ActionText = "Pick Up Pet"
	prompt.ObjectText = "Pet"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 6
	prompt.HoldDuration = 0
	prompt.Parent = helper

	local conn = prompt.Triggered:Connect(function(requestingPlayer)
		if tostring(ownerUserId) ~= tostring(requestingPlayer.UserId) then return end

		if requestingPlayer and requestingPlayer.Character and requestingPlayer.Character.PrimaryPart and not self.carryingPetByUserId[requestingPlayer.UserId] then
			local ok, err = pcall(function() 
				self.PetAttachmentManager:AttachPetToPlayer(pet, requestingPlayer, { resetFlags = false }) 
			end)
			if ok then
				self.petState[pet].location = "player"
				pcall(function() helper:Destroy() end)
				-- Disconnect and remove from storage
				if self.ownedPetPickupConns[pet] then
					self.ownedPetPickupConns[pet]:Disconnect()
					self.ownedPetPickupConns[pet] = nil
				end
				return
			else
				warn("[WildPetManager] Pet pickup reattach failed:", err)
			end
		end
	end)

	self.ownedPetPickupConns[pet] = conn
end

function WildPetManager:SpawnOwnedPetsForPlayer(player, petData)
	local tycoonModel, _ = self.TycoonUtils:FindTycoonByOwnerIdWithDesk(player.UserId)
	if not tycoonModel then
		print(("[WildPetManager] Could not find tycoon for player %s"):format(player.Name))
		return
	end

	local adoptionMat = self:GetAdoptionMatForTycoon(tycoonModel)

	if not adoptionMat then
		print(("[WildPetManager] Could not find adoption mat in tycoon for player %s"):format(player.Name))
		return
	end

	local matPos = adoptionMat.Position

	for _, petInfo in ipairs(petData) do
		local template = self:FindPetTemplateByName(petInfo.modelName)
		if template then
			local pet = template:Clone()
			pet.Name = petInfo.modelName
			pet:SetAttribute("TemplateName", petInfo.modelName)
			if type(petInfo.petUid) == "string" and petInfo.petUid ~= "" then
				pet:SetAttribute("PetUID", petInfo.petUid)
			end
			local resolvedPetUid = ensurePetUid(pet)
			pet.Parent = workspace

			-- restore state (sanitize persisted values; never trust raw datastore values blindly)
			self.petState[pet] = petInfo
			self.petState[pet].ownerUserId = player.UserId
			self.petState[pet].wild = false
			self.petState[pet].petUid = resolvedPetUid
			pet:SetAttribute("WildPet", false)

			local savedXP = math.max(0, math.floor(tonumber(petInfo.xp) or 0))
			local resolvedLevel = self.PetStateManager:GetLevelFromXP(savedXP)
			local detectedBaseScale = tonumber(petInfo.baseScale)
			if not detectedBaseScale then
				-- Backward compatibility for older saves: level-1 scale usually equals base scale.
				if resolvedLevel <= 1 and tonumber(petInfo.scale) then
					detectedBaseScale = tonumber(petInfo.scale)
				end
			end
			if not detectedBaseScale then
				pcall(function()
					detectedBaseScale = tonumber(pet:GetScale())
				end)
			end
			detectedBaseScale = math.clamp(tonumber(detectedBaseScale) or 1.0, 0.5, 2.25)
			self.petState[pet].xp = savedXP
			self.petState[pet].level = resolvedLevel
			self.petState[pet].baseScale = detectedBaseScale
			self.petState[pet].happiness = math.clamp(tonumber(self.petState[pet].happiness) or 100, 0, 100)

			if not self.petState[pet].power then
				self.petState[pet].power = petInfo.power or 1
			end
			if not self.petState[pet].rarityMultiplier then
				self.petState[pet].rarityMultiplier = petInfo.rarityMultiplier or 1
			end

			pet:SetAttribute("Power", self.petState[pet].power)
			pet:SetAttribute("RarityMultiplier", self.petState[pet].rarityMultiplier)

			self.PetRigManager:EnsurePetRig(pet)
			self.PetAnimationManager:SetupAnimatorForPet(pet)
			-- Recompute from level every load so legacy/corrupt saved scale values
			-- cannot permanently inflate pet size across rejoins.
			local targetScale = self.PetStateManager:CalculateScaleForLevel(resolvedLevel, detectedBaseScale)
			self.PetStateManager:SetPetScale(pet, targetScale)

			local restoredToStand = false
			if petInfo.location == "petstand" and petInfo.standId then
				local ok = self.PetStandManager:RestorePetToStand(
					pet,
					player,
					petInfo.standId,
					petInfo.standStoredMoney
				)
				if ok then
					restoredToStand = true
				end
			end

			if not restoredToStand then
				self:PlacePetOnGround(pet, matPos)
				self.petState[pet].location = "free"
				local wanderZone = self:GetOwnerWanderZonePart(player.UserId)
				self.PetMovement.StartWandering(pet, matPos, 20, player.UserId, wanderZone)
				self:AddOwnedPetPickupPrompt(pet, player.UserId)
			end	

			print(("[WildPetManager] Spawned owned pet %s for %s"):format(pet.Name, player.Name))
		else
			warn(("[WildPetManager] Pet model %s not found"):format(petInfo.modelName))
		end
	end
	self:UpdateOwnedPetRegistryForPlayer(player)
end

function WildPetManager:CreateOwnedPetPickupPrompt(pet, position)
	-- Detach pet from player and place it in the tycoon
	self.PetAttachmentManager:DetachPetFromPlayer(pet)

	-- Place pet on ground
	self:PlacePetOnGround(pet, position)
	pet.Parent = workspace

	-- Ensure pet has proper rig and animation
	self.PetRigManager:EnsurePetRig(pet)
	self.PetAnimationManager:SetupAnimatorForPet(pet)

	-- Create pickup prompt (like regular pet pickup)
	local helper = Instance.new("Part")
	helper.Name = "PetPickupPart"
	helper.Size = Vector3.new(1, 1, 1)
	helper.Anchored = false
	helper.Transparency = 1
	helper.CanCollide = false
	helper.Parent = pet

	local pp = pet.PrimaryPart
	if pp then
		helper.CFrame = pp.CFrame * CFrame.new(0, pp.Size.Y/2 + 0.5, 0)
		local w = Instance.new("WeldConstraint")
		w.Part0 = helper
		w.Part1 = pp
		w.Parent = helper
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PetPrompt"
	prompt.ActionText = "Pick Up Pet"
	prompt.ObjectText = "Pet"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 6
	prompt.HoldDuration = 0
	prompt.Parent = helper

	local conn = prompt.Triggered:Connect(function(requestingPlayer)
		local st = self.petState[pet]
		if not st then return end
		if tostring(st.ownerUserId) ~= tostring(requestingPlayer.UserId) then return end

		if requestingPlayer and requestingPlayer.Character and requestingPlayer.Character.PrimaryPart and not self.carryingPetByUserId[requestingPlayer.UserId] then
			local ok, err = pcall(function() 
				self.PetAttachmentManager:AttachPetToPlayer(pet, requestingPlayer, { resetFlags = false }) 
			end)
			if ok then
				self.petState[pet].location = "player"
				pcall(function() helper:Destroy() end)
				return
			else
				warn("[WildPetManager] Pet pickup reattach failed:", err)
			end
		end
	end)

	-- Start wandering in the tycoon area
	local ownerUserId = self.petState[pet] and self.petState[pet].ownerUserId
	local wanderZone = self:GetOwnerWanderZonePart(ownerUserId)
	self.PetMovement.StartWandering(pet, position, 20, ownerUserId, wanderZone)
	self.ownedPetPickupConns[pet] = conn
end

function WildPetManager:StartSpawning()
	task.spawn(function()
		-- Initial spawn per zone/spawn area
		for _, spawnArea in ipairs(self.spawnAreas) do
			local perAreaTarget = tonumber(spawnArea:GetAttribute("InitialWildPets")) or self.INITIAL_SPAWN_PER_ZONE
			for _ = 1, perAreaTarget do
				if self:CountWildPets() >= self.MAX_WILD_PETS then
					break
				end
				self:SpawnWildPet(spawnArea)
				task.wait(0.2 + (math.random() * 0.4))
			end
		end			

		-- Independent periodic spawning per area with random interval
		for _, spawnArea in ipairs(self.spawnAreas) do
			task.spawn(function()
				while spawnArea and spawnArea.Parent do
					task.wait(self:GetRandomSpawnInterval())
					self:CleanupDestroyedWildPets()
					if self:CountWildPets() < self.MAX_WILD_PETS then
						self:SpawnWildPet(spawnArea)
					end
				end
			end)
		end
	end)
end

function WildPetManager:ScanAndConnectAdoptionMats()
	-- Connect all found adoption mats
	for adoptionMat, tycoonModel in pairs(self.adoptionMats) do
		self:ConnectAdoptionMat(adoptionMat, tycoonModel)
	end

	-- Also scan periodically for new ones
	task.spawn(function()
		while true do
			task.wait(10)
			self:FindAdoptionMats()
			for adoptionMat, tycoonModel in pairs(self.adoptionMats) do
				-- Check if already connected
				local prompt = adoptionMat:FindFirstChildWhichIsA("ProximityPrompt")
				if not prompt or prompt.Name ~= "AdoptionPrompt" then
					self:ConnectAdoptionMat(adoptionMat, tycoonModel)
				end
			end
		end
	end)
end

return WildPetManager
