local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Pot = require(ReplicatedStorage.Shared.Data.Pot)
local PotMutations = require(ReplicatedStorage.Shared.Data.PotMutations)
local Seed = require(ReplicatedStorage.Shared.Data.Seed)
local PlantModelResolver = require(ReplicatedStorage.Shared.Modules.PlantModelResolver)
local CachedModules = require(ServerScriptService.Server.Server.CachedModules)
local Services = CachedModules.Cached :: { [string]: any }

local function getWeatherService()
	return Services.WeatherService
end

local function getPotService()
	return Services.PotService
end

local function getWaterService()
	return Services.WaterService
end

local function getTutorialGuideService()
	return Services.TutorialGuideService
end

local function getPlotLikeService()
	return Services.PlotLikeService
end

-- Cache for tracking tutorial plant states to avoid spamming updates
local _tutorialPlantStateCache = {} :: { [number]: { NeedsWater: boolean?, ReadyToHarvest: boolean? } }

-- Store connections for seed server models to clean up on removal
local _seedConnections = {} :: { [string]: { RBXScriptConnection } }
local _seedModelMissingWarnings = {} :: { [string]: boolean }
local _seedModelAliasWarnings = {} :: { [string]: boolean }

-- Persistent respawn teleport connections (one per player, alive for entire session)
local _playerRespawnConns = {} :: { [Player]: RBXScriptConnection }

local function warnMissingSeedModelOnce(seedName: string, reason: string)
	local warningKey = `{seedName}:{reason}`
	if _seedModelMissingWarnings[warningKey] == true then
		return
	end
	_seedModelMissingWarnings[warningKey] = true
	warn(string.format("[PlotService] Missing seed model setup for '%s': %s", seedName, reason))
end

local function warnSeedModelAliasOnce(seedName: string, resolvedModelName: string)
	if _seedModelAliasWarnings[seedName] == true then
		return
	end
	_seedModelAliasWarnings[seedName] = true
	warn(string.format("[PlotService] Using seed model alias '%s' -> '%s'.", seedName, resolvedModelName))
end

local function cleanupSeedConnections(seedConnectionKey: string)
	local connections = _seedConnections[seedConnectionKey]
	if connections then
		for _, conn in connections do
			conn:Disconnect()
		end
		_seedConnections[seedConnectionKey] = nil
	end
end

-- Function to reset tutorial plant state cache for a player
local function resetTutorialPlantStateCache(userId: number, state: string?)
	if not _tutorialPlantStateCache[userId] then
		return
	end
	
	if state then
		_tutorialPlantStateCache[userId][state] = nil
	else
		_tutorialPlantStateCache[userId] = nil
	end
end

local Assets = ReplicatedStorage.Assets
local Remotes = ReplicatedStorage.Shared.Remotes

local PlotService = {}

local function getFloorTemplateFolder(): Instance?
	local mapFix = workspace:FindFirstChild("Map Fix")
	local allFloor = mapFix and mapFix:FindFirstChild("AllFloor")
	local primary = allFloor and (allFloor:FindFirstChild("FloorsAuto") or allFloor:FindFirstChild("Floors"))
	-- Verify the folder actually has floor models; fall back to ReplicatedStorage backup if empty
	if primary and primary:FindFirstChildWhichIsA("Model") then
		return primary
	end
	return ReplicatedStorage:FindFirstChild("FloorsAutoBackup") or primary or nil
end

local function getFloorTemplate(floorNumber: number): Model?
	local floorName = "Floor" .. floorNumber
	local floorFolder = getFloorTemplateFolder()
	local template = floorFolder and floorFolder:FindFirstChild(floorName)
	if template and template:IsA("Model") then
		return template
	end

	local models = Assets:FindFirstChild("Models")
	return models and models:FindFirstChild(floorName) or nil
end

local function getFloorHitbox(floorModel: Instance?): BasePart?
	if not floorModel then
		return nil
	end

	for _, descendant in floorModel:GetDescendants() do
		if descendant:IsA("BasePart")
			and descendant.Name == "Hitbox"
			and descendant:GetAttribute("IsFloorHitbox") == true then
			return descendant
		end
	end

	local hitbox = floorModel:FindFirstChild("Hitbox", true)
	if hitbox and hitbox:IsA("BasePart") then
		return hitbox
	end

	return nil
end

local function getFloorReferenceTransform(floorNumber: number): CFrame?
	if floorNumber <= 1 then
		return nil
	end

	local floorFolder = getFloorTemplateFolder()
	if not floorFolder then
		return nil
	end

	local prevTemplate = floorFolder:FindFirstChild("Floor" .. (floorNumber - 1))
	local nextTemplate = floorFolder:FindFirstChild("Floor" .. floorNumber)
	local prevHitbox = getFloorHitbox(prevTemplate)
	local nextHitbox = getFloorHitbox(nextTemplate)
	if prevHitbox and nextHitbox then
		return prevHitbox.CFrame:ToObjectSpace(nextHitbox.CFrame)
	end

	return nil
end

local function getFallbackFloorOffset(floorNumber: number): Vector3
	if floorNumber == 2 then
		return Vector3.new(25, 50, 0)
	end

	return Vector3.new(0, 85, 0)
end

local function getFloor1ReferenceHitboxCFrame(spawnPart: BasePart): CFrame
	local hitboxOffset = Vector3.new(0, -3, 0)
	return CFrame.new(spawnPart.Position + hitboxOffset) * spawnPart.CFrame.Rotation
end

-- Shared floor placement path for both locked previews and real unlocks.
-- Keeping this centralized ensures the ghost floor and the unlocked floor stay aligned.
local function resolveFloorHitboxTargetCFrame(
	plot: Model,
	referenceFloor: Model?,
	referenceHitbox: BasePart?,
	targetFloorNumber: number
): CFrame?
	local referenceTransform = getFloorReferenceTransform(targetFloorNumber)
	if referenceHitbox and referenceTransform then
		return referenceHitbox.CFrame * referenceTransform
	end

	local spawnInstance = plot:FindFirstChild("Spawn")
	local spawnPart = if spawnInstance and spawnInstance:IsA("BasePart") then spawnInstance else nil
	local baseFloor = plot.Floors:FindFirstChild("1")
	local baseHitbox = baseFloor and getFloorHitbox(baseFloor)
	local floor1ReferenceHitboxCFrame = baseHitbox and baseHitbox.CFrame
	local baseRotation = CFrame.identity

	if not floor1ReferenceHitboxCFrame and spawnPart then
		floor1ReferenceHitboxCFrame = getFloor1ReferenceHitboxCFrame(spawnPart)
	end

	if floor1ReferenceHitboxCFrame then
		baseRotation = floor1ReferenceHitboxCFrame.Rotation
	end

	local fallbackOffset = getFallbackFloorOffset(targetFloorNumber)

	if referenceFloor then
		local newPosition = referenceFloor:GetPivot().Position + fallbackOffset
		return CFrame.new(newPosition) * baseRotation
	end

	if floor1ReferenceHitboxCFrame then
		if referenceTransform then
			return floor1ReferenceHitboxCFrame * referenceTransform
		end

		return CFrame.new(floor1ReferenceHitboxCFrame.Position + fallbackOffset) * baseRotation
	end

	return nil
end

local DEFAULT_POT_STATS = {
	TimeMul = 1,
	XPMul = 1,
	HarvestXPMul = 1,
	WeightMul = 1,
	InsectMul = 1,
}

-- GameDesign.md 5.6: Cracked pot disables buffs and applies +10% grow time debuff
local CRACKED_POT_STATS = {
	TimeMul = 1.10,
	XPMul = 1,
	HarvestXPMul = 1,
	WeightMul = 1,
	InsectMul = 1,
}

-- New growth timing constants (in seconds) - Requirements 1.1, 2.2, 3.2
local SEED_WAIT_TIME = 5           -- Time before requiring water (Seed Stage)
local SPROUT_STAGE_1_DURATION = 30 -- Duration of sprout stage 1 after watering
local SPROUT_STAGE_2_DURATION = 60 -- Duration of sprout stage 2
local _TOTAL_SPROUT_TIME = SEED_WAIT_TIME + SPROUT_STAGE_1_DURATION + SPROUT_STAGE_2_DURATION -- 95 seconds total (for reference)

