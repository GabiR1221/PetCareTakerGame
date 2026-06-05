local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera
local showerRemote = ReplicatedStorage:WaitForChild("ShowerMinigameEvent")

-- Shower client tuning:
-- CameraPartForwardOffset moves the actual camera in front of the physical CameraPart
-- so targeting rays do not start inside/behind that part. Set the same attribute on
-- CameraPart to override this default per shower.
local DEFAULT_CAMERA_PART_FORWARD_OFFSET = 2
-- Owner-client local tool tuning. Edit these for how far the local tools sit off
-- the pet surface and how the showerhead is rotated during rinse mode.
---z = y  
local CLIENT_SPONGE_SURFACE_OFFSET_SCALE = 1.5
local CLIENT_SPONGE_ROTATION_OFFSET = CFrame.Angles(0, 0, 0)
local CLIENT_SHOWERHEAD_SURFACE_OFFSET_SCALE = 0.65
local CLIENT_TOOL_SURFACE_OFFSET_MIN = 0.18
local CLIENT_TOOL_SURFACE_OFFSET_MAX = 0.4
local CLIENT_SHOWERHEAD_ROTATION_OFFSET = CFrame.Angles(0, 0, 0)
local CLIENT_CONTROL_WALL_MIN_CAMERA_DISTANCE = 6
local CLIENT_CONTROL_WALL_MOVE_SMOOTHNESS = 32
local CLIENT_TOOL_MOVE_SMOOTHNESS_HIT = 27
local CLIENT_TOOL_SURFACE_SMOOTHNESS_HIT = 18
local CLIENT_TOOL_NORMAL_SMOOTHNESS_HIT = 12
local CLIENT_TOOL_MAX_SURFACE_STEP = 0.9
local CLIENT_TOOL_CONTROL_WALL_PADDING = 0.08
local CLIENT_TOOL_RECENT_SURFACE_GRACE = 0.35
local CLIENT_TOOL_SURFACE_RAY_STICK_RADIUS = 1.25
local CLIENT_TOOL_MIN_SURFACE_CLEARANCE = 0.08
local CLIENT_TOOL_SURFACE_RAY_STICK_MAX_AGE = 0.65
local LOCAL_FOAM_PATCH_SIZE = 0.85
local LOCAL_FOAM_PATCH_TRANSPARENCY = 0.28
local LOCAL_FOAM_SURFACE_OFFSET = 0.16

local gui = Instance.new("ScreenGui")
gui.Name = "ShowerMinigameGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -30, 0.5, 0)
panel.Size = UDim2.new(0, 260, 0, 170)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.Active = true
panel.ZIndex = 10
panel.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 12, 0, 8)
title.Size = UDim2.new(1, -24, 0, 28)
title.Font = Enum.Font.SourceSansBold
title.TextSize = 22
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Shower"
title.ZIndex = 11
title.Parent = panel
title.Size = UDim2.new(1, -64, 0, 28)

local stageLabel = Instance.new("TextLabel")
stageLabel.Name = "StageLabel"
stageLabel.BackgroundTransparency = 1
stageLabel.Position = UDim2.new(0, 12, 0, 38)
stageLabel.Size = UDim2.new(1, -24, 0, 24)
stageLabel.Font = Enum.Font.SourceSansSemibold
stageLabel.TextSize = 18
stageLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
stageLabel.TextXAlignment = Enum.TextXAlignment.Left
stageLabel.Text = "Scrub with Sponge"
stageLabel.ZIndex = 11
stageLabel.Parent = panel

local barBg = Instance.new("Frame")
barBg.Name = "BarBg"
barBg.Position = UDim2.new(0, 12, 0, 72)
barBg.Size = UDim2.new(1, -24, 0, 24)
barBg.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
barBg.BorderSizePixel = 0
barBg.Parent = panel

local barFill = Instance.new("Frame")
barFill.Name = "BarFill"
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
barFill.BorderSizePixel = 0
barFill.ZIndex = 12
barFill.Parent = barBg

local percentLabel = Instance.new("TextLabel")
percentLabel.Name = "Percent"
percentLabel.BackgroundTransparency = 1
percentLabel.Size = UDim2.new(1, 0, 1, 0)
percentLabel.Font = Enum.Font.SourceSansBold
percentLabel.TextSize = 16
percentLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
percentLabel.Text = "0%"
percentLabel.ZIndex = 13
percentLabel.Parent = barBg

local rotateLabel = Instance.new("TextLabel")
rotateLabel.Name = "RotateLabel"
rotateLabel.BackgroundTransparency = 1
rotateLabel.Position = UDim2.new(0, 12, 0, 105)
rotateLabel.Size = UDim2.new(1, -24, 0, 22)
rotateLabel.Font = Enum.Font.SourceSansSemibold
rotateLabel.TextSize = 18
rotateLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
rotateLabel.TextXAlignment = Enum.TextXAlignment.Left
rotateLabel.Text = "Rotate Pet"
rotateLabel.ZIndex = 11
rotateLabel.Parent = panel

local rotateLeft = Instance.new("TextButton")
rotateLeft.Name = "RotateLeft"
rotateLeft.Position = UDim2.new(0, 12, 0, 132)
rotateLeft.Size = UDim2.new(0.5, -18, 0, 28)
rotateLeft.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
rotateLeft.TextColor3 = Color3.new(1, 1, 1)
rotateLeft.Font = Enum.Font.SourceSansBold
rotateLeft.TextSize = 20
rotateLeft.Text = "<-"
rotateLeft.AutoButtonColor = false
rotateLeft.Active = true
rotateLeft.Selectable = true
rotateLeft.ZIndex = 12
rotateLeft.Parent = panel

local rotateRight = Instance.new("TextButton")
rotateRight.Name = "RotateRight"
rotateRight.Position = UDim2.new(0.5, 6, 0, 132)
rotateRight.Size = UDim2.new(0.5, -18, 0, 28)
rotateRight.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
rotateRight.TextColor3 = Color3.new(1, 1, 1)
rotateRight.Font = Enum.Font.SourceSansBold
rotateRight.TextSize = 20
rotateRight.Text = "->"
rotateRight.AutoButtonColor = false
rotateRight.Active = true 
rotateRight.Selectable = true
rotateRight.ZIndex = 12
rotateRight.Parent = panel

local exitButton = Instance.new("TextButton")
exitButton.Name = "ExitButton"
exitButton.AnchorPoint = Vector2.new(1, 0)
exitButton.Position = UDim2.new(1, -12, 0, 10)
exitButton.Size = UDim2.new(0, 28, 0, 24)
exitButton.BackgroundColor3 = Color3.fromRGB(130, 50, 50)
exitButton.TextColor3 = Color3.new(1, 1, 1)
exitButton.Font = Enum.Font.SourceSansBold
exitButton.TextSize = 18
exitButton.Text = "X"
exitButton.AutoButtonColor = true
exitButton.ZIndex = 12
exitButton.Parent = panel
exitButton.Visible = false


local savedCameraType = nil
local savedCameraSubject = nil
local cameraPart = nil
local controlWall = nil
local currentPet = nil
local cameraConn = nil
local cursorTrackConn = nil
local lastToolMoveFireAt = 0
local lastToolMovePoint = nil
local lastExitFireAt = 0
local pointerScreenPos = nil
local activeTouch = nil
local isTouchDragging = false
local currentStage = 1
local localToolVisuals = {}
local localSpongeOriginal = nil
local localShowerHeadOriginal = nil
local originalVisualSnapshots = {}
local lastLocalToolPos = nil
local lastLocalToolNormal = nil
local lastLocalSurfaceHitAt = nil
local lastLocalToolRight = nil
local lastLocalSurfacePos = nil
local lastLocalSurfaceNormal = nil
local lastLocalToolHitPet = false
local localArmPose = nil
local localCharacterTransparencySnapshots = {}
local localCharacterHiddenConn = nil
local localHiddenServerEffectSnapshots = {}
local localPetBasePivot = nil
local localPetRubOffset = Vector3.zero
local localPetRubTilt = Vector3.zero
local lastLocalRubWorldPos = nil
local lastLocalRubAt = nil
local petSquishRig = nil
local localToolEffects = {}
local spongeRubbingActive = false
local showerHeadEffectActive = false
local showerHeadFixedRight = nil
local showerHeadFixedUp = nil
local localFoamPatches = {}
local localFoamUpdateConn = nil

