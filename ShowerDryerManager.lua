local ShowerDryerManager = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

function ShowerDryerManager:Initialize(stateTable, carryingTable, playersService, petMovement)
	self.petState = stateTable or {}
	self.carryingPetByUserId = carryingTable or {}
	self.Players = playersService
	self.PetMovement = petMovement

	self.showerConnected = {}
	self.dryConnected = {}
	self.activeShowerSessions = {}

	self.showerRemote = ReplicatedStorage:FindFirstChild("ShowerMinigameEvent")
	if not self.showerRemote then
		self.showerRemote = Instance.new("RemoteEvent")
		self.showerRemote.Name = "ShowerMinigameEvent"
		self.showerRemote.Parent = ReplicatedStorage
	end

	if not self.showerRemoteConnection then
		self.showerRemoteConnection = self.showerRemote.OnServerEvent:Connect(function(player, action, payload)
			if action == "ToolMove" then
				self:_handleToolMoveFromClient(player, payload)
			elseif action == "Rotate" then
				self:_handleRotateFromClient(player, payload)
			end
		end)
	end

	-- Load dependencies
	self.PetAttachmentManager = require(script.Parent.PetAttachmentManager)
	self.PetStateManager = require(script.Parent.PetStateManager)
	self.TycoonUtils = require(script.Parent.TycoonUtils)
end

function ShowerDryerManager:_toToolHandle(toolInstance)
	if not toolInstance then return nil end
	if toolInstance:IsA("BasePart") then
		return toolInstance
	end
	if toolInstance:IsA("Model") then
		if not toolInstance.PrimaryPart then
			local firstPart = toolInstance:FindFirstChildWhichIsA("BasePart", true)
			if firstPart then
				toolInstance.PrimaryPart = firstPart
			end
		end
		return toolInstance.PrimaryPart
	end
	return nil
end

function ShowerDryerManager:_bindPetToShowerWeld(session)
	if not session then return nil end
	local pet = session.pet
	local showerPart = session.showerPart
	if not pet or not showerPart or not showerPart:IsA("BasePart") then return nil end

	self.PetAttachmentManager:SetModelPrimaryIfMissing(pet)
	local petPrimary = pet.PrimaryPart
	if not petPrimary then return nil end

	self.PetAttachmentManager:ClearWeldsOnPart(petPrimary)

	local existing = session.showerPetWeld
	if existing and existing.Parent then
		existing:Destroy()
	end

	local weld = Instance.new("Weld")
	weld.Name = "ShowerPetWeld"
	weld.Part0 = showerPart
	weld.Part1 = petPrimary
	weld.C0 = showerPart.CFrame:ToObjectSpace(petPrimary.CFrame)
	weld.C1 = CFrame.new()
	weld.Parent = showerPart

	session.showerPetWeld = weld
	return weld
end



function ShowerDryerManager:_moveToolToPosition(toolInstance, worldPos)
	local handle = self:_toToolHandle(toolInstance)
	if not handle then return nil end

	handle.Anchored = true
	handle.CanCollide = false

	if toolInstance:IsA("Model") then
		local current = toolInstance:GetPivot()
		local _, y, z = current:ToOrientation()
		toolInstance:PivotTo(CFrame.new(worldPos) * CFrame.fromOrientation(0, y, z))
	else
		toolInstance.CFrame = CFrame.new(worldPos)
	end

	return handle
end