local function createLocalEmptyMutationState()
	return {
		Active = {},
		LastUpdated = 0,
	}
end

local function ensureMutationStateTable(potData)
	if not potData then
		return createLocalEmptyMutationState()
	end

	local potService = getPotService()
	if potService and potService.EnsureMutationState then
		return potService.EnsureMutationState(potData)
	end

	-- Debug: Log incoming state
	local incomingCurrent = potData.Mutations and potData.Mutations.Current or "nil"
	print(string.format("[PlotService] ensureMutationStateTable: incoming Current=%s", tostring(incomingCurrent)))

	-- Preserve existing mutation data (especially Current for new format)
	if not potData.Mutations then
		potData.Mutations = createLocalEmptyMutationState()
	else
		-- Ensure Active table exists without overwriting Current
		if not potData.Mutations.Active then
			potData.Mutations.Active = {}
		end
		if not potData.Mutations.LastUpdated then
			potData.Mutations.LastUpdated = 0
		end
	end

	-- Debug: Log outgoing state
	print(string.format("[PlotService] ensureMutationStateTable: outgoing Current=%s", tostring(potData.Mutations.Current)))

	return potData.Mutations
end

local function summarizeMutations(mutationState)
	mutationState = mutationState or createLocalEmptyMutationState()
	local names
	local expiry

	local potService = getPotService()
	if potService and potService.GetMutationNames then
		names = potService.GetMutationNames(mutationState)
	else
		names = {}
		-- Support new format: Mutations.Current (single permanent mutation)
		if mutationState.Current and typeof(mutationState.Current) == "string" and mutationState.Current ~= "" then
			table.insert(names, mutationState.Current)
		end
		-- Also support old format: Mutations.Active (multiple mutations with expiry)
		for name in pairs(mutationState.Active or {}) do
			table.insert(names, name)
		end
		table.sort(names)
	end

	if potService and potService.GetLatestMutationExpiry then
		expiry = potService.GetLatestMutationExpiry(mutationState)
	else
		expiry = 0
		-- New format has no expiry (permanent mutations)
		for _, entry in pairs(mutationState.Active or {}) do
			if entry and entry.ExpiresAt and entry.ExpiresAt > expiry then
				expiry = entry.ExpiresAt
			end
		end
	end

	return table.concat(names, ","), expiry
end

local function getPotStatsFromSeed(playerData: any, floorIndex: number?, seedKey: string?)
	if not playerData or not floorIndex or not seedKey then
		return DEFAULT_POT_STATS
	end

	local floors = playerData.Floors and playerData.Floors.Index
	if not floors then
		return DEFAULT_POT_STATS
	end

	local floorData = floors[floorIndex]
	if not floorData or not floorData.Seeds then
		return DEFAULT_POT_STATS
	end

	local seedEntry = floorData.Seeds[seedKey]
	if not seedEntry or not seedEntry.PotKey then
		return DEFAULT_POT_STATS
	end

	local potKey = seedEntry.PotKey
	local potData = floorData.Pots and floorData.Pots[potKey]
	local potName = if potData and typeof(potData.PotName) == "string" and potData.PotName ~= "" then potData.PotName else potKey:split(":")[1]
	local potStats = Pot[potName] or DEFAULT_POT_STATS

	-- If the pot is cracked, disable all buffs and apply a growth-time debuff
	local status = potData and potData.Status or "Normal"
	if status == "Cracked" then
		return CRACKED_POT_STATS
	end

	return potStats
end

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

-- Get mutation data by name (supports both old and new module format)
local function getMutationData(mutationName: string)
	if not mutationName then
		return nil
	end
	return PotMutations.Mutations and PotMutations.Mutations[mutationName]
		or PotMutations[mutationName]
end

-- Check if mutation is active based on time condition
local function isMutationActiveNow(mutationName: string): boolean
	if not mutationName then
		return false
	end
	local mutData = getMutationData(mutationName)
	if not mutData then
		return false
	end
	if not mutData.TimeCondition then
		return true -- No time restriction
	end
	local timeNow = GetTimeOfDay()
	return mutData.TimeCondition == timeNow
end

-- NEW FORMAT: Get pot mutation growth speed multiplier
local function getPotMutationGrowthSpeedMultiplierFromSeed(playerData: any, floorIndex: number?, seedKey: string?): number
	if not playerData or not floorIndex or not seedKey then
		return 1
	end

	local floors = playerData.Floors and playerData.Floors.Index
	if not floors then
		return 1
	end

	local floorData = floors[floorIndex]
	if not floorData or not floorData.Seeds or not floorData.Pots then
		return 1
	end

	local seedEntry = floorData.Seeds[seedKey]
	if not seedEntry or not seedEntry.PotKey then
		return 1
	end

	local potKey = seedEntry.PotKey
	local potData = floorData.Pots[potKey]
	if not potData or not potData.Mutations then
		return 1
	end

	-- NEW FORMAT: Mutations.Current contains the mutation name
	local mutationName = potData.Mutations.Current
	if not mutationName then
		return 1
	end

	-- Check if mutation is active (time condition)
	if not isMutationActiveNow(mutationName) then
		return 1
	end

	local mutData = getMutationData(mutationName)
	if not mutData then
		return 1
	end

	-- Apply GrowthSpeedMul from new mutation format
	local speedMul = mutData.GrowthSpeedMul
	if typeof(speedMul) == "number" and speedMul > 0 then
		return speedMul
	end

	return 1
end

function PlotService.GetMaxPlots()
	return #workspace.Gardens:GetChildren()
end

function PlotService.AssignPlot(player: Player)
	for i = 1, PlotService.GetMaxPlots() do
		local plot = workspace.Gardens[tostring(i)]
		if plot:GetAttribute("Loaded") == true then
			continue
		end

		return plot
	end

	return nil
end

function PlotService.LocationIsWithinPlot(plot: Model, location: CFrame)
	if plot and location then
		local Instances = {}

		for _, floorModel in plot.Floors:GetChildren() do
			local hitbox = getFloorHitbox(floorModel)
			if hitbox then
				table.insert(Instances, hitbox)
			end
		end

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = Instances

		for _, part: Part in Instances do
			local result = workspace:Raycast(location.Position + Vector3.new(0, 5, 0), Vector3.new(0, -9999, 0), params)
			if result and result.Instance == part then
				return true, part
			end
		end
	end

	return false
end

function PlotService.LocationIsWithinPot(player: Player, location: CFrame)
	if location then
		local Instances = {}

		for _, v in workspace.World.PlacedPots.Server:GetChildren() do
			if v:GetAttribute("Owner") == player.UserId then
				table.insert(Instances, v._Primary)
			end
		end

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = Instances

		for _, part: Part in Instances do
			local result = workspace:Raycast(location.Position + Vector3.new(0, 5, 0), Vector3.new(0, -9999, 0), params)
			if result and result.Instance == part then
				return true, part.Parent
			end
		end
	end

	return false
end

function PlotService.GetPlot(player: Player)
	for _, v in pairs(workspace.Gardens:GetChildren()) do
		if v.Data.Owner.Value == player.Name then
			return v
		end
	end

	return nil
end

-- Constants for floor preview
local FLOOR_PREVIEW_CONFIG = {
	Transparency = 0.85,
	CanCollide = false,
	TintColor = Color3.fromRGB(150, 180, 255), -- Light blue tint for preview
	TintTransparency = 0.3,
	GlowIntensity = 0.5,
}

