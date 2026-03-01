local PetAnimationManager = {}
local ServerStorage = game:GetService("ServerStorage")

local ANIM_VELOCITY_THRESHOLD = 0.8
local ANIM_CHECK_INTERVAL = 0.12
local petAnimatorTasks = {}

function PetAnimationManager:Initialize(stateTable)
	self.petState = stateTable or {}
	self:StartAnimationMonitor()
end

function PetAnimationManager:SetupAnimatorForPet(pet)
	if not pet or not pet:IsA("Model") then return nil end
	local humanoid = pet:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	local animator = humanoid:FindFirstChildWhichIsA("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animFolder = ServerStorage:FindFirstChild("PetAnimations")
	if not animFolder then return nil end
	local animObject = animFolder:FindFirstChild("Walk")
	if not (animObject and animObject:IsA("Animation")) then return nil end

	local ok, track = pcall(function() return animator:LoadAnimation(animObject) end)
	if not ok or not track then return nil end
	track.Looped = true

	petAnimatorTasks[pet] = petAnimatorTasks[pet] or {}
	petAnimatorTasks[pet].walkTrack = track
	petAnimatorTasks[pet].humanoid = humanoid
	petAnimatorTasks[pet].hrp = pet.PrimaryPart

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
						local humanoid = state.humanoid
						local refSpeed = (humanoid and humanoid.WalkSpeed) or 6
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
