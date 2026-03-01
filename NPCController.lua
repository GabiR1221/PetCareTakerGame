-- NPCController (ModuleScript)
-- Controls movement for a single NPC model along provided waypoints and finally to the target desk.
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local NPCController = {}
NPCController.__index = NPCController

local function safeFindHumanoid(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	return humanoid, root
end

local function waitForMoveFinish(humanoid, root, targetPosition, timeout)
	-- Wait until humanoid gets near targetPosition or MoveToFinished fires (with a timeout)
	local start = time()
	local reached = false

	local conn
	conn = humanoid.MoveToFinished:Connect(function(reachedArg)
		-- The event doesn't tell us which target it finished for, so verify distance
		if root and root.Parent and (root.Position - targetPosition).Magnitude <= (4) then
			reached = reachedArg
		end
	end)

	while time() - start < (timeout or 8) do
		if not root or not root.Parent then break end
		if (root.Position - targetPosition).Magnitude <= (4) then
			reached = true
			break
		end
		task.wait(0.15)
	end

	if conn then conn:Disconnect() end
	return reached
end

local function followPathPoints(humanoid, root, points, config)
	-- points = array of Vector3 or Parts. Moves humanoid sequentially to each point.
	for i, point in ipairs(points) do
		if not humanoid or not root or not root.Parent then return false end

		local targetPos = typeof(point) == "Vector3" and point or (point.Position and point.Position or point)
		-- issue MoveTo
		humanoid:MoveTo(targetPos)
		local reached = waitForMoveFinish(humanoid, root, targetPos, config.NPCTimeoutPerWaypoint)
		if reached then
			-- continue to next waypoint
		else
			-- fallback to PathfindingService route from current pos to targetPos
			local success = false
			local ok, err = pcall(function()
				local path = PathfindingService:CreatePath({
					AgentRadius = 2,
					AgentHeight = 5,
					AgentCanJump = true,
					MaxSmoothPathPoints = 0,
				})
				path:ComputeAsync(root.Position, targetPos)
				if path.Status == Enum.PathStatus.Success then
					local waypoints = path:GetWaypoints()
					for _, wp in ipairs(waypoints) do
						if wp.Action == Enum.PathWaypointAction.Jump then
							humanoid.Jump = true
						end
						humanoid:MoveTo(wp.Position)
						waitForMoveFinish(humanoid, root, wp.Position, config.NPCTimeoutPerWaypoint)
					end
					success = true
				else
					success = false
				end
			end)
			if not ok then
				warn("NPCController: pathfinding compute failed:", err)
				success = false
			end
			if not success then
				-- Unable to reach this waypoint -> abort movement sequence
				return false
			end
		end
	end
	return true
end

function NPCController.new(npcModel, config)
	local self = setmetatable({}, NPCController)
	self.Model = npcModel
	self.Config = config
	self._isCleaning = false
	return self
end

-- Starts the NPC: follows waypoints (array of Parts or Vector3s), then moves to deskPart (BasePart)
-- returns task that resolves when NPC finishes (arrived + lifetime + removed)
function NPCController:Start(waypoints, deskPart)
	local humanoid, root = safeFindHumanoid(self.Model)
	if not humanoid or not root then
		warn("NPCController: NPC model missing Humanoid or HumanoidRootPart.")
		self:Cleanup()
		return
	end

	humanoid.WalkSpeed = self.Config.NPCWalkSpeed

	-- helper: try to move using PathfindingService or MoveTo; returns true if reached
	local function attemptMoveToTarget(targetPos, attempts, perWaypointTimeout)
		attempts = attempts or 3
		perWaypointTimeout = perWaypointTimeout or self.Config.NPCTimeoutPerWaypoint
		for attempt = 1, attempts do
			local ok, err = pcall(function()
				local path = PathfindingService:CreatePath({
					AgentRadius = 2,
					AgentHeight = 5,
					AgentCanJump = true,
				})
				path:ComputeAsync(root.Position, targetPos)
				if path.Status == Enum.PathStatus.Success then
					local wps = path:GetWaypoints()
					for _, wp in ipairs(wps) do
						if wp.Action == Enum.PathWaypointAction.Jump then
							humanoid.Jump = true
						end
						humanoid:MoveTo(wp.Position)
						waitForMoveFinish(humanoid, root, wp.Position, perWaypointTimeout)
					end
				else
					-- fallback: direct MoveTo (this may still fail if blocked)
					humanoid:MoveTo(targetPos)
					waitForMoveFinish(humanoid, root, targetPos, perWaypointTimeout)
				end
			end)
			if not ok then
				warn("NPCController: path attempt failed (attempt "..tostring(attempt).."):", err)
			end

			-- check proximity
			if root and (root.Position - targetPos).Magnitude <= (self.Config.ArrivalTolerance or 4) then
				return true
			end

			-- small backoff before retry
			task.wait(0.35 * attempt)
		end
		return false
	end

	-- try to follow provided waypoints first
	local success = true
	if self.Config.FollowWaypoints and waypoints and #waypoints > 0 then
		success = followPathPoints(humanoid, root, waypoints, self.Config)
	end

	-- if following waypoints failed, try to reach desk directly with a few retries
	if not success then
		local reached = attemptMoveToTarget(deskPart.Position, 3, self.Config.NPCTimeoutPerWaypoint)
		success = reached
	end

	-- AFTER attempts, check if we are near the desk
	if root and (root.Position - deskPart.Position).Magnitude <= (self.Config.ArrivalTolerance or 4) then
		-- Arrived
		if root and deskPart then
			pcall(function() root.CFrame = CFrame.new(root.Position, deskPart.Position) end)
		end

		-- mark AtDesk for PetManager
		if self.Model and self.Model.SetAttribute then
			pcall(function() self.Model:SetAttribute("AtDesk", true) end)
		end

		-- WAIT until somebody sets the "Leaving" attribute.
		-- This prevents the NPC from auto-despawning while waiting at desk.
		local left = false
		local conn
		if self.Model and self.Model.GetAttributeChangedSignal then
			conn = self.Model:GetAttributeChangedSignal("Leaving"):Connect(function()
				if self.Model and self.Model:GetAttribute("Leaving") then
					left = true
				end
			end)
		end

		-- Busy-wait until Leaving becomes true or NPC is destroyed
		while self.Model and self.Model.Parent and not left do
			task.wait(0.15)
		end

		if conn then conn:Disconnect() end

		-- unset AtDesk when leaving
		if self.Model and self.Model.SetAttribute then
			pcall(function() self.Model:SetAttribute("AtDesk", false) end)
		end

		-- If signalled to leave, path back to spawn (best-effort)
		if left and self.Model then
			local sx = self.Model:GetAttribute("SpawnPositionX")
			local sy = self.Model:GetAttribute("SpawnPositionY")
			local sz = self.Model:GetAttribute("SpawnPositionZ")
			if sx and sy and sz then
				local spawnPos = Vector3.new(tonumber(sx), tonumber(sy), tonumber(sz))
				pcall(function()
					attemptMoveToTarget(spawnPos, 3, self.Config.NPCTimeoutPerWaypoint)
				end)
			end
		end

		-- cleanup
		self:Cleanup()

	else
		-- NOT arrived after retries.
		-- As a last resort try several extra attempts with more generous timeout,
		-- then teleport to desk so PetManager still gets a chance to interact.
		local extraReached = attemptMoveToTarget(deskPart.Position, 2, math.max(self.Config.NPCTimeoutPerWaypoint, 12))
		if extraReached or (root and (root.Position - deskPart.Position).Magnitude <= (self.Config.ArrivalTolerance or 4)) then
			-- re-run arrival branch by calling Start again with same args (safe recursive re-run)
			-- small delay to avoid tight recursion
			task.delay(0.05, function() pcall(function() self:Start({}, deskPart) end) end)
			return
		end

		-- Last resort teleport (helps if desk moved or path is broken). Remove this block if you dislike teleporting.
		if root and root.Parent then
			pcall(function()
				local teleportPos = deskPart.CFrame * CFrame.new(0, 3, 0)
				if self.Model:SetPrimaryPartCFrame() then
					self.Model:SetPrimaryPartCFrame(teleportPos)
				else
					for _, p in ipairs(self.Model:GetDescendants()) do
						if p:IsA("BasePart") then p.CFrame = teleportPos; break end
					end
				end
			end)
			-- small wait then treat as arrived
			task.wait(0.08)
			-- set AtDesk and continue arrival handling
			if self.Model and self.Model.SetAttribute then
				pcall(function() self.Model:SetAttribute("AtDesk", true) end)
			end

			-- set AtDesk and WAIT until somebody sets the "Leaving" attribute (no short timeout).
			if self.Model and self.Model.SetAttribute then
				pcall(function() self.Model:SetAttribute("AtDesk", true) end)
			end

			local left2 = false
			local conn2
			if self.Model and self.Model.GetAttributeChangedSignal then
				conn2 = self.Model:GetAttributeChangedSignal("Leaving"):Connect(function()
					if self.Model and self.Model:GetAttribute("Leaving") then
						left2 = true
					end
				end)
			end

			-- Busy-wait until Leaving becomes true or NPC is destroyed
			while self.Model and self.Model.Parent and not left2 do
				task.wait(0.15)
			end

			if conn2 then conn2:Disconnect() end

			-- unset AtDesk when leaving
			if self.Model and self.Model.SetAttribute then
				pcall(function() self.Model:SetAttribute("AtDesk", false) end)
			end

			-- If signalled to leave, attempt return path
			if left2 and self.Model then
				local sx = self.Model:GetAttribute("SpawnPositionX")
				local sy = self.Model:GetAttribute("SpawnPositionY")
				local sz = self.Model:GetAttribute("SpawnPositionZ")
				if sx and sy and sz then
					local spawnPos = Vector3.new(tonumber(sx), tonumber(sy), tonumber(sz))
					pcall(function() attemptMoveToTarget(spawnPos, 2, self.Config.NPCTimeoutPerWaypoint) end)
				end
			end

			if conn2 then conn2:Disconnect() end
			if self.Model and self.Model.SetAttribute then
				pcall(function() self.Model:SetAttribute("AtDesk", false) end)
			end
			if left2 then
				-- attempt return path similar to above (best effort)
				local sx = self.Model:GetAttribute("SpawnPositionX")
				local sy = self.Model:GetAttribute("SpawnPositionY")
				local sz = self.Model:GetAttribute("SpawnPositionZ")
				if sx and sy and sz then
					local spawnPos = Vector3.new(tonumber(sx), tonumber(sy), tonumber(sz))
					pcall(function() attemptMoveToTarget(spawnPos, 2, self.Config.NPCTimeoutPerWaypoint) end)
				end
			end
		end

		-- finally cleanup
		self:Cleanup()
	end
end



function NPCController:Cleanup()
	if self._isCleaning then return end
	self._isCleaning = true
	if self.Model and self.Model.Parent then
		pcall(function()
			self.Model:Destroy()
		end)
	end
end

return NPCController
