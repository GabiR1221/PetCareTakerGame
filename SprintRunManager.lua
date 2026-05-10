local SprintRunManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local START_LINE_TAG = "PetRunStartLine"
local START_LINE_NAME = "PetRunStartLine"
local OBSTACLE_ZONE_TAG = "WildPetZone"
local OBSTACLE_ZONE_NAME = "WildPetZonePart"
local BREAK_WALL_TAG = "RunnerBreakWall"
local BREAK_WALL_NAME = "RunnerBreakWall"
local WILD_PET_SPAWN_AREA_TAG = "WildPetSpawnArea"
local LEGACY_WILD_PET_ZONE_TAG = "WildPetZone"

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
local WALL_BREAK_DEFAULT_TRIGGER_DISTANCE = 10
local WALL_BREAK_DEFAULT_STOP_DISTANCE = 1.8
local WALL_BREAK_APPROACH_SPEED_MULTIPLIER = 1
local WALL_BREAK_KNOCKBACK_SPEED = 34
local WALL_BREAK_COOLDOWN = 0.4

local WILD_CASES_FOLDER_NAME = "WildCases"
local DEFAULT_CASE_EGG = "Starter"
local MAX_PENDING_CASES = 40
local CASE_RESPAWN_INTERVAL = 15
local MAX_LIVE_CASES = 24

