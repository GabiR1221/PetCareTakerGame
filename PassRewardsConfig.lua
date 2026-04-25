--!strict
-- Shared config for the Pass system (Rewards + Quests + Shop).
-- Place this ModuleScript in ReplicatedStorage.Modules.


export type CurrencyReward = {
	Id: number,
	Type: "Currency",
	Tier: "Free" | "Premium"?,
	Level: number?,
	CurrencyName: string,
	Amount: number,
	RewardText: string,
	RewardImage: string,
}

export type PetReward = {
	Id: number,
	Type: "Pet",
	Tier: "Free" | "Premium"?,
	Level: number?,
	PetName: string,
	Amount: number,
	RewardText: string,
	RewardImage: string,
}

export type RewardDefinition = CurrencyReward | PetReward

export type QuestCategory = "HourlyQuests" | "DailyQuests" | "WeeklyQuests"
export type QuestAction = "ShowerPet" | "AdoptPet"

export type QuestDefinition = {
	Id: number,
	Slot: number,
	Category: QuestCategory,
	Action: QuestAction,
	Target: number,
	QuestText: string,
	QuestReward: string,
	QuestImage: string,
	RewardType: "Currency" | "Pet",
	RewardCurrencyName: string?,
	RewardAmount: number?,
	RewardPetName: string?,
}

export type ShopItemDefinition = {
	Id: number,
	Type: "Pet" | "Currency",
	PetName: string?,
	CurrencyName: string?,
	Amount: number?,
	ItemText: string,
	ItemImage: string,
	PriceCurrency: string,
	PriceAmount: number,
	ItemPriceText: string,
}

export type PassConfig = {
	PassDataVersion: number,
	PassDataStoreName: string,
	Rewards: {RewardDefinition},
	Quests: {QuestDefinition},
	ShopItems: {ShopItemDefinition},
	ClaimedAttributeName: string,
	QuestProgressAttributeName: string,
	QuestClaimedAttributeName: string,
	PetGrantBridgeName: string,
	QuestProgressBridgeName: string,
	ClaimRemoteName: string,
	StateRemoteName: string,
	GetQuestStateRemoteName: string,
	GetShopStateRemoteName: string,
	BuyShopItemRemoteName: string,
	PremiumAccessEntryName: string,
	PremiumAccessPurchaseType: "Auto" | "GamePass" | "DeveloperProduct",
	ProgressionLevelValueName: string,
	ProgressionXpValueName: string,
	ProgressionXpPerLevel: number,
	EventCoinsValueName: string,
}

local PassRewardsConfig: PassConfig = {
	PassDataVersion = 11, -- bump this (2,3,4,...) any time you want to hard-reset all pass progress------------------------------------------------------------------
	PassDataStoreName = "PassRewardsData_v11", -- change this to reset ONLY pass data (without resetting main game data)-----------------------------------------------
	Rewards = {
		{
			Id = 1,
			Type = "Currency",
			Tier = "Free",
			Level = 1,
			CurrencyName = "Currency",
			Amount = 500,
			RewardText = "+500 Cash",
			RewardImage = "rbxassetid://18885492705",
		},
		{
			Id = 2,
			Type = "Currency",
			Tier = "Free",
			Level = 2,
			CurrencyName = "Currency2",
			Amount = 100,
			RewardText = "+100 Gems",
			RewardImage = "rbxassetid://6995306743",
		},
		{
			Id = 3,
			Type = "Pet",
			Tier = "Premium",
			Level = 3,
			PetName = "OdinDinDinDun", -- MUST match ReplicatedStorage.Pets child name exactly
			Amount = 1,
			RewardText = "Adopt Dog",
			RewardImage = "rbxassetid://0",
		},
	},
	Quests = {
		{
			Id = 1,
			Slot = 1,
			Category = "HourlyQuests",
			Action = "ShowerPet",
			Target = 2,
			QuestText = "Shower any pet 2 times",
			QuestReward = "Reward: 150 Cash",
			QuestImage = "rbxassetid://0",
			RewardType = "Currency",
			RewardCurrencyName = "EventXp",
			RewardAmount = 10,
		},
		{
			Id = 2,
			Slot = 1,
			Category = "DailyQuests",
			Action = "AdoptPet",
			Target = 2,
			QuestText = "Catch/Adopt 2 pets",
			QuestReward = "Reward: 1 Dog",
			QuestImage = "rbxassetid://0",
			RewardType = "Pet",
			RewardPetName = "OdinDinDinDun",
			RewardAmount = 1,
		},
		{
			Id = 3,
			Slot = 1,
			Category = "WeeklyQuests",
			Action = "AdoptPet",
			Target = 2,
			QuestText = "Catch/Adopt 2 pets",
			QuestReward = "Reward: 1000 Cash",
			QuestImage = "rbxassetid://0",
			RewardType = "Currency",
			RewardCurrencyName = "EventXp",
			RewardAmount = 100,
		},
		{
			Id = 4,
			Slot = 2,
			Category = "HourlyQuests",
			Action = "ShowerPet",
			Target = 1,
			QuestText = "Shower any pet 1 times",
			QuestReward = "Reward: 150 Cash",
			QuestImage = "rbxassetid://0",
			RewardType = "Currency",
			RewardCurrencyName = "EventXp",
			RewardAmount = 10,
		},
	},
	ShopItems = {
		{
			Id = 1,
			Type = "Pet",
			PetName = "OdinDinDinDun",
			ItemText = "Dog (Test)",
			ItemImage = "rbxassetid://0",
			PriceCurrency = "EventCoins",
			PriceAmount = 25,
			ItemPriceText = "25 EventCoins",
		},
		{
			Id = 2,
			Type = "Pet",
			PetName = "OdinDinDinDun",
			ItemText = "Cat (Test)",
			ItemImage = "rbxassetid://0",
			PriceCurrency = "EventCoins",
			PriceAmount = 50,
			ItemPriceText = "50 EventCoins",
		},
	},
	ClaimedAttributeName = "PassClaimedRewardsCsv",
	QuestProgressAttributeName = "PassQuestProgressJson",
	QuestClaimedAttributeName = "PassQuestClaimedCsv",
	PetGrantBridgeName = "PetInventoryAdoptionBridge",
	QuestProgressBridgeName = "PassQuestProgressBridge",
	ClaimRemoteName = "ClaimPassReward",
	StateRemoteName = "GetPassRewardsState",
	GetQuestStateRemoteName = "GetPassQuestsState",
	GetShopStateRemoteName = "GetPassShopState",
	BuyShopItemRemoteName = "BuyPassShopItem",
	PremiumAccessEntryName = "PremiumPass",
	PremiumAccessPurchaseType = "Auto",
	ProgressionLevelValueName = "PassLevel",
	ProgressionXpValueName = "EventXp",
	ProgressionXpPerLevel = 10,
	EventCoinsValueName = "EventCoins",
}

return PassRewardsConfig
