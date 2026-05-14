---Replicatedstorage in Modules folder
local EffectModule = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local DEFAULT_TIMED_EFFECT_SECONDS = 1.25
local DEFAULT_CURRENCY_PARTICLE_COUNT = 12
local MAX_CURRENCY_PARTICLE_COUNT = 18
local DEFAULT_PARTICLE_BURST_COUNT = 30
local EFFECT_REMOTE_NAME = "PetEffectEvent"
local rng = Random.new()

local function getRootPart(target)
	if not target then return nil end
	if target:IsA("BasePart") then return target end
	if target:IsA("Model") then
		return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function getTargetCFrame(target)
	if not target then return CFrame.new() end
	if target:IsA("BasePart") then return target.CFrame end
	if target:IsA("Model") then return target:GetPivot() end
	return CFrame.new()
end

function EffectModule:GetEffectsFolder()
	local replicatedFolder = ReplicatedStorage:FindFirstChild("Effects")
		or ReplicatedStorage:FindFirstChild("PetEffects")
	if replicatedFolder then return replicatedFolder end
	if RunService:IsServer() then
		return ServerStorage:FindFirstChild("Effects")
			or ServerStorage:FindFirstChild("PetEffects")
	end
	return nil
end

function EffectModule:GetRemote()
	local remote = ReplicatedStorage:FindFirstChild(EFFECT_REMOTE_NAME)
	if remote and remote:IsA("RemoteEvent") then return remote end
	if not RunService:IsServer() then
		return ReplicatedStorage:WaitForChild(EFFECT_REMOTE_NAME, 10)
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = EFFECT_REMOTE_NAME
	remote.Parent = ReplicatedStorage
	return remote
end

function EffectModule:PlayTimedPartEffectForAll(effectNames, target, options)
	if not RunService:IsServer() then
		return self:PlayTimedPartEffect(effectNames, target, options)
	end
	local remote = self:GetRemote()
	if remote then
		remote:FireAllClients("TimedPart", effectNames, target, options or {})
	end
	return nil
end

function EffectModule:PlayTimedPartEffectForPlayer(player, effectNames, target, options)
	if not RunService:IsServer() then
		return self:PlayTimedPartEffect(effectNames, target, options)
	end
	local remote = self:GetRemote()
	if remote and player then
		remote:FireClient(player, "TimedPart", effectNames, target, options or {})
	end
	return nil
end

function EffectModule:PlayCurrencyCollectEffectForPlayer(player, origin, options)
	if not RunService:IsServer() then
		return self:PlayCurrencyCollectEffect(origin, player, options)
	end
	local remote = self:GetRemote()
	if remote and player then
		remote:FireClient(player, "CurrencyCollect", origin, options or {})
	end
	return nil
end

function EffectModule:HandleClientEffect(action, ...)
	if action == "TimedPart" then
		return self:PlayTimedPartEffect(...)
	elseif action == "CurrencyCollect" then
		local origin, options = ...
		local Players = game:GetService("Players")
		return self:PlayCurrencyCollectEffect(origin, Players.LocalPlayer, options)
	end
	return nil
end

function EffectModule:FindEffectTemplate(effectName)
	if type(effectName) ~= "string" or effectName == "" then return nil end
	local effectsFolder = self:GetEffectsFolder()
	if not effectsFolder then return nil end
	local direct = effectsFolder:FindFirstChild(effectName)
	if direct then return direct end
	local wanted = string.lower(effectName)
	for _, child in ipairs(effectsFolder:GetChildren()) do
		if string.lower(child.Name) == wanted then
			return child
		end
	end
	return nil
end

function EffectModule:GetFirstAvailableTemplate(effectNames)
	if type(effectNames) == "string" then
		return self:FindEffectTemplate(effectNames)
	end
	if type(effectNames) ~= "table" then return nil end
	for _, effectName in ipairs(effectNames) do
		local template = self:FindEffectTemplate(effectName)
		if template then
			return template
		end
	end
	return nil
end

function EffectModule:GetEffectDuration(effectInstance, fallback)
	local duration = tonumber(effectInstance and effectInstance:GetAttribute("Time"))
	if not duration then
		local part = effectInstance and effectInstance:IsA("BasePart") and effectInstance or effectInstance and effectInstance:FindFirstChildWhichIsA("BasePart", true)
		duration = tonumber(part and part:GetAttribute("Time"))
	end
	return math.clamp(duration or fallback or DEFAULT_TIMED_EFFECT_SECONDS, 0.05, 30)
