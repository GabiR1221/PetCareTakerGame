local dss = game:GetService("DataStoreService")
local toolsDS = dss:GetDataStore("ToolsData138")

local toolsFolder = game.ServerStorage.ToolsFolder

game.Players.PlayerAdded:Connect(function(plr)

	local toolsSaved = toolsDS:GetAsync(plr.UserId .. "-tools") or {}

	for i, toolSaved in pairs(toolsSaved) do

		if toolsFolder:FindFirstChild(toolSaved) then 

			local backpackTool = toolsFolder[toolSaved]:Clone()
			if backpackTool:IsA("Tool") and backpackTool:GetAttribute("InventoryCategory") == nil then
				backpackTool:SetAttribute("InventoryCategory", "Food")
			end
			backpackTool.Parent = plr.Backpack

			local starterTool = toolsFolder[toolSaved]:Clone()
			if starterTool:IsA("Tool") and starterTool:GetAttribute("InventoryCategory") == nil then
				starterTool:SetAttribute("InventoryCategory", "Food")
			end
			starterTool.Parent = plr.StarterGear
		end
	end

	plr.CharacterRemoving:Connect(function(char)

		char.Humanoid:UnequipTools()
	end)
end)


game.Players.PlayerRemoving:Connect(function(plr)

	local toolsOwned = {}

	local function collectTools(container)
		if not container then return end
		for _, item in pairs(container:GetChildren()) do
			if item:IsA("Tool")
				and item:GetAttribute("PetTool") ~= true
				and item:GetAttribute("SkipToolSave") ~= true
			then
				table.insert(toolsOwned, item.Name)
			end
		end
	end

	-- StarterGear mirrors tools for respawn; saving both Backpack and StarterGear
	-- causes count inflation/duplication across rejoins. Backpack is authoritative.
	collectTools(plr:FindFirstChild("Backpack"))
	local character = plr.Character
	collectTools(character)
	local inventoryStash = plr:FindFirstChild("InventoryStash")
	if inventoryStash then
		for _, tabFolder in ipairs(inventoryStash:GetChildren()) do
			collectTools(tabFolder)
		end
	end

	local success, errormsg = pcall(function()

		toolsDS:SetAsync(plr.UserId .. "-tools", toolsOwned)
	end)
	if errormsg then warn(errormsg) end
end)

