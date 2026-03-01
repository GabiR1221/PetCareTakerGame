local ShowerDryerManager = {}
local Players = game:GetService("Players")

function ShowerDryerManager:Initialize(stateTable, carryingTable, playersService, petMovement)
	self.petState = stateTable or {}
	self.carryingPetByUserId = carryingTable or {}
	self.Players = playersService
	self.PetMovement = petMovement

	self.showerConnected = {}
	self.dryConnected = {}

	-- Load dependencies
	self.PetAttachmentManager = require(script.Parent.PetAttachmentManager)
	self.PetStateManager = require(script.Parent.PetStateManager)
	self.TycoonUtils = require(script.Parent.TycoonUtils)
end

function ShowerDryerManager:ConnectShowerPrompt(showerPart)
	if not showerPart or not showerPart:IsA("BasePart") then return end
	if self.showerConnected[showerPart] then return end

	local prompt = showerPart:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Use Shower"
		prompt.HoldDuration = 0
		prompt.ObjectText = "Shower"
		prompt.MaxActivationDistance = 6
		prompt.RequiresLineOfSight = false
		prompt.Parent = showerPart
	end

	local conn = prompt.Triggered:Connect(function(player)
		print(("[PetManager] Shower prompt triggered by %s (UserId=%s) on part %s"):format(
			tostring(player.Name), tostring(player.UserId), tostring(showerPart:GetFullName())))

		-- Find tycoon model
		local tycoonModel = nil
		local current = showerPart.Parent
		while current do
			if current:IsA("Folder") then
				local essDirect = current:FindFirstChild("Essentials")
				if essDirect then
					local desk = self.TycoonUtils:FindDeskInEssentials(essDirect)
					if desk then
						tycoonModel = current
						print(("[PetManager] Shower: ancestor climb found model %s"):format(tostring(tycoonModel:GetFullName())))
						break
					end
				end
			end
			current = current.Parent
		end

		if not tycoonModel then
			local resolvedModel, resolvedDesk = self.TycoonUtils:ResolveModelWithDeskFromInstance(showerPart)
			if resolvedModel then
				tycoonModel = resolvedModel
				print(("[PetManager] Shower: resolved via resolveModelWithDeskFromInstance -> %s"):format(tostring(tycoonModel:GetFullName())))
			end
		end

		if tycoonModel == workspace then tycoonModel = nil end

		if not tycoonModel then
			local byOwner, _ = self.TycoonUtils:FindTycoonByOwnerIdWithDesk(player.UserId)
			if byOwner then
				tycoonModel = byOwner
				print(("[PetManager] Shower: resolved via findTycoonByOwnerIdWithDesk -> %s"):format(tostring(tycoonModel:GetFullName())))
			end
		end

		-- Validate owner
		local ownerMatch = false
		if tycoonModel then
			local ownerAttr = tycoonModel:GetAttribute("OwnerId") or tycoonModel:GetAttribute("Owner") or tycoonModel:GetAttribute("OwnerUserId")
			if ownerAttr and tostring(ownerAttr) == tostring(player.UserId) then
				ownerMatch = true
				print(("[PetManager] Shower: matched owner via attribute (value=%s)"):format(tostring(ownerAttr)))
			else
				local candidateNames = {"OwnerId", "Owner", "OwnerUserId"}
				for _, nm in ipairs(candidateNames) do
					local child = tycoonModel:FindFirstChild(nm)
					if child and child.Value and tostring(child.Value) == tostring(player.UserId) then
						ownerMatch = true
						print(("[PetManager] Shower: matched owner via child '%s' (value=%s)"):format(nm, tostring(child.Value)))
						break
					end
				end
			end
		end

		print(("[PetManager] Shower ownerMatch=%s (tycoonModel=%s)"):format(tostring(ownerMatch), tostring(tycoonModel and tycoonModel.Name or "nil")))
		if not ownerMatch then
			print(("[PetManager] Shower: owner check failed for player %s on part %s"):format(tostring(player.Name), tostring(showerPart:GetFullName())))
			return
		end

		-- Ensure player is carrying a pet
		local pet = self.carryingPetByUserId[player.UserId]
		if not pet then
			print("[PetManager] Shower: player triggered while not carrying a pet.")
			return
		end

		self.PetAttachmentManager:SetModelPrimaryIfMissing(pet)
		if not pet.PrimaryPart then
			warn("[PetManager] Shower: pet has no PrimaryPart, aborting.")
			return
		end

		-- Check dirtiness threshold
		self.petState[pet] = self.petState[pet] or {}
		local dirt = tonumber(self.petState[pet].dirtiness) or 0
		if dirt < 10 then
			if prompt and prompt:IsA("ProximityPrompt") then
				local oldObj = prompt.ObjectText
				pcall(function() prompt.ObjectText = "Too Clean" end)
				task.delay(1.5, function()
					if prompt and prompt.Parent then pcall(function() prompt.ObjectText = oldObj end) end
				end)
			end
			return
		end

		-- Remove welds and detach from player
		self.PetAttachmentManager:ClearDirectModelWelds(pet)
		self.PetAttachmentManager:ClearWeldsOnPart(pet.PrimaryPart)
		self.PetAttachmentManager:DetachPetFromPlayer(pet)

		-- Attach to shower
		local ok = self.PetAttachmentManager:AttachPetToPart(pet, showerPart)
		if not ok then
			warn("[PetManager] Shower: failed to attach pet to shower part.")
			return
		end

		-- Mark as on shower
		self.petState[pet] = self.petState[pet] or {}
		self.petState[pet].location = "shower"
		self.petState[pet].shower = showerPart
		self.PetStateManager:SendStateToOwner(pet)

		-- Hold for SHOWER_HOLD_TIME (defined in main script)
		local SHOWER_HOLD_TIME = 3
		task.delay(SHOWER_HOLD_TIME, function()
			if not pet or not pet.PrimaryPart or not showerPart then return end
			self.PetAttachmentManager:ClearWeldsOnPart(pet.PrimaryPart)
			self.PetMovement.StopWandering(pet)

			-- Award XP
			self.PetStateManager:AddXP(pet, 20) -- SHOWER_XP

			-- Reset dirtiness and set wetness
			self.petState[pet] = self.petState[pet] or {}
			self.petState[pet].dirtiness = 0
			self.petState[pet].wetness = 100
			self.petState[pet].showered = true

			-- Try to reattach to owner
			local state = self.petState[pet] or {}
			local ownerId = state.ownerUserId
			local reattached = false

			if ownerId then
				local owner = self.Players:GetPlayerByUserId(ownerId)
				if owner and owner.Character and owner.Character.PrimaryPart and not self.carryingPetByUserId[ownerId] then
					local ok2, err = pcall(function() 
						self.PetAttachmentManager:AttachPetToPlayer(pet, owner) 
					end)
					if ok2 then
						self.petState[pet].location = "player"
						self.petState[pet].shower = showerPart
						reattached = true
						self.PetStateManager:SendStateToOwner(pet)
					else
						warn(("[PetManager] Shower: reattach attempt failed: %s"):format(tostring(err)))
					end
				end
			end

			-- Fallback: release to world
			if not reattached then
				pet:SetPrimaryPartCFrame(showerPart.CFrame * CFrame.new(0, showerPart.Size.Y/2 + 1, 0))
				pet.Parent = workspace
				self.petState[pet] = self.petState[pet] or {}
				self.petState[pet].location = "free"
				self.petState[pet].shower = showerPart
				self.PetStateManager:SendStateToOwner(pet)
			end
		end)
	end)

	self.showerConnected[showerPart] = conn
