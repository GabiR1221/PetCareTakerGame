local PetFeedingManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HUNGER_TICK_SECONDS = 5
local HUNGER_DECAY_AMOUNT = 1
local DEFAULT_MAX_STAT_VALUE = 100
local MAX_FEED_DISTANCE = 20
local FEED_HOLD_DURATION = 1.2
local DEFAULT_FEED_ANIMATION_ID = "rbxassetid://85424941041976"

function PetFeedingManager:Initialize(stateTable, playersService, petStateManager, saveManager, petMovement)
	self.petState = stateTable or {}
	self.Players = playersService
	self.PetStateManager = petStateManager
	self.SaveManager = saveManager
	self.PetMovement = petMovement
	self.feedRemote = ReplicatedStorage:FindFirstChild("PetFeedEvent")
	self.feedInteractRemote = ReplicatedStorage:FindFirstChild("PetFeedInteractEvent")
	self.activeFeedSessions = self.activeFeedSessions or {}

	if not self.feedRemote then
		self.feedRemote = Instance.new("RemoteEvent")
		self.feedRemote.Name = "PetFeedEvent"
		self.feedRemote.Parent = ReplicatedStorage
	end
	if not self.feedInteractRemote then
		self.feedInteractRemote = Instance.new("RemoteEvent")
		self.feedInteractRemote.Name = "PetFeedInteractEvent"
		self.feedInteractRemote.Parent = ReplicatedStorage
	end

	if self.feedConnection then
		self.feedConnection:Disconnect()
	end
	if self.feedInteractConnection then
		self.feedInteractConnection:Disconnect()
	end
	if self.playerRemovingConnection then
		self.playerRemovingConnection:Disconnect()
	end

	self.feedConnection = self.feedRemote.OnServerEvent:Connect(function(player, petModel)
		self:HandleFeedRequest(player, petModel)
	end)
	self.feedInteractConnection = self.feedInteractRemote.OnServerEvent:Connect(function(player, action, petModel)
		self:HandleFeedInteractEvent(player, action, petModel)
	end)
	self.playerRemovingConnection = self.Players.PlayerRemoving:Connect(function(player)
		self:StopFeedSession(player, true)
	end)

	self:StartHungerDecayLoop()
	return self
end

function PetFeedingManager:GetFoodStatValue(tool, attributeName, fallbackChildName, defaultValue)
	if not tool then return defaultValue end

	local attrValue = tool:GetAttribute(attributeName)
	if attrValue ~= nil then
		local numericAttr = tonumber(attrValue)
		if numericAttr ~= nil then
			return numericAttr
		end
	end

	local child = tool:FindFirstChild(fallbackChildName)
	if child and child:IsA("NumberValue") then
		return tonumber(child.Value) or defaultValue
	end

	return defaultValue
end

function PetFeedingManager:IsValidFoodTool(tool)
	if not tool or not tool:IsA("Tool") then
		return false
	end

	if tool:GetAttribute("IsPetFood") == true then
		return true
	end

	return tool:FindFirstChild("HungerGain") ~= nil or tool:GetAttribute("HungerGain") ~= nil
end

function PetFeedingManager:EnsurePetDefaults(petModel)
	if not petModel then return nil end
	self.petState[petModel] = self.petState[petModel] or {}
	local state = self.petState[petModel]

	if state.hunger == nil then
		state.hunger = DEFAULT_MAX_STAT_VALUE
	end
	if state.happiness == nil then
		state.happiness = DEFAULT_MAX_STAT_VALUE
	end

	if self.PetStateManager and self.PetStateManager.ClampPetCoreStats then
		self.PetStateManager:ClampPetCoreStats(petModel, state)
	else
		state.hunger = math.clamp(tonumber(state.hunger) or DEFAULT_MAX_STAT_VALUE, 0, DEFAULT_MAX_STAT_VALUE)
		state.happiness = math.clamp(tonumber(state.happiness) or DEFAULT_MAX_STAT_VALUE, 0, DEFAULT_MAX_STAT_VALUE)
	end
	return state
end

function PetFeedingManager:GetEquippedFoodTool(character)
	if not character then return nil end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and self:IsValidFoodTool(child) then
			return child
		end
	end
	return nil
end

