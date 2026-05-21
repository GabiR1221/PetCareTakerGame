
local PetRigManager = {}
local PhysicsService = game:GetService("PhysicsService")

PetRigManager.PET_COLLISION_GROUP = "Pets"
PetRigManager.PLAYER_COLLISION_GROUP = "Players"

function PetRigManager:EnsureCollisionGroups()
	pcall(function() PhysicsService:RegisterCollisionGroup(self.PET_COLLISION_GROUP) end)
	pcall(function() PhysicsService:RegisterCollisionGroup(self.PLAYER_COLLISION_GROUP) end)
	pcall(function() PhysicsService:CollisionGroupSetCollidable(self.PET_COLLISION_GROUP, self.PLAYER_COLLISION_GROUP, false) end)
	pcall(function() PhysicsService:CollisionGroupSetCollidable(self.PET_COLLISION_GROUP, self.PET_COLLISION_GROUP, false) end)
end


function PetRigManager:SetModelPrimaryIfMissing(model)
	if not model or not model:IsA("Model") then return end
	if model.PrimaryPart then return end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			pcall(function() model.PrimaryPart = d end)
			if model.PrimaryPart then return end
		end
	end
end

function PetRigManager:EnsurePetRig(pet)
	if not pet or not pet:IsA("Model") then return false end
	self:SetModelPrimaryIfMissing(pet)
	self:EnsureCollisionGroups()
	local hrp = pet.PrimaryPart
	if not hrp then return false end

	if hrp.Name ~= "HumanoidRootPart" then
		pcall(function() hrp.Name = "HumanoidRootPart" end)
	end
	pet.PrimaryPart = hrp
	pcall(function() hrp.Anchored = true end)

	for _, obj in ipairs(pet:GetDescendants()) do
		if obj:IsA("Weld") or obj:IsA("WeldConstraint") or obj:IsA("AlignPosition") or 
			obj:IsA("AlignOrientation") or obj:IsA("BodyVelocity") or obj:IsA("LinearVelocity") or 
			obj:IsA("AngularVelocity") or obj:IsA("VectorForce") or obj:IsA("BodyForce") then
			pcall(function() obj:Destroy() end)
		end
	end

	local humanoid = pet:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function()
			pet:SetAttribute("StoredBaseHipHeight", tonumber(humanoid.HipHeight) or 0)
		end)
		humanoid:Destroy()
	end

	local controller = pet:FindFirstChildOfClass("AnimationController")
	if not controller then
		controller = Instance.new("AnimationController")
		controller.Name = "PetAnimationController"
		controller.Parent = pet
	end
	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end

	for _, part in ipairs(pet:GetDescendants()) do
		if part:IsA("BasePart") and part ~= hrp then
			local motorName = "Motor_" .. part.Name
			local existing = hrp:FindFirstChild(motorName)
			if not (existing and existing:IsA("Motor6D")) then
				local m = Instance.new("Motor6D")
				m.Name = motorName
				m.Part0 = hrp
				m.Part1 = part
				m.C0 = hrp.CFrame:ToObjectSpace(part.CFrame)
				m.C1 = CFrame.new()
				m.Parent = hrp
			end
			pcall(function() part.CanCollide = false end)
			pcall(function() part.Massless = true end)
			pcall(function() part.CollisionGroup = self.PET_COLLISION_GROUP end)
		end
	end

	pcall(function() hrp.CanCollide = false end)
	pcall(function() hrp.Massless = true end)
	pcall(function() hrp.CollisionGroup = self.PET_COLLISION_GROUP end)

	pet:SetAttribute("HasPetRig", true)
	return true
end

return PetRigManager
