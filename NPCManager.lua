local NPCManager = {}
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

function NPCManager:Initialize(npcsFolder, stateTable, carryingTable, playersService, config)
	self.NPCS_FOLDER = npcsFolder
	self.petState = stateTable or {}
	self.carryingPetByUserId = carryingTable or {}
	self.Players = playersService
	self.Config = config or {}

	self.npcPromptConnections = {}

	-- Load dependencies
	self.PromptManager = require(script.Parent.PromptManager)
	self.PetAttachmentManager = require(script.Parent.PetAttachmentManager)
	self.PetStateManager = require(script.Parent.PetStateManager)
	self.PetRigManager = require(script.Parent.PetRigManager)
	self.PetAnimationManager = require(script.Parent.PetAnimationManager)
	self.TycoonUtils = require(script.Parent.TycoonUtils)

	self.TycoonUtils:Initialize(config)
end

function NPCManager:IsPlayerOwnerOfNPC(player, npc)
	if not player or not npc then return false end
	local tid = npc:GetAttribute("TargetOwnerId")
	if not tid then return false end
	return tostring(tid) == tostring(player.UserId)
end

function NPCManager:InitializeNPCWithPet(npcModel)
	if not npcModel or not npcModel:IsA("Model") then return end

	local npcPet = npcModel:FindFirstChild("Pet")
	if npcPet and not self.petState[npcPet] then
		self.petState[npcPet] = self.petState[npcPet] or {}
		local state = self.petState[npcPet]
		state.xp = 0
		state.level = 1
		state.scale = 1.0
		state.npc = npcModel
		state.location = "npc"
		
		-- Read power and rarity from the pet model (they may already have attributes)
		local power = npcPet:GetAttribute("Power") or 1
		local rarityMult = npcPet:GetAttribute("RarityMultiplier") or 1

		state.power = power
		state.rarityMultiplier = rarityMult

		-- Initialize dirtiness/wetness based on NPC requests
		local wantsShower = npcModel:GetAttribute("RequestShower") == true
		if wantsShower then
			state.dirtiness = math.random(60, 100)
		else
			state.dirtiness = math.random(0, 20)
		end

		state.hunger = 100

		local wantsDry = npcModel:GetAttribute("RequestDry") == true
		if wantsDry then
			state.wetness = 100
			state.dried = false
		else
			state.wetness = math.random(0, 20)
			state.dried = false
		end

		-- Set up pet rig
		self.PetRigManager:EnsurePetRig(npcPet)
		self.PetAnimationManager:SetupAnimatorForPet(npcPet)

		if npcPet.PrimaryPart then 
			pcall(function() npcPet.PrimaryPart.Anchored = false end) 
		end

		-- Attach pet to NPC
		local attachTo = npcModel:FindFirstChild("HumanoidRootPart") or npcModel.PrimaryPart
		if not attachTo then
			for _, d in ipairs(npcModel:GetDescendants()) do
				if d:IsA("BasePart") then
					attachTo = d
					break
				end
			end
		end

		local ppart = npcPet.PrimaryPart
		if ppart then
			if attachTo then
				pcall(function()
					npcPet.Parent = npcModel
					local prevAnchored = ppart.Anchored
					ppart.Anchored = true
					npcPet:SetPrimaryPartCFrame(attachTo.CFrame * CFrame.new(0, 1, -1))
					ppart.CanCollide = false
					self.PetAttachmentManager:ClearWeldsOnPart(ppart)
					self.PetAttachmentManager:WeldParts(ppart, attachTo)
					pcall(function() ppart.Anchored = prevAnchored and true or false end)
				end)
			else
				pcall(function()
					npcPet.Parent = npcModel
					npcPet:SetPrimaryPartCFrame(npcModel:GetModelCFrame() * CFrame.new(0, 2, 0))
					ppart.CanCollide = false
				end)
			end
		end

		self.PetStateManager:SetPetScale(npcPet, 1.0)
		self.PetStateManager:SendStateToOwner(npcPet)
	end
end

function NPCManager:CleanupNPCPrompt(npc)
	if not npc then return end
	local helper = npc:FindFirstChild("PetPickupPart")
	if helper then
		local prompt = helper:FindFirstChildWhichIsA("ProximityPrompt")
		if prompt then
			pcall(function() prompt:Destroy() end)
		end
		pcall(function() helper:Destroy() end)
	end
	if self.npcPromptConnections[npc] then
		pcall(function() self.npcPromptConnections[npc]:Disconnect() end)
		self.npcPromptConnections[npc] = nil
	end
end

