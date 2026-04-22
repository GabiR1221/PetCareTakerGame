local AccessoryManager = {}
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

function AccessoryManager:Initialize(stateTable, carryingTable, playersService, accessoryEvent, serverStorage)
	self.petState = stateTable or {}
	self.carryingPetByUserId = carryingTable or {}
	self.Players = playersService
	self.accessoryEvent = accessoryEvent
	self.ServerStorage = serverStorage

	self.accessoryConnected = {}

	-- Load dependencies
	self.PetAttachmentManager = require(script.Parent.PetAttachmentManager)
	self.PetStateManager = require(script.Parent.PetStateManager)
	self.PetRigManager = require(script.Parent.PetRigManager)
end

function AccessoryManager:_getOwnedAccessoryNamesForPlayer(player)
	local owned = {}
	if not player then return owned end
	local data = player:FindFirstChild("Data")
	local accessoriesFolder = data and data:FindFirstChild("Accessories")
	if not accessoriesFolder then return owned end

	for _, itemFolder in ipairs(accessoriesFolder:GetChildren()) do
		if itemFolder:IsA("Folder") then
			local itemType = itemFolder:FindFirstChild("ItemType")
			if not itemType or tostring(itemType.Value) == "Accessory" then
				local itemNameValue = itemFolder:FindFirstChild("ItemName")
				local itemName = itemNameValue and tostring(itemNameValue.Value) or ""
				if itemName ~= "" then
					owned[itemName] = true
				end
			end
		end
	end

	return owned
end

function AccessoryManager:_syncAccessoryLegacyState(state)
	state.accessories = state.accessories or { A = false, B = false }
	state.accessorySlots = state.accessorySlots or { A = nil, B = nil }
	state.accessories.A = state.accessorySlots.A ~= nil
	state.accessories.B = state.accessorySlots.B ~= nil
end

function AccessoryManager:_buildEquippedPayload(state)
	if not state then
		return { A = nil, B = nil }
	end
	self:_syncAccessoryLegacyState(state)
	return {
		A = state.accessorySlots.A,
		B = state.accessorySlots.B,
	}
end

function AccessoryManager:_toggleNamedAccessoryOnPet(pet, state, accessoryName)
	if not pet or not state or type(accessoryName) ~= "string" or accessoryName == "" then
		return false
	end

	self:_syncAccessoryLegacyState(state)
	local slots = state.accessorySlots

	if slots.A == accessoryName then
		if self:RemoveAccessoryFromPet(pet, accessoryName) then
			slots.A = nil
		end
		self:_syncAccessoryLegacyState(state)
		return true
	end

	if slots.B == accessoryName then
		if self:RemoveAccessoryFromPet(pet, accessoryName) then
			slots.B = nil
		end
		self:_syncAccessoryLegacyState(state)
		return true
	end

	local attachKey = (slots.A == nil and "A") or (slots.B == nil and "B") or nil
	if not attachKey then
		return false
	end

	local accessoryStorage = self.ServerStorage and self.ServerStorage:FindFirstChild("PetAccessories")
	local accessoryModelTemplate = accessoryStorage and accessoryStorage:FindFirstChild(accessoryName) or nil
	if not accessoryModelTemplate then
		local replicatedAccessories = ReplicatedStorage:FindFirstChild("Accessories")
		accessoryModelTemplate = replicatedAccessories and replicatedAccessories:FindFirstChild(accessoryName) or nil
	end
	
	if not accessoryModelTemplate then
		return false
	end

	local clone = accessoryModelTemplate:Clone()
	clone.Name = accessoryName
	local attachPoint = (attachKey == "A") and "AccessoryAttach1" or "AccessoryAttach2"
	local ok = self:AttachAccessoryToPetModel(pet, clone, attachPoint)
	if not ok then
		pcall(function() clone:Destroy() end)
		return false
	end

	slots[attachKey] = accessoryName
	self:_syncAccessoryLegacyState(state)
	return true
end