local MAX_SQUISH_BONE_COUNT = 50
local DEFAULT_SQUISH_STRENGTH = 2.5
-- Squish tuning can also be overridden per pet model with attributes:
-- ShowerSquishStrength: total dent depth. Raise for stronger squash, lower if the pet caves in too much.
-- ShowerSquishRadius: world-space radius around the brush/shower hit that is affected. Raise for bigger pets/bones farther apart.
-- ShowerSquishFalloffPower: higher values make the dent tighter around the hit point; lower values spread it out.
-- ShowerSquishSurfaceFollow: how much the visible tool follows the deformed surface so it does not float/clip.
-- ShowerToolSurfaceSmoothness / ShowerToolNormalSmoothness: raise to make the tool react faster; lower to reduce bumpy-mesh jitter.
-- ShowerToolMaxSurfaceStep: maximum per-frame visual surface jump; lower if forehead/face bumps still make the sponge pop.
-- ShowerToolRecentSurfaceGrace: keeps the local tool on the last valid pet surface for short raycast misses instead of snapping to the control wall.
-- ShowerToolSurfaceRayStickRadius: if the cursor ray is still near the last pet surface, keep the local sponge there during raycast misses.
-- ShowerToolMinSurfaceClearance: minimum visible gap from the original pet surface after squish-follow, preventing the tool from being pulled through the pet/wall.
-- ShowerToolSurfaceRayStickMaxAge: hard timeout for ray-stick fallback so the sponge cannot get stuck.
local SQUISH_CONTACT_MAX_DISTANCE = 2.7
local DEFAULT_SQUISH_FALLOFF_POWER = 1.7
local DEFAULT_SQUISH_SURFACE_FOLLOW = 0.9
local DEFAULT_PET_SWAY_POSITION_STRENGTH = 0.75
local DEFAULT_PET_SWAY_TILT_STRENGTH = 0.75
local DEFAULT_SQUISH_IN_SPEED = 26
local DEFAULT_SQUISH_OUT_SPEED = 14
local DEFAULT_SQUISH_CENTER_FOLLOW_SPEED = 18
local CENTER_BONE_NAMES = {
	["Root"] = true,
	["center"] = true,
	["centre"] = true,
	["core"] = true,
}

local function lowerName(value)
	return string.lower(tostring(value or ""))
end

local function getSafeUnit(vector, fallback)
	if typeof(vector) == "Vector3" and vector.Magnitude > 1e-4 then
		return vector.Unit
	end
	if typeof(fallback) == "Vector3" and fallback.Magnitude > 1e-4 then
		return fallback.Unit
	end
	return Vector3.new(0, 1, 0)
end

local function getPetNumberAttribute(petModel, name, defaultValue, minValue, maxValue)
	local value = petModel and petModel:GetAttribute(name)
	value = tonumber(value) or defaultValue
	return math.clamp(value, minValue, maxValue)
end

local function resetPetSquishRig()
	if not petSquishRig then return end
	for bone, originalTransform in pairs(petSquishRig.originalTransforms) do
		if bone and bone.Parent then
			bone.Transform = originalTransform
		end
	end
	petSquishRig = nil
end

local function cachePetSquishRig(petModel)
	resetPetSquishRig()
	if not petModel or not petModel.Parent then return nil end

	local allBones = {}
	for _, inst in ipairs(petModel:GetDescendants()) do
		if inst:IsA("Bone") then
			table.insert(allBones, inst)
		end
	end
	if #allBones == 0 then return nil end
	local squishStrength = tonumber(petModel:GetAttribute("ShowerSquishStrength")) or DEFAULT_SQUISH_STRENGTH
	squishStrength = math.clamp(squishStrength, 0.5, 6)

	local centerBone = nil
	for _, bone in ipairs(allBones) do
		local nameKey = lowerName(bone.Name)
		if CENTER_BONE_NAMES[nameKey] or string.find(nameKey, "root", 1, true) or string.find(nameKey, "center", 1, true) then
			centerBone = bone
			break
		end
	end
	-- Fallback for rigs that use generic names (ex: Bone.001..Bone.006): choose
	-- the bone closest to model pivot center as "center".
	if not centerBone then
		local modelCenter = petModel:GetPivot().Position
		local bestBone = nil
		local bestDist = math.huge
		for _, bone in ipairs(allBones) do
			local dist = (bone.WorldPosition - modelCenter).Magnitude
			if dist < bestDist then
				bestDist = dist
				bestBone = bone
			end
		end
		centerBone = bestBone or allBones[1]
	end

	local outerBones = {}
	for _, bone in ipairs(allBones) do
		if bone ~= centerBone then
			table.insert(outerBones, bone)
		end
	end
	table.sort(outerBones, function(a, b)
		return a.Name < b.Name
	end)
	while #outerBones > MAX_SQUISH_BONE_COUNT do
		table.remove(outerBones)
	end

	local originalTransforms = {}
	originalTransforms[centerBone] = centerBone.Transform
	local originalCenterWorldPos = centerBone.WorldPosition
	local originalCenterWorldCFrame = centerBone.WorldCFrame
	local outerBoneData = {}
	for _, bone in ipairs(outerBones) do
		local originalWorldPos = bone.WorldPosition
		local fromCenter = originalWorldPos - originalCenterWorldPos
		originalTransforms[bone] = bone.Transform
		outerBoneData[bone] = {
			centerLocalCFrame = originalCenterWorldCFrame:ToObjectSpace(bone.WorldCFrame),
			centerLocalPosition = originalCenterWorldCFrame:PointToObjectSpace(originalWorldPos),
			restWorldCFrame = bone.WorldCFrame,
			restWorldPos = originalWorldPos,
			restDirFromCenter = getSafeUnit(fromCenter, Vector3.new(0, 1, 0)),
			originalDistanceFromCenter = fromCenter.Magnitude,
		}
	end

	petSquishRig = {
		centerBone = centerBone,
		outerBones = outerBones,
		outerBoneData = outerBoneData,
		originalTransforms = originalTransforms,
		centerCompression = 0,
		outerCompression = 0,
		centerWorldPos = originalCenterWorldPos,
		centerWorldCFrame = originalCenterWorldCFrame,
		squishStrength = squishStrength,
		squishRadius = getPetNumberAttribute(petModel, "ShowerSquishRadius", SQUISH_CONTACT_MAX_DISTANCE, 0.5, 12),
		squishFalloffPower = getPetNumberAttribute(petModel, "ShowerSquishFalloffPower", DEFAULT_SQUISH_FALLOFF_POWER, 0.5, 5),
		squishSurfaceFollow = getPetNumberAttribute(petModel, "ShowerSquishSurfaceFollow", DEFAULT_SQUISH_SURFACE_FOLLOW, 0, 1.4),
		recentContactWorldPos = nil,
		recentContactNormal = nil,
	}
	return petSquishRig
end

local function getPetSquishTargetCompression(rig, isTouchingPet)
	if isTouchingPet then
		return math.clamp(0.45 * (rig.squishStrength or 1), 0, 2.5)
	end
	return 0
end

local function updatePetSquishRestPose(rig)
	if not rig or not rig.centerBone then return end
	rig.centerWorldPos = rig.centerBone.WorldPosition
	rig.centerWorldCFrame = rig.centerBone.WorldCFrame
	for _, bone in ipairs(rig.outerBones) do
		local boneData = rig.outerBoneData and rig.outerBoneData[bone]
		if boneData and boneData.centerLocalCFrame then
			local restWorldCFrame = rig.centerWorldCFrame * boneData.centerLocalCFrame
			local restWorldPos = restWorldCFrame.Position
			boneData.restWorldCFrame = restWorldCFrame
			boneData.restWorldPos = restWorldPos
			boneData.restDirFromCenter = getSafeUnit(restWorldPos - rig.centerWorldPos, boneData.restDirFromCenter)
		elseif boneData and boneData.centerLocalPosition then
			local restWorldPos = rig.centerWorldCFrame:PointToWorldSpace(boneData.centerLocalPosition)
			boneData.restWorldPos = restWorldPos
			boneData.restDirFromCenter = getSafeUnit(restWorldPos - rig.centerWorldPos, boneData.restDirFromCenter)
		end
	end
end

local function getPetSquishHitFrame(rig, targetSurfacePos, targetSurfaceNormal)
	local petCenter = (rig and rig.centerWorldPos) or Vector3.zero
	local outward = nil
	if typeof(targetSurfaceNormal) == "Vector3" and targetSurfaceNormal.Magnitude > 1e-4 then
		outward = targetSurfaceNormal.Unit
	elseif typeof(targetSurfacePos) == "Vector3" then
		outward = getSafeUnit(targetSurfacePos - petCenter, Vector3.new(0, 1, 0))
	else
		outward = Vector3.new(0, 1, 0)
	end
	local hitDir = outward
	if typeof(targetSurfacePos) == "Vector3" then
		hitDir = getSafeUnit(targetSurfacePos - petCenter, outward)
	end
	return hitDir, -outward
end

