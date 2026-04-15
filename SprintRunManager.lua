local SprintRunManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local START_LINE_TAG = "PetRunStartLine"
local START_LINE_NAME = "PetRunStartLine"
local OBSTACLE_ZONE_TAG = "WildPetZone"
local OBSTACLE_ZONE_NAME = "WildPetZonePart"

local RUN_SPEED = 28
local DEFAULT_WALK_SPEED = 16
local DEFAULT_STAMINA = 50
local STAMINA_DRAIN_PER_SECOND = 14
local OBSTACLE_RESPAWN_DELAY = 0.75
local DEFAULT_ZONE_MAX_OBSTACLES = 4
local DEFAULT_OBSTACLE_STAMINA_DAMAGE = 8
local DEFAULT_OBSTACLE_SPEED_MULTIPLIER = 0.55
local OBSTACLE_SPEED_PENALTY_DURATION = 2
local MIN_JUMP_DURATION = 1.17
local JUMP_UPWARD_FORCE_DURATION = 0
local JUMP_FORWARD_FORCE_DURATION = 0.9
local JUMP_UPWARD_SPEED = 0
local JUMP_FORWARD_SPEED_MULTIPLIER = 1.5

local JUMP_FALLBACK_TIMEOUT = 1.5
local JUMP_STAMINA_COST_PERCENT = 0.30

local EXHAUSTION_DECEL_DURATION = 0.9

local STUMBLE_DURATION_MIN = 0.5
local STUMBLE_DURATION_MAX = 1.25
local STUMBLE_SPEED_MULTIPLIER = 0.62
local HITBOX_SIZE = Vector3.new(8, 6, 10)

local function getOrCreateRemote(name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

local function getDescendantByPath(root, pathParts)
	local cursor = root
	for _, partName in ipairs(pathParts) do
		if typeof(cursor) ~= "Instance" then
			return nil
		end
		cursor = cursor:FindFirstChild(partName)
		if not cursor then
			return nil
		end
	end
	return cursor
end

local function getGemUpgradeValue(player, upgradeIndex)
	local valueObj = getDescendantByPath(player, {"Data", "PlayerData", "GemUpgrade" .. tostring(upgradeIndex)})
	if valueObj and valueObj:IsA("ValueBase") then
		local raw = tonumber(valueObj.Value) or 0
		return math.max(0, raw)
	end
	return 0
end

local function getGemRewardConfig(gemShopFolder, rewardIndex)
	local reward = gemShopFolder
		and gemShopFolder:FindFirstChild(tostring(rewardIndex))
		and gemShopFolder[tostring(rewardIndex)]:FindFirstChild("Reward")
	if reward then
		return reward
	end
	return nil
end

local function applyGemShopReward(baseValue, rewardConfig, upgradeValue)
	if not rewardConfig then
		return baseValue
	end

	local defaultReward = rewardConfig:FindFirstChild("DefaultReward")
	local increasePer = rewardConfig:FindFirstChild("IncreasePer")
	local exponential = rewardConfig:FindFirstChild("Exponential")
	if not defaultReward or not increasePer or not exponential then
		return baseValue
	end

	if exponential.Value then
		return baseValue * (defaultReward.Value + (increasePer.Value ^ upgradeValue))
	end
	return baseValue * (defaultReward.Value + (increasePer.Value * upgradeValue))
end



function SprintRunManager:Initialize(playersService, wildPetManager)
	self.Players = playersService
	self.WildPetManager = wildPetManager
	self.playerState = {}
	self.startLines = {}
	self.startLineConns = {}
	self.obstacleZones = {}
	self.obstacleRng = Random.new()
	self.liveObstacleFolder = workspace:FindFirstChild("RunnerLiveObstacles") or Instance.new("Folder")
	self.liveObstacleFolder.Name = "RunnerLiveObstacles"
	self.liveObstacleFolder.Parent = workspace
	self.gemShopFolder = ReplicatedStorage:FindFirstChild("GemShop")
	self.obstacleTemplatesRoot = game:GetService("ServerStorage"):FindFirstChild("RunnerObstacleModels")

	self.stateRemote = getOrCreateRemote("RunnerStateEvent")
	self.actionRemote = getOrCreateRemote("RunnerActionEvent")

	self:ScanStartLines()
	self:ScanObstacleZones()
	self:_connectRemotes()
	self:_connectPlayers()
	self:_startHeartbeat()
end

function SprintRunManager:_connectPlayers()
	self.Players.PlayerRemoving:Connect(function(player)
		self:StopRunning(player, false)
		self.playerState[player] = nil
	end)

	self.Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			self:StopRunning(player, false)
		end)
	end)
