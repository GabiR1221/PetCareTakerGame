local ShowerDryerManager = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Server presentation tuning for what other players see. Edit these offsets
-- if the cloned sponge/showerhead should sit differently in the player's hand.
local SERVER_SPONGE_HAND_OFFSET = CFrame.new(0, 0.5, 0)
local SERVER_SPONGE_ROTATION_OFFSET = CFrame.Angles(0, 0, 0)
local SERVER_SHOWERHEAD_HAND_OFFSET = CFrame.new(0, 0.3, 1)
local SERVER_SHOWERHEAD_ROTATION_OFFSET = CFrame.Angles(math.rad(-25), math.rad(15), 0)

local function getShowerEffectNames(actionName)
	if tostring(actionName or "") == "Place" then
		return {"ShowerPlaceEffect", "PetShowerPlaceEffect", "PetPlacedEffect", "PetInteractionEffect"}
	elseif tostring(actionName or "") == "Remove" then
		return {"ShowerRemoveEffect", "PetShowerRemoveEffect", "PetRemovedEffect", "PetInteractionEffect"}
	end
	return {"PetInteractionEffect"}
end

function ShowerDryerManager:Initialize(stateTable, carryingTable, playersService, petMovement, interactionPetResolver, stowPetAsToolCallback, interactionUiCallback)
	self.petState = stateTable or {}
	self.carryingPetByUserId = carryingTable or {}
	self.Players = playersService
	self.PetMovement = petMovement
	self.ResolveInteractionPet = interactionPetResolver
	self.StowPetAsTool = stowPetAsToolCallback
	self.SetInteractionUiHidden = interactionUiCallback

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
			elseif action == "Exit" then
				self:_handleExitFromClient(player)
			end
		end)
	end

	-- Load dependencies
	self.PetAttachmentManager = require(script.Parent.PetAttachmentManager)
	self.PetStateManager = require(script.Parent.PetStateManager)
	self.TycoonUtils = require(script.Parent.TycoonUtils)
	self.EffectModule = require(ReplicatedStorage.Modules.EffectModule)
end

function ShowerDryerManager:_getShowerEffectNames(actionName)
	return getShowerEffectNames(actionName)
end

function ShowerDryerManager:_playShowerPetEffect(actionName, petModel, showerPart)
	if not self.EffectModule then return end
	self.EffectModule:PlayTimedPartEffectForAll(getShowerEffectNames(actionName), petModel or showerPart, {
		offset = CFrame.new(0, 0.25, 0),
		weld = actionName ~= "Remove",
		anchored = actionName == "Remove",
	})
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

function ShowerDryerManager:_getToolContactPart(toolInstance)
	if not toolInstance then return nil end
	if toolInstance:IsA("BasePart") then
		local childCleanBox = toolInstance:FindFirstChild("CleanBox")
		if childCleanBox and childCleanBox:IsA("BasePart") then
			return childCleanBox
		end
		return toolInstance
	end
	if toolInstance:IsA("Model") then
		local cleanBox = toolInstance:FindFirstChild("CleanBox", true)
		if cleanBox and cleanBox:IsA("BasePart") then
			return cleanBox
		end
		return self:_toToolHandle(toolInstance)
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
	session.baseWeldC0 = weld.C0
	return weld
end

function ShowerDryerManager:_updateRubPose(session, targetSurfacePos, targetSurfaceNormal, touchedPart)
	if not session then return end
	local weld = session.showerPetWeld
	if not weld or not weld.Parent then return end

	local baseC0 = session.baseWeldC0 or weld.C0
	session.baseWeldC0 = baseC0
	session.rubOffset = session.rubOffset or Vector3.zero
	session.rubTilt = session.rubTilt or Vector3.zero
	session.lastRubUpdateAt = session.lastRubUpdateAt or tick()

	if touchedPart and touchedPart.Parent and targetSurfacePos and targetSurfaceNormal then
		local now = tick()
		local dt = math.max(now - (session.lastRubUpdateAt or now), 1 / 240)
		session.lastRubTime = now
		session.lastRubUpdateAt = now
		local normal = targetSurfaceNormal
		if typeof(normal) ~= "Vector3" or normal.Magnitude < 1e-4 then
			normal = Vector3.new(0, 1, 0)
		else
			normal = normal.Unit
		end

		local dragIntensity = 0.55
		if session.lastRubWorldPos then
			local speed = (targetSurfacePos - session.lastRubWorldPos).Magnitude / dt
			dragIntensity = math.clamp((speed / 22), 0.35, 1)
		end
		session.lastRubWorldPos = targetSurfacePos

		local pushIn = -normal * (0.07 + (0.05 * dragIntensity))
		session.rubOffset = session.rubOffset:Lerp(pushIn, 0.42 + (0.22 * dragIntensity))

		local petPrimary = session.pet and session.pet.PrimaryPart
		if petPrimary then
			local localHit = petPrimary.CFrame:PointToObjectSpace(targetSurfacePos)
			local tiltX = math.clamp(-localHit.Z * 0.011, -0.06, 0.06)
			local tiltZ = math.clamp(localHit.X * 0.011, -0.06, 0.06)
			session.rubTilt = session.rubTilt:Lerp(Vector3.new(tiltX, 0, tiltZ), 0.36)
		end
	else
		session.lastRubUpdateAt = tick()
		session.lastRubWorldPos = nil
		session.rubOffset = session.rubOffset:Lerp(Vector3.zero, 0.22)
		session.rubTilt = session.rubTilt:Lerp(Vector3.zero, 0.18)
	end

	local offset = session.rubOffset
	local tilt = session.rubTilt
	weld.C0 = baseC0 * CFrame.new(offset.X, offset.Y, offset.Z) * CFrame.Angles(tilt.X, 0, tilt.Z)
end

function ShowerDryerManager:_moveToolToPosition(toolInstance, worldPos, surfaceNormal)
	local handle = self:_toToolHandle(toolInstance)
	if not handle then return nil end

	handle.Anchored = true
	handle.CanCollide = false
	local normal = surfaceNormal
	if typeof(normal) ~= "Vector3" or normal.Magnitude < 1e-4 then
		normal = Vector3.new(0, 1, 0)
	end

	local up = normal.Unit
	local right = Vector3.new(0, 1, 0):Cross(up)
	if right.Magnitude < 1e-4 then
		right = Vector3.new(1, 0, 0):Cross(up)
	end
	right = right.Unit
	local targetHandleCFrame = CFrame.fromMatrix(worldPos, right, up)

	if toolInstance:IsA("Model") then
		local pivot = toolInstance:GetPivot()
		local relative = pivot:ToObjectSpace(handle.CFrame)
		local targetPivot = targetHandleCFrame * relative:Inverse()
		toolInstance:PivotTo(targetPivot)
	else
		toolInstance.CFrame = targetHandleCFrame
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

