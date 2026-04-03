--TycoonModule as child of ServerMainScript
-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Debris = game:GetService("Debris")
local DataStoreService = game:GetService("DataStoreService")

-- Modules
local configModule = require("../Settings")
local animationsModule = require("./ObjectAnimationsModule")

-- Variables
local rebirthEvent = ReplicatedStorage:WaitForChild("TycoonRebirthEvent")
local soundEvent = ReplicatedStorage:WaitForChild("TycoonSoundEvent")
local soundsFolder = script.Parent.Parent.SoundsFolder
local petDataStore = DataStoreService:GetDataStore("PetData10")-----------CHANGE THIS TO THE SAME PETDATA NAME AS IN PETSAVE

local objectModules = {}
for _, module in ipairs(script.ObjectModules:GetChildren()) do
	if not module:IsA("ModuleScript") then continue end
	objectModules[module.Name] = require(module)
end

local Button = require(script.ButtonClass)
local PlaySoundAtSource = require(script.Parent.Utilities.PlaySoundAtSource)
---Helpers
-- Generic currency helpers: support multiple currency names (e.g. "Currency", "Currency2")
local ServerStorage = game:GetService("ServerStorage")

local function findPlayerCurrencyValueObject(player, currencyName)
	if not player or not currencyName then return nil end
	local dataFolder = player:FindFirstChild("Data")
	if dataFolder then
		local playerData = dataFolder:FindFirstChild("PlayerData")
		if playerData then
			-- prefer a value named exactly currencyName (e.g. "Currency", "Currency2")
			local val = playerData:FindFirstChild(currencyName)
			if val and (val:IsA("IntValue") or val:IsA("NumberValue")) then
				return val
			end
			-- fallback: some systems use "Currency" as canonical name; leave fallback to caller
		end
	end
	-- fallback to server-side attribute storage (ServerStorage.PlayerData/<userid> Attributes)
	local serverFolder = ServerStorage:FindFirstChild("PlayerData")
	if serverFolder then
		local folder = serverFolder:FindFirstChild(tostring(player.UserId))
		if folder then
			-- can't return attribute as Value object; caller should read attribute if this returns nil
			return nil
		end
	end
	return nil
end

local function getPlayerCurrency(player, currencyName)
	currencyName = tostring(currencyName or "Currency")
	local valObj = findPlayerCurrencyValueObject(player, currencyName)
	if valObj then
		return tonumber(valObj.Value) or 0
	end
	-- fallback to server attribute
	local serverFolder = ServerStorage:FindFirstChild("PlayerData")
	if serverFolder then
		local folder = serverFolder:FindFirstChild(tostring(player.UserId))
		if folder then
			return tonumber(folder:GetAttribute(currencyName)) or 0
		end
	end
	return 0
end

local function setPlayerCurrencyDirect(player, currencyName, newValue)
	currencyName = tostring(currencyName or "Currency")
	local valObj = findPlayerCurrencyValueObject(player, currencyName)
	if valObj then
		valObj.Value = tonumber(newValue) or 0
		return true
	end
	local serverFolder = ServerStorage:FindFirstChild("PlayerData")
	if serverFolder then
		local folder = serverFolder:FindFirstChild(tostring(player.UserId))
		if folder then
			folder:SetAttribute(currencyName, tonumber(newValue) or 0)
			return true
		end
	end
	return false
end

