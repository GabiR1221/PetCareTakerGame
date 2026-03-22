
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
-- Services
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

-- External dependencies
local Config = require(ServerScriptService:WaitForChild("NPCConfig"))
local PetMovement = require(ServerScriptService:WaitForChild("PetMovement"))

-- Remote Events
local accessoryEvent = ReplicatedStorage:FindFirstChild("PetAccessoryEvent")
local petStateEvent = ReplicatedStorage:FindFirstChild("PetStateEvent")

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

	
	local function ensurePlayerPetCollisionGroups()
			pcall(function() PhysicsService:RegisterCollisionGroup("Players") end)
			pcall(function() PhysicsService:RegisterCollisionGroup("Pets") end)
			pcall(function() PhysicsService:CollisionGroupSetCollidable("Players", "Pets", false) end)
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
	PetAnimationManager:Initialize(petState)
	NPCManager:Initialize(NPCS_FOLDER, petState, carryingPetByUserId, Players, Config)
	ShowerDryerManager:Initialize(petState, carryingPetByUserId, Players, PetMovement)
	AccessoryManager:Initialize(petState, carryingPetByUserId, Players, accessoryEvent, ServerStorage)
	PetGroundManager:Initialize(petState, carryingPetByUserId, Players, PetMovement, petGroundConnected, petGroundXPTasks, petGroundDirtinessTasks, petPickupPromptConns)

	local saveManager = PetSaveManager:Initialize("PetData", petState, carryingPetByUserId)
	WildPetManager:Initialize(petState, carryingPetByUserId, Players, PetMovement, Config, saveManager)
    PetFeedingManager:Initialize(petState, Players, PetStateManager, saveManager)

	-- Connect remote events
	if accessoryEvent then
	accessoryEvent.OnServerEvent:Connect(function(player, action, data)
		AccessoryManager:HandleAccessoryEvent(player, action, data)
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
				AccessoryManager:ScanAndConnectAll()  -- Make sure this is here
				PetGroundManager:ScanAndConnectAll()
				WildPetManager:ScanAndConnectAdoptionMats()
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
