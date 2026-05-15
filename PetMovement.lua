-- ServerScriptService.PetMovement
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")

local PetMovement = {}

-- Config
local DEFAULT_WANDER_RADIUS = 24
local WANDER_DELAY_MIN = 0.75
local WANDER_DELAY_MAX = 2.25

local WALK_SPEED_MIN = 4.5
local WALK_SPEED_MAX = 7.2

local MOVE_TIMEOUT = 8
local CLOSE_DIST = 1.5
local FLOOR_PADDING = 1.8
local OBSTACLE_CLEARANCE = Vector3.new(2.8, 3.4, 2.8)
local TARGET_SAMPLE_ATTEMPTS = 8

local WALK_ANIM_BASE_SPEED = 6.5
local TURN_RESPONSE = 10 -- smaller = smoother/slower turning
local TURN_MAX_TORQUE = 100000

local IDLE_PAUSE_CHANCE = 0.55
local IDLE_PAUSE_MIN = 0.7
local IDLE_PAUSE_MAX = 2.4

local FLEE_TRIGGER_RANGE = 20
local FLEE_COOLDOWN = 0.35
local FLEE_MIN_DURATION = 1.5
local FLEE_MAX_DURATION = 2.8
local FLEE_START_MAX_WAIT = 0.3
local FLEE_SPEED_MIN = 6.5
local FLEE_SPEED_MAX = 10
local FLEE_INTERRUPT_CHECK_INTERVAL = 0.20
local OWNED_MOVE_POLL_INTERVAL = 0.10
local WILD_MOVE_POLL_INTERVAL = 0.06
local MOVE_REISSUE_INTERVAL = 0.70

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

local function optimizeRuntimePetParts(pet)
	if not pet or not pet.GetDescendants then return end
	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanTouch = false
			d.CanCollide = false
			d.CastShadow = false
			pcall(function()
				d:SetNetworkOwner(nil)
			end)
		end
	end
end

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
		fleeStart = {},
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

			elseif string.find(n, "flee", 1, true)
				or string.find(n, "fear", 1, true)
				or string.find(n, "scare", 1, true)
				or string.find(n, "startle", 1, true) then
				local tr = animator:LoadAnimation(obj)
				tr.Looped = false
				table.insert(state.tracks.fleeStart, tr)
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

local function moveToPositionSmooth(state, targetPos, speed, interruptCheck)
	if not state or not state.humanoid or not state.hrp or not targetPos then
		return false, nil
	end

	local humanoid = state.humanoid
	local hrp = state.hrp

	speed = speed or WALK_SPEED_MIN
	humanoid.WalkSpeed = speed

	setMode(state, "Walk", speed)
	humanoid:MoveTo(targetPos)

	local startTime = os.clock()
	local lastReissue = 0
	local lastInterruptCheck = 0

	while state.wanderRunning and humanoid.Parent and hrp.Parent do
		local flatTarget = Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z)
		local dist = (flatTarget - hrp.Position).Magnitude

		if dist <= CLOSE_DIST then
			return true, nil
		end

		if os.clock() - startTime > MOVE_TIMEOUT then
			return false, "timeout"
		end

		if interruptCheck and (os.clock() - lastInterruptCheck) >= FLEE_INTERRUPT_CHECK_INTERVAL then
			lastInterruptCheck = os.clock()
			local shouldInterrupt, reason = interruptCheck()
			if shouldInterrupt then
				humanoid:Move(Vector3.zero, true)
				return false, reason or "interrupt"
			end
		end

		setFacingTarget(state, targetPos)

		if os.clock() - lastReissue >= MOVE_REISSUE_INTERVAL then
			humanoid:MoveTo(targetPos)
			lastReissue = os.clock()
		end

		local pollInterval = state.pet:GetAttribute("WildPet") == true and WILD_MOVE_POLL_INTERVAL or OWNED_MOVE_POLL_INTERVAL
		task.wait(pollInterval)
	end

	return false, "stopped"
end

local function sampleWanderTarget(anchorPos, radius, bounds)
	local floorPart = bounds and bounds.floorPart or nil
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	if floorPart then
		overlapParams.FilterDescendantsInstances = { floorPart }
	end

	for _ = 1, TARGET_SAMPLE_ATTEMPTS do
		local angle = math.random() * math.pi * 2
		local sampledRadius = math.sqrt(math.random()) * radius
		local target = anchorPos + Vector3.new(math.cos(angle) * sampledRadius, 0, math.sin(angle) * sampledRadius)

		if floorPart then
			target = clampPointToPartXZ(floorPart, target, FLOOR_PADDING)
		end

		local clearanceCenter = target + Vector3.new(0, OBSTACLE_CLEARANCE.Y * 0.5, 0)
		local nearby = workspace:GetPartBoundsInBox(CFrame.new(clearanceCenter), OBSTACLE_CLEARANCE, overlapParams)
		local blocked = false
		for _, part in ipairs(nearby) do
			if part and part.CanCollide and (not floorPart or part ~= floorPart) then
				blocked = true
				break
			end
		end
		if not blocked then
			return target
		end
	end

	local fallback = anchorPos
	if floorPart then
		fallback = clampPointToPartXZ(floorPart, fallback, FLOOR_PADDING)
	end
	return fallback
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

