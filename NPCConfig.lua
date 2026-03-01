-- NPCConfig (ModuleScript)
-- Place in ServerScriptService or ReplicatedStorage
local Config = {}

-- spawn timing (seconds)
Config.MinSpawnDelay = 4
Config.MaxSpawnDelay = 12

-- how many NPCs we allow in the world at once
Config.MaxActiveNPCs = 2

-- template stored in ServerStorage (Model with Humanoid + HumanoidRootPart)
Config.NPCTemplateName = "NPCTemplate"

-- where to parent spawned NPCs
Config.SpawnParent = workspace -- default parent; script will create workspace.NPCs folder automatically

-- path/walk configuration (names expected in workspace)
Config.PathFolderName = "NPCPath"       -- workspace.NPCPath
Config.WaypointsFolderName = "Waypoints" -- workspace.NPCPath.Waypoints
Config.SpawnFolderName = "Spawns"       -- workspace.NPCPath.Spawns

-- tycoon/target expectations
Config.TycoonDeskName = "Desk"          -- tycoon.Essentials.Desk

-- NPC behavior
Config.NPCLifetimeAfterArrival = 8      -- seconds NPC waits at desk before leaving / being cleaned up
Config.NPCTimeoutPerWaypoint = 8       -- seconds to attempt reaching each waypoint before invoking pathfinding fallback
Config.NPCWalkSpeed = 12               -- humanoid walk speed

-- tolerance distance: consider "arrived" if within this many studs of target
Config.ArrivalTolerance = 4

-- If true, we attempt to follow the path defined by NPCPath.Waypoints. If false, we pathfind straight to desk.
Config.FollowWaypoints = true

return Config
