_, CraftSim = ...

---@class CraftSim.ResultData
---@field recipeData CraftSim.RecipeData
---@field itemsByQuality ItemMixin[]
---@field expectedQuality number
---@field expectedQualityInspiration number
---@field expectedQualityHSV number
---@field expectedQualityInspirationHSV number
---@field expectedQualityUpgrade number
---@field expectedItem? ItemMixin
---@field expectedItemUpgrade? ItemMixin
---@field canUpgradeQuality boolean
---@field expectedItemInspiration? ItemMixin
---@field expectedItemHSV? ItemMixin
---@field expectedItemInspirationHSV? ItemMixin

local print = CraftSim.UTIL:SetDebugPrint(CraftSim.CONST.DEBUG_IDS.EXPORT_V2)

CraftSim.ResultData = CraftSim.Object:extend()

---@param recipeData CraftSim.RecipeData
function CraftSim.ResultData:new(recipeData)
    if not recipeData then
        return
    end
    self.recipeData = recipeData
    self.itemsByQuality = {}
    self.canUpgradeQuality = false
    self.expectedQuality = 1
    self.expectedQualityUpgrade = 1
    self.expectedQualityInspiration = 1
    self.expectedQualityHSV = 1
    self.expectedQualityInspirationHSV = 1

    self:UpdatePossibleResultItems()
end

--- Updates based on reagentData
function CraftSim.ResultData:UpdatePossibleResultItems()
    local recipeData = self.recipeData

    -- TODO: only need to update possible list for gear as everything else is static
    self.itemsByQuality = {}
    local craftingReagentInfoTbl = recipeData.reagentData:GetCraftingReagentInfoTbl()

    if recipeData.isEnchantingRecipe then
        if not CraftSim.ENCHANT_RECIPE_DATA[recipeData.recipeID] then
            error("CraftSim: Enchant Recipe Missing in Data: " .. recipeData.recipeID .. " Please contact the developer (discord: genju#4210)")
        end
        local itemIDs = {
            CraftSim.ENCHANT_RECIPE_DATA[recipeData.recipeID].q1,
            CraftSim.ENCHANT_RECIPE_DATA[recipeData.recipeID].q2,
            CraftSim.ENCHANT_RECIPE_DATA[recipeData.recipeID].q3,
        }

        for _, itemID in pairs(itemIDs) do
            table.insert(self.itemsByQuality, Item:CreateFromItemID(itemID))
        end
    elseif recipeData.isGear then
        local itemLinks = CraftSim.DATAEXPORT:GetDifferentQualitiesByCraftingReagentTbl(recipeData.recipeID, craftingReagentInfoTbl, recipeData.allocationItemGUID, recipeData.maxQuality)
    
        for _, itemLink in pairs(itemLinks) do
            table.insert(self.itemsByQuality, Item:CreateFromItemLink(itemLink))
        end
    else 
        local itemIDs = CraftSim.DATAEXPORT:GetDifferentQualityIDsByCraftingReagentTbl(recipeData.recipeID, craftingReagentInfoTbl, recipeData.allocationItemGUID)
        for _, itemID in pairs(itemIDs) do
            table.insert(self.itemsByQuality, Item:CreateFromItemID(itemID))
        end
    end
end