local function changePlayerCurrency(player, currencyName, delta)
	currencyName = tostring(currencyName or "Currency")
	local valObj = findPlayerCurrencyValueObject(player, currencyName)
	delta = tonumber(delta or 0)
	if valObj then
		valObj.Value = (tonumber(valObj.Value) or 0) + delta
		-- If this is an *earning* (delta > 0) try to add to a Total counter named "Total<currencyName>" (e.g. "TotalCurrency", "TotalCurrency2")
		if delta > 0 then
			local totalName = "Total" .. currencyName
			local totalObj = findPlayerCurrencyValueObject(player, totalName)
			if totalObj then
				totalObj.Value = (tonumber(totalObj.Value) or 0) + delta
			else
				local serverFolder = ServerStorage:FindFirstChild("PlayerData")
				if serverFolder then
					local folder = serverFolder:FindFirstChild(tostring(player.UserId))
					if folder then
						local curTotal = tonumber(folder:GetAttribute(totalName)) or 0
						folder:SetAttribute(totalName, curTotal + delta)
					end
				end
			end
		end
		return true
	end

	-- fallback (server attribute)
	local serverFolder = ServerStorage:FindFirstChild("PlayerData")
	if serverFolder then
		local folder = serverFolder:FindFirstChild(tostring(player.UserId))
		if folder then
			local cur = tonumber(folder:GetAttribute(currencyName)) or 0
			folder:SetAttribute(currencyName, cur + delta)
			if delta > 0 then
				local totalName = "Total" .. currencyName
				local curTotal = tonumber(folder:GetAttribute(totalName)) or 0
				folder:SetAttribute(totalName, curTotal + delta)
			end
			return true
		end
	end
	return false
end

local function normalizePetName(name)
	if not name then return "" end
	return string.lower((tostring(name):gsub("^%s+", ""):gsub("%s+$", "")))
end

local function splitCsv(csv)
	local out = {}
	if type(csv) ~= "string" or csv == "" then return out end
	for token in string.gmatch(csv, "([^,]+)") do
		local cleaned = normalizePetName(token)
		if cleaned ~= "" then
			out[cleaned] = true
		end
	end
	return out
end

local function getOwnedPetSetFromFolder(playerFolder)
	if not playerFolder then return {} end
	local csv = playerFolder:GetAttribute("OwnedPetNamesCsv")
	return splitCsv(csv)
end

local function canAffordRequirements(player, currencyRequirements)
	if type(currencyRequirements) ~= "table" then
		return true
	end
	for currencyName, requiredAmount in pairs(currencyRequirements) do
		local required = tonumber(requiredAmount) or 0
		if required > 0 then
			local current = getPlayerCurrency(player, tostring(currencyName))
			if current < required then
				return false
			end
		end
	end
	return true
end

local function chargeRequirements(player, currencyRequirements)
	if type(currencyRequirements) ~= "table" then
		return true
	end
	if not canAffordRequirements(player, currencyRequirements) then
		return false
	end
	for currencyName, requiredAmount in pairs(currencyRequirements) do
		local required = tonumber(requiredAmount) or 0
		if required > 0 then
			changePlayerCurrency(player, tostring(currencyName), -required)
		end
	end
	return true
end

local function resolveRebirthRequirementForTier(rebirthCount)
	local tier = (tonumber(rebirthCount) or 0) + 1
	local tierRequirements = nil
	if type(configModule.RebirthRequirementsByTier) == "table" then
		tierRequirements = configModule.RebirthRequirementsByTier[tier]
	end
	tierRequirements = tierRequirements or {}
	return tierRequirements
end

local function meetsPetRequirements(playerFolder, petRequirements)
	if type(petRequirements) ~= "table" or #petRequirements == 0 then
		return true
	end
	local ownedPets = getOwnedPetSetFromFolder(playerFolder)
	for _, petName in ipairs(petRequirements) do
		local normalized = normalizePetName(petName)
		if normalized ~= "" and not ownedPets[normalized] then
			return false
		end
	end
	return true
end

local function canPlayerRebirthNow(player, playerFolder, percentComplete)
	if percentComplete < (tonumber(configModule.RebirthCompletionPercentage) or 100) then
		return false
	end

	local rebirthCount = tonumber(playerFolder:GetAttribute(configModule.RebirthsName)) or 0
	local rebirthLimit = tonumber(configModule.RebirthLimit)
	if rebirthLimit == nil then
		rebirthLimit = 3 -- secure default for this project when not configured
	end
	if rebirthLimit > 0 and rebirthCount >= rebirthLimit then
		return false
	end

	local tierRequirements = resolveRebirthRequirementForTier(rebirthCount)
	local requiredPets = tierRequirements.RequiredPets or configModule.RebirthRequiredPets
	if not meetsPetRequirements(playerFolder, requiredPets) then
		return false
	end

	local requiredCurrency = tierRequirements.RequiredCurrency or configModule.RebirthRequiredCurrency
	if not canAffordRequirements(player, requiredCurrency) then
		return false
	end

	return true
