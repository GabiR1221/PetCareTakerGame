--starterplayerscripts alongisde with mainclient
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if _G.__PetEffectsClientConnected then return end

local modulesFolder = ReplicatedStorage:FindFirstChild("Modules")
local effectModuleScript = (modulesFolder and modulesFolder:FindFirstChild("EffectModule"))
	or ReplicatedStorage:FindFirstChild("EffectModule")
	or script.Parent:FindFirstChild("EffectModule")

if not effectModuleScript or not effectModuleScript:IsA("ModuleScript") then
	warn("[PetEffectsClient] Missing EffectModule. Put EffectModule in ReplicatedStorage or ReplicatedStorage.Modules for client-side effects.")
	return
end

_G.__PetEffectsClientConnected = true
local EffectModule = require(effectModuleScript)
local remote = EffectModule:GetRemote()
if not remote or not remote:IsA("RemoteEvent") then
	warn("[PetEffectsClient] Missing PetEffectEvent RemoteEvent.")
	return
end

remote.OnClientEvent:Connect(function(action, ...)
	EffectModule:HandleClientEffect(action, ...)
end)