function ShowerDryerManager:_setSessionToolsServerVisible(session, visible)
	if not session then return end
	session.serverToolVisibilitySnapshots = session.serverToolVisibilitySnapshots or {}
	local function visitTool(toolInstance)
		if not toolInstance then return end
		local instances = {}
		if toolInstance:IsA("BasePart") then
			table.insert(instances, toolInstance)
		elseif toolInstance:IsA("Model") then
			for _, d in ipairs(toolInstance:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(instances, d)
				end
			end
		end
		for _, part in ipairs(instances) do
			if visible == false then
				if session.serverToolVisibilitySnapshots[part] == nil then
					session.serverToolVisibilitySnapshots[part] = part.Transparency
				end
				part.Transparency = 1
			else
				local originalTransparency = session.serverToolVisibilitySnapshots[part]
				if originalTransparency ~= nil then
					part.Transparency = originalTransparency
				end
			end
		end
	end

	visitTool(session.spongeTool)
	visitTool(session.showerHeadTool)
	if visible ~= false then
		session.serverToolVisibilitySnapshots = {}
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
	local nearestDistance = 1.15
	for _, dirtPart in ipairs(session.dirtParts or {}) do
		if dirtPart and dirtPart.Parent then
			local distance = math.huge
			local ok, closestPoint = pcall(function()
				return dirtPart:GetClosestPointOnSurface(handle.Position)
			end)
			if ok and typeof(closestPoint) == "Vector3" then
				distance = (closestPoint - handle.Position).Magnitude
			else
				distance = (dirtPart.Position - handle.Position).Magnitude
			end
			if distance <= nearestDistance then
				nearestDistance = distance
				nearestPart = dirtPart
			end
		end
	end

	return nearestPart
end

function ShowerDryerManager:_getNearestDirtPartAtPosition(session, worldPos, maxDistance)
	if not session or typeof(worldPos) ~= "Vector3" then return nil end
	if #(session.dirtParts or {}) == 0 then return nil end

	local nearestPart = nil
	local nearestDistance = tonumber(maxDistance) or 1.35
	for _, dirtPart in ipairs(session.dirtParts or {}) do
		if dirtPart and dirtPart.Parent then
			local distance = math.huge
			local ok, closestPoint = pcall(function()
				return dirtPart:GetClosestPointOnSurface(worldPos)
			end)
			if ok and typeof(closestPoint) == "Vector3" then
				distance = (closestPoint - worldPos).Magnitude
			else
				distance = (dirtPart.Position - worldPos).Magnitude
			end
			if distance <= nearestDistance then
				nearestDistance = distance
				nearestPart = dirtPart
			end
		end
	end

	return nearestPart
end

function ShowerDryerManager:_getDistanceToPartSurface(part, worldPos)
	if not part or not part:IsA("BasePart") or typeof(worldPos) ~= "Vector3" then
		return math.huge
	end
	local ok, closestPoint = pcall(function()
		return part:GetClosestPointOnSurface(worldPos)
	end)
	if ok and typeof(closestPoint) == "Vector3" then
		return (closestPoint - worldPos).Magnitude
	end
	return (part.Position - worldPos).Magnitude
end

function ShowerDryerManager:_getValidatedTouchedDirtPart(session, rawWorldPos, targetSurfacePos, maxDistance)
	if not session or typeof(rawWorldPos) ~= "Vector3" or typeof(targetSurfacePos) ~= "Vector3" then
		return nil
	end
	local dirtParts = session.dirtParts or {}
	if #dirtParts == 0 then
		return nil
	end

	local nearestPart = nil
	local nearestDistance = tonumber(maxDistance) or 1.35
	local rawAllowance = nearestDistance + 0.45
	for _, dirtPart in ipairs(dirtParts) do
		if dirtPart and dirtPart.Parent then
			local surfaceDistance = self:_getDistanceToPartSurface(dirtPart, targetSurfacePos)
			local rawDistance = self:_getDistanceToPartSurface(dirtPart, rawWorldPos)
			if surfaceDistance <= nearestDistance and rawDistance <= rawAllowance then
				nearestDistance = surfaceDistance
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
			if distance <= 3.75 then
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

function ShowerDryerManager:_getToolHalfThickness(toolInstance)
	local contactPart = self:_getToolContactPart(toolInstance)
	if contactPart then
		return math.max(contactPart.Size.X, contactPart.Size.Y, contactPart.Size.Z) * 0.5
	end
	return 0.6
end

function ShowerDryerManager:_getToolCleanRadius(toolInstance)
	local cleanBox = toolInstance and toolInstance.FindFirstChild and toolInstance:FindFirstChild("CleanBox", true) or nil
	if cleanBox and cleanBox:IsA("BasePart") then
		return math.clamp(math.max(cleanBox.Size.X, cleanBox.Size.Y, cleanBox.Size.Z) * 0.5, 1.1, 4.5)
	end
	local contactPart = self:_getToolContactPart(toolInstance)
	if contactPart then
		return math.clamp(math.max(contactPart.Size.X, contactPart.Size.Y, contactPart.Size.Z) * 0.5, 1.1, 4.5)
	end
	return 1.45
end

function ShowerDryerManager:_getPetSurfaceParts(pet)
	local parts = {}
	if not pet or not pet:IsA("Model") then
		return parts
	end

	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("MeshPart") or d:IsA("UnionOperation") or d:IsA("Part") then
			table.insert(parts, d)
		end
	end

	return parts
end

function ShowerDryerManager:_snapPositionToPetSurface(session, worldPos)
	if not session or not session.pet or not worldPos then
		return worldPos, Vector3.new(0, 1, 0)
	end

	local function projectToPartSurface(part, targetPoint, pushOut)
		if not part or not part:IsA("BasePart") then
			return targetPoint, Vector3.new(0, 1, 0)
		end

		local ok, closestPoint = pcall(function()
			return part:GetClosestPointOnSurface(targetPoint)
		end)
		if not ok or typeof(closestPoint) ~= "Vector3" then
			return targetPoint, Vector3.new(0, 1, 0)
		end

		local normal = targetPoint - closestPoint
		if normal.Magnitude < 1e-4 then
			local localPoint = part.CFrame:PointToObjectSpace(targetPoint)
			local half = part.Size * 0.5

			local dx = half.X - math.abs(localPoint.X)
			local dy = half.Y - math.abs(localPoint.Y)
			local dz = half.Z - math.abs(localPoint.Z)

			if dx <= dy and dx <= dz then
				normal = part.CFrame.RightVector * (localPoint.X >= 0 and 1 or -1)
			elseif dy <= dx and dy <= dz then
				normal = part.CFrame.UpVector * (localPoint.Y >= 0 and 1 or -1)
			else
				normal = part.CFrame.LookVector * (localPoint.Z >= 0 and 1 or -1)
			end
		end

		if normal.Magnitude < 1e-4 then
			normal = Vector3.new(0, 1, 0)
		end

		return closestPoint + (normal.Unit * (pushOut or 0.06)), normal.Unit
	end

	local nearestPart = nil
	local nearestDistance = 4.5
	for _, dirtPart in ipairs(session.dirtParts or {}) do
		if dirtPart and dirtPart.Parent then
			local distance = (dirtPart.Position - worldPos).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearestPart = dirtPart
			end
		end
	end

	if nearestPart then
		return projectToPartSurface(nearestPart, worldPos, 0.02)
	end

	local petParts = self:_getPetSurfaceParts(session.pet)
	if #petParts == 0 then
		return worldPos, Vector3.new(0, 1, 0)
	end

	local bestPoint = nil
	local bestNormal = nil
	local bestDistance = math.huge

	for _, part in ipairs(petParts) do
		local point, normal = projectToPartSurface(part, worldPos, 0.02)
		local dist = (point - worldPos).Magnitude
		if dist < bestDistance then
			bestDistance = dist
			bestPoint = point
			bestNormal = normal
		end
	end

	if bestPoint then
		return bestPoint, bestNormal or Vector3.new(0, 1, 0)
	end

	return worldPos, Vector3.new(0, 1, 0)
end

function ShowerDryerManager:_startPlayerToolPose(session)
	if not session or not session.player then return end
	local character = session.player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local endEffector = character:FindFirstChild("RightHand") or character:FindFirstChild("RightLowerArm") or character:FindFirstChild("Right Arm")
	local chainRoot = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
	local snapLimb = character:FindFirstChild("RightUpperArm") or character:FindFirstChild("Right Arm")
	local rightShoulderMotor = nil
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") and (d.Name == "RightShoulder" or d.Name == "Right Shoulder") then
			rightShoulderMotor = d
			break
		end
	end
	if not rightShoulderMotor then
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("Motor6D")
				and string.find(d.Name, "Right")
				and string.find(d.Name, "Shoulder") then
				rightShoulderMotor = d
				break
			end
		end
	end

	local targetPart = Instance.new("Part")
	targetPart.Name = "ShowerToolIKTarget"
	targetPart.Size = Vector3.new(0.2, 0.2, 0.2)
	targetPart.Transparency = 1
	targetPart.CanCollide = false
	targetPart.CanQuery = false
	targetPart.CanTouch = false
	targetPart.Anchored = true
	targetPart.Parent = workspace

	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Name = "ShowerToolIKTargetAttachment"
	targetAttachment.Parent = targetPart

	local ikControl = nil
	local snapWeld = nil
	local snapMode = false
	local previousShoulderEnabled = nil
	local previousSnapCanCollide = nil

	if rightShoulderMotor and snapLimb and snapLimb:IsA("BasePart") then
		previousShoulderEnabled = rightShoulderMotor.Enabled
		rightShoulderMotor.Enabled = false
		previousSnapCanCollide = snapLimb.CanCollide
		snapLimb.CanCollide = false
		snapLimb.CFrame = targetPart.CFrame

		snapWeld = Instance.new("WeldConstraint")
		snapWeld.Name = "ShowerArmSnapWeld"
		snapWeld.Part0 = targetPart
		snapWeld.Part1 = snapLimb
		snapWeld.Parent = targetPart
		snapMode = true
	elseif endEffector and chainRoot and endEffector:IsA("BasePart") and chainRoot:IsA("BasePart") then
		ikControl = Instance.new("IKControl")
		ikControl.Name = "ShowerToolIK"
		ikControl.Type = Enum.IKControlType.Position
		ikControl.ChainRoot = chainRoot
		ikControl.EndEffector = endEffector
		ikControl.Target = targetAttachment
		ikControl.Priority = 100
		ikControl.Weight = 0.9
		ikControl.SmoothTime = 0.08
		ikControl.Enabled = true
		ikControl.Parent = humanoid
	else
		pcall(function()
			targetPart:Destroy()
		end)
		return
	end

	session.armPose = {
		targetPart = targetPart,
		targetAttachment = targetAttachment,
		ikControl = ikControl,
		snapWeld = snapWeld,
		snapMode = snapMode,
		rightShoulderMotor = rightShoulderMotor,
		previousShoulderEnabled = previousShoulderEnabled,
		snapLimb = snapLimb,
		previousSnapCanCollide = previousSnapCanCollide,
		character = character,
		humanoid = humanoid,
	}
end


function ShowerDryerManager:_updatePlayerToolPose(session, toolWorldPos, toolNormal)
	if not session or not session.armPose or not toolWorldPos then return end
	local armPose = session.armPose
	if not armPose.targetPart or not armPose.targetPart.Parent then return end
	local normal = toolNormal
	if typeof(normal) ~= "Vector3" or normal.Magnitude < 1e-4 then
		normal = Vector3.new(0, 1, 0)
	end

	local pullBack = 0.26
	local targetPos = toolWorldPos - (normal.Unit * pullBack)
	armPose.targetPart.CFrame = CFrame.lookAt(targetPos, targetPos + normal.Unit)
end

function ShowerDryerManager:_resolvePlayerShowerAnimationId(session, stage)
	local showerPart = session and session.showerPart
	local attrNames = (tonumber(stage) == 2)
		and {"ShowerLoopAnimationId2", "PlayerShowerAnimationId2", "ShowerAnimationId2"}
		or {"ShowerLoopAnimationId", "PlayerShowerAnimationId", "ShowerAnimationId"}
	for _, attrName in ipairs(attrNames) do
		local raw = showerPart and showerPart:GetAttribute(attrName)
		if raw ~= nil and tostring(raw) ~= "" then
			local digits = tostring(raw):match("%d+")
			if digits then
				return "rbxassetid://" .. digits
			end
		end
	end

	local config = nil
	if tonumber(stage) == 2 then
		config = ReplicatedStorage:FindFirstChild("ShowerLoopAnimationId2") or ReplicatedStorage:FindFirstChild("PlayerShowerAnimationId2")
	end
	config = config or ReplicatedStorage:FindFirstChild("ShowerLoopAnimationId") or ReplicatedStorage:FindFirstChild("PlayerShowerAnimationId")
	if config and config:IsA("ValueBase") and tostring(config.Value) ~= "" then
		local digits = tostring(config.Value):match("%d+")
		if digits then
			return "rbxassetid://" .. digits
		end
	end

	return nil
end

function ShowerDryerManager:_playPlayerShowerLoop(session, humanoid)
	if not session or not humanoid then return nil end
	local animationId = self:_resolvePlayerShowerAnimationId(session, session.serverPresentationStage or session.stage or 1)
	if not animationId then return nil end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.Name = "ShowerLoopAnimation"
	animation.AnimationId = animationId

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or not track then return nil end

	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.15)
	return track