end

local function clearPetDataStoreForPlayer(player)
	if not player then return end
	local ok, err = pcall(function()
		petDataStore:SetAsync(tostring(player.UserId), {})
	end)
	if not ok then
		warn("[TycoonRebirth] Failed to clear pet datastore for", player.Name, err)
	end
end

local function clearLivePetsForPlayer(player)
	if not player then return end
	local clearEvent = ReplicatedStorage:FindFirstChild("PetSystemClearPlayerPets")
	if clearEvent and clearEvent:IsA("BindableEvent") then
		clearEvent:Fire(player.UserId)
	end
end

local function applyMainSystemRebirth(player)
	if not player then return end
	local dataFolder = player:FindFirstChild("Data")
	if not dataFolder then return end
	local playerData = dataFolder:FindFirstChild("PlayerData")
	if not playerData then return end

	local rebirthValue = playerData:FindFirstChild("Rebirth")
	if rebirthValue and (rebirthValue:IsA("IntValue") or rebirthValue:IsA("NumberValue")) then
		rebirthValue.Value = (tonumber(rebirthValue.Value) or 0) + 1
	end
end

local Tycoon = {}
Tycoon.__index = Tycoon

function Tycoon.new(tycoon: Instance)
	local newTycoon = {}
	setmetatable(newTycoon, Tycoon)
	
	newTycoon.Tycoon = tycoon
	
	return newTycoon
end

local function CombineTables(tbl1, tbl2)
	for _, v in ipairs(tbl2) do
		if not v then continue end
		if not table.find(tbl1, v) then
			table.insert(tbl1, v)
		end
	end
	return tbl1
end