function ShowerDryerManager:_prepareToolForSession(toolInstance)
	if not toolInstance then return end
	if toolInstance:IsA("BasePart") then
		toolInstance.Anchored = true
		toolInstance.CanCollide = false
		return
	end
	if toolInstance:IsA("Model") then
		for _, d in ipairs(toolInstance:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
	end
end

function ShowerDryerManager:_getDirtPartsForPet(pet)
	local dirtParts = {}
	if not pet or not pet:IsA("Model") then return dirtParts end

	local dirtFolder = pet:FindFirstChild("Dirt")
	if not dirtFolder then return dirtParts end

	for _, item in ipairs(dirtFolder:GetDescendants()) do
		if item:IsA("BasePart") then
			table.insert(dirtParts, item)
		elseif item:IsA("Model") and item ~= dirtFolder then
			local handle = self:_toToolHandle(item)
			if handle then
				table.insert(dirtParts, handle)
			end
		end
	end

	return dirtParts
end


function ShowerDryerManager:_getNearestDirtPart(session, handle)
	if not session or not handle then return nil end
	if #(session.dirtParts or {}) == 0 then return nil end

	local nearestPart = nil
	local nearestDistance = 2.75
	for _, dirtPart in ipairs(session.dirtParts or {}) do
		if dirtPart and dirtPart.Parent then
			local distance = (dirtPart.Position - handle.Position).Magnitude
			if distance <= nearestDistance then
				nearestDistance = distance
				nearestPart = dirtPart
			end
		end
	end

	return nearestPart
end

function ShowerDryerManager:_getStainState(session, dirtPart)
	session.stainStateByPart = session.stainStateByPart or {}
	local state = session.stainStateByPart[dirtPart]
	if state then return state end

	state = { stage1 = 0, stage2 = 0 }
	session.stainStateByPart[dirtPart] = state
	return state
end

function ShowerDryerManager:_getStageProgressFromStains(session, stage)
	local dirtParts = session.dirtParts or {}
	if #dirtParts == 0 then
		return math.clamp(session.progress or 0, 0, 1)
	end

	local total = 0
	local count = 0
	for _, dirtPart in ipairs(dirtParts) do
		if dirtPart and dirtPart.Parent then
			local stainState = self:_getStainState(session, dirtPart)
			total += (stage == 1) and stainState.stage1 or stainState.stage2
			count += 1
		end
	end

	if count <= 0 then return 0 end
	return math.clamp(total / count, 0, 1)
end

function ShowerDryerManager:_isToolTouchingDirt(session, handle)
	if not session or not handle then return false end
	if #(session.dirtParts or {}) == 0 then return true end
	local touching = false

	for _, dirtPart in ipairs(session.dirtParts or {}) do
		if dirtPart and dirtPart.Parent then
			local distance = (dirtPart.Position - handle.Position).Magnitude
			if distance <= 2.75 then
				touching = true
				break
			end
		end
	end

	return touching
end

function ShowerDryerManager:_updateDirtVisualForSession(session)
	if not session then return end

	for _, dirtPart in ipairs(session.dirtParts or {}) do
		if dirtPart and dirtPart.Parent then
			local startTransparency = dirtPart:GetAttribute("ShowerStartTransparency")
			if startTransparency == nil then
				startTransparency = dirtPart.Transparency
				dirtPart:SetAttribute("ShowerStartTransparency", startTransparency)
			end
			local stainState = self:_getStainState(session, dirtPart)
			local cleanProgress = math.clamp((0.6 * stainState.stage1) + (0.4 * stainState.stage2), 0, 1)
			local targetTransparency = startTransparency + ((1 - startTransparency) * cleanProgress)
			dirtPart.Transparency = math.clamp(targetTransparency, 0, 1)
		end
	end
end

function ShowerDryerManager:_clearDirtSessionAttributes(session)
	for _, dirtPart in ipairs((session and session.dirtParts) or {}) do
		if dirtPart and dirtPart.Parent then
			dirtPart:SetAttribute("ShowerStartTransparency", nil)
		end
	end
end
function ShowerDryerManager:_handleToolMoveFromClient(player, payload)
	if not player then return end
	local session = self.activeShowerSessions[player.UserId]
	if not session then return end
	if not session.pet or not session.pet.Parent then return end
	if (self.petState[session.pet] or {}).location ~= "shower" then return end
	if type(payload) ~= "table" then return end
	local worldPos = payload.worldPos
	if typeof(worldPos) ~= "Vector3" then return end

	local activeTool = (session.stage == 1) and session.spongeTool or session.showerHeadTool
	if not activeTool then return end

	local clampedPos = self:_clampToWall(session, worldPos)
	local activePart = self:_moveToolToPosition(activeTool, clampedPos)
	if not activePart then return end

	local petPrimary = session.pet.PrimaryPart
	if not petPrimary then return end

	local distance = (activePart.Position - petPrimary.Position).Magnitude
	if distance > 6 then return end

	local now = tick()
	if (now - (session.lastProgressTick or 0)) < 0.05 then return end
	session.lastProgressTick = now
	
	local touchedPart = self:_getNearestDirtPart(session, activePart)
	if #(session.dirtParts or {}) > 0 and not touchedPart then
		return
	end

	self:_advanceShowerSession(session, 0.04, touchedPart)
end

function ShowerDryerManager:_findObjectNearShower(showerPart, preferredName)
	if not showerPart then return nil end

	local roots = {showerPart}
	local parent = showerPart.Parent
	if parent then table.insert(roots, parent) end
	if parent and parent.Parent then table.insert(roots, parent.Parent) end

	for _, root in ipairs(roots) do
		if root and root.FindFirstChild then
			local direct = root:FindFirstChild(preferredName)
			if direct and (direct:IsA("BasePart") or direct:IsA("Model")) then
				return direct
			end
			for _, d in ipairs(root:GetDescendants()) do
				if (d:IsA("BasePart") or d:IsA("Model")) and d.Name == preferredName then
					return d
				end
			end
		end
	end

	return nil
end

function ShowerDryerManager:_findPartNearShower(showerPart, preferredName)
	local found = self:_findObjectNearShower(showerPart, preferredName)
	if found and found:IsA("BasePart") then
		return found
	end
	if found and found:IsA("Model") then
		return self:_toToolHandle(found)
	end
	return nil
end

function ShowerDryerManager:_handleRotateFromClient(player, payload)
	if not player then return end
	local session = self.activeShowerSessions[player.UserId]
	if not session then return end
	if type(payload) ~= "table" then return end

	local direction = tonumber(payload.direction) or 0
	if direction == 0 then return end
	direction = (direction > 0) and 1 or -1

	local showerPart = session.showerPart
	if not showerPart or not showerPart:IsA("BasePart") then return end
	
	local weld = session.showerPetWeld
	if not weld or not weld.Parent then
		weld = self:_bindPetToShowerWeld(session)
	end

	local rotationStep = math.rad(90) * direction
	if weld and weld.Parent then
		weld.C0 = weld.C0 * CFrame.Angles(0, rotationStep, 0)
	else
		local pet = session.pet
		if pet and pet.Parent then
			pet:PivotTo(pet:GetPivot() * CFrame.Angles(0, rotationStep, 0))
		end
	end
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
		
		self:_startShowerMinigame(player, pet, showerPart)
	end)
	

	self.showerConnected[showerPart] = conn
