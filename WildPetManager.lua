---WildPetManagerModule
local WildPetManager = {}
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

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
	self.PromptManager = require(script.Parent.PromptManager)
	self.TycoonUtils = require(script.Parent.TycoonUtils)
	self.TycoonUtils:Initialize(config)  -- Initialize TycoonUtils with the config
	self.SaveManager = saveManager
	self.PetStandManager = require(script.Parent.PetStandManager)
	-- Settings
	self.WILD_PET_SPAWN_AREA_TAG = "WildPetSpawnArea"
	self.MAX_WILD_PETS = 10
	self.SPAWN_INTERVAL = 30 -- seconds
	self.WANDER_RADIUS = 50
	self.WILD_PET_MODELS = ServerStorage:FindFirstChild("WildPetModels") or ServerStorage:FindFirstChild("PetModels")

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
	self:StartSpawning()
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

function WildPetManager:RefreshPetTemplates()
	self.petTemplates = {}

	if not self.WILD_PET_MODELS then
		warn("[WildPetManager] WildPetModels/PetModels folder was not found in ServerStorage")
		return
	end

	for _, candidate in ipairs(self.WILD_PET_MODELS:GetDescendants()) do
		if candidate:IsA("Model") then
			-- Keep only top-level templates (directly under a folder/service, not nested inside another model)
			if not candidate.Parent or not candidate.Parent:IsA("Model") then
				local hasPhysicalPart = candidate.PrimaryPart ~= nil or candidate:FindFirstChildWhichIsA("BasePart", true) ~= nil
				if hasPhysicalPart then
					table.insert(self.petTemplates, candidate)
				end
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

function WildPetManager:SpawnWildPet()
	-- Check if we have spawn areas and haven't reached the limit
	if #self.spawnAreas == 0 then
		print("[WildPetManager] No spawn areas found")
		return
	end

	if #self.wildPets >= self.MAX_WILD_PETS then
		print(("[WildPetManager] Max wild pets reached (%d)"):format(self.MAX_WILD_PETS))
		return
	end

	-- Select a random spawn area
	local spawnArea = self.spawnAreas[math.random(1, #self.spawnAreas)]
	if not spawnArea or not spawnArea:IsA("BasePart") then return end

	-- Get a random pet model
	if not self.WILD_PET_MODELS then
		print("[WildPetManager] No WildPetModels/PetModels folder found in ServerStorage")
		return
	end

	local petModels = {}
	for _, child in ipairs(self.WILD_PET_MODELS:GetChildren()) do
		if child:IsA("Model") then
			table.insert(petModels, child)
		end
	end
	
	if #self.petTemplates == 0 then
		self:RefreshPetTemplates()
	end

	if #self.petTemplates == 0 then
		print("[WildPetManager] No pet models found in WildPetModels/PetModels folder")
		return
	end

	local selectedModel = self:GetWeightedRandomTemplate()
	if not selectedModel then
		return
	end
	local pet = selectedModel:Clone()

	-- Generate a random position within the spawn area
	local min = spawnArea.Position - spawnArea.Size / 2
	local max = spawnArea.Position + spawnArea.Size / 2

	local randomPos = Vector3.new(
		math.random(min.X, max.X),
		spawnArea.Position.Y + spawnArea.Size.Y / 2 + 2, -- Spawn on top of the area
		math.random(min.Z, max.Z)
	)
	

	-- Position the pet
	pet:SetPrimaryPartCFrame(CFrame.new(randomPos))
	pet.Parent = workspace
	pet.Name = "WildPet_" .. tostring(math.random(10000, 99999))
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
		wetness = math.random(20, 60),
		hunger = 100,
		power = power,
		rarityMultiplier = rarityMult
	}

	self.wildPets[pet] = spawnArea

	-- Set up pet rig and animation
	self.PetRigManager:EnsurePetRig(pet)
	self.PetAnimationManager:SetupAnimatorForPet(pet)

	-- Start wandering around the spawn area
	self.PetMovement.StartWandering(pet, spawnArea.Position, self.WANDER_RADIUS)

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
		-- Check if player can carry (not already carrying a pet)
		if self.carryingPetByUserId[player.UserId] then
			return
		end

		-- Check if pet is still wild and available
		local state = self.petState[pet]
		if not state or not state.wild then
			return
		end

		-- Attach wild pet to player (without setting owner yet)
		local ok, err = self.PetAttachmentManager:AttachWildPetToPlayer(pet, player)
		if ok then
			-- Update state
			self.petState[pet].location = "player_wild"
			self.petState[pet].carrierUserId = player.UserId

			-- Stop wandering
			self.PetMovement.StopWandering(pet)

			-- Remove from wild pets tracker
			self.wildPets[pet] = nil

			-- Remove pickup prompt
			if self.wildPetPickupConns[pet] then
				self.wildPetPickupConns[pet]:Disconnect()
				self.wildPetPickupConns[pet] = nil
			end
			pcall(function() helper:Destroy() end)

			print(("[WildPetManager] Player %s picked up wild pet %s"):format(player.Name, pet.Name))
		else
			warn("[WildPetManager] Failed to attach wild pet:", err)
		end
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

		-- ADOPT THE PET!
		print(("[WildPetManager] Player %s adopting pet %s"):format(player.Name, pet.Name))

		-- Set pet as owned by player
		self.petState[pet].ownerUserId = player.UserId
		self.petState[pet].wild = false
		self.petState[pet].location = "player"

		-- Update carrying tables
		self.carryingPetByUserId[player.UserId] = pet
		if self.petState[pet].carrierUserId then
			self.petState[pet].carrierUserId = nil
		end

		-- Send adoption message to player
		game.ReplicatedStorage:FindFirstChild("PetAdoptionEvent"):FireClient(player, "PetAdopted", pet)
		if self.SaveManager then
			self.SaveManager:ScheduleSave(player)
		end

		-- Output server message
		print(("[WildPetManager] Pet %s adopted by %s!"):format(pet.Name, player.Name))

		-- Optional: Give adoption bonus XP
		self.PetStateManager:AddXP(pet, 50) -- Adoption bonus

		-- Create new pickup prompt for the now-owned pet
		self:CreateOwnedPetPickupPrompt(pet, adoptionMat.Position)
	end)

	return conn
