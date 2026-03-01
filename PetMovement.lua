-- ServerScriptService.PetMovement
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

local PetMovement = {}

-- Config
local WANDER_RADIUS = 40
local WANDER_DELAY_MIN = 1.5
local WANDER_DELAY_MAX = 4.0
local WALK_SPEED = 6
local MOVE_TIMEOUT = 8
local CLOSE_DIST = 1.5

-- internal state (petModel -> control table)
local petTasks = {} -- pet -> { wanderRunning = bool, wanderThread = coroutine, humanoid = Instance, hrp = BasePart }

local function smoothFaceTowards(part, targetPosition, tFrac)
	if not part or not targetPosition then return end
	local cur = part.CFrame
	local dir = (Vector3.new(targetPosition.X, cur.Position.Y, targetPosition.Z) - cur.Position)
	if dir.Magnitude <= 0.001 then return end
	local lookCFrame = CFrame.new(cur.Position, cur.Position + dir.Unit)
	part.CFrame = cur:Lerp(lookCFrame, math.clamp(tFrac, 0, 1))
end

local function moveToPositionSmooth(humanoid, hrp, targetPos, speed)
	if not humanoid or not hrp or not targetPos then return false end
	speed = speed or WALK_SPEED
	humanoid.WalkSpeed = speed

	local startTime = tick()
	humanoid:MoveTo(targetPos)
	while humanoid.Parent and hrp.Parent do
		local dist = (Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z) - hrp.Position).Magnitude
		if dist <= CLOSE_DIST then return true end
		if tick() - startTime > MOVE_TIMEOUT then return false end
		humanoid:MoveTo(targetPos)
		smoothFaceTowards(hrp, targetPos, 0.18)
		RunService.Heartbeat:Wait()
	end
	return false
end

-- stop wandering (safe)
function PetMovement.StopWandering(pet)
	if not pet then return end
	local t = petTasks[pet]
	if not t then return end
	t.wanderRunning = false
	-- let the thread naturally exit; then clean up table
	pcall(function() petTasks[pet] = nil end)
end

local function startWanderingInternal(pet, spawnPos)
	if not pet or not pet.Parent then return end
	local humanoid = pet:FindFirstChildOfClass("Humanoid")
	local hrp = pet.PrimaryPart
	if not humanoid or not hrp then return end

	petTasks[pet] = petTasks[pet] or {}
	if petTasks[pet].wanderRunning then return end
	petTasks[pet].wanderRunning = true
	petTasks[pet].humanoid = humanoid
	petTasks[pet].hrp = hrp

	local thread = coroutine.create(function()
		while petTasks[pet] and petTasks[pet].wanderRunning and pet and pet.Parent do
			-- choose a random target around spawnPos
			local angle = math.random() * math.pi * 2
			local radius = math.random() * WANDER_RADIUS
			local target = spawnPos + Vector3.new(math.cos(angle)*radius, 0, math.sin(angle)*radius)

			local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 3, AgentCanJump = true })
			pcall(function() path:ComputeAsync(hrp.Position, target) end)

			if path.Status == Enum.PathStatus.Success then
				local waypoints = path:GetWaypoints()
				for _, wp in ipairs(waypoints) do
					if not (petTasks[pet] and petTasks[pet].wanderRunning) or not pet.Parent then break end
					local goal = Vector3.new(wp.Position.X, hrp.Position.Y, wp.Position.Z)
					humanoid:MoveTo(goal)
					local reached = moveToPositionSmooth(humanoid, hrp, goal, WALK_SPEED)
					if not reached then break end
					task.wait(0.06)
				end
			else
				humanoid:MoveTo(target)
				moveToPositionSmooth(humanoid, hrp, target, WALK_SPEED)
			end

			local pause = math.random() * (WANDER_DELAY_MAX - WANDER_DELAY_MIN) + WANDER_DELAY_MIN
			task.wait(pause)
		end
		-- cleanup when thread finishes
		pcall(function() petTasks[pet] = nil end)
	end)

	petTasks[pet].wanderThread = thread
	coroutine.resume(thread)
end

-- StartWandering(pet, originVector3?)
-- originVector3 optional; if nil, module will attempt to use pet.PrimaryPart.Position
function PetMovement.StartWandering(pet, origin)
	if not pet then return end
	-- compute spawnPos fallback
	local spawnPos = nil
	if origin and typeof(origin) == "Vector3" then
		spawnPos = origin
	elseif pet.PrimaryPart and pet.PrimaryPart:IsA("BasePart") then
		spawnPos = pet.PrimaryPart.Position
	else
		-- best-effort fallback
		spawnPos = Vector3.new(0, 5, 0)
	end

	-- ensure humanoid + primary present
	local humanoid = pet:FindFirstChildOfClass("Humanoid")
	local hrp = pet.PrimaryPart
	if not humanoid or not hrp then
		-- cannot start wandering without humanoid and hrp
		return
	end

	startWanderingInternal(pet, spawnPos)

	-- ensure we stop if pet gets removed
	if not pet:GetAttribute("__petMovementHasAncestryHook") then
		pcall(function()
			pet:SetAttribute("__petMovementHasAncestryHook", true)
		end)
		pet.AncestryChanged:Connect(function(_, parent)
			if not parent then
				-- clean up on removal
				PetMovement.StopWandering(pet)
			end
		end)
	end
end

return PetMovement
