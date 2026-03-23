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

function PetMoodVisualManager:_getPetAnchorPart(petModel)
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

function PetMoodVisualManager:_ensureAttachment(petModel)
	local anchor = self:_getPetAnchorPart(petModel)
	if not anchor then return nil end

	local attachment = anchor:FindFirstChild("MoodAttachment")
	if attachment then return attachment end

	attachment = Instance.new("Attachment")
	attachment.Name = "MoodAttachment"
	attachment.Position = Vector3.new(0, (anchor.Size.Y / 2) + 1.5, 0)
	attachment.Parent = anchor
	return attachment
end

function PetMoodVisualManager:_ensureBillboard(petModel)
	local visuals = self:_ensureVisualFolder(petModel)
	local billboard = visuals:FindFirstChild("MoodBillboard")
	if billboard then return billboard end

	billboard = self.moodBillboardTemplate:Clone()
	billboard.Name = "MoodBillboard"

	local attachment = self:_ensureAttachment(petModel)
	if attachment then
		billboard.Adornee = attachment.Parent
	end

	billboard.Parent = visuals
	return billboard
end

function PetMoodVisualManager:_ensureDirtySmoke(petModel)
	local visuals = self:_ensureVisualFolder(petModel)
	local smoke = visuals:FindFirstChild("DirtySmoke")
	if smoke then return smoke end

	smoke = self.dirtySmokeTemplate:Clone()
	smoke.Name = "DirtySmoke"

	local attachment = self:_ensureAttachment(petModel)
	if attachment then
		smoke.Parent = attachment
	end

	return smoke
end

function PetMoodVisualManager:_ensureHappySmoke(petModel)
	local visuals = self:_ensureVisualFolder(petModel)
	local smoke = visuals:FindFirstChild("HappySmoke")
	if smoke then return smoke end

	smoke = self.happySmokeTemplate:Clone()
	smoke.Name = "HappySmoke"

	local attachment = self:_ensureAttachment(petModel)
	if attachment then
		smoke.Parent = attachment
	end

	return smoke
end

function PetMoodVisualManager:_setSmokeEnabled(smokeObj, isEnabled)
	if not smokeObj then return end

	if smokeObj:IsA("ParticleEmitter") then
		smokeObj.Enabled = isEnabled
	elseif smokeObj:IsA("Smoke") then
		smokeObj.Enabled = isEnabled
	end
end

function PetMoodVisualManager:_setMoodFace(petModel, moodName)
	local billboard = self:_ensureBillboard(petModel)
	if not billboard then return end

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

function PetMoodVisualManager:UpdatePetVisuals(petModel)
	if not petModel or not petModel.Parent then return end

	local state = self.petState[petModel]
	if not state then return end

	local anchor = self:_getPetAnchorPart(petModel)
	if not anchor then return end

	local mood = self:_getMoodFromState(state)

	local dirtySmoke = self:_ensureDirtySmoke(petModel)
	local happySmoke = self:_ensureHappySmoke(petModel)

	self:_setSmokeEnabled(dirtySmoke, mood.dirtySmoke)
	self:_setSmokeEnabled(happySmoke, mood.happySmoke)
	self:_setMoodFace(petModel, mood.face)
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
