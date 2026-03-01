local PetGroundManager = {}

function PetGroundManager:Initialize(stateTable, carryingTable, playersService, petMovement, 
	groundConnections, xpTasks, dirtinessTasks, pickupConns)
	self.petState = stateTable or {}
	self.carryingPetByUserId = carryingTable or {}
	self.Players = playersService
	self.PetMovement = petMovement
	self.petGroundConnected = groundConnections or {}
	self.petGroundXPTasks = xpTasks or {}
	self.petGroundDirtinessTasks = dirtinessTasks or {}
	self.petPickupPromptConns = pickupConns or {}

	-- Load dependencies
	self.PetAttachmentManager = require(script.Parent.PetAttachmentManager)
	self.PetStateManager = require(script.Parent.PetStateManager)
	self.PromptManager = require(script.Parent.PromptManager)
	self.PetRigManager = require(script.Parent.PetRigManager)
	self.PetAnimationManager = require(script.Parent.PetAnimationManager)
end

function PetGroundManager:StartPetgroundXP(petModel)
	if not petModel then return end
	if self.petGroundXPTasks[petModel] then return end

	local PETGROUND_XP_PER_SEC = 5
	self.petGroundXPTasks[petModel] = true

	task.spawn(function()
		while petModel and petModel.Parent and self.petState[petModel] and 
			self.petState[petModel].location == "petground" do
			self.PetStateManager:AddXP(petModel, PETGROUND_XP_PER_SEC)
			task.wait(1)
		end
		self.petGroundXPTasks[petModel] = nil
	end)
end

function PetGroundManager:StopPetgroundXP(petModel)
	self.petGroundXPTasks[petModel] = nil
end

function PetGroundManager:StartPetgroundDirtiness(petModel)
	if not petModel then return end
	if self.petGroundDirtinessTasks[petModel] then return end

	self.petGroundDirtinessTasks[petModel] = true

	task.spawn(function()
		while petModel and petModel.Parent and self.petState[petModel] and 
			self.petState[petModel].location == "petground" do
			task.wait(5) -- every 5 seconds
			if not self.petState[petModel] then break end
			self.petState[petModel].dirtiness = math.clamp((self.petState[petModel].dirtiness or 0) + 2, 0, 100)
			self.PetStateManager:SendStateToOwner(petModel)
		end
		self.petGroundDirtinessTasks[petModel] = nil
	end)
end

function PetGroundManager:StopPetgroundDirtiness(petModel)
	self.petGroundDirtinessTasks[petModel] = nil
end

function PetGroundManager:AttachPetToPartRandom(petModel, part)
	if not petModel or not part or not part:IsA("BasePart") then return false end
	self.PetAttachmentManager:SetModelPrimaryIfMissing(petModel)
	local ppart = petModel.PrimaryPart
	if not ppart then return false end

	-- Clear previous welds
	self.PetAttachmentManager:ClearWeldsOnPart(ppart)
	petModel.Parent = workspace

	-- Compute random offset
	local halfX = math.max(0.01, (part.Size.X / 2) - (ppart.Size.X / 2))
	local halfZ = math.max(0.01, (part.Size.Z / 2) - (ppart.Size.Z / 2))
	local rx = (math.random() * 2 - 1) * halfX
	local rz = (math.random() * 2 - 1) * halfZ

	-- Place pet on top of part
	local yOff = (part.Size.Y / 2) + (ppart.Size.Y / 2)
	petModel:SetPrimaryPartCFrame(part.CFrame * CFrame.new(rx, yOff, rz))
	ppart.CanCollide = false

	-- Clear carrying map
	if self.petState[petModel] and self.petState[petModel].ownerUserId then
		self.carryingPetByUserId[self.petState[petModel].ownerUserId] = nil
	end

	self.petState[petModel] = self.petState[petModel] or {}
	self.petState[petModel].npc = nil
	self.PetMovement.StopWandering(petModel)

	return true
end

