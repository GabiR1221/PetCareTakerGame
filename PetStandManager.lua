local PetStandManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")

local FAME_LOOP_INTERVAL_SECONDS = 5
local STAND_VISUAL_UPDATE_INTERVAL_SECONDS = 5
local INCOME_BILLBOARD_UPDATE_INTERVAL_SECONDS = 5

local function getStandEffectNames(actionName)
	local baseName = tostring(actionName or "")
	if baseName == "Place" then
		return {"PetStandPlaceEffect", "StandPlaceEffect", "PetPlacedEffect", "PetInteractionEffect"}
	elseif baseName == "Remove" then
		return {"PetStandRemoveEffect", "PetStandRemoveffect", "StandRemoveEffect", "PetRemovedEffect", "PetInteractionEffect"}
	end
	return {"PetInteractionEffect"}
end

local DEFAULT_FAME_CONFIG = {
	initial = 50,
	min = 0,
	max = 100,
	offStandDecayPerSecond = 0.2,
	defaultMood = {
		targetDelta = 0,
		minSeconds = 50,
		maxSeconds = 90,
	},
	moods = {
		Happy = { targetDelta = 18, minSeconds = 20, maxSeconds = 35 },
		Neutral = { targetDelta = 0, minSeconds = 40, maxSeconds = 70 },
		Sad = { targetDelta = -12, minSeconds = 25, maxSeconds = 45 },
		Nasty = { targetDelta = -22, minSeconds = 20, maxSeconds = 35 },
	}
}

StandMultiplierVisuals = {
	levelImage = "rbxassetid://4614401544",
	levelLabel = "Level",
	fameImage = "rbxassetid://4321867290",
	fameLabel = "Fame",
	accessoryImage = "rbxassetid://10164183611",
	accessoryLabel = "Accessory",
}

function PetStandManager:Initialize(stateTable, carryingTable, playersService, petMovement, saveManager, config, interactionPetResolver, stowPetAsToolCallback, interactionUiCallback, consumePetToolCallback)
	self.petState = stateTable or {}
	self.carryingPetByUserId = carryingTable or {}
	self.Players = playersService
	self.PetMovement = petMovement
	self.SaveManager = saveManager
	self.Config = config or {}
	self.ResolveInteractionPet = interactionPetResolver
	self.StowPetAsTool = stowPetAsToolCallback
	self.SetInteractionUiHidden = interactionUiCallback
	self.ConsumePetTool = consumePetToolCallback

	self.standConnected = {}           -- [standRoot] = true
	self.standData = {}                -- [standRoot] = data table
	self.standIncomeTasks = {}         -- [petModel] = true
	self.standPickupPromptConns = {}   -- [petModel] = RBXScriptConnection
	self.collectorTouchDebounces = {}  -- [collectorPart] = {[userId] = true}
	self.collectorAnimState = {}       -- [collectorPart] = true while tweening
	self.surfacePulseState = {}        -- [standRoot] = true while pulsing
	self.fameTasks = {}                -- [petModel] = true while fame loop runs
	self.fameNpcState = {}             -- [standRoot] = {npcs = {Model, ...}}
	self.lastStateSendAtByPet = {}     -- [petModel] = os.clock timestamp for throttled UI sync
	self.lastStandVisualUpdateAtByPet = {} -- [petModel] = os.clock timestamp for billboard/NPC refresh throttling
	self.lastIncomeBillboardUpdateAtByPet = {} -- [petModel] = os.clock timestamp for income-loop cosmetic refresh

	self.PetAttachmentManager = require(script.Parent.PetAttachmentManager)
	self.PetStateManager = require(script.Parent.PetStateManager)
	self.TycoonUtils = require(script.Parent.TycoonUtils)
	self.Multipliers = require(ReplicatedStorage.Modules.Multipliers)
	self.EffectModule = require(ReplicatedStorage.Modules.EffectModule)
	self.TycoonUtils:Initialize(self.Config)

	self:WatchPurchaseContainers()
	self:StartFameLoop()

	return self
end

