local PetAttachmentManager = {}


function PetAttachmentManager:Initialize(stateTable, carryingTable, playersService, petMovement)
	self.petState = stateTable or {}
	self.carryingPetByUserId = carryingTable or {}
	self.Players = playersService
	self.PetMovement = petMovement
	self.petCarryRemote = self.petCarryRemote or nil

	-- Reference to animation functions (if needed)
	self.teardownAnimatorForPet = require(script.Parent.PetAnimationManager).TeardownAnimatorForPet
end

function PetAttachmentManager:SetCarryRemote(remoteEvent)
	self.petCarryRemote = remoteEvent
end

function PetAttachmentManager:_notifyCarryState(userId, isCarrying, petModel)
	if not self.petCarryRemote or not self.Players or not userId then return end
	local player = self.Players:GetPlayerByUserId(tonumber(userId) or -1)
	if not player then return end
	local petName = nil
	local canDrop = isCarrying == true
	if petModel and petModel.Name then
		petName = tostring(petModel.Name)
	end
	if petModel and self.petState and self.petState[petModel] and self.petState[petModel].wild == true then
		canDrop = false
	end
	pcall(function()
		self.petCarryRemote:FireClient(player, "CarryState", isCarrying == true, petName, canDrop)
	end)
end

function PetAttachmentManager:_findCarrierUserIdForPet(petModel)
	if not petModel then return nil end
	for uid, carriedPet in pairs(self.carryingPetByUserId) do
		if carriedPet == petModel then
			return uid
		end
	end
	return nil
end



function PetAttachmentManager:SetModelPrimaryIfMissing(model)
	if not model or not model:IsA("Model") then return end
	if model.PrimaryPart then return end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local inDirtFolder = d:FindFirstAncestor("Dirt") ~= nil
			local inVisualsFolder = d:FindFirstAncestor("PetVisuals") ~= nil
			if inDirtFolder or inVisualsFolder then
				continue
			end
			pcall(function() model.PrimaryPart = d end)
			if model.PrimaryPart then return end
		end
	end
	-- Fallback if every part was in an excluded folder
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			pcall(function() model.PrimaryPart = d end)
			if model.PrimaryPart then return end
		end
	end
end

function PetAttachmentManager:ClearWeldsOnPart(part)
	if not part then return end
	for _, w in ipairs(part:GetDescendants()) do
		if w:IsA("Weld") or w:IsA("WeldConstraint") or w:IsA("AlignPosition") or w:IsA("AlignOrientation") then
			pcall(function() w:Destroy() end)
		end
	end
	for _, w in ipairs(part:GetChildren()) do
		if w:IsA("Weld") or w:IsA("WeldConstraint") or w:IsA("AlignPosition") or w:IsA("AlignOrientation") then
			pcall(function() w:Destroy() end)
		end
	end
end

function PetAttachmentManager:ClearDirectModelWelds(model)
	if not model or not model.GetChildren then return end
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("Weld") or c:IsA("WeldConstraint") or c:IsA("AlignPosition") or c:IsA("AlignOrientation") or
			c:IsA("BodyVelocity") or c:IsA("LinearVelocity") or c:IsA("AngularVelocity") or
			c:IsA("VectorForce") or c:IsA("BodyForce") then
			pcall(function() c:Destroy() end)
		end
	end
end

function PetAttachmentManager:WeldParts(a, b)
	if not a or not b or not a:IsA("BasePart") or not b:IsA("BasePart") then return nil end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = a
	weld.Part1 = b
	weld.Parent = a
	return weld
end

function PetAttachmentManager:DetachPetFromPlayer(petModel)
	if not petModel or not petModel:IsA("Model") then return end
	self:SetModelPrimaryIfMissing(petModel)
	local ppart = petModel.PrimaryPart
	if ppart then
		self:ClearWeldsOnPart(ppart)
		ppart.CanCollide = false
	end

	if self.petState[petModel] then
		local owner = self.petState[petModel].ownerUserId or self:_findCarrierUserIdForPet(petModel)
		if owner then self.carryingPetByUserId[owner] = nil end
		if owner then self:_notifyCarryState(owner, false, nil) end
		self.petState[petModel].npc = nil
		self.petState[petModel].shower = nil
		self.petState[petModel].location = "free"
	end

	return true
