---Serverstorage-PetSystem(folder)(alongside mainpetsystem)
local LuckyBlockConfig = {}

LuckyBlockConfig.Blocks = {
	
	["LuckyBlock1"] = {
		drops = {
			{ petName = "OdinDinDinDun", weight = 60 },
			{ petName = "Golden OdinDinDinDun", weight = 30 },
			{ petName = "Mythic Gangster Footera", weight = 10 },
		},
	},
	
}

function LuckyBlockConfig:GetBlockConfig(blockName)
	return self.Blocks[tostring(blockName or "")]
end

return LuckyBlockConfig