function PetStandManager:OptimizeStandPetParts(petModel)
	if not petModel or not petModel.GetDescendants then return end
	for _, d in ipairs(petModel:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanTouch = false
			d.CanCollide = false
			d.CastShadow = false
			d.Massless = true
			pcall(function()
				d:SetNetworkOwner(nil)
			end)
		end
	end

	local humanoid = petModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function()
			humanoid.AutoRotate = false
			humanoid:Move(Vector3.zero, true)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end
end

function PetStandManager:GetMoodFromState(state)
	local dirtiness = math.clamp(tonumber(state and state.dirtiness) or 0, 0, 100)
	local hunger = math.clamp(tonumber(state and state.hunger) or 100, 0, 100)
	local cleanliness = 100 - dirtiness
	local fullness = hunger

	if dirtiness >= 80 then return "Nasty" end
	if cleanliness >= 80 and fullness >= 80 then return "Happy" end
	if cleanliness < 40 or fullness < 40 then return "Sad" end
	return "Neutral"
end

function PetStandManager:GetFameConfig()
	local cfg = self.Config and self.Config.PetFame or {}
	local moodCfg = cfg.moods or {}
	return {
		initial = tonumber(cfg.initial) or DEFAULT_FAME_CONFIG.initial,
		min = tonumber(cfg.min) or DEFAULT_FAME_CONFIG.min,
		max = tonumber(cfg.max) or DEFAULT_FAME_CONFIG.max,
		offStandDecayPerSecond = tonumber(cfg.offStandDecayPerSecond) or DEFAULT_FAME_CONFIG.offStandDecayPerSecond,
		defaultMood = cfg.defaultMood or DEFAULT_FAME_CONFIG.defaultMood,
		moods = {
			Happy = moodCfg.Happy or DEFAULT_FAME_CONFIG.moods.Happy,
			Neutral = moodCfg.Neutral or DEFAULT_FAME_CONFIG.moods.Neutral,
			Sad = moodCfg.Sad or DEFAULT_FAME_CONFIG.moods.Sad,
			Nasty = moodCfg.Nasty or DEFAULT_FAME_CONFIG.moods.Nasty,
		}
	}
end

function PetStandManager:EnsureFameState(petModel)
	if not petModel then return nil end
	self.petState[petModel] = self.petState[petModel] or {}
	local state = self.petState[petModel]
	local fameCfg = self:GetFameConfig()
	state.fame = math.clamp(tonumber(state.fame) or fameCfg.initial, fameCfg.min, fameCfg.max)
	return state
end

function PetStandManager:GetFameIncomeMultiplier(fame)
	local clamped = math.clamp(tonumber(fame) or 50, 0, 100)
	return 0.5 + (1.5 * (clamped / 100))
end

function PetStandManager:GetAccessoryIncomePercent(state)
	if not state then return 0 end
	local configured = tonumber(state.accessoryBuffs and state.accessoryBuffs.incomePercent)
	if configured and math.abs(configured) > 0.0001 then
		return configured
	end

	local accessoryName = state.equippedAccessoryName
	if type(accessoryName) ~= "string" or accessoryName == "" then
		accessoryName = state.accessorySlots and state.accessorySlots.A or nil
	end
	if type(accessoryName) ~= "string" or accessoryName == "" then
		state.accessoryBuffs = state.accessoryBuffs or { incomePercent = 0 }
		state.accessoryBuffs.incomePercent = 0
		return 0
	end

	local percent = 0
	local storage = ServerStorage:FindFirstChild("PetAccessories")
	local template = storage and storage:FindFirstChild(accessoryName) or nil
	if not template then
		local replicatedAccessories = ReplicatedStorage:FindFirstChild("Accessories")
		template = replicatedAccessories and replicatedAccessories:FindFirstChild(accessoryName) or nil
	end
	if template then
		percent = tonumber(template:GetAttribute("IncomePercentBuff")) or tonumber(template:GetAttribute("IncomePercent")) or 0
	elseif accessoryName == "Hat1" then
		percent = 5
	end

	state.accessoryBuffs = state.accessoryBuffs or {}
	state.accessoryBuffs.incomePercent = percent
	return percent
end

function PetStandManager:GetStandIncomeBreakdown(petModel)
	local state = self.petState[petModel] or {}
	local power = tonumber(state.power) or tonumber(petModel and petModel:GetAttribute("Power")) or 1
	local level = tonumber(state.level) or 1
	self:EnsureFameState(petModel)

	local levelMultiplier = self:GetLevelIncomeMultiplier(level)
	local fameMultiplier = self:GetFameIncomeMultiplier(self.petState[petModel].fame)
	local accessoryPercent = self:GetAccessoryIncomePercent(state)
	local accessoryMultiplier = 1 + accessoryPercent

	return {
		basePower = math.max(1, power),
		levelMultiplier = levelMultiplier,
		fameMultiplier = fameMultiplier,
		accessoryMultiplier = accessoryMultiplier,
	}
end

function PetStandManager:GetStandMultiplierVisualConfig()
	local cfg = self.Config and self.Config.StandMultiplierVisuals or {}
	return {
		level = { image = tostring(cfg.levelImage or ""), label = tostring(cfg.levelLabel or "Level") },
		fame = { image = tostring(cfg.fameImage or ""), label = tostring(cfg.fameLabel or "Fame") },
		accessory = { image = tostring(cfg.accessoryImage or ""), label = tostring(cfg.accessoryLabel or "Accessory") },
	}
end

function PetStandManager:GetStandRootFromInstance(inst)
	if not inst then return nil end

	if inst:IsA("Model") then
		if inst:FindFirstChild("PetStandPart", true) or inst:FindFirstChild("PetStand", true) then
			return inst
		end
	end

	local current = inst
	while current do
		if current:IsA("Model") then
			if current:FindFirstChild("PetStandPart", true) or current:FindFirstChild("PetStand", true) then
				return current
			end
		end
		current = current.Parent
	end

	return inst
end

function PetStandManager:GetStandPlacementPart(standRoot)
	if not standRoot then return nil end

	if standRoot:IsA("BasePart") then
		return standRoot
	end

	local direct = standRoot:FindFirstChild("PetStandPart")
	if direct and direct:IsA("BasePart") then
		return direct
	end

	local direct2 = standRoot:FindFirstChild("PetStand")
	if direct2 and direct2:IsA("BasePart") then
		return direct2
	end

	for _, d in ipairs(standRoot:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "PetStandPart" or d.Name == "PetStand") then
			return d
		end
	end

	return nil
end

function PetStandManager:GetCollectorPart(standRoot)
	if not standRoot or not standRoot.GetDescendants then return nil end

	local direct = standRoot:FindFirstChild("CollectorPart")
	if direct and direct:IsA("BasePart") then
		return direct
	end

	local direct2 = standRoot:FindFirstChild("Collector")
	if direct2 and direct2:IsA("BasePart") then
		return direct2
	end

	for _, d in ipairs(standRoot:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "CollectorPart" or d.Name == "Collector") then
			return d
		end
	end

	return nil
end

function PetStandManager:GetDisplayLabel(standRoot)
	if not standRoot or not standRoot.GetDescendants then return nil end

	local displayPart = standRoot:FindFirstChild("SurfaceGuiPart", true) or standRoot:FindFirstChild("DisplayPart", true)
	if displayPart then
		local gui = displayPart:FindFirstChildWhichIsA("SurfaceGui")
		if gui then
			local frame = gui:FindFirstChild("Frame")
			if frame and frame:IsA("Frame") then
				local frameLabel = frame:FindFirstChildWhichIsA("TextLabel", true)
				if frameLabel then
					return frameLabel
				end
			end

			local label = gui:FindFirstChildWhichIsA("TextLabel", true)
			if label then
				return label
			end
		end
	end

	for _, d in ipairs(standRoot:GetDescendants()) do
		if d:IsA("TextLabel") then
			return d
		end
	end

	return nil
end

function PetStandManager:PulseSurfaceDisplay(standRoot, label)
	if not standRoot or not label then return end
	if self.surfacePulseState[standRoot] then return end

	self.surfacePulseState[standRoot] = true

	local originalSize = label.Size
	local originalAnchorPoint = label.AnchorPoint
	local originalPosition = label.Position
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(
		originalPosition.X.Scale + ((0.5 - originalAnchorPoint.X) * originalSize.X.Scale),
		originalPosition.X.Offset + math.floor((0.5 - originalAnchorPoint.X) * originalSize.X.Offset + 0.5),
		originalPosition.Y.Scale + ((0.5 - originalAnchorPoint.Y) * originalSize.Y.Scale),
		originalPosition.Y.Offset + math.floor((0.5 - originalAnchorPoint.Y) * originalSize.Y.Offset + 0.5)
	)
	local originalStrokeThickness = nil
	local stroke = label:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		originalStrokeThickness = stroke.Thickness
	end

	local growSize = UDim2.new(
		originalSize.X.Scale * 1.05,
		math.floor(originalSize.X.Offset * 1.05 + 0.3),
		originalSize.Y.Scale * 1.05,
		math.floor(originalSize.Y.Offset * 1.05 + 0.3)
	)

	local growTween = TweenService:Create(
		label,
		TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = growSize}
	)

	local shrinkTween = TweenService:Create(
		label,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Size = originalSize}
	)

	if stroke then
		local growStroke = TweenService:Create(
			stroke,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Thickness = originalStrokeThickness * 1.15}
		)
		growStroke:Play()
	end

	growTween:Play()
	growTween.Completed:Connect(function()
		if stroke and originalStrokeThickness then
			local shrinkStroke = TweenService:Create(
				stroke,
				TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Thickness = originalStrokeThickness}
			)
			shrinkStroke:Play()
		end

		shrinkTween:Play()
		shrinkTween.Completed:Connect(function()
			if label and label.Parent then
				label.AnchorPoint = originalAnchorPoint
				label.Position = originalPosition
			end
			self.surfacePulseState[standRoot] = nil
		end)
	end)
end


function PetStandManager:EnsureStandId(standRoot)
	if not standRoot then return nil end

	local existing = standRoot:GetAttribute("StandId")
	if existing and tostring(existing) ~= "" then
		return tostring(existing)
	end

	local id = standRoot:GetFullName()
	standRoot:SetAttribute("StandId", id)
	return id
end