function PetGroundManager:ConnectPetGround(petGroundModel)
	if not petGroundModel or not petGroundModel:IsA("Model") then return end
	if self.petGroundConnected[petGroundModel] then return end

	-- Find hitbox part
	local hitbox = petGroundModel:FindFirstChild("Hitbox")
	if not hitbox or not hitbox:IsA("BasePart") then
		hitbox = petGroundModel.PrimaryPart
	end
	if not hitbox or not hitbox:IsA("BasePart") then
		for _, d in ipairs(petGroundModel:GetDescendants()) do
			if d:IsA("BasePart") then
				hitbox = d
				break
			end
		end
	end
	if not hitbox then return end

	-- Create prompts
	local helper, prompt = self.PromptManager:CreatePickupPromptForContainer(petGroundModel, "Pick Up Pet")
	local depositPrompt = hitbox:FindFirstChildWhichIsA("ProximityPrompt")
	if not depositPrompt then
		depositPrompt = Instance.new("ProximityPrompt")
		depositPrompt.Name = "PetGroundDepositPrompt"
		depositPrompt.ActionText = "Place Pet"
		depositPrompt.ObjectText = "PetGround"
		depositPrompt.MaxActivationDistance = 6
		depositPrompt.HoldDuration = 0
		depositPrompt.RequiresLineOfSight = false
		depositPrompt.Parent = hitbox
	end

	pcall(function() hitbox.Anchored = true end)

	-- Touch debounce
	local touchDebounce = {}

	local function doDepositByPlayer(player)
		if not player then return end
		local uid = player.UserId
		if touchDebounce[uid] then return end
		touchDebounce[uid] = true
		task.delay(0.5, function() touchDebounce[uid] = nil end)

		local carriedPet = self.carryingPetByUserId[player.UserId]
		if not carriedPet then return end

		-- Validate
		self.PetAttachmentManager:SetModelPrimaryIfMissing(petGroundModel)
		local attachPart = petGroundModel.PrimaryPart or hitbox
		if not attachPart or not attachPart:IsA("BasePart") then
			print("[PetManager] PetGround deposit: no valid attach part found for petground.")
			return
		end

		-- Detach from player
		self.PetAttachmentManager:ClearDirectModelWelds(carriedPet)
		self.PetAttachmentManager:ClearWeldsOnPart(carriedPet.PrimaryPart)
		self.PetAttachmentManager:DetachPetFromPlayer(carriedPet)

		-- Attach to petGround
		local ok = self:AttachPetToPartRandom(carriedPet, attachPart)
		if ok then
			self.petState[carriedPet] = self.petState[carriedPet] or {}
			self.petState[carriedPet].location = "petground"
			self.petState[carriedPet].petground = petGroundModel

			-- Re-create rig
			pcall(function()
				self.PetRigManager:EnsurePetRig(carriedPet)
				self.PetAnimationManager:SetupAnimatorForPet(carriedPet)
				if carriedPet.PrimaryPart then
					pcall(function() carriedPet.PrimaryPart.Anchored = false end)
					pcall(function() carriedPet.PrimaryPart.Massless = true end)
				end
			end)

			-- Start XP and dirtiness tasks
			self:StartPetgroundXP(carriedPet)
			self:StartPetgroundDirtiness(carriedPet)

			-- Start wandering
			local attachPart = petGroundModel.PrimaryPart or hitbox
			if attachPart and attachPart:IsA("BasePart") then
				self.PetMovement.StartWandering(carriedPet, attachPart.Position)
			else
				self.PetMovement.StartWandering(carriedPet)
			end

			-- Create per-pet pickup helper
			local existing = carriedPet:FindFirstChild("PetPickupPart")
			if existing then
				pcall(function() existing:Destroy() end)
			end

			local helper = Instance.new("Part")
			helper.Name = "PetPickupPart"
			helper.Size = Vector3.new(1,1,1)
			helper.Anchored = false
			helper.Transparency = 1
			helper.CanCollide = false
			helper.Parent = carriedPet

			local pp = carriedPet.PrimaryPart
			if pp then
				helper.CFrame = pp.CFrame * CFrame.new(0, pp.Size.Y/2 + 0.5, 0)
				local w = Instance.new("WeldConstraint")
				w.Part0 = helper
				w.Part1 = pp
				w.Parent = helper
			end

			local p = Instance.new("ProximityPrompt")
			p.Name = "PetPrompt"
			p.ActionText = "Pick Up Pet"
			p.ObjectText = "Pet"
			p.RequiresLineOfSight = false
			p.MaxActivationDistance = 6
			p.HoldDuration = 0
			p.Parent = helper

			local conn = p.Triggered:Connect(function(requestingPlayer)
				local st = self.petState[carriedPet]
				if not st then return end
				if tostring(st.ownerUserId) ~= tostring(requestingPlayer.UserId) then return end

				-- Stop tasks
				self:StopPetgroundXP(carriedPet)
				self:StopPetgroundDirtiness(carriedPet)
				self.PetMovement.StopWandering(carriedPet)

				-- Clear welds
				if carriedPet.PrimaryPart then 
					self.PetAttachmentManager:ClearWeldsOnPart(carriedPet.PrimaryPart) 
				end

				if requestingPlayer and requestingPlayer.Character and 
					requestingPlayer.Character.PrimaryPart and not self.carryingPetByUserId[requestingPlayer.UserId] then
					local ok, err = pcall(function() 
						self.PetAttachmentManager:AttachPetToPlayer(carriedPet, requestingPlayer, { resetFlags = false }) 
					end)
					if ok then
						self.petState[carriedPet].location = "player"
						self.petState[carriedPet].petground = nil
						pcall(function() helper:Destroy() end)
						if self.petPickupPromptConns[carriedPet] then
							pcall(function() self.petPickupPromptConns[carriedPet]:Disconnect() end)
							self.petPickupPromptConns[carriedPet] = nil
						end
						return
					else
						warn("[PetManager] PetGround pickup reattach failed:", err)
					end
				end

				-- Fallback
				local attachPart2 = petGroundModel.PrimaryPart or hitbox
				if attachPart2 and carriedPet.SetPrimaryPartCFrame then
					carriedPet:SetPrimaryPartCFrame(attachPart2.CFrame * CFrame.new(0, (attachPart2.Size.Y/2) + 1, 0))
				end
				carriedPet.Parent = workspace
				self.petState[carriedPet].location = "free"
				self.petState[carriedPet].petground = nil

				pcall(function() helper:Destroy() end)
				if self.petPickupPromptConns[carriedPet] then
					pcall(function() self.petPickupPromptConns[carriedPet]:Disconnect() end)
					self.petPickupPromptConns[carriedPet] = nil
				end
			end)

			self.petPickupPromptConns[carriedPet] = conn
			self.PetStateManager:SendStateToOwner(carriedPet)

			print(("[PetManager] Pet %s placed on PetGround %s by %s (deposit)"):format(
				tostring(carriedPet.Name), tostring(petGroundModel:GetFullName()), tostring(player.Name)))
		else
			print(("[PetManager] PetGround deposit: attachPetToPartRandom returned false for pet %s"):format(
				tostring(carriedPet and carriedPet.Name)))
		end
	end

	-- Touch handler
	local touchConn = hitbox.Touched:Connect(function(hit)
		if not hit or not hit.Parent then return end
		local char = hit.Parent
		local player = self.Players:GetPlayerFromCharacter(char)
		if not player then return end
		pcall(function() doDepositByPlayer(player) end)
	end)

	-- Deposit prompt handler
	local depositConn = depositPrompt.Triggered:Connect(function(player)
		pcall(function() doDepositByPlayer(player) end)
	end)

	-- Pickup prompt handler
	local promptConn = nil
	if prompt then
		promptConn = prompt.Triggered:Connect(function(player)
			-- Find pet on this petGround
			local foundPet = nil
			for _, child in ipairs(petGroundModel:GetDescendants()) do
				if child.Name == "Pet" and child:IsA("Model") then
					foundPet = child
					break
				end
			end
			if not foundPet then
				for pet, st in pairs(self.petState) do
					if st and st.location == "petground" and st.petground == petGroundModel then
						foundPet = pet
						break
					end
				end
			end
			if not foundPet then return end

			local st = self.petState[foundPet]
			if not st then return end
			if tostring(st.ownerUserId) ~= tostring(player.UserId) then return end

			-- Clear welds and reattach to player
			if foundPet.PrimaryPart then 
				self.PetAttachmentManager:ClearWeldsOnPart(foundPet.PrimaryPart) 
			end
			self:StopPetgroundXP(foundPet)
			self:StopPetgroundDirtiness(foundPet)

			if player and player.Character and player.Character.PrimaryPart and not self.carryingPetByUserId[player.UserId] then
				local ok, err = pcall(function() 
					self.PetAttachmentManager:AttachPetToPlayer(foundPet, player, { resetFlags = false }) 
				end)
				if ok then
					self.petState[foundPet].location = "player"
					self.petState[foundPet].petground = nil
					return
				else
					warn("[PetManager] PetGround pickup reattach failed:", err)
				end
			end

			-- Fallback
			local attachPart = petGroundModel.PrimaryPart or hitbox
			if attachPart and foundPet.SetPrimaryPartCFrame then
				foundPet:SetPrimaryPartCFrame(attachPart.CFrame * CFrame.new(0, (attachPart.Size.Y/2) + 1, 0))
			end
			foundPet.Parent = workspace
			self.petState[foundPet].location = "free"
			self.petState[foundPet].petground = nil
		end)
	end

	self.petGroundConnected[petGroundModel] = { 
		touchConn = touchConn, 
		depositConn = depositConn, 
		promptConn = promptConn 
	}
end

function PetGroundManager:ScanAndConnectAll()
	-- Look for PetGround models
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") and inst.Name == "PetGround" then
			if not self.petGroundConnected[inst] then
				self:ConnectPetGround(inst)
				print(("[PetManager] scanConnectAllShowers: connected PetGround model at %s"):format(tostring(inst:GetFullName())))
			end
		end
	end

	-- Also check in Essentials
	for _, model in ipairs(workspace:GetDescendants()) do
		if model:IsA("Model") then
			local ess = model:FindFirstChild("Essentials")
			if ess then
				local petgroundModel = ess:FindFirstChild("PetGround")
				if petgroundModel and petgroundModel:IsA("Model") then
					self:ConnectPetGround(petgroundModel)
				end
			end
		end
	end
end

return PetGroundManager