function PetFeedingManager:ValidateFeedContext(player, petModel)
	if not player or typeof(petModel) ~= "Instance" or not petModel:IsA("Model") then
		return nil
	end

	local character = player.Character
	if not character then return nil end

	local tool = self:GetEquippedFoodTool(character)
	if not self:IsValidFoodTool(tool) then
		return nil
	end

	local state = self.petState[petModel]
	if not state or state.ownerUserId ~= player.UserId or state.wild then
		return nil
	end

	local charRoot = character:FindFirstChild("HumanoidRootPart")
	local petPrimary = petModel.PrimaryPart or petModel:FindFirstChildWhichIsA("BasePart")
	if not charRoot or not petPrimary then
		return nil
	end

	if (charRoot.Position - petPrimary.Position).Magnitude > MAX_FEED_DISTANCE then
		return nil
	end

	return {
		character = character,
		tool = tool,
		state = state,
		charRoot = charRoot,
		petPrimary = petPrimary,
	}
end

function PetFeedingManager:CreateFeedAnimationTrack(character, tool)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animationId = tool and tool:GetAttribute("FeedAnimationId")
	if type(animationId) ~= "string" or animationId == "" then
		animationId = DEFAULT_FEED_ANIMATION_ID
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok then
		return nil
	end

	pcall(function()
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		track:Play(0.1)
	end)
	return track
end

function PetFeedingManager:StartFeedSession(player, petModel, context)
	if not player or not petModel or not context then
		return
	end

	self:StopFeedSession(player, false)

	local petHumanoid = petModel:FindFirstChildOfClass("Humanoid")
	local charHumanoid = context.character:FindFirstChildOfClass("Humanoid")
	local session = {
		player = player,
		petModel = petModel,
		startedAt = os.clock(),
		playerAutoRotate = charHumanoid and charHumanoid.AutoRotate,
		petWalkSpeed = petHumanoid and petHumanoid.WalkSpeed,
		petJumpPower = petHumanoid and petHumanoid.JumpPower,
		petAutoRotate = petHumanoid and petHumanoid.AutoRotate,
		track = self:CreateFeedAnimationTrack(context.character, context.tool),
		active = true,
		cancelToken = 0,
	}

	self.activeFeedSessions[player] = session

	if self.PetMovement and self.PetMovement.StopWandering then
		pcall(function()
			self.PetMovement.StopWandering(petModel)
		end)
	end

	if charHumanoid then
		charHumanoid.AutoRotate = false
	end
	if petHumanoid then
		petHumanoid.AutoRotate = false
		petHumanoid.WalkSpeed = 0
		petHumanoid.JumpPower = 0
		pcall(function()
			petHumanoid:Move(Vector3.zero, true)
		end)
	end

	task.spawn(function()
		while session.active do
			local liveContext = self:ValidateFeedContext(player, petModel)
			if not liveContext then
				break
			end

			local livePetPrimary = petModel.PrimaryPart or liveContext.petPrimary
			if not livePetPrimary or not liveContext.charRoot then
				break
			end

			local charPos = liveContext.charRoot.Position
			local petPos = livePetPrimary.Position
			local charLook = Vector3.new(petPos.X, charPos.Y, petPos.Z)
			local petLook = Vector3.new(charPos.X, petPos.Y, charPos.Z)

			if (charLook - charPos).Magnitude > 0.01 then
				liveContext.charRoot.CFrame = CFrame.lookAt(charPos, charLook)
			end
			if (petLook - petPos).Magnitude > 0.01 then
				livePetPrimary.CFrame = CFrame.lookAt(petPos, petLook)
			end

			if petHumanoid then
				pcall(function()
					petHumanoid:Move(Vector3.zero, true)
				end)
			end

			task.wait(0.05)
		end
		self:StopFeedSession(player, true)
	end)
end

function PetFeedingManager:StopFeedSession(player, restartMovement)
	local session = self.activeFeedSessions and self.activeFeedSessions[player]
	if not session then return end
	session.active = false
	self.activeFeedSessions[player] = nil

	local character = player and player.Character
	local charHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	if charHumanoid and session.playerAutoRotate ~= nil then
		charHumanoid.AutoRotate = session.playerAutoRotate
	end

	local petModel = session.petModel
	local petHumanoid = petModel and petModel:FindFirstChildOfClass("Humanoid")
	if petHumanoid then
		if session.petAutoRotate ~= nil then
			petHumanoid.AutoRotate = session.petAutoRotate
		end
		if session.petWalkSpeed ~= nil then
			petHumanoid.WalkSpeed = session.petWalkSpeed
		end
		if session.petJumpPower ~= nil then
			petHumanoid.JumpPower = session.petJumpPower
		end
	end

	if session.track then
		pcall(function()
			session.track:Stop(0.1)
			session.track:Destroy()
		end)
	end

	if restartMovement and petModel and petModel.Parent and self.PetMovement and self.PetMovement.StartWandering then
		local state = self.petState[petModel]
		if state and not state.wild and state.location == "free" then
			pcall(function()
				self.PetMovement.StartWandering(petModel, nil, nil, state.ownerUserId)
			end)
		end
	end