function PetStandManager:GetStandById(standId)
	if not standId then return nil end

	for _, inst in ipairs(workspace:GetDescendants()) do
		if (inst:IsA("Model") or inst:IsA("BasePart")) and inst:GetAttribute("StandId") == standId then
			return inst
		end
	end

	return nil
end

function PetStandManager:GetStoredMoneyValue(standRoot)
	if not standRoot then return nil end

	local stored = standRoot:FindFirstChild("StoredMoney")
	if stored and stored:IsA("NumberValue") then
		return stored
	end

	stored = Instance.new("NumberValue")
	stored.Name = "StoredMoney"
	stored.Value = 0
	stored.Parent = standRoot
	return stored
end

function PetStandManager:GetStandEffectNames(actionName)
	return getStandEffectNames(actionName)
end

function PetStandManager:PlayStandPetEffect(actionName, petModel, standPart)
	if not self.EffectModule then return end
	local target = petModel or standPart
	if not target then return end
	self.EffectModule:PlayTimedPartEffectForAll(getStandEffectNames(actionName), target, {
		offset = CFrame.new(0, 0.25, 0),
		weld = actionName ~= "Remove",
		anchored = actionName == "Remove",
	})
end

function PetStandManager:UpdateStandDisplay(standRoot)
	if not standRoot then return end

	local label = self:GetDisplayLabel(standRoot)
	if not label then return end

	local stored = self:GetStoredMoneyValue(standRoot)
	if stored then
		label.Text = tostring(math.floor(stored.Value))
		self:PulseSurfaceDisplay(standRoot, label)
	end
end

function PetStandManager:AnimateCollectorPress(collectorPart)
	if not collectorPart then return end
	if self.collectorAnimState[collectorPart] then return end

	self.collectorAnimState[collectorPart] = true

	local baseCFrame = collectorPart:GetAttribute("CollectorBaseCFrame")
	if typeof(baseCFrame) ~= "CFrame" then
		baseCFrame = collectorPart.CFrame
		collectorPart:SetAttribute("CollectorBaseCFrame", baseCFrame)
	end
	local pressDistance = math.clamp(tonumber(collectorPart:GetAttribute("PressDepth")) or 0.13, 0.05, 2)
	local pressedCFrame = baseCFrame + Vector3.new(0, -pressDistance, 0)

	local downTween = TweenService:Create(
		collectorPart,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{CFrame = pressedCFrame}
	)

	local upTween = TweenService:Create(
		collectorPart,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{CFrame = baseCFrame}
	)

	downTween:Play()
	downTween.Completed:Connect(function()
		upTween:Play()
		upTween.Completed:Connect(function()
			self.collectorAnimState[collectorPart] = nil
		end)
	end)
end


function PetStandManager:ScanContainer(container)
	if not container then return end

	local processed = {}

	for _, inst in ipairs(container:GetDescendants()) do
		if inst:IsA("BasePart") and (inst.Name == "PetStand" or inst.Name == "PetStandPart") then
			local standRoot = self:GetStandRootFromInstance(inst)
			if standRoot and not processed[standRoot] then
				processed[standRoot] = true
				self:ConnectStandPrompt(standRoot)
			end
		end
	end
end

function PetStandManager:WatchPurchaseContainers()
	if self._watchingPurchaseContainers then
		return
	end
	self._watchingPurchaseContainers = true

	local function hookContainer(container)
		if not container or container:GetAttribute("__PetStandWatched") == true then
			return
		end

		container:SetAttribute("__PetStandWatched", true)

		self:ScanContainer(container)

		container.ChildAdded:Connect(function()
			task.wait(0.1)
			self:ScanContainer(container)
		end)

		container.DescendantAdded:Connect(function()
			task.wait(0.1)
			self:ScanContainer(container)
		end)
	end

	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Folder") or inst:IsA("Model") then
			if inst.Name == "Essentials"
				or inst.Name == "PurchasedItems"
				or inst.Name == "PurchasedObjects" then
				hookContainer(inst)
			end
		end
	end

	workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("Folder") or inst:IsA("Model") then
			if inst.Name == "Essentials"
				or inst.Name == "PurchasedItems"
				or inst.Name == "PurchasedObjects" then
				task.wait(0.1)
				hookContainer(inst)
			end
		end
	end)
end

function PetStandManager:GetLevelIncomeMultiplier(level)
	level = math.max(1, tonumber(level) or 1)
	return 1 + (math.sqrt(level - 1) * 0.30) ----CHANGE THIS TO CHANGE INCOME PER LEVEL---------------------------------------
end

function PetStandManager:GetPetIncomePerSecond(petModel)
	if not petModel then return 1 end

	local breakdown = self:GetStandIncomeBreakdown(petModel)
	local income = breakdown.basePower * breakdown.levelMultiplier * breakdown.fameMultiplier * breakdown.accessoryMultiplier

	return math.max(1, math.floor(income + 0.5))
end

function PetStandManager:DestroyFameBillboard(petModel)
	if not petModel then return end
	local existing = petModel:FindFirstChild("PetFameBillboard", true)
	if existing then
		pcall(function() existing:Destroy() end)
	end
end

function PetStandManager:DestroyStandMultipliersBillboard(petModel)
	if not petModel then return end
	local existing = petModel:FindFirstChild("StandMultipliersRuntime", true)
	if existing then
		pcall(function() existing:Destroy() end)
	end
end

function PetStandManager:DestroyStandBillboards(petModel)
	self:DestroyFameBillboard(petModel)
	self:DestroyStandMultipliersBillboard(petModel)
end

function PetStandManager:EnsureFameBillboard(petModel)
	if not petModel then return nil end
	local adornee = petModel.PrimaryPart or petModel:FindFirstChildWhichIsA("BasePart")
	if not adornee then return nil end

	local billboard = petModel:FindFirstChild("PetFameBillboard", true)
	if not billboard then
		billboard = Instance.new("BillboardGui")
		billboard.Name = "PetFameBillboard"
		billboard.Size = UDim2.new(0.9, 0, 0.9, 0)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.8, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = adornee

		local bg = Instance.new("Frame")
		bg.Name = "BarBackground"
		bg.Size = UDim2.new(0.9, 0, 0.8, 0)
		bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		bg.BorderSizePixel = 0
		bg.Parent = billboard

		local fill = Instance.new("Frame")
		fill.Name = "BarFill"
		fill.Size = UDim2.fromScale(0.5, 1)
		fill.BackgroundColor3 = Color3.fromRGB(248, 198, 57)
		fill.BorderSizePixel = 0
		fill.Parent = bg
	end

	billboard.Adornee = adornee
	if billboard.Parent ~= adornee then
		billboard.Parent = adornee
	end
	return billboard
end


function PetStandManager:UpdateFameBillboard(petModel)
	local state = self:EnsureFameState(petModel)
	if not state then return end
	if state.location ~= "petstand" then return end
	local fameCfg = self:GetFameConfig()
	local billboard = self:EnsureFameBillboard(petModel)
	if not billboard then return end
	local bg = billboard:FindFirstChild("BarBackground")
	local fill = bg and bg:FindFirstChild("BarFill")
	if fill then
		local alpha = (state.fame - fameCfg.min) / math.max(1, (fameCfg.max - fameCfg.min))
		fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
	end
end

