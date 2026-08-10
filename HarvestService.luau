--Connected Discord-GitHub
--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CachedModules = require(ServerScriptService.Server.Server.CachedModules)
local Seed = require(ReplicatedStorage.Shared.Data.Seed)
local SeedShop = require(ReplicatedStorage.Shared.Data.SeedShop)
local PotShop = require(ReplicatedStorage.Shared.Data.PotShop)
local DropsData = require(ReplicatedStorage.Shared.Data.DropsData)
local Pot = require(ReplicatedStorage.Shared.Data.Pot)
local PotMutations = require(ReplicatedStorage.Shared.Data.PotMutations)
local Remotes = ReplicatedStorage.Shared.Remotes
local Services = CachedModules.Cached :: { [string]: any }
local PotServiceModule = Services.PotService

-- Fallback in case PotServiceModule.ClearMutation is unavailable at runtime.
-- Matches the format returned by PotService.CreateEmptyMutationState().
local function createEmptyPotMutationState()
	return { Active = {}, LastUpdated = 0 }
end

local serverFolder = workspace.World.PlantedSeeds.Server
local HarvestService = {}
local harvestLocks: { [string]: boolean } = {}

-- NOTE: HangingService is resolved lazily inside GiveHarvestRewards to avoid
-- nil reference when this module loads before HangingService initializes.
-- DO NOT cache Services.HangingService at module scope.

-- Constants
local HARVEST_MAX_DISTANCE = 20 -- Max distance for harvest interaction (matches client ProximityPrompt)
local HARVEST_MULTI_DISTANCE_BUFFER = 8 -- Account for server/client fruit prompt position drift
local LAST_HARVESTER_ATTRIBUTE = "LastHarvesterUserId"

local DEFAULT_POT_STATS = {
	TimeMul = 1,
	XPMul = 1,
	HarvestXPMul = 1,
	WeightMul = 1,
	InsectMul = 1,
}

-- Helper: Get time of day for time-conditional mutations
local function GetTimeOfDay(): string
	local Lighting = game:GetService("Lighting")
	local clockTime = Lighting.ClockTime
	-- Night is from 18:00 to 6:00
	if clockTime >= 18 or clockTime < 6 then
		return "Night"
	else
		return "Day"
	end
end

-- Get the current mutation name from pot data (NEW FORMAT: Mutations.Current)
local function getCurrentMutationName(potData): string?
	if not potData or not potData.Mutations then
		return nil
	end
	return potData.Mutations.Current
end

-- Check if mutation is active based on time condition
local function isMutationActiveNow(mutationName: string): boolean
	if not mutationName then
		return false
	end
	local mutData = PotMutations.Mutations and PotMutations.Mutations[mutationName]
		or PotMutations[mutationName]
	if not mutData then
		return false
	end
	if not mutData.TimeCondition then
		return true -- No time restriction
	end
	local timeNow = GetTimeOfDay()
	return mutData.TimeCondition == timeNow
end

-- Get mutation data by name
local function getMutationData(mutationName: string)
	if not mutationName then
		return nil
	end
	return PotMutations.Mutations and PotMutations.Mutations[mutationName]
		or PotMutations[mutationName]
end

-- Apply pot mutation sell value multiplier (NEW FORMAT)
local function applyPotMutationMultipliers(baseMultiplier, potData)
	local mutationName = getCurrentMutationName(potData)
	if not mutationName then
		return baseMultiplier
	end

	-- Check if mutation is active (time condition)
	if not isMutationActiveNow(mutationName) then
		return baseMultiplier
	end

	local mutData = getMutationData(mutationName)
	if not mutData then
		return baseMultiplier
	end

	-- Apply SellValueMul from new mutation format
	local sellMul = mutData.SellValueMul
	if typeof(sellMul) == "number" and sellMul > 0 then
		return baseMultiplier * sellMul
	end

	return baseMultiplier
end