local function chooseRandomCaseReward(eggName, luckMultiplier)
	luckMultiplier = tonumber(luckMultiplier) or 1
	local eggs = ReplicatedStorage:FindFirstChild("Eggs")
	local eggInfo = eggs and eggs:FindFirstChild(tostring(eggName or ""))
	if not eggInfo then return nil, nil end
	local dropsFolder = eggInfo:FindFirstChild("Pets") or eggInfo:FindFirstChild("Items")
	if not dropsFolder then return nil, nil end

	local entries, total = {}, 0
	for _, drop in ipairs(dropsFolder:GetChildren()) do
		local weight = tonumber(drop.Value) or 0
		if weight > 0 then
			local itemType = drop:GetAttribute("ItemType") or ((drop:FindFirstChild("ItemType") and drop.ItemType.Value) or "Toy")
			local adjusted = weight * luckMultiplier
			table.insert(entries, {name = drop.Name, weight = adjusted, itemType = tostring(itemType)})
			total += adjusted
		end
	end
	if total <= 0 then return nil, nil end
	local pick = Random.new():NextNumber(0, total)
	local run = 0
	for _, e in ipairs(entries) do
		run += e.weight
		if run >= pick then return e.name, e.itemType end
	end
	local last = entries[#entries]
	return last and last.name, last and last.itemType
end

local function resolveInventoryItemType(itemName, hintedType)
	local hint = tostring(hintedType or "")
	if string.lower(hint) == "accessory" then hint = "Accessory" end
	if string.lower(hint) == "toy" then hint = "Toy" end
	if hint == "Toy" or hint == "Accessory" then
		return hint
	end

	local accessoriesRoot = ReplicatedStorage:FindFirstChild("Accessories")
	if accessoriesRoot and itemName and accessoriesRoot:FindFirstChild(tostring(itemName)) then
		return "Accessory"
	end

	local toysRoot = ReplicatedStorage:FindFirstChild("Toys")
	if toysRoot and itemName and toysRoot:FindFirstChild(tostring(itemName)) then
		return "Toy"
	end

	return "Toy"
end

local function createInventoryItemLocal(player, itemNameText, itemTypeRaw)
	if not player or type(itemNameText) ~= "string" or itemNameText == "" then return false end
	local data = player:FindFirstChild("Data")
	if not data then return false end
	local folderName = tostring(itemTypeRaw) == "Accessory" and "Accessories" or "Toys"
	local target = data:FindFirstChild(folderName)
	if not target then
		target = Instance.new("Folder")
		target.Name = folderName
		target.Parent = data
	end

	local newItem = Instance.new("Folder")
	newItem.Name = tostring(os.time()) .. "_" .. tostring(math.random(1000, 999999))
	newItem.Parent = target

	local itemName = Instance.new("StringValue")
	itemName.Name = "ItemName"
	itemName.Value = itemNameText
	itemName.Parent = newItem

	local itemTypeValue = Instance.new("StringValue")
	itemTypeValue.Name = "ItemType"
	itemTypeValue.Value = tostring(itemTypeRaw or "Toy")
	itemTypeValue.Parent = newItem

	local equipped = Instance.new("BoolValue")
	equipped.Name = "Equipped"
	equipped.Value = false
	equipped.Parent = newItem
	return true
end

local function getPendingCasesJsonValue(player)
	local data = player and player:FindFirstChild("Data")
	local pd = data and data:FindFirstChild("PlayerData")
	if not pd then return nil end
	local v = pd:FindFirstChild("PendingCasesJson")
	if not v then
		v = Instance.new("StringValue")
		v.Name = "PendingCasesJson"
		v.Value = ""
		v.Parent = pd
	end
	return v
end

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

	local upgradedReward
	if exponential.Value then
		upgradedReward = defaultReward.Value + (increasePer.Value ^ upgradeValue)
	else
		upgradedReward = defaultReward.Value + (increasePer.Value * upgradeValue)
	end

	local upgradeRoot = rewardConfig.Parent
	local operatorValue = upgradeRoot and upgradeRoot:FindFirstChild("Operator")
	local operator = operatorValue and tostring(operatorValue.Value) or "x"
	if operator == "+" then
		return baseValue + upgradedReward
	end

	return baseValue * upgradedReward
end



function SprintRunManager:Initialize(playersService, wildPetManager)
	self.Players = playersService
	self.WildPetManager = wildPetManager
	self.playerState = {}
	self.startLines = {}
	self.startLineConns = {}
	self.obstacleZones = {}
	self.breakWalls = {}
	self.obstacleRng = Random.new()
	self.liveObstacleFolder = workspace:FindFirstChild("RunnerLiveObstacles") or Instance.new("Folder")
	self.liveObstacleFolder.Name = "RunnerLiveObstacles"
	self.liveObstacleFolder.Parent = workspace
	self.gemShopFolder = ReplicatedStorage:FindFirstChild("GemShop")
	self.obstacleTemplatesRoot = game:GetService("ServerStorage"):FindFirstChild("RunnerObstacleModels")
	self.wildCaseTemplatesRoot = ServerStorage:FindFirstChild(WILD_CASES_FOLDER_NAME)

	self.stateRemote = getOrCreateRemote("RunnerStateEvent")
	self.actionRemote = getOrCreateRemote("RunnerActionEvent")
	self.pendingCasesByUserId = {}
	self.liveCasesByPart = {}
	self.caseHatchRemote = getOrCreateRemote("CaseHatchEvent")

	self:ScanStartLines()
	self:ScanObstacleZones()
	self:ScanBreakWalls()
	self:_connectRemotes()
	self:_connectPlayers()
	self:_startHeartbeat()
	self:_startCaseSpawnLoop()
	for _, player in ipairs(self.Players:GetPlayers()) do
		player:SetAttribute("RunnerActive", false)
	end
end

function SprintRunManager:_startCaseSpawnLoop()
	task.spawn(function()
		while true do
			task.wait(CASE_RESPAWN_INTERVAL)
			local liveCount = 0
			for _, rec in pairs(self.liveCasesByPart) do
				if rec and rec.instance and rec.instance.Parent then
					liveCount += 1
				end
			end
			if liveCount >= MAX_LIVE_CASES then
				continue
			end
			self:SpawnRunnerCasesForPlayer(nil, math.max(1, math.min(3, MAX_LIVE_CASES - liveCount)))
		end
	end)
end

function SprintRunManager:_connectPlayers()
	self.Players.PlayerRemoving:Connect(function(player)
		self:StopRunning(player, false)
		self:PersistPendingCases(player)
		self.playerState[player] = nil
	end)

	self.Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("RunnerActive", false)
		task.defer(function()
			-- Data can still be hydrating from datastore; load pending cases after it settles.
			local data = player:WaitForChild("Data", 15)
			local playerData = data and data:WaitForChild("PlayerData", 15)
			if playerData then
				playerData:WaitForChild("PendingCasesJson", 15)
			end
			task.wait(2)
			self:LoadPendingCases(player)
		end)
		player.CharacterRemoving:Connect(function()
			self:StopRunning(player, false)
		end)
	end)
end