function Tycoon:Initialize()
	local purchasedFolder = self.Tycoon:FindFirstChild("PurchasedObjects")
		or Instance.new("Folder", self.Tycoon)
	purchasedFolder.Name = "PurchasedObjects"

	if typeof(configModule.AutoCollect) == "boolean" then
		self.Tycoon:SetAttribute("AutoCollectEnabled", configModule.AutoCollect)
	else
		self.Tycoon:SetAttribute("AutoCollectEnabled", false)
		self:UpdateAutoCollect()
	end

	self.TotalPurchasedButtons = self.TotalPurchasedButtons or 0
	self.PurchasedObjects = self.PurchasedObjects or {}
	self.RemovedObjects = self.RemovedObjects or {}
	self.PurchasedSpecialButtons = self.PurchasedSpecialButtons or {} -- For game pass, group, and dev product buttons
	self.RebirthPersistentButtons = self.RebirthPersistentButtons or {}
	
	-- Create a backup of the tycoon for resets
	if not self.Backup then
		self.Backup = self.Tycoon:Clone()
		for i, v in ipairs(self.Backup:GetChildren()) do
			if v:IsA("Script") then
				v:Destroy()
			end
		end
	end
	
	local dropsFolder = Instance.new("Folder")
	dropsFolder.Name = self.Tycoon.Name
	dropsFolder.Parent = workspace:FindFirstChild("Drops")
	
	self.DefaultDropColor = self.Tycoon:GetAttribute("DropColor") or BrickColor.new("Medium stone grey")
	self.DefaultDropMaterial = self.Tycoon:GetAttribute("DropMaterial") or "Plastic"

	-- Set up any objects in Essentials (currency collectors, drop collectors, etc.)
	for _, object in ipairs(self.Tycoon.Essentials:GetChildren()) do
		self:SetUpObject(object)
	end
	
	local spawnLocation = self.Tycoon.Essentials:FindFirstChildWhichIsA("SpawnLocation")
	if spawnLocation then
		spawnLocation.BrickColor = self.Tycoon:GetAttribute("TycoonColor")
		spawnLocation.TeamColor = self.Tycoon:GetAttribute("TycoonColor")
	end
	
	self.Buttons = {}
	self.Objects = {}
	
	for _, instance in ipairs(self.Tycoon.Buttons:GetChildren()) do
		if not instance:FindFirstChild("Head") or not instance:FindFirstChild("Head"):IsA("BasePart") then
			warn("Button '"..instance.Name.."' requires a BasePart named 'Head'; removed button")
			instance:Destroy()
			continue
		end
		
		local button = Button.new(instance, self.Tycoon)
		local isInitialized = button:Initialize()
		if isInitialized == false then button = nil continue end
		table.insert(self.Buttons, button)
	end
	
	self.Dependencies = {Purchases = {}, Removables = {}}
	
	local globalButtonDebounce = true
	for _, button in ipairs(self.Buttons) do
		if button.PurchaseObjects then
			for _, object in ipairs(button.PurchaseObjects) do
				object.Parent = nil
				self.Objects[object.Name] = object
			end
		end
		
		if not button.Instance.Parent then
			if button.PurchaseDependencies then
				for _, dependency in ipairs(button.PurchaseDependencies) do
					if not self.Dependencies.Purchases[dependency] then
						self.Dependencies.Purchases[dependency] = {}
					end
					table.insert(self.Dependencies.Purchases[dependency], button)
				end
			end
			if button.RemoveDependencies then
				for _, dependency in ipairs(button.RemoveDependencies) do
					if not self.Dependencies.Removables[dependency] then
						self.Dependencies.Removables[dependency] = {}
					end
					table.insert(self.Dependencies.Removables[dependency], button)
				end
			end
		end
		
		local errorSoundDebounce = true
		button.Instance.Head.Touched:Connect(function(hit)
			if not globalButtonDebounce then return end
			
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			local owner = Players:GetPlayerByUserId(self.Tycoon:GetAttribute("OwnerId"))
			if not owner or not player or player ~= owner then return end
			
			local ownerFolder = ServerStorage.PlayerData:FindFirstChild(owner.UserId)
			if not ownerFolder then return end
			globalButtonDebounce = false
			
			local purchaseSuccess = button:AttemptPurchase()
			if purchaseSuccess then
				button.Instance.Head.CanTouch = false
				
				-- Update self.PurchasedObjects and self.RemovedObjects before handling dependencies
				if button.PurchaseObjects then
					for _, object in ipairs(button.PurchaseObjects) do
						table.insert(self.PurchasedObjects, object.Name)
						object.Parent = self.Tycoon.PurchasedObjects
						self:SetUpObject(object)
						
						animationsModule.PlayAnimation(owner, object, "Purchase")
					end
				end
				
				if button.RemoveObjects then
					for _, object in ipairs(button.RemoveObjects) do
						table.insert(self.RemovedObjects, object.Name)
					end
				end
				
				if button.PurchaseObjects then
					for _, object in ipairs(button.PurchaseObjects) do
						self:HandleDependencies(object, self.Dependencies.Purchases)
					end
				end
				
				if button.RemoveObjects then
					for _, object in ipairs(button.RemoveObjects) do
						self:HandleDependencies(object, self.Dependencies.Removables)
						
						animationsModule.PlayAnimation(owner, object, "Remove")
						task.delay(configModule.ObjectRemoveAnimationTime, function()
							object:Destroy()
						end)
					end
				end
				
				self.TotalPurchasedButtons += 1
				table.remove(self.Buttons, table.find(self.Buttons, button))
				button.Instance:SetAttribute("Purchased", true)
				
				if button.Instance:HasTag("KeepOnRebirth") then
					table.insert(self.RebirthPersistentButtons, button.Instance.Name)
				end
				
				local completionPercentage = self:GetCompletionPercentage()
				if configModule.RebirthsEnabled and completionPercentage >= configModule.RebirthCompletionPercentage then
					rebirthEvent:FireClient(owner)
				end
				
				PlaySoundAtSource("PurchaseSound", self.Tycoon, button.Instance.Head, true)
				
				animationsModule.PlayAnimation(owner, button.Instance, "ButtonVanish")
				task.delay(configModule.ButtonVanishAnimationTime, function()
					button:Destroy()
				end)
			elseif errorSoundDebounce == true then
				errorSoundDebounce = false
				PlaySoundAtSource("ErrorPurchaseSound", self.Tycoon, button.Instance.Head)
				local errorSoundLength = soundsFolder:FindFirstChild("ErrorPurchaseSound") and soundsFolder.ErrorPurchaseSound.TimeLength
				if errorSoundLength then
					task.delay(errorSoundLength, function()
						errorSoundDebounce = true
					end)
				end
			end
			
			task.wait(configModule.PurchaseCooldown)
			
			globalButtonDebounce = true
		end)
	end

	local gatePart = self.Tycoon.Essentials.Gate:FindFirstChildWhichIsA("Model").Head
	if not gatePart then return end

	-- Assign the tycoon an owner when the gate is interacted with if it has none
	local function assignTycoon(hit)
		-- If hit or its parent aren't valid or the tycoon already has an owner, return
		if (not hit) or (not hit.Parent) then return end
		if self.Tycoon:GetAttribute("OwnerId") ~= 0 then return end

		local player = hit.Parent == Players and hit or Players:GetPlayerFromCharacter(hit.Parent)

		self:AssignTycoon(player)
		PlaySoundAtSource("TycoonClaimSound", self.Tycoon, self.Tycoon.Essentials.Gate:FindFirstChildWhichIsA("Model").Head)
	end

	if gatePart:FindFirstChildWhichIsA("ProximityPrompt") then
		if self.Tycoon:GetAttribute("OwnerId") ~= 0 then
			gatePart:FindFirstChildWhichIsA("ProximityPrompt").Enabled = false
		end

		gatePart:FindFirstChildWhichIsA("ProximityPrompt").Triggered:Connect(assignTycoon)
	else
		gatePart.Touched:Connect(assignTycoon)
	end
