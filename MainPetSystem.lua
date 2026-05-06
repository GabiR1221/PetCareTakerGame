
-- Main Pet System Orchestrator
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PhysicsService = game:GetService("PhysicsService")

-- Create PetSystem folder if it doesn't exist
local PetSystem = ServerScriptService:FindFirstChild("PetSystem") or Instance.new("Folder")
PetSystem.Name = "PetSystem"
PetSystem.Parent = ServerScriptService

-- Require modules
local Modules = PetSystem:FindFirstChild("Modules") or Instance.new("Folder")
Modules.Name = "Modules"
Modules.Parent = PetSystem

local PetStateManager = require(Modules:WaitForChild("PetStateManager"))
local PetAttachmentManager = require(Modules:WaitForChild("PetAttachmentManager"))
local TycoonUtils = require(Modules:WaitForChild("TycoonUtils"))
local PetRigManager = require(Modules:WaitForChild("PetRigManager"))
local PetAnimationManager = require(Modules:WaitForChild("PetAnimationManager"))
local PromptManager = require(Modules:WaitForChild("PromptManager"))
local NPCManager = require(Modules:WaitForChild("NPCManager"))
local ShowerDryerManager = require(Modules:WaitForChild("ShowerDryerManager"))
local AccessoryManager = require(Modules:WaitForChild("AccessoryManager"))
local PetGroundManager = require(Modules:WaitForChild("PetGroundManager"))
local WildPetManager = require(Modules:WaitForChild("WildPetManager"))
local PetSaveManager = require(Modules:WaitForChild("PetSaveManager"))
local PetFeedingManager = require(Modules:WaitForChild("PetFeedingManager"))
local PetStandManager = require(Modules:WaitForChild("PetStandManager"))
local PetMoodVisualManager = require(Modules:WaitForChild("PetMoodVisualManager"))
local SprintRunManager = require(Modules:WaitForChild("SprintRunManager"))
local ToyHappinessManager = require(Modules:WaitForChild("ToyHappinessManager"))
-- Services
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

-- External dependencies
local Config = require(ServerScriptService:WaitForChild("NPCConfig"))
local PetMovement = require(ServerScriptService:WaitForChild("PetMovement"))

-- Remote Events
local accessoryEvent = ReplicatedStorage:FindFirstChild("PetAccessoryEvent")
local petStateEvent = ReplicatedStorage:FindFirstChild("PetStateEvent")
local petCarryEvent = ReplicatedStorage:FindFirstChild("PetCarryEvent")
local PetGamepassGrantBridgeName = "PetGamepassGrantBridge"
local PetSellBridgeName = "PetSellBridge"
local PetSellRequestBridgeName = "PetSellRequestBridge"
local PetInventoryAdoptionBridgeName = "PetInventoryAdoptionBridge"
local PetRuntimeStateBridgeName = "PetRuntimeStateBridge"
-- Configuration
local SHOWER_HOLD_TIME = 3
local PICKUP_PROMPT_MAX_DISTANCE = 6
local GIVEBACK_PROMPT_MAX_DISTANCE = 6
local SHOWER_XP = 20
local DRY_XP = 12
local PETGROUND_XP_PER_SEC = 5
local ENABLE_PET_PICKUP_TOOLS = true -- Set to false to restore weld/carry pickup behavior.
local MAX_ACTIVE_WANDERING_PETS = 3
local GAME_NOTIFICATION_EVENT_NAME = "GameNotificationEvent"

-- Initialize state trackers (these could be moved to their respective managers)
local carryingPetByUserId = {}
local petState = {}
local petGroundConnected = {}
local petGroundXPTasks = {}
local petGroundDirtinessTasks = {}
local petPickupPromptConns = {}
local sellPromptConns = {}
local attachDropPickupPrompt
local createPetPickupTool
local isInsideTycoonBounds
local stashedPetModelsByUserId = {}
local petInteractionUiEvent = ReplicatedStorage:FindFirstChild("PetInteractionUIEvent")
if not petInteractionUiEvent then
	petInteractionUiEvent = Instance.new("RemoteEvent")
	petInteractionUiEvent.Name = "PetInteractionUIEvent"
	petInteractionUiEvent.Parent = ReplicatedStorage
end

local function getStashedPetBucket(userId)
	if not stashedPetModelsByUserId[userId] then
		stashedPetModelsByUserId[userId] = {}
	end
	return stashedPetModelsByUserId[userId]
end

local function setPetStashedModel(userId, petUid, petModel)
	if not userId or type(petUid) ~= "string" or petUid == "" then return end
	local bucket = getStashedPetBucket(userId)
	bucket[petUid] = petModel
end

local function getPetStashedModel(userId, petUid)
	local bucket = stashedPetModelsByUserId[userId]
	if not bucket then return nil end
	return bucket[petUid]
end

local function clearPetStashedModel(userId, petUid)
	local bucket = stashedPetModelsByUserId[userId]
	if not bucket then return end
	bucket[petUid] = nil
	if next(bucket) == nil then
		stashedPetModelsByUserId[userId] = nil
	end
end

local function setInteractionUiHidden(player, hidden)
	if not petInteractionUiEvent or not player then return end
	pcall(function()
		player:SetAttribute("PetInteractionActive", hidden == true)
	end)
	pcall(function()
		petInteractionUiEvent:FireClient(player, hidden == true)
	end)
end

local function getTycoonReturnPartForPlayer(userId)
	local tycoonModel = TycoonUtils:FindTycoonByOwnerId(userId)
	local desk = nil
	if tycoonModel then
		local ess = TycoonUtils:FindEssentialsInModel(tycoonModel)
		desk = TycoonUtils:FindDeskInEssentials(ess)
	else
		local fallbackTycoon, fallbackDesk = TycoonUtils:FindTycoonByOwnerIdWithDesk(userId)
		tycoonModel = fallbackTycoon
		desk = fallbackDesk
	end
	if not tycoonModel then
		return nil, nil, nil
	end
	local returnPart = TycoonUtils:GetPreferredReturnPartForTycoon(tycoonModel, desk)
	return tycoonModel, returnPart, desk
end