--- Updates based on professionStats and reagentData
function CraftSim.ResultData:Update()
    local recipeData = self.recipeData   

    if recipeData.isGear then
        self:UpdatePossibleResultItems()
    end

    -- based on stats predict the resulting items if there are any

    if #self.itemsByQuality == 0 then
        print("ResultData: No OutputItems")
        return
    end

    local craftingReagentInfoTbl = recipeData.reagentData:GetCraftingReagentInfoTbl()
    local professionStats = self.recipeData.professionStats
    local updatedOperationInfo = C_TradeSkillUI.GetCraftingOperationInfo(recipeData.recipeID, craftingReagentInfoTbl, self.recipeData.allocationItemGUID)

    if not updatedOperationInfo then
        print("Could not update resultData: No OperationInfo")
        return
    end

    self.expectedQuality = updatedOperationInfo.craftingQuality
    self.expectedItem = self.itemsByQuality[self.expectedQuality]

    if self.expectedQuality == self.recipeData.maxQuality then
        return
    end

    if not recipeData.supportsQualities or not recipeData.supportsInspiration then
        return
    end

    -- TODO: new util function? V2 ?
    local function expectedQualityBySkill(skill, maxQuality, recipeDifficulty)
        local thresholds = CraftSim.AVERAGEPROFIT:GetQualityThresholds(maxQuality, recipeDifficulty, CraftSimOptions.breakPointOffset)
        local expectedQuality = 1

        for _, threshold in pairs(thresholds) do
            if skill >= threshold then
                expectedQuality = expectedQuality + 1
            end
        end

        return expectedQuality
    end

    local skillInspiration = professionStats.skill.value + professionStats.inspiration.extraValue
    local maxHSVSkill = professionStats.recipeDifficulty.value * 0.05
    local skillHSV = professionStats.skill.value + maxHSVSkill
    local skillInspirationHSV = professionStats.skill.value + professionStats.inspiration.extraValue + maxHSVSkill

    local qualityInspiration = expectedQualityBySkill(skillInspiration, recipeData.maxQuality, professionStats.recipeDifficulty.value)
    local qualityHSV = expectedQualityBySkill(skillHSV, recipeData.maxQuality, professionStats.recipeDifficulty.value)
    local qualityInspirationHSV = expectedQualityBySkill(skillInspirationHSV, recipeData.maxQuality, professionStats.recipeDifficulty.value)

    self.expectedQualityUpgrade = math.max(self.expectedQuality, qualityInspiration, qualityHSV, qualityInspirationHSV)
    self.expectedQualityInspiration = qualityInspiration
    self.expectedQualityHSV = qualityHSV
    self.expectedQualityInspirationHSV = qualityInspirationHSV

    if self.expectedQuality < self.expectedQualityUpgrade then
        self.canUpgradeQuality = true
    end

    self.expectedItemInspiration = self.itemsByQuality[qualityInspiration]
    self.expectedItemHSV = self.itemsByQuality[qualityHSV]
    self.expectedItemInspirationHSV = self.itemsByQuality[qualityInspirationHSV]
    self.expectedItemUpgrade = self.itemsByQuality[self.expectedQualityUpgrade]
end

function CraftSim.ResultData:Debug()
    local debugLines = {}
    for q, item in pairs(self.itemsByQuality) do
        table.insert(debugLines, "Possible Result Q" .. q .. " " .. (item:GetItemLink() or item:GetItemID()))
    end
    return CraftSim.UTIL:Concat({debugLines, 
        {
            "expectedQuality: " .. tostring(self.expectedQuality),
            "expectedQualityUpgrade: " .. tostring(self.expectedQualityUpgrade),
            "expectedQualityInspiration: " .. tostring(self.expectedQualityInspiration),
            "expectedQualityHSV: " .. tostring(self.expectedQualityHSV),
            "expectedQualityInspirationHSV: " .. tostring(self.expectedQualityInspirationHSV),
            "expectedItem: " .. tostring(self.expectedItem and self.expectedItem:GetItemLink()),
            "expectedItemUpgrade: " .. tostring(self.expectedItemUpgrade and self.expectedItemUpgrade:GetItemLink()),
            "canUpgradeQuality: " .. tostring(self.canUpgradeQuality),
            "expectedItemInspiration: " .. tostring(self.expectedItemInspiration and self.expectedItemInspiration:GetItemLink()),
            "expectedItemHSV: " .. tostring(self.expectedItemHSV and self.expectedItemHSV:GetItemLink()),
            "expectedItemInspirationHSV: " .. tostring(self.expectedItemInspirationHSV and self.expectedItemInspirationHSV:GetItemLink()),
        }
    })
end

