local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetMoodVisualManager = {}

function PetMoodVisualManager:Initialize(stateTable)
	self.petState = stateTable or {}

	self.assetsFolder = ReplicatedStorage:WaitForChild("PetVisualAssets")
	self.dirtySmokeTemplate = self.assetsFolder:WaitForChild("DirtySmoke")
	self.happySmokeTemplate = self.assetsFolder:WaitForChild("HappySmoke")
	self.moodBillboardTemplate = self.assetsFolder:WaitForChild("MoodBillboard")

	self.faceImageIds = {
		Happy = "rbxassetid://PUT_HAPPY_FACE_IMAGE_ID_HERE",
		Nasty = "rbxassetid://PUT_NASTY_FACE_IMAGE_ID_HERE",
		Sad = "rbxassetid://PUT_SAD_FACE_IMAGE_ID_HERE",
		Neutral = "rbxassetid://PUT_NEUTRAL_FACE_IMAGE_ID_HERE",
	}

	self:_startLoop()
	return self
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

	local facePart = self:_getDefaultPetAnchorPart(petModel)
	if not facePart then return end

	local faceAttachment = self:_ensureAttachmentOnPart(
		facePart,
		"MoodFaceAttachment",
		(facePart.Size.Y / 2) + 1
	)

	if billboard.Adornee ~= faceAttachment.Parent then
		billboard.Adornee = faceAttachment.Parent
	end

	local imageLabel = billboard:FindFirstChild("FaceImage", true)
	if not imageLabel or not imageLabel:IsA("ImageLabel") then return end

	local imageId = self.faceImageIds[moodName] or self.faceImageIds.Neutral
	imageLabel.Image = imageId
	billboard.Enabled = true
end

function PetMoodVisualManager:_getMoodFromState(state)
	local dirtiness = math.clamp(tonumber(state.dirtiness) or 0, 0, 100)
	local wetness = math.clamp(tonumber(state.wetness) or 0, 0, 100)
	local hunger = math.clamp(tonumber(state.hunger) or 100, 0, 100)

	local cleanliness = 100 - dirtiness
	local dryness = 100 - wetness
	local fullness = hunger

	local isDirty = dirtiness >= 80
	local isHappy = cleanliness >= 80 and dryness >= 80 and fullness >= 80

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

	if cleanliness < 40 or dryness < 40 or fullness < 40 then
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
	local alpha = (d - 10) / 90
	return math.clamp(1 - alpha, 0, 1)
end

function PetMoodVisualManager:_applyDirtVisuals(petModel, state)
	if not petModel or not state then return end
	if state.location == "shower" then return end
	local dirtFolder = petModel:FindFirstChild("Dirt")
	if not dirtFolder then return end

	local targetTransparency = self:_getDirtTransparencyFromDirtiness(state.dirtiness)

	for _, item in ipairs(dirtFolder:GetDescendants()) do
		if item:IsA("BasePart") then
			local baseTransparency = item:GetAttribute("BaseDirtTransparency")
			if baseTransparency == nil then
				baseTransparency = item.Transparency
				item:SetAttribute("BaseDirtTransparency", baseTransparency)
			end
			item.Transparency = math.clamp(math.max(baseTransparency, targetTransparency), 0, 1)
		elseif item:IsA("Decal") or item:IsA("Texture") then
			item.Transparency = targetTransparency
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
				if petModel and petModel.Parent and state and not state.wild then
					pcall(function()
						self:UpdatePetVisuals(petModel)
					end)
				end
			end

			self:_cleanupRemovedPets()
			task.wait(0.5)
		end
	end)
end

return PetMoodVisualManager