local function findNearestPlayerPosition(position, maxRange)
	if not position then return nil end
	local nearest = nil
	local bestDist = maxRange or FLEE_TRIGGER_RANGE

	for _, plr in ipairs(Players:GetPlayers()) do
		local character = plr.Character
		local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			local dist = (root.Position - position).Magnitude
			if dist <= bestDist then
				bestDist = dist
				nearest = root.Position
			end
		end
	end

	return nearest
end

local function shouldInterruptForFlee(state, hrp)
	if not state or not hrp then
		return false, nil
	end
	if state.isFleeing then
		return false, nil
	end
	if state.pet:GetAttribute("WildPet") ~= true then
		return false, nil
	end

	if (os.clock() - (state.lastFleeAt or 0)) < FLEE_COOLDOWN then
		return false, nil
	end

	local threatPos = state.pendingFleeThreat or findNearestPlayerPosition(hrp.Position, FLEE_TRIGGER_RANGE)
	if threatPos then
		state.pendingFleeThreat = threatPos
		return true, "flee"
	end

	return false, nil
end

local function playFleeStartAnimation(state)
	if not state then return end
	loadTracks(state)
	stopTrack(state.tracks and state.tracks.walk, 0.06)
	for _, tr in ipairs((state.tracks and state.tracks.idles) or {}) do
		stopTrack(tr, 0.06)
	end
	for _, tr in ipairs((state.tracks and state.tracks.pause) or {}) do
		stopTrack(tr, 0.06)
	end

	local track = playRandomFromList(state.tracks and state.tracks.fleeStart, 0.08)
	if not track then return end
	pcall(function()
		track.Priority = Enum.AnimationPriority.Action
	end)

	local endAt = os.clock() + math.clamp(track.Length > 0 and track.Length or 0.5, 0.2, FLEE_START_MAX_WAIT)
	while state.wanderRunning and track.IsPlaying and os.clock() < endAt do
		task.wait(0.03)
	end
	stopTrack(track, 0.05)
end

local function sampleFleeTarget(anchorPos, radius, bounds, threatPos, petPos)
	local floorPart = bounds and bounds.floorPart or nil
	local away = Vector3.new(1, 0, 0)
	if threatPos and petPos then
		local delta = Vector3.new(petPos.X - threatPos.X, 0, petPos.Z - threatPos.Z)
		if delta.Magnitude > 0.05 then
			away = delta.Unit
		end
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	if floorPart then
		overlapParams.FilterDescendantsInstances = { floorPart }
	end

	for _ = 1, TARGET_SAMPLE_ATTEMPTS do
		local jitter = (math.random() - 0.5) * math.rad(70)
		local dir = (CFrame.Angles(0, jitter, 0):VectorToWorldSpace(away)).Unit
		local dist = radius * (0.55 + math.random() * 0.45)
		local target = anchorPos + dir * dist

		if floorPart then
			target = clampPointToPartXZ(floorPart, target, FLOOR_PADDING)
		end

		local clearanceCenter = target + Vector3.new(0, OBSTACLE_CLEARANCE.Y * 0.5, 0)
		local nearby = workspace:GetPartBoundsInBox(CFrame.new(clearanceCenter), OBSTACLE_CLEARANCE, overlapParams)
		local blocked = false
		for _, part in ipairs(nearby) do
			if part and part.CanCollide and (not floorPart or part ~= floorPart) then
				blocked = true
				break
			end
		end
		if not blocked then
			return target
		end
	end

	return sampleWanderTarget(anchorPos, radius, bounds)
end