end

function EffectModule:_prepareVisualInstance(effectInstance, options)
	options = options or {}
	local anchored = options.anchored == true or options.weld == false
	if effectInstance:IsA("BasePart") then
		effectInstance.Anchored = anchored
		effectInstance.CanCollide = false
		effectInstance.CanTouch = false
		effectInstance.CanQuery = false
	end
	for _, descendant in ipairs(effectInstance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		elseif descendant:IsA("ParticleEmitter") then
			local emitCount = tonumber(descendant:GetAttribute("EmitCount")) or DEFAULT_PARTICLE_BURST_COUNT
			descendant:Emit(math.clamp(math.floor(emitCount), 1, 250))
			descendant.Enabled = descendant:GetAttribute("ContinuousEffect") == true
		elseif descendant:IsA("Trail") or descendant:IsA("Beam") then
			descendant.Enabled = true
		end
	end
end

function EffectModule:PlayTimedPartEffect(effectNames, target, options)
	options = options or {}
	local template = self:GetFirstAvailableTemplate(effectNames)
	if not template or not target then return nil end

	local clone = template:Clone()
	clone.Name = tostring(options.name or template.Name) .. "Runtime"
	clone:SetAttribute("RuntimeEffect", true)
	local duration = self:GetEffectDuration(clone, options.duration)
	local offset = options.offset or CFrame.new()
	local targetCFrame = getTargetCFrame(target) * offset
	local rootPart = getRootPart(target)

	if clone:IsA("Model") then
		if not clone.PrimaryPart then
			local firstPart = clone:FindFirstChildWhichIsA("BasePart", true)
			if firstPart then clone.PrimaryPart = firstPart end
		end
		clone:PivotTo(targetCFrame)
	elseif clone:IsA("BasePart") then
		clone.CFrame = targetCFrame
	end

	clone.Parent = workspace
	self:_prepareVisualInstance(clone, options)

	local cloneRoot = getRootPart(clone)
	if rootPart and cloneRoot and options.weld ~= false then
		local weld = Instance.new("WeldConstraint")
		weld.Name = "RuntimeEffectWeld"
		weld.Part0 = cloneRoot
		weld.Part1 = rootPart
		weld.Parent = cloneRoot
	end

	Debris:AddItem(clone, duration)
	return clone
end

function EffectModule:FindCurrencyParticleTemplate(templateName)
	local candidates = {}
	if type(templateName) == "string" and templateName ~= "" then
		table.insert(candidates, templateName)
	end
	table.insert(candidates, "CashParticle")
	table.insert(candidates, "MoneyParticle")
	table.insert(candidates, "CurrencyParticle")
	table.insert(candidates, "CashModel")

	local roots = {
		ReplicatedStorage,
		ReplicatedStorage:FindFirstChild("Effects"),
		ReplicatedStorage:FindFirstChild("PetEffects"),
	}
	if RunService:IsServer() then
		table.insert(roots, ServerStorage)
		table.insert(roots, ServerStorage:FindFirstChild("Effects"))
		table.insert(roots, ServerStorage:FindFirstChild("PetEffects"))
	end
	for _, root in ipairs(roots) do
		if root then
			for _, name in ipairs(candidates) do
				local found = root:FindFirstChild(name)
				if found and (found:IsA("BasePart") or found:IsA("Model")) then
					return found
				end
			end
		end
	end
	return nil
end

local function prepareCurrencyVisual(instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

local function setCurrencyCFrame(instance, cframe)
	if instance:IsA("BasePart") then
		instance.CFrame = cframe
	elseif instance:IsA("Model") then
		if not instance.PrimaryPart then
			local firstPart = instance:FindFirstChildWhichIsA("BasePart", true)
			if firstPart then instance.PrimaryPart = firstPart end
		end
		instance:PivotTo(cframe)
	end
end

local function setCurrencyTransparency(instance, transparency)
	if instance:IsA("BasePart") then
		instance.Transparency = transparency
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = transparency
		end
	end
end

local function makeCurrencyParticle(parent, position, size, template)
	if template then
		local clone = template:Clone()
		clone.Name = "CurrencyParticle"
		prepareCurrencyVisual(clone)
		setCurrencyCFrame(clone, CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)))
		clone.Parent = parent
		return clone
	end

	local coin = Instance.new("Part")
	coin.Name = "CurrencyParticle"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(size * 0.28, size, size)
	coin.Color = Color3.fromRGB(255, 209, 77)
	coin.Material = Enum.Material.Neon
	coin.Anchored = true
	coin.CanCollide = false
	coin.CanTouch = false
	coin.CanQuery = false
	coin.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	coin.Parent = parent
	return coin