end

function PetFeedingManager:HandleFeedInteractEvent(player, action, petModel)
	if not player or typeof(action) ~= "string" then return end

	if action == "start" then
		local context = self:ValidateFeedContext(player, petModel)
		if not context then return end
		self:StartFeedSession(player, petModel, context)
		return
	end

	if action == "cancel" then
		local session = self.activeFeedSessions and self.activeFeedSessions[player]
		if not session then
			return
		end

		local cancelToken = os.clock()
		session.cancelToken = cancelToken
		task.delay(0.2, function()
			local current = self.activeFeedSessions and self.activeFeedSessions[player]
			if current and current == session and current.active and current.cancelToken == cancelToken then
				self:StopFeedSession(player, true)
			end
		end)
		return
	end

	if action == "complete" then
		local session = self.activeFeedSessions and self.activeFeedSessions[player]
		if not session or session.petModel ~= petModel then
			-- Fallback for prompt event ordering issues where cancel can arrive first.
			local context = self:ValidateFeedContext(player, petModel)
			if context then
				self:HandleFeedRequest(player, petModel)
			end
			return
		end
		session.cancelToken = 0
		if (os.clock() - session.startedAt) < (FEED_HOLD_DURATION - 0.05) then
			self:StopFeedSession(player, true)
			return
		end

		self:HandleFeedRequest(player, petModel)
		self:StopFeedSession(player, true)
	end
end


function PetFeedingManager:StartHungerDecayLoop()
	if self.hungerDecayStarted then
		return
	end
	self.hungerDecayStarted = true

	task.spawn(function()
		while true do
			task.wait(HUNGER_TICK_SECONDS)

			for petModel, state in pairs(self.petState) do
				if petModel and petModel.Parent and state and state.ownerUserId and not state.wild then
					self:EnsurePetDefaults(petModel)
					local hungerMax = (self.PetStateManager and self.PetStateManager.GetPetStatMax)
						and self.PetStateManager:GetPetStatMax(petModel, "hunger", state)
						or DEFAULT_MAX_STAT_VALUE
					local oldHunger = state.hunger
					state.hunger = math.clamp(oldHunger - HUNGER_DECAY_AMOUNT, 0, hungerMax)
					if state.hunger ~= oldHunger then
						self.PetStateManager:SendStateToOwner(petModel)

						local owner = self.Players:GetPlayerByUserId(state.ownerUserId)
						if owner and self.SaveManager then
							if type(self.SaveManager.MarkDirty) == "function" then
								self.SaveManager:MarkDirty(owner)
							else
								self.SaveManager:ScheduleSave(owner)
							end
						end
					end
				end
			end
		end
	end)
end

function PetFeedingManager:HandleFeedRequest(player, petModel)
	local context = self:ValidateFeedContext(player, petModel)
	if not context then return end
	local tool = context.tool
	local state = context.state

	if tool:GetAttribute("Consumed") == true then
		return
	end

	local hungerGain = math.max(0, self:GetFoodStatValue(tool, "HungerGain", "HungerGain", 0))
	local xpReward = math.max(0, self:GetFoodStatValue(tool, "XPReward", "XPReward", 0))
	if hungerGain <= 0 and xpReward <= 0 then
		return
	end

	self:EnsurePetDefaults(petModel)
	local hungerMax = (self.PetStateManager and self.PetStateManager.GetPetStatMax)
		and self.PetStateManager:GetPetStatMax(petModel, "hunger", state)
		or DEFAULT_MAX_STAT_VALUE
	state.hunger = math.clamp((state.hunger or hungerMax) + hungerGain, 0, hungerMax)
	self.PetStateManager:SendStateToOwner(petModel)

	if xpReward > 0 then
		self.PetStateManager:AddXP(petModel, xpReward)
	end

	tool:SetAttribute("Consumed", true)
	if self.SaveManager then
		self.SaveManager:ScheduleSave(player)
	end

	tool:Destroy()
end

return PetFeedingManager