-- Compute all mutation effects from pot data (NEW FORMAT)
local function computePotMutationEffects(potData)
	local result = {
		GrowthSpeedMultiplier = 1,
		HarvestXPMultiplier = 1,
		WeightMultiplier = 1,
		MaxWeightMultiplier = 1,
		SellValueMultiplier = 1,
		DropRateMultiplier = 1,
		BugChanceReduction = 0,
		BugChanceIncrease = 0,
		RareBugChanceMul = 1,
		WaterTimeReduction = 0,
		FrozenDebuffReduction = 0,
		RareSeedDropChance = 0,
		MaxSizeChance = 0,
		BugImmune = false,
		OnHarvestDestroyChance = 0,
	}

	local mutationName = getCurrentMutationName(potData)
	if not mutationName then
		return result
	end

	-- Check if mutation is active (time condition)
	if not isMutationActiveNow(mutationName) then
		return result
	end

	local mutData = getMutationData(mutationName)
	if not mutData then
		return result
	end

	-- Apply all mutation effects from new format
	if typeof(mutData.GrowthSpeedMul) == "number" then
		result.GrowthSpeedMultiplier = mutData.GrowthSpeedMul
	end
	if typeof(mutData.HarvestXPMul) == "number" then
		result.HarvestXPMultiplier = mutData.HarvestXPMul
	end
	if typeof(mutData.WeightMul) == "number" then
		result.WeightMultiplier = mutData.WeightMul
	end
	if typeof(mutData.MaxWeightMul) == "number" then
		result.MaxWeightMultiplier = mutData.MaxWeightMul
	end
	if typeof(mutData.SellValueMul) == "number" then
		result.SellValueMultiplier = mutData.SellValueMul
	end
	if typeof(mutData.DropRateMul) == "number" then
		result.DropRateMultiplier = mutData.DropRateMul
	end
	if typeof(mutData.BugChanceReduction) == "number" then
		result.BugChanceReduction = mutData.BugChanceReduction
	end
	if typeof(mutData.BugChanceIncrease) == "number" then
		result.BugChanceIncrease = mutData.BugChanceIncrease
	end
	if typeof(mutData.RareBugChanceMul) == "number" then
		result.RareBugChanceMul = mutData.RareBugChanceMul
	end
	if typeof(mutData.WaterTimeReduction) == "number" then
		result.WaterTimeReduction = mutData.WaterTimeReduction
	end
	if typeof(mutData.FrozenDebuffReduction) == "number" then
		result.FrozenDebuffReduction = mutData.FrozenDebuffReduction
	end
	if typeof(mutData.RareSeedDropChance) == "number" then
		result.RareSeedDropChance = mutData.RareSeedDropChance
	end
	if typeof(mutData.MaxSizeChance) == "number" then
		result.MaxSizeChance = mutData.MaxSizeChance
	end

	return result
end

local function resolvePotStats(potKey: string?, potData: any?)
	if not potKey or potKey == "" then
		return nil, DEFAULT_POT_STATS
	end

	local potName = if potData and typeof(potData.PotName) == "string" and potData.PotName ~= ""
		then potData.PotName
		else potKey:split(":")[1]
	return potName, Pot[potName] or DEFAULT_POT_STATS
end

local function broadcastHarvestEvent(
	player: Player,
	seedName: string,
	seedKey: string,
	potKey: string?,
	floorIndex: number?,
	calculatedWeight: number,
	fruitFolder: Folder?,
	serverConfig: Instance?,
	isMultiHarvest: boolean,
	fruitNumber: string?
)
	local questService = Services.QuestService
	if not (questService and fruitFolder and serverConfig) then
		return
	end

	local potName = nil
	if potKey and potKey ~= "" then
		local dataService = Services.DataService
		local playerData = dataService and dataService.GetPlayerData(player)
		local floorData = playerData and playerData.Floors and playerData.Floors.Index and floorIndex
			and playerData.Floors.Index[floorIndex]
		local potData = floorData and floorData.Pots and floorData.Pots[potKey]

		if potData and typeof(potData.PotName) == "string" and potData.PotName ~= "" then
			potName = potData.PotName
		else
			potName = string.split(potKey, ":")[1]
		end
	end

	local potRarity
	if potName and questService.ResolvePotRarity then
		potRarity = questService.ResolvePotRarity(potName)
	end

	local fruitSizeValue = fruitFolder:FindFirstChild("SizeScaling")
	local mutationsValue = fruitFolder:FindFirstChild("Mutations")
	local plantSizeValue = serverConfig:FindFirstChild("PlantSize")

	local mutations = mutationsValue and mutationsValue.Value or ""
	local harvestInfo = {
		WeightKg = calculatedWeight,
		FruitSize = fruitSizeValue and fruitSizeValue.Value or 1,
		PlantSize = plantSizeValue and plantSizeValue.Value or 1,
		Mutations = mutations,
		IsMutated = mutations ~= "",
		MultiHarvest = isMultiHarvest,
		FruitSlot = fruitNumber,
		SeedKey = seedKey,
		Floor = floorIndex,
	}

	questService.BroadcastEvent(player, "PlantHarvested", seedName, potName, potRarity, harvestInfo)
