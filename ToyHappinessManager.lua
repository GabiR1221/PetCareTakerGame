local ToyHappinessManager = {}

local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local DEFAULTS = {
	ToyName = "Ball",
	ToyType = "Ball",
	Duration = 5,
	TickSeconds = 0.5,
	HappinessGainPerTick = 2,
	MaxPetsPerToy = 3,
	JumpDistance = 7,
	JumpHeight = 2.8,
	JumpTime = 0.4,
	WanderRadius = 20,
	PetBounceRadius = 4,
	PetBounceCooldown = 0.8,
	JumpCooldown = 1.25,
	DecayIntervalMin = 5,
	DecayIntervalMax = 15,
	DecayAmountMin = 3,
	DecayAmountMax = 7,
}
local DEFAULT_MAX_HAPPINESS = 100

local function getToyPrimaryPart(toy)
	if not toy then return nil end
	if toy:IsA("BasePart") then
		return toy
	end
	if toy:IsA("Model") then
		if toy.PrimaryPart then return toy.PrimaryPart end
		local firstPart = toy:FindFirstChildWhichIsA("BasePart", true)
		if firstPart then
			pcall(function() toy.PrimaryPart = firstPart end)
		end
		return toy.PrimaryPart
	end
	return nil
end

local function getToyReferenceCFrame(toyInstance, toyPrimary)
	if toyInstance:IsA("Model") then
		return toyInstance:GetPivot()
	end
	return toyPrimary.CFrame
end

local function ensurePrompt(toyPrimary)
	if not toyPrimary then return nil end
	local prompt = toyPrimary:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ToyPrompt"
		prompt.ActionText = "Play"
		prompt.ObjectText = "Toy"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = toyPrimary
	end
	return prompt
end

