local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetMoodVisualManager = {}

local PLACEHOLDER_TOKEN = "PUT_"

local function normalizeImageId(value)
	if value == nil then return nil end
	local s = tostring(value)
	if s == "" then return nil end
	if string.find(s, PLACEHOLDER_TOKEN, 1, true) then
		return nil
	end
	if string.find(s, "rbxassetid://", 1, true) == 1 then
		return s
	end
	if string.match(s, "^%d+$") then
		return "rbxassetid://" .. s
	end
	return nil
end

function PetMoodVisualManager.Initialize(selfOrStateTable, maybeStateTable)
	local manager = PetMoodVisualManager
	local stateTable = maybeStateTable or selfOrStateTable
	if stateTable == manager then
		stateTable = {}
	end

	manager.petState = stateTable or {}

	manager.assetsFolder = ReplicatedStorage:WaitForChild("PetVisualAssets")
	manager.dirtySmokeTemplate = manager.assetsFolder:WaitForChild("DirtySmoke")
	manager.happySmokeTemplate = manager.assetsFolder:WaitForChild("HappySmoke")
	manager.moodBillboardTemplate = manager.assetsFolder:WaitForChild("MoodBillboard")

	manager.faceImageIds = {
		Happy = nil,
		Nasty = nil,
		Sad = nil,
		Neutral = nil,
	}

	local configuredIds = manager.moodBillboardTemplate:GetAttribute("FaceImageIds")
	if type(configuredIds) == "string" and configuredIds ~= "" then
		for pair in string.gmatch(configuredIds, "([^;]+)") do
			local mood, id = string.match(pair, "^%s*([%w_]+)%s*=%s*(.-)%s*$")
			if mood and id then
				manager.faceImageIds[mood] = normalizeImageId(id)
			end
		end
	end

	for moodName, attrName in pairs({
		Happy = "860151953",
		Nasty = "756193742",
		Sad = "9357787270",
		Neutral = "7603175993",
		}) do
		local attrValue = manager.moodBillboardTemplate:GetAttribute(attrName)
		local normalized = normalizeImageId(attrValue)
		if normalized then
			manager.faceImageIds[moodName] = normalized
		end
	end

	manager:_startLoop()
	return manager
end

function PetMoodVisualManager:_getDefaultPetAnchorPart(petModel)
	if not petModel or not petModel:IsA("Model") then return nil end
	return petModel.PrimaryPart or petModel:FindFirstChildWhichIsA("BasePart")
end

function PetMoodVisualManager:_ensureVisualFolder(petModel)
	local folder = petModel:FindFirstChild("PetVisuals")
	if folder then return folder end

	folder = Instance.new("Folder")
	folder.Name = "PetVisuals"
	folder.Parent = petModel
	return folder
end

function PetMoodVisualManager:_ensureAttachmentOnPart(part, attachmentName, yOffset)
	if not part or not part:IsA("BasePart") then return nil end

	local attachment = part:FindFirstChild(attachmentName)
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end

	attachment = Instance.new("Attachment")
	attachment.Name = attachmentName
	attachment.Position = Vector3.new(0, yOffset or 0, 0)
	attachment.Parent = part
	return attachment
end

function PetMoodVisualManager:_ensurePartEffect(petModel, effectName, template, offset)
	local visuals = self:_ensureVisualFolder(petModel)
	local existing = visuals:FindFirstChild(effectName)
	if existing then
		return existing
	end

	local primary = self:_getDefaultPetAnchorPart(petModel)
	if not primary then return nil end

	local clone = template:Clone()
	clone.Name = effectName
	clone.Parent = visuals

	if clone:IsA("BasePart") then
		clone.Anchored = false
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CanQuery = false
		clone.Massless = true
		clone.Transparency = 1

		clone.CFrame = primary.CFrame * (offset or CFrame.new())

		local weld = Instance.new("WeldConstraint")
		weld.Name = effectName .. "Weld"
		weld.Part0 = clone
		weld.Part1 = primary
		weld.Parent = clone
	end

	return clone
end

function PetMoodVisualManager:_ensureDirtySmoke(petModel)
	return self:_ensurePartEffect(petModel, "DirtySmoke", self.dirtySmokeTemplate, CFrame.new(0, 2, 0))
end

function PetMoodVisualManager:_ensureHappySmoke(petModel)
	return self:_ensurePartEffect(petModel, "HappySmoke", self.happySmokeTemplate, CFrame.new(0, 2.5, 0))
end

function PetMoodVisualManager:_ensureBillboard(petModel)
	local visuals = self:_ensureVisualFolder(petModel)
	local billboard = visuals:FindFirstChild("MoodBillboard")
	if billboard then
		return billboard
	end

	billboard = self.moodBillboardTemplate:Clone()
	billboard.Name = "MoodBillboard"
	billboard.Parent = visuals
	return billboard
