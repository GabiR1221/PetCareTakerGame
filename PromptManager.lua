---PromptManager
local PromptManager = {}

local PICKUP_PROMPT_MAX_DISTANCE = 6

function PromptManager:CreatePickupPromptForNPC(npcModel)
	if not npcModel or not npcModel:IsA("Model") then return nil end

	local helper = npcModel:FindFirstChild("PetPickupPart")
	if not helper then
		helper = Instance.new("Part")
		helper.Name = "PetPickupPart"
		helper.Size = Vector3.new(1,1,1)
		helper.Anchored = false
		helper.Transparency = 1
		helper.CanCollide = false
		helper.Parent = npcModel

		local rootPart = npcModel:FindFirstChild("HumanoidRootPart") or npcModel.PrimaryPart
		if rootPart then
			helper.CFrame = rootPart.CFrame * CFrame.new(0, 0, -2)
			local w = Instance.new("WeldConstraint")
			w.Part0 = helper
			w.Part1 = rootPart
			w.Parent = helper
		else
			helper.CFrame = npcModel:GetModelCFrame() or CFrame.new(0,5,0)
		end
	end

	local prompt = helper:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PetPrompt"
		prompt.ActionText = "Take Pet"
		prompt.ObjectText = "Pet"
		prompt.MaxActivationDistance = PICKUP_PROMPT_MAX_DISTANCE
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = helper
	end

	return helper, prompt
end

function PromptManager:CreatePickupPromptForContainer(containerModel, promptText)
	if not containerModel or not containerModel:IsA("Model") then return nil end

	local helper = containerModel:FindFirstChild("PetPickupPart")
	if not helper then
		helper = Instance.new("Part")
		helper.Name = "PetPickupPart"
		helper.Size = Vector3.new(1,1,1)
		helper.Anchored = true
		helper.Transparency = 1
		helper.CanCollide = false
		helper.Parent = containerModel

		local attachTo = containerModel.PrimaryPart or containerModel:FindFirstChildWhichIsA("BasePart")
		if attachTo then
			helper.CFrame = attachTo.CFrame * CFrame.new(0, 0, -2)
			local w = Instance.new("WeldConstraint")
			w.Part0 = helper
			w.Part1 = attachTo
			w.Parent = helper
		else
			helper.CFrame = containerModel:GetModelCFrame() or CFrame.new(0,5,0)
		end
	end

	local prompt = helper:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PetPrompt"
		prompt.ActionText = promptText or "Pick Up Pet"
		prompt.ObjectText = "Pet"
		prompt.MaxActivationDistance = PICKUP_PROMPT_MAX_DISTANCE
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = helper
	else
		prompt.ActionText = promptText or prompt.ActionText
	end

	return helper, prompt
end

return PromptManager
