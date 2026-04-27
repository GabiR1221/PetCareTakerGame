-- InventoryCategoryServer
-- Splits player tools into two inventory tabs: Pets and Food.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local INVENTORY_FOLDER_NAME = "InventoryRemotes"
local SWITCH_REMOTE_NAME = "SwitchInventoryTab"
local TAB_CHANGED_REMOTE_NAME = "InventoryTabChanged"

local TAB_PETS = "Pets"
local TAB_FOOD = "Food"
local VALID_TABS = {
	[TAB_PETS] = true,
	[TAB_FOOD] = true,
}

local activeTabByUserId = {}
local connectionsByPlayer = {}
local watcherTokenByUserId = {}

local function ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild(INVENTORY_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = INVENTORY_FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	local switchRemote = folder:FindFirstChild(SWITCH_REMOTE_NAME)
	if not switchRemote then
		switchRemote = Instance.new("RemoteEvent")
		switchRemote.Name = SWITCH_REMOTE_NAME
		switchRemote.Parent = folder
	end

	local tabChanged = folder:FindFirstChild(TAB_CHANGED_REMOTE_NAME)
	if not tabChanged then
		tabChanged = Instance.new("RemoteEvent")
		tabChanged.Name = TAB_CHANGED_REMOTE_NAME
		tabChanged.Parent = folder
	end

	return switchRemote, tabChanged
end

local switchRemote, tabChangedRemote = ensureRemotes()

local function getToolTab(tool)
	if not tool or not tool:IsA("Tool") then
		return TAB_FOOD
	end

	local explicit = tostring(tool:GetAttribute("InventoryCategory") or "")
	if VALID_TABS[explicit] then
		return explicit
	end

	if tool:GetAttribute("PetTool") == true or tool:GetAttribute("PetUID") ~= nil then
		return TAB_PETS
	end

	return TAB_FOOD
end

local function ensureStash(player)
	local stash = player:FindFirstChild("InventoryStash")
	if not stash then
		stash = Instance.new("Folder")
		stash.Name = "InventoryStash"
		stash.Parent = player
	end

	local pets = stash:FindFirstChild(TAB_PETS) or Instance.new("Folder")
	pets.Name = TAB_PETS
	pets.Parent = stash

	local food = stash:FindFirstChild(TAB_FOOD) or Instance.new("Folder")
	food.Name = TAB_FOOD
	food.Parent = stash

	return stash
end

local function moveToolToBackpack(player, tool)
	if not tool or not tool:IsA("Tool") then return end
	if not player or not player.Parent then return end
	tool.Parent = player:WaitForChild("Backpack")
end

local function switchPlayerTab(player, tabName)
	if not player or not player.Parent then return end
	if not VALID_TABS[tabName] then return end

	activeTabByUserId[player.UserId] = tabName
	local stash = ensureStash(player)

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
			task.wait()
		end
	end

	local function stashNonTabTools(container)
		if not container then return end
		for _, tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") then
				local toolTab = getToolTab(tool)
				if toolTab ~= tabName then
					local targetFolder = stash:FindFirstChild(toolTab)
					if targetFolder then
						tool.Parent = targetFolder
					end
				end
			end
		end
	end
	stashNonTabTools(player.Backpack)
	stashNonTabTools(character)

	for _, tabFolder in ipairs(stash:GetChildren()) do
		if tabFolder:IsA("Folder") and tabFolder.Name == tabName then
			for _, tool in ipairs(tabFolder:GetChildren()) do
				moveToolToBackpack(player, tool)
			end
		end
	end

	tabChangedRemote:FireClient(player, tabName)
end

local function handlePotentialNewTool(player, tool)
	if not tool or not tool:IsA("Tool") then return end
	local activeTab = activeTabByUserId[player.UserId] or TAB_PETS
	local toolTab = getToolTab(tool)
	if toolTab ~= activeTab then
		switchPlayerTab(player, toolTab)
	end
end

local function disconnectPlayerConnections(player)
	local bag = connectionsByPlayer[player]
	if not bag then return end
	for _, conn in ipairs(bag) do
		pcall(function() conn:Disconnect() end)
	end
	connectionsByPlayer[player] = nil
end

Players.PlayerAdded:Connect(function(player)
	activeTabByUserId[player.UserId] = TAB_PETS
	ensureStash(player)
	local backpack = player:WaitForChild("Backpack")
	local watcherToken = {}
	watcherTokenByUserId[player.UserId] = watcherToken

	local bag = {}
	connectionsByPlayer[player] = bag

	table.insert(bag, player.CharacterAdded:Connect(function(character)
		table.insert(bag, character.ChildAdded:Connect(function(child)
			handlePotentialNewTool(player, child)
		end))
	end))

	table.insert(bag, backpack.ChildAdded:Connect(function(child)
		handlePotentialNewTool(player, child)
	end))

	task.defer(function()
		switchPlayerTab(player, TAB_PETS)
	end)

	task.spawn(function()
		while player.Parent and watcherTokenByUserId[player.UserId] == watcherToken do
			local activeTab = activeTabByUserId[player.UserId] or TAB_PETS
			local detectedMismatchTab = nil
			for _, container in ipairs({ player.Character, backpack }) do
				if container then
					for _, tool in ipairs(container:GetChildren()) do
						if tool:IsA("Tool") then
							local toolTab = getToolTab(tool)
							if toolTab ~= activeTab then
								detectedMismatchTab = toolTab
								break
							end
						end
					end
				end
				if detectedMismatchTab then break end
			end
			if detectedMismatchTab then
				switchPlayerTab(player, detectedMismatchTab)
			end
			task.wait(0.35)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	disconnectPlayerConnections(player)
	watcherTokenByUserId[player.UserId] = nil
	activeTabByUserId[player.UserId] = nil
end)

switchRemote.OnServerEvent:Connect(function(player, requestedTab)
	if type(requestedTab) ~= "string" then return end
	if not VALID_TABS[requestedTab] then return end
	switchPlayerTab(player, requestedTab)
end)
