-- ServerScriptService.PetMovement
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

local PetMovement = {}

-- Config
local DEFAULT_WANDER_RADIUS = 24
local WANDER_DELAY_MIN = 0.75
local WANDER_DELAY_MAX = 2.25

local WALK_SPEED_MIN = 4.5
local WALK_SPEED_MAX = 7.2

local MOVE_TIMEOUT = 8
local CLOSE_DIST = 1.5
local FLOOR_PADDING = 2

local WALK_ANIM_BASE_SPEED = 6.5
local TURN_RESPONSE = 10 -- smaller = smoother/slower turning
local TURN_MAX_TORQUE = 100000

local IDLE_PAUSE_CHANCE = 0.55
local IDLE_PAUSE_MIN = 0.7
local IDLE_PAUSE_MAX = 2.4

local FLOOR_NAME_CANDIDATES = {
	"Floor",
	"TycoonFloor",
	"Base",
	"Baseplate",
	"Ground",
	"Path",
}

-- pet -> state table
-- state = {
--   wanderRunning, humanoid, hrp, animator, gyro, tracks, mode, ancestryConn,
--   walkTrack, idleTracks, pauseTracks, turnTrack
-- }
local petTasks = {}

local function pointInsidePartXZ(part, worldPos)
	if not part or not worldPos then return false end
	local localPoint = part.CFrame:PointToObjectSpace(worldPos)
	local halfX = part.Size.X * 0.5
	local halfZ = part.Size.Z * 0.5
	return math.abs(localPoint.X) <= halfX and math.abs(localPoint.Z) <= halfZ
end

local function clampPointToPartXZ(part, worldPos, padding)
	padding = padding or 0
	local localPoint = part.CFrame:PointToObjectSpace(worldPos)
	local halfX = math.max(0, (part.Size.X * 0.5) - padding)
	local halfZ = math.max(0, (part.Size.Z * 0.5) - padding)
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -halfX, halfX),
		localPoint.Y,
		math.clamp(localPoint.Z, -halfZ, halfZ)
	)
	return part.CFrame:PointToWorldSpace(clamped)
end

local function findEssentials(model)
	if not model or not model.FindFirstChild then return nil end
	local direct = model:FindFirstChild("Essentials")
	if direct then return direct end
	for _, desc in ipairs(model:GetDescendants()) do
		if string.lower(desc.Name) == "essentials" then
			return desc
		end
	end
	return nil
end

local function getOwnerUserId(inst)
	if not inst or not inst.FindFirstChild then return nil end

	local attr = inst.GetAttribute and (inst:GetAttribute("OwnerId") or inst:GetAttribute("Owner") or inst:GetAttribute("OwnerUserId"))
	if attr ~= nil then
		return tostring(attr)
	end

	for _, nm in ipairs({ "OwnerId", "Owner", "OwnerUserId" }) do
		local child = inst:FindFirstChild(nm)
		if child and child.Value ~= nil then
			return tostring(child.Value)
		end
	end

	return nil
end

local function scoreFloorPart(part)
	if not part or not part:IsA("BasePart") then return -1 end
	return part.Size.X * part.Size.Z
end

local function findFloorPartInEssentials(ess)
	if not ess then return nil end

	for _, candidateName in ipairs(FLOOR_NAME_CANDIDATES) do
		local direct = ess:FindFirstChild(candidateName)
		if direct and direct:IsA("BasePart") then
			return direct
		end
	end

	local best, bestScore = nil, -1
	for _, desc in ipairs(ess:GetDescendants()) do
		if desc:IsA("BasePart") then
			local lower = string.lower(desc.Name)
			if string.find(lower, "floor", 1, true) or string.find(lower, "base", 1, true) or string.find(lower, "ground", 1, true) then
				local score = scoreFloorPart(desc)
				if score > bestScore then
					best = desc
					bestScore = score
				end
			end
		end
	end

	if best then return best end

	for _, desc in ipairs(ess:GetDescendants()) do
		if desc:IsA("BasePart") then
			local score = scoreFloorPart(desc)
			if score > bestScore then
				best = desc
				bestScore = score
			end
		end
	end

	return best