end

function EffectModule:PlayCurrencyCollectEffect(origin, playerOrCharacter, options)
	options = options or {}
	local originPart = getRootPart(origin)
	if not originPart then return end

	local character = nil
	if playerOrCharacter and playerOrCharacter:IsA("Player") then
		character = playerOrCharacter.Character
	elseif playerOrCharacter and playerOrCharacter:IsA("Model") then
		character = playerOrCharacter
	end
	local targetPart = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
	if not targetPart then return end

	local amount = math.clamp(math.floor(tonumber(options.count) or DEFAULT_CURRENCY_PARTICLE_COUNT), 1, MAX_CURRENCY_PARTICLE_COUNT)
	local template = self:FindCurrencyParticleTemplate(options.templateName)
	local folder = workspace:FindFirstChild("RuntimeEffects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RuntimeEffects"
		folder.Parent = workspace
	end

	local originPos = originPart.Position + Vector3.new(0, math.max(originPart.Size.Y * 0.5, 0.5), 0)
	for i = 1, amount do
		local size = rng:NextNumber(0.18, 0.32)
		local coin = makeCurrencyParticle(folder, originPos, size, template)
		local scatter = Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(1.4, 3.6), rng:NextNumber(-3, 3))
		local groundPos = originPos + scatter
		local scatterTargetCFrame = CFrame.new(groundPos) * CFrame.Angles(rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi), math.rad(90))
		local function beginCollectDelay()
			task.delay(rng:NextNumber(0.2, 0.5), function()
				if not coin or not coin.Parent or not targetPart.Parent then
					if coin then coin:Destroy() end
					return
				end
				local startCFrame = coin:IsA("BasePart") and coin.CFrame or coin:GetPivot()
				local collectDuration = rng:NextNumber(0.24, 0.36)
				local collectStartedAt = os.clock()
				local connection = nil
				connection = RunService.Heartbeat:Connect(function()
					if not coin or not coin.Parent or not targetPart.Parent then
						if connection then connection:Disconnect() end
						if coin then coin:Destroy() end
						return
					end
					local alpha = math.clamp((os.clock() - collectStartedAt) / collectDuration, 0, 1)
					local eased = alpha * alpha
					local targetCFrame = targetPart.CFrame
					setCurrencyCFrame(coin, startCFrame:Lerp(targetCFrame, eased))
					setCurrencyTransparency(coin, alpha)
					if alpha >= 1 then
						if connection then connection:Disconnect() end
						if coin then coin:Destroy() end
					end
				end)
			end)
		end

		if coin:IsA("BasePart") then
			local scatterTween = TweenService:Create(
				coin,
				TweenInfo.new(rng:NextNumber(0.28, 0.42), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{CFrame = scatterTargetCFrame}
			)
			scatterTween:Play()
			scatterTween.Completed:Connect(beginCollectDelay)
		else
			local startCFrame = coin:GetPivot()
			local scatterDuration = rng:NextNumber(0.28, 0.42)
			local scatterStartedAt = os.clock()
			local scatterConnection = nil
			scatterConnection = RunService.Heartbeat:Connect(function()
				if not coin or not coin.Parent then
					if scatterConnection then scatterConnection:Disconnect() end
					return
				end
				local alpha = math.clamp((os.clock() - scatterStartedAt) / scatterDuration, 0, 1)
				setCurrencyCFrame(coin, startCFrame:Lerp(scatterTargetCFrame, 1 - ((1 - alpha) * (1 - alpha))))
				if alpha >= 1 then
					if scatterConnection then scatterConnection:Disconnect() end
					beginCollectDelay()
				end
			end)
		end
		Debris:AddItem(coin, 2.5)
	end
end

return EffectModule