end

function WildPetManager:AddOwnedPetPickupPrompt(pet, ownerUserId)
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

	local adoptionMat = nil
	for mat, tModel in pairs(self.adoptionMats) do
		if tModel == tycoonModel then
			adoptionMat = mat
			break
		end
	end

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
			pet.Parent = workspace

			-- restore state
			self.petState[pet] = petInfo
			self.petState[pet].ownerUserId = player.UserId
			self.petState[pet].wild = false

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
				self.PetMovement.StartWandering(pet, matPos, 20)
				self:AddOwnedPetPickupPrompt(pet, player.UserId)
			end

			print(("[WildPetManager] Spawned owned pet %s for %s"):format(pet.Name, player.Name))
		else
			warn(("[WildPetManager] Pet model %s not found"):format(petInfo.modelName))
		end
	end
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
	self.PetMovement.StartWandering(pet, position, 20)
	self.ownedPetPickupConns[pet] = conn
end

function WildPetManager:StartSpawning()
	task.spawn(function()
		-- Initial spawn
		for i = 1, math.min(3, self.MAX_WILD_PETS) do
			task.wait(2)
			self:SpawnWildPet()
		end

		-- Periodic spawning
		while true do
			task.wait(self.SPAWN_INTERVAL)

			-- Remove any destroyed wild pets
			for pet, _ in pairs(self.wildPets) do
				if not pet or not pet.Parent then
					self.wildPets[pet] = nil
					if self.wildPetPickupConns[pet] then
						self.wildPetPickupConns[pet]:Disconnect()
						self.wildPetPickupConns[pet] = nil
					end
				end
			end

			-- Spawn new ones if under limit
			local currentCount = 0
			for _ in pairs(self.wildPets) do currentCount += 1 end

			if currentCount < self.MAX_WILD_PETS then
				local toSpawn = math.min(2, self.MAX_WILD_PETS - currentCount)
				for i = 1, toSpawn do
					task.wait(1)
					self:SpawnWildPet()
				end
			end
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