end

function ShowerDryerManager:_clampToWall(session, worldPos)
	if not session.controlWallPart or not session.controlWallPart:IsA("BasePart") then
		return worldPos
	end

	local wall = session.controlWallPart
	local localPos = wall.CFrame:PointToObjectSpace(worldPos)
	local x = math.clamp(localPos.X, -wall.Size.X / 2, wall.Size.X / 2)
	local y = math.clamp(localPos.Y, -wall.Size.Y / 2, wall.Size.Y / 2)
	local z = math.clamp(localPos.Z, -wall.Size.Z / 2, wall.Size.Z / 2)
	return wall.CFrame:PointToWorldSpace(Vector3.new(x, y, z))
end

function ShowerDryerManager:_advanceShowerSession(session, amount, touchedPart)
	if not session then return end
	local hasDirtParts = #(session.dirtParts or {}) > 0
	if touchedPart and touchedPart.Parent then
		local stainState = self:_getStainState(session, touchedPart)
		if session.stage == 1 then
			stainState.stage1 = math.clamp(stainState.stage1 + amount, 0, 1)
		else
			stainState.stage2 = math.clamp(stainState.stage2 + amount, 0, 1)
		end
	end

	if session.stage == 1 then
		if hasDirtParts then
			session.progress = self:_getStageProgressFromStains(session, 1)
		else
			session.progress = math.clamp((session.progress or 0) + amount, 0, 1)
		end
		local stageOneFloorDirtiness = tonumber(session.stageOneFloorDirtiness) or math.min(46, session.startingDirtiness)
		local reducedDirt = math.floor(session.startingDirtiness - ((session.startingDirtiness - stageOneFloorDirtiness) * session.progress))
		reducedDirt = math.clamp(reducedDirt, stageOneFloorDirtiness, 100)
		self.petState[session.pet] = self.petState[session.pet] or {}
		self.petState[session.pet].dirtiness = reducedDirt
		self.PetStateManager:SendStateToOwner(session.pet)

		if self.showerRemote then
			self.showerRemote:FireClient(session.player, "Progress", {
				stage = 1,
				progress = session.progress,
				stageText = "Scrub with Sponge",
			})
		end

		if session.progress >= 1 then
			session.stage = 2
			session.progress = 0
			if self.showerRemote then
				self.showerRemote:FireClient(session.player, "Stage", {
					stage = 2,
					progress = 0,
					stageText = "Rinse with Shower Head",
				})
			end
		end
	else
		if hasDirtParts then
			session.progress = self:_getStageProgressFromStains(session, 2)
		else
			session.progress = math.clamp((session.progress or 0) + amount, 0, 1)
		end
		self.petState[session.pet] = self.petState[session.pet] or {}
		local stageOneFloorDirtiness = tonumber(session.stageOneFloorDirtiness) or 46
		self.petState[session.pet].dirtiness = math.floor(stageOneFloorDirtiness * (1 - session.progress))
		self.petState[session.pet].wetness = math.floor(100 * session.progress)
		self.PetStateManager:SendStateToOwner(session.pet)

		if self.showerRemote then
			self.showerRemote:FireClient(session.player, "Progress", {
				stage = 2,
				progress = session.progress,
				stageText = "Rinse with Shower Head",
			})
		end

		if session.progress >= 1 then
			self:_updateDirtVisualForSession(session)
			self:_finishShowerForPet(session.player, session.pet, session.showerPart)
		end
	end
	self:_updateDirtVisualForSession(session)