local function getPetSquishWeight(rig, boneData, targetSurfacePos, hitDir)
	if not rig or not boneData or typeof(targetSurfacePos) ~= "Vector3" then return 0 end
	local radius = rig.squishRadius or SQUISH_CONTACT_MAX_DISTANCE
	local restWorldPos = boneData.restWorldPos or targetSurfacePos
	local distToHit = (restWorldPos - targetSurfacePos).Magnitude
	if distToHit >= radius then return 0 end

	local distanceWeight = 1 - (distToHit / radius)
	local falloffPower = rig.squishFalloffPower or DEFAULT_SQUISH_FALLOFF_POWER
	distanceWeight = math.pow(math.clamp(distanceWeight, 0, 1), falloffPower)

	-- Only bones on the same side as the contact should move. Using the cached
	-- rest-pose direction prevents left/right bones from being pushed along their
	-- already-deformed CFrame, which was the source of sideways stretching.
	local restDirFromCenter = boneData.restDirFromCenter or Vector3.new(0, 1, 0)
	local sideWeight = math.clamp(restDirFromCenter:Dot(hitDir), 0, 1)
	return distanceWeight * sideWeight
end

local function getSquishedSurfacePosition(targetSurfacePos, targetSurfaceNormal, isTouchingPet, compressionOverride)
	local rig = petSquishRig
	if not rig or typeof(targetSurfacePos) ~= "Vector3" then
		return targetSurfacePos, targetSurfaceNormal
	end
	local compression = compressionOverride
	if compression == nil then
		compression = rig.outerCompression or 0
	end
	if not isTouchingPet or compression <= 0 then
		return targetSurfacePos, targetSurfaceNormal
	end

	updatePetSquishRestPose(rig)
	local hitDir, inward = getPetSquishHitFrame(rig, targetSurfacePos, targetSurfaceNormal)
	local strongestWeight = 0
	for _, bone in ipairs(rig.outerBones) do
		local weight = getPetSquishWeight(rig, rig.outerBoneData and rig.outerBoneData[bone], targetSurfacePos, hitDir)
		if weight > strongestWeight then
			strongestWeight = weight
		end
	end
	local follow = rig.squishSurfaceFollow or DEFAULT_SQUISH_SURFACE_FOLLOW
	local visualOffset = inward * compression * strongestWeight * follow
	return targetSurfacePos + visualOffset, targetSurfaceNormal
end

local function applyPetSquish(targetSurfacePos, targetSurfaceNormal, isTouchingPet)
	local rig = petSquishRig
	if not rig or not rig.centerBone then return end
	local now = tick()
	local dt = math.clamp(now - (lastLocalRubAt or now), 1 / 240, 1 / 20)
	local targetCompression = 0

	if isTouchingPet and typeof(targetSurfacePos) == "Vector3" then
		rig.recentContactWorldPos = targetSurfacePos
		rig.recentContactNormal = targetSurfaceNormal
		targetCompression = getPetSquishTargetCompression(rig, true)
	else
		targetSurfacePos = rig.recentContactWorldPos
		targetSurfaceNormal = rig.recentContactNormal
	end

	local inAlpha = 1 - math.exp(-dt * DEFAULT_SQUISH_IN_SPEED)
	local outAlpha = 1 - math.exp(-dt * DEFAULT_SQUISH_OUT_SPEED)
	local blendAlpha = targetCompression > rig.outerCompression and inAlpha or outAlpha
	rig.outerCompression += (targetCompression - rig.outerCompression) * blendAlpha

	-- Keep the center/root bone stable so deformation is an inward dent instead
	-- of a whole-rig translation.
	rig.centerBone.Transform = rig.originalTransforms[rig.centerBone]

	if typeof(targetSurfacePos) ~= "Vector3" then
		for _, bone in ipairs(rig.outerBones) do
			local base = rig.originalTransforms[bone]
			if base then
				bone.Transform = base
			end
		end
		return
	end

	updatePetSquishRestPose(rig)
	local hitDir, inward = getPetSquishHitFrame(rig, targetSurfacePos, targetSurfaceNormal)
	for _, bone in ipairs(rig.outerBones) do
		local base = rig.originalTransforms[bone]
		local boneData = rig.outerBoneData and rig.outerBoneData[bone]
		if base and boneData then
			local weight = getPetSquishWeight(rig, boneData, targetSurfacePos, hitDir)
			local compression = rig.outerCompression * weight
			local inwardDisplacement = inward * compression
			local restWorldCFrame = boneData.restWorldCFrame or bone.WorldCFrame
			local localDisp = restWorldCFrame:VectorToObjectSpace(inwardDisplacement)

			-- Bone.Transform translation is evaluated in the bone's own rest/world
			-- frame, so convert the inward world-space dent to that frame. This keeps
			-- a front-face press moving away from the camera instead of bulging out.
			bone.Transform = base * CFrame.new(localDisp)
		end
	end
end

local function clearCameraFollow()
	if cameraConn then
		cameraConn:Disconnect()
		cameraConn = nil
	end
end

local function clearCursorTracking()
	if cursorTrackConn then
		cursorTrackConn:Disconnect()
		cursorTrackConn = nil
	end
end

