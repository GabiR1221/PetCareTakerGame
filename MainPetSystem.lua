
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

-- Configuration
local SHOWER_HOLD_TIME = 3
local PICKUP_PROMPT_MAX_DISTANCE = 6
local GIVEBACK_PROMPT_MAX_DISTANCE = 6
local SHOWER_XP = 20
local DRY_XP = 12
local PETGROUND_XP_PER_SEC = 5

-- Initialize state trackers (these could be moved to their respective managers)
local carryingPetByUserId = {}
local petState = {}
local petGroundConnected = {}
local petGroundXPTasks = {}
local petGroundDirtinessTasks = {}
local petPickupPromptConns = {}
local sellPromptConns = {}
local attachDropPickupPrompt
local isInsideTycoonBounds

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



local function dropCarriedPet(player, options)
	options = options or {}
	local carriedPet = carryingPetByUserId[player.UserId]
	if not carriedPet or not carriedPet.Parent then return false end
	local state = petState[carriedPet]
	if not state then return false end
	if state.ownerUserId and tostring(state.ownerUserId) ~= tostring(player.UserId) then return false end
	if options.blockWildDrop and state.wild then return false end

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
	helper.Parent = petModel

	local pp = petModel.PrimaryPart or petModel:FindFirstChildWhichIsA("BasePart")
	if pp then
		helper.CFrame = pp.CFrame * CFrame.new(0, pp.Size.Y/2 + 0.5, 0)
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

	if petPickupPromptConns[petModel] then
		pcall(function() petPickupPromptConns[petModel]:Disconnect() end)
		petPickupPromptConns[petModel] = nil
	end

	petPickupPromptConns[petModel] = prompt.Triggered:Connect(function(requestingPlayer)
		if not requestingPlayer or not requestingPlayer.Character or not requestingPlayer.Character.PrimaryPart then return end
		if carryingPetByUserId[requestingPlayer.UserId] then return end
		if tostring(requestingPlayer.UserId) ~= tostring(ownerUserId) then return end

		local ok = pcall(function()
			PetAttachmentManager:AttachPetToPlayer(petModel, requestingPlayer, { resetFlags = false })
		end)
		if ok then
			pcall(function() helper:Destroy() end)
			if petPickupPromptConns[petModel] then
				pcall(function() petPickupPromptConns[petModel]:Disconnect() end)
				petPickupPromptConns[petModel] = nil
			end
			petState[petModel] = petState[petModel] or {}
			petState[petModel].location = "player"
		end
	end)
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
ShowerDryerManager:Initialize(petState, carryingPetByUserId, Players, PetMovement)
AccessoryManager:Initialize(petState, carryingPetByUserId, Players, accessoryEvent, ServerStorage)
PetGroundManager:Initialize(petState, carryingPetByUserId, Players, PetMovement, petGroundConnected, petGroundXPTasks, petGroundDirtinessTasks, petPickupPromptConns)

local saveManager = PetSaveManager:Initialize("PetData67", petState, carryingPetByUserId) ----------------------------------------Changingggggg
PetStandManager:Initialize(petState, carryingPetByUserId, Players, PetMovement, saveManager, Config)
WildPetManager:Initialize(petState, carryingPetByUserId, Players, PetMovement, Config, saveManager)
PetFeedingManager:Initialize(petState, Players, PetStateManager, saveManager)
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

petCarryEvent.OnServerEvent:Connect(function(player, action)
	if action == "RequestCarryState" then
		local carriedPet = carryingPetByUserId[player.UserId]
		local currentlyCarrying = carriedPet ~= nil
		local petName = currentlyCarrying and tostring(carriedPet.Name) or nil
		local canDrop = currentlyCarrying and canPlayerDropCarriedPetAtCurrentPosition(player, carriedPet) or false
		petCarryEvent:FireClient(player, "CarryState", currentlyCarrying, petName, canDrop)
		return
	end
	if action ~= "DropPet" then return end
	if not player then return end

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
		WildPetManager:SpawnOwnedPetsForPlayer(player, petData)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if saveManager then
		saveManager:SavePlayerPets(player)
	else
		warn("[PetSystem] saveManager is nil, cannot save pets for", player.Name)
	end
end)

print("[PetSystem] Initialized successfully.")