end

function ShowerDryerManager:_startShowerMinigame(player, pet, showerPart)
	if not player or not pet or not showerPart then return end

	self:_cleanupShowerSession(player, false)

	local cameraPart = self:_findPartNearShower(showerPart, "CameraPart")
	local spongeTool = self:_findObjectNearShower(showerPart, "SpongePart")
	local showerHeadTool = self:_findObjectNearShower(showerPart, "ShowerHeadPart")
	local controlWallPart = self:_findPartNearShower(showerPart, "ShowerControlWall")
	local dirtParts = self:_getDirtPartsForPet(pet)

	local session = {
		player = player,
		pet = pet,
		showerPart = showerPart,
		cameraPart = cameraPart,
		spongeTool = spongeTool,
		showerHeadTool = showerHeadTool,
		controlWallPart = controlWallPart,
		dirtParts = dirtParts,
		stage = 1,
		progress = 0,
		startingDirtiness = math.clamp(tonumber((self.petState[pet] or {}).dirtiness) or 0, 0, 100),
		stageOneFloorDirtiness = math.min(46, math.clamp(tonumber((self.petState[pet] or {}).dirtiness) or 0, 0, 100)),
		connections = {},
		lastProgressTick = 0,
		originalShowerCFrame = showerPart.CFrame,
	}

	self.activeShowerSessions[player.UserId] = session
	self:_bindPetToShowerWeld(session)

	local spongePart = self:_toToolHandle(spongeTool)
	local showerHeadPart = self:_toToolHandle(showerHeadTool)
	self:_prepareToolForSession(spongeTool)
	self:_prepareToolForSession(showerHeadTool)

	if self.showerRemote then
		self.showerRemote:FireClient(player, "Start", {
			cameraPart = cameraPart,
			controlWall = controlWallPart,
			spongePart = spongePart,
			showerHeadPart = showerHeadPart,
			stage = 1,
			progress = 0,
			stageText = "Scrub with Sponge",
			rotationEnabled = true,
		})
	end
end

function ShowerDryerManager:_setPromptEnabled(prompt, isEnabled)
	if not prompt then return end
	pcall(function() prompt.Enabled = isEnabled end)
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

function ShowerDryerManager:_cleanupShowerSession(player, sendEndEvent)
	if not player then return end
	local session = self.activeShowerSessions[player.UserId]
	if not session then return end

	for _, conn in ipairs(session.connections or {}) do
		pcall(function() conn:Disconnect() end)
	end
	
	self:_clearDirtSessionAttributes(session)
	if session.showerPetWeld and session.showerPetWeld.Parent then
		pcall(function()
			session.showerPetWeld:Destroy()
		end)
		session.showerPetWeld = nil
	end
	if session.showerPart and session.originalShowerCFrame then
		pcall(function()
			session.showerPart.CFrame = session.originalShowerCFrame
		end)
	end

	if sendEndEvent and self.showerRemote then
		pcall(function() self.showerRemote:FireClient(player, "End", {}) end)
	end

	self.activeShowerSessions[player.UserId] = nil
end

function ShowerDryerManager:_finishShowerForPet(player, pet, showerPart)
	if not pet or not pet.PrimaryPart or not showerPart then return end
	
	local session = player and self.activeShowerSessions[player.UserId]
	if session and session.showerPetWeld and session.showerPetWeld.Parent then
		pcall(function()
			session.showerPetWeld:Destroy()
		end)
		session.showerPetWeld = nil
	end
	local orphanWeld = showerPart:FindFirstChild("ShowerPetWeld")
	if orphanWeld and orphanWeld:IsA("Weld") then
		pcall(function()
			orphanWeld:Destroy()
		end)
	end

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

	self:_cleanupShowerSession(player, true)
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