local function canPlayerDropCarriedPet(player, carriedPet)
	if not player or not carriedPet then return false end
	local state = petState[carriedPet]
	if not state then return false end
	if state.ownerUserId and tostring(state.ownerUserId) ~= tostring(player.UserId) then
		return false
	end
	return state.wild ~= true
end

local function canPlayerDropCarriedPetAtCurrentPosition(player, carriedPet)
	if not canPlayerDropCarriedPet(player, carriedPet) then
		return false
	end

	local character = player.Character
	local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
	if not root then
		return false
	end

	local tycoonModel, returnPart = getTycoonReturnPartForPlayer(player.UserId)
	local boundaryReference = carriedPet and (carriedPet.PrimaryPart or carriedPet:FindFirstChildWhichIsA("BasePart")) or root
	if tycoonModel and returnPart and not isInsideTycoonBounds(boundaryReference, tycoonModel, returnPart) then
		return false
	end

	return true
end

local function resolveInventoryPetIdByUid(player, petUid)
	if not player or type(petUid) ~= "string" or petUid == "" then return nil end
	local data = player:FindFirstChild("Data")
	local pets = data and data:FindFirstChild("Pets")
	if not pets then return nil end
	for _, petFolder in ipairs(pets:GetChildren()) do
		local uidValue = petFolder:FindFirstChild("PetUID")
		if uidValue and uidValue.Value == petUid then
			return tostring(petFolder.Name)
		end
	end
	return nil
end

local function resolveInventoryPetIdByPetName(player, petName)
	if not player or type(petName) ~= "string" or petName == "" then return nil end
	local data = player:FindFirstChild("Data")
	local pets = data and data:FindFirstChild("Pets")
	if not pets then return nil end
	for _, petFolder in ipairs(pets:GetChildren()) do
		local petNameValue = petFolder:FindFirstChild("PetName")
		if petNameValue and tostring(petNameValue.Value) == petName then
			return tostring(petFolder.Name)
		end
	end
	return nil
end

local function setInventoryRuntimeLocation(player, inventoryPetId, location)
	if not player or not inventoryPetId then return end
	local data = player:FindFirstChild("Data")
	local petsFolder = data and data:FindFirstChild("Pets")
	local inventoryPet = petsFolder and petsFolder:FindFirstChild(tostring(inventoryPetId))
	if not inventoryPet then return end

	local runtimeLocation = inventoryPet:FindFirstChild("RuntimeLocation")
	if not runtimeLocation then
		runtimeLocation = Instance.new("StringValue")
		runtimeLocation.Name = "RuntimeLocation"
		runtimeLocation.Parent = inventoryPet
	end
	runtimeLocation.Value = tostring(location or "")
end

local function getNotificationEvent()
	local ev = ReplicatedStorage:FindFirstChild(GAME_NOTIFICATION_EVENT_NAME)
	if ev and ev:IsA("RemoteEvent") then
		return ev
	end
	return nil
end

local function notifyWanderingLimitReached(player)
	local ev = getNotificationEvent()
	if not ev or not player then return end
	ev:FireClient(player, "error", "❌ You can only have 3 wandering pets active at a time.")
end

local function countActiveOwnedWanderingPets(userId)
	local count = 0
	for petModel, state in pairs(petState) do
		if petModel and petModel.Parent and state and tostring(state.ownerUserId) == tostring(userId) then
			if state.wild ~= true and tostring(state.location) == "free" then
				count += 1
			end
		end
	end
	return count
end

local function dropCarriedPet(player, options)
	options = options or {}
	local carriedPet = carryingPetByUserId[player.UserId]
	if not carriedPet or not carriedPet.Parent then return false end
	local state = petState[carriedPet]
	if not state then return false end
	if state.ownerUserId and tostring(state.ownerUserId) ~= tostring(player.UserId) then return false end
	if options.blockWildDrop and state.wild then return false end

	if countActiveOwnedWanderingPets(player.UserId) >= MAX_ACTIVE_WANDERING_PETS then
		notifyWanderingLimitReached(player)
		return false
	end

	local character = player.Character
	local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
	if not root then return false end

	PetAttachmentManager:DetachPetFromPlayer(carriedPet)
	carriedPet.Parent = workspace

	pcall(function()
		PetRigManager:EnsurePetRig(carriedPet)
		PetAnimationManager:SetupAnimatorForPet(carriedPet)
	end)

	local dropPos = root.Position + (root.CFrame.LookVector * 3)
	if options.forcePosition and typeof(options.forcePosition) == "Vector3" then
		dropPos = options.forcePosition
	end

	if carriedPet.PrimaryPart then
		local yOffset = (carriedPet.PrimaryPart.Size.Y * 0.5) + 0.3
		carriedPet:SetPrimaryPartCFrame(CFrame.new(dropPos + Vector3.new(0, yOffset, 0)))
		pcall(function()
			carriedPet.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
			carriedPet.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
		end)
	end

	state.location = "free"
	state.npc = nil
	state.shower = nil

	PetMovement.StartWandering(carriedPet)
	attachDropPickupPrompt(carriedPet, state.ownerUserId or player.UserId)
	PetStateManager:SendStateToOwner(carriedPet)
	return true
end

local function getPickupPartFromPet(petModel)
	if not petModel or not petModel:IsA("Model") then return nil end
	local helper = petModel:FindFirstChild("PetPickupPart")
	if helper and helper:IsA("BasePart") then
		return helper
	end
	local primary = petModel.PrimaryPart or petModel:FindFirstChildWhichIsA("BasePart")
	return primary
end