end

function PetMoodVisualManager:_setSmokeEnabled(smokeObj, isEnabled)
	if not smokeObj then return end

	local function setEffectEnabled(obj)
		if obj:IsA("ParticleEmitter") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
			obj.Enabled = isEnabled
		end
	end

	setEffectEnabled(smokeObj)
	for _, d in ipairs(smokeObj:GetDescendants()) do
		setEffectEnabled(d)
	end
end

function PetMoodVisualManager:_setMoodFace(petModel, moodName)
	local billboard = self:_ensureBillboard(petModel)
	if not billboard then return end
	billboard.Enabled = true

	local facePart = self:_getDefaultPetAnchorPart(petModel)
	if not facePart then return end

	local faceAttachment = self:_ensureAttachmentOnPart(
		facePart,
		"MoodFaceAttachment",
		(facePart.Size.Y / 2) + 1
	)

	if billboard.Adornee ~= faceAttachment then
		billboard.Adornee = faceAttachment
	end

	local imageLabel = billboard:FindFirstChild("FaceImage", true)
	if not imageLabel or not imageLabel:IsA("ImageLabel") then
		imageLabel = billboard:FindFirstChildWhichIsA("ImageLabel", true)
	end

	local imageId = self.faceImageIds[moodName] or self.faceImageIds.Neutral
	if imageLabel and not imageId then
		local specific = imageLabel:GetAttribute(moodName .. "ImageId")
		local neutral = imageLabel:GetAttribute("NeutralImageId")
		imageId = normalizeImageId(specific) or normalizeImageId(neutral)
	end

	local fallbackText = billboard:FindFirstChild("FaceFallbackText", true)
	if not fallbackText or not fallbackText:IsA("TextLabel") then
		fallbackText = billboard:FindFirstChildWhichIsA("TextLabel", true)
	end

	if imageLabel and imageId then
		imageLabel.Visible = true
		imageLabel.Image = imageId
		if fallbackText and fallbackText:IsA("TextLabel") then
			fallbackText.Visible = false
		end
		return
	end

	if imageLabel and imageLabel:IsA("ImageLabel") then
		imageLabel.Image = ""
		imageLabel.Visible = false
	end
	if fallbackText and fallbackText:IsA("TextLabel") then
		fallbackText.Visible = true
		fallbackText.Text = moodName
	else
		local createdText = Instance.new("TextLabel")
		createdText.Name = "FaceFallbackText"
		createdText.BackgroundTransparency = 1
		createdText.Size = UDim2.fromScale(1, 1)
		createdText.TextScaled = true
		createdText.TextColor3 = Color3.fromRGB(255, 255, 255)
		createdText.TextStrokeTransparency = 0.5
		createdText.Font = Enum.Font.SourceSansBold
		createdText.Text = moodName
		createdText.Parent = billboard
	end
end

function PetMoodVisualManager:_getMoodFromState(state)
	local dirtiness = math.clamp(tonumber(state.dirtiness) or 0, 0, 100)
	local hunger = math.clamp(tonumber(state.hunger) or 100, 0, 100)

	local cleanliness = 100 - dirtiness
	local fullness = hunger

	local isDirty = dirtiness >= 80
	local isHappy = cleanliness >= 80 and fullness >= 80

	if isDirty then
		return {
			face = "Nasty",
			dirtySmoke = true,
			happySmoke = false,
		}
	end

	if isHappy then
		return {
			face = "Happy",
			dirtySmoke = false,
			happySmoke = true,
		}
	end

	if cleanliness < 40 or fullness < 40 then
		return {
			face = "Sad",
			dirtySmoke = false,
			happySmoke = false,
		}
	end

	return {
		face = "Neutral",
		dirtySmoke = false,
		happySmoke = false,
	}
end

function PetMoodVisualManager:_getDirtTransparencyFromDirtiness(dirtiness)
	local d = math.clamp(tonumber(dirtiness) or 0, 0, 100)
	if d <= 10 then
		return 1
	end
	local normalized = (d - 10) / 90
	local visibilityBoost = normalized ^ 0.6
	return math.clamp(1 - visibilityBoost, 0, 1)
end

local DIRT_DECAL_NAME_MARKERS = { "dirt", "dirty", "mud", "stain", "grime", "soil" }
local DIRT_DECAL_EXCLUDE_MARKERS = { "face", "eye", "mouth", "smile", "cheek", "blush", "sad", "happy" }

local function nameHasAnyMarker(inst, markers)
	local name = string.lower(tostring((inst and inst.Name) or ""))
	for _, marker in ipairs(markers) do
		if string.find(name, marker, 1, true) then
			return true
		end
	end
	return false