local function setToyVisualEnabled(toyInstance, enabled)
	if not toyInstance then return end
	if toyInstance:IsA("BasePart") then
		toyInstance.Transparency = enabled and 0 or 1
		toyInstance.CanCollide = false
		toyInstance.CanTouch = enabled
		toyInstance.CanQuery = enabled
		return
	end

	for _, desc in ipairs(toyInstance:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = enabled and 0 or 1
			desc.CanCollide = false
			desc.CanTouch = enabled
			desc.CanQuery = enabled
		end
	end
end

function ToyHappinessManager:Initialize(stateTable, carryingTable, playersService, petMovement)
	self.petState = stateTable or {}
	self.carryingPetByUserId = carryingTable or {}
	self.Players = playersService
	self.PetMovement = petMovement

	self.TycoonUtils = require(script.Parent.TycoonUtils)
	self.PetStateManager = require(script.Parent.PetStateManager)
	self.PetSaveManager = nil

	self.connectedPrompts = {}
	self.activeSessionsByToy = {}
	self.dynamicToysByTemplate = {}
	self.lastTriggeredAt = {}
	self.lastJumpAtByToy = {}
	self.happinessDecayStarted = false
	self.autoToyPlayStarted = false

	self:_startHappinessDecayLoop()
	self:_startAutoToyPlayLoop()
	return self
end


function ToyHappinessManager:SetSaveManager(saveManager)
	self.PetSaveManager = saveManager
end

function ToyHappinessManager:_readNumberAttribute(inst, name, defaultValue)
	if not inst then return defaultValue end
	local attr = inst:GetAttribute(name)
	if attr ~= nil then
		local numeric = tonumber(attr)
		if numeric ~= nil then
			return numeric
		end
	end
	return defaultValue
end

function ToyHappinessManager:_readPositiveIntAttribute(inst, name, defaultValue)
	local raw = tonumber(self:_readNumberAttribute(inst, name, defaultValue))
	if raw == nil then
		raw = tonumber(defaultValue) or 1
	end
	return math.max(1, math.floor(raw))
end

function ToyHappinessManager:_getToyStableId(toyPrimary)
	if not toyPrimary then return nil end
	local existing = toyPrimary:GetAttribute("ToyStableId")
	if existing ~= nil and tostring(existing) ~= "" then
		return tostring(existing)
	end
	local newId = HttpService:GenerateGUID(false)
	toyPrimary:SetAttribute("ToyStableId", newId)
	return newId
end

function ToyHappinessManager:_canTriggerToyJump(toyPrimary, toyInstance)
	if not toyPrimary then return false end
	local cooldown = self:_readNumberAttribute(toyInstance, "JumpCooldown", DEFAULTS.JumpCooldown)
	local now = os.clock()
	local last = self.lastJumpAtByToy[toyPrimary]
	if last and (now - last) < cooldown then
		return false
	end
	self.lastJumpAtByToy[toyPrimary] = now
	return true
end

function ToyHappinessManager:_isPlayerOwnerOfTycoon(player, tycoonModel)
	if not player or not tycoonModel then return false end

	local ownerAttr = tycoonModel:GetAttribute("OwnerId") or tycoonModel:GetAttribute("Owner") or tycoonModel:GetAttribute("OwnerUserId")
	if ownerAttr and tostring(ownerAttr) == tostring(player.UserId) then
		return true
	end

	for _, nm in ipairs({ "OwnerId", "Owner", "OwnerUserId" }) do
		local child = tycoonModel:FindFirstChild(nm)
		if child and child.Value and tostring(child.Value) == tostring(player.UserId) then
			return true
		end
	end

	return false
end

function ToyHappinessManager:_getOwnerPlayerFromTycoon(tycoonModel)
	if not tycoonModel then return nil end
	local ownerAttr = tycoonModel:GetAttribute("OwnerId") or tycoonModel:GetAttribute("Owner") or tycoonModel:GetAttribute("OwnerUserId")
	if ownerAttr then
		local ownerId = tonumber(ownerAttr)
		if ownerId then
			return self.Players:GetPlayerByUserId(ownerId)
		end
	end

	for _, nm in ipairs({ "OwnerId", "Owner", "OwnerUserId" }) do
		local child = tycoonModel:FindFirstChild(nm)
		if child then
			if child:IsA("ObjectValue") and child.Value and child.Value:IsA("Player") then
				return child.Value
			end
			local raw = child.Value
			local ownerId = tonumber(raw)
			if ownerId then
				local player = self.Players:GetPlayerByUserId(ownerId)
				if player then return player end
			end
		end
	end

	return nil
end

function ToyHappinessManager:_isToyTemplateEquippedForOwner(template, ownerPlayer)
	if not template or not ownerPlayer then return false end
	local equippedName = tostring(ownerPlayer:GetAttribute("EquippedToyName") or "")
	if equippedName == "" then return false end
	if string.lower(template.Name) == string.lower(equippedName) then
		return true
	end

	local toyType = template:GetAttribute("ToyType")
	if toyType ~= nil and tostring(toyType) ~= "" and string.lower(tostring(toyType)) == string.lower(equippedName) then
		return true
	end

	return false
end

function ToyHappinessManager:_setToyEnabled(toyInstance, enabled)
	local toyPrimary = getToyPrimaryPart(toyInstance)
	if toyPrimary then
		local prompt = ensurePrompt(toyPrimary)
		if prompt then
			prompt.Enabled = enabled
		end
		if not enabled then
			self:_cleanupFinishedSession(toyPrimary)
		end
	end
	setToyVisualEnabled(toyInstance, enabled)
end

function ToyHappinessManager:_isToyTemplateCandidate(inst)
	if not inst then return false end
	if inst:GetAttribute("IsDynamicToy") == true then
		return false
	end
	if inst:GetAttribute("IsPetToy") == true then
		return true
	end

	local toyType = inst:GetAttribute("ToyType")
	if toyType ~= nil and tostring(toyType) ~= "" then
		return true
	end

	return string.lower(inst.Name) == string.lower(DEFAULTS.ToyName)
end

function ToyHappinessManager:_resolveGroundedPosition(basePos, toyInstance, toyPrimary, zonePart)
	local target = self:_clampPointToZoneXZ(zonePart, basePos)
	local halfHeight = self:_getToyHalfHeight(toyInstance, toyPrimary)

	local rayOrigin = target + Vector3.new(0, 24, 0)
	local rayDirection = Vector3.new(0, -120, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local blacklist = { toyInstance }
	if zonePart and zonePart:IsA("BasePart") then
		table.insert(blacklist, zonePart)
	end
	for petModel, _ in pairs(self.petState) do
		if petModel and petModel.Parent then
			table.insert(blacklist, petModel)
		end
	end
	params.FilterDescendantsInstances = blacklist
	params.IgnoreWater = true

	local hit = workspace:Raycast(rayOrigin, rayDirection, params)
	if hit then
		return Vector3.new(target.X, hit.Position.Y + halfHeight, target.Z)
	end

	return Vector3.new(target.X, basePos.Y, target.Z)
end

function ToyHappinessManager:_collectToyTemplatesFromEssentials(essentials)
	local templates = {}
	if not essentials then return templates end

	for _, child in ipairs(essentials:GetChildren()) do
		if (child:IsA("BasePart") or child:IsA("Model")) and self:_isToyTemplateCandidate(child) then
			table.insert(templates, child)
		end
	end

	return templates
end

function ToyHappinessManager:_resolveToyType(template)
	if not template then return DEFAULTS.ToyType end
	local attr = template:GetAttribute("ToyType")
	if attr ~= nil and tostring(attr) ~= "" then
		return tostring(attr)
	end
	return template.Name
end

function ToyHappinessManager:_getOwnedPlayablePets(player)
	local ownedPets = {}
	if not player then return ownedPets end

	for pet, st in pairs(self.petState) do
		if pet and pet.Parent and st and tostring(st.ownerUserId) == tostring(player.UserId) and st.wild ~= true then
			if self.carryingPetByUserId[player.UserId] ~= pet and st.location ~= "petstand" then
				table.insert(ownedPets, pet)
			end
		end
	end

	return ownedPets
end

function ToyHappinessManager:_selectNearestPets(player, toyPrimary, maxPets)
	local ownedPets = self:_getOwnedPlayablePets(player)
	table.sort(ownedPets, function(a, b)
		local ap = a.PrimaryPart and a.PrimaryPart.Position or Vector3.zero
		local bp = b.PrimaryPart and b.PrimaryPart.Position or Vector3.zero
		return (ap - toyPrimary.Position).Magnitude < (bp - toyPrimary.Position).Magnitude
	end)

	local selected = {}
	for i = 1, math.min(#ownedPets, maxPets) do
		table.insert(selected, ownedPets[i])
	end
	return selected
end

function ToyHappinessManager:_resolveWanderZoneForOwner(ownerUserId)
	if not ownerUserId then return nil end
	local tycoonModel = self.TycoonUtils:FindTycoonByOwnerId(ownerUserId)
	if not tycoonModel then return nil end

	local zonePartName = tostring(tycoonModel:GetAttribute("PetWanderZonePartName") or "PetWanderZone")
	local zonePart = self.TycoonUtils:FindPartByNameInModel(tycoonModel, zonePartName)
	if zonePart and zonePart:IsA("BasePart") then
		return zonePart
	end

	local essentials = self.TycoonUtils:FindEssentialsInModel(tycoonModel)
	if essentials then
		local direct = essentials:FindFirstChild(zonePartName)
		if direct and direct:IsA("BasePart") then
			return direct
		end
	end

	return nil
end

function ToyHappinessManager:_registerMovedPet(session, pet)
	if not session or not pet then return end
	session.movedPetSet = session.movedPetSet or {}
	session.movedPets = session.movedPets or {}
	if session.movedPetSet[pet] then return end
	session.movedPetSet[pet] = true
	table.insert(session.movedPets, pet)
end

function ToyHappinessManager:_cleanupFinishedSession(toyPrimary)
	local session = self.activeSessionsByToy[toyPrimary]
	if not session then return end

	for _, pet in ipairs(session.movedPets or {}) do
		if pet and pet.Parent then
			local st = self.petState[pet] or {}
			st.toyAssignedId = nil
			st.toyAssignedType = nil
			self.PetMovement.StopWandering(pet)
			task.defer(function()
				if pet and pet.Parent then
					local ownerId = st.ownerUserId
					self.PetMovement.StartWandering(
						pet,
						(pet.PrimaryPart and pet.PrimaryPart.Position) or nil,
						DEFAULTS.WanderRadius,
						ownerId,
						session.wanderZone
					)
					self.PetStateManager:SendStateToOwner(pet)
				end
			end)
		end
	end

	self.activeSessionsByToy[toyPrimary] = nil
	if self.PetSaveManager and session.player then
		self.PetSaveManager:ScheduleSave(session.player)
	end
end

function ToyHappinessManager:_keepSessionPetsNearToy(session)
	if not session or not session.toyPrimary then return end
	local pets = session.rewardPets or {}
	for index, pet in ipairs(pets) do
		if pet and pet.Parent and pet.PrimaryPart then
			local radius = 1.8 + ((index - 1) * 0.5)
			local angle = (index / math.max(#pets, 1)) * math.pi * 2
			local target = session.toyPrimary.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			target = self:_clampPointToZoneXZ(session.wanderZone, target)
			local humanoid = pet:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:MoveTo(target)
			end
		end
	end
end


function ToyHappinessManager:_clampPointToZoneXZ(zonePart, worldPoint)
	if not zonePart or not zonePart:IsA("BasePart") then
		return worldPoint
	end
	local localPoint = zonePart.CFrame:PointToObjectSpace(worldPoint)
	local halfX = zonePart.Size.X * 0.5
	local halfZ = zonePart.Size.Z * 0.5
	local clampedLocal = Vector3.new(
		math.clamp(localPoint.X, -halfX, halfX),
		localPoint.Y,
		math.clamp(localPoint.Z, -halfZ, halfZ)
	)
	return zonePart.CFrame:PointToWorldSpace(clampedLocal)
end

function ToyHappinessManager:_getToyHalfHeight(toyInstance, toyPrimary)
	if toyInstance and toyInstance:IsA("Model") then
		local ok, _, size = pcall(function()
			return toyInstance:GetBoundingBox()
		end)
		if ok and size then
			return size.Y * 0.5
		end
	end
	return (toyPrimary and toyPrimary.Size.Y * 0.5) or 0.5
end

function ToyHappinessManager:_solveLandingPosition(toyInstance, toyPrimary, zonePart)
	local startCFrame = getToyReferenceCFrame(toyInstance, toyPrimary)
	local jumpDistance = self:_readNumberAttribute(toyInstance, "JumpDistance", DEFAULTS.JumpDistance)
	local angle = math.random() * math.pi * 2
	local planar = Vector3.new(math.cos(angle), 0, math.sin(angle)) * jumpDistance
	local desired = startCFrame.Position + planar
	desired = self:_resolveGroundedPosition(desired, toyInstance, toyPrimary, zonePart)

	return startCFrame, desired
end

function ToyHappinessManager:_setToyCFrame(toyInstance, targetCFrame)
	if toyInstance:IsA("Model") then
		toyInstance:PivotTo(targetCFrame)
	else
		toyInstance.CFrame = targetCFrame
	end
end

function ToyHappinessManager:_animateToyJump(toyInstance, toyPrimary, zonePart)
	if not toyInstance or not toyPrimary then return end
	local startCFrame, landingPos = self:_solveLandingPosition(toyInstance, toyPrimary, zonePart)
	local jumpHeight = self:_readNumberAttribute(toyInstance, "JumpHeight", DEFAULTS.JumpHeight)
	local jumpTime = math.max(0.1, self:_readNumberAttribute(toyInstance, "JumpTime", DEFAULTS.JumpTime))
	local rx, ry, rz = startCFrame:ToOrientation()
	local rotationOnly = CFrame.fromOrientation(rx, ry, rz)
	local apexPos = ((startCFrame.Position + landingPos) * 0.5) + Vector3.new(0, jumpHeight, 0)

	local driveValue = Instance.new("CFrameValue")
	driveValue.Value = startCFrame
	local conn = driveValue:GetPropertyChangedSignal("Value"):Connect(function()
		if toyInstance and toyInstance.Parent then
			self:_setToyCFrame(toyInstance, driveValue.Value)
		end
	end)

	local upTween = TweenService:Create(driveValue, TweenInfo.new(jumpTime * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Value = CFrame.new(apexPos) * rotationOnly,
	})
	local downTween = TweenService:Create(driveValue, TweenInfo.new(jumpTime * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Value = CFrame.new(landingPos) * rotationOnly,
	})

	task.spawn(function()
		upTween:Play()
		upTween.Completed:Wait()
		downTween:Play()
		downTween.Completed:Wait()
		if toyInstance and toyInstance.Parent then
			self:_setToyCFrame(toyInstance, CFrame.new(landingPos) * rotationOnly)
		end
		conn:Disconnect()
		driveValue:Destroy()
	end)

	return landingPos
end

function ToyHappinessManager:_sendPetsToToy(session, player, toyPrimary, pets, forHappiness)
	if not session or not toyPrimary then return end
	for index, pet in ipairs(pets) do
		if pet and pet.Parent and pet.PrimaryPart then
			self.PetMovement.StopWandering(pet)
			self:_registerMovedPet(session, pet)
			local radius = 1.8 + ((index - 1) * 0.5)
			local angle = (index / math.max(#pets, 1)) * math.pi * 2
			local target = toyPrimary.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			target = self:_clampPointToZoneXZ(session.wanderZone, target)
			local humanoid = pet:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.AutoRotate = true
				humanoid:MoveTo(target)
			end

			local st = self.petState[pet] or {}
			if forHappiness then
				st.toyAssignedId = session.toyStableId
				st.toyAssignedType = tostring(toyPrimary:GetAttribute("ToyType") or DEFAULTS.ToyType)
			end
			self.petState[pet] = st
			self.PetStateManager:SendStateToOwner(pet)
		end
	end
end

function ToyHappinessManager:_isPetReservedForAnotherToy(pet, requestingToyId)
	local st = self.petState[pet]
	if not st then return false end
	local assigned = st.toyAssignedId
	if assigned == nil then return false end
	return tostring(assigned) ~= tostring(requestingToyId)
end


function ToyHappinessManager:_handlePetTriggeredBounce(session)
	if not session or not session.toyPrimary or not session.player then return end
	local now = os.clock()
	local cooldown = self:_readNumberAttribute(session.toy, "PetBounceCooldown", DEFAULTS.PetBounceCooldown)
	if session.lastPetBounceAt and (now - session.lastPetBounceAt) < cooldown then
		return
	end

	local triggerRadius = self:_readNumberAttribute(session.toy, "PetBounceRadius", DEFAULTS.PetBounceRadius)
	for _, pet in ipairs(session.rewardPets or {}) do
		if pet and pet.Parent and pet.PrimaryPart then
			if (pet.PrimaryPart.Position - session.toyPrimary.Position).Magnitude <= triggerRadius then
				if not self:_canTriggerToyJump(session.toyPrimary, session.toy) then
					return
				end
				session.lastPetBounceAt = now
				self:_animateToyJump(session.toy, session.toyPrimary, session.wanderZone)
				local maxPets = self:_readPositiveIntAttribute(session.toy, "MaxPetsPerToy", DEFAULTS.MaxPetsPerToy)
				local spectators = self:_selectNearestPets(session.player, session.toyPrimary, maxPets)
				self:_sendPetsToToy(session, session.player, session.toyPrimary, spectators, false)
				return
			end
		end
	end
end

function ToyHappinessManager:_runHappinessSession(player, toyInstance, toyPrimary)
	if not player or not toyInstance or not toyPrimary then return end

	local maxPets = self:_readPositiveIntAttribute(toyInstance, "MaxPetsPerToy", DEFAULTS.MaxPetsPerToy)
	local duration = math.max(0.25, self:_readNumberAttribute(toyInstance, "HappinessDuration", DEFAULTS.Duration))
	local tickSeconds = math.max(0.1, self:_readNumberAttribute(toyInstance, "HappinessTick", DEFAULTS.TickSeconds))
	local happinessGain = math.max(0, self:_readNumberAttribute(toyInstance, "HappinessGainPerTick", DEFAULTS.HappinessGainPerTick))
	local toyStableId = self:_getToyStableId(toyPrimary)

	local rewardPets = {}
	for _, pet in ipairs(self:_selectNearestPets(player, toyPrimary, maxPets * 3)) do
		if not self:_isPetReservedForAnotherToy(pet, toyStableId) then
			table.insert(rewardPets, pet)
			if #rewardPets >= maxPets then
				break
			end
		end
	end

	self:_cleanupFinishedSession(toyPrimary)
	local session = {
		player = player,
		toy = toyInstance,
		toyPrimary = toyPrimary,
		toyStableId = toyStableId,
		wanderZone = self:_resolveWanderZoneForOwner(player.UserId),
		rewardPets = rewardPets,
		movedPets = {},
		movedPetSet = {},
		lastPetBounceAt = 0,
	}
	self.activeSessionsByToy[toyPrimary] = session

	self:_animateToyJump(toyInstance, toyPrimary, session.wanderZone)
	self:_sendPetsToToy(session, player, toyPrimary, rewardPets, true)

	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			local live = self.activeSessionsByToy[toyPrimary]
			if live ~= session then
				return
			end

			for _, pet in ipairs(rewardPets) do
				if pet and pet.Parent then
					local st = self.petState[pet]
					if st and tostring(st.ownerUserId) == tostring(player.UserId) and st.wild ~= true and st.toyAssignedId == session.toyStableId then
						local happinessMax = (self.PetStateManager and self.PetStateManager.GetPetStatMax)
							and self.PetStateManager:GetPetStatMax(pet, "happiness", st)
							or DEFAULT_MAX_HAPPINESS
						st.happiness = math.clamp((tonumber(st.happiness) or happinessMax) + happinessGain, 0, happinessMax)
						self.PetStateManager:SendStateToOwner(pet)
					end
				end
			end

			self:_keepSessionPetsNearToy(session)
			self:_handlePetTriggeredBounce(session)
			task.wait(tickSeconds)
			elapsed += tickSeconds
		end

		self:_cleanupFinishedSession(toyPrimary)
	end)
end

function ToyHappinessManager:ConnectToyPrompt(toyInstance)
	if not toyInstance then return end
	local toyPrimary = getToyPrimaryPart(toyInstance)
	if not toyPrimary then return end

	local prompt = ensurePrompt(toyPrimary)
	if not prompt then return end
	if self.connectedPrompts[prompt] then return end

	prompt.ActionText = tostring(toyInstance:GetAttribute("PromptActionText") or "Play")
	prompt.ObjectText = tostring(toyInstance:GetAttribute("PromptObjectText") or "Toy")
	prompt.MaxActivationDistance = self:_readNumberAttribute(toyInstance, "PromptDistance", 8)
	prompt.HoldDuration = self:_readNumberAttribute(toyInstance, "PromptHold", 0)
	prompt.RequiresLineOfSight = false

	local conn = prompt.Triggered:Connect(function(player)
		if not player then return end
		local now = os.clock()
		local last = self.lastTriggeredAt[toyPrimary]
		if last and (now - last) < 0.15 then
			return
		end
		self.lastTriggeredAt[toyPrimary] = now

		local tycoonModel = self.TycoonUtils:FindTycoonByOwnerId(player.UserId)
		if not tycoonModel then
			local resolved = self.TycoonUtils:ResolveModelWithDeskFromInstance(toyInstance)
			tycoonModel = resolved
		end
		if not tycoonModel or not self:_isPlayerOwnerOfTycoon(player, tycoonModel) then
			return
		end
		if not self:_canTriggerToyJump(toyPrimary, toyInstance) then
			return
		end

		self:_runHappinessSession(player, toyInstance, toyPrimary)
	end)

	self.connectedPrompts[prompt] = conn
end


function ToyHappinessManager:_getDynamicToyList(template)
	self.dynamicToysByTemplate[template] = self.dynamicToysByTemplate[template] or {}
	local arr = self.dynamicToysByTemplate[template]
	local alive = {}
	for _, inst in ipairs(arr) do
		if inst and inst.Parent then
			table.insert(alive, inst)
		end
	end
	self.dynamicToysByTemplate[template] = alive
	return alive
end

function ToyHappinessManager:_cloneToyFromTemplate(template, index)
	if not template or not template.Parent then return nil end
	local clone = template:Clone()
	clone.Name = string.format("%s_Auto_%d", template.Name, index)
	clone:SetAttribute("IsDynamicToy", true)
	clone:SetAttribute("ToyType", self:_resolveToyType(template))

	if clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
	elseif clone:IsA("Model") then
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				desc.CanCollide = false
			end
		end
	end

	local templatePrimary = getToyPrimaryPart(template)
	local clonePrimary = getToyPrimaryPart(clone)
	if templatePrimary and clonePrimary then
		local offset = Vector3.new((index - 1) * 5, 0, 0)
		if clone:IsA("Model") then
			clone:PivotTo(template:GetPivot() + offset)
		else
			clone.CFrame = templatePrimary.CFrame + offset
		end
	end

	clone.Parent = template.Parent
	clonePrimary = clonePrimary or getToyPrimaryPart(clone)
	if clonePrimary then
		local tycoonModel = self.TycoonUtils:ResolveModelWithDeskFromInstance(template)
		local ownerId = tycoonModel and (tycoonModel:GetAttribute("OwnerId") or tycoonModel:GetAttribute("Owner") or tycoonModel:GetAttribute("OwnerUserId")) or nil
		local zonePart = ownerId and self:_resolveWanderZoneForOwner(tonumber(ownerId) or ownerId) or nil
		local groundedPos = self:_resolveGroundedPosition(clonePrimary.Position, clone, clonePrimary, zonePart)
		local current = getToyReferenceCFrame(clone, clonePrimary)
		local rx, ry, rz = current:ToOrientation()
		self:_setToyCFrame(clone, CFrame.new(groundedPos) * CFrame.fromOrientation(rx, ry, rz))
	end
	clone:SetAttribute("ToyGroundInitialized", true)
	return clone
end

function ToyHappinessManager:_syncToyCountForTycoon(ownerPlayer, template)
	if not ownerPlayer or not template then return end
	local ownedPets = self:_getOwnedPlayablePets(ownerPlayer)
	local maxPerToy = self:_readPositiveIntAttribute(template, "MaxPetsPerToy", DEFAULTS.MaxPetsPerToy)
	local needed = math.max(1, math.ceil(#ownedPets / maxPerToy))

	local dynamic = self:_getDynamicToyList(template)
	local have = 1 + #dynamic

	if have < needed then
		for i = have + 1, needed do
			local clone = self:_cloneToyFromTemplate(template, i)
			if clone then
				table.insert(dynamic, clone)
				self:ConnectToyPrompt(clone)
			end
		end
	elseif have > needed then
		local toRemove = have - needed
		for i = #dynamic, 1, -1 do
			if toRemove <= 0 then break end
			local toy = dynamic[i]
			if toy and toy.Parent then
				local primary = getToyPrimaryPart(toy)
				if primary then
					self:_cleanupFinishedSession(primary)
				end
				toy:Destroy()
			end
			table.remove(dynamic, i)
			toRemove -= 1
		end
	end
end

function ToyHappinessManager:EnsurePetDefaults(petModel)
	if not petModel then return end
	self.petState[petModel] = self.petState[petModel] or {}
	local state = self.petState[petModel]
	if state.happiness == nil then
		state.happiness = DEFAULT_MAX_HAPPINESS
	end

	if self.PetStateManager and self.PetStateManager.ClampPetCoreStats then
		self.PetStateManager:ClampPetCoreStats(petModel, state)
	else
		state.happiness = math.clamp(tonumber(state.happiness) or DEFAULT_MAX_HAPPINESS, 0, DEFAULT_MAX_HAPPINESS)
	end
end

function ToyHappinessManager:_startHappinessDecayLoop()
	if self.happinessDecayStarted then return end
	self.happinessDecayStarted = true
	task.spawn(function()
		while true do
			local waitTime = math.random(DEFAULTS.DecayIntervalMin, DEFAULTS.DecayIntervalMax)
			task.wait(waitTime)
			for petModel, st in pairs(self.petState) do
				if petModel and petModel.Parent and st and st.wild ~= true and st.ownerUserId then
					self:EnsurePetDefaults(petModel)
					local happinessMax = (self.PetStateManager and self.PetStateManager.GetPetStatMax)
						and self.PetStateManager:GetPetStatMax(petModel, "happiness", st)
						or DEFAULT_MAX_HAPPINESS
					local decay = math.random(DEFAULTS.DecayAmountMin, DEFAULTS.DecayAmountMax)
					local old = st.happiness
					st.happiness = math.clamp(old - decay, 0, happinessMax)
					if st.happiness ~= old then
						self.PetStateManager:SendStateToOwner(petModel)
						local owner = self.Players:GetPlayerByUserId(st.ownerUserId)
						if owner and self.PetSaveManager then
							if type(self.PetSaveManager.MarkDirty) == "function" then
								self.PetSaveManager:MarkDirty(owner)
							else
								self.PetSaveManager:ScheduleSave(owner)
							end
						end
					end
				end
			end
		end
	end)
end

function ToyHappinessManager:_ownerHasLowHappinessPets(player, threshold)
	if not player then return false end
	local target = tonumber(threshold) or 80
	for petModel, st in pairs(self.petState) do
		if petModel and petModel.Parent and st and st.wild ~= true and tonumber(st.ownerUserId) == tonumber(player.UserId) then
			if (tonumber(st.happiness) or DEFAULT_MAX_HAPPINESS) < target then
				return true
			end
		end
	end
	return false
end

function ToyHappinessManager:_startAutoToyPlayLoop()
	if self.autoToyPlayStarted then return end
	self.autoToyPlayStarted = true

	task.spawn(function()
		while true do
			task.wait(8)

			for _, rootName in ipairs({"Tycoon", "Tycoons"}) do
				local root = workspace:FindFirstChild(rootName)
				if not root then continue end

				for _, tycoonModel in ipairs(root:GetChildren()) do
					if not (tycoonModel:IsA("Model") or tycoonModel:IsA("Folder")) then continue end
					local essentials = self.TycoonUtils:FindEssentialsInModel(tycoonModel)
					if not essentials then continue end

					local ownerPlayer = self:_getOwnerPlayerFromTycoon(tycoonModel)
					if not ownerPlayer then continue end

					for _, toy in ipairs(self:_collectToyTemplatesFromEssentials(essentials)) do
						if toy:GetAttribute("AutoPlayWhenLowHappiness") ~= true then continue end
						if not self:_isToyTemplateEquippedForOwner(toy, ownerPlayer) then continue end

						local lowThreshold = tonumber(toy:GetAttribute("AutoPlayHappinessThreshold") or 80) or 80
						if not self:_ownerHasLowHappinessPets(ownerPlayer, lowThreshold) then continue end

						local toyPrimary = getToyPrimaryPart(toy)
						if not toyPrimary then continue end
						if self.activeSessionsByToy[toyPrimary] then continue end
						if not self:_canTriggerToyJump(toyPrimary, toy) then continue end

						self:_runHappinessSession(ownerPlayer, toy, toyPrimary)
					end
				end
			end
		end
	end)
end

function ToyHappinessManager:ScanAndConnectAll()
	local roots = {}
	local tycoonRoot = workspace:FindFirstChild("Tycoon")
	if tycoonRoot then table.insert(roots, tycoonRoot) end
	local topTycoons = workspace:FindFirstChild("Tycoons")
	if topTycoons then table.insert(roots, topTycoons) end

	for _, root in ipairs(roots) do
		for _, tycoonModel in ipairs(root:GetDescendants()) do
			if tycoonModel:IsA("Model") or tycoonModel:IsA("Folder") then
				local essentials = self.TycoonUtils:FindEssentialsInModel(tycoonModel)
				if essentials then
					local ownerPlayer = self:_getOwnerPlayerFromTycoon(tycoonModel)
					local templates = self:_collectToyTemplatesFromEssentials(essentials)
					for _, template in ipairs(templates) do
						local primary = getToyPrimaryPart(template)
						if primary then
							local isEquippedToy = self:_isToyTemplateEquippedForOwner(template, ownerPlayer)
							self:_setToyEnabled(template, isEquippedToy)
							if not isEquippedToy then
								local dynamic = self:_getDynamicToyList(template)
								for i = #dynamic, 1, -1 do
									local toy = dynamic[i]
									if toy and toy.Parent then
										local p = getToyPrimaryPart(toy)
										if p then
											self:_cleanupFinishedSession(p)
										end
										toy:Destroy()
									end
									table.remove(dynamic, i)
								end
								continue
							end

							primary.Anchored = true
							primary.CanCollide = false
							template:SetAttribute("ToyType", self:_resolveToyType(template))
							local ownerId = tycoonModel:GetAttribute("OwnerId") or tycoonModel:GetAttribute("Owner") or tycoonModel:GetAttribute("OwnerUserId")
							local zonePart = ownerId and self:_resolveWanderZoneForOwner(tonumber(ownerId) or ownerId) or nil
							if template:GetAttribute("ToyGroundInitialized") ~= true then
								local groundedPos = self:_resolveGroundedPosition(primary.Position, template, primary, zonePart)
								local current = getToyReferenceCFrame(template, primary)
								local rx, ry, rz = current:ToOrientation()
								self:_setToyCFrame(template, CFrame.new(groundedPos) * CFrame.fromOrientation(rx, ry, rz))
								template:SetAttribute("ToyGroundInitialized", true)
							end
							self:ConnectToyPrompt(template)
							if ownerPlayer then
								self:_syncToyCountForTycoon(ownerPlayer, template)
							end
						end
					end
				end
			end
		end
	end

	for petModel, state in pairs(self.petState) do
		if petModel and petModel.Parent and state and state.wild ~= true then
			self:EnsurePetDefaults(petModel)
		end
	end
end

return ToyHappinessManager