end

local function collectTycoonCandidates()
	local candidates = {}

	local root = workspace:FindFirstChild("Tycoon")
	if root then
		local tycoonsFolder = root:FindFirstChild("Tycoons")
		if tycoonsFolder then
			for _, inst in ipairs(tycoonsFolder:GetChildren()) do
				table.insert(candidates, inst)
			end
		end
	end

	local topTycoons = workspace:FindFirstChild("Tycoons")
	if topTycoons then
		for _, inst in ipairs(topTycoons:GetChildren()) do
			table.insert(candidates, inst)
		end
	end

	return candidates
end

local function resolveWanderBounds(origin, ownerUserId)
	if not origin then return nil end

	local bestFloor, bestDistance = nil, math.huge

	for _, tycoon in ipairs(collectTycoonCandidates()) do
		local ownerId = getOwnerUserId(tycoon)
		if (not ownerUserId) or (ownerId and tostring(ownerId) == tostring(ownerUserId)) then
			local ess = findEssentials(tycoon)
			local floorPart = findFloorPartInEssentials(ess)
			if floorPart then
				local clamped = clampPointToPartXZ(floorPart, origin)
				local d = (Vector3.new(clamped.X, 0, clamped.Z) - Vector3.new(origin.X, 0, origin.Z)).Magnitude
				local inside = pointInsidePartXZ(floorPart, origin)

				if inside then
					return {
						floorPart = floorPart,
						center = floorPart.Position,
					}
				end

				if d < bestDistance then
					bestDistance = d
					bestFloor = floorPart
				end
			end
		end
	end

	if bestFloor and bestDistance <= 60 then
		return {
			floorPart = bestFloor,
			center = bestFloor.Position,
		}
	end

	return nil
end

local function pickIdleLookTarget(anchorPos)
	local angle = math.random() * math.pi * 2
	local dist = 2 + math.random() * 4
	return anchorPos + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
end

local function getRig(pet)
	if not pet then return nil end
	local humanoid = pet:FindFirstChildOfClass("Humanoid")
	local hrp = pet.PrimaryPart
	if not humanoid or not hrp then
		return nil
	end
	return humanoid, hrp
end

local function getAnimator(humanoid)
	if not humanoid then return nil end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

local function findAnimationsFolder(pet)
	if not pet then return nil end

	local directNames = {
		Animations = true,
		Animation = true,
		Anim = true,
		PetAnimations = true,
	}

	for _, child in ipairs(pet:GetChildren()) do
		if child:IsA("Folder") and directNames[child.Name] then
			return child
		end
	end

	local ess = findEssentials(pet)
	if ess then
		for _, child in ipairs(ess:GetChildren()) do
			if child:IsA("Folder") and directNames[child.Name] then
				return child
			end
		end
	end

	for _, desc in ipairs(pet:GetDescendants()) do
		if desc:IsA("Folder") and directNames[desc.Name] then
			return desc
		end
	end

	return nil
end

local function stopTrack(track, fadeTime)
	if track and track.IsPlaying then
		pcall(function()
			track:Stop(fadeTime or 0.12)
		end)
	end
end

