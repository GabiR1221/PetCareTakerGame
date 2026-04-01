-- clientmainRebirthTYCOONSCRIPT
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

-- Variables
local player = Players.LocalPlayer
local rebirthEvent = ReplicatedStorage:WaitForChild("TycoonRebirthEvent")
local rebirthGui = script.Parent
local rebirthButton = rebirthGui:WaitForChild("RebirthButton")
local originalButtonSize = rebirthButton.Size
local soundEvent = ReplicatedStorage:WaitForChild("TycoonSoundEvent")
local animationEvent = ReplicatedStorage:WaitForChild("TycoonObjectAnimationEvent")
local getModuleFunction = ReplicatedStorage:WaitForChild("TycoonGetObjectAnimationsFunction")
local objectAnimations = require(getModuleFunction:InvokeServer())

-- Displays the rebirth button
local function ShowRebirthButton()
	if rebirthButton.Visible == true then return end

	rebirthButton.Visible = true
	
	-- Remove the below 4 lines if you don't want the button to animate
	rebirthButton.Size = UDim2.new(0, 0, 0, 0)
	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local buttonTween = TweenService:Create(rebirthButton, tweenInfo, {Size = originalButtonSize})
	buttonTween:Play()
end

-- Fires the rebirth event on the server and hides the rebirth button
local function Rebirth()
	rebirthEvent:FireServer()
	
	-- Remove the below 6 lines if you don't want the button to animate
	rebirthButton.Size = originalButtonSize
	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	local buttonTween = TweenService:Create(rebirthButton, tweenInfo, {Size = UDim2.new(0, 0, 0, 0)})
	buttonTween:Play()
	task.wait(0.2)
	rebirthButton.Visible = false
end

-- Plays the given sound
local function PlaySound(sound)
	local clonedSound = sound:Clone()
	clonedSound.Parent = SoundService
	clonedSound:Play()
	
	task.delay(clonedSound.TimeLength, function()
		clonedSound:Destroy()
	end)
end

-- Plays the given animation on the given object
local function PlayAnimation(animationStyle, animationType, object, maxDistance)
	local parts = {}
	for _, part in ipairs(object:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	
	if #parts == 0 then
		warn("No BaseParts in object "..object.Name)
		return
	end
	
	if objectAnimations[animationStyle] then
		local character = player.Character
		if character then
			local distance = (character:GetPivot().Position - object:GetPivot().Position).Magnitude
			if distance > maxDistance then return end
		end
		
		-- Call the HandleCollisions function to make sure collisions are
		-- only enabled when the purchase animation finishes
		-- Or to disable collisions when the remove animation plays
		objectAnimations.HandleCollisions(parts, animationType)
		
		objectAnimations[animationStyle](parts, object)
	end
end

-- Updates the prompt action text for currency stealing
function UpdatePromptText(prompt : ProximityPrompt)
	if prompt.Name == "CollectPrompt" then
		local parentModel = prompt:FindFirstAncestorWhichIsA("Model")
		local parentFolder = prompt:FindFirstAncestor("Essentials") or prompt:FindFirstAncestor("PurchasedObjects")
		if not parentModel or not parentFolder then return end
		local tycoonOwnerId = parentFolder.Parent:GetAttribute("OwnerId")
		if tycoonOwnerId and tycoonOwnerId ~= player.UserId then
			if tycoonOwnerId == 0 or parentModel:GetAttribute("CanBeStolen") == false then
				prompt.ActionText = "Cannot Steal"
			else
				prompt.ActionText = "Steal Currency"
			end
		else
			prompt.ActionText = "Collect All Currency"
		end
	end
end

-- Connections
rebirthEvent.OnClientEvent:Connect(ShowRebirthButton)
rebirthButton.MouseButton1Click:Connect(Rebirth)
soundEvent.OnClientEvent:Connect(PlaySound)
animationEvent.OnClientEvent:Connect(PlayAnimation)
ProximityPromptService.PromptShown:Connect(UpdatePromptText)
ProximityPromptService.PromptTriggerEnded:Connect(UpdatePromptText)