local function removePetToolInstances(player, petUid)
	if not player or type(petUid) ~= "string" or petUid == "" then return end
	for _, container in ipairs({ player:FindFirstChild("Backpack"), player:FindFirstChild("StarterGear"), player.Character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and tostring(child:GetAttribute("PetUID") or "") == petUid then
					child:Destroy()
				end
			end
		end
	end
end

local function removePetToolForPlacedPet(player, petModel)
	if not player or not petModel then return false end
	local state = petState[petModel]
	if not state then return false end
	if tostring(state.ownerUserId) ~= tostring(player.UserId) then return false end
	local petUid = tostring(state.petUid or petModel:GetAttribute("PetUID") or "")
	if petUid == "" then return false end
	removePetToolInstances(player, petUid)
	clearPetStashedModel(player.UserId, petUid)
	return true
end

local function findOwnedPetByUid(userId, petUid)
	if type(petUid) ~= "string" or petUid == "" then return nil, nil end
	local stashed = getPetStashedModel(userId, petUid)
	if stashed and stashed.Parent then
		return stashed, petState[stashed]
	end

	for petModel, state in pairs(petState) do
		if state and tostring(state.ownerUserId) == tostring(userId) then
			local modelUid = tostring(state.petUid or petModel:GetAttribute("PetUID") or "")
			if modelUid == petUid then
				return petModel, state
			end
		end
	end
	return nil, nil
end

local function getEquippedPetToolUid(player)
	if not player then return nil end
	local character = player.Character
	if not character then return nil end
	local equippedTool = character:FindFirstChildOfClass("Tool")
	if not equippedTool then return nil end
	if equippedTool:GetAttribute("PetTool") ~= true then return nil end
	local petUid = tostring(equippedTool:GetAttribute("PetUID") or "")
	if petUid == "" then return nil end
	return petUid
end

local function resolvePlayerInteractionPet(player)
	if not player then return nil, nil, nil end
	local carriedPet = carryingPetByUserId[player.UserId]
	if carriedPet and carriedPet.Parent then
		return carriedPet, petState[carriedPet], "carried"
	end

	local equippedPetUid = getEquippedPetToolUid(player)
	if not equippedPetUid then
		return nil, nil, nil
	end

	local petModel, state = findOwnedPetByUid(player.UserId, equippedPetUid)
	if not petModel or not state then
		return nil, nil, nil
	end
	if tostring(state.ownerUserId) ~= tostring(player.UserId) then
		return nil, nil, nil
	end
	if state.wild == true then
		return nil, nil, nil
	end

	if tostring(state.location) ~= "inventory" and tostring(state.location) ~= "player" then
		return nil, nil, nil
	end

	return petModel, state, "tool"
end

local function dropPetFromTool(player, petUid)
	if not player or type(petUid) ~= "string" or petUid == "" then return false end

	local petModel, state = findOwnedPetByUid(player.UserId, petUid)
	if not petModel or not state then
		removePetToolInstances(player, petUid)
		return false
	end
	if tostring(state.ownerUserId) ~= tostring(player.UserId) then
		return false
	end

	if countActiveOwnedWanderingPets(player.UserId) >= MAX_ACTIVE_WANDERING_PETS then
		notifyWanderingLimitReached(player)
		return false
	end

	local character = player.Character
	local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
	if not root then
		return false
	end
	local tycoonModel, returnPart = getTycoonReturnPartForPlayer(player.UserId)
	if tycoonModel and returnPart and not isInsideTycoonBounds(root, tycoonModel, returnPart) then
		return false
	end

	removePetToolInstances(player, petUid)
	clearPetStashedModel(player.UserId, petUid)

	PetAttachmentManager:DetachPetFromPlayer(petModel)
	petModel.Parent = workspace
	pcall(function()
		PetRigManager:EnsurePetRig(petModel)
		PetAnimationManager:SetupAnimatorForPet(petModel)
	end)

	if petModel.PrimaryPart then
		local dropPos = root.Position + (root.CFrame.LookVector * 3)
		local yOffset = (petModel.PrimaryPart.Size.Y * 0.5) + 0.3
		petModel:SetPrimaryPartCFrame(CFrame.new(dropPos + Vector3.new(0, yOffset, 0)))
		pcall(function()
			petModel.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
			petModel.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
		end)
	end

	state.location = "free"
	state.npc = nil
	state.shower = nil
	state.accessoryTable = nil
	state.petstand = nil
	state.petstandRoot = nil
	state.petground = nil

	PetMovement.StartWandering(petModel)
	attachDropPickupPrompt(petModel, state.ownerUserId or player.UserId)
	PetStateManager:SendStateToOwner(petModel)
	setInteractionUiHidden(player, false)
	return true
end



local function stowCarriedPetAsTool(player)
	if not player then return false end
	local carriedPet = carryingPetByUserId[player.UserId]
	if not carriedPet or not carriedPet.Parent then
		return false
	end

	local state = petState[carriedPet]
	if not state or state.wild == true then
		return false
	end
	if tostring(state.ownerUserId) ~= tostring(player.UserId) then
		return false
	end

	PetAttachmentManager:DetachPetFromPlayer(carriedPet)
	carriedPet.Parent = ServerStorage
	state.location = "inventory"
	state.npc = nil
	state.shower = nil
	local petUid = tostring(state.petUid or carriedPet:GetAttribute("PetUID") or "")
	if petUid == "" then
		return false
	end
	setPetStashedModel(player.UserId, petUid, carriedPet)
	PetStateManager:SendStateToOwner(carriedPet)
	for _, container in ipairs({ player:FindFirstChild("Backpack"), player.Character, player:FindFirstChild("StarterGear") }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and tostring(item:GetAttribute("PetUID") or "") == petUid then
					return true
				end
			end
		end
	end
	return createPetPickupTool(player, carriedPet, state)
end

local function equipPetToolByUid(player, petUid)
	if not player or type(petUid) ~= "string" or petUid == "" then return end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end
	for _, tool in ipairs(backpack:GetChildren()) do
		if tool:IsA("Tool") and tostring(tool:GetAttribute("PetUID") or "") == petUid then
			humanoid:EquipTool(tool)
			break
		end
	end
end

local function stowPetAsToolForPlayer(player, petModel, autoEquip)
	if not player or not petModel then return false end
	local state = petState[petModel]
	if not state then return false end
	if tostring(state.ownerUserId) ~= tostring(player.UserId) then return false end
	if state.wild == true then return false end

	PetAttachmentManager:DetachPetFromPlayer(petModel)
	if petModel.PrimaryPart then
		PetAttachmentManager:ClearWeldsOnPart(petModel.PrimaryPart)
		pcall(function()
			petModel.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
			petModel.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
		end)
	end
	petModel.Parent = ServerStorage

	local petUid = tostring(state.petUid or petModel:GetAttribute("PetUID") or "")
	if petUid == "" then return false end

	state.location = "inventory"
	state.npc = nil
	state.shower = nil
	state.accessoryTable = nil
	state.petstand = nil
	state.petstandRoot = nil
	state.petground = nil
	setPetStashedModel(player.UserId, petUid, petModel)

	createPetPickupTool(player, petModel, state)
	if autoEquip ~= false then
		equipPetToolByUid(player, petUid)
	end
	PetStateManager:SendStateToOwner(petModel)
	setInteractionUiHidden(player, false)
	return true
end

local function buildPetToolHandle(petModel)
	local sourcePart = nil
	if petModel then
		for _, candidate in ipairs(petModel:GetDescendants()) do
			if candidate:IsA("MeshPart") and candidate.Transparency < 0.95 then
				sourcePart = candidate
				break
			end
		end
		if not sourcePart then
			for _, candidate in ipairs(petModel:GetDescendants()) do
				if candidate:IsA("BasePart")
					and candidate.Transparency < 0.95
					and candidate.Name ~= "HumanoidRootPart"
				then
					sourcePart = candidate
					break
				end
			end
		end
	end
	local handle = nil

	if sourcePart and sourcePart:IsA("BasePart") then
		handle = sourcePart:Clone()
		for _, desc in ipairs(handle:GetDescendants()) do
			if not desc:IsA("DataModelMesh") and not desc:IsA("SpecialMesh") then
				desc:Destroy()
			end
		end
	else
		handle = Instance.new("Part")
		handle.Color = Color3.fromRGB(155, 208, 255)
	end

	handle.Name = "Handle"
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Transparency = math.clamp(tonumber(handle.Transparency) or 0, 0, 0.2)
	if not sourcePart then
		handle.Size = Vector3.new(1.1, 1.1, 1.1)
	end
	handle.CFrame = CFrame.new()
	return handle
end

local function normalizeImageAssetId(assetValue)
	if type(assetValue) == "number" then
		if assetValue <= 0 then return nil end
		return "rbxassetid://" .. math.floor(assetValue)
	end
	if type(assetValue) ~= "string" then
		return nil
	end
	local trimmed = string.match(assetValue, "^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		return nil
	end
	if string.find(trimmed, "rbxassetid://", 1, true) then
		return trimmed
	end
	local digits = string.match(trimmed, "(%d+)")
	if digits then
		return "rbxassetid://" .. digits
	end
	return nil
end

local function attachToolBillboardFromPet(tool, handle, petModel)
	if not tool or not handle or not petModel then return end
	local src = petModel:FindFirstChild("MainBillboard", true)
	if not src or not src:IsA("BillboardGui") then return end
	local existing = handle:FindFirstChild("MainBillboard")
	if existing then
		existing:Destroy()
	end
	local clone = src:Clone()
	clone.Name = "MainBillboard"
	clone.Enabled = true
	clone.AlwaysOnTop = true
	clone.Adornee = handle
	clone.Parent = handle
end

local function resolvePetTemplateImage(template)
	if not template then return nil end

	for _, attrName in ipairs({"InventoryImage", "IconImageId", "PetImageId", "ImageAssetId", "ThumbnailId", "ImageId"}) do
		local image = normalizeImageAssetId(template:GetAttribute(attrName))
		if image then return image end
	end

	local settings = template:FindFirstChild("Settings")
	if settings then
		for _, valueName in ipairs({"InventoryImage", "IconImageId", "ImageId", "ThumbnailId"}) do
			local valueObject = settings:FindFirstChild(valueName)
			if valueObject and valueObject:IsA("ValueBase") then
				local image = normalizeImageAssetId(valueObject.Value)
				if image then return image end
			end
		end
	end

	local decal = template:FindFirstChildWhichIsA("Decal", true)
	if decal then
		local image = normalizeImageAssetId(decal.Texture)
		if image then return image end
	end
	local texture = template:FindFirstChildWhichIsA("Texture", true)
	if texture then
		local image = normalizeImageAssetId(texture.Texture)
		if image then return image end
	end

	return nil
end

local function resolvePetToolTextureId(petModel, petName)
	local petsFolder = ReplicatedStorage:FindFirstChild("Pets")
	if not petsFolder then
		return nil
	end

	local templateName = tostring((petModel and petModel:GetAttribute("TemplateName")) or petName or "")
	if templateName == "" then
		templateName = tostring(petName or "")
	end
	if templateName == "" then
		return nil
	end

	local template = petsFolder:FindFirstChild(templateName)
	if not template then
		for _, candidate in ipairs(petsFolder:GetChildren()) do
			if string.lower(candidate.Name) == string.lower(templateName) then
				template = candidate
				break
			end
		end
	end
	local image = resolvePetTemplateImage(template)
	if image then
		return image
	end
	return nil
end

createPetPickupTool = function(player, petModel, state)
	local petUid = tostring(state.petUid or petModel:GetAttribute("PetUID") or "")
	if petUid == "" then
		return false
	end

	removePetToolInstances(player, petUid)

	local petName = tostring(petModel:GetAttribute("TemplateName") or petModel.Name or "Pet")
	local tool = Instance.new("Tool")
	tool.Name = petName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("PetTool", true)
	tool:SetAttribute("InventoryCategory", "Pets")
	tool:SetAttribute("PetUID", petUid)
	tool:SetAttribute("TemplateName", petName)
	tool:SetAttribute("SkipToolSave", true)
	local toolTextureId = resolvePetToolTextureId(petModel, petName)
	if toolTextureId then
		tool.TextureId = toolTextureId
		tool:SetAttribute("IconImageId", toolTextureId)
		tool:SetAttribute("InventoryImage", toolTextureId)
	end

	local handle = buildPetToolHandle(petModel)
	handle.Parent = tool
	attachToolBillboardFromPet(tool, handle, petModel)

	tool.Activated:Connect(function()
		dropPetFromTool(player, petUid)
	end)

	tool.Parent = player:WaitForChild("Backpack")
	local starterGear = player:FindFirstChild("StarterGear")
	if starterGear then
		local starterTool = tool:Clone()
		starterTool.Activated:Connect(function()
			dropPetFromTool(player, petUid)
		end)
		starterTool.Parent = starterGear
	end
	return true
end

local function tryPickupOwnedPetAsTool(player, petModel)
	if not player or not petModel or not petModel:IsA("Model") or not petModel.Parent then
		return false
	end

	local state = petState[petModel]
	if not state or state.wild == true then
		return false
	end
	if tostring(state.ownerUserId) ~= tostring(player.UserId) then
		return false
	end
	if state.location == "player" or state.location == "npc" or state.location == "shower" then
		return false
	end

	local character = player.Character
	local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
	local pickupPart = getPickupPartFromPet(petModel)
	if not root or not pickupPart then
		return false
	end

	local maxDistance = tonumber(pickupPart:GetAttribute("PickupDistance")) or PICKUP_PROMPT_MAX_DISTANCE
	if (pickupPart.Position - root.Position).Magnitude > (maxDistance + 1.5) then
		return false
	end

	PetMovement.StopWandering(petModel)
	local helper = petModel:FindFirstChild("PetPickupPart")
	if helper then
		pcall(function() helper:Destroy() end)
	end
	if petPickupPromptConns[petModel] then
		pcall(function() petPickupPromptConns[petModel]:Disconnect() end)
		petPickupPromptConns[petModel] = nil
	end

	petModel.Parent = ServerStorage
	state.location = "inventory"
	setPetStashedModel(player.UserId, tostring(state.petUid or petModel:GetAttribute("PetUID") or ""), petModel)
	PetStateManager:SendStateToOwner(petModel)

	local created = createPetPickupTool(player, petModel, state)
	if created then
		equipPetToolByUid(player, tostring(state.petUid or petModel:GetAttribute("PetUID") or ""))
	end
	return created
end

local function restoreInventoryPetToolsForPlayer(player)
	for petModel, state in pairs(petState) do
		if state
			and tostring(state.ownerUserId) == tostring(player.UserId)
			and state.wild ~= true
			and tostring(state.location) == "inventory"
		then
			local petUid = tostring(state.petUid or petModel:GetAttribute("PetUID") or "")
			if petUid ~= "" then
				petModel.Parent = ServerStorage
				setPetStashedModel(player.UserId, petUid, petModel)
				createPetPickupTool(player, petModel, state)
			end
		end
	end
end

local function tryPickupOwnedPet(player, petModel)
	if not player or not petModel or not petModel:IsA("Model") or not petModel.Parent then
		return false
	end
	if carryingPetByUserId[player.UserId] then
		return false
	end

	local state = petState[petModel]
	if not state or state.wild == true then
		return false
	end
	if tostring(state.ownerUserId) ~= tostring(player.UserId) then
		return false
	end
	if state.location == "player" or state.location == "npc" or state.location == "shower" then
		return false
	end

	local character = player.Character
	local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
	local pickupPart = getPickupPartFromPet(petModel)
	if not root or not pickupPart then
		return false
	end

	local maxDistance = tonumber(pickupPart:GetAttribute("PickupDistance")) or PICKUP_PROMPT_MAX_DISTANCE
	if (pickupPart.Position - root.Position).Magnitude > (maxDistance + 1.5) then
		return false
	end

	local ok = pcall(function()
		PetAttachmentManager:AttachPetToPlayer(petModel, player, { resetFlags = false })
	end)
	if not ok then
		return false
	end

	local helper = petModel:FindFirstChild("PetPickupPart")
	if helper then
		pcall(function() helper:Destroy() end)
	end
	if petPickupPromptConns[petModel] then
		pcall(function() petPickupPromptConns[petModel]:Disconnect() end)
		petPickupPromptConns[petModel] = nil
	end

	petState[petModel] = petState[petModel] or {}
	petState[petModel].location = "player"
	PetStateManager:SendStateToOwner(petModel)
	return true
end

isInsideTycoonBounds = function(referencePart, tycoonModel, returnPart)
	if not referencePart or not tycoonModel then return true end

	local boundaryPartName = tostring(tycoonModel:GetAttribute("CarryBoundaryPartName") or "PetCarryBoundary")
	local essentials = TycoonUtils:FindEssentialsInModel(tycoonModel)
	local boundaryPart = essentials and essentials:FindFirstChild(boundaryPartName)
	if boundaryPart and boundaryPart:IsA("BasePart") then
		local localPoint = boundaryPart.CFrame:PointToObjectSpace(referencePart.Position)
		local margin = tonumber(boundaryPart:GetAttribute("CarryBoundaryMargin"))
			or tonumber(tycoonModel:GetAttribute("CarryBoundaryMargin"))
			or 0
		local half = (boundaryPart.Size * 0.5) + Vector3.new(margin, margin, margin)
		return math.abs(localPoint.X) <= half.X
			and math.abs(localPoint.Y) <= half.Y
			and math.abs(localPoint.Z) <= half.Z
	end

	if returnPart and returnPart:IsA("BasePart") then
		local maxCarryDistance = tonumber(tycoonModel:GetAttribute("CarryBoundaryRadius")) or 180
		if (referencePart.Position - returnPart.Position).Magnitude > maxCarryDistance then
			return false
		end
	end
	local ok, boxCFrame, boxSize = pcall(function()
		return tycoonModel:GetBoundingBox()
	end)
	if not ok or not boxCFrame or not boxSize then
		return true
	end
	local localPoint = boxCFrame:PointToObjectSpace(referencePart.Position)
	local margin = 6
	return math.abs(localPoint.X) <= (boxSize.X * 0.5 + margin)
		and math.abs(localPoint.Y) <= (boxSize.Y * 0.5 + margin)
		and math.abs(localPoint.Z) <= (boxSize.Z * 0.5 + margin)
end

local function connectSellPrompt(sellPart, petSellRequestBridge)
	if not sellPart or not sellPart:IsA("BasePart") then return end
	if not petSellRequestBridge or not petSellRequestBridge:IsA("BindableFunction") then return end

	local prompt = sellPart:FindFirstChild("SellPrompt")
	if not prompt or not prompt:IsA("ProximityPrompt") then return end
	if sellPromptConns[prompt] then return end

	sellPromptConns[prompt] = prompt.Triggered:Connect(function(player)
		if not player then return end
		local carriedPet = carryingPetByUserId[player.UserId]
		if not carriedPet or not carriedPet.Parent then return end

		local state = petState[carriedPet]
		if not state or state.wild == true then return end
		if tostring(state.ownerUserId) ~= tostring(player.UserId) then return end

		local petUid = tostring(state.petUid or carriedPet:GetAttribute("PetUID") or "")
		local carriedPetName = tostring(carriedPet:GetAttribute("TemplateName") or carriedPet.Name or "")
		local inventoryPetId = nil
		if petUid ~= "" then
			inventoryPetId = resolveInventoryPetIdByUid(player, petUid)
		end
		if not inventoryPetId then
			inventoryPetId = resolveInventoryPetIdByPetName(player, carriedPetName)
		end
		if not inventoryPetId then return end

		local ok, sold = pcall(function()
			return petSellRequestBridge:Invoke(player, inventoryPetId, { allowOffRing = true, source = "SellPrompt" })
		end)
		if ok and sold then
			carryingPetByUserId[player.UserId] = nil
		end
	end)

	prompt.Destroying:Connect(function()
		if sellPromptConns[prompt] then
			pcall(function() sellPromptConns[prompt]:Disconnect() end)
			sellPromptConns[prompt] = nil
		end
	end)
end

local function scanAndConnectSellPrompts(petSellRequestBridge)
	if not petSellRequestBridge or not petSellRequestBridge:IsA("BindableFunction") then return end
	for _, part in ipairs(workspace:GetDescendants()) do
		if part:IsA("BasePart") and part.Name == "SellPart" then
			connectSellPrompt(part, petSellRequestBridge)
		end
	end
end



function attachDropPickupPrompt(petModel, ownerUserId)
	if not petModel or not petModel:IsA("Model") then return end

	local existingHelper = petModel:FindFirstChild("PetPickupPart")
	if existingHelper then
		pcall(function() existingHelper:Destroy() end)
	end

	local helper = Instance.new("Part")
	helper.Name = "PetPickupPart"
	helper.Size = Vector3.new(1, 1, 1)
	helper.Anchored = false
	helper.Transparency = 1
	helper.CanCollide = false
	helper.CanTouch = false
	helper.CanQuery = false
	helper.Parent = petModel

	local pp = petModel.PrimaryPart or petModel:FindFirstChildWhichIsA("BasePart")
	if pp then
		helper.CFrame = pp.CFrame * CFrame.new(0, pp.Size.Y/2 + 0.5, 0)
		local w = Instance.new("WeldConstraint")
		w.Part0 = helper
		w.Part1 = pp
		w.Parent = helper
	end
	helper:SetAttribute("PickupDistance", PICKUP_PROMPT_MAX_DISTANCE)

	if petPickupPromptConns[petModel] then
		pcall(function() petPickupPromptConns[petModel]:Disconnect() end)
		petPickupPromptConns[petModel] = nil
	end

	petPickupPromptConns[petModel] = nil
end



local function ensurePlayerPetCollisionGroups()
	pcall(function() PhysicsService:RegisterCollisionGroup("Players") end)
	pcall(function() PhysicsService:RegisterCollisionGroup("Pets") end)
	pcall(function() PhysicsService:CollisionGroupSetCollidable("Players", "Pets", false) end)
	pcall(function() PhysicsService:CollisionGroupSetCollidable("Pets", "Pets", false) end)
end

local function setCharacterCollisionGroup(character, groupName)
	if not character then return end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			pcall(function() d.CollisionGroup = groupName end)
		end
	end
end

ensurePlayerPetCollisionGroups()

local function suppressLegacyPetPrompts(instance)
	if ENABLE_PET_PICKUP_TOOLS ~= true then return end
	if instance and instance:IsA("ProximityPrompt") and instance.Name == "PetPrompt" then
		instance.Enabled = false
	end
end

for _, desc in ipairs(workspace:GetDescendants()) do
	suppressLegacyPetPrompts(desc)
end
workspace.DescendantAdded:Connect(function(desc)
	suppressLegacyPetPrompts(desc)
end)

for _, existingPlayer in ipairs(Players:GetPlayers()) do
	local char = existingPlayer.Character
	if char then
		setCharacterCollisionGroup(char, "Players")
	end
end

-- Create NPCs folder
local NPCS_FOLDER = workspace:FindFirstChild("NPCs") or Instance.new("Folder", workspace)
NPCS_FOLDER.Name = "NPCs"

-- Initialize managers with dependencies
PetStateManager:Initialize(petState, petStateEvent, carryingPetByUserId)
PetAttachmentManager:Initialize(petState, carryingPetByUserId, Players, PetMovement)
PetAttachmentManager:SetCarryRemote(petCarryEvent)
PetAnimationManager:Initialize(petState)
NPCManager:Initialize(NPCS_FOLDER, petState, carryingPetByUserId, Players, Config)
ShowerDryerManager:Initialize(petState, carryingPetByUserId, Players, PetMovement, resolvePlayerInteractionPet, stowPetAsToolForPlayer, setInteractionUiHidden)
AccessoryManager:Initialize(petState, carryingPetByUserId, Players, accessoryEvent, ServerStorage, resolvePlayerInteractionPet, stowPetAsToolForPlayer, setInteractionUiHidden)
PetGroundManager:Initialize(petState, carryingPetByUserId, Players, PetMovement, petGroundConnected, petGroundXPTasks, petGroundDirtinessTasks, petPickupPromptConns)

local saveManager = PetSaveManager:Initialize("PetData103", petState, carryingPetByUserId) ----------------------------------------Changingggggg
PetStandManager:Initialize(petState, carryingPetByUserId, Players, PetMovement, saveManager, Config, resolvePlayerInteractionPet, stowPetAsToolForPlayer, setInteractionUiHidden, removePetToolForPlacedPet)
WildPetManager:Initialize(petState, carryingPetByUserId, Players, PetMovement, Config, saveManager)
PetFeedingManager:Initialize(petState, Players, PetStateManager, saveManager, PetMovement)
PetMoodVisualManager:Initialize(petState)
SprintRunManager:Initialize(Players, WildPetManager)
ToyHappinessManager:Initialize(petState, carryingPetByUserId, Players, PetMovement)
ToyHappinessManager:SetSaveManager(saveManager)

local petGamepassGrantBridge = ReplicatedStorage:FindFirstChild(PetGamepassGrantBridgeName)
if not petGamepassGrantBridge or not petGamepassGrantBridge:IsA("BindableEvent") then
	petGamepassGrantBridge = Instance.new("BindableEvent")
	petGamepassGrantBridge.Name = PetGamepassGrantBridgeName
	petGamepassGrantBridge.Parent = ReplicatedStorage
end

local petInventoryAdoptionBridge = ReplicatedStorage:FindFirstChild(PetInventoryAdoptionBridgeName)
if not petInventoryAdoptionBridge or not petInventoryAdoptionBridge:IsA("BindableEvent") then
	petInventoryAdoptionBridge = Instance.new("BindableEvent")
	petInventoryAdoptionBridge.Name = PetInventoryAdoptionBridgeName
	petInventoryAdoptionBridge.Parent = ReplicatedStorage
end

petInventoryAdoptionBridge.Event:Connect(function(player, _templateName, petUid)
	if ENABLE_PET_PICKUP_TOOLS ~= true then return end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	if type(petUid) ~= "string" or petUid == "" then return end

	local petModel, state = findOwnedPetByUid(player.UserId, petUid)
	if not petModel or not state then return end
	if tostring(state.ownerUserId) ~= tostring(player.UserId) then return end
	if state.wild == true then return end

	PetMovement.StopWandering(petModel)
	local helper = petModel:FindFirstChild("PetPickupPart")
	if helper then
		pcall(function() helper:Destroy() end)
	end
	if petPickupPromptConns[petModel] then
		pcall(function() petPickupPromptConns[petModel]:Disconnect() end)
		petPickupPromptConns[petModel] = nil
	end

	petModel.Parent = ServerStorage
	state.location = "inventory"
	setPetStashedModel(player.UserId, petUid, petModel)
	PetStateManager:SendStateToOwner(petModel)
	createPetPickupTool(player, petModel, state)
	equipPetToolByUid(player, petUid)
	if saveManager then
		saveManager:ScheduleSave(player)
	end
end)

petGamepassGrantBridge.Event:Connect(function(player, gamepassName, petsToGrant)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	if type(petsToGrant) ~= "table" then return end

	for _, petName in ipairs(petsToGrant) do
		if type(petName) == "string" then
			local ok, reason = WildPetManager:GrantOwnedPetFromTemplate(player, petName)
			if not ok then
				if reason == "TemplateMissing" then
					warn(("[PetSystem] Failed to grant gamepass pet '%s' for %s (gamepass=%s, reason=%s). Add a Model named '%s' in ServerStorage.WildPetModels/ServerStorage.PetModels or ReplicatedStorage.Pets.")
						:format(petName, player.Name, tostring(gamepassName), tostring(reason), petName))
				else
					warn(("[PetSystem] Failed to grant gamepass pet '%s' for %s (gamepass=%s, reason=%s)")
						:format(petName, player.Name, tostring(gamepassName), tostring(reason)))
				end
			end
		end
	end
end)

local petSellBridge = ReplicatedStorage:FindFirstChild(PetSellBridgeName)
if not petSellBridge or not petSellBridge:IsA("BindableEvent") then
	petSellBridge = Instance.new("BindableEvent")
	petSellBridge.Name = PetSellBridgeName
	petSellBridge.Parent = ReplicatedStorage
end

petSellBridge.Event:Connect(function(player, petUid, petName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	if type(petUid) == "string" and petUid ~= "" then
		removePetToolInstances(player, petUid)
		clearPetStashedModel(player.UserId, petUid)
		local removed = WildPetManager:RemoveOwnedPetByUid(player, petUid)
		if removed then
			return
		end
	end
	if type(petName) == "string" and petName ~= "" then
		WildPetManager:RemoveOneOwnedPetByName(player, petName)
	end
end)

local petSellRequestBridge = ReplicatedStorage:FindFirstChild(PetSellRequestBridgeName)
scanAndConnectSellPrompts(petSellRequestBridge)
workspace.DescendantAdded:Connect(function(descendant)
	if not petSellRequestBridge or not petSellRequestBridge:IsA("BindableFunction") then
		petSellRequestBridge = ReplicatedStorage:FindFirstChild(PetSellRequestBridgeName)
	end
	if descendant:IsA("BasePart") and descendant.Name == "SellPart" then
		connectSellPrompt(descendant, petSellRequestBridge)
	end
end)

local petRuntimeStateBridge = ReplicatedStorage:FindFirstChild(PetRuntimeStateBridgeName)
if not petRuntimeStateBridge or not petRuntimeStateBridge:IsA("BindableFunction") then
	petRuntimeStateBridge = Instance.new("BindableFunction")
	petRuntimeStateBridge.Name = PetRuntimeStateBridgeName
	petRuntimeStateBridge.Parent = ReplicatedStorage
end

petRuntimeStateBridge.OnInvoke = function(player, petUid)
	if not player or type(petUid) ~= "string" or petUid == "" then
		return nil
	end

	local petModel, state = findOwnedPetByUid(player.UserId, petUid)
	if not petModel or not state then
		return nil
	end
	if tostring(state.ownerUserId) ~= tostring(player.UserId) then
		return nil
	end

	return {
		location = tostring(state.location or ""),
		wild = state.wild == true,
	}
end

task.spawn(function()
	while not (petSellRequestBridge and petSellRequestBridge:IsA("BindableFunction")) do
		petSellRequestBridge = ReplicatedStorage:FindFirstChild(PetSellRequestBridgeName)
		task.wait(1)
	end
	scanAndConnectSellPrompts(petSellRequestBridge)
end)

local petSellRequestBridge = ReplicatedStorage:FindFirstChild(PetSellRequestBridgeName)
scanAndConnectSellPrompts(petSellRequestBridge)
workspace.DescendantAdded:Connect(function(descendant)
	if not petSellRequestBridge or not petSellRequestBridge:IsA("BindableFunction") then
		petSellRequestBridge = ReplicatedStorage:FindFirstChild(PetSellRequestBridgeName)
	end
	if descendant:IsA("BasePart") and descendant.Name == "SellPart" then
		connectSellPrompt(descendant, petSellRequestBridge)
	end
end)
task.spawn(function()
	while not (petSellRequestBridge and petSellRequestBridge:IsA("BindableFunction")) do
		petSellRequestBridge = ReplicatedStorage:FindFirstChild(PetSellRequestBridgeName)
		task.wait(1)
	end
	scanAndConnectSellPrompts(petSellRequestBridge)
end)



-- Connect remote events
if accessoryEvent then
	accessoryEvent.OnServerEvent:Connect(function(player, action, data)
		AccessoryManager:HandleAccessoryEvent(player, action, data)
	end)
end

petCarryEvent.OnServerEvent:Connect(function(player, action, payload)
	if action == "RequestCarryState" then
		local carriedPet = carryingPetByUserId[player.UserId]
		local currentlyCarrying = carriedPet ~= nil
		local petName = currentlyCarrying and tostring(carriedPet.Name) or nil
		local canDrop = currentlyCarrying and canPlayerDropCarriedPetAtCurrentPosition(player, carriedPet) or false
		petCarryEvent:FireClient(player, "CarryState", currentlyCarrying, petName, canDrop)
		return
	end
	if action == "TryPickupPet" then
		local targetPet = payload
		if typeof(targetPet) ~= "Instance" then
			return
		end
		if ENABLE_PET_PICKUP_TOOLS then
			tryPickupOwnedPetAsTool(player, targetPet)
		else
			tryPickupOwnedPet(player, targetPet)
		end
		return
	end
	if action ~= "DropPet" then return end
	if not player then return end

	if ENABLE_PET_PICKUP_TOOLS then
		stowCarriedPetAsTool(player)
		return
	end
	dropCarriedPet(player, { blockWildDrop = true })
end)

if petStateEvent then
	petStateEvent.OnServerEvent:Connect(function(player, action)
		if action ~= "RequestOwnedPetsState" then return end
		if not player then return end

		for petModel, st in pairs(petState) do
			if petModel and petModel.Parent and st and tostring(st.ownerUserId) == tostring(player.UserId) then
				PetStateManager:SendStateToOwner(petModel)
			end
		end
	end)
end

-- Scan for existing NPCs
for _, npc in ipairs(NPCS_FOLDER:GetChildren()) do
	NPCManager:SetupNPC(npc)
end

-- Monitor new NPCs
NPCS_FOLDER.ChildAdded:Connect(function(npc)
	task.wait(0.05)
	NPCManager:SetupNPC(npc)
end)

AccessoryManager:ScanAndConnectAll()

-- Periodic scan for interactables
task.spawn(function()
	while true do
		pcall(function()
			ShowerDryerManager:ScanAndConnectAll()
			AccessoryManager:ScanAndConnectAll()
			PetGroundManager:ScanAndConnectAll()
			PetStandManager:ScanAndConnectAll()
			WildPetManager:ScanAndConnectAdoptionMats()
			ToyHappinessManager:ScanAndConnectAll()
		end)
		task.wait(6)
	end
end)

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("OwnedPetsRuntimeReady", false)
	player.CharacterAdded:Connect(function(character)
		setCharacterCollisionGroup(character, "Players")
		character.DescendantAdded:Connect(function(desc)
			if desc:IsA("BasePart") then
				pcall(function() desc.CollisionGroup = "Players" end)
			end
		end)
	end)

	task.wait(3)
	if not saveManager then
		warn("[PetSystem] saveManager nil, cannot load pets")
		return
	end
	local petData = saveManager:LoadPlayerPets(player)
	if petData and #petData > 0 then
		if not ENABLE_PET_PICKUP_TOOLS then
			for _, petInfo in ipairs(petData) do
				if type(petInfo) == "table" and petInfo.location == "inventory" then
					petInfo.location = "free"
				end
			end
		end
		WildPetManager:SpawnOwnedPetsForPlayer(player, petData)
		local data = player:FindFirstChild("Data")
		local petsFolder = data and data:FindFirstChild("Pets")
		local inventoryIdsByName = {}
		if petsFolder then
			for _, petFolder in ipairs(petsFolder:GetChildren()) do
				local petNameValue = petFolder:FindFirstChild("PetName")
				local petName = petNameValue and tostring(petNameValue.Value) or ""
				if petName ~= "" then
					inventoryIdsByName[petName] = inventoryIdsByName[petName] or {}
					table.insert(inventoryIdsByName[petName], tostring(petFolder.Name))
				end
			end
		end
		for _, petInfo in ipairs(petData) do
			if type(petInfo) == "table" then
				local petUid = tostring(petInfo.petUid or "")
				local inventoryPetId = petUid ~= "" and resolveInventoryPetIdByUid(player, petUid) or nil
				if not inventoryPetId then
					local modelName = tostring(petInfo.modelName or "")
					local idsForName = inventoryIdsByName[modelName]
					if idsForName and #idsForName > 0 then
						inventoryPetId = table.remove(idsForName, 1)
					end
				end
				if inventoryPetId then
					setInventoryRuntimeLocation(player, inventoryPetId, petInfo.location)
				end
			end
		end
		player:SetAttribute("OwnedPetsRuntimeReady", true)
		if ENABLE_PET_PICKUP_TOOLS then
			restoreInventoryPetToolsForPlayer(player)
		end
		task.defer(function()
			AccessoryManager:RestoreAccessoriesForPlayer(player.UserId)
		end)
	end
	if player:GetAttribute("OwnedPetsRuntimeReady") ~= true then
		player:SetAttribute("OwnedPetsRuntimeReady", true)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	stashedPetModelsByUserId[player.UserId] = nil
	if saveManager then
		saveManager:SavePlayerPets(player)
	else
		warn("[PetSystem] saveManager is nil, cannot save pets for", player.Name)
	end
end)

print("[PetSystem] Initialized successfully.")