end

function PetAttachmentManager:AttachPetToPart(petModel, part, opts)
	if not petModel or not part or not part:IsA("BasePart") then return false end
	opts = opts or {}
	self:SetModelPrimaryIfMissing(petModel)
	local ppart = petModel.PrimaryPart
	if not ppart then return false end

	self:ClearWeldsOnPart(ppart)
	petModel.Parent = workspace

	local targetCFrame = nil
	local standAttachment = opts.standAttachment
	local petAttachment = opts.petAttachment
	if standAttachment and standAttachment:IsA("Attachment") and petAttachment and petAttachment:IsA("Attachment") then
		targetCFrame = standAttachment.WorldCFrame * petAttachment.CFrame:Inverse()
	else
		local yOff = (part.Size.Y / 2) + (ppart.Size.Y / 2)
		targetCFrame = part.CFrame * CFrame.new(0, yOff, 0)
	end
	petModel:SetPrimaryPartCFrame(targetCFrame)
	ppart.CanCollide = false

	pcall(function() self:WeldParts(ppart, part) end)

	if self.petState[petModel] and self.petState[petModel].ownerUserId then
		local ownerId = self.petState[petModel].ownerUserId
		self.carryingPetByUserId[ownerId] = nil
		self:_notifyCarryState(ownerId, false, nil)
	end

	self.petState[petModel] = self.petState[petModel] or {}
	self.petState[petModel].npc = nil
	self.PetMovement.StopWandering(petModel)

	return true
end

