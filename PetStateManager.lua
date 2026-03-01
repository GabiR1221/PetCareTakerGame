local PetStateManager = {}
local LEVEL_THRESHOLDS = { 0, 50, 150, 350, 750, 1550 }
local Players = game:GetService("Players")

function PetStateManager:Initialize(stateTable, petStateEvent, carryingTable)
	self.petState = stateTable or {}
	self.petStateEvent = petStateEvent
	self.carryingPetByUserId = carryingTable or {}
end

function PetStateManager:GetLevelFromXP(xp)
	xp = tonumber(xp) or 0
	local level = 1
	for i = 1, #LEVEL_THRESHOLDS do
		if xp >= LEVEL_THRESHOLDS[i] then
			level = i
		else
			break
		end
	end
	return level
end

function PetStateManager:XPForNextLevel(level)
	level = tonumber(level) or 1
	if LEVEL_THRESHOLDS[level + 1] then
		return LEVEL_THRESHOLDS[level + 1] - (LEVEL_THRESHOLDS[level] or 0)
	end
	return math.huge
end

function PetStateManager:AddXP(petModel, amount)
	if not petModel then return end
	self.petState[petModel] = self.petState[petModel] or {}
	local state = self.petState[petModel]

	-- Get power and rarity multiplier (from state, fallback to attributes/defaults)
	local power = state.power or (petModel:GetAttribute("Power") or 1)
	local rarityMult = state.rarityMultiplier or (petModel:GetAttribute("RarityMultiplier") or 1)

	-- Actual XP = (base + power) * multiplier
	local actualXP = (amount + power) * rarityMult
	actualXP = math.floor(actualXP)  -- ensure integer

	state.xp = (state.xp or 0) + actualXP

	-- Level calculation (unchanged)
	local prevLevel = state.level or self:GetLevelFromXP(0)
	local newLevel = self:GetLevelFromXP(state.xp)
	state.level = newLevel

	self:SendStateToOwner(petModel)

	if newLevel > prevLevel then
		local baseScale = 1.0
		local newScale = baseScale * (1 + 0.15 * (newLevel - 1))
		self:SetPetScale(petModel, newScale)
		print(("[PetStateManager] Pet %s leveled up %d -> %d (xp=%d). New scale=%.2f"):format(
			tostring(petModel.Name), prevLevel, newLevel, state.xp, newScale))
	end

	return newLevel > prevLevel, newLevel
end

function PetStateManager:SendStateToOwner(petModel)
	if not petModel then return end
	local st = self.petState[petModel] or {}
	local uid = st.ownerUserId
	if not uid then return end
	local player = Players:GetPlayerByUserId(uid)
	if not player or not self.petStateEvent then return end

	local xp = st.xp or 0
	local level = st.level or self:GetLevelFromXP(xp)
	local xpInLevel = xp - (LEVEL_THRESHOLDS[level] or 0)
	local xpForNext = self:XPForNextLevel(level)
	local progress = 0
	if xpForNext and xpForNext ~= math.huge then
		progress = math.clamp(xpInLevel / xpForNext, 0, 1)
	end

	local payload = {
		xp = xp,
		level = level,
		scale = st.scale or 1,
		dirtiness = tonumber(st.dirtiness) or 0,
		wetness = tonumber(st.wetness) or 0,
		petName = tostring(petModel.Name),
		levelProgress = progress,
		xpInLevel = xpInLevel,
		xpForNext = xpForNext
	}

	pcall(function()
		self.petStateEvent:FireClient(player, "UpdatePetState", petModel, payload)
	end)
end

function PetStateManager:SetPetScale(petModel, newScale)
	if not petModel or not petModel:IsA("Model") then return end

	local function setModelPrimaryIfMissing(model)
		if not model or not model:IsA("Model") then return end
		if model.PrimaryPart then return end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				pcall(function() model.PrimaryPart = d end)
				if model.PrimaryPart then return end
			end
		end
	end

	setModelPrimaryIfMissing(petModel)
	local primary = petModel.PrimaryPart
	if not primary then return end

	local state = self.petState[petModel] or {}
	local oldScale = state.scale or 1
	if oldScale == newScale then
		state.scale = newScale
		self.petState[petModel] = state
		return
	end

	local scaleFactor = newScale / (oldScale == 0 and 1 or oldScale)
	local primaryCFrame = primary.CFrame

	for _, desc in ipairs(petModel:GetDescendants()) do
		if desc:IsA("BasePart") and desc ~= primary then
			local rel = primaryCFrame:ToObjectSpace(desc.CFrame)
			local rx, ry, rz = rel:ToEulerAnglesXYZ()
			local newRel = CFrame.new(rel.Position * scaleFactor) * CFrame.Angles(rx, ry, rz)
			desc.CFrame = primaryCFrame * newRel
			desc.Size = desc.Size * scaleFactor

			for _, m in ipairs(desc:GetChildren()) do
				if m:IsA("SpecialMesh") then
					local old = m.Scale or Vector3.new(1,1,1)
					m.Scale = old * scaleFactor
				end
			end
		end
	end

	self.petState[petModel] = self.petState[petModel] or {}
	self.petState[petModel].scale = newScale
end

function PetStateManager:UpdatePetAttribute(petModel, attribute, value)
	if not petModel then return end
	self.petState[petModel] = self.petState[petModel] or {}
	self.petState[petModel][attribute] = value
	self:SendStateToOwner(petModel)
end

function PetStateManager:GetPetState(petModel)
	return self.petState[petModel] or {}
end

function PetStateManager:IsPlayerCarrying(player)
	if not player then return false end
	return self.carryingPetByUserId[player.UserId] ~= nil
end

return PetStateManager