end

function SprintRunManager:_connectRemotes()
	self.actionRemote.OnServerEvent:Connect(function(player, action)
		if action == "Jump" then
			self:RequestJump(player)
		elseif action == "GoBack" then
			self:GoBackToPlot(player)
		elseif action == "JumpAnimEnded" then
			self:OnJumpAnimationEnded(player)
		end
	end)
end

function SprintRunManager:_beginExhaustion(player, state, startingSpeed)
	if not state or state.exhaustedStarted then
		return
	end

	state.exhausted = true
	state.exhaustedStarted = true
	state.exhaustionStartedAt = os.clock()
	state.exhaustionDecelDuration = EXHAUSTION_DECEL_DURATION
	state.exhaustionStartSpeed = math.max(0, tonumber(startingSpeed) or state.runSpeed or RUN_SPEED)
	state.exhaustionPhase = "Slide"

	self.stateRemote:FireClient(player, "ExhaustionState", true, {
		phase = "Slide",
		duration = state.exhaustionDecelDuration,
	})
end


function SprintRunManager:_startHeartbeat()
	RunService.Heartbeat:Connect(function(dt)
		for player, state in pairs(self.playerState) do
			if not state.active then
				continue
			end

			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
			if not hum or not root or hum.Health <= 0 then
				self:StopRunning(player, true)
				continue
			end

			local now = os.clock()

			if state.stumbling then
				if state.stumbleEndAt and now >= state.stumbleEndAt then
					self:_clearStumbleForce(state)
					state.stumbling = false
					state.stumbleEndAt = nil
					state.stumbleStartedAt = nil
					state.stumbleSpeed = nil
					player:SetAttribute("RunnerStumbling", false)
					self.stateRemote:FireClient(player, "StumbleState", false)
				else
					hum.WalkSpeed = 0
					hum.JumpPower = 0
					hum.JumpHeight = 0
					hum.AutoRotate = true
					hum.Jump = false
					hum:Move(Vector3.zero, false)
				end

			elseif state.jumping then
				if state.jumpEndAt and now >= state.jumpEndAt then
					self:_endJumpState(player, state, true)
				end
			end

			if state.jumping and state.jumpForwardForceEndAt and os.clock() >= state.jumpForwardForceEndAt then
				state.jumpForwardForceEndAt = nil
			end
			
			dt = math.max(dt or 0, 0)
			local maxStamina = state.maxStamina or DEFAULT_STAMINA
			if not state.exhausted then
				state.currentStamina = math.max(0, (state.currentStamina or maxStamina) - (state.staminaDrainPerSecond or STAMINA_DRAIN_PER_SECOND) * dt)
				if state.currentStamina <= 0 then
					self:_beginExhaustion(player, state, state.runSpeed)
					state.currentStamina = 0
				end
			end


			local speed = state.runSpeed or RUN_SPEED
			if (state.speedPenaltyUntil or 0) > os.clock() then
				local penaltyMultiplier = state.speedPenaltyMultiplier or DEFAULT_OBSTACLE_SPEED_MULTIPLIER
				speed *= math.clamp(penaltyMultiplier, 0.1, 1)
			end
			if state.exhausted then
				local exhaustedSpeed = 0
				if state.exhaustedStarted and state.exhaustionPhase ~= "Collapsed" then
					local elapsed = math.max(0, now - (state.exhaustionStartedAt or now))
					local duration = math.max(0.05, state.exhaustionDecelDuration or EXHAUSTION_DECEL_DURATION)
					local alpha = math.clamp(elapsed / duration, 0, 1)
					exhaustedSpeed = (state.exhaustionStartSpeed or speed) * (1 - alpha)

					if alpha >= 1 then
						state.exhaustionPhase = "Collapsed"
						self.stateRemote:FireClient(player, "ExhaustionState", true, { phase = "Collapsed" })
					end
				end

				if state.exhaustionPhase ~= "Collapsed" then
					hum.WalkSpeed = 0
					hum.JumpPower = 0
					hum.JumpHeight = 0
					hum.AutoRotate = false
					hum.Jump = false
					hum:Move(Vector3.zero, true)
					local moveDir = root.CFrame.LookVector
					root.AssemblyLinearVelocity = Vector3.new(moveDir.X * exhaustedSpeed, root.AssemblyLinearVelocity.Y, moveDir.Z * exhaustedSpeed)
				else
					if hum.WalkSpeed ~= 0 then
						hum.WalkSpeed = 0
					end
					hum.JumpPower = 0
					hum.JumpHeight = 0
					hum.AutoRotate = false
					hum.Jump = false
					hum:Move(Vector3.zero, true)
					root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
				end
			elseif state.jumping then
				hum.WalkSpeed = 0
				hum.JumpPower = 0
				hum.AutoRotate = false
				hum.JumpHeight = 0
				hum.Jump = false
				hum:Move(Vector3.zero, false)
			else
				if hum.WalkSpeed ~= speed then
					hum.WalkSpeed = speed
				end
				hum.JumpPower = 0
				hum.JumpHeight = 0
				hum.AutoRotate = true
				hum.Jump = false
				local moveDir = root.CFrame.LookVector
				hum:Move(moveDir, false)
				root.AssemblyLinearVelocity = Vector3.new(moveDir.X * speed, root.AssemblyLinearVelocity.Y, moveDir.Z * speed)
			end

			if state._hitbox then
				state._hitbox.CFrame = root.CFrame * CFrame.new(0, 0, -3)
			end
			
			local now = os.clock()
			if (now - (state.lastStaminaUpdateAt or 0)) >= 0.1 then
				state.lastStaminaUpdateAt = now
				self.stateRemote:FireClient(player, "StaminaUpdate", true, {
					current = state.currentStamina,
					max = maxStamina,
					exhausted = state.exhausted == true,
					phase = state.exhaustionPhase,
				})
			end
		end
		self:_tickObstacleZones()
	end)