function AccessoryManager:ConnectAccessoryPrompt(tablePart)
	if not tablePart or not tablePart:IsA("BasePart") then return end
	if self.accessoryConnected[tablePart] then return end

	local prompt = tablePart:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Use Accessory Table"
		prompt.HoldDuration = 0
		prompt.ObjectText = "AccessoryTable"
		prompt.MaxActivationDistance = 6
		prompt.RequiresLineOfSight = false
		prompt.Parent = tablePart
	end

	local conn = prompt.Triggered:Connect(function(player)
		print(("[PetManager] Accessory prompt triggered by %s on %s"):format(player.Name, tablePart:GetFullName()))

		-- Find tycoon model using the same logic as the old script
		local tycoonModel = nil

		-- Method 1: Climb ancestors looking for Folder with Essentials
		local current = tablePart.Parent
		while current do
			if current:IsA("Folder") then
				local essDirect = current:FindFirstChild("Essentials")
				if essDirect then
					-- Use the TycoonUtils module to find desk
					local TycoonUtils = require(script.Parent.TycoonUtils)
					local desk = TycoonUtils:FindDeskInEssentials(essDirect)
					if desk then
						tycoonModel = current
						print(("[PetManager] Accessory: Found tycoon via Essentials in parent: %s"):format(tostring(tycoonModel.Name)))
						break
					end
				end
			end
			current = current.Parent
		end

		-- Method 2: Use resolveModelWithDeskFromInstance (same as old script)
		if not tycoonModel then
			local TycoonUtils = require(script.Parent.TycoonUtils)
			local resolvedModel, resolvedDesk = TycoonUtils:ResolveModelWithDeskFromInstance(tablePart)
			if resolvedModel then
				tycoonModel = resolvedModel
				print(("[PetManager] Accessory: Found tycoon via resolve: %s"):format(tostring(tycoonModel.Name)))
			end
		end

		-- Method 3: Find by owner ID
		if not tycoonModel then
			local TycoonUtils = require(script.Parent.TycoonUtils)
			local byOwner,_ = TycoonUtils:FindTycoonByOwnerIdWithDesk(player.UserId)
			if byOwner then
				tycoonModel = byOwner
				print(("[PetManager] Accessory: Found tycoon by owner ID: %s"):format(tostring(tycoonModel.Name)))
			end
		end

		-- If no tycoon model, we still proceed (like old script)
		if not tycoonModel then
			print("[PetManager] Accessory: No tycoon model found, proceeding with pet check only")
		end

		-- Owner check (same logic as old script)
		local ownerMatch = true  -- Default to true
		if tycoonModel then
			ownerMatch = false
			local ownerAttr = tycoonModel:GetAttribute("OwnerId") or tycoonModel:GetAttribute("Owner") or tycoonModel:GetAttribute("OwnerUserId")
			if ownerAttr and tostring(ownerAttr) == tostring(player.UserId) then
				ownerMatch = true
			else
				local candidateNames = {"OwnerId","Owner","OwnerUserId"}
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
			print("[PetManager] Accessory: Owner check failed")
			return
		end

		-- Must be carrying a pet
		local pet = self.carryingPetByUserId[player.UserId]
		if not pet then
			print("[PetManager] Accessory: Player not carrying a pet")
			return
		end

		-- Ensure PrimaryPart
		self.PetAttachmentManager:SetModelPrimaryIfMissing(pet)
		if not pet.PrimaryPart then
			warn("[PetManager] Accessory: Pet has no PrimaryPart")
			return
		end

		-- Detach from player and attach to table (EXACTLY like old script)
		self.PetAttachmentManager:ClearDirectModelWelds(pet)
		self.PetAttachmentManager:ClearWeldsOnPart(pet.PrimaryPart)
		self.PetAttachmentManager:DetachPetFromPlayer(pet)

		local ok = self.PetAttachmentManager:AttachPetToPart(pet, tablePart)
		if not ok then
			warn("[PetManager] Accessory: Failed to attach pet to table")
			return
		end

		self.carryingPetByUserId[player.UserId] = nil

		-- Update state (EXACTLY like old script)
		self.petState[pet] = self.petState[pet] or {}
		self.petState[pet].location = "accessory"
		self.petState[pet].accessoryTable = tablePart
		self.petState[pet].accessories = self.petState[pet].accessories or {A = false, B = false}
		self.petState[pet].accessorySlots = self.petState[pet].accessorySlots or {A = nil, B = nil}
		self:_syncAccessoryLegacyState(self.petState[pet])

		-- Fire client UI (EXACTLY like old script)
		print(("[PetManager] Accessory: Opening UI for player %s, pet %s"):format(player.Name, pet.Name))
		local ownedMap = self:_getOwnedAccessoryNamesForPlayer(player)
		local ownedList = {}
		for accessoryName in pairs(ownedMap) do
			table.insert(ownedList, accessoryName)
		end
		table.sort(ownedList)
		self.accessoryEvent:FireClient(player, "OpenAccessoryUI", tablePart, pet, {
			ownedAccessories = ownedList,
			equipped = self:_buildEquippedPayload(self.petState[pet]),
		})
	end)

	self.accessoryConnected[tablePart] = conn