end

local function syncPlantFruitDataFromServerConfig(plantEntry: any, serverConfiguration: Instance)
	if not (plantEntry and typeof(plantEntry.Fruits) == "table" and serverConfiguration) then
		return
	end

	local fruitsFolder = serverConfiguration:FindFirstChild("Fruits")
	if not fruitsFolder then
		return
	end

	for _, fruitFolder in ipairs(fruitsFolder:GetChildren()) do
		if not fruitFolder:IsA("Folder") then
			continue
		end

		local fruitState = plantEntry.Fruits[tonumber(fruitFolder.Name) or fruitFolder.Name]
		if typeof(fruitState) ~= "table" then
			continue
		end

		local canHarvest = fruitFolder:FindFirstChild("CanHarvest")
		if canHarvest and typeof(canHarvest.Value) == "boolean" then
			fruitState.CanHarvest = canHarvest.Value
		end

		local lastHarvest = fruitFolder:FindFirstChild("LastHarvest")
		if lastHarvest and typeof(lastHarvest.Value) == "number" then
			fruitState.LastHarvest = lastHarvest.Value
		end

		local mutations = fruitFolder:FindFirstChild("Mutations")
		if mutations and typeof(mutations.Value) == "string" then
			fruitState.Mutations = mutations.Value
		end

		local sizeScaling = fruitFolder:FindFirstChild("SizeScaling")
		if sizeScaling and typeof(sizeScaling.Value) == "number" then
			fruitState.SizeScaling = sizeScaling.Value
		end
	end
end

-- Process harvest request (called from RemoteEvent triggered by client ProximityPrompt)
function HarvestService.ProcessHarvest(player: Player, plantKey: string, fruitNumber: string?)
	local DataService = Services.DataService

	-- SECURITY: Early type validation
	if typeof(plantKey) ~= "string" or plantKey == "" then
		return
	end
	if fruitNumber ~= nil and typeof(fruitNumber) ~= "string" then
		return
	end

	local foundPlant = serverFolder:FindFirstChild(plantKey)
	if not foundPlant then
		return
	end

	-- SECURITY: Early ownership check to prevent unauthorized access
	local ownerId = foundPlant:GetAttribute("Owner")
	if player.UserId ~= ownerId then
		return
	end

	local seedName = plantKey:split(":")[1]
	local seedData = Seed[seedName]
	if not seedData then
		return
	end

	-- Tutorial lock: only allow harvesting during the correct tutorial step.
	local TutorialGuideService = Services.TutorialGuideService
	if TutorialGuideService and TutorialGuideService.GuardAction then
		if not TutorialGuideService.GuardAction(player, "HarvestPlant", { PlantName = seedName }) then
			return
		end
	end

	local ownerPlayer = Players:GetPlayerByUserId(ownerId)
	if not ownerPlayer then
		return
	end

	local ownerData = DataService.GetPlayerData(ownerPlayer)
	if not ownerData then
		return
	end

	local floorIndex = foundPlant:GetAttribute("Floor")
	local plantData = ownerData.Floors.Index[floorIndex].Seeds[plantKey]
	local serverConfiguration = foundPlant:FindFirstChild("ServerConfiguration")

	if not plantData or not serverConfiguration then
		return
	end

	if serverConfiguration.GrowthPercentage.Value < 100 then
		return
	end

	local isMultiHarvest = seedData.MultiHarvest

	if (isMultiHarvest and fruitNumber) or (not isMultiHarvest and not fruitNumber) then
		-- Validate fruit number exists in server configuration for multi-harvest
		if isMultiHarvest then
			local fruitsFolder = serverConfiguration:FindFirstChild("Fruits")
			if not fruitsFolder or not fruitsFolder:FindFirstChild(fruitNumber) then
				return
			end
		end

		HarvestService.Harvest(
			ownerData.Floors.Index[floorIndex].Seeds,
			ownerData.Floors.Index[floorIndex].Pots,
			player,
			foundPlant,
			fruitNumber,
			isMultiHarvest,
			seedData,
			seedName,
			floorIndex
		)
	end