function SprintRunManager:_connectRemotes()
	self.actionRemote.OnServerEvent:Connect(function(player, action, payload)
		if action == "Jump" then
			self:RequestJump(player)
		elseif action == "GoBack" then
			self:GoBackToPlot(player)
		elseif action == "JumpAnimEnded" then
			self:OnJumpAnimationEnded(player)
		elseif action == "WallBreakAnimEnded" then
			self:OnWallBreakAnimationEnded(player)
		elseif action == "WallBreakFailMarker" then
			self:OnWallBreakFailMarker(player)
		elseif action == "ClaimPendingCase" then
			self:ClaimPendingCase(player, tostring(payload))
		elseif action == "RequestPendingCasesSync" then
			if self.pendingCasesByUserId[player.UserId] == nil then
				self:LoadPendingCases(player)
			end
			self.stateRemote:FireClient(player, "PendingCasesUpdate", self.pendingCasesByUserId[player.UserId] or {})
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

function SprintRunManager:_enterCollapsedExhaustion(player, state)
	if not state then
		return
	end

	state.exhausted = true
	state.exhaustedStarted = false
	state.exhaustionStartedAt = nil
	state.exhaustionDecelDuration = 0
	state.exhaustionStartSpeed = 0
	state.exhaustionPhase = "Collapsed"
	state.pendingFailExhaustion = false
	state.pendingFailExhaustionAt = nil
	state.failKnockbackUntil = nil
	state.failKnockbackDirection = nil

	self.stateRemote:FireClient(player, "ExhaustionState", true, {
		phase = "Collapsed",
	})
	self.stateRemote:FireClient(player, "StaminaUpdate", true, {
		current = state.currentStamina,
		max = state.maxStamina or DEFAULT_STAMINA,
		exhausted = true,
		phase = "Collapsed",
	})
end

function SprintRunManager:_restoreCharacterMovement(player, state)
	local char = player and player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return false end

	local targetWalkSpeed = (state and state.defaultWalkSpeed) or DEFAULT_WALK_SPEED
	if targetWalkSpeed <= 0 then
		targetWalkSpeed = DEFAULT_WALK_SPEED
	end

	hum.WalkSpeed = targetWalkSpeed
	hum.JumpPower = (state and state.defaultJumpPower) or hum.JumpPower
	hum.JumpHeight = (state and state.defaultJumpHeight) or hum.JumpHeight
	hum.AutoRotate = (state and state.defaultAutoRotate) ~= false
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, (state and state.defaultFreefallEnabled) ~= false)
	return true
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
			if state.pendingFailExhaustion and now >= (state.pendingFailExhaustionAt or 0) then
				self:_enterCollapsedExhaustion(player, state)
			end

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
				
			elseif state.wallBreaking then
				local wallPart = state.wallBreakWall
				if (not wallPart) or (not wallPart.Parent) then
					self:_clearWallBreakState(player, state, false, false)
				elseif state.wallBreakPhase == "Approach" then
					local targetPos = self:_getWallApproachTargetPosition(root, wallPart)
					local toTarget = targetPos - root.Position
					local horizontal = Vector3.new(toTarget.X, 0, toTarget.Z)
					local dist = horizontal.Magnitude
					local stopDistance = state.wallBreakStopDistance or WALL_BREAK_DEFAULT_STOP_DISTANCE
					if dist <= stopDistance then
						if state.wallBreakSuccess == true then
							root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
						end
						state.wallBreakPhase = "Animating"
						self.stateRemote:FireClient(player, "WallBreakState", true, {
							phase = "Animating",
							success = state.wallBreakSuccess == true,
							successAnimationId = state.wallBreakSuccessAnimationId,
							failedAnimationId = state.wallBreakFailAnimationId,
							wallPart = wallPart,
						})
					else
						local moveDir = horizontal.Unit
						local approachSpeed = math.max(0, (state.runSpeed or RUN_SPEED) * WALL_BREAK_APPROACH_SPEED_MULTIPLIER)
						hum.WalkSpeed = approachSpeed
						hum.JumpPower = 0
						hum.JumpHeight = 0
						hum.AutoRotate = true
						hum.Jump = false
						hum:Move(moveDir, false)
						root.AssemblyLinearVelocity = Vector3.new(moveDir.X * approachSpeed, root.AssemblyLinearVelocity.Y, moveDir.Z * approachSpeed)
					end
				end
			end

			if state.jumping and state.jumpForwardForceEndAt and os.clock() >= state.jumpForwardForceEndAt then
				state.jumpForwardForceEndAt = nil
			end

			dt = math.max(dt or 0, 0)
			local maxStamina = state.maxStamina or DEFAULT_STAMINA
			if not state.exhausted and not state.wallBreaking and not state.pendingFailExhaustion then
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
			elseif state.failKnockbackUntil and now <= state.failKnockbackUntil and state.failKnockbackDirection then
				local dir = state.failKnockbackDirection
				hum.WalkSpeed = 0
				hum.JumpPower = 0
				hum.JumpHeight = 0
				hum.AutoRotate = false
				hum.Jump = false
				hum:Move(Vector3.zero, false)
				root.AssemblyLinearVelocity = Vector3.new(
					-dir.X * (WALL_BREAK_KNOCKBACK_SPEED * 1.2),
					root.AssemblyLinearVelocity.Y,
					-dir.Z * (WALL_BREAK_KNOCKBACK_SPEED * 1.2)
				)
			elseif state.wallBreaking then
				if state.wallBreakPhase == "Animating" then
					local isFailAnim = state.wallBreakSuccess == false
					if (not isFailAnim) or (isFailAnim and not state.wallBreakFailLocked) then
						local wallBreakSpeed = state.runSpeed or RUN_SPEED
						hum.WalkSpeed = wallBreakSpeed
						hum.JumpPower = 0
						hum.JumpHeight = 0
						hum.AutoRotate = true
						hum.Jump = false
						local wallBreakDir = root.CFrame.LookVector
						hum:Move(wallBreakDir, false)
						root.AssemblyLinearVelocity = Vector3.new(wallBreakDir.X * wallBreakSpeed, root.AssemblyLinearVelocity.Y, wallBreakDir.Z * wallBreakSpeed)
					else
						hum.WalkSpeed = 0
						hum.JumpPower = 0
						hum.JumpHeight = 0
						hum.AutoRotate = false
						hum.Jump = false
						hum:Move(Vector3.zero, false)
					end
				else
					local wallBreakSpeed = state.runSpeed or RUN_SPEED
					hum.WalkSpeed = wallBreakSpeed
					hum.JumpPower = 0
					hum.JumpHeight = 0
					hum.AutoRotate = true
					hum.Jump = false
					local wallBreakDir = root.CFrame.LookVector
					hum:Move(wallBreakDir, false)
					root.AssemblyLinearVelocity = Vector3.new(wallBreakDir.X * wallBreakSpeed, root.AssemblyLinearVelocity.Y, wallBreakDir.Z * wallBreakSpeed)
				end
			elseif state.pendingFailExhaustion then
				hum.WalkSpeed = 0
				hum.JumpPower = 0
				hum.JumpHeight = 0
				hum.AutoRotate = false
				hum.Jump = false
				hum:Move(Vector3.zero, false)
				if state.failKnockbackUntil and now <= state.failKnockbackUntil and state.failKnockbackDirection then
					local dir = state.failKnockbackDirection
					root.AssemblyLinearVelocity = Vector3.new(
						-dir.X * (WALL_BREAK_KNOCKBACK_SPEED * 1.2),
						root.AssemblyLinearVelocity.Y,
						-dir.Z * (WALL_BREAK_KNOCKBACK_SPEED * 1.2)
					)
				end
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

			self:_tryBeginWallBreak(player, state, root)
			
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

