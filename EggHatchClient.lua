--// Egg Preview
local PreviewFrame = UI.PreviewFrame
local DefaultSize = PreviewFrame.Size
local CurrentTarget = PreviewFrame.CurrentTarget
PreviewFrame.Size = UDim2.new(0.2,0,0.2,0)

function FindClosestEgg(EggsAvailable)
	local CurrentClosest, ClosestDistance = nil, 100

	for _,Egg in EggsAvailable do
		local EggModel = workspace.Map.Eggs[Egg]
		local mag = (EggModel:GetPivot().Position-Player.Character.HumanoidRootPart.Position).Magnitude
		if mag <= ClosestDistance then
			CurrentClosest = EggModel
			ClosestDistance = mag
		end
	end
	return CurrentClosest
end

local IsClosing = false -- so it doesnt ruin the animation

local function getDisplayTemplate(itemName)
	local toys = ReplicatedStorage:FindFirstChild("Toys")
	if toys and toys:FindFirstChild(itemName) then
		return toys[itemName]
	end

	local pets = ReplicatedStorage:FindFirstChild("Pets")
	if pets and pets:FindFirstChild(itemName) then
		return pets[itemName]
	end

	return nil
end

local function getTemplateRarity(itemName)
	local template = getDisplayTemplate(itemName)
	local settings = template and template:FindFirstChild("Settings")
	local rarity = settings and settings:FindFirstChild("Rarity")
	return rarity and tostring(rarity.Value) or "Common"
end

local function getPrimaryPart(instance)
	if not instance then return nil end
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance:FindFirstChild("MainPart") or instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function getExtentsSize(instance)
	if not instance then return Vector3.new(2, 2, 2) end
	if instance:IsA("Model") then
		return instance:GetExtentsSize()
	end
	if instance:IsA("BasePart") then
		return instance.Size
	end
	return Vector3.new(2, 2, 2)
end

local function rotateForViewport(instance, yawDegrees)
	local primary = getPrimaryPart(instance)
	if not primary then return end
	if instance:IsA("Model") then
		instance:PivotTo(instance:GetPivot() * CFrame.Angles(0, math.rad(yawDegrees), 0))
	else
		instance.CFrame = instance.CFrame * CFrame.Angles(0, math.rad(yawDegrees), 0)
	end
end

local function pivotToCamera(instance, camera, xValue, yValue, zValue, yawDegrees, rollDegrees)
	if not instance or not camera then return end
	local offset = CFrame.new(xValue, yValue, zValue)
	local rotation = CFrame.Angles(math.rad(0), math.rad(yawDegrees or 0), math.rad(rollDegrees or 0))
	if instance:IsA("Model") then
		instance:PivotTo(camera:GetRenderCFrame() * offset * rotation)
	else
		local primary = getPrimaryPart(instance)
		if primary then
			primary.CFrame = camera:GetRenderCFrame() * offset * rotation
		end
	end
end


