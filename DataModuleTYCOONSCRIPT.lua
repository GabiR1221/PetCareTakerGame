--DataModuleTYCOONSCRIPT Tycoon as child of ServerMainScript
-- Services
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
-- Modules
local configModule = require("../Settings")
local tycoonModule = require("./TycoonModule")
-- Variables
local dataStore = DataStoreService:GetDataStore(configModule.DataStoreName)

local module = {}

function module:SaveLeaderstats(userId)
	if configModule.SaveLeaderstats ~= true then return end

	local playerFolder = ServerStorage.PlayerData:FindFirstChild(tostring(userId))
	if not playerFolder then return end

	-- Build a set of currency names to skip when saving leaderstats (we use simulator values)
	local currencySkip = {}
	for _, c in ipairs(configModule.Currencies) do
		currencySkip[c.Name] = true
	end

	local playerAttrs = playerFolder:GetAttributes() or {}
	local key = tostring(userId) .. tostring(configModule.LeaderstatsDataKey)

	local success, errorMessage = pcall(function()
		dataStore:UpdateAsync(key, function(old)
			old = old or {}
			for k, v in pairs(playerAttrs) do
				if not currencySkip[k] then
					old[k] = v
				end
			end
			return old
		end)
	end)


	if not success then
		warn("Failed to save leaderstats data for UserId " .. tostring(userId) .. ". Error message: " .. tostring(errorMessage))
	end
end