end

local function hierarchyHasAnyNameMarker(inst, markers)
	local current = inst
	while current do
		if nameHasAnyMarker(current, markers) then
			return true
		end
		current = current.Parent
	end
	return false
end

function PetMoodVisualManager:_isDirtDecalVisual(item, dirtFolder)
	if not item or not (item:IsA("Decal") or item:IsA("Texture")) then
		return false
	end

	local isInDirtFolder = dirtFolder and item:IsDescendantOf(dirtFolder)
	local isMarked = item:GetAttribute("ShowerDirt") == true or item:GetAttribute("IsDirt") == true or item:GetAttribute("CleanInShower") == true
	local isCosmetic = nameHasAnyMarker(item, DIRT_DECAL_EXCLUDE_MARKERS)
	local hasDirtName = hierarchyHasAnyNameMarker(item, DIRT_DECAL_NAME_MARKERS)
	local parent = item.Parent
	local wasDetected = item:GetAttribute("DetectedMeshDirtDecal") == true
	local isHiddenMeshDecal = parent and parent:IsA("BasePart") and item.Transparency >= 0.95 and not isCosmetic
	if isHiddenMeshDecal then
		item:SetAttribute("DetectedMeshDirtDecal", true)
	end

	return isInDirtFolder or isMarked or wasDetected or (hasDirtName and not isCosmetic) or isHiddenMeshDecal
end

function PetMoodVisualManager:_resolveBaseDirtTransparency(item)
	if not item or not (item:IsA("BasePart") or item:IsA("Decal") or item:IsA("Texture")) then
		return 0
	end

	local baseTransparency = item:GetAttribute("BaseDirtTransparency")
	if baseTransparency ~= nil then
		return math.clamp(tonumber(baseTransparency) or 0, 0, 1)
	end

	baseTransparency = math.clamp(item.Transparency, 0, 1)
	if baseTransparency >= 0.99 then
		local configuredBase = item:GetAttribute("DirtyBaseTransparency")
		if configuredBase ~= nil then
			baseTransparency = math.clamp(tonumber(configuredBase) or 0, 0, 1)
		else
			baseTransparency = 0
		end
	end

	item:SetAttribute("BaseDirtTransparency", baseTransparency)
	return baseTransparency
end


function PetMoodVisualManager:_applyDirtVisuals(petModel, state)
	if not petModel or not state then return end
	if state.location == "shower" then return end
	local dirtFolder = petModel:FindFirstChild("Dirt")

	local targetTransparency = self:_getDirtTransparencyFromDirtiness(state.dirtiness)

	if dirtFolder then
		for _, item in ipairs(dirtFolder:GetDescendants()) do
			if item:IsA("BasePart") then
				local baseTransparency = self:_resolveBaseDirtTransparency(item)
				item.Transparency = math.clamp(math.max(baseTransparency, targetTransparency), 0, 1)
			end
		end
	end

	for _, item in ipairs(petModel:GetDescendants()) do
		if self:_isDirtDecalVisual(item, dirtFolder) then
			item.Transparency = targetTransparency
		elseif item:IsA("BasePart") and dirtFolder and item:IsDescendantOf(dirtFolder) then
			local baseTransparency = self:_resolveBaseDirtTransparency(item)
			item.Transparency = math.clamp(math.max(baseTransparency, targetTransparency), 0, 1)
		end
	end
end


function PetMoodVisualManager:UpdatePetVisuals(petModel)
	if not petModel or not petModel.Parent then return end

	local state = self.petState[petModel]
	if not state then return end

	local dirtySmoke = self:_ensureDirtySmoke(petModel)
	local happySmoke = self:_ensureHappySmoke(petModel)

	local mood = self:_getMoodFromState(state)

	self:_setSmokeEnabled(dirtySmoke, mood.dirtySmoke)
	self:_setSmokeEnabled(happySmoke, mood.happySmoke)
	self:_setMoodFace(petModel, mood.face)
	self:_applyDirtVisuals(petModel, state)
end

function PetMoodVisualManager:_cleanupRemovedPets()
	for petModel, _ in pairs(self.petState) do
		if petModel and not petModel.Parent then
			self.petState[petModel] = nil
		end
	end
end

function PetMoodVisualManager:_startLoop()
	if self._loopStarted then return end
	self._loopStarted = true

	task.spawn(function()
		while true do
			for petModel, state in pairs(self.petState) do
				if petModel and petModel.Parent and state and not state.wild and state.location ~= "inventory" then
					pcall(function()
						self:UpdatePetVisuals(petModel)
					end)
				end
			end

			self:_cleanupRemovedPets()
			task.wait(5)
		end
	end)
end

return PetMoodVisualManager