end

function ShowerDryerManager:ConnectDryPrompt(dryPart)
	if not dryPart or not dryPart:IsA("BasePart") then return end
	if self.dryConnected[dryPart] then return end

	local prompt = dryPart:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Dry Pet"
		prompt.HoldDuration = 0
		prompt.ObjectText = "DryStation"
		prompt.MaxActivationDistance = 6
		prompt.RequiresLineOfSight = false
		prompt.Parent = dryPart
	end

	local conn = prompt.Triggered:Connect(function(player)
		print(("[PetManager] Dry prompt triggered by %s (UserId=%s) on part %s"):format(
			tostring(player.Name), tostring(player.UserId), tostring(dryPart:GetFullName())))

		-- Find tycoon model
		local tycoonModel = nil
		local current = dryPart.Parent
		while current do
			if current:IsA("Folder") then
				local essDirect = current:FindFirstChild("Essentials")
				if essDirect then
					local desk = self.TycoonUtils:FindDeskInEssentials(essDirect)
					if desk then
						tycoonModel = current
						print(("[PetManager] Dry: ancestor climb found model %s"):format(tostring(tycoonModel:GetFullName())))
						break
					end
				end
			end
			current = current.Parent
		end

		if not tycoonModel then
			local resolvedModel, resolvedDesk = self.TycoonUtils:ResolveModelWithDeskFromInstance(dryPart)
			if resolvedModel then
				tycoonModel = resolvedModel
				print(("[PetManager] Dry: resolved via resolveModelWithDeskFromInstance -> %s"):format(tostring(tycoonModel:GetFullName())))
			end
		end

		if tycoonModel == workspace then tycoonModel = nil end

		if not tycoonModel then
			local byOwner, _ = self.TycoonUtils:FindTycoonByOwnerIdWithDesk(player.UserId)
			if byOwner then
				tycoonModel = byOwner
				print(("[PetManager] Dry: resolved via findTycoonByOwnerIdWithDesk -> %s"):format(tostring(tycoonModel:GetFullName())))
			end
		end

		-- Validate owner
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
			print(("[PetManager] Dry: owner check failed for player %s on part %s"):format(tostring(player.Name), tostring(dryPart:GetFullName())))
			return
		end

		-- Ensure player is carrying a pet
		local pet = self.carryingPetByUserId[player.UserId]
		if not pet then return end

		self.PetAttachmentManager:SetModelPrimaryIfMissing(pet)
		if not pet.PrimaryPart then return end

		-- Check wetness threshold
		self.petState[pet] = self.petState[pet] or {}
		local wet = tonumber(self.petState[pet].wetness) or 0
		if wet < 10 then
			if prompt and prompt:IsA("ProximityPrompt") then
				local oldObj = prompt.ObjectText
				pcall(function() prompt.ObjectText = "Not Wet" end)
				task.delay(1.5, function()
					if prompt and prompt.Parent then pcall(function() prompt.ObjectText = oldObj end) end
				end)
			end
			return
		end

		-- Detach from player and attach to dry station
		self.PetAttachmentManager:ClearDirectModelWelds(pet)
		self.PetAttachmentManager:ClearWeldsOnPart(pet.PrimaryPart)
		self.PetAttachmentManager:DetachPetFromPlayer(pet)

		local ok = self.PetAttachmentManager:AttachPetToPart(pet, dryPart)
		if not ok then return end

		-- Mark as on dry station
		self.petState[pet] = self.petState[pet] or {}
		self.petState[pet].location = "dry"
		self.petState[pet].dryStation = dryPart
		self.PetStateManager:SendStateToOwner(pet)

		-- Hold for DRY_HOLD_TIME
		local DRY_HOLD_TIME = 3
		task.delay(DRY_HOLD_TIME, function()
			if not pet or not pet.PrimaryPart or not dryPart then return end
			self.PetAttachmentManager:ClearWeldsOnPart(pet.PrimaryPart)
			self.PetMovement.StopWandering(pet)

			-- Award dry XP
			self.PetStateManager:AddXP(pet, 12) -- DRY_XP

			-- Set wetness to 0 and mark dried flag
			self.petState[pet] = self.petState[pet] or {}
			self.petState[pet].wetness = 0
			self.petState[pet].dried = true

			-- Try to reattach to owner
			local state = self.petState[pet] or {}
			local ownerId = state.ownerUserId
			local reattached = false
			if ownerId then
				local owner = self.Players:GetPlayerByUserId(ownerId)
				if owner and owner.Character and owner.Character.PrimaryPart and not self.carryingPetByUserId[ownerId] then
					local ok2, err = pcall(function() 
						self.PetAttachmentManager:AttachPetToPlayer(pet, owner, { resetFlags = false }) 
					end)
					if ok2 then
						self.petState[pet].location = "player"
						self.petState[pet].dryStation = dryPart
						reattached = true
						self.PetStateManager:SendStateToOwner(pet)
					end
				end
			end

			if not reattached then
				pet:SetPrimaryPartCFrame(dryPart.CFrame * CFrame.new(0, dryPart.Size.Y/2 + 1, 0))
				pet.Parent = workspace
				self.petState[pet] = self.petState[pet] or {}
				self.petState[pet].location = "free"
				self.petState[pet].dryStation = dryPart
				self.PetStateManager:SendStateToOwner(pet)
			end
		end)
	end)

	self.dryConnected[dryPart] = conn