function NPCManager:CommandNPCReturnAndCleanup(npc)
	if not npc then return end
	local sx = npc:GetAttribute("SpawnPositionX")
	local sy = npc:GetAttribute("SpawnPositionY")
	local sz = npc:GetAttribute("SpawnPositionZ")
	local spawnCFrame = nil
	if sx and sy and sz then
		spawnCFrame = CFrame.new(tonumber(sx), tonumber(sy), tonumber(sz))
	end

	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
	if humanoid and root and spawnCFrame then
		pcall(function()
			humanoid:MoveTo(spawnCFrame.Position)
		end)
		task.wait(4)
		pcall(function() npc:Destroy() end)
	else
		task.wait(0.2)
		pcall(function() npc:Destroy() end)
	end
end

function NPCManager:GivePetToNPC(petModel, npcModel)
	if not petModel or not npcModel then return false, "missing args" end
	self.PetAttachmentManager:SetModelPrimaryIfMissing(petModel)
	local ppart = petModel.PrimaryPart
	if not ppart then return false, "pet has no PrimaryPart" end

	-- Read NPC requests
	local reqShower = npcModel:GetAttribute("RequestShower") == true
	local reqDry = npcModel:GetAttribute("RequestDry") == true
	local reqAccessoryA = npcModel:GetAttribute("RequestAccessoryA") == true
	local reqAccessoryB = npcModel:GetAttribute("RequestAccessoryB") == true
	local reqLevelMin = npcModel:GetAttribute("RequestLevelMin")
	local reqLevelMax = npcModel:GetAttribute("RequestLevelMax")

	local petState = self.petState[petModel] or {}
	local petShowered = petState.showered == true
	local petDried = petState.dried == true
	local petAcc = petState.accessories or {}
	local petAccA = petAcc.A == true
	local petAccB = petAcc.B == true
	local petLevel = petState.level or self.PetStateManager:GetLevelFromXP(petState.xp or 0)

	local satisfied = true
	local missing = {}

	if reqShower and not petShowered then
		satisfied = false
		table.insert(missing, "Shower")
	end
	if reqDry and not petDried then
		satisfied = false
		table.insert(missing, "Dry")
	end
	if reqAccessoryA and not petAccA then
		satisfied = false
		table.insert(missing, "Accessory A")
	end
	if reqAccessoryB and not petAccB then
		satisfied = false
		table.insert(missing, "Accessory B")
	end

	if reqLevelMin and tonumber(reqLevelMin) then
		local minL = tonumber(reqLevelMin)
		local maxL = tonumber(reqLevelMax) or minL
		if petLevel < minL or petLevel > maxL then
			satisfied = false
			table.insert(missing, ("Level %d-%d"):format(minL, maxL))
		end
	end

	if not satisfied then
		if npcModel and npcModel.SetAttribute then
			pcall(function()
				if reqShower then npcModel:SetAttribute("NeedsShower", not petShowered) end
				if reqDry then npcModel:SetAttribute("NeedsDry", not petDried) end
				if reqAccessoryA then npcModel:SetAttribute("NeedsAccessoryA", not petAccA) end
				if reqAccessoryB then npcModel:SetAttribute("NeedsAccessoryB", not petAccB) end
				if reqLevelMin then
					local minL = tonumber(reqLevelMin)
					local maxL = tonumber(reqLevelMax) or minL
					npcModel:SetAttribute("NeedsLevel", ("%d-%d"):format(minL, maxL))
				end
			end)
		end
		return false, "requirements not met", missing
	end

	-- All requirements satisfied
	self.PetAttachmentManager:ClearWeldsOnPart(ppart)
	self.PetAttachmentManager:ClearDirectModelWelds(petModel)

	local attachTo = npcModel:FindFirstChild("HumanoidRootPart") or npcModel.PrimaryPart
	if not attachTo then
		for _, d in ipairs(npcModel:GetDescendants()) do
			if d:IsA("BasePart") then 
				attachTo = d
				break
			end
		end
	end

	petModel.Parent = npcModel
	if attachTo then
		petModel:SetPrimaryPartCFrame(attachTo.CFrame * CFrame.new(0, 1, -1))
		if ppart then ppart.CanCollide = false end
		self.PetAttachmentManager:ClearWeldsOnPart(ppart)
		self.PetAttachmentManager:WeldParts(ppart, attachTo)
	else
		petModel:SetPrimaryPartCFrame(npcModel:GetModelCFrame() * CFrame.new(0, 2, 0))
	end

	-- Update state
	self.petState[petModel] = self.petState[petModel] or {}
	self.petState[petModel].location = "npc"
	self.petState[petModel].npc = npcModel
	self.petState[petModel].shower = nil
	if self.petState[petModel].ownerUserId then
		self.carryingPetByUserId[self.petState[petModel].ownerUserId] = nil
	end

	-- Mark NPC as leaving
	if npcModel and npcModel.SetAttribute then
		pcall(function()
			npcModel:SetAttribute("Leaving", true)
			npcModel:SetAttribute("NeedsShower", false)
			npcModel:SetAttribute("NeedsDry", false)
			npcModel:SetAttribute("NeedsAccessoryA", false)
			npcModel:SetAttribute("NeedsAccessoryB", false)
		end)
	end

	return true
