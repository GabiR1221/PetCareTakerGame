local PetStateManager = {}
local LEVEL_THRESHOLDS = { 0, 50, 150, 350, 750, 1550 }
local Players = game:GetService("Players")
local DEFAULT_BASE_PET_SCALE = 1.0
local SCALE_PER_LEVEL = 0.08 -- intentionally conservative so high-level pets don't become oversized
local MIN_ALLOWED_SCALE = 0.5
local MAX_ALLOWED_SCALE = 2.25

local function resolveInventoryPetIdByUid(player, petUid)
	if not player or type(petUid) ~= "string" or petUid == "" then return nil end
	local data = player:FindFirstChild("Data")
	local pets = data and data:FindFirstChild("Pets")
	if not pets then return nil end

	for _, petFolder in ipairs(pets:GetChildren()) do
		local uidValue = petFolder:FindFirstChild("PetUID")
		if uidValue and uidValue.Value == petUid then
			return tostring(petFolder.Name)
		end
	end

	return nil
end


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

function PetStateManager:CalculateScaleForLevel(level, baseScale)
	level = math.max(1, math.floor(tonumber(level) or 1))
	baseScale = tonumber(baseScale) or DEFAULT_BASE_PET_SCALE
	baseScale = math.clamp(baseScale, MIN_ALLOWED_SCALE, MAX_ALLOWED_SCALE)
	local computed = baseScale * (1 + SCALE_PER_LEVEL * (level - 1))
	return math.clamp(computed, MIN_ALLOWED_SCALE, MAX_ALLOWED_SCALE)
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
		local baseScale = tonumber(state.baseScale) or tonumber(state.scale) or DEFAULT_BASE_PET_SCALE
		local newScale = self:CalculateScaleForLevel(newLevel, baseScale)
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
		hunger = tonumber(st.hunger) or 100,
		petName = tostring(petModel.Name),
		petUid = tostring(st.petUid or petModel:GetAttribute("PetUID") or ""),
		inventoryPetId = nil,
		levelProgress = progress,
		xpInLevel = xpInLevel,
		xpForNext = xpForNext
	}
	if payload.petUid ~= "" then
		st.petUid = payload.petUid
	end
	payload.inventoryPetId = resolveInventoryPetIdByUid(player, payload.petUid)
	if payload.inventoryPetId then
		local data = player:FindFirstChild("Data")
		local petsFolder = data and data:FindFirstChild("Pets")
		local inventoryPet = petsFolder and petsFolder:FindFirstChild(payload.inventoryPetId)
		if inventoryPet then
			local levelValue = inventoryPet:FindFirstChild("Level")
			if not levelValue then
				levelValue = Instance.new("IntValue")
				levelValue.Name = "Level"
				levelValue.Parent = inventoryPet
			end
			levelValue.Value = level

			local xpValue = inventoryPet:FindFirstChild("XP")
			if not xpValue then
				xpValue = Instance.new("IntValue")
				xpValue.Name = "XP"
				xpValue.Parent = inventoryPet
			end
			xpValue.Value = xp
		end
	end

	pcall(function()
		self.petStateEvent:FireClient(player, "UpdatePetState", petModel, payload)
	end)
end

function PetStateManager:SetPetScale(petModel, newScale)
	if not petModel or not petModel:IsA("Model") then return end
	newScale = tonumber(newScale) or 1
	newScale = math.clamp(newScale, MIN_ALLOWED_SCALE, MAX_ALLOWED_SCALE)

	self.petState[petModel] = self.petState[petModel] or {}
	local state = self.petState[petModel]
	local oldScale = tonumber(state.scale) or 1
	local currentModelScale = nil
	pcall(function()
		currentModelScale = tonumber(petModel:GetScale())
	end)
	if currentModelScale == nil then
		currentModelScale = oldScale
	end
	local appliedCurrentScale = (type(currentModelScale) == "number" and currentModelScale > 0) and currentModelScale or oldScale
	if math.abs(oldScale - newScale) < 0.0001 and math.abs(currentModelScale - newScale) < 0.0001 then
		state.scale = newScale
		return
	end

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
	local scaledOk = pcall(function()
		petModel:ScaleTo(newScale)
	end)

	-- Fallback for rigs that cannot use ScaleTo (kept lightweight but includes PrimaryPart).
	if not scaledOk then
		-- IMPORTANT: use the model's *actual* current scale as denominator.
		-- Using stale saved state here can cause no-op resizing on rejoin.
		local scaleFactor = newScale / (appliedCurrentScale == 0 and 1 or appliedCurrentScale)
		local primaryCFrame = primary.CFrame

		for _, desc in ipairs(petModel:GetDescendants()) do
			if desc:IsA("BasePart") then
				if desc ~= primary then
					local rel = primaryCFrame:ToObjectSpace(desc.CFrame)
					local rx, ry, rz = rel:ToEulerAnglesXYZ()
					local newRel = CFrame.new(rel.Position * scaleFactor) * CFrame.Angles(rx, ry, rz)
					desc.CFrame = primaryCFrame * newRel
				end

				desc.Size = desc.Size * scaleFactor

				for _, m in ipairs(desc:GetChildren()) do
					if m:IsA("SpecialMesh") then
						local old = m.Scale or Vector3.new(1, 1, 1)
						m.Scale = old * scaleFactor
					end
				end
			end
		end
	end

	local humanoid = petModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local baseHip = humanoid:GetAttribute("BaseHipHeight")
		if type(baseHip) ~= "number" then
			baseHip = (tonumber(humanoid.HipHeight) or 0) / (oldScale == 0 and 1 or oldScale)
			humanoid:SetAttribute("BaseHipHeight", baseHip)
		end

		local targetHip = math.max(0, baseHip * newScale)
		if math.abs((humanoid.HipHeight or 0) - targetHip) > 0.001 then
			humanoid.HipHeight = targetHip
		end
	end

	state.scale = newScale
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