end

function SprintRunManager:ScanObstacleZones()
	for _, zone in ipairs(CollectionService:GetTagged(OBSTACLE_ZONE_TAG)) do
		if zone:IsA("BasePart") then
			self:_registerObstacleZone(zone)
		end
	end

	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == OBSTACLE_ZONE_NAME then
			self:_registerObstacleZone(inst)
		end
	end
end

function SprintRunManager:_registerObstacleZone(zonePart)
	if self.obstacleZones[zonePart] then return end

	self.obstacleZones[zonePart] = {
		part = zonePart,
		active = {},
		nextSpawnAt = 0,
	}

	zonePart.Destroying:Connect(function()
		local zoneState = self.obstacleZones[zonePart]
		if not zoneState then return end
		for obstacle in pairs(zoneState.active) do
			pcall(function() obstacle:Destroy() end)
		end
		self.obstacleZones[zonePart] = nil
	end)
end

function SprintRunManager:_resolveZoneId(zonePart)
	local zoneId = zonePart:GetAttribute("ZoneId") or zonePart:GetAttribute("WildPetZone")
	if zoneId ~= nil and tostring(zoneId) ~= "" then
		return tostring(zoneId)
	end
	return zonePart.Name
end

function SprintRunManager:_getObstacleTemplatesForZone(zonePart)
	if not self.obstacleTemplatesRoot then
		return {}
	end

	local templates = {}
	local zoneId = self:_resolveZoneId(zonePart)
	local zonesFolder = self.obstacleTemplatesRoot:FindFirstChild("Zones")

	local function addTemplatesFrom(container)
		if not container then return end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Model") or child:IsA("BasePart") then
				table.insert(templates, child)
			end
		end
	end

	if zonesFolder and zoneId then
		addTemplatesFrom(zonesFolder:FindFirstChild(zoneId))
		local numeric = tonumber(zoneId)
		if numeric then
			addTemplatesFrom(zonesFolder:FindFirstChild(("Zone%d"):format(numeric)))
		end
	end

	if #templates == 0 then
		addTemplatesFrom(self.obstacleTemplatesRoot:FindFirstChild("All"))
	end
	if #templates == 0 then
		addTemplatesFrom(self.obstacleTemplatesRoot)
	end
	return templates
end

function SprintRunManager:_placeObstacleInZone(zonePart, obstacleModel)
	local randomX = (self.obstacleRng:NextNumber() - 0.5) * zonePart.Size.X
	local randomZ = (self.obstacleRng:NextNumber() - 0.5) * zonePart.Size.Z
	local targetPos = (zonePart.CFrame * CFrame.new(randomX, 0, randomZ)).Position + Vector3.new(0, 2.5, 0)

	if obstacleModel:IsA("Model") then
		local primary = obstacleModel.PrimaryPart or obstacleModel:FindFirstChildWhichIsA("BasePart")
		if primary then
			if not obstacleModel.PrimaryPart then
				obstacleModel.PrimaryPart = primary
			end
			obstacleModel:PivotTo(CFrame.new(targetPos))
		end
	elseif obstacleModel:IsA("BasePart") then
		obstacleModel.CFrame = CFrame.new(targetPos)
	end