local function tryFleeFromNearbyPlayer(state, hrp, wanderRadius, bounds)
	if not state or not hrp then return false end
	if state.pet:GetAttribute("WildPet") ~= true then return false end

	local threatPos = state.pendingFleeThreat or findNearestPlayerPosition(hrp.Position, FLEE_TRIGGER_RANGE)
	if not threatPos then
		return false
	end

	if (os.clock() - (state.lastFleeAt or 0)) < FLEE_COOLDOWN then
		return false
	end

	state.lastFleeAt = os.clock()
	state.pendingFleeThreat = nil
	state.isFleeing = true
	setMode(state, "Idle")
	playFleeStartAnimation(state)

	local fleeStartedAt = os.clock()
	local fleeEndAt = fleeStartedAt + (FLEE_MIN_DURATION + math.random() * (FLEE_MAX_DURATION - FLEE_MIN_DURATION))

	while state.wanderRunning and state.pet.Parent and os.clock() < fleeEndAt do
		local nearestThreat = findNearestPlayerPosition(hrp.Position, FLEE_TRIGGER_RANGE + 3)
		if nearestThreat then
			threatPos = nearestThreat
		elseif os.clock() >= (fleeStartedAt + FLEE_MIN_DURATION) then
			break
		end

		local fleeTarget = sampleFleeTarget(hrp.Position, wanderRadius, bounds, threatPos, hrp.Position)
		local runSpeed = FLEE_SPEED_MIN + (math.random() * (FLEE_SPEED_MAX - FLEE_SPEED_MIN))
		moveToPositionSmooth(state, fleeTarget, runSpeed)
		task.wait(0.02)
	end

	state.isFleeing = false
	state.pendingFleeThreat = nil
	return true
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

local function cleanupStateIfCurrent(pet, expectedState)
	local state = petTasks[pet]
	if not state then return end
	if state ~= expectedState then return end
	cleanupState(pet)
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
	state.isFleeing = false
	state.pendingFleeThreat = nil

	petTasks[pet] = state

	loadTracks(state)
	setMode(state, "Idle")

	local wanderRadius = tonumber(options.wanderRadius) or DEFAULT_WANDER_RADIUS
	local ownerUserId = options.ownerUserId
	local constraintPart = options.constraintPart

	local bounds = nil
	if constraintPart and constraintPart:IsA("BasePart") then
		bounds = {
			floorPart = constraintPart,
			center = constraintPart.Position,
		}
	elseif ownerUserId ~= nil then
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
		while pet and pet.Parent do
			local currentState = petTasks[pet]
			if not currentState or currentState ~= state or not currentState.wanderRunning then
				break
			end

			if tryFleeFromNearbyPlayer(currentState, hrp, wanderRadius, bounds) then
				task.wait(0.05)
				continue
			end


			local target = sampleWanderTarget(spawnPos, wanderRadius, bounds)
			local moveSpeed = WALK_SPEED_MIN + (math.random() * (WALK_SPEED_MAX - WALK_SPEED_MIN))

			local useSimpleOwnedMovement = ownerUserId ~= nil and pet:GetAttribute("WildPet") ~= true
			if useSimpleOwnedMovement then
				if bounds and bounds.floorPart then
					target = clampPointToPartXZ(bounds.floorPart, target, FLOOR_PADDING)
				end
				moveToPositionSmooth(currentState, target, moveSpeed, nil)
			else
				local path = PathfindingService:CreatePath({
					AgentRadius = 2,
					AgentHeight = 3,
					AgentCanJump = false,
					WaypointSpacing = 2,
				})

				local success = pcall(function()
					path:ComputeAsync(hrp.Position, target)
				end)

				if success and path.Status == Enum.PathStatus.Success then
					local waypoints = path:GetWaypoints()

					for i, wp in ipairs(waypoints) do
						local liveState = petTasks[pet]
						if not liveState or liveState ~= state or not liveState.wanderRunning or not pet.Parent then
							break
						end

						local goal = Vector3.new(wp.Position.X, hrp.Position.Y, wp.Position.Z)
						if bounds and bounds.floorPart then
							goal = clampPointToPartXZ(bounds.floorPart, goal, FLOOR_PADDING)
						end

						if tryFleeFromNearbyPlayer(currentState, hrp, wanderRadius, bounds) then
							break
						end

						local reached, reason = moveToPositionSmooth(currentState, goal, moveSpeed, function()
							return shouldInterruptForFlee(currentState, hrp)
						end)
						if reason == "flee" then
							break
						end

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
					moveToPositionSmooth(currentState, target, moveSpeed, function()
						return shouldInterruptForFlee(currentState, hrp)
					end)
				end
			end

			doIdlePause(currentState, spawnPos)

			local pause = WANDER_DELAY_MIN + math.random() * (WANDER_DELAY_MAX - WANDER_DELAY_MIN)
			task.wait(pause)
		end

		cleanupStateIfCurrent(pet, state)
	end)
end

-- StartWandering(pet, originVector3?, wanderRadius?, ownerUserId?, constraintPart?)
function PetMovement.StartWandering(pet, origin, wanderRadius, ownerUserId, constraintPart)
	if not pet then return end
	optimizeRuntimePetParts(pet)

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

	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end)

	startWanderingInternal(pet, spawnPos, {
		wanderRadius = tonumber(wanderRadius) or DEFAULT_WANDER_RADIUS,
		ownerUserId = ownerUserId,
		constraintPart = constraintPart,
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