function module:SaveTycoon(tycoon)
	if configModule.SaveTycoon ~= true then return end
	if not tycoon.Tycoon or not tycoon.PurchasedObjects or not tycoon.RemovedObjects then return end

	local ownerId = tycoon.Tycoon:GetAttribute("OwnerId")
	if not ownerId or ownerId == 0 then return end

	-- ensure we treat folder names/keys as strings
	local ownerIdStr = tostring(ownerId)
	local ownerFolder = ServerStorage.PlayerData:FindFirstChild(ownerIdStr)
	if not ownerFolder then return end

	-- Build serializable arrays (strings) for purchased & removed
	local function toNameArray(list)
		local out = {}
		-- handle if list is a table of Instances, strings or a single dictionary-like table
		if type(list) ~= "table" then return out end
		for _, v in ipairs(list) do
			if typeof(v) == "Instance" then
				table.insert(out, v.Name)
			else
				table.insert(out, tostring(v))
			end
		end
		return out
	end

	local purchasedArray = toNameArray(tycoon.PurchasedObjects)
	local removedArray   = toNameArray(tycoon.RemovedObjects)

	local payload = { purchasedArray, removedArray }

	local key = ownerIdStr .. tostring(configModule.TycoonDataKey)

	local success, errorMessage = pcall(function()
		dataStore:UpdateAsync(key, function(old)
			-- Replace with our payload. You could also merge with `old` if you want a more tolerant behavior.
			return payload
		end)
	end)

	if not success then
		warn("Failed to save tycoon data for player UserId " .. ownerIdStr .. ". Error message: " .. tostring(errorMessage))
	else
		-- optional debug
		-- print(("Saved tycoon for %s -> purchased=%d removed=%d"):format(ownerIdStr, #purchasedArray, #removedArray))
	end
end


function module:LoadLeaderstats(player)
	if configModule.SaveLeaderstats ~= true then return end

	local playerFolder = ServerStorage.PlayerData:FindFirstChild(tostring(player.UserId))
	if not playerFolder then return end

	local currencyData
	local key = tostring(player.UserId) .. tostring(configModule.LeaderstatsDataKey)
	local success, errorMessage = pcall(function()
		currencyData = dataStore:GetAsync(key)
	end)

	if not success then
		warn("Failed to retrieve leaderstats data for player '" .. player.Name .. "' with UserId " .. player.UserId .. ". Error message: " .. tostring(errorMessage))
	end

	if not currencyData then return end

	local currencySkip = {}
	for _, c in ipairs(configModule.Currencies) do currencySkip[c.Name] = true end

	for name, value in pairs(currencyData) do
		if currencySkip[name] then continue end
		if playerFolder:GetAttribute(name) ~= nil then
			playerFolder:SetAttribute(name, value)
		end
	end

end


function module:LoadTycoon(tycoon)
	if configModule.SaveTycoon ~= true then return end
	if not tycoon.Tycoon or not tycoon.Objects or not tycoon.Buttons then return end

	local owner = Players:GetPlayerByUserId(tycoon.Tycoon:GetAttribute("OwnerId"))
	if not owner then return end

	local ownerFolder = ServerStorage.PlayerData:FindFirstChild(tostring(owner.UserId))
	if not ownerFolder then return end


	local tycoonData
	local success, errorMessage = pcall(function()
		tycoonData = dataStore:GetAsync(owner.UserId..configModule.TycoonDataKey)
	end)

	if not success then
		warn("Failed to retrieve tycoon data for player '"..owner.Name..
			"' with UserId "..owner.UserId..". Error message: "..errorMessage)
	end

	if not tycoonData then return end

	tycoon.PurchasedObjects = tycoonData[1]
	tycoon.RemovedObjects = tycoonData[2]

	for _, objectName in ipairs(tycoonData[1]) do
		local object = tycoon.Objects[objectName]
		if not object then continue end

		local success = false
		tycoon.Tycoon.PurchasedObjects.ChildAdded:Once(function(obj)
			success = true
		end)

		object.Parent = tycoon.Tycoon.PurchasedObjects
		repeat task.wait() until success == true
	end

	for _, objectName in ipairs(tycoonData[1]) do
		local object = tycoon.Objects[objectName]
		if not object then continue end
		tycoon:HandleDependencies(object, tycoon.Dependencies.Purchases, true)
	end

	for _, objectName in ipairs(tycoonData[2]) do
		local object = tycoon.Tycoon.PurchasedObjects:FindFirstChild(objectName)
		if not object then continue end
		tycoon:HandleDependencies(object, tycoon.Dependencies.Removables, true)
		object:Destroy()
	end

	local purchasedButtons = {}
	for _, button in ipairs(tycoon.Buttons) do
		if button.Instance:HasTag("KeepOnRebirth") then
			table.insert(tycoon.RebirthPersistentButtons, button)
		end

		local allObjectsPurchased = true
		if button.PurchaseObjects then
			for _, object in ipairs(button.PurchaseObjects) do
				if not table.find(tycoonData[1], object.Name) then
					allObjectsPurchased = false
					break
				end
			end
		end

		if button.RemoveObjects then
			for _, object in ipairs(button.RemoveObjects) do
				if not table.find(tycoonData[2], object.Name) then
					allObjectsPurchased = false
					break
				end
			end
		end

		if allObjectsPurchased == true then
			if button.Instance:GetAttribute("GamePassId") or button.Instance:GetAttribute("GroupId") or button.Instance:GetAttribute("DevProductId") then
				table.insert(tycoon.PurchasedSpecialButtons, button.Instance.Name)
			else
				tycoon.TotalPurchasedButtons += 1
			end

			table.insert(purchasedButtons, button)
			button:Destroy()
		elseif configModule.RebirthsEnabled and button.Instance:GetAttribute("PostRebirthText") then
			local rebirths = ownerFolder:GetAttribute(configModule.RebirthsName)
			local rebirthsRequired = button.Instance:GetAttribute(configModule.RebirthsName)
			if rebirthsRequired and rebirths >= rebirthsRequired then
				button.Instance.Name = button.Instance:GetAttribute("PostRebirthText")
			end
		end
	end

	for _, button in ipairs(purchasedButtons) do
		table.remove(tycoon.Buttons, table.find(tycoon.Buttons, button))
	end
end

return module