end

function HarvestService.Init()
	-- Setup RemoteEvent handler (kept for backward compatibility with client prompts during transition)
	-- Client triggers HarvestPrompt -> PromptClient fires this RemoteEvent -> Server processes
	Remotes.Harvest.OnServerEvent:Connect(function(player: Player, plantKey: string, fruitNumber: string)
		HarvestService.ProcessHarvest(player, plantKey, fruitNumber)
	end)
end

function HarvestService.IsWithinHarvestBounds(character: Model, part: Instance, magnitudeThreshold: number)
	if character and part and magnitudeThreshold then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local distance = (rootPart.Position - part.Position).Magnitude
			if distance <= magnitudeThreshold then
				return true
			end
		end
	end

	return false
end

function HarvestService.CalculateWeight(seedData: any, fruitSize: number, plantSize: number, weightMultiplier: number?): number
	local weightData = seedData.Weight
	if not weightData or not weightData.Average then
		return 0
	end

	local baseWeight = weightData.Average
	local calculatedWeight = baseWeight * fruitSize

	if plantSize > 1.0 then
		calculatedWeight += baseWeight * (plantSize - 1.0) * 0.5
	end

	local finalWeight = calculatedWeight * (weightMultiplier or 1)
	return math.floor(finalWeight * 100) / 100
end

function HarvestService.CalculateQualityMultiplier(mutations: string, fruitSize: number, plantSize: number, potData: any): number
	local multiplier = applyPotMutationMultipliers(1.0, potData)

	-- Apply fruit mutation bonus
	if mutations and mutations ~= "" then
		local mutationCount = #mutations:split(",")
		multiplier = multiplier + (mutationCount * 0.1)
	end

	-- Apply size bonuses
	if fruitSize > 1.0 then
		multiplier = multiplier + ((fruitSize - 1.0) * 0.2)
	end

	if plantSize > 1.0 then
		multiplier = multiplier + ((plantSize - 1.0) * 0.15)
	end

	return math.clamp(multiplier, 1.0, 10.0) -- Increased max to accommodate pot mutations
end

function HarvestService.GiveHarvestRewards(
	player: Player,
	seedData: any,
	seedName: string,
	qualityMultiplier: number,
	isMultiHarvest: boolean,
	xpMultiplier: number?,
	floorIndex: number?
): {}
	local LevelService = Services.LevelService
	local DataService = Services.DataService

	local playerData = DataService.GetPlayerData(player)
	if not playerData then
		return {}
	end

	-- ====== Get hanging item buffs (lazy reference to avoid nil at module load) ======
	local HangingService = Services.HangingService
	local hangingBuffs = { XPMultiplier = 1, MoneyMultiplier = 1 }
	if HangingService and HangingService.GetHarvestBuffMultipliers then
		hangingBuffs = HangingService.GetHarvestBuffMultipliers(player, floorIndex)
	end
	-- =============================================================================

	local baseGold = seedData.HarvestGold or 0
	local baseXP = seedData.HarvestXP or 0

	-- ====== MODIFIED: Apply hanging item buffs to gold and XP ======
	local finalGold = math.floor(baseGold * qualityMultiplier * hangingBuffs.MoneyMultiplier)
	local finalXP = math.floor(baseXP * qualityMultiplier * (xpMultiplier or 1) * hangingBuffs.XPMultiplier)
	-- ============================================================

	if isMultiHarvest and seedData.HarvestCount and seedData.HarvestCount > 0 then
		finalGold = math.floor(finalGold / seedData.HarvestCount)
		finalXP = math.floor(finalXP / seedData.HarvestCount)
	end

	local rewards = {}

	if finalGold > 0 then
		local MoneyService = Services.MoneyService
		if MoneyService and MoneyService.giveMoney then
			local ok = MoneyService.giveMoney(player, "Gold", finalGold)
			if ok then
				table.insert(rewards, { Type = "Gold", Amount = finalGold })
			end
		end
	end

	if finalXP > 0 then
		local leveledUp = LevelService.AddXP(player, finalXP)
		table.insert(rewards, { Type = "XP", Amount = finalXP, LeveledUp = leveledUp })
	end

	if #rewards > 0 then
		print(
			string.format(
				"🌾 %s harvested %s | Gold: +%d (x%.2f) | XP: +%d (x%.2f) | Quality: %.2fx",
				player.Name,
				seedName,
				finalGold,
				hangingBuffs.MoneyMultiplier,
				finalXP,
				hangingBuffs.XPMultiplier,
				qualityMultiplier
			)
		)
	end

	return rewards