local function loadTracks(state)
	if state.tracksLoaded then return end
	state.tracksLoaded = true
	state.tracks = {
		walk = nil,
		idles = {},
		pause = {},
		turn = nil,
	}

	local folder = findAnimationsFolder(state.pet)
	if not folder then
		return
	end

	local animator = state.animator
	if not animator then
		return
	end

	for _, obj in ipairs(folder:GetDescendants()) do
		if obj:IsA("Animation") then
			local n = string.lower(obj.Name)

			if string.find(n, "walk", 1, true) or string.find(n, "run", 1, true) then
				if not state.tracks.walk then
					state.tracks.walk = animator:LoadAnimation(obj)
					state.tracks.walk.Looped = true
				end

			elseif string.find(n, "idle", 1, true) then
				local tr = animator:LoadAnimation(obj)
				tr.Looped = true
				table.insert(state.tracks.idles, tr)

			elseif string.find(n, "pause", 1, true) or string.find(n, "rest", 1, true) or string.find(n, "stand", 1, true) or string.find(n, "wait", 1, true) then
				local tr = animator:LoadAnimation(obj)
				tr.Looped = true
				table.insert(state.tracks.pause, tr)

			elseif string.find(n, "turn", 1, true) then
				if not state.tracks.turn then
					state.tracks.turn = animator:LoadAnimation(obj)
					state.tracks.turn.Looped = false
				end
			end
		end
	end
end

local function ensureGyro(state)
	if state.gyro and state.gyro.Parent then
		return state.gyro
	end

	local hrp = state.hrp
	if not hrp then return nil end

	local gyro = hrp:FindFirstChild("PetTurnGyro")
	if not gyro then
		gyro = Instance.new("BodyGyro")
		gyro.Name = "PetTurnGyro"
		gyro.MaxTorque = Vector3.new(0, TURN_MAX_TORQUE, 0)
		gyro.P = 2500
		gyro.D = 120
		gyro.Parent = hrp
	end

	state.gyro = gyro
	return gyro
end

local function setFacingTarget(state, targetPos)
	if not state or not state.hrp or not targetPos then return end
	local hrp = state.hrp
	local flat = Vector3.new(targetPos.X - hrp.Position.X, 0, targetPos.Z - hrp.Position.Z)
	if flat.Magnitude < 0.05 then return end

	local gyro = ensureGyro(state)
	if gyro then
		gyro.CFrame = CFrame.new(hrp.Position, hrp.Position + flat.Unit)
	end
end

