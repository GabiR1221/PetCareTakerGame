--!strict
-- Shared config for session-only Playtime rewards.
-- Place in ReplicatedStorage.Modules.

export type CurrencyPlaytimeReward = {
	Id: number,
	Type: "Currency",
	RequiredPlaytimeSeconds: number,
	CurrencyName: string,
	Amount: number,
	RewardText: string,
	RewardImage: string,
}

export type PetPlaytimeReward = {
	Id: number,
	Type: "Pet",
	RequiredPlaytimeSeconds: number,
	PetName: string,
	Amount: number,
	RewardText: string,
	RewardImage: string,
}

export type PlaytimeRewardDefinition = CurrencyPlaytimeReward | PetPlaytimeReward

export type PlaytimeRewardsConfigType = {
	Rewards: {PlaytimeRewardDefinition},
	GetStateRemoteName: string,
	ClaimRemoteName: string,
	PetGrantBridgeName: string,
}

local PlaytimeRewardsConfig: PlaytimeRewardsConfigType = {
	Rewards = {
		{
			Id = 1,
			Type = "Currency",
			RequiredPlaytimeSeconds = 30,
			CurrencyName = "Currency",
			Amount = 250,
			RewardText = "+250 Cash",
			RewardImage = "rbxassetid://18885492705",
		},
		{
			Id = 2,
			Type = "Pet",
			RequiredPlaytimeSeconds = 50,
			PetName = "OdinDinDinDun", -- MUST match ReplicatedStorage.Pets child name exactly
			Amount = 1,
			RewardText = "Adopt Dog",
			RewardImage = "rbxassetid://0",
		},
		{
			Id = 3,
			Type = "Currency",
			RequiredPlaytimeSeconds = 60,
			CurrencyName = "Currency2",
			Amount = 50,
			RewardText = "+50 Gems",
			RewardImage = "rbxassetid://6995306743",
		},
	},
	GetStateRemoteName = "GetPlaytimeRewardsState",
	ClaimRemoteName = "ClaimPlaytimeReward",
	PetGrantBridgeName = "PetInventoryAdoptionBridge",
}

return PlaytimeRewardsConfig