-- Helper: Create unlock indicator UI on preview floor
local function createUnlockIndicator(previewFloor: Model): Instance?
	local floorHitbox = getFloorHitbox(previewFloor)
	if not floorHitbox then
		return nil
	end

	-- Create a part for billboard attachment
	local indicatorPart = Instance.new("Part")
	indicatorPart.Name = "UnlockIndicatorAttach"
	indicatorPart.Shape = Enum.PartType.Ball
	indicatorPart.Size = Vector3.new(0.1, 0.1, 0.1)
	indicatorPart.CanCollide = false
	indicatorPart.CFrame = floorHitbox.CFrame + Vector3.new(0, 15, 0)
	indicatorPart.Transparency = 1
	indicatorPart.Parent = previewFloor

	-- Create BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "UnlockIndicator"
	billboard.Size = UDim2.new(8, 0, 3, 0)
	billboard.MaxDistance = 150
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.Parent = indicatorPart

	-- Create text frame
	local textFrame = Instance.new("TextLabel")
	textFrame.Size = UDim2.new(1, 0, 1, 0)
	textFrame.BackgroundColor3 = Color3.fromRGB(50, 100, 200)
	textFrame.BackgroundTransparency = 0.2
	textFrame.TextColor3 = Color3.fromRGB(255, 255, 255)
	textFrame.TextSize = 18
	textFrame.Font = Enum.Font.GothamBold
	textFrame.Text = "🔒 Floor " .. previewFloor.Name .. " Locked"
	textFrame.BorderSizePixel = 2
	textFrame.BorderColor3 = Color3.fromRGB(100, 180, 255)
	textFrame.Parent = billboard

	-- Add corner radius
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = textFrame

	return indicatorPart
end

-- Helper: Apply visual tint to preview floor parts
local function applyPreviewTint(part: BasePart)
	if part:IsA("BasePart") then
		-- Store original color
		local originalColor = part.Color
		part:SetAttribute("OriginalColor", originalColor)
		part:SetAttribute("IsPreviewFloor", true)
		
		-- Apply slight tint (blend with blue)
		local tintColor = FLOOR_PREVIEW_CONFIG.TintColor
		part.Color = Color3.new(
			(originalColor.R + tintColor.R) / 2,
			(originalColor.G + tintColor.G) / 2,
			(originalColor.B + tintColor.B) / 2
		)
	end
end

-- Helper: Apply enhancement effects to preview floor
local function applyPreviewEffects(previewFloor: Model)
	local tintedParts = 0
	
	for _, descendant in previewFloor:GetDescendants() do
		if descendant:IsA("BasePart") then
			-- Apply transparency
			descendant.Transparency = FLOOR_PREVIEW_CONFIG.Transparency
			descendant.CanCollide = FLOOR_PREVIEW_CONFIG.CanCollide
			
			-- Apply tint if visible
			if descendant.Transparency < 1 then
				applyPreviewTint(descendant)
				tintedParts += 1
			end
		end
	end
	
	-- Mark floor as preview
	previewFloor:SetAttribute("IsPreviewFloor", true)
	previewFloor:SetAttribute("LockedFloorNumber", tonumber(previewFloor.Name))
	
	return tintedParts
end

-- Main function: Create preview of next unlocked floor
local function applyTransparencyToNextFloor(plot: Model, maxFloorIndex: number)
	if maxFloorIndex < 1 then return end

	local nextFloorNumber = maxFloorIndex + 1
	local nextFloorTemplate = getFloorTemplate(nextFloorNumber)
	if not nextFloorTemplate then return end

	-- Check if next floor already exists in the plot
	if plot.Floors:FindFirstChild(tostring(nextFloorNumber)) then return end

	-- Clone the template
	local previewFloor = nextFloorTemplate:Clone()
	previewFloor.Name = tostring(nextFloorNumber)

	-- Get current floor for positioning reference.
	-- Floor 1 is the base garden terrain (NOT in plot.Floors); ensureFloor1Reference creates a reference.
	local currentFloor = plot.Floors:FindFirstChild(tostring(maxFloorIndex))

	-- Position the preview floor
	local previewHitbox = getFloorHitbox(previewFloor)
	local currentHitbox = currentFloor and getFloorHitbox(currentFloor)
	local targetHitboxCFrame = resolveFloorHitboxTargetCFrame(plot, currentFloor, currentHitbox, nextFloorNumber)

	if not targetHitboxCFrame then
		previewFloor:Destroy()
		return
	end

	if previewHitbox then
		local hitboxOffset = previewFloor:GetPivot():ToObjectSpace(previewHitbox.CFrame)
		previewFloor:PivotTo(targetHitboxCFrame * hitboxOffset:Inverse())
	else
		previewFloor:PivotTo(targetHitboxCFrame)
	end

	-- Apply visual effects and transparency
	local tintedPartsCount = applyPreviewEffects(previewFloor)
	
	-- Create unlock indicator UI
	local indicatorPart = createUnlockIndicator(previewFloor)
	if indicatorPart then
		table.insert(_seedConnections[`preview_{plot.Name}_{nextFloorNumber}`] or {}, indicatorPart)
	end

	-- Attach to plot
	previewFloor.Parent = plot.Floors
	
	print(string.format(
		"🔒 Preview floor %d created (transparency=%.1f, tinted=%d parts) for %s",
		nextFloorNumber,
		FLOOR_PREVIEW_CONFIG.Transparency,
		tintedPartsCount,
		plot.Data.Owner.Value
	))
end

-- Helper function to sync missing visual elements from template to plot floor
local function syncFloorFromTemplate(plotFloor: Model, floorNumber: number)
	local floorTemplate = getFloorTemplate(floorNumber)
	if not floorTemplate then
		return
	end

	-- Get hitboxes for position calculation
	local templateHitbox = getFloorHitbox(floorTemplate)
	local plotHitbox = getFloorHitbox(plotFloor)
	if not templateHitbox or not plotHitbox then
		return
	end

	-- List of folders that should NOT be synced (player data folders)
	local protectedNames = {
		Pots = true,
		Seeds = true,
		Plants = true,
		Hitbox = true, -- Keep existing hitbox
	}

	-- Sync each child from template that doesn't exist in plot floor
	for _, templateChild in floorTemplate:GetChildren() do
		if protectedNames[templateChild.Name] then
			continue
		end

		-- Skip if already exists
		if plotFloor:FindFirstChild(templateChild.Name) then
			continue
		end

		-- Clone and position relative to hitbox
		local newChild = templateChild:Clone()
		
		if newChild:IsA("BasePart") then
			local relativeCFrame = templateHitbox.CFrame:ToObjectSpace(templateChild.CFrame)
			newChild.CFrame = plotHitbox.CFrame * relativeCFrame
		elseif newChild:IsA("Model") then
			local relativeCFrame = templateHitbox.CFrame:ToObjectSpace(templateChild:GetPivot())
			newChild:PivotTo(plotHitbox.CFrame * relativeCFrame)
		end
		
		newChild.Parent = plotFloor
	end
end

function PlotService.UnlockFloor(player: Player, floorNumber: number): boolean
	local plot = PlotService.GetPlot(player)

	if not plot then
		warn("❌ No plot found for", player.Name)
		return false
	end

	-- Check if floor already exists; destroy preview floor if present
	local existingFloor = plot.Floors:FindFirstChild(tostring(floorNumber))
	if existingFloor then
		if existingFloor:GetAttribute("IsPreviewFloor") == true then
			existingFloor:Destroy()
		else
			warn("❌ Floor", floorNumber, "already exists for", player.Name)
			return false
		end
	end

	local previousFloor = plot.Floors:FindFirstChild(tostring(floorNumber - 1))
	if not previousFloor then
		warn("❌ Previous floor", floorNumber - 1, "not found for", player.Name)
		return false
	end

	local floorTemplate = getFloorTemplate(floorNumber)
	if not floorTemplate then
		warn("❌ Floor template 'Floor" .. floorNumber .. "' not found")
		return false
	end

	-- Sync previous floor with template to ensure all visual elements exist (including climbing elements)
	syncFloorFromTemplate(previousFloor, floorNumber - 1)

	local newFloor = floorTemplate:Clone()
	newFloor.Name = tostring(floorNumber)

	local newHitbox = getFloorHitbox(newFloor)
	local previousHitbox = getFloorHitbox(previousFloor)
	local targetHitboxCFrame = resolveFloorHitboxTargetCFrame(plot, previousFloor, previousHitbox, floorNumber)

	if targetHitboxCFrame then
		if newHitbox then
			local hitboxOffset = newFloor:GetPivot():ToObjectSpace(newHitbox.CFrame)
			newFloor:PivotTo(targetHitboxCFrame * hitboxOffset:Inverse())
		else
			newFloor:PivotTo(targetHitboxCFrame)
		end
	end
	newFloor:SetAttribute("Index", floorNumber)
	if newHitbox then
		newHitbox.CanQuery = true
		newHitbox:AddTag("Hitbox")
	end
	newFloor.Parent = plot.Floors
	
	-- Create preview of the next floor (if exists)
	applyTransparencyToNextFloor(plot, floorNumber)
	
	print("🏢 Floor", floorNumber, "unlocked in plot for", player.Name)
	return true