end

local rarityWeight = {
	["Common"] = 1,
	["Rare"] = 2,
	["Epic"] = 3,
	["Legendary"] = 4,
	["Mythic"] = 5,
}

local function _randomDrop(potName: string, seedName: string)
	local seedRarity = SeedShop.SeedByName[seedName].Rarity
	local potRarity = PotShop.PotByName[potName].Rarity
	local timeofDay = GetTimeOfDay()
	local dropsList = DropsData.DropByName

	-- Filter eligible drops based on requirements
	local eligibleDrops = {}
	
	for dropName, dropData in pairs(dropsList) do
		local requires = dropData.Requires or {}
		local isEligible = true
		
		-- Check pot rarity requirement
		local potRequirement = requires["Pot"]
		if potRequirement and potRequirement ~= "" and typeof(potRequirement) == "string" then
			if not rarityWeight[potRarity] or not rarityWeight[potRequirement] then
				isEligible = false
			elseif rarityWeight[potRarity] < rarityWeight[potRequirement] then
				isEligible = false
			end
		end
		
		-- Check seed rarity requirement
		if isEligible then
			local seedRequirement = requires["Seed"]
			if seedRequirement and seedRequirement ~= "" and typeof(seedRequirement) == "string" then
				if not rarityWeight[seedRarity] or not rarityWeight[seedRequirement] then
					isEligible = false
				elseif rarityWeight[seedRarity] < rarityWeight[seedRequirement] then
					isEligible = false
				end
			end
		end
		
		-- Check time requirement (nếu có)
		if isEligible then
			local timeRequirement = requires["Time"]
			if timeRequirement and timeRequirement ~= "" and typeof(timeRequirement) == "string" then
				if timeRequirement ~= timeofDay then
					isEligible = false
				end
			end
		end
		
		-- If all requirements pass, add to eligible drops
		if isEligible then
			table.insert(eligibleDrops, { name = dropName, data = dropData })
		end
	end
	
	-- Roll for each eligible drop (có thể không drop gì cả nếu tất cả fail chance)
	for _, drop in ipairs(eligibleDrops) do
		if math.random() < drop.data.Chance then
			return drop.name, drop.data
		end
	end
	
	-- Không drop gì
	return nil, nil
end