local function getToolHandle(toolInstance)
	if not toolInstance then return nil end
	if toolInstance:IsA("BasePart") then
		return toolInstance
	end
	if toolInstance:IsA("Model") then
		local handle = toolInstance:FindFirstChild("Handle", true)
			or toolInstance:FindFirstChild("SpongePart", true)
			or toolInstance:FindFirstChild("ShowerHeadPart", true)
		if handle and handle:IsA("BasePart") then
			return handle
		end
		if toolInstance.PrimaryPart and toolInstance.PrimaryPart.Name ~= "CleanBox" then
			return toolInstance.PrimaryPart
		end
		for _, d in ipairs(toolInstance:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "CleanBox" then
				return d
			end
		end
		return toolInstance.PrimaryPart or toolInstance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function prepareLocalVisualInstance(instance)
	if instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript") then
		instance:Destroy()
		return false
	end
	if instance:IsA("BasePart") then
		local isNestedCleanBox = instance.Name == "CleanBox" and instance.Parent ~= nil
		if isNestedCleanBox then
			instance.Transparency = 1
			instance.LocalTransparencyModifier = 1
		else
			instance.LocalTransparencyModifier = 0
		end
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanQuery = false
		instance.CanTouch = false
		instance.Massless = true
	end
	return true
end

local function getEffectsFolder()
	local effects = ReplicatedStorage:FindFirstChild("Effects")
	if effects and effects:IsA("Folder") then
		return effects
	end
	return nil
end

local function getToolContactPart(toolInstance)
	if not toolInstance then return nil end
	if toolInstance:IsA("BasePart") then
		return toolInstance.Name == "CleanBox" and toolInstance or (toolInstance:FindFirstChild("CleanBox") or toolInstance)
	end
	if toolInstance:IsA("Model") then
		local cleanBox = toolInstance:FindFirstChild("CleanBox", true)
		if cleanBox and cleanBox:IsA("BasePart") then
			return cleanBox
		end
		return getToolHandle(toolInstance)
	end
	return nil
end

local function getToolVisualPivotPart(toolInstance)
	-- Local visuals should be positioned by the visible sponge/showerhead body,
	-- not by an invisible CleanBox that can be offset for hit detection.
	local handle = getToolHandle(toolInstance)
	if handle and handle:IsA("BasePart") then
		return handle
	end
	if toolInstance and toolInstance:IsA("Model") then
		for _, d in ipairs(toolInstance:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "CleanBox" then
				return d
			end
		end
	end
	return getToolContactPart(toolInstance)
end

local function setEffectEnabled(effectInstance, enabled)
	if not effectInstance then return end
	local function apply(inst)
		if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") then
			inst.Enabled = enabled == true
		elseif inst:IsA("BasePart") then
			inst.Transparency = 1
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			inst.Transparency = (enabled == true) and 0 or 1
		elseif inst:IsA("Light") then
			inst.Enabled = enabled == true
		end
	end
	apply(effectInstance)
	for _, d in ipairs(effectInstance:GetDescendants()) do
		apply(d)
	end
end

local function attachEffectToPart(effectInstance, targetPart, centerOnTarget)
	if not effectInstance or not targetPart then return end
	if effectInstance:IsA("Attachment") then
		if centerOnTarget then
			effectInstance.CFrame = CFrame.new()
		end
		effectInstance.Parent = targetPart
		return
	end
	if effectInstance:IsA("ParticleEmitter") or effectInstance:IsA("Trail") or effectInstance:IsA("Beam") or effectInstance:IsA("Light") then
		local attachment = Instance.new("Attachment")
		attachment.Name = effectInstance.Name .. "Attachment"
		if centerOnTarget then
			attachment.CFrame = CFrame.new()
		end
		attachment.Parent = targetPart
		effectInstance.Parent = attachment
		return
	end
	if effectInstance:IsA("BasePart") then
		effectInstance.Anchored = false
		effectInstance.CanCollide = false
		effectInstance.CanQuery = false
		effectInstance.CanTouch = false
		effectInstance.Massless = true
		effectInstance.CFrame = centerOnTarget and targetPart.CFrame or effectInstance.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = targetPart
		weld.Part1 = effectInstance
		weld.Parent = effectInstance
	end
	effectInstance.Parent = targetPart
end

local function addLocalToolEffect(originalTool, effectName, startsEnabled)
	if not originalTool or localToolEffects[originalTool] then return end
	local visual = localToolVisuals[originalTool]
	if not visual then return end
	local effectsFolder = getEffectsFolder()
	local template = effectsFolder and effectsFolder:FindFirstChild(effectName)
	if not template then return end
	local targetPart = getToolVisualPivotPart(visual) or getToolHandle(visual) or getToolContactPart(visual)
	if not targetPart then return end
	local clone = template:Clone()
	clone.Name = "Local" .. effectName
	attachEffectToPart(clone, targetPart, true)
	localToolEffects[originalTool] = clone
	setEffectEnabled(clone, startsEnabled == true)
end

local function setLocalToolEffectActive(originalTool, active)
	local effect = originalTool and localToolEffects[originalTool]
	if effect then
		setEffectEnabled(effect, active == true)
	end
end

local function setOriginalToolLocalHidden(toolInstance, hidden)
	if not toolInstance then return end
	local parts = {}
	if toolInstance:IsA("BasePart") then
		table.insert(parts, toolInstance)
	elseif toolInstance:IsA("Model") then
		for _, d in ipairs(toolInstance:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(parts, d) end
		end
	end
	for _, part in ipairs(parts) do
		if originalVisualSnapshots[part] == nil then
			originalVisualSnapshots[part] = part.LocalTransparencyModifier
		end
		part.LocalTransparencyModifier = hidden and 1 or (originalVisualSnapshots[part] or 0)
	end
end

local function cloneLocalToolVisual(toolInstance)
	if not toolInstance then return nil end
	local clone = toolInstance:Clone()
	clone.Name = "LocalShower" .. tostring(toolInstance.Name)
	for _, d in ipairs(clone:GetDescendants()) do
		prepareLocalVisualInstance(d)
	end
	prepareLocalVisualInstance(clone)
	if clone:IsA("Model") and not clone.PrimaryPart then
		local handle = getToolHandle(clone)
		if handle then
			pcall(function() clone.PrimaryPart = handle end)
		end
	end
	clone.Parent = workspace.CurrentCamera or workspace
	return clone
end

local function setLocalShowerCharacterVisible(visible)
	local character = player.Character
	if not character then return end
	local function hideCharacterInstance(inst)
		if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Light") then
			if localHiddenServerEffectSnapshots[inst] == nil then
				localHiddenServerEffectSnapshots[inst] = inst.Enabled
			end
			inst.Enabled = false
			return
		end
		if inst:IsA("BasePart") then
			if localCharacterTransparencySnapshots[inst] == nil then
				localCharacterTransparencySnapshots[inst] = inst.LocalTransparencyModifier
			end
			inst.LocalTransparencyModifier = 1
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			if localCharacterTransparencySnapshots[inst] == nil then
				localCharacterTransparencySnapshots[inst] = inst.Transparency
			end
			inst.Transparency = 1
		end
	end
	if visible == false then
		for _, d in ipairs(character:GetDescendants()) do
			hideCharacterInstance(d)
		end
		if localCharacterHiddenConn then
			localCharacterHiddenConn:Disconnect()
		end
		localCharacterHiddenConn = character.DescendantAdded:Connect(hideCharacterInstance)
	else
		if localCharacterHiddenConn then
			localCharacterHiddenConn:Disconnect()
			localCharacterHiddenConn = nil
		end
		for inst, enabled in pairs(localHiddenServerEffectSnapshots) do
			if inst and inst.Parent and (inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Light")) then
				inst.Enabled = enabled == true
			end
		end
		localHiddenServerEffectSnapshots = {}
		for inst, value in pairs(localCharacterTransparencySnapshots) do
			if inst and inst.Parent then
				if inst:IsA("BasePart") then
					inst.LocalTransparencyModifier = value or 0
				elseif inst:IsA("Decal") or inst:IsA("Texture") then
					inst.Transparency = value or 0
				end
			end
		end
		localCharacterTransparencySnapshots = {}
	end
end

local function cleanupLocalArmPose()
	if localArmPose then
		if localArmPose.ikControl then
			pcall(function()
				localArmPose.ikControl.Enabled = false
				localArmPose.ikControl:Destroy()
			end)
		end
		if localArmPose.targetPart then
			pcall(function() localArmPose.targetPart:Destroy() end)
		end
		localArmPose = nil
	end
	setLocalShowerCharacterVisible(true)
end

local function setupLocalArmPose()
	cleanupLocalArmPose()
	setLocalShowerCharacterVisible(false)
end

local function updateLocalArmPose(toolWorldPos, toolNormal)
	if not localArmPose or not localArmPose.targetPart or not toolWorldPos then return end
	local normal = toolNormal
	if typeof(normal) ~= "Vector3" or normal.Magnitude < 1e-4 then
		normal = Vector3.new(0, 1, 0)
	end
	local targetPos = toolWorldPos - (normal.Unit * 0.26)
	localArmPose.targetPart.CFrame = CFrame.lookAt(targetPos, targetPos + normal.Unit)
end

local function getLocalFoamCFrame(localPos, localNormal)
	if not currentPet or not currentPet.Parent or typeof(localPos) ~= "Vector3" then
		return nil
	end
	local petPivot = localPetBasePivot or currentPet:GetPivot()
	local baseWorldPos = petPivot:PointToWorldSpace(localPos)
	local worldNormal = petPivot:VectorToWorldSpace(getSafeUnit(localNormal, Vector3.new(0, 1, 0)))
	worldNormal = getSafeUnit(worldNormal, Vector3.new(0, 1, 0))
	local compression = petSquishRig and petSquishRig.outerCompression or 0
	local squishedWorldPos = getSquishedSurfacePosition(baseWorldPos, worldNormal, compression > 0, compression)
	local currentPivot = currentPet:GetPivot()
	local petMotionOffset = currentPivot.Position - petPivot.Position
	local worldPos = squishedWorldPos + petMotionOffset
	local cameraRight = camera and camera.CFrame.RightVector or Vector3.new(1, 0, 0)
	local tangent = cameraRight - (worldNormal * cameraRight:Dot(worldNormal))
	if tangent.Magnitude < 1e-4 then
		tangent = Vector3.new(0, 1, 0):Cross(worldNormal)
	end
	if tangent.Magnitude < 1e-4 then
		tangent = Vector3.new(1, 0, 0):Cross(worldNormal)
	end
	tangent = tangent.Unit
	-- Cylinder parts are thick along local X, so use the surface normal as X to
	-- make the circular face lie flat on the pet surface.
	local foamOffset = tonumber(currentPet:GetAttribute("ShowerFoamSurfaceOffset")) or LOCAL_FOAM_SURFACE_OFFSET
	foamOffset = math.clamp(foamOffset, 0.04, 0.45)
	return CFrame.fromMatrix(worldPos + (worldNormal * foamOffset), worldNormal, tangent)
end

local function clearLocalFoamPatches()
	if localFoamUpdateConn then
		localFoamUpdateConn:Disconnect()
		localFoamUpdateConn = nil
	end
	for _, patch in pairs(localFoamPatches) do
		if patch.part then
			pcall(function() patch.part:Destroy() end)
		end
	end
	localFoamPatches = {}
end

local function ensureLocalFoamUpdater()
	if localFoamUpdateConn then return end
	localFoamUpdateConn = RunService.RenderStepped:Connect(function()
		if not gui.Enabled or not currentPet or not currentPet.Parent then return end
		for _, patch in pairs(localFoamPatches) do
			if patch.part and patch.part.Parent then
				local cf = getLocalFoamCFrame(patch.localPos, patch.localNormal)
				if cf then
					patch.part.CFrame = cf
				end
			end
		end
	end)
end

local function addLocalFoamPatch(key, localPos, localNormal)
	if not key or typeof(localPos) ~= "Vector3" then return end
	local existing = localFoamPatches[key]
	if existing and existing.part then return end
	local cf = getLocalFoamCFrame(localPos, localNormal)
	if not cf then return end
	local foam = Instance.new("Part")
	foam.Name = "LocalShowerFoamPatch"
	foam.Anchored = true
	foam.CanCollide = false
	foam.CanQuery = false
	foam.CanTouch = false
	foam.CastShadow = false
	foam.Material = Enum.Material.SmoothPlastic
	foam.Color = Color3.fromRGB(245, 255, 255)
	foam.Transparency = LOCAL_FOAM_PATCH_TRANSPARENCY
	foam.Shape = Enum.PartType.Cylinder
	foam.Size = Vector3.new(0.035, LOCAL_FOAM_PATCH_SIZE, LOCAL_FOAM_PATCH_SIZE)
	foam.CFrame = cf
	foam.Parent = workspace.CurrentCamera or workspace
	localFoamPatches[key] = { part = foam, localPos = localPos, localNormal = localNormal }
	ensureLocalFoamUpdater()
end

local function clearLocalFoamPatch(key)
	local patch = key and localFoamPatches[key]
	if not patch then return end
	localFoamPatches[key] = nil
	if patch.part then
		local part = patch.part
		local tween = TweenService:Create(part, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 })
		tween:Play()
		task.delay(0.15, function()
			if part and part.Parent then part:Destroy() end
		end)
	end
end

local function cleanupLocalShowerVisuals()
	clearLocalFoamPatches()
	for _, effect in pairs(localToolEffects) do
		if effect then pcall(function() effect:Destroy() end) end
	end
	localToolEffects = {}
	spongeRubbingActive = false
	showerHeadEffectActive = false
	for original, visual in pairs(localToolVisuals) do
		if visual then pcall(function() visual:Destroy() end) end
		setOriginalToolLocalHidden(original, false)
	end
	for part, localTransparency in pairs(originalVisualSnapshots) do
		if part and part.Parent then
			part.LocalTransparencyModifier = localTransparency or 0
		end
	end
	localToolVisuals = {}
	localSpongeOriginal = nil
	localShowerHeadOriginal = nil
	originalVisualSnapshots = {}
	lastLocalToolPos = nil
	lastLocalToolNormal = nil
	lastLocalSurfaceHitAt = nil
	lastLocalToolRight = nil
	lastLocalSurfacePos = nil
	lastLocalSurfaceNormal = nil
	lastLocalToolHitPet = false
	localPetBasePivot = nil
	localPetRubOffset = Vector3.zero
	localPetRubTilt = Vector3.zero
	lastLocalRubWorldPos = nil
	lastLocalRubAt = nil
	showerHeadFixedRight = nil
	showerHeadFixedUp = nil
	cleanupLocalArmPose()
end

local function setLocalToolVisualVisible(originalTool, visible)
	local visual = originalTool and localToolVisuals[originalTool]
	if not visual then return end
	local modifier = visible and 0 or 1
	if visual:IsA("BasePart") then
		visual.LocalTransparencyModifier = modifier
	elseif visual:IsA("Model") then
		for _, d in ipairs(visual:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = modifier
			end
		end
	end
end

local function updateLocalToolStageVisibility()
	setLocalToolVisualVisible(localSpongeOriginal, currentStage == 1)
	setLocalToolVisualVisible(localShowerHeadOriginal, currentStage ~= 1)
end

local function normalizeLocalToolOriginal(toolInstance)
	if not toolInstance then return nil end
	if toolInstance:IsA("BasePart") then
		local parent = toolInstance.Parent
		if parent and parent:IsA("Model") then
			local partCount = 0
			for _, d in ipairs(parent:GetDescendants()) do
				if d:IsA("BasePart") then
					partCount += 1
					if partCount > 1 then break end
				end
			end
			if partCount > 1 or parent:FindFirstChild("CleanBox", true) then
				return parent
			end
		end
	end
	return toolInstance
end

local function setupLocalShowerVisuals(payload)
	cleanupLocalShowerVisuals()
	localSpongeOriginal = normalizeLocalToolOriginal(payload.spongeTool or payload.spongePart)
	localShowerHeadOriginal = normalizeLocalToolOriginal(payload.showerHeadTool or payload.showerHeadPart)
	for _, original in ipairs({ localSpongeOriginal, localShowerHeadOriginal }) do
		if original then
			local visual = cloneLocalToolVisual(original)
			if visual then
				localToolVisuals[original] = visual
				setOriginalToolLocalHidden(original, true)
			end
		end
	end
	addLocalToolEffect(localSpongeOriginal, "SpongeEffect", false)
	addLocalToolEffect(localShowerHeadOriginal, "ShowerHeadEffect", false)
	updateLocalToolStageVisibility()
	setupLocalArmPose()
end

local function getLocalActiveOriginalTool()
	if currentStage == 1 and localSpongeOriginal and localToolVisuals[localSpongeOriginal] then
		return localSpongeOriginal
	end
	if currentStage ~= 1 and localShowerHeadOriginal and localToolVisuals[localShowerHeadOriginal] then
		return localShowerHeadOriginal
	end
	for original in pairs(localToolVisuals) do return original end
	return nil
end

local function getLocalToolHalfThickness(toolInstance)
	local visualPart = getToolVisualPivotPart(toolInstance)
	if visualPart then
		return math.max(visualPart.Size.X, visualPart.Size.Y, visualPart.Size.Z) * 0.5
	end
	local handle = getToolHandle(toolInstance)
	if handle then
		return math.max(handle.Size.X, handle.Size.Y, handle.Size.Z) * 0.5
	end
	return 0.6
end

local function moveLocalToolToPosition(toolInstance, worldPos, surfaceNormal)
	local visual = toolInstance and localToolVisuals[toolInstance]
	if not visual or not worldPos then return end
	local normal = surfaceNormal
	if typeof(normal) ~= "Vector3" or normal.Magnitude < 1e-4 then
		normal = lastLocalToolNormal or Vector3.new(0, 1, 0)
	end
	normal = normal.Unit
	local up = normal
	local right = lastLocalToolRight
	if toolInstance == localShowerHeadOriginal and currentStage ~= 1 then
		if not showerHeadFixedRight or not showerHeadFixedUp then
			local camCf = camera and camera.CFrame or CFrame.new()
			showerHeadFixedRight = camCf.RightVector
			showerHeadFixedUp = (camCf * CLIENT_SHOWERHEAD_ROTATION_OFFSET).UpVector
		end
		right = showerHeadFixedRight
		up = showerHeadFixedUp
	end
	local previousRight = right
	if typeof(right) == "Vector3" and right.Magnitude > 1e-4 then
		right = right - (up * right:Dot(up))
	end
	if typeof(right) ~= "Vector3" or right.Magnitude < 1e-4 then
		local cameraRight = camera and camera.CFrame.RightVector or Vector3.new(1, 0, 0)
		right = cameraRight - (up * cameraRight:Dot(up))
	end
	if typeof(right) ~= "Vector3" or right.Magnitude < 1e-4 then
		right = Vector3.new(0, 1, 0):Cross(up)
	end
	if right.Magnitude < 1e-4 then
		right = Vector3.new(1, 0, 0):Cross(up)
	end
	right = right.Unit
	if typeof(previousRight) == "Vector3" and previousRight.Magnitude > 1e-4 and right:Dot(previousRight.Unit) < 0 then
		right = -right
	end
	lastLocalToolRight = right
	local cf = CFrame.fromMatrix(worldPos, right, up)
	if toolInstance == localSpongeOriginal and currentStage == 1 then
		cf = cf * CLIENT_SPONGE_ROTATION_OFFSET
	end
	if visual:IsA("Model") then
		local pivotPart = getToolVisualPivotPart(visual) or getToolHandle(visual)
		if pivotPart then
			local relative = visual:GetPivot():ToObjectSpace(pivotPart.CFrame)
			visual:PivotTo(cf * relative:Inverse())
		else
			visual:PivotTo(cf)
		end
	elseif visual:IsA("BasePart") then
		visual.CFrame = cf
	end
	updateLocalArmPose(worldPos, normal)
end

local function applyLocalPetRub(targetSurfacePos, targetSurfaceNormal, isTouchingPet)
	if not currentPet or not currentPet.Parent then return end
	localPetBasePivot = localPetBasePivot or currentPet:GetPivot()
	local now = tick()
	if isTouchingPet and typeof(targetSurfacePos) == "Vector3" then
		local normal = targetSurfaceNormal
		if typeof(normal) ~= "Vector3" or normal.Magnitude < 1e-4 then
			normal = Vector3.new(0, 1, 0)
		else
			normal = normal.Unit
		end
		local dt = math.max(now - (lastLocalRubAt or now), 1 / 240)
		local dragIntensity = 0.55
		if lastLocalRubWorldPos then
			dragIntensity = math.clamp(((targetSurfacePos - lastLocalRubWorldPos).Magnitude / dt) / 22, 0.35, 1)
		end
		lastLocalRubWorldPos = targetSurfacePos
		lastLocalRubAt = now

		localPetRubOffset = localPetRubOffset:Lerp(-normal * (0.07 + (0.05 * dragIntensity)), 0.48)
		local swayPositionStrength = tonumber(currentPet:GetAttribute("ShowerPetSwayPositionStrength")) or DEFAULT_PET_SWAY_POSITION_STRENGTH
		swayPositionStrength = math.clamp(swayPositionStrength, 0, 2)
		localPetRubOffset *= swayPositionStrength
		local petPivot = currentPet:GetPivot()
		local localHit = petPivot:PointToObjectSpace(targetSurfacePos)
		local tiltX = math.clamp(-localHit.Z * 0.011, -0.06, 0.06)
		local tiltZ = math.clamp(localHit.X * 0.011, -0.06, 0.06)
		localPetRubTilt = localPetRubTilt:Lerp(Vector3.new(tiltX, 0, tiltZ), 0.4)
		local swayTiltStrength = tonumber(currentPet:GetAttribute("ShowerPetSwayTiltStrength")) or DEFAULT_PET_SWAY_TILT_STRENGTH
		swayTiltStrength = math.clamp(swayTiltStrength, 0, 2)
		localPetRubTilt *= swayTiltStrength
	else
		lastLocalSurfacePos = nil
		lastLocalSurfaceNormal = nil
		lastLocalRubWorldPos = nil
		lastLocalSurfaceHitAt = nil
		lastLocalRubAt = now
		localPetRubOffset = localPetRubOffset:Lerp(Vector3.zero, 0.22)
		localPetRubTilt = localPetRubTilt:Lerp(Vector3.zero, 0.18)
	end

	currentPet:PivotTo(localPetBasePivot * CFrame.new(localPetRubOffset) * CFrame.Angles(localPetRubTilt.X, 0, localPetRubTilt.Z))
	applyPetSquish(targetSurfacePos, targetSurfaceNormal, isTouchingPet)
end

local function suppressLocalServerShowerLoop(animationId)
	if type(animationId) ~= "string" or animationId == "" then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	local expectedDigits = string.match(animationId, "%d+")
	if not expectedDigits then return end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local trackAnimation = track.Animation
		local trackDigits = trackAnimation and string.match(tostring(trackAnimation.AnimationId or ""), "%d+")
		if track.Name == "ShowerLoopAnimation" or (trackDigits and trackDigits == expectedDigits) then
			pcall(function() track:Stop(0.05) end)
		end
	end
end

local function rotateLocalPet(direction)
	if not currentPet or not currentPet.Parent then return end
	local rotationStep = math.rad(90) * ((direction or 0) >= 0 and 1 or -1)
	pcall(function()
		localPetBasePivot = (localPetBasePivot or currentPet:GetPivot()) * CFrame.Angles(0, rotationStep, 0)
		currentPet:PivotTo(localPetBasePivot * CFrame.new(localPetRubOffset) * CFrame.Angles(localPetRubTilt.X, 0, localPetRubTilt.Z))
	end)
end

local function endShowerView()
	clearCameraFollow()
	clearCursorTracking()
	cleanupLocalShowerVisuals()
	if savedCameraType then
		camera.CameraType = savedCameraType
		savedCameraType = nil
	end
	if savedCameraSubject then
		camera.CameraSubject = savedCameraSubject
		savedCameraSubject = nil
	end
	cameraPart = nil
	controlWall = nil
	currentPet = nil
	resetPetSquishRig()
	gui.Enabled = false
	exitButton.Visible = false
end

local function getCameraPartViewCFrame(targetCameraPart)
	local forwardOffset = DEFAULT_CAMERA_PART_FORWARD_OFFSET
	local attrOffset = targetCameraPart and targetCameraPart:GetAttribute("ClientCameraForwardOffset")
	if attrOffset ~= nil then
		forwardOffset = math.clamp(tonumber(attrOffset) or forwardOffset, -8, 8)
	end
	return targetCameraPart.CFrame * CFrame.new(0, 0, -forwardOffset)
end

local function startShowerView(targetCameraPart)
	if not targetCameraPart or not targetCameraPart:IsA("BasePart") then
		return
	end

	savedCameraType = camera.CameraType
	savedCameraSubject = camera.CameraSubject
	cameraPart = targetCameraPart

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = getCameraPartViewCFrame(targetCameraPart)

	clearCameraFollow()
	cameraConn = RunService.RenderStepped:Connect(function()
		if cameraPart and cameraPart.Parent then
			local baseCFrame = getCameraPartViewCFrame(cameraPart)
			local viewport = camera.ViewportSize
			local nx = 0
			local ny = 0
			if viewport.X > 0 and viewport.Y > 0 then
				nx = ((mouse.X / viewport.X) - 0.5) * 2
				ny = ((mouse.Y / viewport.Y) - 0.5) * 2
			end
			nx = math.clamp(nx, -1, 1)
			ny = math.clamp(ny, -1, 1)

			local yaw = math.rad(nx * 4.5)
			local pitch = math.rad(-ny * 2.8)
			local localOffset = Vector3.new(nx * 0.15, -ny * 0.08, 0)
			camera.CFrame = baseCFrame * CFrame.new(localOffset) * CFrame.Angles(pitch, yaw, 0)
		end
	end)
end

local function updateBar(progress)
	progress = math.clamp(tonumber(progress) or 0, 0, 1)
	barFill.Size = UDim2.new(progress, 0, 1, 0)
	percentLabel.Text = ("%d%%"):format(math.floor(progress * 100 + 0.5))
end

local function getControlWallIntersectionForRay(ray)
	if not controlWall or not controlWall:IsA("BasePart") then return nil end
	local wallCf = controlWall.CFrame
	local normal = wallCf.LookVector
	local rayDir = ray.Direction.Unit
	local originToWall = wallCf.Position - ray.Origin
	local denom = rayDir:Dot(normal)
	if math.abs(denom) <= 1e-4 then return nil end
	local distance = originToWall:Dot(normal) / denom
	if distance <= 0 then return nil end
	if distance < CLIENT_CONTROL_WALL_MIN_CAMERA_DISTANCE then
		distance = CLIENT_CONTROL_WALL_MIN_CAMERA_DISTANCE
	end
	return ray.Origin + (rayDir * distance), normal, distance
end

local function getMovePoint(screenPos)
	local x = (screenPos and screenPos.X) or mouse.X
	local y = (screenPos and screenPos.Y) or mouse.Y
	local ray = camera:ViewportPointToRay(x, y)
	local rayDir = ray.Direction.Unit
	local wallPos, wallNormal, wallDistance = getControlWallIntersectionForRay(ray)
	if currentPet and currentPet.Parent then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {currentPet}
		local hitPet = workspace:Raycast(ray.Origin, rayDir * 500, params)
		if hitPet then
			local surfaceNormal = hitPet.Normal
			local toCamera = ray.Origin - hitPet.Position
			if toCamera.Magnitude > 1e-4 and surfaceNormal:Dot(toCamera.Unit) < 0 then
				surfaceNormal = -surfaceNormal
			end
			return {
				worldPos = hitPet.Position + (surfaceNormal * 0.02),
				hitPet = true,
				surfaceNormal = surfaceNormal,
				rayOrigin = ray.Origin,
				rayDirection = rayDir,
				wallDistance = wallDistance,
			}
		end
	end

	if wallPos then
		return {
			worldPos = wallPos,
			hitPet = false,
			surfaceNormal = wallNormal,
			rayOrigin = ray.Origin,
			rayDirection = rayDir,
			wallDistance = wallDistance,
		}
	end

	local fallbackDistance = CLIENT_CONTROL_WALL_MIN_CAMERA_DISTANCE
	return {
		worldPos = ray.Origin + (rayDir * fallbackDistance),
		hitPet = false,
		surfaceNormal = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1),
		rayOrigin = ray.Origin,
		rayDirection = rayDir,
		wallDistance = fallbackDistance,
	}
end

local function smoothLocalToolSurface(worldPos, normal, hitPet, dt, refreshHitTime)
	if not hitPet or typeof(worldPos) ~= "Vector3" then
		lastLocalSurfacePos = nil
		lastLocalSurfaceNormal = nil
		lastLocalSurfaceHitAt = nil
		return worldPos, normal
	end
	local surfaceSmoothness = tonumber((currentPet and currentPet:GetAttribute("ShowerToolSurfaceSmoothness")) or CLIENT_TOOL_SURFACE_SMOOTHNESS_HIT) or CLIENT_TOOL_SURFACE_SMOOTHNESS_HIT
	local normalSmoothness = tonumber((currentPet and currentPet:GetAttribute("ShowerToolNormalSmoothness")) or CLIENT_TOOL_NORMAL_SMOOTHNESS_HIT) or CLIENT_TOOL_NORMAL_SMOOTHNESS_HIT
	local maxSurfaceStep = tonumber((currentPet and currentPet:GetAttribute("ShowerToolMaxSurfaceStep")) or CLIENT_TOOL_MAX_SURFACE_STEP) or CLIENT_TOOL_MAX_SURFACE_STEP
	surfaceSmoothness = math.clamp(surfaceSmoothness, 1, 80)
	normalSmoothness = math.clamp(normalSmoothness, 1, 80)
	maxSurfaceStep = math.clamp(maxSurfaceStep, 0.05, 5)

	local frameDt = math.clamp(tonumber(dt) or (1 / 60), 0, 0.1)
	local smoothedPos = worldPos
	if lastLocalSurfacePos then
		local surfaceAlpha = 1 - math.exp(-frameDt * surfaceSmoothness)
		smoothedPos = lastLocalSurfacePos:Lerp(worldPos, surfaceAlpha)
		local step = smoothedPos - lastLocalSurfacePos
		if step.Magnitude > maxSurfaceStep then
			smoothedPos = lastLocalSurfacePos + (step.Unit * maxSurfaceStep)
		end
	end

	local smoothedNormal = getSafeUnit(normal, lastLocalSurfaceNormal or Vector3.new(0, 1, 0))
	if lastLocalSurfaceNormal and lastLocalSurfaceNormal.Magnitude > 1e-4 then
		local targetNormal = smoothedNormal
		if targetNormal:Dot(lastLocalSurfaceNormal.Unit) < -0.35 then
			targetNormal = lastLocalSurfaceNormal
		end
		local normalAlpha = 1 - math.exp(-frameDt * normalSmoothness)
		smoothedNormal = getSafeUnit(lastLocalSurfaceNormal:Lerp(targetNormal, normalAlpha), targetNormal)
	end

	lastLocalSurfacePos = smoothedPos
	lastLocalSurfaceNormal = smoothedNormal
	if refreshHitTime then
		lastLocalSurfaceHitAt = tick()
	end
	return smoothedPos, smoothedNormal
end

local function getRecentLocalSurfaceGrace()
	local grace = tonumber((currentPet and currentPet:GetAttribute("ShowerToolRecentSurfaceGrace")) or CLIENT_TOOL_RECENT_SURFACE_GRACE) or CLIENT_TOOL_RECENT_SURFACE_GRACE
	return math.clamp(grace, 0, 0.5)
end

local function getLocalToolSurfaceRayStickRadius()
	local radius = tonumber((currentPet and currentPet:GetAttribute("ShowerToolSurfaceRayStickRadius")) or CLIENT_TOOL_SURFACE_RAY_STICK_RADIUS) or CLIENT_TOOL_SURFACE_RAY_STICK_RADIUS
	return math.clamp(radius, 0, 5)
end

local function getLocalToolSurfaceRayStickMaxAge()
	local maxAge = tonumber((currentPet and currentPet:GetAttribute("ShowerToolSurfaceRayStickMaxAge")) or CLIENT_TOOL_SURFACE_RAY_STICK_MAX_AGE) or CLIENT_TOOL_SURFACE_RAY_STICK_MAX_AGE
	return math.clamp(maxAge, 0, 1.5)
end

local function getLocalToolMinSurfaceClearance()
	local clearance = tonumber((currentPet and currentPet:GetAttribute("ShowerToolMinSurfaceClearance")) or CLIENT_TOOL_MIN_SURFACE_CLEARANCE) or CLIENT_TOOL_MIN_SURFACE_CLEARANCE
	return math.clamp(clearance, 0, CLIENT_TOOL_SURFACE_OFFSET_MAX)
end

local function keepLocalToolOutsideSurface(desiredPos, surfacePos, surfaceNormal)
	if typeof(desiredPos) ~= "Vector3" or typeof(surfacePos) ~= "Vector3" then return desiredPos end
	local normal = getSafeUnit(surfaceNormal, lastLocalSurfaceNormal or Vector3.new(0, 1, 0))
	local minClearance = getLocalToolMinSurfaceClearance()
	local clearance = (desiredPos - surfacePos):Dot(normal)
	if clearance < minClearance then
		desiredPos += normal * (minClearance - clearance)
	end
	return desiredPos
end

local function clampLocalToolToControlWall(desiredPos, movePoint)
	if typeof(desiredPos) ~= "Vector3" or not movePoint then return desiredPos end
	local rayOrigin = movePoint.rayOrigin
	local rayDirection = movePoint.rayDirection
	local wallDistance = movePoint.wallDistance
	if typeof(rayOrigin) ~= "Vector3" or typeof(rayDirection) ~= "Vector3" or not wallDistance then
		return desiredPos
	end
	local rayDir = getSafeUnit(rayDirection, Vector3.new(0, 0, -1))
	local maxDistance = math.max(CLIENT_CONTROL_WALL_MIN_CAMERA_DISTANCE, wallDistance - CLIENT_TOOL_CONTROL_WALL_PADDING)
	local desiredDistance = (desiredPos - rayOrigin):Dot(rayDir)
	if desiredDistance > maxDistance then
		desiredPos -= rayDir * (desiredDistance - maxDistance)
	end
	return desiredPos
end

local function startCursorTracking()
	clearCursorTracking()
	cursorTrackConn = RunService.RenderStepped:Connect(function(dt)
		if not gui.Enabled then return end
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not isTouchDragging then
			applyLocalPetRub(nil, nil, false)
			if spongeRubbingActive then
				spongeRubbingActive = false
				setLocalToolEffectActive(localSpongeOriginal, false)
			end
			return
		end

		local mousePos = pointerScreenPos or UserInputService:GetMouseLocation()
		local isOverPanel = mousePos and (
			mousePos.X >= panel.AbsolutePosition.X
				and mousePos.X <= (panel.AbsolutePosition.X + panel.AbsoluteSize.X)
				and mousePos.Y >= panel.AbsolutePosition.Y
				and mousePos.Y <= (panel.AbsolutePosition.Y + panel.AbsoluteSize.Y)
		)
		if isOverPanel then
			applyLocalPetRub(nil, nil, false)
			if spongeRubbingActive then
				spongeRubbingActive = false
				setLocalToolEffectActive(localSpongeOriginal, false)
			end
			return
		end

		local now = tick()
		local movePoint = getMovePoint(mousePos)
		if not movePoint then
			applyLocalPetRub(nil, nil, false)
			if spongeRubbingActive then
				spongeRubbingActive = false
				setLocalToolEffectActive(localSpongeOriginal, false)
			end
			return
		end

		local worldPos = movePoint.worldPos
		if typeof(worldPos) ~= "Vector3" then return end

		local activeOriginalTool = getLocalActiveOriginalTool()
		if activeOriginalTool then
			local normal = movePoint.surfaceNormal
			if movePoint.hitPet ~= true and activeOriginalTool == localSpongeOriginal then
				normal = lastLocalToolNormal or (camera and -camera.CFrame.LookVector) or Vector3.new(0, 1, 0)
			elseif typeof(normal) ~= "Vector3" or normal.Magnitude < 1e-4 then
				normal = lastLocalToolNormal or Vector3.new(0, 1, 0)
			end
			normal = normal.Unit
			local toolSurfacePos = worldPos
			local visualHitPet = movePoint.hitPet == true
			if not visualHitPet and activeOriginalTool == localSpongeOriginal and lastLocalSurfacePos then
				local surfaceAge = lastLocalSurfaceHitAt and (now - lastLocalSurfaceHitAt) or math.huge
				local recentGrace = getRecentLocalSurfaceGrace()
				local maxStickAge = getLocalToolSurfaceRayStickMaxAge()
				local isRecentSurface = surfaceAge <= recentGrace
				local rayStickRadius = getLocalToolSurfaceRayStickRadius()
				local rayOrigin = movePoint.rayOrigin
				local rayDirection = movePoint.rayDirection
				local isStillAimingAtSurface = false
				if typeof(rayOrigin) == "Vector3" and typeof(rayDirection) == "Vector3" and rayStickRadius > 0 then
					local rayDir = getSafeUnit(rayDirection, Vector3.new(0, 0, -1))
					local toSurface = lastLocalSurfacePos - rayOrigin
					local closestPoint = rayOrigin + (rayDir * math.max(toSurface:Dot(rayDir), 0))
					isStillAimingAtSurface = (lastLocalSurfacePos - closestPoint).Magnitude <= rayStickRadius
				end
				if isRecentSurface or (isStillAimingAtSurface and surfaceAge <= maxStickAge) then
					visualHitPet = true
					toolSurfacePos = lastLocalSurfacePos
					normal = getSafeUnit(lastLocalSurfaceNormal, normal)
				end
			end
			toolSurfacePos, normal = smoothLocalToolSurface(toolSurfacePos, normal, visualHitPet, dt, movePoint.hitPet == true)
			local surfaceNormalForClearance = normal
			if activeOriginalTool == localShowerHeadOriginal and currentStage ~= 1 then
				if not showerHeadFixedUp then
					local camCf = camera and camera.CFrame or CFrame.new()
					showerHeadFixedRight = camCf.RightVector
					showerHeadFixedUp = (camCf * CLIENT_SHOWERHEAD_ROTATION_OFFSET).UpVector
				end
				normal = showerHeadFixedUp
			end

			local offsetScale = (activeOriginalTool == localShowerHeadOriginal and currentStage ~= 1)
				and CLIENT_SHOWERHEAD_SURFACE_OFFSET_SCALE
				or CLIENT_SPONGE_SURFACE_OFFSET_SCALE
			local toolOffset = math.clamp(
				getLocalToolHalfThickness(activeOriginalTool) * offsetScale,
				CLIENT_TOOL_SURFACE_OFFSET_MIN,
				CLIENT_TOOL_SURFACE_OFFSET_MAX
			)
			local predictedCompression = petSquishRig and math.max(
				petSquishRig.outerCompression or 0,
				getPetSquishTargetCompression(petSquishRig, visualHitPet)
			) or 0
			local visualSurfacePos = toolSurfacePos
			if visualHitPet then
				visualSurfacePos = getSquishedSurfacePosition(toolSurfacePos, surfaceNormalForClearance, true, predictedCompression)
			end
			local desiredPos = visualHitPet and (visualSurfacePos + (normal * toolOffset)) or worldPos
			if visualHitPet then
				desiredPos = keepLocalToolOutsideSurface(desiredPos, toolSurfacePos, surfaceNormalForClearance)
			end
			desiredPos = clampLocalToolToControlWall(desiredPos, movePoint)
			if lastLocalToolPos then
				local hitSmoothness = tonumber((currentPet and currentPet:GetAttribute("ShowerToolHitSmoothness")) or CLIENT_TOOL_MOVE_SMOOTHNESS_HIT) or CLIENT_TOOL_MOVE_SMOOTHNESS_HIT
				local airSmoothness = tonumber((currentPet and currentPet:GetAttribute("ShowerToolAirSmoothness")) or CLIENT_CONTROL_WALL_MOVE_SMOOTHNESS) or CLIENT_CONTROL_WALL_MOVE_SMOOTHNESS
				hitSmoothness = math.clamp(hitSmoothness, 1, 80)
				airSmoothness = math.clamp(airSmoothness, 1, 80)
				local smoothness = visualHitPet and hitSmoothness or airSmoothness
				local alpha = 1 - math.exp(-math.clamp(tonumber(dt) or (1 / 60), 0, 0.1) * smoothness)
				desiredPos = lastLocalToolPos:Lerp(desiredPos, alpha)
				if visualHitPet then
					desiredPos = keepLocalToolOutsideSurface(desiredPos, toolSurfacePos, surfaceNormalForClearance)
				end
				desiredPos = clampLocalToolToControlWall(desiredPos, movePoint)
			end
			lastLocalToolPos = desiredPos
			lastLocalToolNormal = normal
			lastLocalToolHitPet = movePoint.hitPet == true
			moveLocalToolToPosition(activeOriginalTool, desiredPos, normal)
			applyLocalPetRub(toolSurfacePos, surfaceNormalForClearance, visualHitPet)
			local spongeActive = (currentStage == 1 and visualHitPet)
			if spongeActive ~= spongeRubbingActive then
				spongeRubbingActive = spongeActive
				setLocalToolEffectActive(localSpongeOriginal, spongeRubbingActive)
			end
			local showerActive = (currentStage ~= 1)
			if showerActive ~= showerHeadEffectActive then
				showerHeadEffectActive = showerActive
				setLocalToolEffectActive(localShowerHeadOriginal, showerHeadEffectActive)
			end
		end

		local hasMovedEnough = (not lastToolMovePoint) or ((worldPos - lastToolMovePoint).Magnitude >= 0.04)
		if not hasMovedEnough and (now - lastToolMoveFireAt) < 0.06 then
			return
		end
		if (now - lastToolMoveFireAt) < 0.02 then return end
		lastToolMoveFireAt = now
		lastToolMovePoint = worldPos

		showerRemote:FireServer("ToolMove", {
			worldPos = worldPos,
			hitPet = movePoint.hitPet == true,
		})
	end)
end

local defaultRotateButtonColor = Color3.fromRGB(70, 70, 70)
local pressedRotateButtonColor = Color3.fromRGB(110, 110, 110)

local function pulseButton(button)
	if not button then return end
	button.BackgroundColor3 = pressedRotateButtonColor
	local tween = TweenService:Create(
		button,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundColor3 = defaultRotateButtonColor }
	)
	tween:Play()
end

local lastRotateFireAt = 0
local function fireRotate(direction, button)
	if not gui.Enabled then return end
	local now = tick()
	if (now - lastRotateFireAt) < 0.08 then return end
	lastRotateFireAt = now
	pulseButton(button)
	rotateLocalPet(direction)
	showerRemote:FireServer("Rotate", { direction = direction })
end

local function hookRotateButton(button, direction)
	button.MouseButton1Down:Connect(function()
		button.BackgroundColor3 = pressedRotateButtonColor
	end)
	button.MouseButton1Up:Connect(function()
		button.BackgroundColor3 = defaultRotateButtonColor
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = defaultRotateButtonColor
	end)
	button.Activated:Connect(function()
		fireRotate(direction, button)
	end)
	button.MouseButton1Click:Connect(function()
		fireRotate(direction, button)
	end)
end

hookRotateButton(rotateLeft, -1)
hookRotateButton(rotateRight, 1)

exitButton.Activated:Connect(function()
	if gui.Enabled then
		local now = tick()
		if (now - lastExitFireAt) < 0.2 then return end
		lastExitFireAt = now
		showerRemote:FireServer("Exit", {})
		endShowerView()
	end
end)


local function isPointInsideButton(button, screenPos)
	if not button or not button.Visible then return false end
	local pos = button.AbsolutePosition
	local size = button.AbsoluteSize
	return screenPos.X >= pos.X
		and screenPos.X <= (pos.X + size.X)
		and screenPos.Y >= pos.Y
		and screenPos.Y <= (pos.Y + size.Y)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not gui.Enabled then return end
	if not gui.Enabled then return end
	local isPointerPress = input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	if not isPointerPress then return end

	local inputPos = input.Position or UserInputService:GetMouseLocation()
	if not inputPos then return end

	if isPointInsideButton(rotateLeft, inputPos) then
		fireRotate(-1, rotateLeft)
	elseif isPointInsideButton(rotateRight, inputPos) then
		fireRotate(1, rotateRight)
	elseif gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.Touch then
		activeTouch = input
		isTouchDragging = true
		pointerScreenPos = inputPos
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
	end
end)	

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed or not gui.Enabled then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		pointerScreenPos = input.Position
		return
	end
	if input.UserInputType == Enum.UserInputType.Touch and activeTouch and input == activeTouch and isTouchDragging then
		pointerScreenPos = input.Position
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch and activeTouch and input == activeTouch then
		activeTouch = nil
		isTouchDragging = false
		pointerScreenPos = nil
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		pointerScreenPos = nil
	end
end)