end


-- Helper: Remove preview floor's visual markers after it's unlocked
local function cleanupPreviewFloorVisuals(floor: Model)
	if floor:GetAttribute("IsPreviewFloor") ~= true then
		return
	end

	-- Restore original colors
	for _, descendant in floor:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("IsPreviewFloor") == true then
			local originalColor = descendant:GetAttribute("OriginalColor")
			if originalColor then
				descendant.Color = originalColor
			end
			descendant.Transparency = 0 -- Restore to solid
			descendant.CanCollide = true -- Restore collision
		end
	end
	
	-- Remove unlock indicator
	local unlockIndicator = floor:FindFirstChild("UnlockIndicatorAttach", true)
	if unlockIndicator then
		unlockIndicator:Destroy()
	end
	
	floor:SetAttribute("IsPreviewFloor", nil)
end

-- Ensure Floor 1 reference model exists in plot.Floors.
-- Floor 1 is the base garden terrain (pre-built, never placed by UnlockFloor).
-- Without this reference, UnlockFloor(2+) and applyTransparencyToNextFloor fail silently.
-- The reference is minimal (invisible hitbox only) — just provides a CFrame anchor for positioning.
local function ensureFloor1Reference(plot: Model)
	if plot.Floors:FindFirstChild("1") then return end

	local spawnPart = plot:FindFirstChild("Spawn")
	if not spawnPart or not spawnPart:IsA("BasePart") then return end

	-- Floor1 hitbox center is ~3 studs below Spawn surface (measured from workspace.Floor1 vs Spawn Y)
	local hitboxCFrame = getFloor1ReferenceHitboxCFrame(spawnPart)
	local hitboxCenterY = hitboxCFrame.Position.Y

	local ref = Instance.new("Model")
	ref.Name = "1"

	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(80, 6, 80) -- approximate floor 1 footprint
	hitbox.CFrame = hitboxCFrame
	hitbox.Anchored = true
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox:SetAttribute("IsFloorHitbox", true)
	hitbox.Parent = ref

	ref.Parent = plot.Floors
	print("[PlotService] Created Floor 1 reference hitbox at Y=" .. string.format("%.2f", hitboxCenterY))
end

local function MarkPlayerPlot()
	for _,player in game.Players:GetPlayers() do
		local plot = PlotService.GetPlot(player)
		if plot then
			local floor1Model = plot.Floors:FindFirstChild("1")
			if not floor1Model then continue end
			local currentPivotCFrame  = floor1Model:GetPivot()
			-- local currentPosition = currentPivotCFrame.Position
			local targetPosition = currentPivotCFrame + Vector3.new(0, 30, 0)
			local plotMarkerRemote = Remotes.ServerEffects:FindFirstChild("PlotMarker")
			if plotMarkerRemote and plotMarkerRemote:IsA("RemoteEvent") then
				plotMarkerRemote:FireAllClients("SetPlotMarker", player.UserId, targetPosition)
			end
			-- plot:SetAttribute("OwnerUserId", player.UserId)
		end
	end
end

-- Update the Portal NameBoard text for a given garden index
local function updatePortalNameBoard(gardenIndex: number, displayName: string)
	for _, obj in workspace:GetChildren() do
		if obj.Name == "Portal" and obj:IsA("Model") and obj:GetAttribute("GardenIndex") == gardenIndex then
			local nameT = obj:FindFirstChild("NameT", true)
			if nameT and nameT:IsA("TextLabel") then
				nameT.Text = if displayName ~= "" then displayName .. "'s Garden" else "No Owner"
			end
			break
		end
	end
end