function PetStandManager:UpdateIncomeBillboard(petModel)
	if not petModel then return end
	local mainBillboard = petModel:FindFirstChild("MainBillboard", true)
	if not mainBillboard then
		local templateName = tostring(petModel:GetAttribute("TemplateName") or petModel.Name or "")
		local template = nil
		local petsFolder = ReplicatedStorage:FindFirstChild("Pets")
		if petsFolder and templateName ~= "" then
			template = petsFolder:FindFirstChild(templateName)
		end
		if not template and templateName ~= "" then
			local wildFolder = ServerStorage:FindFirstChild("WildPetModels") or ServerStorage:FindFirstChild("PetModels")
			template = wildFolder and wildFolder:FindFirstChild(templateName)
		end
		local templateBillboard = template and template:FindFirstChild("MainBillboard", true)
		if templateBillboard and templateBillboard:IsA("BillboardGui") then
			mainBillboard = templateBillboard:Clone()
			local adornee = petModel.PrimaryPart or petModel:FindFirstChildWhichIsA("BasePart")
			mainBillboard.Parent = adornee or petModel
		end
	end

	local incomeLabel = mainBillboard and mainBillboard:FindFirstChild("Income", true)
	if mainBillboard and mainBillboard:IsA("BillboardGui") then
		mainBillboard.Enabled = true
		mainBillboard.AlwaysOnTop = true
		local adornee = petModel.PrimaryPart or petModel:FindFirstChildWhichIsA("BasePart")
		if adornee then
			mainBillboard.Adornee = adornee
			if mainBillboard.Parent ~= adornee then
				mainBillboard.Parent = adornee
			end
		end
	end
	if incomeLabel and incomeLabel:IsA("TextLabel") then
		local incomePerSecond = self:GetPetIncomePerSecond(petModel)
		incomeLabel.Text = ("$%d/s"):format(incomePerSecond)
	end
end

function PetStandManager:UpdatePetToolIncomeBillboards(petModel)
	if not petModel then return end
	local state = self.petState[petModel]
	if not state or state.wild == true then return end
	local petUid = tostring(state.petUid or petModel:GetAttribute("PetUID") or "")
	if petUid == "" then return end
	local player = state.ownerUserId and self.Players and self.Players:GetPlayerByUserId(tonumber(state.ownerUserId)) or nil
	if not player then return end

	local incomePerSecond = self:GetPetIncomePerSecond(petModel)
	for _, container in ipairs({ player:FindFirstChild("Backpack"), player.Character, player:FindFirstChild("StarterGear") }) do
		if container then
			for _, tool in ipairs(container:GetChildren()) do
				if tool:IsA("Tool") and tostring(tool:GetAttribute("PetUID") or "") == petUid then
					local billboard = tool:FindFirstChild("MainBillboard", true)
					local incomeLabel = billboard and billboard:FindFirstChild("Income", true)
					if incomeLabel and incomeLabel:IsA("TextLabel") then
						incomeLabel.Text = ("$%d/s"):format(incomePerSecond)
					end
				end
			end
		end
	end
end

function PetStandManager:UpdateStandMultipliersBillboard(petModel)
	if not petModel then return end
	local state = self.petState[petModel]
	if not state or state.wild == true then return end

	local templateGui = ReplicatedStorage:FindFirstChild("StandMultipliers")
	if not templateGui or not templateGui:IsA("BillboardGui") then return end

	local adornee = petModel.PrimaryPart or petModel:FindFirstChildWhichIsA("BasePart")
	local runtimeGui = petModel:FindFirstChild("StandMultipliersRuntime")
	if not runtimeGui then
		runtimeGui = templateGui:Clone()
		runtimeGui.Name = "StandMultipliersRuntime"
		runtimeGui.Parent = adornee or petModel
	end
	runtimeGui.Enabled = true
	runtimeGui.AlwaysOnTop = true

	if adornee then
		runtimeGui.Adornee = adornee
		if runtimeGui.Parent ~= adornee then
			runtimeGui.Parent = adornee
		end
	end

	local template = runtimeGui:FindFirstChild("Template")
	local layout = runtimeGui:FindFirstChildWhichIsA("UIListLayout")
	if not template or not template:IsA("Frame") or not layout then return end
	template.Visible = false

	local visual = self:GetStandMultiplierVisualConfig()
	local bd = self:GetStandIncomeBreakdown(petModel)
	local rows = {
		{ key = "level", value = bd.levelMultiplier, visible = true },
		{ key = "fame", value = bd.fameMultiplier, visible = true },
		{ key = "accessory", value = bd.accessoryMultiplier, visible = math.abs(bd.accessoryMultiplier - 1) > 0.0001 },
	}

	local signatureParts = {}
	for _, row in ipairs(rows) do
		if row.visible then
			table.insert(signatureParts, ("%s:%.3f"):format(row.key, row.value))
		end
	end
	local signature = table.concat(signatureParts, "|")
	if runtimeGui:GetAttribute("RowsSignature") == signature then
		return
	end
	runtimeGui:SetAttribute("RowsSignature", signature)

	for _, child in ipairs(runtimeGui:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "Template" then
			child:Destroy()
		end
	end

	local function addRow(row)
		local clone = template:Clone()
		clone.Name = row.key .. "Multiplier"
		clone.Visible = true
		clone.Parent = runtimeGui
		local imageLabel = clone:FindFirstChildWhichIsA("ImageLabel", true)
		local textLabel = clone:FindFirstChildWhichIsA("TextLabel", true)
		local map = visual[row.key]
		if imageLabel and map and map.image ~= "" then
			imageLabel.Image = map.image
		end
		if textLabel then
			local prefix = (map and map.label) or row.key
			textLabel.Text = ("%s x%.2f"):format(prefix, row.value)
		end
	end

	for _, row in ipairs(rows) do
		if row.visible then
			addRow(row)
		end
	end
end

function PetStandManager:GetFameNpcCount(fame)
	local value = math.clamp(tonumber(fame) or 0, 0, 100)
	if value >= 100 then return 3 end
	if value >= 75 then return 2 end
	if value >= 50 then return 1 end
	return 0
end

function PetStandManager:GetFameNpcTemplate(standRoot, index)
	local configuredName = standRoot and (standRoot:GetAttribute("FameNpcTemplate" .. tostring(index)) or standRoot:GetAttribute("FameNpcTemplate"))
	local candidateNames = {}
	if type(configuredName) == "string" and configuredName ~= "" then
		table.insert(candidateNames, configuredName)
	end
	table.insert(candidateNames, "StandFameNPC" .. tostring(index))
	table.insert(candidateNames, "FameNPC" .. tostring(index))
	table.insert(candidateNames, "StandFameNPC")
	table.insert(candidateNames, "FameNPC")

	local roots = {
		ReplicatedStorage,
		ReplicatedStorage:FindFirstChild("StandFameNPCs"),
		ReplicatedStorage:FindFirstChild("FameNPCs"),
		ReplicatedStorage:FindFirstChild("NPCs"),
		ServerStorage,
		ServerStorage:FindFirstChild("StandFameNPCs"),
		ServerStorage:FindFirstChild("FameNPCs"),
		ServerStorage:FindFirstChild("NPCs"),
	}
	for _, root in ipairs(roots) do
		if root then
			for _, name in ipairs(candidateNames) do
				local template = root:FindFirstChild(name)
				if template and template:IsA("Model") then
					return template
				end
			end
		end
	end
	return nil
end

function PetStandManager:FindFameNpcPoint(standRoot, index)
	if not standRoot then return nil end
	local names = {
		"FameNpcPoint" .. tostring(index),
		"FameNPCPoint" .. tostring(index),
		"StandNpcPoint" .. tostring(index),
		"StandNPCPoint" .. tostring(index),
		"AudiencePoint" .. tostring(index),
	}
	for _, name in ipairs(names) do
		local point = standRoot:FindFirstChild(name, true)
		if point and point:IsA("BasePart") then return point end
	end

	local current = standRoot.Parent
	while current do
		if current.Name == "Essentials" or current:FindFirstChild("Essentials") then
			local searchRoot = current.Name == "Essentials" and current or current:FindFirstChild("Essentials")
			if searchRoot then
				for _, name in ipairs(names) do
					local point = searchRoot:FindFirstChild(name, true)
					if point and point:IsA("BasePart") then return point end
				end
				local folders = {"FameNpcPoints", "FameNPCPoints", "StandNpcPoints", "AudiencePoints"}
				for _, folderName in ipairs(folders) do
					local folder = searchRoot:FindFirstChild(folderName, true)
					if folder then
						local points = {}
						for _, child in ipairs(folder:GetChildren()) do
							if child:IsA("BasePart") then table.insert(points, child) end
						end
						table.sort(points, function(a, b) return a.Name < b.Name end)
						if points[index] then return points[index] end
					end
				end
			end
			break
		end
		current = current.Parent
	end
	return nil
end

function PetStandManager:GetFallbackFameNpcCFrame(standRoot, index)
	local standPart = self:GetStandPlacementPart(standRoot)
	if not standPart then return CFrame.new() end
	local offsets = {
		Vector3.new(0, standPart.Size.Y / 2, -4),
		Vector3.new(3, standPart.Size.Y / 2, -4.5),
		Vector3.new(-3, standPart.Size.Y / 2, -4.5),
	}
	local position = standPart.CFrame:PointToWorldSpace(offsets[index] or offsets[1])
	local lookAt = standPart.Position + Vector3.new(0, 1, 0)
	return CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z))
