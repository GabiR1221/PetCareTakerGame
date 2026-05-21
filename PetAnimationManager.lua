local PetAnimationManager = {}
local ServerStorage = game:GetService("ServerStorage")

local function findAnimationContainer(root, name)
	if not root or not name or name == "" then return nil end
	local direct = root:FindFirstChild(name)
	if direct then
		return direct
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == name and (descendant:IsA("Folder") or descendant:IsA("Model")) then
			return descendant
		end
	end

	return nil
end

local ANIM_VELOCITY_THRESHOLD = 0.8
local ANIM_CHECK_INTERVAL = 0.12
local petAnimatorTasks = {}

function PetAnimationManager:Initialize(stateTable)
	self.petState = stateTable or {}
	self:StartAnimationMonitor()
end

function PetAnimationManager:GetAnimationObjectForPet(pet, animationName)
	if not pet or not animationName then return nil end

	local animRoot = ServerStorage:FindFirstChild("PetAnimations")
	if not animRoot then return nil end

	local templateName = pet:GetAttribute("TemplateName")
	local candidateNames = {}
	for _, value in ipairs({templateName, pet.Name}) do
		if typeof(value) == "string" and value ~= "" and not table.find(candidateNames, value) then
			table.insert(candidateNames, value)
		end
	end

	for _, candidateName in ipairs(candidateNames) do
		local container = findAnimationContainer(animRoot, candidateName)
		if container then
			local animObject = container:FindFirstChild(animationName)
			if animObject and animObject:IsA("Animation") then
				return animObject
			end
		end
	end

	local fallback = animRoot:FindFirstChild(animationName)
	if fallback and fallback:IsA("Animation") then
		return fallback
	end

	return nil
end

function PetAnimationManager:SetupAnimatorForPet(pet)
	if not pet or not pet:IsA("Model") then return nil end
	local animatorHost = pet:FindFirstChildOfClass("Humanoid")
	if not animatorHost then
		animatorHost = pet:FindFirstChildOfClass("AnimationController")
		if not animatorHost then
			animatorHost = Instance.new("AnimationController")
			animatorHost.Name = "PetAnimationController"
			animatorHost.Parent = pet
		end
	end

	local animator = animatorHost:FindFirstChildWhichIsA("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animatorHost
	end

	local animObject = self:GetAnimationObjectForPet(pet, "Walk")
	if not animObject then return nil end

	self:TeardownAnimatorForPet(pet)

	local ok, track = pcall(function() return animator:LoadAnimation(animObject) end)
	if not ok or not track then return nil end
	track.Looped = true

	petAnimatorTasks[pet] = petAnimatorTasks[pet] or {}
	petAnimatorTasks[pet].walkTrack = track
	petAnimatorTasks[pet].animatorHost = animatorHost
	petAnimatorTasks[pet].hrp = pet.PrimaryPart
	petAnimatorTasks[pet].animationName = animObject.Name
	petAnimatorTasks[pet].animationSource = animObject:GetFullName()

	return track
end

function PetAnimationManager:TeardownAnimatorForPet(pet)
	local t = petAnimatorTasks[pet]
	if not t then return end
	local track = t.walkTrack
	if track then
		pcall(function()
			if track.IsPlaying then track:Stop() end
		end)
	end
	petAnimatorTasks[pet] = nil
end

function PetAnimationManager:StartAnimationMonitor()
	task.spawn(function()
		while true do
			for pet, state in pairs(petAnimatorTasks) do
				pcall(function()
					if not pet or not pet.Parent then
						if state.walkTrack then
							pcall(function()
								if state.walkTrack.IsPlaying then state.walkTrack:Stop() end
							end)
						end
						petAnimatorTasks[pet] = nil
						return
					end

					local hrp = state.hrp or (pet.PrimaryPart and pet.PrimaryPart:IsA("BasePart") and pet.PrimaryPart)
					local track = state.walkTrack
					if not hrp or not track then return end

					local vel = Vector3.new(0,0,0)
					if hrp.AssemblyLinearVelocity then
						vel = hrp.AssemblyLinearVelocity
					elseif hrp.Velocity then
						vel = hrp.Velocity
					end
					local speed = vel.Magnitude

					if speed >= ANIM_VELOCITY_THRESHOLD then
						if not track.IsPlaying then pcall(function() track:Play() end) end
						local refSpeed = tonumber(pet:GetAttribute("PetMoveSpeed")) or 6
						local speedScale = math.clamp(speed / math.max(refSpeed, 0.0001), 0.3, 2.5)
						pcall(function() track:AdjustSpeed(speedScale) end)
					else
						if track.IsPlaying then pcall(function() track:Stop() end) end
					end
				end)
			end
			task.wait(ANIM_CHECK_INTERVAL)
		end
	end)
end

return PetAnimationManager
