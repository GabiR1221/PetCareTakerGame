---TycoonUtilsModule
local TycoonUtils = {}

function TycoonUtils:Initialize(config)
	self.Config = config or {}
end

function TycoonUtils:FindEssentialsInModel(model)
	if not model or not model.FindFirstChild then return nil end
	local ess = model:FindFirstChild("Essentials")
	if ess then return ess end
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name and string.lower(d.Name) == "essentials" then
			return d
		end
	end
	return nil
end

function TycoonUtils:FindDeskInEssentials(ess)
	if not ess then return nil end
	local direct = ess:FindFirstChild(self.Config.TycoonDeskName or "Desk")
	if direct and direct:IsA("BasePart") then return direct end

	local targetNameLower = string.lower(self.Config.TycoonDeskName or "desk")
	for _, desc in ipairs(ess:GetDescendants()) do
		if desc:IsA("BasePart") and string.lower(desc.Name) == targetNameLower then
			return desc
		end
	end

	for _, desc in ipairs(ess:GetDescendants()) do
		if desc:IsA("BasePart") then
			return desc
		end
	end

	return nil
end

function TycoonUtils:ResolveModelWithDeskFromInstance(inst)
	if not inst then return nil, nil end

	local ess = self:FindEssentialsInModel(inst)
	local desk = self:FindDeskInEssentials(ess)
	if desk then return inst, desk end

	for _, child in ipairs(inst:GetChildren()) do
		if child and child.FindFirstChild then
			local ess2 = self:FindEssentialsInModel(child)
			local desk2 = self:FindDeskInEssentials(ess2)
			if desk2 then return child, desk2 end
		end
	end

	for _, desc in ipairs(inst:GetDescendants()) do
		if desc and desc.FindFirstChild then
			local ess2 = self:FindEssentialsInModel(desc)
			local desk2 = self:FindDeskInEssentials(ess2)
			if desk2 then return desc, desk2 end
		end
	end

	local current = inst.Parent
	while current do
		if current.FindFirstChild then
			local essCur = current:FindFirstChild("Essentials")
			local deskCur = self:FindDeskInEssentials(essCur)
			if deskCur then return current, deskCur end

			for _, child in ipairs(current:GetChildren()) do
				if child and child.FindFirstChild then
					local essChild = self:FindEssentialsInModel(child)
					local deskChild = self:FindDeskInEssentials(essChild)
					if deskChild then return child, deskChild end
				end
			end
		end
		current = current.Parent
	end

	for _, candidate in ipairs(workspace:GetDescendants()) do
		if candidate and candidate.FindFirstChild then
			local essCand = self:FindEssentialsInModel(candidate)
			local deskCand = self:FindDeskInEssentials(essCand)
			if deskCand then
				return candidate, deskCand
			end
		end
	end

	return nil, nil
end

function TycoonUtils:FindTycoonByOwnerIdWithDesk(userId)
	if not userId then return nil, nil end

	local function checkContainer(inst)
		if not inst or not inst.FindFirstChild then return nil, nil end
		local ownerAttr = inst:GetAttribute("OwnerId")
		if ownerAttr and tostring(ownerAttr) == tostring(userId) then
			local ess = self:FindEssentialsInModel(inst)
			local desk = self:FindDeskInEssentials(ess)
			if desk then return inst, desk end
		end

		local candidateNames = {"OwnerId", "Owner", "OwnerUserId"}
		for _, nm in ipairs(candidateNames) do
			local child = inst:FindFirstChild(nm)
			if child and child.Value and tostring(child.Value) == tostring(userId) then
				local ess = self:FindEssentialsInModel(inst)
				local desk = self:FindDeskInEssentials(ess)
				if desk then return inst, desk end
			end
		end
		return nil, nil
	end

	local tycoonRoot = workspace:FindFirstChild("Tycoon")
	if tycoonRoot then
		local tycoonsFolder = tycoonRoot:FindFirstChild("Tycoons")
		if tycoonsFolder then
			for _, inst in ipairs(tycoonsFolder:GetChildren()) do
				local found, desk = checkContainer(inst)
				if found then return found, desk end
			end
		end
	end

	local globalTycoons = workspace:FindFirstChild("Tycoons")
	if globalTycoons then
		for _, inst in ipairs(globalTycoons:GetChildren()) do
			local found, desk = checkContainer(inst)
			if found then return found, desk end
		end
	end

	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst and inst.FindFirstChild then
			local ownerAttr = inst.GetAttribute and inst:GetAttribute("OwnerId")
			if ownerAttr and tostring(ownerAttr) == tostring(userId) then
				local ess = self:FindEssentialsInModel(inst)
				local desk = self:FindDeskInEssentials(ess)
				if desk then return inst, desk end
			end
			for _, nm in ipairs({"OwnerId", "Owner", "OwnerUserId"}) do
				local child = inst:FindFirstChild(nm)
				if child and child.Value and tostring(child.Value) == tostring(userId) then
					local ess = self:FindEssentialsInModel(inst)
					local desk = self:FindDeskInEssentials(ess)
					if desk then return inst, desk end
				end
			end
		end
	end

	return nil, nil
end

return TycoonUtils