end

function PetStandManager:GetFameNpcCFrame(standRoot, index)
	local point = self:FindFameNpcPoint(standRoot, index)
	if point then return point.CFrame end
	return self:GetFallbackFameNpcCFrame(standRoot, index)
end

function PetStandManager:PrepareFameNpc(npc)
	for _, descendant in ipairs(npc:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			if descendant.Name == "HumanoidRootPart" or descendant == npc.PrimaryPart then
				descendant.Anchored = true
			end
		end
	end
end

function PetStandManager:CaptureFameNpcParts(npc)
	local parts = {}
	if not npc then return parts end
	for _, descendant in ipairs(npc:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, {part = descendant, transparency = descendant.Transparency})
		end
	end
	return parts
end

function PetStandManager:TweenFameNpc(npc, fromCFrame, toCFrame, parts, duration, fadeIn, onComplete)
	if not npc then return end
	duration = math.clamp(tonumber(duration) or 0.25, 0.05, 2)
	local alphaValue = Instance.new("NumberValue")
	alphaValue.Value = 0
	local conn = nil
	conn = alphaValue.Changed:Connect(function(value)
		if not npc or not npc.Parent then
			if conn then conn:Disconnect() end
			alphaValue:Destroy()
			return
		end
		local alpha = math.clamp(value, 0, 1)
		npc:PivotTo(fromCFrame:Lerp(toCFrame, alpha))
		for _, entry in ipairs(parts or {}) do
			local part = entry.part
			if part and part.Parent then
				local original = entry.transparency or 0
				if fadeIn then
					part.Transparency = 1 + ((original - 1) * alpha)
				else
					part.Transparency = original + ((1 - original) * alpha)
				end
			end
		end
	end)
	local tween = TweenService:Create(alphaValue, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Value = 1})
	tween:Play()
	tween.Completed:Connect(function()
		if conn then conn:Disconnect() end
		alphaValue:Destroy()
		if type(onComplete) == "function" then onComplete() end
	end)
end

function PetStandManager:PlayFameNpcAnimation(npc, standRoot, index)
	local animationId = standRoot and (standRoot:GetAttribute("FameNpcAnimationId" .. tostring(index)) or standRoot:GetAttribute("FameNpcAnimationId"))
		or npc:GetAttribute("FameNpcAnimationId")
		or npc:GetAttribute("AnimationId")
	if type(animationId) ~= "string" or animationId == "" then return end

	local animator = nil
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = humanoid
	else
		local controller = npc:FindFirstChildOfClass("AnimationController") or Instance.new("AnimationController")
		controller.Parent = npc
		animator = controller:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = controller
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if ok and track then
		track.Looped = true
		track:Play(0.15)
	end
end