end

function AccessoryManager:ScanAndConnectAll()

	-- Method 1: Scan through common tycoon roots (same as old script)
	local possibleRoots = {}
	local tycoonRoot = workspace:FindFirstChild("Tycoon")
	if tycoonRoot then table.insert(possibleRoots, tycoonRoot) end
	local topTycoons = workspace:FindFirstChild("Tycoons")
	if topTycoons then table.insert(possibleRoots, topTycoons) end

	for _, root in ipairs(possibleRoots) do
		for _, tycoon in ipairs(root:GetDescendants()) do
			if tycoon:IsA("BasePart") and tycoon.Name == "AccessoryTable" then
				if not self.accessoryConnected[tycoon] then
					self:ConnectAccessoryPrompt(tycoon)
					print(("[PetManager] Connected accessory table in root: %s"):format(tycoon:GetFullName()))
				end
			end
		end
	end

	-- Method 2: Fallback - scan workspace for Essentials folders (same as old script)
	for _, model in ipairs(workspace:GetDescendants()) do
		if model:IsA("Model") then
			local ess = model:FindFirstChild("Essentials")
			if ess then
				local accessory = ess:FindFirstChild("AccessoryTable")
				if accessory and accessory:IsA("BasePart") then
					if not self.accessoryConnected[accessory] then
						self:ConnectAccessoryPrompt(accessory)
						print(("[PetManager] Connected accessory table in Essentials: %s"):format(accessory:GetFullName()))
					end
				end
			end
		end
	end
end

function AccessoryManager:AttachAccessoryToPetModel(petModel, accessoryModel, attachPointName)
	if not petModel or not accessoryModel then return false end
	self.PetAttachmentManager:SetModelPrimaryIfMissing(petModel)
	self.PetAttachmentManager:SetModelPrimaryIfMissing(accessoryModel)

	local ppart = petModel.PrimaryPart
	local aPart = accessoryModel.PrimaryPart
	if not aPart then return false end

	local attachToPart = nil
	local targetCFrame = nil
	local namedAttachment = petModel:FindFirstChild("AccessoryAttachment", true)
	if namedAttachment and namedAttachment:IsA("Attachment") and namedAttachment.Parent and namedAttachment.Parent:IsA("BasePart") then
		attachToPart = namedAttachment.Parent
		targetCFrame = namedAttachment.WorldCFrame
	else
		local attachTo = petModel:FindFirstChild(attachPointName)
		if attachTo and attachTo:IsA("BasePart") then
			attachToPart = attachTo
			targetCFrame = attachTo.CFrame
		else
			attachToPart = ppart
			targetCFrame = ppart.CFrame
		end
	end

	accessoryModel.Parent = petModel
	accessoryModel:SetPrimaryPartCFrame(targetCFrame)
	for _, bp in ipairs(accessoryModel:GetDescendants()) do
		if bp:IsA("BasePart") then
			bp.CanCollide = false
			bp.Massless = true
		end
	end

	-- Create weld constraint
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = aPart
	weld.Part1 = attachToPart
	weld.Parent = aPart

	return true
end

function AccessoryManager:RemoveAccessoryFromPet(petModel, accessoryName)
	if not petModel then return false end
	for _, child in ipairs(petModel:GetChildren()) do
		if child.Name == accessoryName then
			-- Remove any welds
			for _, weld in ipairs(child:GetDescendants()) do
				if weld:IsA("WeldConstraint") or weld:IsA("Weld") then
					weld:Destroy()
				end
			end
			child:Destroy()
			return true
		end
	end
	return false
end