function CraftSim.ResultData:Copy(recipeData)
    local copy = CraftSim.ResultData(recipeData)
    return  copy
end

---@class CraftSim.ResultData.Serialized
---@field itemLinksByQuality string[]
---@field expectedQuality number
---@field expectedQualityInspiration number
---@field expectedQualityHSV number
---@field expectedQualityInspirationHSV number
---@field expectedQualityUpgrade number
---@field canUpgradeQuality boolean
---@field expectedItemLink? string
---@field expectedItemLinkUpgrade? string
---@field expectedItemLinkInspiration? string
---@field expectedItemLinkHSV? string
---@field expectedItemLinkInspirationHSV? string

--- Make sure that the items are loaded before serializing or the links are empty
function CraftSim.ResultData:Serialize()
    local serialized = {}
    serialized.itemLinksByQuality = CraftSim.UTIL:Map(self.itemsByQuality, function (item)
        return item:GetItemLink()
    end)
    serialized.expectedQuality = self.expectedQuality
    serialized.expectedQualityInspiration = self.expectedQualityInspiration
    serialized.expectedQualityHSV = self.expectedQualityHSV
    serialized.expectedQualityInspirationHSV = self.expectedQualityInspirationHSV
    serialized.expectedQualityUpgrade = self.expectedQualityUpgrade
    serialized.canUpgradeQuality = self.canUpgradeQuality
    serialized.expectedItemLink = (self.expectedItem and self.expectedItem:GetItemLink()) or nil
    serialized.expectedItemLinkUpgrade = (self.expectedItemUpgrade and self.expectedItemUpgrade:GetItemLink()) or nil
    serialized.expectedItemLinkInspiration = (self.expectedItemInspiration and self.expectedItemInspiration:GetItemLink()) or nil
    serialized.expectedItemLinkHSV = (self.expectedItemHSV and self.expectedItemHSV:GetItemLink()) or nil
    serialized.expectedItemLinkInspirationHSV = (self.expectedItemInspirationHSV and self.expectedItemInspirationHSV:GetItemLink()) or nil
    return serialized
end

--- Will not contain a reference to a recipeData instance
---@param serializedResultData CraftSim.ResultData.Serialized
---@return CraftSim.ResultData
function CraftSim.ResultData:Deserialize(serializedResultData)
    local deserialized = CraftSim.ResultData()
    deserialized.itemsByQuality = CraftSim.UTIL:Map(serializedResultData.itemLinksByQuality, function (itemLink)
        return Item:CreateFromItemLink(itemLink)
    end)
    deserialized.expectedQuality = tonumber(serializedResultData.expectedQuality)
    deserialized.expectedQualityInspiration = tonumber(serializedResultData.expectedQualityInspiration)
    deserialized.expectedQualityHSV = tonumber(serializedResultData.expectedQualityHSV)
    deserialized.expectedQualityInspirationHSV = tonumber(serializedResultData.expectedQualityInspirationHSV)
    deserialized.expectedQualityUpgrade = tonumber(serializedResultData.expectedQualityUpgrade)
    deserialized.canUpgradeQuality = not not serializedResultData.canUpgradeQuality
    deserialized.expectedItem = (serializedResultData.expectedItemLink and deserialized.itemsByQuality[deserialized.expectedQuality]) or nil
    deserialized.expectedItemUpgrade = (serializedResultData.expectedItemLinkUpgrade and deserialized.itemsByQuality[deserialized.expectedQualityUpgrade]) or nil
    deserialized.expectedItemInspiration = (serializedResultData.expectedItemLinkInspiration and deserialized.itemsByQuality[deserialized.expectedQualityInspiration]) or nil
    deserialized.expectedItemHSV = (serializedResultData.expectedItemLinkHSV and deserialized.itemsByQuality[deserialized.expectedQualityHSV]) or nil
    deserialized.expectedItemInspirationHSV = (serializedResultData.expectedItemLinkInspirationHSV and deserialized.itemsByQuality[deserialized.expectedQualityInspirationHSV]) or nil
    return deserialized
end