showerRemote.OnClientEvent:Connect(function(action, payload)
	payload = payload or {}

	if action == "Start" then
		gui.Enabled = true
		pointerScreenPos = nil
		activeTouch = nil
		isTouchDragging = false
		lastRotateFireAt = 0
		lastToolMoveFireAt = 0
		lastToolMovePoint = nil
		currentStage = tonumber(payload.stage) or 1
		stageLabel.Text = tostring(payload.stageText or "Scrub with Sponge")
		updateBar(payload.progress or 0)
		controlWall = payload.controlWall
		currentPet = payload.pet
		localPetBasePivot = currentPet and currentPet:GetPivot() or nil
		cachePetSquishRig(currentPet)
		setupLocalShowerVisuals(payload)
		task.defer(suppressLocalServerShowerLoop, payload.serverLoopAnimationId)
		task.delay(0.25, suppressLocalServerShowerLoop, payload.serverLoopAnimationId)
		task.delay(0.75, suppressLocalServerShowerLoop, payload.serverLoopAnimationId)
		startShowerView(payload.cameraPart)
		startCursorTracking()
	elseif action == "Progress" then
		if payload.stageText then
			stageLabel.Text = tostring(payload.stageText)
		end
		if payload.serverLoopAnimationId then
			task.defer(suppressLocalServerShowerLoop, payload.serverLoopAnimationId)
			task.delay(0.25, suppressLocalServerShowerLoop, payload.serverLoopAnimationId)
		end
		updateBar(payload.progress or 0)
	elseif action == "Stage" then
		currentStage = tonumber(payload.stage) or currentStage
		lastLocalToolPos = nil
		lastLocalToolNormal = nil
		lastLocalToolRight = nil
		lastLocalSurfacePos = nil
		lastLocalSurfaceHitAt = nil
		lastLocalSurfaceNormal = nil
		showerHeadFixedRight = nil
		showerHeadFixedUp = nil
		updateLocalToolStageVisibility()
		spongeRubbingActive = false
		setLocalToolEffectActive(localSpongeOriginal, false)
		showerHeadEffectActive = (currentStage ~= 1)
		setLocalToolEffectActive(localShowerHeadOriginal, showerHeadEffectActive)
		if payload.stageText then
			stageLabel.Text = tostring(payload.stageText)
		end
		if payload.serverLoopAnimationId then
			task.defer(suppressLocalServerShowerLoop, payload.serverLoopAnimationId)
			task.delay(0.25, suppressLocalServerShowerLoop, payload.serverLoopAnimationId)
		end
		updateBar(payload.progress or 0)
	elseif action == "FoamPatch" then
		local key = payload.key and tostring(payload.key) or nil
		if payload.mode == "Clear" then
			clearLocalFoamPatch(key)
		elseif payload.mode == "ClearAll" then
			clearLocalFoamPatches()
		else
			addLocalFoamPatch(key, payload.localPos, payload.localNormal)
		end
	elseif action == "End" then
		endShowerView()
		pointerScreenPos = nil
		activeTouch = nil
		isTouchDragging = false
		resetPetSquishRig()
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.2)
	endShowerView()
end)