end

function Tycoon:HandleDependencies(object : Instance, dependencyTable : table, noAnimations: boolean)
	local dependentButtons = dependencyTable[object]
	if not dependentButtons or #dependentButtons < 1 then return end
	
	local owner = Players:GetPlayerByUserId(self.Tycoon:GetAttribute("OwnerId"))
	for _, dependentButton in ipairs(dependentButtons) do
		local hasInvalidDependency = false
		
		local purchaseDependencies = dependentButton.PurchaseDependencies
		if purchaseDependencies then
			for _, dependency in ipairs(purchaseDependencies) do
				if not table.find(self.PurchasedObjects, dependency.Name) then
					hasInvalidDependency = true
					break
				end
			end
		end
		
		local removeDependencies = dependentButton.RemoveDependencies
		if removeDependencies then
			for _, dependency in ipairs(removeDependencies) do
				if not table.find(self.RemovedObjects, dependency.Name) then
					hasInvalidDependency = true
					break
				end
			end
		end
		
		if hasInvalidDependency then continue end
		
		dependentButton.Instance.Parent = self.Tycoon.Buttons
		if owner and noAnimations ~= true then
			animationsModule.PlayAnimation(owner, dependentButton.Instance, "ButtonAppear")
		end
	end
end

function Tycoon:AssignTycoon(player: Player)
	if not player then return end
	if self.Tycoon:GetAttribute("OwnerId") and self.Tycoon:GetAttribute("OwnerId") ~= 0 and self.Tycoon:GetAttribute("OwnerId") ~= player.UserId then return end
	
	local playerFolder = ServerStorage:FindFirstChild("PlayerData"):FindFirstChild(player.UserId)
	if not playerFolder then return end
	
	local playerTycoonValue = playerFolder:FindFirstChild("Tycoon")
	if not playerTycoonValue or (playerTycoonValue.Value ~= nil and playerTycoonValue.Value ~= self.Tycoon) then return end
	
	self.Tycoon:SetAttribute("OwnerId", player.UserId)
	playerTycoonValue.Value = self.Tycoon
	
	if configModule.RebirthsEnabled then
		for _, button in ipairs(self.Buttons) do
			if button.Instance:GetAttribute("PostRebirthText") then
				local rebirths = playerFolder:GetAttribute(configModule.RebirthsName)
				local rebirthsRequired = button.Instance:GetAttribute(configModule.RebirthsName)
				if rebirthsRequired and rebirths >= rebirthsRequired then
					button.Instance.Name = button.Instance:GetAttribute("PostRebirthText")
				end
			end
		end
	end
	
	local gatePart = self.Tycoon.Essentials.Gate:FindFirstChildWhichIsA("Model").Head
	if not gatePart then return end
	
	gatePart.Transparency = 0.5
	
	local playerName = player.DisplayName or player.Name
	gatePart.Parent.Name = playerName.."'s Tycoon"
	
	local proximityPrompt = gatePart:FindFirstChildWhichIsA("ProximityPrompt")
	if not proximityPrompt then return end
	
	proximityPrompt.Enabled = false