end


function ShowerDryerManager:_setRuntimeEffectPartsInvisible(effectInstance)
	if not effectInstance then return end
	local function apply(inst)
		if inst:IsA("BasePart") then
			inst.Transparency = 1
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.Massless = true
		elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Light") then
			inst.Enabled = true
		end
	end
	apply(effectInstance)
	for _, d in ipairs(effectInstance:GetDescendants()) do
		apply(d)
	end
end

function ShowerDryerManager:_attachServerToolEffect(effectTemplate, targetPart)
	if not effectTemplate or not targetPart then return nil end
	local clone = effectTemplate:Clone()
	clone.Name = "Server" .. tostring(effectTemplate.Name)

	if clone:IsA("Attachment") then
		clone.Parent = targetPart
		self:_setRuntimeEffectPartsInvisible(clone)
		return clone
	end

	if clone:IsA("ParticleEmitter") or clone:IsA("Trail") or clone:IsA("Beam") or clone:IsA("Light") then
		local attachment = Instance.new("Attachment")
		attachment.Name = clone.Name .. "Attachment"
		attachment.Parent = targetPart
		clone.Parent = attachment
		self:_setRuntimeEffectPartsInvisible(attachment)
		return attachment
	end

	if clone:IsA("BasePart") then
		clone.CFrame = targetPart.CFrame
		clone.Anchored = false
		clone.Parent = targetPart
		local weld = Instance.new("WeldConstraint")
		weld.Name = "ServerShowerEffectWeld"
		weld.Part0 = targetPart
		weld.Part1 = clone
		weld.Parent = clone
	elseif clone:IsA("Model") then
		if not clone.PrimaryPart then
			local firstPart = clone:FindFirstChildWhichIsA("BasePart", true)
			if firstPart then
				pcall(function() clone.PrimaryPart = firstPart end)
			end
		end
		if clone.PrimaryPart then
			clone:PivotTo(targetPart.CFrame)
		end
		clone.Parent = targetPart
		if clone.PrimaryPart then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "ServerShowerEffectWeld"
			weld.Part0 = targetPart
			weld.Part1 = clone.PrimaryPart
			weld.Parent = clone.PrimaryPart
		end
	else
		clone.Parent = targetPart
	end

	local fallbackAttachment = nil
	for _, d in ipairs(clone:GetDescendants()) do
		if (d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Light"))
			and not (d.Parent and (d.Parent:IsA("Attachment") or d.Parent:IsA("BasePart"))) then
			fallbackAttachment = fallbackAttachment or Instance.new("Attachment")
			fallbackAttachment.Name = clone.Name .. "FallbackAttachment"
			fallbackAttachment.Parent = targetPart
			d.Parent = fallbackAttachment
		end
	end

	self:_setRuntimeEffectPartsInvisible(clone)
	if fallbackAttachment and not clone:IsA("BasePart") and not clone:IsA("Model") then
		clone.Parent = fallbackAttachment
		return fallbackAttachment
	end
	return clone
end

function ShowerDryerManager:_captureToolPresentationSnapshot(toolInstance)
	if not toolInstance then return nil end
	local snapshot = {
		tool = toolInstance,
		parent = toolInstance.Parent,
		partState = {},
	}
	if toolInstance:IsA("Model") then
		snapshot.pivot = toolInstance:GetPivot()
	elseif toolInstance:IsA("BasePart") then
		snapshot.cframe = toolInstance.CFrame
	end
	local function capturePart(part)
		snapshot.partState[part] = {
			Anchored = part.Anchored,
			CanCollide = part.CanCollide,
			CanQuery = part.CanQuery,
			CanTouch = part.CanTouch,
			Massless = part.Massless,
		}
	end
	if toolInstance:IsA("BasePart") then
		capturePart(toolInstance)
	elseif toolInstance:IsA("Model") then
		for _, d in ipairs(toolInstance:GetDescendants()) do
			if d:IsA("BasePart") then
				capturePart(d)
			end
		end
	end
	return snapshot
end

function ShowerDryerManager:_restoreToolPresentationSnapshot(snapshot)
	if not snapshot or not snapshot.tool then return end
	local toolInstance = snapshot.tool
	if snapshot.parent then
		toolInstance.Parent = snapshot.parent
	end
	if toolInstance:IsA("Model") and snapshot.pivot then
		pcall(function() toolInstance:PivotTo(snapshot.pivot) end)
	elseif toolInstance:IsA("BasePart") and snapshot.cframe then
		pcall(function() toolInstance.CFrame = snapshot.cframe end)
	end
	for part, state in pairs(snapshot.partState or {}) do
		if part and part.Parent then
			pcall(function()
				part.Anchored = state.Anchored == true
				part.CanCollide = state.CanCollide == true
				part.CanQuery = state.CanQuery == true
				part.CanTouch = state.CanTouch == true
				part.Massless = state.Massless == true
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end)
		end
	end
end

function ShowerDryerManager:_createHeldToolPresentationWelds(toolInstance, contactPart, hand)
	local welds = {}
	local function addWeld(part0, part1, name)
		if not part0 or not part1 or part0 == part1 then return end
		local weld = Instance.new("WeldConstraint")
		weld.Name = name or "ServerShowerPresentationWeld"
		weld.Part0 = part0
		weld.Part1 = part1
		weld.Parent = part1
		table.insert(welds, weld)
	end

	addWeld(hand, contactPart, "ServerShowerHeldToolWeld")
	if toolInstance:IsA("Model") then
		for _, d in ipairs(toolInstance:GetDescendants()) do
			if d:IsA("BasePart") and d ~= contactPart then
				addWeld(contactPart, d, "ServerShowerToolPartWeld")
			end
		end
	end
	return welds
end

function ShowerDryerManager:_prepareExistingHeldTool(toolInstance)
	if not toolInstance then return end
	local function prep(part)
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
	end
	if toolInstance:IsA("BasePart") then
		prep(toolInstance)
	elseif toolInstance:IsA("Model") then
		for _, d in ipairs(toolInstance:GetDescendants()) do
			if d:IsA("BasePart") then
				prep(d)
			end
		end
		if not toolInstance.PrimaryPart then
			local handle = self:_getToolContactPart(toolInstance) or self:_toToolHandle(toolInstance)
			if handle then pcall(function() toolInstance.PrimaryPart = handle end) end
		end
	end
end

function ShowerDryerManager:_cloneServerHeldTool(toolInstance)
	if not toolInstance then return nil end
	local clone = toolInstance:Clone()
	clone.Name = "ServerShowerHeld" .. tostring(toolInstance.Name)
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	if clone:IsA("BasePart") then
		clone.Anchored = false
		clone.CanCollide = false
		clone.CanQuery = false
		clone.CanTouch = false
		clone.Massless = true
	elseif clone:IsA("Model") and not clone.PrimaryPart then
		local handle = self:_getToolContactPart(clone) or self:_toToolHandle(clone)
		if handle then
			pcall(function() clone.PrimaryPart = handle end)
		end
	end
	return clone
end

function ShowerDryerManager:_attachHeldToolToCharacter(session, toolInstance, effectName)
	if not session or not session.player then return nil end
	local character = session.player.Character
	if not character then return nil end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm") or character:FindFirstChild("RightLowerArm")
	if not hand or not hand:IsA("BasePart") then return nil end
	local snapshot = self:_captureToolPresentationSnapshot(toolInstance)
	self:_prepareExistingHeldTool(toolInstance)
	toolInstance.Parent = character
	local contactPart = self:_getToolContactPart(toolInstance) or self:_toToolHandle(toolInstance)
	if not contactPart then
		self:_restoreToolPresentationSnapshot(snapshot)
		return nil
	end
	local isShowerHead = tostring(effectName) == "ShowerHeadEffect"
	local handOffset = isShowerHead and SERVER_SHOWERHEAD_HAND_OFFSET or SERVER_SPONGE_HAND_OFFSET
	local rotationOffset = isShowerHead and SERVER_SHOWERHEAD_ROTATION_OFFSET or SERVER_SPONGE_ROTATION_OFFSET
	local handCf = hand.CFrame * handOffset * rotationOffset
	if toolInstance:IsA("Model") then
		local relative = toolInstance:GetPivot():ToObjectSpace(contactPart.CFrame)
		toolInstance:PivotTo(handCf * relative:Inverse())
	else
		toolInstance.CFrame = handCf
	end
	local welds = self:_createHeldToolPresentationWelds(toolInstance, contactPart, hand)

	local effectClone = nil
	local effectsFolder = ReplicatedStorage:FindFirstChild("Effects")
	local template = effectsFolder and effectsFolder:FindFirstChild(effectName)
	if template then
		effectClone = self:_attachServerToolEffect(template, contactPart)
	end
	return { tool = toolInstance, effect = effectClone, snapshot = snapshot, welds = welds }
end

function ShowerDryerManager:_clearServerShowerPresentation(session)
	if not session then return end
	if session.serverToolEffect then
		pcall(function() session.serverToolEffect:Destroy() end)
		session.serverToolEffect = nil
	end
	for _, weld in ipairs(session.serverHeldToolWelds or {}) do
		if weld and weld.Parent then
			pcall(function() weld:Destroy() end)
		end
	end
	session.serverHeldToolWelds = nil
	if session.serverHeldToolSnapshot then
		self:_restoreToolPresentationSnapshot(session.serverHeldToolSnapshot)
		session.serverHeldToolSnapshot = nil
	end
	session.serverHeldTool = nil
end

function ShowerDryerManager:_stopServerShowerAnimation(session)
	local stance = session and session.playerStance
	if stance and stance.showerLoopTrack then
		pcall(function()
			stance.showerLoopTrack:Stop(0.15)
			stance.showerLoopTrack:Destroy()
		end)
		stance.showerLoopTrack = nil
	end
end

function ShowerDryerManager:_setServerShowerPresentationStage(session, stage)
	if not session then return end
	stage = tonumber(stage) == 2 and 2 or 1
	if session.serverPresentationStage == stage and session.serverHeldTool then return end
	session.serverPresentationStage = stage
	self:_clearServerShowerPresentation(session)

	local tool = (stage == 1) and session.spongeTool or session.showerHeadTool
	local effectName = (stage == 1) and "SpongeEffect" or "ShowerHeadEffect"
	local presentation = self:_attachHeldToolToCharacter(session, tool, effectName)
	if presentation then
		session.serverHeldTool = presentation.tool
		session.serverToolEffect = presentation.effect
		session.serverHeldToolSnapshot = presentation.snapshot
		session.serverHeldToolWelds = presentation.welds
	end

	local stance = session.playerStance
	if stance and stance.humanoid then
		self:_stopServerShowerAnimation(session)
		stance.showerLoopTrack = self:_playPlayerShowerLoop(session, stance.humanoid)
	end
end

function ShowerDryerManager:_startPlayerShowerStance(session)
	if not session or not session.player then return end
	local character = session.player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then return end

	local showerPart = session.showerPart
	if not showerPart or not showerPart:IsA("BasePart") then return end

	local standPart = Instance.new("Part")
	standPart.Name = "ShowerPlayerStand"
	standPart.Size = Vector3.new(1, 1, 1)
	standPart.Transparency = 1
	standPart.CanCollide = false
	standPart.CanQuery = false
	standPart.CanTouch = false
	standPart.Anchored = true
	standPart.Parent = workspace

	local standOffset = Vector3.new(0, 1, -5.4)
	local standPos = showerPart.CFrame:PointToWorldSpace(standOffset)
	local lookAtPos = showerPart.Position + Vector3.new(0, 1.35, 0)
	local flatLook = Vector3.new(lookAtPos.X - standPos.X, 0, lookAtPos.Z - standPos.Z)
	if flatLook.Magnitude < 1e-4 then
		local fallback = showerPart.CFrame.LookVector
		flatLook = Vector3.new(fallback.X, 0, fallback.Z)
	end
	local lookDir = flatLook.Unit
	local worldUp = Vector3.new(0, 1, 0)
	local rightDir = worldUp:Cross(lookDir)
	if rightDir.Magnitude < 1e-4 then
		rightDir = Vector3.new(1, 0, 0)
	end
	rightDir = rightDir.Unit
	lookDir = rightDir:Cross(worldUp).Unit
	standPart.CFrame = CFrame.fromMatrix(standPos, rightDir, worldUp, -lookDir)

	local previousJumpPower = humanoid.JumpPower
	local previousJumpHeight = humanoid.JumpHeight
	local previousWalkSpeed = humanoid.WalkSpeed
	local previousAutoRotate = humanoid.AutoRotate
	local previousSit = humanoid.Sit
	local previousPlatformStand = humanoid.PlatformStand
	local previousAnchored = root.Anchored

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = standPart.CFrame
	root.Anchored = true

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid.Sit = false
	humanoid.PlatformStand = false
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
	end)
	local showerLoopTrack = nil

	local lockConn = RunService.Heartbeat:Connect(function()
		if not root.Parent or not standPart.Parent then return end
		root.CFrame = standPart.CFrame
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		humanoid.Sit = false
		humanoid.PlatformStand = false
	end)

	session.playerStance = {
		standPart = standPart,
		humanoid = humanoid,
		root = root,
		walkSpeed = previousWalkSpeed,
		jumpPower = previousJumpPower,
		jumpHeight = previousJumpHeight,
		autoRotate = previousAutoRotate,
		wasSit = previousSit,
		wasPlatformStand = previousPlatformStand,
		wasAnchored = previousAnchored,
		showerLoopTrack = showerLoopTrack,
		lockConn = lockConn,
	}
	self:_setServerShowerPresentationStage(session, session.stage or 1)