function SprintRunManager:ScanBreakWalls()
	for _, wall in ipairs(CollectionService:GetTagged(BREAK_WALL_TAG)) do
		if wall:IsA("BasePart") then
			self:_registerBreakWall(wall)
		end
	end

	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == BREAK_WALL_NAME then
			self:_registerBreakWall(inst)
		end
	end
end

function SprintRunManager:_registerBreakWall(wall)
	if self.breakWalls[wall] then return end
	self.breakWalls[wall] = true
	if wall:GetAttribute("BreakDefaultTransparency") == nil then
		wall:SetAttribute("BreakDefaultTransparency", wall.Transparency)
	end
	if wall:GetAttribute("BreakDefaultCanCollide") == nil then
		wall:SetAttribute("BreakDefaultCanCollide", wall.CanCollide)
	end
	wall.Destroying:Connect(function()
		self.breakWalls[wall] = nil
	end)
end

function SprintRunManager:_getClosestBreakWall(root)
	if not root then return nil, nil end
	local nearestWall = nil
	local nearestDistance = nil
	local look = root.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude <= 0 then
		forward = Vector3.new(0, 0, -1)
	else
		forward = forward.Unit
	end
	for wall in pairs(self.breakWalls) do
		if wall and wall.Parent then
			local closest = self:_getWallApproachTargetPosition(root, wall)
			local offset = closest - root.Position
			local horizontal = Vector3.new(offset.X, 0, offset.Z)
			local dist = horizontal.Magnitude
			if dist <= 0 then
				continue
			end
			local toWall = horizontal.Unit
			if forward:Dot(toWall) < 0.2 then
				continue
			end
			local triggerDistance = tonumber(wall:GetAttribute("BreakTriggerDistance")) or WALL_BREAK_DEFAULT_TRIGGER_DISTANCE
			if dist <= triggerDistance and (not nearestDistance or dist < nearestDistance) then
				nearestDistance = dist
				nearestWall = wall
			end
		else
			self.breakWalls[wall] = nil
		end
	end
	return nearestWall, nearestDistance
