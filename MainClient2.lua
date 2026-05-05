-- MainClient2 (LocalScript)
-- Place in StarterPlayerScripts.
-- Continuation companion for MainClientScript to avoid register overflow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local function waitForHatchFunction(timeout)
	timeout = timeout or 15
	local started = os.clock()
	while os.clock() - started < timeout do
		if type(_G.HatchEgg) == "function" then
			return _G.HatchEgg
		end
		task.wait(0.2)
	end
	return nil
end

local hatchEggFn = waitForHatchFunction()
-- It's normal for this to be nil briefly due to client script load order.

local caseHatchEvent = ReplicatedStorage:FindFirstChild("CaseHatchEvent")
if not caseHatchEvent then
	caseHatchEvent = Instance.new("RemoteEvent")
	caseHatchEvent.Name = "CaseHatchEvent"
	caseHatchEvent.Parent = ReplicatedStorage
end

caseHatchEvent.OnClientEvent:Connect(function(action, eggName, itemName)
	if action ~= "PlayHatch" then return end
	if type(eggName) ~= "string" or eggName == "" then return end
	if type(itemName) ~= "string" or itemName == "" then return end
	if type(hatchEggFn) ~= "function" then
		hatchEggFn = waitForHatchFunction(30)
	end
	if type(hatchEggFn) ~= "function" then
		warn("[MainClient2] Unable to play hatch: _G.HatchEgg unavailable.")
		return
	end
	pcall(function()
		hatchEggFn(eggName, itemName, 0)
	end)
end)