function HarvestService.Harvest(
	ownerSeedData: any,
	ownerPotData: any,
	player: Player,
	foundPlant: Model,
	fruitNumber: string,
	isMultiHarvest: boolean,
	seedData: any,
	seedName: string,
	floorIndex: number,
	options: any?
)
	local InventoryService = Services.InventoryService
	local MaterialDropService = Services.MaterialDropService
	local WeatherService = Services.WeatherService
	local serverConfiguration = foundPlant.ServerConfiguration
	if not serverConfiguration then
		return
	end

	local plantKey = foundPlant.Name
	local lockKey = plantKey .. ":" .. (isMultiHarvest and tostring(fruitNumber or "0") or "main")
	if harvestLocks[lockKey] then
		return
	end
	harvestLocks[lockKey] = true

	local ok, err = pcall(function()
	local skipDistanceCheck = typeof(options) == "table" and options.SkipDistanceCheck == true
	local plantEntry = ownerSeedData and ownerSeedData[plantKey]
	if not plantEntry then
		return
	end

	local potKey = plantEntry.PotKey
	floorIndex = foundPlant:GetAttribute("Floor") or floorIndex
	local potData = potKey and ownerPotData and ownerPotData[potKey]
	local potName, potStats = resolvePotStats(potKey, potData)

	-- Get pot mutations early (used for weight/xp/value side effects)
	-- NEW FORMAT: Pass pot data directly to compute mutation effects
	local mutationEffects = computePotMutationEffects(potData)

	-- If pot is cracked, disable all base pot buffs for harvest calculations (GameDesign.md 5.6)
	local potStatus = "Normal"
	if potKey and ownerPotData and ownerPotData[potKey] then
		potStatus = ownerPotData[potKey].Status or "Normal"
	end
	if potStatus == "Cracked" then
		potStats = DEFAULT_POT_STATS
	end

	local weightMultiplier = (potStats.WeightMul or DEFAULT_POT_STATS.WeightMul) * (mutationEffects.WeightMultiplier or 1)
	local xpMultiplier = (potStats.HarvestXPMul or potStats.XPMul or DEFAULT_POT_STATS.XPMul)
		* (mutationEffects.HarvestXPMultiplier or 1)

	if isMultiHarvest then
		-- Distance check: use PrimaryPart if available, fallback to model pivot position
		local distanceTarget = foundPlant.PrimaryPart
		if not distanceTarget then
			-- Fallback: find any BasePart in the server model for distance measurement
			for _, child in foundPlant:GetDescendants() do
				if child:IsA("BasePart") then
					distanceTarget = child
					break
				end
			end
		end
		if not skipDistanceCheck and (
			not distanceTarget
			or not HarvestService.IsWithinHarvestBounds(
				player.Character,
				distanceTarget,
				HARVEST_MAX_DISTANCE + HARVEST_MULTI_DISTANCE_BUFFER
			)
		) then
			return
		end

		local fruitFolder: Folder = serverConfiguration.Fruits:FindFirstChild(fruitNumber)
		if not fruitFolder or not fruitFolder.CanHarvest.Value then
			return
		end

		if player.UserId ~= foundPlant:GetAttribute("Owner") then
			return
		end

		local calculatedKg =
			HarvestService.CalculateWeight(seedData, fruitFolder.SizeScaling.Value, serverConfiguration.PlantSize.Value, weightMultiplier)

		InventoryService.GiveFruit(player, seedName, {
			Mutations = fruitFolder.Mutations.Value,
			FruitSize = fruitFolder.SizeScaling.Value,
			OverallPlantSize = serverConfiguration.PlantSize.Value,
			WeightKg = calculatedKg,
		})

		--random drop 
		-- local dropName,dropData = randomDrop(potName,seedName)
		-- print("[Harvest Service] :",dropName,dropData)
		-- if dropName then
		-- 	InventoryService.AddItem(player,dropName,"Decor",1,1,dropData)
		-- end

		local qualityMultiplier = HarvestService.CalculateQualityMultiplier(
			fruitFolder.Mutations.Value,
			fruitFolder.SizeScaling.Value,
			serverConfiguration.PlantSize.Value,
			potData
		)

		HarvestService.GiveHarvestRewards(player, seedData, seedName, qualityMultiplier, true, xpMultiplier, floorIndex)
		broadcastHarvestEvent(
			player,
			seedName,
			plantKey,
			potKey,
			floorIndex,
			calculatedKg,
			fruitFolder,
			serverConfiguration,
			true,
			fruitNumber
		)

		-- Roll for evolution material drops
		if MaterialDropService and WeatherService then
			local dropPotName = potName or "Clay Pot"
			local currentWeather = WeatherService.ServerWeather.Name or ""
			local timeOfDay = GetTimeOfDay()
			MaterialDropService.RollMaterialDrop(player, seedName, dropPotName, timeOfDay, currentWeather, potStatus)
		end

		-- Rare seed drop (e.g., BloodmoonBlessed)
		if mutationEffects.RareSeedDropChance and mutationEffects.RareSeedDropChance > 0 then
			if math.random() <= mutationEffects.RareSeedDropChance then
				local SeedService = Services.SeedService
				local NotificationService = Services.NotificationService
				local pool = SeedShop.RestockSeeds
				if SeedService and pool and #pool > 0 then
					local choice = pool[math.random(1, #pool)]
					local rewardSeedName = choice and choice.Name
					if typeof(rewardSeedName) == "string" and rewardSeedName ~= "" then
						SeedService.GiveSeed(player, rewardSeedName, 1, false)
						InventoryService.InventoryUpdated(player, rewardSeedName)
						if NotificationService then
							NotificationService.PushToPlayer(
								player,
								`🌱 Received a rare seed: {rewardSeedName}`,
								{ color = Color3.fromRGB(160, 255, 160), duration = 4 }
							)
						end
					end
				end
			end
		end

		-- Electrified downside (5% chance): crack the pot
		if mutationEffects.OnHarvestDestroyChance and mutationEffects.OnHarvestDestroyChance > 0 and potKey then
			if math.random() <= mutationEffects.OnHarvestDestroyChance then
				local PotCrackingService = Services.PotCrackingService
				if PotCrackingService and ownerPotData and ownerPotData[potKey] then
					local statusNow = ownerPotData[potKey].Status or "Normal"
					if statusNow == "Normal" then
						PotCrackingService.CrackPot(player, potKey, floorIndex, "Electrified")
					end
				end
			end
		end

		fruitFolder.Mutations.Value = ""
		fruitFolder:SetAttribute(LAST_HARVESTER_ATTRIBUTE, player.UserId)
		fruitFolder.CanHarvest.Value = false
		fruitFolder.LastHarvest.Value = os.time()
		syncPlantFruitDataFromServerConfig(plantEntry, serverConfiguration)
		Remotes.ClientEffects:FireClient(player, "CollectSound")

		-- Decrement HarvestsRemaining for multi-harvest plants
		if plantEntry.HarvestsRemaining and plantEntry.HarvestsRemaining > 0 then
			plantEntry.HarvestsRemaining -= 1
		end

		-- Check if plant should be destroyed (no harvests remaining OR all fruits harvested this round)
		local noHarvestsRemaining = plantEntry.HarvestsRemaining ~= nil and plantEntry.HarvestsRemaining <= 0
		local allFruitsHarvested = true
		for _, otherFruitFolder in ipairs(serverConfiguration.Fruits:GetChildren()) do
			if otherFruitFolder:IsA("Folder") and otherFruitFolder.CanHarvest.Value == true then
				allFruitsHarvested = false
				break
			end
		end

		if noHarvestsRemaining or allFruitsHarvested then
			if potKey and ownerPotData[potKey] then
				ownerPotData[potKey].IsPlanted = false
				local potModel = workspace.World.PlacedPots.Server:FindFirstChild(potKey)
				if potModel then
					potModel:SetAttribute("IsPlanted", false)
				end
				if PotServiceModule and PotServiceModule.ClearMutation then
					PotServiceModule.ClearMutation(player, potKey, floorIndex)
				else
					ownerPotData[potKey].Mutations = createEmptyPotMutationState()
				end
			end
			-- Clear seed data first, then destroy plant after a short delay
			-- This prevents Replica race condition warnings
			ownerSeedData[plantKey] = nil
			task.defer(function()
				if foundPlant and foundPlant.Parent then
					foundPlant:Destroy()
				end
			end)
		end
	else
		-- Distance check (prompts are now on client, use constant)
		local singleDistanceTarget = foundPlant.PrimaryPart
		if not singleDistanceTarget then
			for _, child in foundPlant:GetDescendants() do
				if child:IsA("BasePart") then
					singleDistanceTarget = child
					break
				end
			end
		end
		if not skipDistanceCheck and (
			not HarvestService.IsWithinHarvestBounds(
				player.Character,
				singleDistanceTarget,
				HARVEST_MAX_DISTANCE
			)
		) then
			return
		end

		if player.UserId ~= foundPlant:GetAttribute("Owner") then
			return
		end

		local fruitFolder: Folder = serverConfiguration.Fruits["1"]
		if not fruitFolder then
			return
		end
		fruitFolder:SetAttribute(LAST_HARVESTER_ATTRIBUTE, player.UserId)

		local calculatedKg =
			HarvestService.CalculateWeight(seedData, fruitFolder.SizeScaling.Value, serverConfiguration.PlantSize.Value, weightMultiplier)

		InventoryService.GiveFruit(player, seedName, {
			Mutations = fruitFolder.Mutations.Value,
			FruitSize = fruitFolder.SizeScaling.Value,
			OverallPlantSize = serverConfiguration.PlantSize.Value,
			WeightKg = calculatedKg,
		})

		local qualityMultiplier = HarvestService.CalculateQualityMultiplier(
			fruitFolder.Mutations.Value,
			fruitFolder.SizeScaling.Value,
			serverConfiguration.PlantSize.Value,
			potData
		)

		HarvestService.GiveHarvestRewards(player, seedData, seedName, qualityMultiplier, false, xpMultiplier, floorIndex)
		broadcastHarvestEvent(
			player,
			seedName,
			plantKey,
			potKey,
			floorIndex,
			calculatedKg,
			fruitFolder,
			serverConfiguration,
			false,
			nil
		)

		-- Roll for evolution material drops
		if MaterialDropService and WeatherService then
			local dropPotName = potName or "Clay Pot"
			local currentWeather = WeatherService.ServerWeather.Name or ""
			local timeOfDay = GetTimeOfDay()
			MaterialDropService.RollMaterialDrop(player, seedName, dropPotName, timeOfDay, currentWeather, potStatus)
		end

		-- Rare seed drop (e.g., BloodmoonBlessed)
		if mutationEffects.RareSeedDropChance and mutationEffects.RareSeedDropChance > 0 then
			if math.random() <= mutationEffects.RareSeedDropChance then
				local SeedService = Services.SeedService
				local NotificationService = Services.NotificationService
				local pool = SeedShop.RestockSeeds
				if SeedService and pool and #pool > 0 then
					local choice = pool[math.random(1, #pool)]
					local rewardSeedName = choice and choice.Name
					if typeof(rewardSeedName) == "string" and rewardSeedName ~= "" then
						SeedService.GiveSeed(player, rewardSeedName, 1, false)
						InventoryService.InventoryUpdated(player, rewardSeedName)
						if NotificationService then
							NotificationService.PushToPlayer(
								player,
								`🌱 Received a rare seed: {rewardSeedName}`,
								{ color = Color3.fromRGB(160, 255, 160), duration = 4 }
							)
						end
					end
				end
			end
		end

		-- Electrified downside (5% chance): crack the pot
		if mutationEffects.OnHarvestDestroyChance and mutationEffects.OnHarvestDestroyChance > 0 and potKey then
			if math.random() <= mutationEffects.OnHarvestDestroyChance then
				local PotCrackingService = Services.PotCrackingService
				if PotCrackingService and ownerPotData and ownerPotData[potKey] then
					local statusNow = ownerPotData[potKey].Status or "Normal"
					if statusNow == "Normal" then
						PotCrackingService.CrackPot(player, potKey, floorIndex, "Electrified")
					end
				end
			end
		end

		if potKey and ownerPotData[potKey] then
			ownerPotData[potKey].IsPlanted = false
			local potModel = workspace.World.PlacedPots.Server:FindFirstChild(potKey)
			if potModel then
				potModel:SetAttribute("IsPlanted", false)
			end
			if PotServiceModule and PotServiceModule.ClearMutation then
				PotServiceModule.ClearMutation(player, potKey, floorIndex)
			else
				ownerPotData[potKey].Mutations = createEmptyPotMutationState()
			end
		end
		syncPlantFruitDataFromServerConfig(plantEntry, serverConfiguration)
		-- Clear seed data first, then destroy plant after a short delay
		-- This prevents Replica race condition warnings
		ownerSeedData[plantKey] = nil
		local plantToDestroy = foundPlant
		task.defer(function()
			if plantToDestroy and plantToDestroy.Parent then
				plantToDestroy:Destroy()
			end
		end)

		Remotes.ClientEffects:FireClient(player, "CollectSound")
	end
	end)

	harvestLocks[lockKey] = nil
	if not ok then
		warn("[HarvestService] Harvest error:", err)
	end
end

return HarvestService