end

function SprintRunManager:_getWallApproachTargetPosition(root, wall)
	if not root or not wall then
		return Vector3.zero
	end
	local localPos = wall.CFrame:PointToObjectSpace(root.Position)
	local halfSize = wall.Size * 0.5
	local x = math.clamp(localPos.X, -halfSize.X, halfSize.X)
	local y = math.clamp(localPos.Y, -halfSize.Y, halfSize.Y)
	local z = math.clamp(localPos.Z, -halfSize.Z, halfSize.Z)
	return wall.CFrame:PointToWorldSpace(Vector3.new(x, y, z))
end

function SprintRunManager:_tryBeginWallBreak(player, state, root)
	if not state or not state.active then return end
	if state.wallBreaking or state.jumping or state.stumbling or state.exhausted then return end
	if os.clock() < (state.wallBreakCooldownUntil or 0) then return end

	local wall = self:_getClosestBreakWall(root)
	if not wall then return end
	if state.brokenWalls and state.brokenWalls[wall] then return end

	local staminaRequired = math.max(0, tonumber(wall:GetAttribute("BreakStaminaRequired")) or 0)
	local currentStamina = tonumber(state.currentStamina) or 0
	local success = currentStamina >= staminaRequired

	state.wallBreaking = true
	state.wallBreakWall = wall
	state.wallBreakPhase = "Approach"
	state.wallBreakSuccess = success
	state.wallBreakKnockbackApplied = false
	state.wallBreakFailLocked = false
	state.wallBreakTriggeredAt = os.clock()
	state.wallBreakStopDistance = tonumber(wall:GetAttribute("BreakStopDistance")) or WALL_BREAK_DEFAULT_STOP_DISTANCE
	state.wallBreakSuccessAnimationId = wall:GetAttribute("BreakSuccessAnimationId")
		or (state.startLine and state.startLine:GetAttribute("BreakSuccessAnimationId"))
	state.wallBreakFailAnimationId = wall:GetAttribute("BreakFailAnimationId")
		or (state.startLine and state.startLine:GetAttribute("BreakFailAnimationId"))
	state.wallBreakCooldownUntil = os.clock() + WALL_BREAK_COOLDOWN

	if success and staminaRequired > 0 then
		state.currentStamina = math.max(0, currentStamina - staminaRequired)
		self.stateRemote:FireClient(player, "StaminaUpdate", true, {
			current = state.currentStamina,
			max = state.maxStamina or DEFAULT_STAMINA,
			exhausted = state.exhausted == true,
		})
	end

	self.stateRemote:FireClient(player, "WallBreakState", true, {
		phase = "Approach",
		success = success,
	})
end

function SprintRunManager:_clearWallBreakState(player, state, unlock, setCooldown)
	if not state then return end
	state.wallBreaking = false
	state.wallBreakPhase = nil
	state.wallBreakSuccess = nil
	state.wallBreakKnockbackApplied = false
	state.wallBreakFailLocked = false
	state.wallBreakTriggeredAt = nil
	state.wallBreakStopDistance = nil
	state.wallBreakSuccessAnimationId = nil
	state.wallBreakFailAnimationId = nil
	state.wallBreakWall = nil
	if setCooldown then
		state.wallBreakCooldownUntil = os.clock() + WALL_BREAK_COOLDOWN
	end
	if unlock then
		self.stateRemote:FireClient(player, "WallBreakState", false)
	end
end

function SprintRunManager:OnWallBreakAnimationEnded(player)
	local state = self.playerState[player]
	if not state or not state.active or not state.wallBreaking then return end
	local success = state.wallBreakSuccess == true

	if success then
		state.brokenWalls = state.brokenWalls or {}
		local brokenWall = state.wallBreakWall
		if brokenWall then
			state.brokenWalls[brokenWall] = true
		end
		self:_clearWallBreakState(player, state, true, true)
		return
	end

	state.currentStamina = 0
	if not state.wallBreakKnockbackApplied then
		self:OnWallBreakFailMarker(player)
	end
	state.pendingFailExhaustion = true
	state.pendingFailExhaustionAt = os.clock() + 0.28
	self.stateRemote:FireClient(player, "StaminaUpdate", true, {
		current = state.currentStamina,
		max = state.maxStamina or DEFAULT_STAMINA,
		exhausted = false,
	})
	self:_clearWallBreakState(player, state, true, true)
end