end

function ShowerDryerManager:ScanAndConnectAll()
	-- Scan for showers and dryers
	local possibleRoots = {}
	local tycoonRoot = workspace:FindFirstChild("Tycoon")
	if tycoonRoot then table.insert(possibleRoots, tycoonRoot) end
	local topTycoons = workspace:FindFirstChild("Tycoons")
	if topTycoons then table.insert(possibleRoots, topTycoons) end

	for _, root in ipairs(possibleRoots) do
		for _, tycoon in ipairs(root:GetDescendants()) do
			if tycoon:IsA("BasePart") then
				if tycoon.Name == "Shower" then
					self:ConnectShowerPrompt(tycoon)
				elseif tycoon.Name == "DryPart" then
					self:ConnectDryPrompt(tycoon)
				end
			end
		end
	end

	-- Fallback scan
	for _, model in ipairs(workspace:GetDescendants()) do
		if model:IsA("Model") then
			local ess = model:FindFirstChild("Essentials")
			if ess then
				local shower = ess:FindFirstChild("Shower")
				if shower and shower:IsA("BasePart") then
					self:ConnectShowerPrompt(shower)
				end
				local dryp = ess:FindFirstChild("DryPart")
				if dryp and dryp:IsA("BasePart") then
					self:ConnectDryPrompt(dryp)
				end
			end
		end
	end
end

return ShowerDryerManager