end

function NPCManager:SetupNPC(npcModel)
	if not npcModel or not npcModel:IsA("Model") then return end
	if self.npcPromptConnections[npcModel] then return end

	-- Initialize pet if exists
	self:InitializeNPCWithPet(npcModel)

	-- Create prompt
	local helper, prompt = self.PromptManager:CreatePickupPromptForNPC(npcModel)
	if not prompt then return end

	local conn = prompt.Triggered:Connect(function(player)
		if not self:IsPlayerOwnerOfNPC(player, npcModel) then return end
		if tostring(npcModel:GetAttribute("AtDesk")) ~= "true" then return end

		local pet = npcModel:FindFirstChild("Pet")
		if pet and (pet:IsA("Model") or pet:IsA("BasePart")) then
			-- TAKE PET
			if self.carryingPetByUserId[player.UserId] then return end

			local ok, err = self.PetAttachmentManager:AttachPetToPlayer(pet, player, { resetFlags = true })
			if ok then
				self.petState[pet] = self.petState[pet] or {}
				self.petState[pet].npc = nil
				self.petState[pet].location = "player"
				prompt.ActionText = "Give Pet"
			else
				warn("PetManager: failed to attach pet to player:", err)
			end
		else
			-- GIVE PET
			local petModel = self.carryingPetByUserId[player.UserId]
			if not petModel then return end

			local ok, err, missing = self:GivePetToNPC(petModel, npcModel)
			if ok then
				print(("[PetManager] Player %s successfully gave pet %s to NPC %s"):format(player.Name, tostring(petModel.Name), tostring(npcModel.Name)))
			else
				warn(("[PetManager] GivePet rejected for player %s -> %s"):format(player.Name, tostring(err)))

				local needs = {}
				if missing and type(missing) == "table" and #missing > 0 then
					for _, v in ipairs(missing) do
						table.insert(needs, v)
					end
				else
					local attemptedPet = self.carryingPetByUserId[player.UserId]
					local state = attemptedPet and self.petState[attemptedPet] or {}

					if npcModel.GetAttribute then
						local rs = npcModel:GetAttribute("RequestShower")
						local rd = npcModel:GetAttribute("RequestDry")
						local ra = npcModel:GetAttribute("RequestAccessoryA")
						local rb = npcModel:GetAttribute("RequestAccessoryB")

						if rs and not (state.showered == true) then table.insert(needs, "Shower") end
						if rd and not (state.dried == true) then table.insert(needs, "Dry") end

						local acc = state.accessories or {}
						if ra and not (acc.A == true) then table.insert(needs, "Accessory A") end
						if rb and not (acc.B == true) then table.insert(needs, "Accessory B") end
					end
				end

				local reqText = ""
				if #needs > 0 then reqText = "Needs: "..table.concat(needs, " + ") end

				if prompt and prompt:IsA("ProximityPrompt") and reqText ~= "" then
					pcall(function() prompt.ObjectText = ("Pet (%s)"):format(reqText) end)
					task.delay(3, function()
						if prompt and prompt.Parent then
							pcall(function() prompt.ObjectText = "Pet" end)
						end
					end)
				end
			end
		end
	end)

	self.npcPromptConnections[npcModel] = conn

	-- Update prompt text dynamically
	task.spawn(function()
		while npcModel.Parent do
			local pet = npcModel:FindFirstChild("Pet")
			if pet then
				prompt.ActionText = "Take Pet"
			else
				prompt.ActionText = "Give Pet"
			end
			task.wait(0.4)
		end
		self:CleanupNPCPrompt(npcModel)
	end)
end

function NPCManager:WatchNPCAttributes(npc)
	if not npc or not npc:IsA("Model") then return end
	local attrConn = npc:GetAttributeChangedSignal("AtDesk"):Connect(function()
		local val = npc:GetAttribute("AtDesk")
		if tostring(val) == "true" then
			self:SetupNPC(npc)
		end
	end)
end

return NPCManager