function SprintRunManager:OnWallBreakFailMarker(player)
	local state = self.playerState[player]
	if not state or not state.active then return end
	if not state.wallBreaking and not state.pendingFailExhaustion then return end
	if state.wallBreaking and state.wallBreakSuccess == true then return end
	if state.wallBreakKnockbackApplied then return end

	local char = player.Character
	local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
	if not root then return end

	state.wallBreakKnockbackApplied = true
	state.wallBreakFailLocked = true
	local look = root.CFrame.LookVector
	local horizontal = Vector3.new(look.X, 0, look.Z)
	if horizontal.Magnitude <= 0 then
		horizontal = Vector3.new(0, 0, -1)
	else
		horizontal = horizontal.Unit
	end
	
	state.failKnockbackDirection = horizontal
	state.failKnockbackUntil = os.clock() + 0.4

	root.AssemblyLinearVelocity = Vector3.new(
		-horizontal.X * (WALL_BREAK_KNOCKBACK_SPEED * 1.2),
		root.AssemblyLinearVelocity.Y,
		-horizontal.Z * (WALL_BREAK_KNOCKBACK_SPEED * 1.2)
	)

	local impulseVector = Vector3.new(
		-horizontal.X * (WALL_BREAK_KNOCKBACK_SPEED * 5) * root.AssemblyMass,
		0,
		-horizontal.Z * (WALL_BREAK_KNOCKBACK_SPEED * 5) * root.AssemblyMass
	)
	pcall(function()
		root:ApplyImpulse(impulseVector)
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
	state.brokenWalls = {}
	state.wallBreakFailLocked = false
	state.pendingFailExhaustion = false
	state.pendingFailExhaustionAt = nil
	state.failKnockbackUntil = nil
	state.failKnockbackDirection = nil
	state.jumpForwardSpeed = math.max(0, state.runSpeed * JUMP_FORWARD_SPEED_MULTIPLIER)
	state.defaultFreefallEnabled = hum:GetStateEnabled(Enum.HumanoidStateType.Freefall)

	player:SetAttribute("RunnerActive", true)
	player:SetAttribute("RunnerJumping", false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
	hum.JumpPower = 0
	hum.JumpHeight = 0
	hum.WalkSpeed = state.runSpeed
	hum.AutoRotate = true
	self:_createCatchHitbox(player)
	self:SpawnRunnerCasesForPlayer(player, 4)

	self.stateRemote:FireClient(player, "RunnerState", true, {
		runAnimationId = startLine and startLine:GetAttribute("RunAnimationId") or nil,
		jumpAnimationId = startLine and startLine:GetAttribute("JumpAnimationId") or nil,
		jumpStartAnimationId = startLine and (startLine:GetAttribute("JumpStartAnimationId") or startLine:GetAttribute("JumpAnimationId")) or nil,
		jumpSlideAnimationId = startLine and (startLine:GetAttribute("JumpSlideAnimationId") or startLine:GetAttribute("JumpAnimationId")) or nil,
		stumbleAnimationId = startLine and (startLine:GetAttribute("StumbleAnimationId") or startLine:GetAttribute("JumpSlideAnimationId") or startLine:GetAttribute("JumpAnimationId")) or nil,
		exhaustedSlideAnimationId = startLine and (startLine:GetAttribute("ExhaustedSlideAnimationId") or startLine:GetAttribute("OutOfStaminaSlideAnimationId")) or nil,
		exhaustedLoopAnimationId = startLine and (startLine:GetAttribute("ExhaustedLoopAnimationId") or startLine:GetAttribute("OutOfStaminaLoopAnimationId")) or nil,
		breakSuccessAnimationId = startLine and startLine:GetAttribute("BreakSuccessAnimationId") or nil,
		breakFailAnimationId = startLine and startLine:GetAttribute("BreakFailAnimationId") or nil,
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

function SprintRunManager:PersistPendingCases(player)
	local list = self.pendingCasesByUserId[player.UserId] or {}
	local jsonValue = getPendingCasesJsonValue(player)
	if not jsonValue then return end
	local ok, encoded = pcall(function() return HttpService:JSONEncode(list) end)
	jsonValue.Value = ok and encoded or "[]"
end

function SprintRunManager:LoadPendingCases(player)
	local jsonValue = getPendingCasesJsonValue(player)
	if not jsonValue then return end
	local decoded = {}
	if jsonValue.Value ~= "" then
		local ok, data = pcall(function() return HttpService:JSONDecode(jsonValue.Value) end)
		if ok and type(data) == "table" then decoded = data end
	end
	self.pendingCasesByUserId[player.UserId] = decoded
	self.stateRemote:FireClient(player, "PendingCasesUpdate", decoded)
end

function SprintRunManager:_extractZoneIdFromName(zoneFolderName)
	local num = tostring(zoneFolderName or ""):match("%d+")
	return tonumber(num)
end

function SprintRunManager:_resolveZoneIdFromValue(raw)
	if raw == nil then return nil end
	if type(raw) == "number" then
		return tonumber(raw)
	end
	local asText = tostring(raw)
	return tonumber(asText) or tonumber(asText:match("%d+"))
end

function SprintRunManager:_getCaseTemplatesForZoneId(zoneId)
	if not self.wildCaseTemplatesRoot then return {} end
	local candidates = {}
	local rootLevelFallback = {}
	local allZoned = {}
	for _, child in ipairs(self.wildCaseTemplatesRoot:GetChildren()) do
		if child:IsA("Folder") then
			local folderZone = self:_extractZoneIdFromName(child.Name)
			for _, template in ipairs(child:GetChildren()) do
				if template:IsA("BasePart") or template:IsA("Model") then
					table.insert(allZoned, template)
					if folderZone == zoneId then
						table.insert(candidates, template)
					end
				end
			end
		elseif child:IsA("BasePart") or child:IsA("Model") then
			table.insert(rootLevelFallback, child)
		end
	end
	if zoneId == nil then
		if #allZoned > 0 then
			return allZoned
		end
		return rootLevelFallback
	end
	if #candidates == 0 then
		-- Fallback only to root-level generic templates, never to other ZoneX folders.
		return rootLevelFallback
	end
	return candidates
end

function SprintRunManager:_getRunnerCaseSpawnAreas()
	local all = CollectionService:GetTagged(WILD_PET_SPAWN_AREA_TAG)
	local legacy = CollectionService:GetTagged(LEGACY_WILD_PET_ZONE_TAG)
	local valid = {}
	for _, area in ipairs(all) do
		if area and area:IsA("BasePart") and area.Parent then
			table.insert(valid, area)
		end
	end
	for _, area in ipairs(legacy) do
		if area and area:IsA("BasePart") and area.Parent then
			table.insert(valid, area)
		end
	end

	-- Fallback 1: WildPetManager-discovered spawn areas
	if #valid == 0 and self.WildPetManager and type(self.WildPetManager.spawnAreas) == "table" then
		for _, area in ipairs(self.WildPetManager.spawnAreas) do
			if area and area:IsA("BasePart") and area.Parent then
				table.insert(valid, area)
			end
		end
	end

	-- Fallback 2: runner obstacle zones, if no wild-pet spawn areas were found
	if #valid == 0 and type(self.obstacleZones) == "table" then
		for _, area in ipairs(self.obstacleZones) do
			if area and area:IsA("BasePart") and area.Parent then
				table.insert(valid, area)
			end
		end
	end

	return valid
end


function SprintRunManager:_addPendingCase(player, caseTemplate)
	if not player or not caseTemplate then return end
	local userId = player.UserId
	self.pendingCasesByUserId[userId] = self.pendingCasesByUserId[userId] or {}
	local list = self.pendingCasesByUserId[userId]
	if #list >= MAX_PENDING_CASES then return end
	local id = HttpService:GenerateGUID(false)
	list[#list+1] = {
		id = id,
		name = caseTemplate.Name,
		image = tostring(caseTemplate:GetAttribute("ImageId") or ""),
		egg = tostring(caseTemplate:GetAttribute("EggName") or DEFAULT_CASE_EGG),
		itemTypeHint = tostring(caseTemplate:GetAttribute("RewardItemType") or caseTemplate:GetAttribute("ItemType") or ""),
	}
	self:PersistPendingCases(player)
end

function SprintRunManager:ClaimPendingCase(player, caseId)
	local list = self.pendingCasesByUserId[player.UserId] or {}
	for i, c in ipairs(list) do
		if c.id == caseId then
			table.remove(list, i)
			local itemName, rolledType = chooseRandomCaseReward(c.egg, 1)
			local itemType = resolveInventoryItemType(itemName, c.itemTypeHint ~= "" and c.itemTypeHint or rolledType)
			if itemName then
				local granted = false
				if _G.createInventoryItem then
					local ok, created = pcall(function()
						return _G.createInventoryItem(player, itemName, itemType)
					end)
					granted = ok and created == true
				end
				if not granted then
					createInventoryItemLocal(player, itemName, itemType)
				end
			end
			self.stateRemote:FireClient(player, "CaseClaimResult", {id = caseId, itemName = itemName, itemType = itemType, sourceEgg = c.egg})
			if itemName then
				self.caseHatchRemote:FireClient(player, "PlayHatch", c.egg, itemName)
			end
			self:PersistPendingCases(player)
			self.stateRemote:FireClient(player, "PendingCasesUpdate", list)
			return
		end
	end
end

function SprintRunManager:_spawnRunnerCaseForZone(zonePart)
	if not self.wildCaseTemplatesRoot or not zonePart then return end
	local zoneId = self:_resolveZoneIdFromValue(zonePart:GetAttribute("ZoneId"))
	local templates = self:_getCaseTemplatesForZoneId(zoneId)
	if #templates == 0 then return end
	local totalWeight = 0
	for _, t in ipairs(templates) do
		totalWeight += math.max(0, tonumber(t:GetAttribute("SpawnWeight")) or 1)
	end
	local pick = Random.new():NextNumber(0, math.max(1, totalWeight))
	local run = 0
	local template = templates[1]
	for _, t in ipairs(templates) do
		run += math.max(0, tonumber(t:GetAttribute("SpawnWeight")) or 1)
		if pick <= run then
			template = t
			break
		end
	end
	if not template:IsA("BasePart") and not template:IsA("Model") then return end
	local case = template:Clone()
	case.Parent = self.liveObstacleFolder
	local base = case:IsA("Model") and (case.PrimaryPart or case:FindFirstChildWhichIsA("BasePart")) or case
	if not base then case:Destroy() return end
	if case:IsA("Model") and not case.PrimaryPart then case.PrimaryPart = base end
	local size = zonePart.Size
	local pos = zonePart.Position + Vector3.new((math.random()-0.5)*size.X*0.8, 3, (math.random()-0.5)*size.Z*0.8)
	if case:IsA("Model") then case:PivotTo(CFrame.new(pos)) else case.CFrame = CFrame.new(pos) end
	self.liveCasesByPart[base] = {instance = case, template = template}
	base.Touched:Connect(function(hit)
		local ch = hit and hit.Parent
		local plr = ch and self.Players:GetPlayerFromCharacter(ch)
		if not plr or plr:GetAttribute("RunnerActive") ~= true then return end
		local rec = self.liveCasesByPart[base]
		if not rec then return end
		self:_addPendingCase(plr, rec.template)
		self.liveCasesByPart[base] = nil
		rec.instance:Destroy()
	end)
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

	-- Safety net: after teleporting back, force movement stats to defaults in case
	-- an in-flight sprint heartbeat frame tries to overwrite humanoid values.
	for i = 0, 3 do
		task.delay(i * 0.08, function()
			self:_restoreCharacterMovement(player, state)
		end)
	end

	state.isReturning = false
	self.stateRemote:FireClient(player, "PendingCasesUpdate", self.pendingCasesByUserId[player.UserId] or {})
end

function SprintRunManager:SpawnRunnerCasesForPlayer(player, maxPerRun)
	maxPerRun = tonumber(maxPerRun) or 4
	local areas = self:_getRunnerCaseSpawnAreas()
	if #areas == 0 then
		warn("[SprintRunManager] No valid areas found for runner cases. Tag spawn parts with WildPetSpawnArea or configure WildPetManager areas.")
		return
	end
	local spawned = 0
	for _, area in ipairs(areas) do
		if spawned >= maxPerRun then break end
		local before = #self.liveObstacleFolder:GetChildren()
		self:_spawnRunnerCaseForZone(area)
		local after = #self.liveObstacleFolder:GetChildren()
		if after > before then
			spawned += 1
		end
	end
	if spawned == 0 then
		warn("[SprintRunManager] 0 runner cases spawned. Check WildCases/ZoneX folder names and ZoneId attributes on spawn parts.")
	end
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
	state.wallBreaking = false
	state.wallBreakPhase = nil
	state.wallBreakSuccess = nil
	state.wallBreakKnockbackApplied = false
	state.wallBreakFailLocked = false
	state.wallBreakWall = nil
	state.brokenWalls = {}
	state.wallBreakCooldownUntil = 0
	state.pendingFailExhaustion = false
	state.pendingFailExhaustionAt = nil
	state.failKnockbackUntil = nil
	state.failKnockbackDirection = nil
	state.stumbleEndAt = nil
	state.stumbleStartedAt = nil
	state.stumbleSpeed = nil
	player:SetAttribute("RunnerActive", false)
	self:_clearStumbleForce(state)
	player:SetAttribute("RunnerJumping", false)
	self:_clearJumpForce(state)

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		self:_restoreCharacterMovement(player, state)
		task.delay(0.1, function()
			self:_restoreCharacterMovement(player, state)
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
