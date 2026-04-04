--// Gem Shop
local Gemshop = ReplicatedStorage.GemShop
local Defaultwalkspeed = Player.Character.Humanoid.WalkSpeed

local BANK_OPEN_POSITION = UDim2.new(0.359, 0, 0.414, 0)
local PETS_WHILE_BANK_OPEN_POSITION = UDim2.new(0.095, 0, 0.414, 0)

local openedPetFrameFromBank = false
local defaultPetsPosition = Frames.Pets.Position

local function showPetsNextToBank()
	if not Frames.Pets.Visible then
		openedPetFrameFromBank = true
	end

	-- IMPORTANT: direct control, do NOT use ButtonHandler.OnClick for Pets here
	Frames.Pets.Position = PETS_WHILE_BANK_OPEN_POSITION
	Frames.Pets.Visible = true
end

local function hideBankOpenedPets()
	if not openedPetFrameFromBank then return end
	openedPetFrameFromBank = false

	Frames.Pets.Visible = false
	Frames.Pets.Position = defaultPetsPosition
end

Frames.Bank:GetPropertyChangedSignal("Visible"):Connect(function()
	if Frames.Bank.Visible then
		showPetsNextToBank()
	else
		hideBankOpenedPets()
	end
end)

local function GemRing()
	while task.wait(0.1) do
		if (Player.Character.HumanoidRootPart.Position - workspace.Map.Rings.GemShop.MainPart.Position).Magnitude < 10 then
			if not Frames.GemShop.Visible then
				Utilities.ButtonHandler.OnClick(Frames.GemShop, UDim2.new(0.359,0,0.414,0))
			end
		end

		if Player.Character then
			local Walkspeed = Defaultwalkspeed + Gemshop["1"].Reward.DefaultReward.Value + Gemshop["1"].Reward.IncreasePer.Value * (PlayerData.GemUpgrade1.Value+1)
			Player.Character.Humanoid.WalkSpeed = Walkspeed
		end
	end
end

local function BankRing()
	local wasInRange = false
	while task.wait(0.1) do
		local character = Player.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		local bankPart = workspace.Map.Rings.Bank.MainPart
		local inRange = humanoidRootPart and (humanoidRootPart.Position - bankPart.Position).Magnitude < 10

		if inRange and not wasInRange then
			if not Frames.Bank.Visible then
				Utilities.ButtonHandler.OnClick(Frames.Bank, BANK_OPEN_POSITION)
			else
				showPetsNextToBank()
			end
		end

		wasInRange = inRange and true or false
	end
end

coroutine.wrap(GemRing)()
coroutine.wrap(BankRing)()
