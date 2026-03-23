
local PetStandManager = {}

function PetStandManager:Initialize(stateTable, carryingTable, playersService, petMovement, saveManager, config)
	self.petState = stateTable or {}
	self.carryingPetByUserId = carryingTable or {}
	self.Players = playersService
	self.PetMovement = petMovement
	self.SaveManager = saveManager
	self.Config = config or {}

	self.standConnected = {}
	self.standIncomeTasks = {}
	self.standPickupPromptConns = {}

	self.PetAttachmentManager = require(script.Parent.PetAttachmentManager)
	self.PetStateManager = require(script.Parent.PetStateManager)
	self.TycoonUtils = require(script.Parent.TycoonUtils)
	self.TycoonUtils:Initialize(self.Config)

	return self
end

function PetStandManager:GetStandContainer(standPart)
	if not standPart then return nil end

	local current = standPart.Parent
	while current do
		if current:IsA("Model") or current:IsA("Folder") then
			return current
		end
		current = current.Parent
	end

	return standPart.Parent
end

function PetStandManager:GetDisplayLabel(standPart)
	if not standPart then return nil end

	local container = self:GetStandContainer(standPart)
	if not container then return nil end

	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("TextLabel") then
			return d
		end
	end

	return nil
end

function PetStandManager:GetStoredMoneyValue(standPart)
	if not standPart then return nil end

	local container = self:GetStandContainer(standPart)
	if not container then return nil end

	local stored = container:FindFirstChild("StoredMoney")
	if stored and stored:IsA("NumberValue") then
		return stored
	end

	stored = Instance.new("NumberValue")
	stored.Name = "StoredMoney"
	stored.Value = 0
	stored.Parent = container
	return stored
end

function PetStandManager:UpdateStandDisplay(standPart)
	if not standPart then return end

	local label = self:GetDisplayLabel(standPart)
	if not label then return end

	local stored = self:GetStoredMoneyValue(standPart)
	if stored then
		label.Text = tostring(math.floor(stored.Value))
	end
end

function PetStandManager:AddCurrencyToPlayer(player, amount)
	if not player or not amount or amount <= 0 then return end

	local dataFolder = player:FindFirstChild("Data")
	if not dataFolder then
		warn("[PetStandManager] Player has no Data folder:", player.Name)
		return
	end

	local playerData = dataFolder:FindFirstChild("PlayerData")
	if not playerData then
		warn("[PetStandManager] Player has no PlayerData folder:", player.Name)
		return
	end

	local currency = playerData:FindFirstChild("Currency")
	if not currency then
		warn("[PetStandManager] Player has no Currency value:", player.Name)
		return
	end

	if currency:IsA("NumberValue") or currency:IsA("IntValue") then
		currency.Value = currency.Value + amount
	end
end

function PetStandManager:StartIncomeLoop(petModel, standPart)
	if not petModel or not standPart then return end
	if self.standIncomeTasks[petModel] then return end

	self.standIncomeTasks[petModel] = true

	task.spawn(function()
		while self.standIncomeTasks[petModel]
			and petModel
			and petModel.Parent
			and standPart
			and standPart.Parent
			and self.petState[petModel]
			and self.petState[petModel].location == "petstand"
			and self.petState[petModel].petstand == standPart do

			local state = self.petState[petModel]
			local ownerUserId = state.ownerUserId
			local owner = ownerUserId and self.Players:GetPlayerByUserId(ownerUserId) or nil
			local power = tonumber(state.power) or tonumber(petModel:GetAttribute("Power")) or 1
			power = math.max(1, math.floor(power))

			local stored = self:GetStoredMoneyValue(standPart)
			if stored then
				stored.Value = stored.Value + power
			end
			self:UpdateStandDisplay(standPart)

			if owner then
				self:AddCurrencyToPlayer(owner, power)
				if self.SaveManager then
					self.SaveManager:ScheduleSave(owner)
				end
			end

			task.wait(1)
		end

		self.standIncomeTasks[petModel] = nil
	end)
end

function PetStandManager:StopIncomeLoop(petModel)
	self.standIncomeTasks[petModel] = nil
end

function PetStandManager:CreatePlacedPetPickupPrompt(petModel, standPart)
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

function PetStandManager:ResolveTycoonForStandPart(standPart, player)
	local tycoonModel = nil
	local current = standPart.Parent

	while current do
		if current:IsA("Folder") then
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

function PetStandManager:ConnectStandPrompt(standPart)
	if not standPart or not standPart:IsA("BasePart") then return end
	if self.standConnected[standPart] then return end

	local prompt = standPart:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Place Pet"
		prompt.HoldDuration = 0
		prompt.ObjectText = "Pet Stand"
		prompt.MaxActivationDistance = 6
		prompt.RequiresLineOfSight = false
		prompt.Parent = standPart
	end

	local conn = prompt.Triggered:Connect(function(player)
		print(("[PetStandManager] Stand prompt triggered by %s on %s"):format(
			tostring(player.Name), tostring(standPart:GetFullName())))

		if not self:IsPlayerAllowedToUseStand(player, standPart) then
			print("[PetStandManager] Stand owner check failed for", player.Name)
			return
		end

		local pet = self.carryingPetByUserId[player.UserId]
		if not pet then
			print("[PetStandManager] Player is not carrying a pet:", player.Name)
			return
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

		self.PetMovement.StopWandering(pet)
		self:CreatePlacedPetPickupPrompt(pet, standPart)
		self:StartIncomeLoop(pet, standPart)
		self.PetStateManager:SendStateToOwner(pet)
		self:UpdateStandDisplay(standPart)

		print(("[PetStandManager] Pet %s placed on stand %s"):format(
			tostring(pet.Name), tostring(standPart:GetFullName())))
	end)

	self.standConnected[standPart] = conn
	print("[PetStandManager] Connected stand:", standPart:GetFullName())
end

function PetStandManager:ScanAndConnectAll()
	local possibleRoots = {}
	local tycoonRoot = workspace:FindFirstChild("Tycoon")
	if tycoonRoot then table.insert(possibleRoots, tycoonRoot) end
	local topTycoons = workspace:FindFirstChild("Tycoons")
	if topTycoons then table.insert(possibleRoots, topTycoons) end

	for _, root in ipairs(possibleRoots) do
		for _, inst in ipairs(root:GetDescendants()) do
			if inst:IsA("BasePart") then
				if inst.Name == "PetStand" or inst.Name == "PetStandPart" then
					self:ConnectStandPrompt(inst)
				end
			end
		end
	end

	for _, model in ipairs(workspace:GetDescendants()) do
		if model:IsA("Model") then
			local ess = model:FindFirstChild("Essentials")
			if ess then
				local stand = ess:FindFirstChild("PetStand")
				if stand and stand:IsA("BasePart") then
					self:ConnectStandPrompt(stand)
				end

				local stand2 = ess:FindFirstChild("PetStandPart")
				if stand2 and stand2:IsA("BasePart") then
					self:ConnectStandPrompt(stand2)
				end
			end

			local purchased = model:FindFirstChild("PurchasedItems")
			if purchased then
				local stand = purchased:FindFirstChild("PetStand")
				if stand and stand:IsA("BasePart") then
					self:ConnectStandPrompt(stand)
				end

				local stand2 = purchased:FindFirstChild("PetStandPart")
				if stand2 and stand2:IsA("BasePart") then
					self:ConnectStandPrompt(stand2)
				end
			end
		end
	end
end

return PetStandManager