function FindEgg()
	if not Player.Character:FindFirstChild("HumanoidRootPart") or not Player.Character:FindFirstChild("Humanoid") or Player.Character.Humanoid.Health == 0 then return end

	local Camera = workspace.CurrentCamera
	local EggsAvailable = {}
	local CameraRatio = ((Camera.CFrame.Position - Camera.Focus.Position).Magnitude)/11

	for _,Egg in workspace.Map.Eggs:GetChildren() do
		if Egg == nil then continue end
		if not Egg:FindFirstChild("EggModel") then warn(Egg.Name.." does not have an EggModel") end

		local mag = (Egg:GetPivot().Position-Player.Character.HumanoidRootPart.Position).Magnitude
		if mag <= 12 then
			EggsAvailable[#EggsAvailable + 1] = Egg.Name
		end
	end

	local SetVisibility = #EggsAvailable >= 1 -- if its 0 then its already false

	if SetVisibility then -- a egg(s) is in distance
		local Egg = #EggsAvailable > 1 and FindClosestEgg(EggsAvailable) or workspace.Map.Eggs[EggsAvailable[1]]
		local WSP = workspace.CurrentCamera:WorldToScreenPoint(Egg:GetPivot().Position)
		PreviewFrame.Position = UDim2.new(0,WSP.X,0,WSP.Y)
		CurrentTarget.Value = Egg.Name
	else
		CurrentTarget.Value = "None"
	end

	if Player.NonSaveValues.IsOpeningEgg.Value then
		SetVisibility = false -- if you are opening an egg itll auto close the previewframe
	end

	--// Make the previewframe visible
	if SetVisibility and not PreviewFrame.Visible then
		PreviewFrame.Visible = true
		Utilities.Tween.Tween(PreviewFrame, {Speed = 0.15}, {Size = UDim2.new(DefaultSize.X.Scale/CameraRatio, DefaultSize.X.Offset, DefaultSize.Y.Scale/CameraRatio, DefaultSize.Y.Offset)})	
	elseif not SetVisibility and PreviewFrame.Visible and not IsClosing then -- set to invisible, while is visible & isnt closing
		IsClosing = true
		Utilities.Tween.Tween(PreviewFrame, {Speed = 0.15}, {Size = UDim2.new(0.2,0,0.2,0)})	
		task.wait(0.15)
		PreviewFrame.Visible = false
		IsClosing = false
	end
end

function UpdatePreviewFrame()
	if CurrentTarget.Value ~= "None" then
		local Egg = CurrentTarget.Value
		PreviewFrame.EggInfo.EggName.Text = Egg

		if not ReplicatedStorage.Eggs:FindFirstChild(Egg) then print(Egg.." does not have settings in ReplicatedStorage.Eggs!") return end

		local EggInfo = ReplicatedStorage.Eggs[Egg]

		local IsRobuxEgg = EggInfo:FindFirstChild("ProductId")
		if IsRobuxEgg then
			PreviewFrame.EggInfo.Price.Text = "Costs \u{E002}"..Utilities.Short.en(EggInfo.Cost.Value)
		else
			PreviewFrame.EggInfo.Price.Text = "Costs "..Utilities.Short.en(EggInfo.Cost.Value)
		end

		PreviewFrame.Buttons.Triple.Visible = not IsRobuxEgg
		PreviewFrame.Buttons.Auto.Visible = not IsRobuxEgg

		--// This part gets the item chances
		local Pets, TotalWeight = {}, 0

		for _, Pet in EggInfo.Pets:GetChildren() do
			table.insert(Pets, {Pet.Name, Pet.Value})
		end

		table.sort(Pets, function(a,b)
			return a[2] > b[2]
		end)

		local BaseChance = Pets[1][2] -- this is the most common pet

		local LuckMultiplier = Multipliers.GetLuckMultiplier(Player)

		for _,v in Pets do
			local Chance = math.min(v[2] * LuckMultiplier, BaseChance) -- so if the easiest pet is 70%, all pets will go towards 70% 
			TotalWeight += Chance
			v[2] = Chance
		end

		for i = 1,9 do
			local PetInfo = Pets[i]
			local PetSlot = PreviewFrame.PetChances.List["Pet"..i]
			PetSlot.Visible = PetInfo ~= nil

			if PetInfo == nil then continue end

			PetSlot.Rarity.Text = getTemplateRarity(PetInfo[1])
			PetSlot.Percentage.Text = Utilities.Short.en(100/TotalWeight * PetInfo[2]).."%"
			PetSlot.PetName.Value = PetInfo[1]

			local displayTemplate = getDisplayTemplate(PetInfo[1])
			if not displayTemplate then
				PetSlot.Visible = false
				continue
			end

			local PetModel = displayTemplate:Clone()
			PetModel.Parent = PetSlot.Pet

			local mainPart = getPrimaryPart(PetModel)
			if not mainPart then
				PetSlot.Visible = false
				PetModel:Destroy()
				continue
			end

			local Pos = mainPart.Position
			local Camera = Instance.new("Camera")
			PetSlot.Pet.CurrentCamera = Camera
			rotateForViewport(PetModel, 180)
			Camera.CFrame = CFrame.new(Vector3.new(Pos.X + getExtentsSize(PetModel).X * 1.5, Pos.Y, Pos.Z + 1), Pos)
		end
	end
end

CurrentTarget.Changed:Connect(UpdatePreviewFrame)

--// Egg Hatching and VIEWPORT
local IsAutoOpening = false

function HatchEgg(Egg: string, Result: string, Offset:number)
	local OpeningTime = 3

	local NewViewport = script.EggViewport:Clone()
	NewViewport.Parent = UI.OpenEgg

	Player.CameraMinZoomDistance = 15
	Frames.Visible = false
	UI[GameSettings.ButtonSide.Value].Buttons.Visible = false

	local Clone = workspace.Map.Eggs[Egg].EggModel:Clone()
	Clone:ScaleTo(0.5)
	Clone.Parent = workspace

	local Rot, X, Y, Z = Instance.new("NumberValue"), Instance.new("NumberValue"), Instance.new("NumberValue"), Instance.new("NumberValue")
	Rot.Value = 30 Z.Value = -4 X.Value = 10

	local Camera = workspace.CurrentCamera
	local PL = Instance.new("PointLight")
	PL.Shadows = false PL.Range = 4 PL.Brightness *= 1.5
	PL.Parent = Clone.Egg

	Clone:PivotTo(Camera:GetRenderCFrame()*CFrame.new(X,Y,Z))
	local CameraConnection1 = RunService.Heartbeat:Connect(function()
		local X, Y, Z = X.Value, Y.Value, Z.Value
		Clone:PivotTo(Camera:GetRenderCFrame()*CFrame.new(X,Y,Z)*CFrame.Angles(0,0,math.rad(Rot.Value)))
	end)

	local CameraConnection2 = Camera:GetPropertyChangedSignal("CFrame"):Connect(function()
		local X, Y, Z = X.Value, Y.Value, Z.Value
		Clone:PivotTo(Camera:GetRenderCFrame()*CFrame.new(X,Y,Z)*CFrame.Angles(0,0,math.rad(Rot.Value)))
	end)

	local TweenIn = TweenService:Create(X, TweenInfo.new(OpeningTime*0.2, Enum.EasingStyle.Back), {Value = Offset})
	TweenIn:Play()

	local RotTweenIn = TweenService:Create(Rot, TweenInfo.new(OpeningTime*0.2, Enum.EasingStyle.Back), {Value = 0})
	RotTweenIn:Play()

	-- add an audio for the egg flying in
	TweenIn.Completed:Wait()

	local Eggdelay = 0.075
	for i = 1,(OpeningTime * 1.5) + 1 do
		local Tween = TweenService:Create(Rot, TweenInfo.new(Eggdelay, Enum.EasingStyle.Back), {Value = -6})
		-- add an audio for rotating here
		Tween:Play()
		Tween.Completed:Wait()

		Eggdelay -= .005
	end

	CameraConnection1:Disconnect()
	CameraConnection2:Disconnect()	
	Clone:Destroy()	

	-- Now we're going to show the hatched item

	local hatchedTemplate = getDisplayTemplate(Result)
	if not hatchedTemplate then
		warn(("[EggHatchClient] Missing toy/pet template for '%s'"):format(tostring(Result)))
		NewViewport:Destroy()
		Player.CameraMinZoomDistance = 0.5
		UI[GameSettings.ButtonSide.Value].Buttons.Visible = true
		Frames.Visible = true
		return
	end

	local PetModel = hatchedTemplate:Clone()
	if PetModel:IsA("Model") then
		PetModel:ScaleTo(0.6)
	end
	PetModel.Parent = workspace
	local petMainPart = getPrimaryPart(PetModel)
	if not petMainPart then
		warn(("[EggHatchClient] Hatched toy '%s' has no BasePart/MainPart"):format(tostring(Result)))
		PetModel:Destroy()
		NewViewport:Destroy()
		Player.CameraMinZoomDistance = 0.5
		UI[GameSettings.ButtonSide.Value].Buttons.Visible = true
		Frames.Visible = true
		return
	end

	local autoDeleteValue = Data.AutoDelete:FindFirstChild(Result)
	NewViewport.Deleted.Visible = autoDeleteValue and autoDeleteValue.Value or false
	NewViewport.PetName.Text = Result
	NewViewport.PetName.Visible = true
	NewViewport.PetRarity.Text = getTemplateRarity(Result)
	NewViewport.PetRarity.Visible = true

	local PL = Instance.new("PointLight")
	PL.Shadows = false PL.Range = 4 PL.Brightness *= 2
	PL.Parent = petMainPart

	X.Value = Offset Y.Value = 0 Z.Value = -4 Rot.Value = 175
	local CameraConnection1 = RunService.Heartbeat:Connect(function()
		local X, Y, Z = X.Value, Y.Value, Z.Value
		pivotToCamera(PetModel, Camera, X, Y, Z, Rot.Value, 0)
	end)

	local CameraConnection2 = Camera:GetPropertyChangedSignal("CFrame"):Connect(function()
		local X, Y, Z = X.Value, Y.Value, Z.Value
		pivotToCamera(PetModel, Camera, X, Y, Z, Rot.Value, 0)
	end)

	task.wait(OpeningTime*0.25)

	NewViewport:TweenPosition(UDim2.new(NewViewport.Position.X.Scale, 0, NewViewport.Position.Y.Scale + 10, 0), Enum.EasingDirection.InOut, Enum.EasingStyle.Quad, OpeningTime * 0.1)
	TweenService:Create(Y, TweenInfo.new(OpeningTime*0.15, Enum.EasingStyle.Back), {Value = -5}):Play()
	NewViewport.Deleted.Visible = false
	NewViewport.PetName.Visible = false
	NewViewport.PetRarity.Visible = false
	task.wait(OpeningTime * 0.15)

	CameraConnection1:Disconnect()
	CameraConnection2:Disconnect()
	X:Destroy() Y:Destroy() Z:Destroy() Rot:Destroy()

	PetModel:Destroy()
	NewViewport:Destroy()

	Player.CameraMinZoomDistance = 0.5
	UI[GameSettings.ButtonSide.Value].Buttons.Visible = true
	Frames.Visible = true	
end

Remotes.Egg.OnClientInvoke = HatchEgg

function SingleEgg()
	local Egg = CurrentTarget.Value

	local EggInfo = ReplicatedStorage.Eggs[Egg]

	if not EggInfo:FindFirstChild("ProductId") then
		local Result = Remotes.Egg:InvokeServer(Egg, 1)

		if Result ~= nil then
			HatchEgg(Egg, Result[1], 0)
		end
	else
		MarketPlaceService:PromptProductPurchase(Player, EggInfo.ProductId.Value)
	end
end

function TripleEgg()
	local Egg = CurrentTarget.Value

	local Result = Remotes.Egg:InvokeServer(Egg, 3)

	if Result ~= nil then
		for i = 1,#Result do
			coroutine.wrap(function()
				local Position = (i - 2) * 3
				HatchEgg(Egg, Result[i], Position)
			end)()
		end
	end
end

local function ChooseEggAmount(Egg)
	local EggInfo = ReplicatedStorage.Eggs[Egg]

	local EggAmount = 1

	if ReplicatedStorage.Gamepasses:FindFirstChild("TripleEgg") and not Player.Data.Gamepasses.TripleEgg.Value then 
		return EggAmount
	end -- triple egg is a gamepass that the player doesn't own, so open 1 egg

	if PlayerData.Currency.Value >= EggInfo.Cost.Value * 3 then
		EggAmount = 3
	end

	return EggAmount
end

function AutoEgg()
	if IsAutoOpening then return end

	if ReplicatedStorage.Gamepasses:FindFirstChild("AutoEgg") and not Player.Data.Gamepasses.AutoEgg.Value then 
		MarketPlaceService:PromptGamePassPurchase(ReplicatedStorage.Gamepasses.AutoEgg.Value)
		return
	end

	local Egg = CurrentTarget.Value	
	IsAutoOpening = true

	while true do
		if Player.NonSaveValues.IsOpeningEgg.Value then task.wait(0.1) continue end -- player is already opening an egg

		if CurrentTarget.Value == "None" or CurrentTarget.Value ~= Egg then
			IsAutoOpening = false
			break
		end

		local Result = Remotes.Egg:InvokeServer(Egg, ChooseEggAmount(Egg))

		if Result == nil then
			IsAutoOpening = false
			break
		end

		if #Result > 1 then
			for i = 1,#Result do
				coroutine.wrap(function()
					local Position = (i - 2) * 3
					HatchEgg(Egg, Result[i], Position)
				end)()
			end
		else
			HatchEgg(Egg, Result[1], 0)
		end

		task.wait(0.1)
	end
end

PreviewFrame.Buttons.Single.Click.MouseButton1Click:Connect(SingleEgg)
PreviewFrame.Buttons.Triple.Click.MouseButton1Click:Connect(TripleEgg)
PreviewFrame.Buttons.Auto.Click.MouseButton1Click:Connect(AutoEgg)

UserInputService.InputBegan:Connect(function(Input)
	if UserInputService:GetFocusedTextBox() ~= nil then return end

	if Input.KeyCode == Enum.KeyCode.E then SingleEgg() end
	if Input.KeyCode == Enum.KeyCode.R then TripleEgg() end
	if Input.KeyCode == Enum.KeyCode.T then AutoEgg() end
end)
