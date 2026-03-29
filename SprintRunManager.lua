local SprintRunManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local START_LINE_TAG = "PetRunStartLine"
local START_LINE_NAME = "PetRunStartLine"

local RUN_SPEED = 28
local DEFAULT_WALK_SPEED = 16
local DEFAULT_STAMINA = 50
local STAMINA_DRAIN_PER_SECOND = 14
local JUMP_DURATION = 1
local JUMP_FORCE_DURATION = 0.5
local JUMP_PUSH_FORCE = 36
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
	self.gemShopFolder = ReplicatedStorage:FindFirstChild("GemShop")

	self.stateRemote = getOrCreateRemote("RunnerStateEvent")
	self.actionRemote = getOrCreateRemote("RunnerActionEvent")

	self:ScanStartLines()
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
		end
	end)
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

			if state.jumpEndAt and os.clock() >= state.jumpEndAt then
				self:_clearJumpForce(state)
				state.jumping = false
				state.jumpEndAt = nil
				hum.JumpPower = 0
				hum.JumpHeight = 0
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
				player:SetAttribute("RunnerJumping", false)
				self.stateRemote:FireClient(player, "JumpState", false)
			end
			if state.jumpForceEndAt and os.clock() >= state.jumpForceEndAt then
				self:_clearJumpForce(state)
				state.jumpForceEndAt = nil
			end
			
			dt = math.max(dt or 0, 0)
			local maxStamina = state.maxStamina or DEFAULT_STAMINA
			if not state.exhausted then
				state.currentStamina = math.max(0, (state.currentStamina or maxStamina) - (state.staminaDrainPerSecond or STAMINA_DRAIN_PER_SECOND) * dt)
				if state.currentStamina <= 0 then
					state.exhausted = true
					state.currentStamina = 0
				end
			end


			local speed = state.runSpeed or RUN_SPEED
			local canMove = (not state.exhausted) and (not state.jumping)
			if not canMove then
				if hum.WalkSpeed ~= 0 then
					hum.WalkSpeed = 0
				end
				hum.JumpPower = 0
				hum.JumpHeight = 0
				hum.AutoRotate = false
				hum.Jump = false
				hum:Move(Vector3.zero, false)
				root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
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
				})
			end
		end
	end)
end

function SprintRunManager:_clearJumpForce(state)
	if not state then return end
	if state.jumpLinearVelocity then
		pcall(function() state.jumpLinearVelocity:Destroy() end)
		state.jumpLinearVelocity = nil
	end
	if state.jumpAttachment then
		pcall(function() state.jumpAttachment:Destroy() end)
		state.jumpAttachment = nil
	end
end

function SprintRunManager:_applyJumpForce(state, root)
	self:_clearJumpForce(state)
	local attachment = Instance.new("Attachment")
	attachment.Name = "RunnerJumpAttachment"
	attachment.Parent = root

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "RunnerJumpVelocity"
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linearVelocity.MaxForce = math.huge
	linearVelocity.VectorVelocity = (root.CFrame.LookVector * JUMP_PUSH_FORCE) + Vector3.new(0, 8, 0)
	linearVelocity.Attachment0 = attachment
	linearVelocity.Parent = root

	state.jumpAttachment = attachment
	state.jumpLinearVelocity = linearVelocity
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

	player:SetAttribute("RunnerJumping", false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	hum.JumpPower = 0
	hum.JumpHeight = 0
	hum.WalkSpeed = state.runSpeed
	hum.AutoRotate = true
	self:_createCatchHitbox(player)

	self.stateRemote:FireClient(player, "RunnerState", true, {
		runAnimationId = startLine and startLine:GetAttribute("RunAnimationId") or nil,
		jumpAnimationId = startLine and startLine:GetAttribute("JumpAnimationId") or nil,
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
	if state.exhausted then return end
	if now < (state.nextAllowedJumpAt or 0) then return end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
	if not root or not hum then return end

	state.lastJumpAt = now
	state.jumping = true
	state.jumpEndAt = now + JUMP_DURATION
	state.jumpForceEndAt = now + JUMP_FORCE_DURATION
	state.nextAllowedJumpAt = state.jumpEndAt

	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	hum.Jump = false
	self:_applyJumpForce(state, root)
	player:SetAttribute("RunnerJumping", true)
	self.stateRemote:FireClient(player, "JumpState", true)
end

function SprintRunManager:GoBackToPlot(player)
	local state = self.playerState[player]
	if not state or not state.active then return end
	if state.isReturning then return end
	state.isReturning = true

	self:StopRunning(player, true)
	
	local tycoonUtils = self.WildPetManager and self.WildPetManager.TycoonUtils
	local desk

	if tycoonUtils then
		local _, foundDesk = tycoonUtils:FindTycoonByOwnerIdWithDesk(player.UserId)
		desk = foundDesk
	end

	if desk and player.Character then
		local root = player.Character:FindFirstChild("HumanoidRootPart") or player.Character.PrimaryPart
		if root then
			root.CFrame = desk.CFrame + Vector3.new(0, 4, 0)
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
	state.jumpForceEndAt = nil
	state.nextAllowedJumpAt = 0
	state.exhausted = false
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
		task.delay(0.1, function()
			if hum and hum.Parent then
				hum.WalkSpeed = state.defaultWalkSpeed or DEFAULT_WALK_SPEED
				hum.JumpPower = state.defaultJumpPower or hum.JumpPower
				hum.JumpHeight = state.defaultJumpHeight or hum.JumpHeight
				hum.AutoRotate = state.defaultAutoRotate
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
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
		self.stateRemote:FireClient(player, "RunnerState", false)
	end
end

return SprintRunManager