local function playRandomFromList(list, fadeTime)
	if not list or #list == 0 then return nil end
	local tr = list[math.random(1, #list)]
	if tr and not tr.IsPlaying then
		pcall(function()
			tr:Play(fadeTime or 0.15)
		end)
	end
	return tr
end

local function setMode(state, mode, speed)
	if not state then return end
	loadTracks(state)

	if state.mode == mode and mode ~= "Walk" then
		return
	end

	state.mode = mode

	local walk = state.tracks and state.tracks.walk
	local turn = state.tracks and state.tracks.turn

	if mode == "Walk" then
		for _, tr in ipairs(state.tracks.idles or {}) do
			stopTrack(tr, 0.12)
		end
		for _, tr in ipairs(state.tracks.pause or {}) do
			stopTrack(tr, 0.12)
		end
		if turn then
			stopTrack(turn, 0.08)
		end

		if walk then
			if not walk.IsPlaying then
				pcall(function()
					walk:Play(0.12)
				end)
			end
			local animSpeed = math.clamp((speed or WALK_SPEED_MIN) / WALK_ANIM_BASE_SPEED, 0.75, 1.45)
			pcall(function()
				walk:AdjustSpeed(animSpeed)
			end)
		end

	elseif mode == "IdlePause" then
		if walk then
			stopTrack(walk, 0.12)
		end
		for _, tr in ipairs(state.tracks.idles or {}) do
			stopTrack(tr, 0.1)
		end

		local tr = playRandomFromList(state.tracks.pause, 0.15)
		if not tr then
			tr = playRandomFromList(state.tracks.idles, 0.15)
		end
		if tr then
			state.activeIdleTrack = tr
		end

	elseif mode == "Idle" then
		if walk then
			stopTrack(walk, 0.12)
		end
		for _, tr in ipairs(state.tracks.pause or {}) do
			stopTrack(tr, 0.1)
		end

		local tr = playRandomFromList(state.tracks.idles, 0.15)
		if not tr then
			tr = playRandomFromList(state.tracks.pause, 0.15)
		end
		if tr then
			state.activeIdleTrack = tr
		end
	end
end

local function moveToPositionSmooth(state, targetPos, speed)
	if not state or not state.humanoid or not state.hrp or not targetPos then
		return false
	end

	local humanoid = state.humanoid
	local hrp = state.hrp

	speed = speed or WALK_SPEED_MIN
	humanoid.WalkSpeed = speed

	setMode(state, "Walk", speed)
	humanoid:MoveTo(targetPos)

	local startTime = os.clock()
	local lastReissue = 0

	while state.wanderRunning and humanoid.Parent and hrp.Parent do
		local flatTarget = Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z)
		local dist = (flatTarget - hrp.Position).Magnitude

		if dist <= CLOSE_DIST then
			return true
		end

		if os.clock() - startTime > MOVE_TIMEOUT then
			return false
		end

		setFacingTarget(state, targetPos)

		if os.clock() - lastReissue >= 0.35 then
			humanoid:MoveTo(targetPos)
			lastReissue = os.clock()
		end

		task.wait(1 / 30)
	end

	return false
end

local function sampleWanderTarget(anchorPos, radius, bounds)
	local angle = math.random() * math.pi * 2
	local sampledRadius = math.sqrt(math.random()) * radius
	local target = anchorPos + Vector3.new(math.cos(angle) * sampledRadius, 0, math.sin(angle) * sampledRadius)

	if bounds and bounds.floorPart then
		target = clampPointToPartXZ(bounds.floorPart, target, FLOOR_PADDING)
	end

	return target
end

local function doIdlePause(state, anchorPos)
	if not state or not state.wanderRunning or not state.hrp then
		return
	end

	local pauseChance = math.random()
	if pauseChance > IDLE_PAUSE_CHANCE then
		setMode(state, "Idle")
		task.wait(0.1)
		return
	end

	setMode(state, "IdlePause")

	local pauseTime = IDLE_PAUSE_MIN + math.random() * (IDLE_PAUSE_MAX - IDLE_PAUSE_MIN)
	local endTime = os.clock() + pauseTime

	while state.wanderRunning and os.clock() < endTime do
		if math.random() < 0.35 then
			setFacingTarget(state, pickIdleLookTarget(anchorPos))
		end
		task.wait(0.15 + math.random() * 0.15)
	end

	if state.wanderRunning then
		setMode(state, "Idle")
	end
end

local function cleanupState(pet)
	local state = petTasks[pet]
	if not state then return end

	state.wanderRunning = false

	if state.ancestryConn then
		pcall(function()
			state.ancestryConn:Disconnect()
		end)
		state.ancestryConn = nil
	end

	if state.gyro then
		pcall(function()
			state.gyro:Destroy()
		end)
		state.gyro = nil
	end

	if state.tracks then
		if state.tracks.walk then stopTrack(state.tracks.walk, 0.05) end
		for _, tr in ipairs(state.tracks.idles or {}) do stopTrack(tr, 0.05) end
		for _, tr in ipairs(state.tracks.pause or {}) do stopTrack(tr, 0.05) end
		if state.tracks.turn then stopTrack(state.tracks.turn, 0.05) end
	end

	petTasks[pet] = nil
end

function PetMovement.StopWandering(pet)
	if not pet then return end
	cleanupState(pet)

	pcall(function()
		local humanoid = pet:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:Move(Vector3.new(0, 0, 0), true)
		end
	end)
end

local function startWanderingInternal(pet, spawnPos, options)
	if not pet or not pet.Parent then return end

	options = options or {}

	local humanoid, hrp = getRig(pet)
	if not humanoid or not hrp then return end

	local state = petTasks[pet]
	if state and state.wanderRunning then
		return
	end

	state = state or {}
	state.pet = pet
	state.humanoid = humanoid
	state.hrp = hrp
	state.animator = getAnimator(humanoid)
	state.wanderRunning = true
	state.mode = "Idle"
	state.tracksLoaded = false

	petTasks[pet] = state

	loadTracks(state)
	setMode(state, "Idle")

	local wanderRadius = tonumber(options.wanderRadius) or DEFAULT_WANDER_RADIUS
	local ownerUserId = options.ownerUserId

	local bounds = nil
	if ownerUserId ~= nil then
		bounds = resolveWanderBounds(spawnPos, ownerUserId)
	end
	if bounds and bounds.floorPart then
		spawnPos = clampPointToPartXZ(bounds.floorPart, spawnPos, FLOOR_PADDING)
	end

	state.ancestryConn = pet.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cleanupState(pet)
		end
	end)

	task.spawn(function()
		while petTasks[pet] and petTasks[pet].wanderRunning and pet and pet.Parent do
			local currentState = petTasks[pet]
			if not currentState then
				break
			end

			local target = sampleWanderTarget(spawnPos, wanderRadius, bounds)
			local moveSpeed = WALK_SPEED_MIN + (math.random() * (WALK_SPEED_MAX - WALK_SPEED_MIN))

			local path = PathfindingService:CreatePath({
				AgentRadius = 2,
				AgentHeight = 3,
				AgentCanJump = true,
				WaypointSpacing = 2,
			})

			local success = pcall(function()
				path:ComputeAsync(hrp.Position, target)
			end)

			if success and path.Status == Enum.PathStatus.Success then
				local waypoints = path:GetWaypoints()

				for i, wp in ipairs(waypoints) do
					if not (petTasks[pet] and petTasks[pet].wanderRunning) or not pet.Parent then
						break
					end

					local goal = Vector3.new(wp.Position.X, hrp.Position.Y, wp.Position.Z)
					if bounds and bounds.floorPart then
						goal = clampPointToPartXZ(bounds.floorPart, goal, FLOOR_PADDING)
					end

					local reached = moveToPositionSmooth(currentState, goal, moveSpeed)

					if wp.Action == Enum.PathWaypointAction.Jump then
						pcall(function()
							humanoid.Jump = true
						end)
					end

					if not reached then
						break
					end

					task.wait(0.03 + math.random() * 0.08)
				end
			else
				if bounds and bounds.floorPart then
					target = clampPointToPartXZ(bounds.floorPart, target, FLOOR_PADDING)
				end
				moveToPositionSmooth(currentState, target, moveSpeed)
			end

			doIdlePause(currentState, spawnPos)

			local pause = WANDER_DELAY_MIN + math.random() * (WANDER_DELAY_MAX - WANDER_DELAY_MIN)
			task.wait(pause)
		end

		cleanupState(pet)
	end)
end

-- StartWandering(pet, originVector3?, wanderRadius?, ownerUserId?)
function PetMovement.StartWandering(pet, origin, wanderRadius, ownerUserId)
	if not pet then return end

	local spawnPos
	if origin and typeof(origin) == "Vector3" then
		spawnPos = origin
	elseif pet.PrimaryPart and pet.PrimaryPart:IsA("BasePart") then
		spawnPos = pet.PrimaryPart.Position
	else
		spawnPos = Vector3.new(0, 5, 0)
	end

	local humanoid, hrp = getRig(pet)
	if not humanoid or not hrp then
		return
	end

	startWanderingInternal(pet, spawnPos, {
		wanderRadius = tonumber(wanderRadius) or DEFAULT_WANDER_RADIUS,
		ownerUserId = ownerUserId,
	})

	if not pet:GetAttribute("__petMovementHasAncestryHook") then
		pcall(function()
			pet:SetAttribute("__petMovementHasAncestryHook", true)
		end)

		pet.AncestryChanged:Connect(function(_, parent)
			if not parent then
				PetMovement.StopWandering(pet)
			end
		end)
	end
end

return PetMovement