function PetAttachmentManager:AttachWildPetToPlayer(petModel, player, opts)
	-- Similar to AttachPetToPlayer but doesn't set ownerUserId
	opts = opts or {}
	if not petModel or not player then return false, "missing args" end
	local char = player.Character
	if not char or not char.PrimaryPart then return false, "no char" end

	-- Ensure PrimaryPart exists
	self:SetModelPrimaryIfMissing(petModel)
	local ppart = petModel.PrimaryPart
	if not ppart then return false, "pet has no PrimaryPart" end
	self.PetMovement.StopWandering(petModel)
	local teardownAnimatorForPet = require(script.Parent.PetAnimationManager).TeardownAnimatorForPet

	-- STOP/TEARDOWN any pet animator before we move the pet into the player's character
	if type(teardownAnimatorForPet) == "function" then
		pcall(function() teardownAnimatorForPet(petModel) end)
	end

	-- Remove the pet's Humanoid while carried
	local petHum = petModel:FindFirstChildOfClass("Humanoid")
	if petHum then
		self.petState[petModel] = self.petState[petModel] or {}
		self.petState[petModel].hadHumanoid = true
		local storedBaseHip = petHum:GetAttribute("BaseHipHeight")
		if type(storedBaseHip) ~= "number" then
			storedBaseHip = tonumber(petHum.HipHeight) or 0
		end
		petModel:SetAttribute("StoredBaseHipHeight", math.max(0, tonumber(storedBaseHip) or 0))
		pcall(function() petHum:Destroy() end)
	end

	-- destroy any weld-like objects parented directly under the pet model
	self:ClearDirectModelWelds(petModel)

	-- clear welds on petPrimary (in-case there are welds parented on the part)
	self:ClearWeldsOnPart(ppart)

	-- parent pet under character so it follows together (no Humanoid present now)
	petModel.Parent = char

	-- disable collisions and make massless on pet parts while carried to avoid wedging / heavy physics
	for _, bp in ipairs(petModel:GetDescendants()) do
		if bp:IsA("BasePart") then
			pcall(function() bp.CanCollide = false end)
			pcall(function() bp.Massless = true end)
			pcall(function() bp.Anchored = false end)
		end
	end

	-- position pet in front of HRP
	local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
	if hrp then
		pcall(function()
			ppart.AssemblyLinearVelocity = Vector3.zero
			ppart.AssemblyAngularVelocity = Vector3.zero
		end)
		petModel:SetPrimaryPartCFrame(hrp.CFrame * CFrame.new(0, 0, -2))
	end

	-- create a WeldConstraint between pet.PrimaryPart and HRP (non-physical link)
	local attachPart = hrp
	if opts.attachToHand then
		local rightHand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
		if rightHand and rightHand:IsA("BasePart") then
			attachPart = rightHand
		end
	end

	-- create a WeldConstraint between pet.PrimaryPart and target part (non-physical link)
	pcall(function() self:WeldParts(ppart, attachPart) end)
	if attachPart ~= hrp then
		local armOffset = CFrame.new(0, -0.5, -0.5) * CFrame.Angles(0, math.rad(90), 0)
		petModel:SetPrimaryPartCFrame(attachPart.CFrame * armOffset)
	end

	-- update maps (but don't set ownerUserId yet)
	local uid = player.UserId
	self.carryingPetByUserId[uid] = petModel
	self:_notifyCarryState(uid, true, petModel)
	self.petState[petModel] = self.petState[petModel] or {}
	self.petState[petModel].location = "player_wild"
	self.petState[petModel].npc = nil
	self.petState[petModel].shower = nil

	return true
end

function PetAttachmentManager:AttachPetToPlayer(petModel, player, opts)
	opts = opts or {}
	local resetFlags = opts.resetFlags == true

	if not petModel or not player then return false, "missing args" end
	local char = player.Character
	if not char or not char.PrimaryPart then return false, "no char" end

	self:SetModelPrimaryIfMissing(petModel)
	local ppart = petModel.PrimaryPart
	if not ppart then return false, "pet has no PrimaryPart" end
	self.PetMovement.StopWandering(petModel)

	local petHum = petModel:FindFirstChildOfClass("Humanoid")
	if petHum then
		self.petState[petModel] = self.petState[petModel] or {}
		self.petState[petModel].hadHumanoid = true
		local storedBaseHip = petHum:GetAttribute("BaseHipHeight")
		if type(storedBaseHip) ~= "number" then
			storedBaseHip = tonumber(petHum.HipHeight) or 0
		end
		petModel:SetAttribute("StoredBaseHipHeight", math.max(0, tonumber(storedBaseHip) or 0))
		pcall(function() petHum:Destroy() end)
	end

	self:ClearDirectModelWelds(petModel)
	self:ClearWeldsOnPart(ppart)
	petModel.Parent = char

	for _, bp in ipairs(petModel:GetDescendants()) do
		if bp:IsA("BasePart") then
			pcall(function() bp.CanCollide = false end)
			pcall(function() bp.Massless = true end)
			pcall(function() bp.Anchored = false end)
		end
	end

	local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
	if hrp then
		pcall(function()
			ppart.AssemblyLinearVelocity = Vector3.zero
			ppart.AssemblyAngularVelocity = Vector3.zero
		end)
		petModel:SetPrimaryPartCFrame(hrp.CFrame * CFrame.new(0, 0, -2))
	end

	pcall(function() self:WeldParts(ppart, hrp) end)

	local uid = player.UserId
	self.carryingPetByUserId[uid] = petModel
	self:_notifyCarryState(uid, true, petModel)
	self.petState[petModel] = self.petState[petModel] or {}
	self.petState[petModel].ownerUserId = uid
	self.petState[petModel].location = "player"
	self.petState[petModel].npc = nil
	self.petState[petModel].shower = nil

	if resetFlags then
		self.petState[petModel].showered = false
		self.petState[petModel].dried = true
	else
		self.petState[petModel].showered = self.petState[petModel].showered == true
		self.petState[petModel].dried = true
	end

	return true
end

return PetAttachmentManager
