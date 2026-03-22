local PetFeedingManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HUNGER_TICK_SECONDS = 5
local HUNGER_DECAY_AMOUNT = 1
local MAX_STAT_VALUE = 100
local MAX_FEED_DISTANCE = 20

function PetFeedingManager:Initialize(stateTable, playersService, petStateManager, saveManager)
	self.petState = stateTable or {}
	self.Players = playersService
	self.PetStateManager = petStateManager
	self.SaveManager = saveManager
	self.feedRemote = ReplicatedStorage:FindFirstChild("PetFeedEvent")

	if not self.feedRemote then
		self.feedRemote = Instance.new("RemoteEvent")
		self.feedRemote.Name = "PetFeedEvent"
		self.feedRemote.Parent = ReplicatedStorage
	end

	if self.feedConnection then
		self.feedConnection:Disconnect()
	end

	self.feedConnection = self.feedRemote.OnServerEvent:Connect(function(player, petModel)
		self:HandleFeedRequest(player, petModel)
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
		state.hunger = MAX_STAT_VALUE
	end

	state.hunger = math.clamp(tonumber(state.hunger) or MAX_STAT_VALUE, 0, MAX_STAT_VALUE)
	return state
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
					local oldHunger = state.hunger
					state.hunger = math.clamp(oldHunger - HUNGER_DECAY_AMOUNT, 0, MAX_STAT_VALUE)
					if state.hunger ~= oldHunger then
						self.PetStateManager:SendStateToOwner(petModel)

						local owner = self.Players:GetPlayerByUserId(state.ownerUserId)
						if owner and self.SaveManager then
							self.SaveManager:ScheduleSave(owner)
						end
					end
				end
			end
		end
	end)
end

function PetFeedingManager:HandleFeedRequest(player, petModel)
	if not player or typeof(petModel) ~= "Instance" or not petModel:IsA("Model") then
		return
	end

	local character = player.Character
	if not character then return end

	local tool = character:FindFirstChildWhichIsA("Tool")
	if not self:IsValidFoodTool(tool) then
		return
	end

	local state = self.petState[petModel]
	if not state or state.ownerUserId ~= player.UserId or state.wild then
		return
	end

	local charRoot = character:FindFirstChild("HumanoidRootPart")
	local petPrimary = petModel.PrimaryPart or petModel:FindFirstChildWhichIsA("BasePart")
	if not charRoot or not petPrimary then
		return
	end

	if (charRoot.Position - petPrimary.Position).Magnitude > MAX_FEED_DISTANCE then
		return
	end

	if tool:GetAttribute("Consumed") == true then
		return
	end

	local hungerGain = math.max(0, self:GetFoodStatValue(tool, "HungerGain", "HungerGain", 0))
	local xpReward = math.max(0, self:GetFoodStatValue(tool, "XPReward", "XPReward", 0))
	if hungerGain <= 0 and xpReward <= 0 then
		return
	end

	self:EnsurePetDefaults(petModel)
	state.hunger = math.clamp((state.hunger or MAX_STAT_VALUE) + hungerGain, 0, MAX_STAT_VALUE)
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