end

function Tycoon:ResetTycoon(isRebirth: boolean)
	local purchasesToKeep = {{}, {}, {}}
	
	if isRebirth == true then
		for _, button in ipairs(self.RebirthPersistentButtons) do
			if #button >= 2 then
				table.insert(purchasesToKeep[1], button[1]) -- Button name
				table.insert(purchasesToKeep[2], button[2]) -- Purchase objects
				if #button == 3 then
					table.insert(purchasesToKeep[3], button[3]) -- Remove objects
				end
			end
		end
	else
		self.TotalPurchasedButtons = 0
		self.PurchasedObjects = {}
		self.RemovedObjects = {}
		self.PurchasedSpecialButtons = {}
		self.RebirthPersistentButtons = {}
	end
	
	self.Tycoon:ClearAllChildren()
	
	local drops = workspace:FindFirstChild("Drops") and workspace.Drops:FindFirstChild(self.Tycoon.Name)
	if drops then
		drops:Destroy()
	end
	
	for _, v in ipairs(self.Backup:GetChildren()) do
		v:Clone().Parent = self.Tycoon
	end
	
	self.TotalPurchasedButtons = 0
	
	self.Tycoon:SetAttribute("DropColor", self.DefaultDropColor)
	self.Tycoon:SetAttribute("DropMaterial", self.DefaultDropMaterial)
	
	-- Re-purchase any buttons that should be kept
	if isRebirth == true then
		local buttons = self.Tycoon:FindFirstChild("Buttons")
		local purchases = self.Tycoon:FindFirstChild("Purchases")
		local purchasedFolder = self.Tycoon:FindFirstChild("PurchasedObjects")
		if buttons and purchases and purchasedFolder then
			self.TotalPurchasedButtons = 0
			self.PurchasedObjects = {}
			self.RemovedObjects = {}
			self.PurchasedSpecialButtons = {} -- For game pass, group, and dev product buttons
			
			for _, buttonName in ipairs(purchasesToKeep[1]) do
				local button = buttons:FindFirstChild(buttonName)
				if button then
					if button:GetAttribute("GamePassId") or button:GetAttribute("GroupId") or button:GetAttribute("DevProductId") then
						table.insert(self.PurchasedSpecialButtons, button.Name)
					else
						self.TotalPurchasedButtons += 1
					end
					button:Destroy()
				end
			end
			
			-- Loop through each kept PurchaseObject and purchase it
			for _, purchaseObjectName in ipairs(purchasesToKeep[2]) do
				local purchaseObject = purchases:FindFirstChild(purchaseObjectName)
				if purchaseObject then
					purchaseObject.Parent = purchasedFolder
					table.insert(self.PurchasedObjects, purchaseObjectName)
				end
			end
			
			-- Loop through each kept RemoveObject and remove it
			for _, removeObjectName in ipairs(purchasesToKeep[3]) do
				local removeObject = purchasedFolder:FindFirstChild(removeObjectName)
				if removeObject then
					removeObject:Destroy()
					table.insert(self.PurchasedObjects, removeObjectName)
				end
			end
		end
	end
	
	self:Initialize()
end