function PetStandManager:SpawnFameNpc(standRoot, index)
	local template = self:GetFameNpcTemplate(standRoot, index)
	if not template then return nil end
	local npc = template:Clone()
	npc.Name = "StandFameNPC" .. tostring(index)
	npc:SetAttribute("RuntimeFameNpc", true)
	if not npc.PrimaryPart then
		local root = npc:FindFirstChild("HumanoidRootPart", true) or npc:FindFirstChildWhichIsA("BasePart", true)
		if root then npc.PrimaryPart = root end
	end
	local targetCFrame = self:GetFameNpcCFrame(standRoot, index)
	local startCFrame = targetCFrame + Vector3.new(0, -1.25, 0)
	npc:PivotTo(startCFrame)
	self:PrepareFameNpc(npc)
	local parts = self:CaptureFameNpcParts(npc)
	for _, entry in ipairs(parts) do
		if entry.part then entry.part.Transparency = 1 end
	end
	local folder = workspace:FindFirstChild("RuntimeEffects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RuntimeEffects"
		folder.Parent = workspace
	end
	npc.Parent = folder
	self:TweenFameNpc(npc, startCFrame, targetCFrame, parts, standRoot and standRoot:GetAttribute("FameNpcTweenTime") or 0.25, true)
	self:PlayFameNpcAnimation(npc, standRoot, index)
	return npc
end

function PetStandManager:UpdateStandFameNpcs(petModel)
	if not petModel then return end
	local state = self.petState[petModel]
	local standRoot = state and state.petstandRoot
	if not standRoot then return end
	local desiredCount = self:GetFameNpcCount(state.fame)
	local runtime = self.fameNpcState[standRoot]
	if not runtime then
		runtime = {npcs = {}}
		self.fameNpcState[standRoot] = runtime
	end

	for index = 1, 3 do
		local npc = runtime.npcs[index]
		if index <= desiredCount then
			if not npc or not npc.Parent then
				runtime.npcs[index] = self:SpawnFameNpc(standRoot, index)
			else
				npc:PivotTo(self:GetFameNpcCFrame(standRoot, index))
			end
		elseif npc then
			self:AnimateFameNpcOut(npc, standRoot)
			runtime.npcs[index] = nil
		end
	end

	if desiredCount <= 0 then
		self.fameNpcState[standRoot] = nil
	end
end


function PetStandManager:AnimateFameNpcOut(npc, standRoot)
	if not npc or not npc.Parent then return end
	local parts = self:CaptureFameNpcParts(npc)
	local startCFrame = npc:GetPivot()
	local endCFrame = startCFrame + Vector3.new(0, -1.25, 0)
	self:TweenFameNpc(npc, startCFrame, endCFrame, parts, standRoot and standRoot:GetAttribute("FameNpcTweenTime") or 0.2, false, function()
		if npc then pcall(function() npc:Destroy() end) end
	end)
end

function PetStandManager:DestroyStandFameNpcs(standRoot)
	local runtime = standRoot and self.fameNpcState[standRoot]
	if not runtime then return end
	for index, npc in pairs(runtime.npcs or {}) do
		if npc then self:AnimateFameNpcOut(npc, standRoot) end
		runtime.npcs[index] = nil
	end
	self.fameNpcState[standRoot] = nil
end

function PetStandManager:StartFameLoop()
	if self._fameLoopStarted then return end
	self._fameLoopStarted = true
	task.spawn(function()
		local lastTick = os.clock()
		while true do
			local now = os.clock()
			local elapsed = math.max(0.01, now - lastTick)
			lastTick = now
			local fameCfg = self:GetFameConfig()
			for petModel, state in pairs(self.petState) do
				if petModel and petModel.Parent and state then
					if state.wild then
						if (now - (self.lastStandVisualUpdateAtByPet[petModel] or 0)) >= STAND_VISUAL_UPDATE_INTERVAL_SECONDS then
							self.lastStandVisualUpdateAtByPet[petModel] = now
							self:UpdateIncomeBillboard(petModel)
						end
					else
						self:EnsureFameState(petModel)
						if state.location == "petstand" then
							local moodName = self:GetMoodFromState(state)
							local moodData = fameCfg.moods[moodName] or fameCfg.defaultMood
							local targetDelta = tonumber(moodData.targetDelta) or 0
							local minSeconds = math.max(0.05, tonumber(moodData.minSeconds) or 30)
							local maxSeconds = math.max(minSeconds, tonumber(moodData.maxSeconds) or minSeconds)
							local blendSeconds = (minSeconds + maxSeconds) * 0.5
							local step = (targetDelta / blendSeconds) * elapsed
							state.fame = math.clamp((tonumber(state.fame) or fameCfg.initial) + step, fameCfg.min, fameCfg.max)
						else
							state.fame = math.clamp((tonumber(state.fame) or fameCfg.initial) - (fameCfg.offStandDecayPerSecond * elapsed), fameCfg.min, fameCfg.max)
							self:DestroyFameBillboard(petModel)
							if state.petstandRoot then
								self:DestroyStandFameNpcs(state.petstandRoot)
							end
						end

						if (now - (self.lastStandVisualUpdateAtByPet[petModel] or 0)) >= STAND_VISUAL_UPDATE_INTERVAL_SECONDS then
							self.lastStandVisualUpdateAtByPet[petModel] = now
							if state.location == "petstand" then
								self:UpdateFameBillboard(petModel)
								self:UpdateStandFameNpcs(petModel)
							end
							self:UpdateIncomeBillboard(petModel)
							self:UpdateStandMultipliersBillboard(petModel)
							self:UpdatePetToolIncomeBillboards(petModel)
						end
						if (now - (self.lastStateSendAtByPet[petModel] or 0)) >= 5 then
							self.lastStateSendAtByPet[petModel] = now
							self.PetStateManager:SendStateToOwner(petModel)
						end
					end
				end
			end
			task.wait(FAME_LOOP_INTERVAL_SECONDS)
		end
	end)
end

function PetStandManager:AddCurrencyToPlayer(player, amount)
	if not player or not amount or amount <= 0 then return 0 end

	local dataFolder = player:FindFirstChild("Data")
	if not dataFolder then
		warn("[PetStandManager] Player has no Data folder:", player.Name)
		return 0
	end

	local playerData = dataFolder:FindFirstChild("PlayerData")
	if not playerData then
		warn("[PetStandManager] Player has no PlayerData folder:", player.Name)
		return 0
	end

	local currency = playerData:FindFirstChild("Currency")
	if not currency then
		warn("[PetStandManager] Player has no Currency value:", player.Name)
		return 0
	end
	
	local totalCurrency = playerData:FindFirstChild("TotalCurrency")

	local currencyMultiplier = 1
	if self.Multipliers and self.Multipliers.CurrencyMultiplier then
		local ok, resolvedMultiplier = pcall(self.Multipliers.CurrencyMultiplier, player)
		if ok and tonumber(resolvedMultiplier) and resolvedMultiplier > 0 then
			currencyMultiplier = resolvedMultiplier
		else
			warn("[PetStandManager] Failed to resolve currency multiplier for:", player.Name)
		end
	end

	local finalAward = math.max(1, math.floor((amount * currencyMultiplier) + 0.5))


	if currency:IsA("NumberValue") or currency:IsA("IntValue") then
		currency.Value = currency.Value + finalAward

		if totalCurrency and (totalCurrency:IsA("NumberValue") or totalCurrency:IsA("IntValue")) then
			totalCurrency.Value = totalCurrency.Value + finalAward
		end

		return finalAward
	end

	return 0
end

function PetStandManager:ResolveTycoonForStandPart(standPart, player)
	local tycoonModel = nil
	local current = standPart.Parent

	while current do
		if current:IsA("Folder") or current:IsA("Model") then
			local essDirect = current:FindFirstChild("Essentials")
			if essDirect then
				local desk = self.TycoonUtils:FindDeskInEssentials(essDirect)
				if desk then
					tycoonModel = current
					break
				end
			end
		end
		current = current.Parent
	end

	if not tycoonModel then
		local resolvedModel = self.TycoonUtils:ResolveModelWithDeskFromInstance(standPart)
		if resolvedModel then
			tycoonModel = resolvedModel
		end
	end

	if tycoonModel == workspace then
		tycoonModel = nil
	end

	if not tycoonModel and player then
		local byOwner = self.TycoonUtils:FindTycoonByOwnerIdWithDesk(player.UserId)
		if byOwner then
			tycoonModel = byOwner
		end
	end

	return tycoonModel
end

function PetStandManager:IsPlayerAllowedToUseStand(player, standPart)
	if not player or not standPart then return false end

	local tycoonModel = self:ResolveTycoonForStandPart(standPart, player)
	if not tycoonModel then
		return false
	end

	local ownerAttr = tycoonModel:GetAttribute("OwnerId") or tycoonModel:GetAttribute("Owner") or tycoonModel:GetAttribute("OwnerUserId")
	if ownerAttr and tostring(ownerAttr) == tostring(player.UserId) then
		return true
	end

	for _, nm in ipairs({"OwnerId", "Owner", "OwnerUserId"}) do
		local child = tycoonModel:FindFirstChild(nm)
		if child and child.Value and tostring(child.Value) == tostring(player.UserId) then
			return true
		end
	end

	return false
end

function PetStandManager:GetPetOnStand(standRoot)
	if not standRoot then return nil end
	for petModel, state in pairs(self.petState) do
		if petModel and petModel.Parent and state and state.location == "petstand" and state.petstandRoot == standRoot then
			return petModel, state
		end
	end
	return nil, nil
end

function PetStandManager:GetCurrencyParticleCountForCollection(standRoot, collectorPart, collectedAmount)
	local maxCount = math.clamp(math.floor(tonumber(collectorPart and collectorPart:GetAttribute("CurrencyParticleCount")) or 12), 1, 18)
	local petModel = self:GetPetOnStand(standRoot)
	local incomePerSecond = petModel and self:GetPetIncomePerSecond(petModel) or 0
	local twoMinuteIncome = math.max(1, incomePerSecond * 120)
	local ratio = math.clamp((tonumber(collectedAmount) or 0) / twoMinuteIncome, 0, 1)
	return math.clamp(math.ceil(maxCount * ratio), 1, maxCount)
end

function PetStandManager:CollectStandMoney(player, standRoot)
	if not player or not standRoot then return 0 end

	local placementPart = self:GetStandPlacementPart(standRoot)
	if not placementPart then return 0 end

	if not self:IsPlayerAllowedToUseStand(player, placementPart) then
		return 0
	end

	local stored = self:GetStoredMoneyValue(standRoot)
	if not stored then return 0 end

	local amount = math.floor(stored.Value)
	if amount <= 0 then
		return 0
	end

	local added = self:AddCurrencyToPlayer(player, amount)
	if added > 0 then
		stored.Value = math.max(0, stored.Value - added)
		self:UpdateStandDisplay(standRoot)
		local collectorPart = self:GetCollectorPart(standRoot)
		if collectorPart and self.EffectModule then
			self.EffectModule:PlayCurrencyCollectEffectForPlayer(player, collectorPart, {
				count = self:GetCurrencyParticleCountForCollection(standRoot, collectorPart, amount),
				templateName = collectorPart:GetAttribute("CurrencyParticleTemplate"),
			})
		end

		if self.SaveManager then
			self.SaveManager:ScheduleSave(player)
		end
	end

	return added
end

function PetStandManager:StartIncomeLoop(petModel, standRoot)
	if not petModel or not standRoot then return end
	if self.standIncomeTasks[petModel] then return end

	self.standIncomeTasks[petModel] = true

	task.spawn(function()
		while self.standIncomeTasks[petModel]
			and petModel
			and petModel.Parent
			and standRoot
			and standRoot.Parent
			and self.petState[petModel]
			and self.petState[petModel].location == "petstand"
			and self.petState[petModel].petstandRoot == standRoot do

			local income = self:GetPetIncomePerSecond(petModel)

			local stored = self:GetStoredMoneyValue(standRoot)
			if stored then
				stored.Value = stored.Value + income
			end
			self:UpdateStandDisplay(standRoot)
			local now = os.clock()
			if (now - (self.lastIncomeBillboardUpdateAtByPet[petModel] or 0)) >= INCOME_BILLBOARD_UPDATE_INTERVAL_SECONDS then
				self.lastIncomeBillboardUpdateAtByPet[petModel] = now
				self:UpdateIncomeBillboard(petModel)
				self:UpdateStandMultipliersBillboard(petModel)
			end

			task.wait(1)
		end

		self.standIncomeTasks[petModel] = nil
	end)
end

function PetStandManager:StopIncomeLoop(petModel)
	self.standIncomeTasks[petModel] = nil
end

function PetStandManager:CreatePlacedPetPickupPrompt(petModel, standRoot, standPart)
	if not petModel then return end

	local existing = petModel:FindFirstChild("PetPickupPart")
	if existing then
		pcall(function() existing:Destroy() end)
	end

	local helper = Instance.new("Part")
	helper.Name = "PetPickupPart"
	helper.Size = Vector3.new(1,1,1)
	helper.Anchored = false
	helper.Transparency = 1
	helper.CanCollide = false
	helper.Parent = petModel

	local pp = petModel.PrimaryPart
	if pp then
		helper.CFrame = pp.CFrame * CFrame.new(0, pp.Size.Y / 2 + 0.5, 0)
		local w = Instance.new("WeldConstraint")
		w.Part0 = helper
		w.Part1 = pp
		w.Parent = helper
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PetPrompt"
	prompt.ActionText = "Pick Up Pet"
	prompt.ObjectText = "Pet"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 6
	prompt.HoldDuration = 0
	prompt.Parent = helper

	local conn = prompt.Triggered:Connect(function(player)
		local st = self.petState[petModel]
		if not st then return end
		if tostring(st.ownerUserId) ~= tostring(player.UserId) then return end

		-- auto collect before pickup
		self:CollectStandMoney(player, standRoot)
		self:PlayStandPetEffect("Remove", petModel, standPart)
		self:DestroyStandFameNpcs(standRoot)
		self:StopIncomeLoop(petModel)

		if petModel.PrimaryPart then
			self.PetAttachmentManager:ClearWeldsOnPart(petModel.PrimaryPart)
		end

		local restoredToTool = false
		if type(self.StowPetAsTool) == "function" then
			local ok, result = pcall(function()
				return self.StowPetAsTool(player, petModel, true)
			end)
			restoredToTool = (ok and result == true)
		end

		if restoredToTool then
			self.petState[petModel].petstand = nil
			self.petState[petModel].petstandRoot = nil
			self:DestroyStandBillboards(petModel)
			pcall(function() helper:Destroy() end)
			if self.standPickupPromptConns[petModel] then
				pcall(function() self.standPickupPromptConns[petModel]:Disconnect() end)
				self.standPickupPromptConns[petModel] = nil
			end
		else
			if player.Character and player.Character.PrimaryPart and not self.carryingPetByUserId[player.UserId] then
				local ok, err = pcall(function()
					self.PetAttachmentManager:AttachPetToPlayer(petModel, player, { resetFlags = false })
				end)
				if ok then
					self.petState[petModel].location = "player"
					self.petState[petModel].petstand = nil
					self.petState[petModel].petstandRoot = nil
					self:DestroyStandBillboards(petModel)
					pcall(function() helper:Destroy() end)
					if self.standPickupPromptConns[petModel] then
						pcall(function() self.standPickupPromptConns[petModel]:Disconnect() end)
						self.standPickupPromptConns[petModel] = nil
					end
				else
					warn("[PetStandManager] Failed to pick pet back up:", err)
				end
			else
				warn("[PetStandManager] Failed to return stand pet as tool.")
			end
		end
	end)

	self.standPickupPromptConns[petModel] = conn
end

function PetStandManager:ConnectCollector(standRoot, collectorPart)
	if not standRoot or not collectorPart or not collectorPart:IsA("BasePart") then return end

	self.collectorTouchDebounces[collectorPart] = self.collectorTouchDebounces[collectorPart] or {}
	local debounceTable = self.collectorTouchDebounces[collectorPart]

	collectorPart.Touched:Connect(function(hit)
		if not hit or not hit.Parent then return end

		local player = self.Players:GetPlayerFromCharacter(hit.Parent)
		if not player then return end

		if debounceTable[player.UserId] then return end
		debounceTable[player.UserId] = true

		task.delay(0.75, function()
			debounceTable[player.UserId] = nil
		end)

		local collected = self:CollectStandMoney(player, standRoot)
		if collected > 0 then
			self:AnimateCollectorPress(collectorPart)
			print(("[PetStandManager] %s collected %d from stand %s"):format(
				tostring(player.Name), collected, tostring(standRoot:GetFullName())))
		end
	end)
end

function PetStandManager:ConnectStandPrompt(standRoot)
	if not standRoot then return end
	if self.standConnected[standRoot] then return end

	self:EnsureStandId(standRoot)

	local standPart = self:GetStandPlacementPart(standRoot)
	if not standPart or not standPart:IsA("BasePart") then return end

	local prompt = standPart:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PetStandPrompt"
		prompt.ActionText = "Place Pet"
		prompt.HoldDuration = 0
		prompt.ObjectText = "Pet Stand"
		prompt.MaxActivationDistance = 6
		prompt.RequiresLineOfSight = false
		prompt.Parent = standPart
	end

	local collectorPart = self:GetCollectorPart(standRoot)
	if collectorPart then
		self:ConnectCollector(standRoot, collectorPart)
	end

	self:GetStoredMoneyValue(standRoot)
	self:UpdateStandDisplay(standRoot)

	local conn = prompt.Triggered:Connect(function(player)
		if not self:IsPlayerAllowedToUseStand(player, standPart) then
			return
		end

		local pet = self.carryingPetByUserId[player.UserId]
		if not pet and type(self.ResolveInteractionPet) == "function" then
			local resolvedPet = self.ResolveInteractionPet(player)
			pet = resolvedPet
		end
		if not pet then
			return
		end
		local petState = self.petState[pet]
		if (petState and petState.isLuckyBlock == true) or pet:GetAttribute("IsLuckyBlock") == true then
			return
		end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			pcall(function() hum:UnequipTools() end)
		end

		-- allow only one pet per stand
		for otherPet, st in pairs(self.petState) do
			if otherPet ~= pet and st and st.location == "petstand" and st.petstandRoot == standRoot then
				return
			end
		end

		self.PetAttachmentManager:SetModelPrimaryIfMissing(pet)
		if not pet.PrimaryPart then
			warn("[PetStandManager] Pet has no PrimaryPart:", pet.Name)
			return
		end

		self.PetAttachmentManager:ClearDirectModelWelds(pet)
		self.PetAttachmentManager:ClearWeldsOnPart(pet.PrimaryPart)
		self.PetAttachmentManager:DetachPetFromPlayer(pet)

		local ok = self.PetAttachmentManager:AttachPetToPart(pet, standPart)
		if not ok then
			warn("[PetStandManager] Failed to attach pet to stand")
			return
		end

		self.petState[pet] = self.petState[pet] or {}
		self.petState[pet].location = "petstand"
		self.petState[pet].petstand = standPart
		self.petState[pet].petstandRoot = standRoot
		self:OptimizeStandPetParts(pet)
		self:EnsureFameState(pet)
		if type(self.ConsumePetTool) == "function" then
			self.ConsumePetTool(player, pet)
		end

		self.PetMovement.StopWandering(pet)
		self:PlayStandPetEffect("Place", pet, standPart)
		self:CreatePlacedPetPickupPrompt(pet, standRoot, standPart)
		self:StartIncomeLoop(pet, standRoot)
		self:UpdateFameBillboard(pet)
		self:UpdateStandFameNpcs(pet)
		self:UpdateStandMultipliersBillboard(pet)
		self:UpdateIncomeBillboard(pet)
		if self.SaveManager then
			self.SaveManager:ScheduleSave(player, { urgent = true, reason = "PlacePetOnStand" })
		end
		local fameBillboard = pet:FindFirstChild("PetFameBillboard")
		if fameBillboard and fameBillboard:IsA("BillboardGui") then
			fameBillboard.Enabled = true
			fameBillboard.AlwaysOnTop = true
		end
		self.PetStateManager:SendStateToOwner(pet)
		self:UpdateStandDisplay(standRoot)
	end)

	self.standConnected[standRoot] = true
	self.standData[standRoot] = {
		standPart = standPart,
		collectorPart = collectorPart,
		connection = conn,
	}
end


function PetStandManager:RestorePetToStand(petModel, player, standId, storedMoney)
	if not petModel or not player or not standId then
		return false
	end

	local standRoot = self:GetStandById(standId)
	if not standRoot then
		warn("[PetStandManager] Could not restore stand by StandId:", standId)
		return false
	end

	local standPart = self:GetStandPlacementPart(standRoot)
	if not standPart then
		warn("[PetStandManager] Stand has no placement part for restore:", standRoot:GetFullName())
		return false
	end

	-- prevent double occupancy
	for otherPet, st in pairs(self.petState) do
		if otherPet ~= petModel and st and st.location == "petstand" and st.petstandRoot == standRoot then
			warn("[PetStandManager] Restore blocked, stand already occupied:", standRoot:GetFullName())
			return false
		end
	end

	self.PetAttachmentManager:SetModelPrimaryIfMissing(petModel)
	if not petModel.PrimaryPart then
		return false
	end

	self.PetAttachmentManager:ClearDirectModelWelds(petModel)
	self.PetAttachmentManager:ClearWeldsOnPart(petModel.PrimaryPart)

	local ok = self.PetAttachmentManager:AttachPetToPart(petModel, standPart)
	if not ok then
		return false
	end

	self.petState[petModel] = self.petState[petModel] or {}
	self.petState[petModel].ownerUserId = player.UserId
	self.petState[petModel].location = "petstand"
	self.petState[petModel].petstand = standPart
	self.petState[petModel].petstandRoot = standRoot
	self:OptimizeStandPetParts(petModel)
	self:EnsureFameState(petModel)

	local stored = self:GetStoredMoneyValue(standRoot)
	if storedMoney ~= nil and stored then
		stored.Value = tonumber(storedMoney) or 0
	end

	self.PetMovement.StopWandering(petModel)
	self:CreatePlacedPetPickupPrompt(petModel, standRoot, standPart)
	self:StartIncomeLoop(petModel, standRoot)
	self:UpdateFameBillboard(petModel)
	self:UpdateStandFameNpcs(petModel)
	self:UpdateStandMultipliersBillboard(petModel)
	self:UpdateIncomeBillboard(petModel)
	self.PetStateManager:SendStateToOwner(petModel)
	self:UpdateStandDisplay(standRoot)

	return true
end

function PetStandManager:ScanAndConnectAll()
	local function scanContainer(container)
		if not container then return end

		local processed = {}

		for _, inst in ipairs(container:GetDescendants()) do
			if inst:IsA("BasePart") and (inst.Name == "PetStand" or inst.Name == "PetStandPart") then
				local standRoot = self:GetStandRootFromInstance(inst)
				if standRoot and not processed[standRoot] then
					processed[standRoot] = true
					self:ConnectStandPrompt(standRoot)
				end
			end
		end
	end

	for _, inst in ipairs(workspace:GetDescendants()) do
		if (inst:IsA("Folder") or inst:IsA("Model")) and (inst.Name == "Essentials" or inst.Name == "PurchasedItems") then
			scanContainer(inst)
		end
	end
end

return PetStandManager