end

function SprintRunManager:_connectObstacleTouch(zoneState, obstacleInstance)
	local touchParts = {}
	if obstacleInstance:IsA("Model") then
		for _, desc in ipairs(obstacleInstance:GetDescendants()) do
			if desc:IsA("BasePart") then
				table.insert(touchParts, desc)
			end
		end
	elseif obstacleInstance:IsA("BasePart") then
		table.insert(touchParts, obstacleInstance)
	end

	local function onTouched(otherPart)
		if not otherPart then return end
		if obstacleInstance:GetAttribute("Consumed") then return end

		local character = otherPart.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end

		local player = self.Players:GetPlayerFromCharacter(character)
		if not player then return end

		local state = self.playerState[player]
		if not state or not state.active then return end

		obstacleInstance:SetAttribute("Consumed", true)

		self:_applyObstaclePenalty(player, state, obstacleInstance)
		self:_startStumble(player, state, obstacleInstance)
		self:_despawnObstacle(zoneState, obstacleInstance)
	end

	for _, part in ipairs(touchParts) do
		part.CanTouch = true
		part.Touched:Connect(onTouched)
	end
end

function SprintRunManager:_spawnObstacleInZone(zoneState)
	local zonePart = zoneState and zoneState.part
	if not zonePart or not zonePart.Parent then return end

	local templates = self:_getObstacleTemplatesForZone(zonePart)
	if #templates == 0 then return end

	local template = templates[self.obstacleRng:NextInteger(1, #templates)]
	local obstacle = template:Clone()
	obstacle.Parent = self.liveObstacleFolder
	obstacle:SetAttribute("Consumed", false)
	self:_placeObstacleInZone(zonePart, obstacle)
	zoneState.active[obstacle] = true
	self:_connectObstacleTouch(zoneState, obstacle)
end

function SprintRunManager:_despawnObstacle(zoneState, obstacleInstance)
	if not zoneState or not obstacleInstance then return end
	zoneState.active[obstacleInstance] = nil
	pcall(function() obstacleInstance:Destroy() end)
	zoneState.nextSpawnAt = os.clock() + OBSTACLE_RESPAWN_DELAY
end

function SprintRunManager:_applyObstaclePenalty(player, state, obstacleInstance)
	local staminaDamage = obstacleInstance:GetAttribute("StaminaDamage")
	if staminaDamage == nil then
		staminaDamage = DEFAULT_OBSTACLE_STAMINA_DAMAGE
	end
	staminaDamage = math.max(0, tonumber(staminaDamage) or DEFAULT_OBSTACLE_STAMINA_DAMAGE)

	local speedMultiplier = obstacleInstance:GetAttribute("SpeedMultiplier")
	if speedMultiplier == nil then
		speedMultiplier = DEFAULT_OBSTACLE_SPEED_MULTIPLIER
	end
	speedMultiplier = math.clamp(tonumber(speedMultiplier) or DEFAULT_OBSTACLE_SPEED_MULTIPLIER, 0.1, 1)

	local now = os.clock()
	state.currentStamina = math.max(0, (state.currentStamina or 0) - staminaDamage)
	state.speedPenaltyUntil = now + OBSTACLE_SPEED_PENALTY_DURATION
	state.speedPenaltyMultiplier = speedMultiplier
	if state.currentStamina <= 0 then
		self:_beginExhaustion(player, state, state.runSpeed)
	end

	self.stateRemote:FireClient(player, "StaminaUpdate", true, {
		current = state.currentStamina,
		max = state.maxStamina or DEFAULT_STAMINA,
		exhausted = state.exhausted == true,
	})
end

function SprintRunManager:_tickObstacleZones()
	local now = os.clock()
	for zonePart, zoneState in pairs(self.obstacleZones) do
		if not zonePart or not zonePart.Parent then
			self.obstacleZones[zonePart] = nil
			continue
		end

		local maxObstacles = tonumber(zonePart:GetAttribute("MaxObstacles")) or DEFAULT_ZONE_MAX_OBSTACLES
		maxObstacles = math.max(0, math.floor(maxObstacles))

		local activeCount = 0
		for obstacleInstance in pairs(zoneState.active) do
			if obstacleInstance and obstacleInstance.Parent then
				activeCount += 1
			else
				zoneState.active[obstacleInstance] = nil
			end
		end

		if activeCount < maxObstacles and now >= (zoneState.nextSpawnAt or 0) then
			self:_spawnObstacleInZone(zoneState)
			zoneState.nextSpawnAt = now + 0.1
		end
	end
end

function SprintRunManager:_clearStumbleForce(state)
	if not state then return end

	if state.stumbleLinearVelocity then
		pcall(function() state.stumbleLinearVelocity:Destroy() end)
		state.stumbleLinearVelocity = nil
	end

	if state.stumbleAttachment then
		pcall(function() state.stumbleAttachment:Destroy() end)
		state.stumbleAttachment = nil
	end

	state.stumbleDirection = nil
end

function SprintRunManager:_applyStumbleForce(state, root, stumbleSpeed)
	self:_clearStumbleForce(state)

	local attachment = Instance.new("Attachment")
	attachment.Name = "RunnerStumbleAttachment"
	attachment.Parent = root

	local look = root.CFrame.LookVector
	local horizontalLook = Vector3.new(look.X, 0, look.Z)
	if horizontalLook.Magnitude <= 0 then
		horizontalLook = Vector3.new(0, 0, -1)
	else
		horizontalLook = horizontalLook.Unit
	end

	local stumbleVelocity = Instance.new("LinearVelocity")
	stumbleVelocity.Name = "RunnerStumbleVelocity"
	stumbleVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	stumbleVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	stumbleVelocity.MaxForce = math.huge
	stumbleVelocity.Attachment0 = attachment
	stumbleVelocity.VectorVelocity = horizontalLook * math.max(0, stumbleSpeed or 0)
	stumbleVelocity.Parent = root

	state.stumbleAttachment = attachment
	state.stumbleLinearVelocity = stumbleVelocity
	state.stumbleDirection = horizontalLook
end

function SprintRunManager:_endJumpState(player, state, sendClientEvent)
	if not state then return end

	self:_clearJumpForce(state)

	state.jumping = false
	state.jumpEndAt = nil
	state.slideEndAt = nil
	state.jumpUpForceEndAt = nil
	state.jumpForwardForceEndAt = nil
	state.slideStateSent = false

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.JumpPower = 0
		hum.JumpHeight = 0
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end

	player:SetAttribute("RunnerJumping", false)
	self:_finalizeJumpCarryPose(player)

	if sendClientEvent then
		self.stateRemote:FireClient(player, "JumpState", false)
	end
end


function SprintRunManager:_startStumble(player, state, obstacleInstance)
	if not state or not state.active then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
	if not hum or not root then return end

	local now = os.clock()

	local stumbleDuration = obstacleInstance and tonumber(obstacleInstance:GetAttribute("StumbleDuration"))
	if not stumbleDuration then
		stumbleDuration = STUMBLE_DURATION_MIN + (self.obstacleRng:NextNumber() * (STUMBLE_DURATION_MAX - STUMBLE_DURATION_MIN))
	end
	stumbleDuration = math.max(0.1, stumbleDuration)

	local stumbleMultiplier = obstacleInstance and tonumber(obstacleInstance:GetAttribute("StumbleSpeedMultiplier"))
	if not stumbleMultiplier then
		stumbleMultiplier = STUMBLE_SPEED_MULTIPLIER
	end
	stumbleMultiplier = math.clamp(stumbleMultiplier, 0.1, 1)

	if state.jumping then
		self:_endJumpState(player, state, true)
	end

	state.stumbling = true
	state.stumbleStartedAt = now
	state.stumbleEndAt = now + stumbleDuration
	state.nextAllowedJumpAt = math.max(state.nextAllowedJumpAt or 0, state.stumbleEndAt)

	local stumbleSpeed = math.max(0, (state.runSpeed or RUN_SPEED) * stumbleMultiplier)
	state.stumbleSpeed = stumbleSpeed
	self:_applyStumbleForce(state, root, stumbleSpeed)

	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
	hum.AutoRotate = true
	hum.Jump = false
	hum:Move(Vector3.zero, false)

	self.stateRemote:FireClient(player, "StumbleState", true, {
		duration = stumbleDuration,
	})
end

function SprintRunManager:OnJumpAnimationEnded(player)
	local state = self.playerState[player]
	if not state or not state.active then return end
	if not state.jumping then return end
	if state.stumbling then return end

end

function SprintRunManager:_isGrounded(hum, root)
	if not hum or not root then
		return false
	end

	if hum.FloorMaterial ~= Enum.Material.Air then
		return true
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { root.Parent }
	rayParams.IgnoreWater = true

	local result = workspace:Raycast(root.Position, Vector3.new(0, -4, 0), rayParams)
	return result ~= nil
end

function SprintRunManager:_clearSingleJumpForce(state, forceField)
	if not state then return end
	local forceObject = state[forceField]
	if forceObject then
		pcall(function() forceObject:Destroy() end)
		state[forceField] = nil
	end

	if state.jumpAttachment and (not state.jumpLinearVelocity) then
		pcall(function() state.jumpAttachment:Destroy() end)
		state.jumpAttachment = nil
	end
end

function SprintRunManager:_clearJumpForce(state)
	if not state then return end
	self:_clearSingleJumpForce(state, "jumpLinearVelocity")

	if state.jumpAttachment then
		pcall(function() state.jumpAttachment:Destroy() end)
		state.jumpAttachment = nil
	end

	state.jumpDirection = nil
end

function SprintRunManager:_finalizeJumpCarryPose(player)
	if not player or not self.WildPetManager then return end
	if type(self.WildPetManager.NormalizeRunnerCaughtPetHold) ~= "function" then return end

	local ok, err = pcall(function()
		self.WildPetManager:NormalizeRunnerCaughtPetHold(player)
	end)
	if not ok then
		warn("[SprintRunManager] Failed to normalize runner catch carry pose:", err)
	end
end

function SprintRunManager:_applyJumpForce(state, root, forwardSpeed)
	self:_clearJumpForce(state)

	local attachment = Instance.new("Attachment")
	attachment.Name = "RunnerJumpAttachment"
	attachment.Parent = root

	local look = root.CFrame.LookVector
	local horizontalLook = Vector3.new(look.X, 0, look.Z)
	if horizontalLook.Magnitude <= 0 then
		horizontalLook = Vector3.new(0, 0, -1)
	else
		horizontalLook = horizontalLook.Unit
	end

	local jumpVelocity = Instance.new("LinearVelocity")
	jumpVelocity.Name = "RunnerJumpVelocity"
	jumpVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	jumpVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	jumpVelocity.MaxForce = math.huge
	jumpVelocity.Attachment0 = attachment
	jumpVelocity.VectorVelocity = (horizontalLook * math.max(0, forwardSpeed or 0)) + Vector3.new(0, JUMP_UPWARD_SPEED, 0)
	jumpVelocity.Parent = root

	state.jumpAttachment = attachment
	state.jumpLinearVelocity = jumpVelocity
	state.jumpDirection = horizontalLook
end

function SprintRunManager:_setJumpForwardOnly(state)
	if not state or not state.jumpLinearVelocity then
		return
	end

	local dir = state.jumpDirection
	if not dir then
		return
	end

	state.jumpLinearVelocity.VectorVelocity = dir * math.max(0, state.jumpForwardSpeed or 0)
end

function SprintRunManager:ScanStartLines()
	for _, line in ipairs(CollectionService:GetTagged(START_LINE_TAG)) do
		if line:IsA("BasePart") then
			self:_registerStartLine(line)
		end
	end

	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == START_LINE_NAME then
			self:_registerStartLine(inst)
		end
	end
end

function SprintRunManager:_registerStartLine(part)
	if self.startLines[part] then return end
	self.startLines[part] = true
	self.startLineConns[part] = part.Touched:Connect(function(otherPart)
		local character = otherPart and otherPart.Parent
		if not character then return end
		local player = self.Players:GetPlayerFromCharacter(character)
		if not player then return end
		self:StartRunning(player, part)
	end)
end

function SprintRunManager:_createCatchHitbox(player)
	local state = self.playerState[player]
	if not state then return end
	local char = player.Character
	local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
	if not root then return end

	local hitbox = Instance.new("Part")
	hitbox.Name = "PetRunCatchHitbox"
	hitbox.Size = HITBOX_SIZE
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.CanQuery = false
	hitbox.CanTouch = true
	hitbox.Anchored = true
	hitbox.Parent = workspace
	hitbox.CFrame = root.CFrame * CFrame.new(0, 0, -3)

	state._hitbox = hitbox
	state._hitboxConn = hitbox.Touched:Connect(function(otherPart)
		if not state.active or not state.jumping then return end
		if not self.WildPetManager then return end
		local model = otherPart:FindFirstAncestorOfClass("Model")
		if not model then return end
		self.WildPetManager:TryAutoPickupWildPet(player, model)
	end)
end

function SprintRunManager:StartRunning(player, startLine)
	if not player then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
	if not hum or not root then return end

	local state = self.playerState[player]
	if state and state.active then return end

	state = state or {}
	self.playerState[player] = state
	state.active = true
	state.jumping = false
	state.lastJumpAt = 0
	state.jumpEndAt = nil
	state.defaultWalkSpeed = hum.WalkSpeed
	state.runSpeed = (startLine and startLine:GetAttribute("RunSpeed")) or RUN_SPEED
	if state.defaultWalkSpeed <= 0 then
		state.defaultWalkSpeed = DEFAULT_WALK_SPEED
	end
	if state.defaultWalkSpeed >= state.runSpeed then
		state.defaultWalkSpeed = DEFAULT_WALK_SPEED
	end
	state.defaultJumpPower = hum.JumpPower
	state.defaultJumpHeight = hum.JumpHeight
	state.defaultAutoRotate = hum.AutoRotate
	state.startLine = startLine
	state.runSpeed = self:GetRunSpeedForPlayer(player, state.runSpeed)
	state.maxStamina = self:GetMaxStaminaForPlayer(player, DEFAULT_STAMINA)
	state.currentStamina = state.maxStamina
	state.staminaDrainPerSecond = STAMINA_DRAIN_PER_SECOND
	state.exhausted = false
	state.lastStaminaUpdateAt = 0
	state.speedPenaltyUntil = 0
	state.speedPenaltyMultiplier = 1
	state.jumpForwardSpeed = math.max(0, state.runSpeed * JUMP_FORWARD_SPEED_MULTIPLIER)
	state.defaultFreefallEnabled = hum:GetStateEnabled(Enum.HumanoidStateType.Freefall)

	player:SetAttribute("RunnerJumping", false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
	hum.JumpPower = 0
	hum.JumpHeight = 0
	hum.WalkSpeed = state.runSpeed
	hum.AutoRotate = true
	self:_createCatchHitbox(player)

	self.stateRemote:FireClient(player, "RunnerState", true, {
		runAnimationId = startLine and startLine:GetAttribute("RunAnimationId") or nil,
		jumpAnimationId = startLine and startLine:GetAttribute("JumpAnimationId") or nil,
		jumpStartAnimationId = startLine and (startLine:GetAttribute("JumpStartAnimationId") or startLine:GetAttribute("JumpAnimationId")) or nil,
		jumpSlideAnimationId = startLine and (startLine:GetAttribute("JumpSlideAnimationId") or startLine:GetAttribute("JumpAnimationId")) or nil,
		stumbleAnimationId = startLine and (startLine:GetAttribute("StumbleAnimationId") or startLine:GetAttribute("JumpSlideAnimationId") or startLine:GetAttribute("JumpAnimationId")) or nil,
		exhaustedSlideAnimationId = startLine and (startLine:GetAttribute("ExhaustedSlideAnimationId") or startLine:GetAttribute("OutOfStaminaSlideAnimationId")) or nil,
		exhaustedLoopAnimationId = startLine and (startLine:GetAttribute("ExhaustedLoopAnimationId") or startLine:GetAttribute("OutOfStaminaLoopAnimationId")) or nil,
		currentStamina = state.currentStamina,
		maxStamina = state.maxStamina,
	})
end

function SprintRunManager:GetRunSpeedForPlayer(player, baseSpeed)
	local speed = baseSpeed or RUN_SPEED
	local upgradeValue = getGemUpgradeValue(player, 3)
	local reward = getGemRewardConfig(self.gemShopFolder, 3)
	return applyGemShopReward(speed, reward, upgradeValue)
end

function SprintRunManager:GetMaxStaminaForPlayer(player, baseStamina)
	local stamina = baseStamina or DEFAULT_STAMINA
	local upgradeValue = getGemUpgradeValue(player, 4)
	local reward = getGemRewardConfig(self.gemShopFolder, 4)
	return applyGemShopReward(stamina, reward, upgradeValue)
end

function SprintRunManager:RequestJump(player)
	local state = self.playerState[player]
	if not state or not state.active then return end

	local now = os.clock()
	if state.jumping then return end
	if state.stumbling then return end
	if state.exhausted then return end
	if now < (state.nextAllowedJumpAt or 0) then return end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
	if not root or not hum then return end

	state.lastJumpAt = now
	state.jumping = true
	state.slideStateSent = false

	local forwardDuration = math.max(MIN_JUMP_DURATION, state.jumpForwardDuration or JUMP_FORWARD_FORCE_DURATION)
	state.slideDuration = forwardDuration
	state.slideEndAt = nil
	state.jumpUpForceEndAt = nil
	state.jumpEndAt = now + forwardDuration
	state.nextAllowedJumpAt = now + math.max(MIN_JUMP_DURATION, forwardDuration + 0.15)
	state.jumpForwardSpeed = math.max(0, (state.runSpeed or RUN_SPEED) * JUMP_FORWARD_SPEED_MULTIPLIER)

	local currentStamina = state.currentStamina or state.maxStamina or DEFAULT_STAMINA
	local staminaCost = math.max(1, math.floor(currentStamina * JUMP_STAMINA_COST_PERCENT + 0.5))
	state.currentStamina = math.max(0, currentStamina - staminaCost)
	if state.currentStamina <= 0 then
		self:_beginExhaustion(player, state, state.runSpeed)
	else
		state.exhausted = false
	end


	self.stateRemote:FireClient(player, "StaminaUpdate", true, {
		current = state.currentStamina,
		max = state.maxStamina or DEFAULT_STAMINA,
		exhausted = state.exhausted == true,
	})

	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
	hum.Jump = false

	self:_applyJumpForce(state, root, state.jumpForwardSpeed)

	pcall(function()
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end)

	player:SetAttribute("RunnerJumping", true)
	self.stateRemote:FireClient(player, "JumpState", true, {
		phase = "Start",
		slideDuration = forwardDuration,
	})
end

function SprintRunManager:GoBackToPlot(player)
	local state = self.playerState[player]
	if not state or not state.active then return end
	if state.isReturning then return end
	if state.jumping then return end
	if state.stumbling then return end
	if state.jumpEndAt and os.clock() < state.jumpEndAt then return end

	state.isReturning = true

	self:StopRunning(player, true)

	local tycoonUtils = self.WildPetManager and self.WildPetManager.TycoonUtils
	local desk
	local tycoonModel

	if tycoonUtils then
		local foundTycoon, foundDesk = tycoonUtils:FindTycoonByOwnerIdWithDesk(player.UserId)
		tycoonModel = foundTycoon
		desk = foundDesk
	end

	if self.WildPetManager then
		pcall(function()
			self.WildPetManager:AutoAdoptCarriedWildPet(player)
		end)
	end

	local returnPart = tycoonUtils and tycoonUtils:GetPreferredReturnPartForTycoon(tycoonModel, desk) or desk
	if returnPart and player.Character then
		local root = player.Character:FindFirstChild("HumanoidRootPart") or player.Character.PrimaryPart
		if root then
			root.CFrame = returnPart.CFrame + Vector3.new(0, 4, 0)
		end
	end

	state.isReturning = false
end

function SprintRunManager:StopRunning(player, notifyClient)
	local state = self.playerState[player]
	if not state or not state.active then return end
	state.active = false
	state.jumping = false
	state.jumpEndAt = nil
	state.jumpUpForceEndAt = nil
	state.jumpForwardForceEndAt = nil
	state.slideEndAt = nil
	state.slideDuration = nil
	state.slideStartedAt = nil
	state.nextAllowedJumpAt = 0
	state.exhausted = false
	state.exhaustedStarted = false
	state.exhaustionStartedAt = nil
	state.exhaustionStartSpeed = nil
	state.exhaustionPhase = nil
	state.speedPenaltyUntil = 0
	state.speedPenaltyMultiplier = 1
	state.slideStateSent = false
	state.stumbling = false
	state.stumbleEndAt = nil
	state.stumbleStartedAt = nil
	state.stumbleSpeed = nil
	self:_clearStumbleForce(state)
	player:SetAttribute("RunnerJumping", false)
	self:_clearJumpForce(state)

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = state.defaultWalkSpeed or DEFAULT_WALK_SPEED
		hum.JumpPower = state.defaultJumpPower or hum.JumpPower
		hum.JumpHeight = state.defaultJumpHeight or hum.JumpHeight
		hum.AutoRotate = state.defaultAutoRotate
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, state.defaultFreefallEnabled ~= false)
		task.delay(0.1, function()
			if hum and hum.Parent then
				hum.WalkSpeed = state.defaultWalkSpeed or DEFAULT_WALK_SPEED
				hum.JumpPower = state.defaultJumpPower or hum.JumpPower
				hum.JumpHeight = state.defaultJumpHeight or hum.JumpHeight
				hum.AutoRotate = state.defaultAutoRotate
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
				hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, state.defaultFreefallEnabled ~= false)
			end
		end)
	end

	if state._hitboxConn then
		state._hitboxConn:Disconnect()
		state._hitboxConn = nil
	end
	if state._hitbox then
		state._hitbox:Destroy()
		state._hitbox = nil
	end

	if notifyClient then
		self.stateRemote:FireClient(player, "ExhaustionState", false)
		self.stateRemote:FireClient(player, "RunnerState", false)
	end
end

return SprintRunManager