end

function ShowerDryerManager:_stopPlayerShowerStance(session)
	if not session or not session.playerStance then return end
	self:_clearServerShowerPresentation(session)
	local stance = session.playerStance
	if stance.lockConn then
		pcall(function()
			stance.lockConn:Disconnect()
		end)
	end
	if stance.humanoid and stance.humanoid.Parent then
		pcall(function()
			stance.humanoid.WalkSpeed = stance.walkSpeed or 16
			stance.humanoid.JumpPower = stance.jumpPower or 50
			stance.humanoid.JumpHeight = stance.jumpHeight or 7.2
			stance.humanoid.AutoRotate = (stance.autoRotate ~= false)
			stance.humanoid.Sit = (stance.wasSit == true)
			stance.humanoid.PlatformStand = (stance.wasPlatformStand == true)
		end)
	end
	if stance.root and stance.root.Parent then
		pcall(function()
			stance.root.Anchored = (stance.wasAnchored == true)
			stance.root.AssemblyLinearVelocity = Vector3.zero
			stance.root.AssemblyAngularVelocity = Vector3.zero
			local look = stance.root.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude > 1e-4 then
				stance.root.CFrame = CFrame.lookAt(stance.root.Position, stance.root.Position + flatLook.Unit)
			end
		end)
	end
	if stance.showerLoopTrack then
		pcall(function()
			stance.showerLoopTrack:Stop(0.15)
			stance.showerLoopTrack:Destroy()
		end)
	end
	if stance.standPart and stance.standPart.Parent then
		pcall(function()
			stance.standPart:Destroy()
		end)
	end
	if stance.humanoid and stance.humanoid.Parent then
		pcall(function()
			stance.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
		task.defer(function()
			if stance.humanoid and stance.humanoid.Parent then
				pcall(function()
					stance.humanoid:ChangeState(Enum.HumanoidStateType.Running)
				end)
			end
		end)
	end
	session.playerStance = nil
end

function ShowerDryerManager:_stopPlayerToolPose(session)
	if not session or not session.armPose then return end
	local armPose = session.armPose
	if armPose.ikControl and armPose.ikControl.Parent then
		pcall(function()
			armPose.ikControl.Enabled = false
			armPose.ikControl:Destroy()
		end)
	end
	if armPose.snapWeld and armPose.snapWeld.Parent then
		pcall(function()
			armPose.snapWeld:Destroy()
		end)
	end
	if armPose.rightShoulderMotor and armPose.rightShoulderMotor.Parent then
		pcall(function()
			armPose.rightShoulderMotor.Enabled = (armPose.previousShoulderEnabled ~= false)
		end)
	end
	if armPose.snapLimb and armPose.snapLimb.Parent and armPose.previousSnapCanCollide ~= nil then
		pcall(function()
			armPose.snapLimb.CanCollide = armPose.previousSnapCanCollide
		end)
	end
	if armPose.targetPart and armPose.targetPart.Parent then
		pcall(function()
			armPose.targetPart:Destroy()
		end)
	end
	session.armPose = nil
end

function ShowerDryerManager:_mapClientPresentedPointToServerPet(session, worldPos)
	if not session or typeof(worldPos) ~= "Vector3" then
		return worldPos
	end
	local steps = math.floor(tonumber(session.logicalRotationSteps) or 0) % 4
	if steps == 0 then
		return worldPos
	end

	local basePivot = session.serverPetBasePivot
	if typeof(basePivot) ~= "CFrame" then
		local pet = session.pet
		if not pet or not pet.Parent then
			return worldPos
		end
		basePivot = pet:GetPivot()
		session.serverPetBasePivot = basePivot
	end

	local presentedPivot = basePivot * CFrame.Angles(0, math.rad(90 * steps), 0)
	local localPoint = presentedPivot:PointToObjectSpace(worldPos)
	return basePivot:PointToWorldSpace(localPoint)
end

function ShowerDryerManager:_handleToolMoveFromClient(player, payload)
	if not player then return end
	local session = self.activeShowerSessions[player.UserId]
	if not session then return end
	if not session.pet or not session.pet.Parent then return end
	if (self.petState[session.pet] or {}).location ~= "shower" then return end
	if type(payload) ~= "table" then return end
	if session.player ~= player then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and session.showerPart and session.showerPart:IsA("BasePart") then
		if (root.Position - session.showerPart.Position).Magnitude > 30 then
			return
		end
	end

	local worldPos = payload.worldPos
	if typeof(worldPos) ~= "Vector3" then return end
	if worldPos.X ~= worldPos.X or worldPos.Y ~= worldPos.Y or worldPos.Z ~= worldPos.Z then return end

	local activeTool = (session.stage == 1) and session.spongeTool or session.showerHeadTool
	if not activeTool then return end

	local clientClampedPos = self:_clampToWall(session, worldPos)

	if session.showerPart and session.showerPart:IsA("BasePart") then
		local showerDistance = (clientClampedPos - session.showerPart.Position).Magnitude
		if showerDistance > 20 then
			return
		end
	end

	local nowForMove = tick()
	local lastMoveAt = session.lastClientMoveAt
	if session.lastClientMovePos and lastMoveAt then
		local dt = math.max(nowForMove - lastMoveAt, 1 / 240)
		local speed = (clientClampedPos - session.lastClientMovePos).Magnitude / dt
		if speed > 180 then
			session.lastClientMoveAt = nowForMove
			session.lastClientMovePos = clientClampedPos
			return
		end
	end
	session.lastClientMoveAt = nowForMove
	session.lastClientMovePos = clientClampedPos

	local serverContactPos = self:_mapClientPresentedPointToServerPet(session, clientClampedPos)
	local surfacePos, surfaceNormal = self:_snapPositionToPetSurface(session, serverContactPos)
	if typeof(surfacePos) ~= "Vector3" then return end
	if typeof(surfaceNormal) ~= "Vector3" or surfaceNormal.Magnitude < 1e-4 then
		surfaceNormal = Vector3.new(0, 1, 0)
	end

	local snapDistance = (surfacePos - serverContactPos).Magnitude
	local snapEnterDistance = 1.1
	local snapExitDistance = 1.5
	local useSnappedSurface = session.surfaceSnapActive == true
	if useSnappedSurface then
		useSnappedSurface = snapDistance <= snapExitDistance
	else
		useSnappedSurface = snapDistance <= snapEnterDistance
	end
	session.surfaceSnapActive = useSnappedSurface
	local clientHitPet = payload.hitPet == true
	if not useSnappedSurface or not clientHitPet then
		return
	end
	local targetSurfacePos = surfacePos
	local targetSurfaceNormal = surfaceNormal
	if typeof(targetSurfaceNormal) ~= "Vector3" or targetSurfaceNormal.Magnitude < 1e-4 then
		targetSurfaceNormal = Vector3.new(0, 1, 0)
	end

	local toolOffset = math.clamp(self:_getToolHalfThickness(activeTool) * 0.65, 0.18, 0.4)
	local finalPos = targetSurfacePos + targetSurfaceNormal.Unit * toolOffset
	session.lastToolWorldPos = finalPos
	session.lastToolNormal = targetSurfaceNormal

	-- Server no longer moves replicated brush/showerhead parts or rubs the pet weld.
	-- It only validates the owner-sent target and advances progress. The owner sees
	-- local-only tool/pet feedback from ShowerMinigameClient.

	local petPrimary = session.pet.PrimaryPart
	if not petPrimary then return end

	local distance = (targetSurfacePos - petPrimary.Position).Magnitude
	if distance > 6 then return end

	local now = tick()
	local cleanRadius = self:_getToolCleanRadius(activeTool)
	local touchedPart = self:_getValidatedTouchedDirtPart(session, serverContactPos, targetSurfacePos, cleanRadius)

	if (now - (session.lastProgressTick or 0)) < 0.04 then return end
	session.lastProgressTick = now

	if #(session.dirtParts or {}) > 0 and not touchedPart then
		return
	end

	self:_advanceShowerSession(session, 0.065, touchedPart)
end

function ShowerDryerManager:_handleExitFromClient(player)
	if not player then return end
	local session = self.activeShowerSessions[player.UserId]
	if not session then return end
	if not session.pet or not session.pet.Parent then
		self:_cleanupShowerSession(player, true)
		return
	end

	local pet = session.pet
	local showerPart = session.showerPart
	if session.showerPetWeld and session.showerPetWeld.Parent then
		pcall(function()
			session.showerPetWeld:Destroy()
		end)
		session.showerPetWeld = nil
	end
	self.PetAttachmentManager:SetModelPrimaryIfMissing(pet)
	if pet.PrimaryPart then
		self.PetAttachmentManager:ClearWeldsOnPart(pet.PrimaryPart)
	end
	self.PetMovement.StopWandering(pet)
	self:_playShowerPetEffect("Remove", pet, showerPart)

	self.petState[pet] = self.petState[pet] or {}
	local state = self.petState[pet]
	local ownerId = state.ownerUserId
	local restoredToTool = false
	if ownerId then
		local owner = self.Players:GetPlayerByUserId(ownerId)
		if owner and type(self.StowPetAsTool) == "function" then
			local ok2, result = pcall(function()
				return self.StowPetAsTool(owner, pet, true)
			end)
			if ok2 and result == true then
				state.shower = nil
				restoredToTool = true
			end
		end
	end
	if type(self.SetInteractionUiHidden) == "function" then
		self.SetInteractionUiHidden(player, false)
	end

	if not restoredToTool then
		if pet.PrimaryPart and showerPart and showerPart:IsA("BasePart") then
			pet:SetPrimaryPartCFrame(showerPart.CFrame * CFrame.new(0, showerPart.Size.Y/2 + 2, 0))
			pet.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
			pet.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
		end
		pet.Parent = workspace
		state.location = "free"
		state.shower = showerPart
		self.PetStateManager:SendStateToOwner(pet)
	end

	self:_cleanupShowerSession(player, true)
end

function ShowerDryerManager:_normalizeShowerToolObject(found, preferredName)
	if not found then return nil end
	if found:IsA("Model") then return found end
	if found:IsA("BasePart") then
		local parent = found.Parent
		local isToolPartName = preferredName == "SpongePart" or preferredName == "ShowerHeadPart"
		if isToolPartName and parent and parent:IsA("Model") and (parent:FindFirstChild("CleanBox", true) or parent:FindFirstChildWhichIsA("WeldConstraint", true)) then
			return parent
		end
		return found
	end
	return nil
end

function ShowerDryerManager:_findObjectNearShower(showerPart, preferredName)
	if not showerPart then return nil end

	local candidateNames = { preferredName }
	if preferredName == "SpongePart" then
		table.insert(candidateNames, "Sponge")
		table.insert(candidateNames, "SpongeTool")
	elseif preferredName == "ShowerHeadPart" then
		table.insert(candidateNames, "ShowerHead")
		table.insert(candidateNames, "ShowerHeadTool")
		table.insert(candidateNames, "Shower Head")
	end

	local roots = {showerPart}
	local parent = showerPart.Parent
	if parent then table.insert(roots, parent) end
	if parent and parent.Parent then table.insert(roots, parent.Parent) end

	for _, root in ipairs(roots) do
		if root and root.FindFirstChild then
			for _, candidateName in ipairs(candidateNames) do
				local direct = root:FindFirstChild(candidateName)
				local normalizedDirect = self:_normalizeShowerToolObject(direct, preferredName)
				if normalizedDirect then
					return normalizedDirect
				end
			end
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("Model") then
					for _, candidateName in ipairs(candidateNames) do
						if d.Name == candidateName then
							local normalized = self:_normalizeShowerToolObject(d, preferredName)
							if normalized then
								return normalized
							end
						end
					end
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
	if not session.pet or not session.pet.Parent then return end
	if (self.petState[session.pet] or {}).location ~= "shower" then return end
	if type(payload) ~= "table" then return end

	local direction = tonumber(payload.direction) or 0
	if direction == 0 then return end
	direction = (direction > 0) and 1 or -1

	local now = tick()
	if (now - (session.lastRotateTick or 0)) < 0.08 then
		return
	end
	session.lastRotateTick = now


	-- Rotation is a local presentation detail, but the server records the same
	-- 90-degree steps so tool hit positions can be mapped back to the authoritative
	-- unrotated pet/dirt parts for validation and progress.
	session.logicalRotationSteps = ((session.logicalRotationSteps or 0) + direction) % 4
	session.lastClientMoveAt = nil
	session.lastClientMovePos = nil
	session.surfaceSnapActive = false
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

		-- Ensure player is carrying a pet or has an equipped pet tool
		local pet = self.carryingPetByUserId[player.UserId]
		if not pet and type(self.ResolveInteractionPet) == "function" then
			local resolvedPet = self.ResolveInteractionPet(player)
			pet = resolvedPet
		end
		if not pet then
			print("[PetManager] Shower: player triggered while not carrying/holding a pet.")
			return
		end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			pcall(function() hum:UnequipTools() end)
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
		self:_playShowerPetEffect("Place", pet, showerPart)
		self.petState[pet] = self.petState[pet] or {}
		self.petState[pet].location = "shower"
		self.petState[pet].shower = showerPart
		if type(self.SetInteractionUiHidden) == "function" then
			self.SetInteractionUiHidden(player, true)
		end
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
			self:_setServerShowerPresentationStage(session, 2)
			if self.showerRemote then
				self.showerRemote:FireClient(session.player, "Stage", {
					stage = 2,
					progress = 0,
					stageText = "Rinse with Shower Head",
					serverLoopAnimationId = self:_resolvePlayerShowerAnimationId(session, 2),
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
		self.petState[session.pet].wetness = 0
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
		lastRotateTick = 0,
		lastToolWorldPos = nil,
		lastToolNormal = nil,
		logicalRotationSteps = 0,
		serverPetBasePivot = pet:GetPivot(),
		originalShowerCFrame = showerPart.CFrame,
	}

	self.activeShowerSessions[player.UserId] = session
	self:_startPlayerShowerStance(session)
	self:_bindPetToShowerWeld(session)
	-- Server now shows a lightweight looping shower animation for other players.
	-- The detailed minigame camera/tool feedback stays on the showering player's client.

	local spongePart = self:_toToolHandle(spongeTool)
	local showerHeadPart = self:_toToolHandle(showerHeadTool)
	self:_prepareToolForSession(spongeTool)
	self:_prepareToolForSession(showerHeadTool)

	if self.showerRemote then
		self.showerRemote:FireClient(player, "Start", {
			cameraPart = cameraPart,
			controlWall = controlWallPart,
			pet = pet,
			spongePart = spongePart,
			showerHeadPart = showerHeadPart,
			spongeTool = spongeTool,
			showerHeadTool = showerHeadTool,
			stage = 1,
			progress = 0,
			stageText = "Scrub with Sponge",
			rotationEnabled = true,
			serverLoopAnimationId = self:_resolvePlayerShowerAnimationId(session),
		})
	end
end

function ShowerDryerManager:_setPromptEnabled(prompt, isEnabled)
	if not prompt then return end
	pcall(function() prompt.Enabled = isEnabled end)
end


function ShowerDryerManager:_cleanupShowerSession(player, sendEndEvent)
	if not player then return end
	local session = self.activeShowerSessions[player.UserId]
	if not session then return end

	for _, conn in ipairs(session.connections or {}) do
		pcall(function() conn:Disconnect() end)
	end

	self:_clearDirtSessionAttributes(session)
	self:_setSessionToolsServerVisible(session, true)
	self:_stopPlayerToolPose(session)
	self:_stopPlayerShowerStance(session)
	
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
	self:_playShowerPetEffect("Remove", pet, showerPart)

	-- Award XP
	self.PetStateManager:AddXP(pet, 20) -- SHOWER_XP
	local questBridge = ReplicatedStorage:FindFirstChild("PassQuestProgressBridge")
	if questBridge and questBridge:IsA("BindableEvent") and player then
		(questBridge :: BindableEvent):Fire(player, "ShowerPet", 1)
	end

	-- Reset dirtiness; drying mechanic has been removed.
	self.petState[pet] = self.petState[pet] or {}
	self.petState[pet].dirtiness = 0
	self.petState[pet].wetness = 0
	self.petState[pet].showered = true
	self.petState[pet].dried = true

	-- Return to pet tool flow (auto-equip) instead of old carried reattach
	local state = self.petState[pet] or {}
	local ownerId = state.ownerUserId
	local restoredToTool = false

	if ownerId then
		local owner = self.Players:GetPlayerByUserId(ownerId)
		if owner and type(self.StowPetAsTool) == "function" then
			local ok2, result = pcall(function()
				return self.StowPetAsTool(owner, pet, true)
			end)
			if ok2 and result == true then
				self.petState[pet].shower = nil
				restoredToTool = true
			else
				warn(("[PetManager] Shower: stow-to-tool attempt failed: %s"):format(tostring(result)))
			end
		end
	end
	if type(self.SetInteractionUiHidden) == "function" then
		self.SetInteractionUiHidden(player, false)
	end

	-- Fallback: release to world
	if not restoredToTool then
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
	-- Scan for showers
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
			end
		end
	end
end

return ShowerDryerManager