function AccessoryManager:HandleAccessoryEvent(player, action, data)
	print(("[PetManager] Accessory event: %s from %s"):format(action, player.Name))

	if action == "ToggleAccessory" then
		local pet = data and data.pet
		local which = data and data.which
		local accessoryName = data and data.accessoryName
		if not pet then
			print("[PetManager] Accessory: Missing pet in ToggleAccessory")
			return
		end

		local state = self.petState[pet]
		if not state then
			print("[PetManager] Accessory: No state for pet")
			return
		end

		if tostring(state.ownerUserId) ~= tostring(player.UserId) then
			print("[PetManager] Accessory: Player not owner of pet")
			return
		end

		if state.location ~= "accessory" then
			print("[PetManager] Accessory: Pet not at accessory table")
			return
		end

		self:_syncAccessoryLegacyState(state)

		-- Find accessory model in ServerStorage
		if not self.ServerStorage then
			print("[PetManager] Accessory: No ServerStorage")
			return
		end

		local accessoryStorage = self.ServerStorage:FindFirstChild("PetAccessories")
		if not accessoryStorage then
			print("[PetManager] Accessory: No PetAccessories folder in ServerStorage")
			return
		end

		if not accessoryName and which then
			accessoryName = (which == "A") and "AccessoryA" or (which == "B") and "AccessoryB" or nil
		end
		if not accessoryName then
			print("[PetManager] Accessory: Invalid accessory request")
			return
		end

		local ownedMap = self:_getOwnedAccessoryNamesForPlayer(player)
		if not ownedMap[accessoryName] then
			print(("[PetManager] Accessory: %s does not own accessory '%s'"):format(player.Name, accessoryName))
			self.accessoryEvent:FireClient(player, "AccessoryToggleFailed", nil, pet, {
				reason = "NotOwned",
				equipped = self:_buildEquippedPayload(state),
			})
			return
		end

		local toggled = self:_toggleNamedAccessoryOnPet(pet, state, accessoryName)
		if not toggled then
			print(("[PetManager] Accessory: Failed toggling accessory %s"):format(accessoryName))
			self.accessoryEvent:FireClient(player, "AccessoryToggleFailed", nil, pet, {
				reason = "ToggleFailed",
				equipped = self:_buildEquippedPayload(state),
			})
			return
		end

		-- Send state update
		self.PetStateManager:SendStateToOwner(pet)
		self.accessoryEvent:FireClient(player, "AccessoryState", nil, pet, {
			equipped = self:_buildEquippedPayload(state),
		})

	elseif action == "ExitAccessory" then
		local pet = data and data.pet
		if not pet then
			print("[PetManager] Accessory: No pet in ExitAccessory")
			return
		end

		local state = self.petState[pet]
		if not state then
			print("[PetManager] Accessory: No state for pet in ExitAccessory")
			return
		end

		if tostring(state.ownerUserId) ~= tostring(player.UserId) then
			print("[PetManager] Accessory: Player not owner in ExitAccessory")
			return
		end

		if state.location ~= "accessory" then
			print("[PetManager] Accessory: Pet not at accessory table in ExitAccessory")
			return
		end

		-- Remove table attachment welds
		self.PetAttachmentManager:DetachPetFromPlayer(pet)
		self.PetAttachmentManager:ClearDirectModelWelds(pet)
		if pet.PrimaryPart then
			self.PetAttachmentManager:ClearWeldsOnPart(pet.PrimaryPart)
			pet.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
			pet.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
		end

		-- Try to reattach to owner
		local owner = self.Players:GetPlayerByUserId(state.ownerUserId)
		local reattached = false

		if owner and owner.Character and owner.Character.PrimaryPart and not self.carryingPetByUserId[state.ownerUserId] then
			local ok, attachResult = pcall(function()
				return self.PetAttachmentManager:AttachPetToPlayer(pet, owner, { resetFlags = false })
			end)

			if ok and attachResult == true then
				self.petState[pet].location = "player"
				self.petState[pet].accessoryTable = nil
				reattached = true
				print("[PetManager] Accessory: Successfully reattached pet to player")
			else
				warn("[PetManager] Accessory: Reattach on Exit failed:", tostring(attachResult))
			end
		else
			print("[PetManager] Accessory: Owner not available for reattach")
		end

		if not reattached then
			-- Leave in world at table for pickup
			local tablePart = state.accessoryTable
			if tablePart and tablePart:IsA("BasePart") then
				pet:SetPrimaryPartCFrame(tablePart.CFrame * CFrame.new(0, tablePart.Size.Y/2 + 2, 0))
				if pet.PrimaryPart then
					pet.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
					pet.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
				end
			end
			pet.Parent = workspace
			self.petState[pet].location = "free"
			self.petState[pet].accessoryTable = nil
			print("[PetManager] Accessory: Released pet to world")
			self.PetRigManager:EnsurePetRig(pet)
		end
		self.PetStateManager:SendStateToOwner(pet)
	end
end

return AccessoryManager