function Tycoon:Rebirth()
	local player = Players:GetPlayerByUserId(self.Tycoon:GetAttribute("OwnerId"))
	if not player then return end
	
	local playerFolder = ServerStorage.PlayerData:FindFirstChild(player.UserId)
	if not playerFolder then return end
	
	local percentComplete = self:GetCompletionPercentage()
	if not canPlayerRebirthNow(player, playerFolder, percentComplete) then
		return
	end

	local rebirthCount = tonumber(playerFolder:GetAttribute(configModule.RebirthsName)) or 0
	local tierRequirements = resolveRebirthRequirementForTier(rebirthCount)
	local requiredCurrency = tierRequirements.RequiredCurrency or configModule.RebirthRequiredCurrency
	if not chargeRequirements(player, requiredCurrency) then
		return
	end

	playerFolder:SetAttribute(configModule.RebirthsName, rebirthCount + 1)
	applyMainSystemRebirth(player)

	-- Rebirth wipe: remove owned pets from memory + datastore
	clearLivePetsForPlayer(player)
	clearPetDataStoreForPlayer(player)
	playerFolder:SetAttribute("OwnedPetNamesCsv", "")

	-- Reset each configured currency to 0 and reset totals if needed
	local ownerPlayer = player
	for i, currency in ipairs(configModule.Currencies) do
		-- force currency wipe on rebirth
		setPlayerCurrencyDirect(ownerPlayer, currency.Name, 0)
		-- reset total counter (TotalCurrency, TotalCurrency2) to 0 if present
		local totalName = "Total" .. tostring(currency.Name)
		setPlayerCurrencyDirect(ownerPlayer, totalName, 0)
	end
	-- extra compatibility for systems that use explicit Currency/Currency2 values
	setPlayerCurrencyDirect(ownerPlayer, "Currency", 0)
	setPlayerCurrencyDirect(ownerPlayer, "Currency2", 0)
	
	self:ResetTycoon(true)
	self:AssignTycoon(Players:GetPlayerByUserId(self.Tycoon:GetAttribute("OwnerId")))
	PlaySoundAtSource("RebirthSound", self.Tycoon, "Client")
end

function Tycoon:GetCompletionPercentage()
	local playerFolder = ServerStorage.PlayerData:FindFirstChild(self.Tycoon:GetAttribute("OwnerId"))
	if not playerFolder then return end
	
	local unlockedButtons = self.TotalPurchasedButtons
	local unpurchasedButtons = {}
	for _, button in ipairs(self.Tycoon.Buttons:GetChildren()) do
		if button:GetAttribute("Purchased") ~= true then
			table.insert(unpurchasedButtons, button)
		end
	end
	for _, button in ipairs(self.Buttons) do
		table.insert(unpurchasedButtons, button.Instance)
	end
	
	for _, button in ipairs(unpurchasedButtons) do
		if button:GetAttribute("GamePassId") or button:GetAttribute("GroupId") or button:GetAttribute("DevProductId") or button:GetAttribute("BadgeId") then continue end
		
		if not button:GetAttribute(configModule.RebirthsName) then
			unlockedButtons += 1
		else
			local playerRebirths = playerFolder:GetAttribute(configModule.RebirthsName)
			if playerRebirths and playerRebirths >= button:GetAttribute(configModule.RebirthsName) then
				unlockedButtons += 1
			end
		end
	end
	
	return math.round((self.TotalPurchasedButtons / unlockedButtons) * 100)
end

function Tycoon:SetUpObject(object: Instance)
	for _, part in ipairs(object:GetDescendants()) do
		if not part:IsA("BasePart") or part.Name ~= "TycoonColorPart" then continue end
		part.BrickColor = self.Tycoon:GetAttribute("TycoonColor") or part.BrickColor
	end
	
	for _, tag in ipairs(object:GetTags()) do
		if objectModules[tag] then
			local newObject = objectModules[tag].new(object, self.Tycoon)
			newObject:Initialize()
		end
	end
end

function Tycoon:UpdateAutoCollect()
	self.Tycoon:SetAttribute("AutoCollectEnabled", false)
	
	local owner = Players:GetPlayerByUserId(self.Tycoon:GetAttribute("OwnerId"))
	if not owner then return end
	
	local gamePassId = configModule.AutoCollect
	if typeof(gamePassId) ~= "number" then return end
	
	local success, errorMessage = pcall(function()
		MarketplaceService:GetProductInfo(gamePassId, Enum.InfoType.GamePass)
	end)
	
	if MarketplaceService:UserOwnsGamePassAsync(owner.UserId, gamePassId) then
		self.Tycoon:SetAttribute("AutoCollectEnabled", true)
	end
	
	if not success then
		warn("Auto Collect Game Pass' product info with ID "..gamePassId.." could not be found. Make sure the ID is correct in the Settings module. Error message:")
		warn(errorMessage)
		return
	end
end

return Tycoon