function PlotService.DataLoaded(player: Player)
	local plot = PlotService.AssignPlot(player)
	if plot then
		plot:SetAttribute("Loaded", true)
		plot.Data.Owner.Value = player.Name

		-- Update Portal NameBoard for this garden
		updatePortalNameBoard(tonumber(plot.Name) :: number, player.DisplayName)

		local BeanstalkService = CachedModules.Cached.BeanstalkService
		if BeanstalkService and BeanstalkService.ExpandSetup and BeanstalkService.ExpandSetup.UpdatePromptForPlayer then
			BeanstalkService.ExpandSetup.UpdatePromptForPlayer(player)
		end

		local DataService = CachedModules.Cached.DataService
		local playerData = DataService.GetPlayerData(player)
		local plotData = playerData.Floors.Index
		ensureFloor1Reference(plot)
		MarkPlayerPlot()
		print("📂 Loading plot data for", player.Name, "playerdata:", playerData)
		task.spawn(function()
			local replica = DataService.GetReplica(player)
			
			for floorIndex = 1, #plotData do
				if floorIndex > 1 and not plot.Floors:FindFirstChild(tostring(floorIndex)) then
					PlotService.UnlockFloor(player, floorIndex)
				end

				for key, data in plotData[floorIndex].Pots do
					if plotData[floorIndex].Pots[key].isInventory then
						continue
					end
					-- Ensure mutation state exists before syncing
					ensureMutationStateTable(data)
					if replica then
						-- Set entire potData to avoid nested path nil errors
						replica:Set({"Floors", "Index", floorIndex, "Pots", key}, data)
					end
					PlotService.CreatePotServerModel(player, key, data)
				end

				for key, data in plotData[floorIndex].Seeds do
					PlotService.CreateSeedServerModel(player, key, data)
				end
			end
			
			-- Create preview of next unlocked floor with transparency
			applyTransparencyToNextFloor(plot, #plotData)
		end)

		task.spawn(function()
			if not player.Character then
				player.CharacterAdded:Wait()
			end

			-- Prefer explicit Spawn part; fall back to first floor position
			local spawnPart = plot:FindFirstChild("Spawn")
			if spawnPart and spawnPart:IsA("BasePart") then
				player.Character:PivotTo(spawnPart.CFrame + Vector3.new(0, 5, 0))
			else
				local floor1 = plot.Floors:FindFirstChild("1")
				if floor1 then
					player.Character:PivotTo(floor1:GetPivot() + Vector3.new(0, 10, 0))
				end
			end
		end)

		-- Persistent re-teleport on every respawn after death
		-- Without this, players respawn at the default SpawnLocation (mid-air) and die in a loop
		local respawnConn
		respawnConn = player.CharacterAdded:Connect(function(character)
			local assignedPlot = PlotService.GetPlot(player)
			if not assignedPlot then return end

			-- Small yield so character physics settle before teleport
			task.wait(0.1)

			local spawnPart = assignedPlot:FindFirstChild("Spawn")
			if spawnPart and spawnPart:IsA("BasePart") then
				character:PivotTo(spawnPart.CFrame + Vector3.new(0, 5, 0))
			else
				local floor1 = assignedPlot.Floors:FindFirstChild("1")
				if floor1 then
					character:PivotTo(floor1:GetPivot() + Vector3.new(0, 10, 0))
				end
			end
		end)
		_playerRespawnConns[player] = respawnConn

		-- Create like board for the plot
		task.spawn(function()
			local PlotLikeService = getPlotLikeService()
			if PlotLikeService and PlotLikeService.CreateLikeBoard then
				PlotLikeService.CreateLikeBoard(plot, player.UserId)
			end
		end)
	end
end

function PlotService.PlayerRemoved(player: Player)
	-- Disconnect persistent respawn teleport connection
	local respawnConn = _playerRespawnConns[player]
	if respawnConn then
		respawnConn:Disconnect()
		_playerRespawnConns[player] = nil
	end

	-- Always clear plot marker even if plot lookup fails due state desync.
	local plotMarkerRemote = Remotes.ServerEffects:FindFirstChild("PlotMarker")
	if plotMarkerRemote and plotMarkerRemote:IsA("RemoteEvent") then
		plotMarkerRemote:FireAllClients("RemovePlotMarker", player.UserId)
	end

	local plot = PlotService.GetPlot(player)
	if plot then
		plot:SetAttribute("Loaded", false)
		plot.Data.Owner.Value = ""

		-- Clear Portal NameBoard for this garden
		updatePortalNameBoard(tonumber(plot.Name) :: number, "")

		-- Clear all pots
		for _, pot: Model in workspace.World.PlacedPots.Server:GetChildren() do
			if pot:GetAttribute("Owner") == player.UserId then
				pot:Destroy()
			end
		end

		-- Clear all planted seeds and their connections
		for _, seed: Model in workspace.World.PlantedSeeds.Server:GetChildren() do
			if seed:GetAttribute("Owner") == player.UserId then
				-- Clean up connections for this seed
				local seedConnectionKey = `{player.UserId}:{seed.Name}`
				cleanupSeedConnections(seedConnectionKey)
				
				seed:Destroy()
			end
		end
		
		-- Clean up tutorial plant state cache
		_tutorialPlantStateCache[player.UserId] = nil

		-- Remove unlocked floors (keep only floor 1)
		for _, floor in plot.Floors:GetChildren() do
			local floorIndex = tonumber(floor.Name)
			if floorIndex and floorIndex > 1 then
				floor:Destroy()
			end
		end

		-- Clean up like board display (keep Board model, just remove the GUI and prompt)
		local boardModel = plot:FindFirstChild("Board")
		if boardModel then
			boardModel:SetAttribute("LikeSetup", nil)
			boardModel:SetAttribute("OwnerId", nil)
			
			local likeDisplay = boardModel:FindFirstChild("LikeDisplay", true)
			if likeDisplay then
				likeDisplay:Destroy()
			end
			
			-- Remove LikePrompt from board parts
			for _, descendant in boardModel:GetDescendants() do
				if descendant:IsA("ProximityPrompt") and descendant.Name == "LikePrompt" then
					descendant:Destroy()
				end
			end
		end
	end
end

-- NOTE: Harvest prompts are created client-side in PlantReplicator
-- because ProximityPrompts need to be in replicated containers (Client folder)
-- Server validates harvest requests via Remotes.Harvest RemoteEvent

function PlotService.CreatePotServerModel(player: Player, key: string, data: any)
	local DataService = CachedModules.Cached.DataService
	local PlayerData = DataService.GetPlayerData(player)

	local floorData = PlayerData.Floors.Index
	local saveData = floorData[data.Floor]
	local trueName = if typeof(data.PotName) == "string" and data.PotName ~= "" then data.PotName else key:split(":")[1]
	local folder = Assets.Models:FindFirstChild(trueName)

	if folder and saveData and Pot[trueName] then
		local serverModelFolder = folder:FindFirstChild("ServerModel")
		local serverModelTemplate = serverModelFolder and serverModelFolder:FindFirstChild(trueName)
		if not serverModelTemplate then
			warn("[PlotService] ServerModel not found for pot:", trueName)
			return
		end
		local serverModel = serverModelTemplate:Clone()
		serverModel.Name = key
		serverModel:SetAttribute("Owner", player.UserId)
		serverModel:SetAttribute("Plot", PlotService.GetPlot(player).Name)
		serverModel:SetAttribute("Floor", data.Floor)
		serverModel:SetAttribute("PotName", trueName)
		serverModel:SetAttribute("IsPlanted", data.IsPlanted == true)
		serverModel:SetAttribute("PotStatus", data.Status or "Normal")
		
		-- Set mutation attributes
		local mutationState = ensureMutationStateTable(data)
		local mutationString, latestExpiry = summarizeMutations(mutationState)
		serverModel:SetAttribute("Mutations", mutationString)
		serverModel:SetAttribute("MutationExpiresAt", latestExpiry)

		local deseralizedCFrame = CFrame.new(table.unpack(data.Location))
		local rotationOnly = CFrame.fromMatrix(
			Vector3.zero,
			deseralizedCFrame.RightVector,
			deseralizedCFrame.UpVector,
			-deseralizedCFrame.LookVector
		)
		deseralizedCFrame = CFrame.new(
			deseralizedCFrame.Position.X,
			deseralizedCFrame.Position.Y - 1,
			deseralizedCFrame.Position.Z
		) * rotationOnly * CFrame.Angles(math.rad(90), 0, 0)

		deseralizedCFrame = PlotService.GetPlot(player).ReferencePoint.CFrame:ToWorldSpace(deseralizedCFrame)
		serverModel:PivotTo(deseralizedCFrame)
		serverModel.Parent = workspace.World.PlacedPots.Server
		print("Creating pot server model for", player.Name, "pot key:", key, "data:", data)
	end
end

function PlotService.CreateSeedServerModel(player: Player, key: string, data: any)
	local DataService = CachedModules.Cached.DataService
	local PlayerData = DataService.GetPlayerData(player)

	local floorData = PlayerData.Floors.Index
	local saveData = floorData[data.Floor].Seeds[key]
	local trueName = key:split(":")[1]

	if not saveData then
		return
	end
	if not Seed[trueName] then
		warnMissingSeedModelOnce(trueName, "seed data entry not found")
		return
	end

	local resolvedModelName, usedAlias = PlantModelResolver.ResolveModelName(trueName, Assets.Models)
	if not resolvedModelName then
		warnMissingSeedModelOnce(trueName, "ReplicatedStorage.Assets.Models folder not found")
		return
	end
	if usedAlias then
		warnSeedModelAliasOnce(trueName, resolvedModelName)
	end

	local folder = Assets.Models:FindFirstChild(resolvedModelName)
	local serverModelFolder = folder and folder:FindFirstChild("ServerModel")
	local serverModelTemplate = serverModelFolder and serverModelFolder:FindFirstChild(resolvedModelName)
	if not serverModelTemplate then
		warnMissingSeedModelOnce(trueName, "ServerModel template missing")
		return
	end

	local serverModel = serverModelTemplate:Clone()
	serverModel.Name = key
	serverModel:SetAttribute("Owner", player.UserId)
	serverModel:SetAttribute("Floor", data.Floor)
	serverModel:SetAttribute("PotKey", data.PotKey)

	-- Ensure PrimaryPart is set (some models may have _Primary Part without PrimaryPart assigned)
	if not serverModel.PrimaryPart then
		local fallback = serverModel:FindFirstChild("_Primary")
		if fallback and fallback:IsA("BasePart") then
			serverModel.PrimaryPart = fallback
		end
	end

	local serverConfig = script.ServerModelConfig:Clone()
	serverConfig.Name = "ServerConfiguration"

	serverConfig.DatePlanted.Value = data.DatePlanted
	serverConfig.GrowthPercentage.Value = data.GrowthPercentage
	serverConfig.LastGrowthIncrement.Value = data.LastGrowthIncrement
	serverConfig.State.Value = data.State
	serverConfig.Water.Value = data.Water
	serverConfig.NeedWater.Value = data.NeedWater
	serverConfig.PlantSize.Value = data.PlantSize
		
	-- Migration logic for existing plants without WaterTime (Requirements 7.1, 7.2, 7.3)
	local waterTimeValue = data.WaterTime or 0
	if waterTimeValue == 0 and data.Water == true then
		-- Estimate WaterTime for existing watered plants: DatePlanted + SEED_WAIT_TIME
		waterTimeValue = data.DatePlanted + SEED_WAIT_TIME
	end
	serverConfig.WaterTime.Value = waterTimeValue
	local sproutStage1Value = serverConfig:FindFirstChild("SproutStage1Duration")
	if sproutStage1Value then
		sproutStage1Value.Value = SPROUT_STAGE_1_DURATION
	end
	local sproutStage2Value = serverConfig:FindFirstChild("SproutStage2Duration")
	if sproutStage2Value then
		sproutStage2Value.Value = SPROUT_STAGE_2_DURATION
	end
		
	-- Recalculate State based on elapsed time for state restoration on rejoin (Requirements 5.2, 5.3)
	if data.Water == true and waterTimeValue > 0 then
		local currentTime = os.time()
		local elapsedSinceWatering = currentTime - waterTimeValue
			
		if elapsedSinceWatering < SPROUT_STAGE_1_DURATION then
			serverConfig.State.Value = 1 -- Sprout Stage 1
		elseif elapsedSinceWatering < SPROUT_STAGE_1_DURATION + SPROUT_STAGE_2_DURATION then
			serverConfig.State.Value = 2 -- Sprout Stage 2
		else
			serverConfig.State.Value = 3 -- Mature Stage
		end
	elseif data.Water == false then
		serverConfig.State.Value = 1 -- Seed Stage
	end

	-- Create Fruits folder if it doesn't exist
	local fruitsFolder = serverConfig:FindFirstChild("Fruits")
	if not fruitsFolder then
		fruitsFolder = Instance.new("Folder")
		fruitsFolder.Name = "Fruits"
		fruitsFolder.Parent = serverConfig
	end

	-- Initialize connections table for this seed
	local seedConnectionKey = `{player.UserId}:{key}`
	_seedConnections[seedConnectionKey] = {}

	local destroyConn
	destroyConn = serverModel.Destroying:Connect(function()
		cleanupSeedConnections(seedConnectionKey)
		if destroyConn then
			destroyConn:Disconnect()
			destroyConn = nil
		end
	end)
	table.insert(_seedConnections[seedConnectionKey], destroyConn)
		
	for index: number, fruitData: any in data.Fruits do
		local fruitConfig = script.FruitConfigTemplate:Clone()
		fruitConfig.Name = tostring(index)
		fruitConfig.CanHarvest.Value = fruitData.CanHarvest
		fruitConfig.LastHarvest.Value = fruitData.LastHarvest
		fruitConfig.Mutations.Value = fruitData.Mutations
		fruitConfig.SizeScaling.Value = fruitData.SizeScaling
		fruitConfig.Parent = fruitsFolder

		-- Updating - Replica auto sync
		for _, v in fruitConfig:GetChildren() do
			if not v:IsA("Folder") then
				local conn = v.Changed:Connect(function()
					if saveData.Fruits[index][v.Name] ~= nil then
						saveData.Fruits[index][v.Name] = v.Value
					end
				end)
				table.insert(_seedConnections[seedConnectionKey], conn)
			end
		end
	end

	-- Sync changes - Replica auto sync
	for _, v in serverConfig:GetChildren() do
		if not v:IsA("Folder") then
			local conn = v.Changed:Connect(function()
				if saveData[v.Name] ~= nil then
					saveData[v.Name] = v.Value
				end
			end)
			table.insert(_seedConnections[seedConnectionKey], conn)
		end
	end

	serverConfig.Parent = serverModel

	-- NOTE: Harvest prompts are now created client-side in PlantReplicator
	-- Client listens to CanHarvest.Changed to sync prompt enabled state

	-- Position
	local deseralizedCFrame = CFrame.new(table.unpack(data.Location))
	deseralizedCFrame = CFrame.new(
		deseralizedCFrame.Position.X,
		deseralizedCFrame.Position.Y - 1,
		deseralizedCFrame.Position.Z
	) * CFrame.Angles(math.rad(90), 0, 0)

	deseralizedCFrame = PlotService.GetPlot(player).ReferencePoint.CFrame:ToWorldSpace(deseralizedCFrame)
	serverModel:PivotTo(deseralizedCFrame * CFrame.new(0, 0, -2))
	serverModel.Parent = workspace.World.PlantedSeeds.Server
end

function PlotService.CreateEggServerModel(player: Player, floor: number, key: string, data: any)
	--[[
		Create visual representation of egg on plot
		Eggs are simple models that display countdown timers
	]]
	if not data or not data.Location then
		return
	end

	-- Ensure PlacedEggs folder exists
	local worldFolder = workspace:FindFirstChild("World")
	if not worldFolder then
		worldFolder = Instance.new("Folder")
		worldFolder.Name = "World"
		worldFolder.Parent = workspace
	end
	
	local placedEggsFolder = worldFolder:FindFirstChild("PlacedEggs")
	if not placedEggsFolder then
		placedEggsFolder = Instance.new("Folder")
		placedEggsFolder.Name = "PlacedEggs"
		placedEggsFolder.Parent = worldFolder
	end
	
	local serverEggsFolder = placedEggsFolder:FindFirstChild("Server")
	if not serverEggsFolder then
		serverEggsFolder = Instance.new("Folder")
		serverEggsFolder.Name = "Server"
		serverEggsFolder.Parent = placedEggsFolder
	end

	-- Try to get egg model template
	local trueName = key:split(":")[1]
	local petsAndEggs = Assets:FindFirstChild("Models") and Assets.Models:FindFirstChild("PetsAndEggs")
	local eggFolder = petsAndEggs and petsAndEggs:FindFirstChild("Eggs")
	local eggModelTemplate = eggFolder and eggFolder:FindFirstChild(trueName)
	if not eggModelTemplate then
		-- Create simple egg model if template doesn't exist
		local spherePart = Instance.new("Part")
		spherePart.Name = "EggModel"
		spherePart.Shape = Enum.PartType.Ball
		spherePart.Size = Vector3.new(1, 1.2, 1)
		spherePart.CanCollide = false
		
		local modelParent = Instance.new("Model")
		modelParent.Name = key
		spherePart.Parent = modelParent
		modelParent.PrimaryPart = spherePart
		-- Color based on rarity
		local rarityColors = {
			Common = Color3.fromRGB(163, 162, 165),
			Uncommon = Color3.fromRGB(75, 151, 75),
			Rare = Color3.fromRGB(0, 162, 255),
			Legendary = Color3.fromRGB(170, 0, 255),
			Mythic = Color3.fromRGB(255, 200, 0),
		}
		spherePart.Color = rarityColors[data.Rarity] or rarityColors.Common
		
		eggModelTemplate = modelParent
	else
		eggModelTemplate = eggModelTemplate:Clone()
	end

	-- Clone the template to create the actual egg model
	local eggModel = eggModelTemplate:Clone()
	if not eggModel then
		warn("[PlotService] Failed to clone egg model template for", trueName)
		return
	end

	-- Set anchored and basic properties
	if eggModel:IsA("Model") then
		-- Models don't have Anchored property, only parts
		-- Anchor all parts in the model
		for _, part in pairs(eggModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.Transparency = 1
			end
		end
	elseif eggModel:IsA("BasePart") then
		eggModel.Anchored = true
		part.Transparency = 1
	end

	eggModel.Name = key
	eggModel:SetAttribute("Owner", player.UserId)
	eggModel:SetAttribute("Floor", floor)
	eggModel:SetAttribute("EggKey", key)
	eggModel:SetAttribute("EggName", data.EggName)
	eggModel:SetAttribute("Rarity", data.Rarity or "Common")
	-- FIXED: Use HatchStartTime from egg data (was DatePlanted which didn't exist)
	eggModel:SetAttribute("HatchStartTime", data.HatchStartTime or data.DatePlaced or os.time())
	eggModel:SetAttribute("HatchDuration", data.HatchDuration or 0)
	eggModel:SetAttribute("ExpiresAt", data.ExpiresAt)
	eggModel:SetAttribute("Status", data.Status or "Incubating")

	-- Deserialize and position CFrame
	if data.Location then
		local deseralizedCFrame = CFrame.new(table.unpack(data.Location))
		local rotationOnly = CFrame.fromMatrix(
			Vector3.zero,
			deseralizedCFrame.RightVector,
			deseralizedCFrame.UpVector,
			-deseralizedCFrame.LookVector
		)
		deseralizedCFrame = CFrame.new(
			deseralizedCFrame.Position.X,
			deseralizedCFrame.Position.Y,
			deseralizedCFrame.Position.Z
		) * rotationOnly

		deseralizedCFrame = PlotService.GetPlot(player).ReferencePoint.CFrame:ToWorldSpace(deseralizedCFrame)
		-- Use PivotTo for both Models and Parts
		if eggModel.PrimaryPart or eggModel:IsA("BasePart") then
			eggModel:PivotTo(deseralizedCFrame)
		end
	end

	-- Parent model to server folder
	eggModel.Parent = serverEggsFolder
	print("[PlotService] Created egg server model for", player.Name, "egg key:", key, "model:", eggModel)
end

function PlotService.UpdatePlot(player: Player, action: string, data: any)
	local DataService = CachedModules.Cached.DataService
	local PlayerData = DataService.GetPlayerData(player)

	if PlayerData then
		if action == "potPlaced" then
			local itemKey: string = data.ItemKey
			local floor: number = data.Floor

			local newItemData = PlayerData.Floors.Index[floor].Pots[itemKey]
			if newItemData then
				PlotService.CreatePotServerModel(player, itemKey, newItemData)
			end
		end

		if action == "seedPlanted" then
			local itemKey: string = data.ItemKey
			local floor: number = data.Floor

			local newItemData = PlayerData.Floors.Index[floor].Seeds[itemKey]
			if newItemData then
				PlotService.CreateSeedServerModel(player, itemKey, newItemData)
			end
		end

		if action == "eggPlaced" then
			local itemKey: string = data.ItemKey
			local floor: number = data.Floor

			local newItemData = PlayerData.Floors.Index[floor].Eggs[itemKey]
			if newItemData then
				PlotService.CreateEggServerModel(player, floor, itemKey, newItemData)
			end
		end
	end
end

function PlotService.GetPlantedSeedAtLocation(player: Player, location: CFrame)
	if not location then
		return false
	end

	local instancesToFilter = {}
	local instanceMap = {}

	for _, seedModel in workspace.World.PlantedSeeds.Server:GetChildren() do
		if seedModel:GetAttribute("Owner") == player.UserId and seedModel.PrimaryPart then
			table.insert(instancesToFilter, seedModel.PrimaryPart)
			instanceMap[seedModel.PrimaryPart] = seedModel
		end
	end

	-- print(instancesToFilter)
	if #instancesToFilter == 0 then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = instancesToFilter

	for _, v in instancesToFilter do
		local result = workspace:Raycast(location.Position + Vector3.new(0, 5, 0), Vector3.new(0, -9999, 0), params)
		if result and result.Instance then
			local foundSeedModel = instanceMap[result.Instance]
			if foundSeedModel then
				return true, foundSeedModel
			end
		end
	end

	return false
end

function PlotService.GetPotAtLocation(player: Player, location: CFrame)
	if not location then
		return false
	end

	local instancesToFilter = {}
	local instanceMap = {}

	for _, PotModel in workspace.World.PlacedPots.Server:GetChildren() do
		if PotModel:GetAttribute("Owner") == player.UserId and PotModel.PrimaryPart then
			table.insert(instancesToFilter, PotModel.PrimaryPart)
			instanceMap[PotModel.PrimaryPart] = PotModel
		end
	end

	print(instancesToFilter)
	if #instancesToFilter == 0 then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = instancesToFilter

	for _, v in instancesToFilter do
		local result = workspace:Raycast(location.Position + Vector3.new(0, 5, 0), Vector3.new(0, -9999, 0), params)
		if result and result.Instance then
			local foundPotModel = instanceMap[result.Instance]
			if foundPotModel then
				return true, foundPotModel
			end
		end
	end

	return false
end

function PlotService.Init()
	local DataService = CachedModules.Cached.DataService
	task.spawn(function()
		while task.wait(1) do
			for _, crop: Model in workspace.World.PlantedSeeds.Server:GetChildren() do
				local _plotNumber = crop:GetAttribute("Plot")
				local owner = crop:GetAttribute("Owner")

				local player = Players:GetPlayerByUserId(tonumber(owner))
				if not player then
					continue
				end

				local playerData = DataService.GetPlayerData(player)
				local serverConfig = crop:FindFirstChild("ServerConfiguration")

				if serverConfig then
					local growthPercentage = serverConfig.GrowthPercentage
					local lastGrowthIncrement = serverConfig.LastGrowthIncrement
					local datePlanted = serverConfig.DatePlanted
					local state = serverConfig.State
					local water = serverConfig.Water
					local needWater = serverConfig.NeedWater
					local waterTime = serverConfig.WaterTime

					local seedName = crop.Name:split(":")[1]
					local foundSeed = Seed[seedName]
					local floorIndex = crop:GetAttribute("Floor")
					local potStats = getPotStatsFromSeed(playerData, floorIndex, crop.Name)
					local timeMultiplier = potStats.TimeMul or DEFAULT_POT_STATS.TimeMul
					local potMutationGrowthMul = getPotMutationGrowthSpeedMultiplierFromSeed(playerData, floorIndex, crop.Name)
					local potMutationTimeMultiplier = 1
					if potMutationGrowthMul > 0 then
						potMutationTimeMultiplier = 1 / potMutationGrowthMul
					end
					local activeWeatherData
					do
						local weatherService = getWeatherService()
						activeWeatherData = weatherService and weatherService.ServerWeather and weatherService.ServerWeather.Data or nil
					end

					local weatherGrowthMultiplier = 1
					if activeWeatherData then
						weatherGrowthMultiplier = activeWeatherData.GrowthSpeedMultiplier or 1
					end
					if weatherGrowthMultiplier <= 0 then
						weatherGrowthMultiplier = 1
					end
					-- SunnyWeather gamepass: 2x growth speed (= 50% time reduction)
					if player:GetAttribute("SunnyWeather") == true then
						weatherGrowthMultiplier = weatherGrowthMultiplier * 2
					end
					local weatherTimeMultiplier = 1 / weatherGrowthMultiplier

					local harvestInterval = foundSeed.HarvestIntervalSec
					local currentTime = os.time()
					local elapsedSincePlanted = currentTime - datePlanted.Value
					
					if owner and foundSeed then
						-- Check if this is a tutorial plant that should have frozen growth
						local tutorialService = getTutorialGuideService()
						local _isTutorialPlant = false
						local shouldFreezeGrowth = false
						local shouldBlockAutoWater = false
						
						if tutorialService then
							local isTutorial = tutorialService.IsPlayerInTutorial and tutorialService.IsPlayerInTutorial(player)
							if isTutorial then
								local plantName = seedName
								if plantName == "Lily" then
									_isTutorialPlant = true
									shouldFreezeGrowth = tutorialService.ShouldFreezePlantGrowth and tutorialService.ShouldFreezePlantGrowth(player)
									-- Block auto-water during tutorial so player must water manually
									shouldBlockAutoWater = tutorialService.IsWaitingForWatering and tutorialService.IsWaitingForWatering(player)
								end
							end
						end

						local shouldHideGrowthUI = _isTutorialPlant and shouldFreezeGrowth
						local currentHideGrowthUI = crop:GetAttribute("HideGrowthUI")
						if shouldHideGrowthUI then
							if currentHideGrowthUI ~= true then
								crop:SetAttribute("HideGrowthUI", true)
							end
						elseif currentHideGrowthUI ~= nil then
							crop:SetAttribute("HideGrowthUI", nil)
						end
						
						-- NEW TIME-BASED GROWTH LOGIC
						-- Flow: 5s seed wait → water → 30s sprout 1 → 60s sprout 2 → mature
						
						-- Calculate growth time for GrowthPercentage (still used for harvest timing)
						local growthTime = math.max(
							1,
							foundSeed.GrowTimeSec * timeMultiplier * weatherTimeMultiplier * potMutationTimeMultiplier
						)
						-- Scale sprout stages to match actual growth time (so mature aligns with harvest readiness).
						local totalSproutTime = SPROUT_STAGE_1_DURATION + SPROUT_STAGE_2_DURATION
						local postWaterGrowthTime = math.max(0.1, growthTime - SEED_WAIT_TIME)
						local stage1Ratio = 0.5
						local stage2Ratio = 0.5
						if totalSproutTime > 0 then
							stage1Ratio = SPROUT_STAGE_1_DURATION / totalSproutTime
							stage2Ratio = SPROUT_STAGE_2_DURATION / totalSproutTime
						end
						local sproutStage1Duration = math.max(0.1, postWaterGrowthTime * stage1Ratio)
						local sproutStage2Duration = math.max(0.1, postWaterGrowthTime * stage2Ratio)
						local stage1Value = serverConfig:FindFirstChild("SproutStage1Duration")
						if stage1Value then
							stage1Value.Value = sproutStage1Duration
						end
						local stage2Value = serverConfig:FindFirstChild("SproutStage2Duration")
						if stage2Value then
							stage2Value.Value = sproutStage2Duration
						end
						
						-- SEED STAGE: Before watering (first 5 seconds)
						if water.Value == false then
							-- Check if 5 seconds have elapsed since planting (Requirements 1.1, 1.2, 1.3)
							if elapsedSincePlanted >= SEED_WAIT_TIME and needWater.Value == false then
								needWater.Value = true
								
								-- Notify tutorial system when plant needs water
								if tutorialService and tutorialService.OnPlantStateChanged then
									local cachedState = _tutorialPlantStateCache[owner]
									if not cachedState or not cachedState.NeedsWater then
										_tutorialPlantStateCache[owner] = _tutorialPlantStateCache[owner] or {}
										_tutorialPlantStateCache[owner].NeedsWater = true
										tutorialService.OnPlantStateChanged(player, "NeedsWater", crop)
									end
								end
							end
							
							-- Handle auto-watering from weather or AutoWater gamepass
							if needWater.Value == true then
								local autoWatered = false
								-- Skip auto-water for tutorial plants during watering step
								if not shouldBlockAutoWater then
									local waterService = getWaterService()
									local hasAutoWaterPerk = player:GetAttribute("AutoWater") == true
									local weatherAutoWater = activeWeatherData and activeWeatherData.AutoWatersPlants
									if (weatherAutoWater or hasAutoWaterPerk) and waterService and waterService.AutoWaterPlant then
										autoWatered = waterService.AutoWaterPlant(crop) == true
									end
								end

								-- GROWTH PAUSE: While waiting for water (Requirements 1.4)
								if not autoWatered then
									-- Increment DatePlanted to track wait time (pause growth)
									datePlanted.Value += 1
									continue
								end
							end
							
							-- Keep state at 1 during seed stage
							state.Value = 1
							
						else
							-- AFTER WATERING: Time-based stage transitions
							local actualWaterTime = waterTime.Value
							-- Backward compatibility: estimate WaterTime if not set
							if actualWaterTime == 0 then
								actualWaterTime = datePlanted.Value + SEED_WAIT_TIME
							end
							
							if shouldFreezeGrowth then
								-- Keep plant at sprout stage 1 during tutorial bug catch step
								local maxElapsed = math.max(0, sproutStage1Duration - 0.1)
								local frozenElapsed = math.min(currentTime - actualWaterTime, maxElapsed)
								if currentTime - lastGrowthIncrement.Value >= 1 then
									lastGrowthIncrement.Value = currentTime
									waterTime.Value = currentTime - frozenElapsed
									datePlanted.Value = waterTime.Value - SEED_WAIT_TIME
									growthPercentage.Value = math.clamp(((currentTime - datePlanted.Value) / growthTime) * 100, 0, 49)
								end
								actualWaterTime = waterTime.Value
							end
							
							local elapsedSinceWatering = currentTime - actualWaterTime
							
							-- Determine current stage based on time since watering
							-- State 1: Sprout Stage 1 (0-30 seconds after watering) - Requirements 2.1, 2.2
							-- State 2: Sprout Stage 2 (30-90 seconds after watering) - Requirements 3.1, 3.2
							-- State 3: Mature Stage (90+ seconds after watering) - Requirements 4.1
							
							local previousState = state.Value
							if shouldFreezeGrowth then
								state.Value = 1
							elseif elapsedSinceWatering < sproutStage1Duration then
								-- Sprout Stage 1: 0-30 seconds after watering
								state.Value = 1
							elseif elapsedSinceWatering < sproutStage1Duration + sproutStage2Duration then
								-- Sprout Stage 2: 30-90 seconds after watering (Requirements 3.1, 6.2)
								state.Value = 2
							else
								-- Mature Stage: 90+ seconds after watering (Requirements 4.1, 6.3)
								state.Value = 3
							end

							-- NOTE: Harvest prompts are created client-side when state changes to 3
							-- Client PlantReplicator handles prompt creation and CanHarvest sync

							-- Update GrowthPercentage based on total elapsed time (for harvest timing)
							if not shouldFreezeGrowth then
								if currentTime - lastGrowthIncrement.Value >= 1 then
									lastGrowthIncrement.Value = currentTime
									growthPercentage.Value = math.clamp(((currentTime - datePlanted.Value) / growthTime) * 100, 0, 100)
								end
							end
							
							-- Handle harvest when growth is complete (Requirements 4.2, 4.3)
							if growthPercentage.Value >= 100 then
								if foundSeed.HarvestCount > 1 then
									-- Check if plant has remaining harvests (multi-harvest limit)
									local plantData = playerData.Floors.Index[floorIndex] and playerData.Floors.Index[floorIndex].Seeds[crop.Name]
									local harvestsRemaining = plantData and plantData.HarvestsRemaining
									local canRegrow = harvestsRemaining == nil or harvestsRemaining > 0

									for _, fruit in serverConfig.Fruits:GetChildren() do
										local lastHarvest = fruit.LastHarvest
										local delta = (currentTime - datePlanted.Value) - foundSeed.GrowTimeSec
										if lastHarvest.Value - datePlanted.Value > 0 and delta > 0 and delta < (2 * harvestInterval) then
											lastHarvest.Value = currentTime - harvestInterval
										end
										local canHarvest = fruit.CanHarvest
										-- Only allow regrow if plant has remaining harvests
										if canRegrow and currentTime - lastHarvest.Value >= harvestInterval then
											fruit.SizeScaling.Value = 1
											canHarvest.Value = true
										elseif not canRegrow then
											canHarvest.Value = false
										else
											canHarvest.Value = false
										end
									end
								else
									local folder = serverConfig.Fruits["1"]
									if not folder.CanHarvest.Value then
										folder.CanHarvest.Value = true
										
										-- Notify tutorial system when plant is ready to harvest
										if tutorialService and tutorialService.OnPlantStateChanged then
											local cachedState = _tutorialPlantStateCache[owner]
											if not cachedState or not cachedState.ReadyToHarvest then
												_tutorialPlantStateCache[owner] = _tutorialPlantStateCache[owner] or {}
												_tutorialPlantStateCache[owner].ReadyToHarvest = true
												tutorialService.OnPlantStateChanged(player, "ReadyToHarvest", crop)
											end
										end
									end
								end

								local activeWeatherName
								do
									local weatherService = getWeatherService()
									activeWeatherName = weatherService and weatherService.ServerWeather and weatherService.ServerWeather.Name or nil
								end
								local SetMutationLimit = 3
								if os.time() - lastGrowthIncrement.Value <= SetMutationLimit and activeWeatherName then
									if foundSeed.HarvestCount > 1 then
										for _, fruit in serverConfig.Fruits:GetChildren() do
											local mutation = fruit:FindFirstChild("Mutations")
											mutation.Value = activeWeatherName
										end
									else
										local folder = serverConfig.Fruits["1"]
										local mutation = folder:FindFirstChild("Mutations")
										mutation.Value = activeWeatherName
									end
								end
							end
						end
					end
				end
			end
		end
	end)
end

-- Export function to reset tutorial plant state cache (called by TutorialGuideService when step changes)
function PlotService.ResetTutorialPlantStateCache(player: Player, state: string?)
	if player then
		resetTutorialPlantStateCache(player.UserId, state)
	end
end

return PlotService
