local PetStandManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

function PetStandManager:Initialize(stateTable, carryingTable, playersService, petMovement, saveManager, config)
	self.petState = stateTable or {}
	self.carryingPetByUserId = carryingTable or {}
	self.Players = playersService
	self.PetMovement = petMovement
	self.SaveManager = saveManager
	self.Config = config or {}

	self.standConnected = {}           -- [standRoot] = true
	self.standData = {}                -- [standRoot] = data table
	self.standIncomeTasks = {}         -- [petModel] = true
	self.standPickupPromptConns = {}   -- [petModel] = RBXScriptConnection
	self.collectorTouchDebounces = {}  -- [collectorPart] = {[userId] = true}
	self.collectorAnimState = {}       -- [collectorPart] = true while tweening
	self.surfacePulseState = {}        -- [standRoot] = true while pulsing

	self.PetAttachmentManager = require(script.Parent.PetAttachmentManager)
	self.PetStateManager = require(script.Parent.PetStateManager)
	self.TycoonUtils = require(script.Parent.TycoonUtils)
	self.Multipliers = require(ReplicatedStorage.Modules.Multipliers)
	self.TycoonUtils:Initialize(self.Config)

	self:WatchPurchaseContainers()

	return self
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

	local baseCFrame = collectorPart.CFrame
	local pressedCFrame = baseCFrame * CFrame.new(0, -0.35, 0)

	local downTween = TweenService:Create(
		collectorPart,
		TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{CFrame = pressedCFrame}
	)

	local upTween = TweenService:Create(
		collectorPart,
		TweenInfo.new(0.11, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
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

	local state = self.petState[petModel] or {}
	local power = tonumber(state.power) or tonumber(petModel:GetAttribute("Power")) or 1
	local level = tonumber(state.level) or 1

	local multiplier = self:GetLevelIncomeMultiplier(level)
	local income = power * multiplier

	return math.max(1, math.floor(income + 0.5))
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
		self:StopIncomeLoop(petModel)

		if petModel.PrimaryPart then
			self.PetAttachmentManager:ClearWeldsOnPart(petModel.PrimaryPart)
		end

		if player.Character and player.Character.PrimaryPart and not self.carryingPetByUserId[player.UserId] then
			local ok, err = pcall(function()
				self.PetAttachmentManager:AttachPetToPlayer(petModel, player, { resetFlags = false })
			end)

			if ok then
				self.petState[petModel].location = "player"
				self.petState[petModel].petstand = nil
				self.petState[petModel].petstandRoot = nil

				pcall(function() helper:Destroy() end)

				if self.standPickupPromptConns[petModel] then
					pcall(function() self.standPickupPromptConns[petModel]:Disconnect() end)
					self.standPickupPromptConns[petModel] = nil
				end
			else
				warn("[PetStandManager] Failed to pick pet back up:", err)
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
		if not pet then
			return
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

		self.PetMovement.StopWandering(pet)
		self:CreatePlacedPetPickupPrompt(pet, standRoot, standPart)
		self:StartIncomeLoop(pet, standRoot)
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

	local stored = self:GetStoredMoneyValue(standRoot)
	if storedMoney ~= nil and stored then
		stored.Value = tonumber(storedMoney) or 0
	end

	self.PetMovement.StopWandering(petModel)
	self:CreatePlacedPetPickupPrompt(petModel, standRoot, standPart)
	self:StartIncomeLoop(petModel, standRoot)
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
