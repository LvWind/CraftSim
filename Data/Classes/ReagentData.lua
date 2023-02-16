_, CraftSim = ...



---@class CraftSim.ReagentData
---@field recipeData CraftSim.RecipeData
---@field requiredReagents CraftSim.Reagent[]
---@field optionalReagentSlots CraftSim.OptionalReagentSlot[]
---@field finishingReagentSlots CraftSim.OptionalReagentSlot[]
---@field salvageReagentSlot CraftSim.SalvageReagentSlot

local print = CraftSim.UTIL:SetDebugPrint(CraftSim.CONST.DEBUG_IDS.EXPORT_V2)

CraftSim.ReagentData = CraftSim.Object:extend()

function CraftSim.ReagentData:new(recipeData, schematicInfo)
    self.recipeData = recipeData
    self.requiredReagents = {}
    self.optionalReagentSlots = {}
    self.finishingReagentSlots = {}
    self.salvageReagentSlot = CraftSim.SalvageReagentSlot(self.recipeData)

    if not schematicInfo then
        return
    end
    for _, reagentSlotSchematic in pairs(schematicInfo.reagentSlotSchematics) do
        local reagentType = reagentSlotSchematic.reagentType
        -- for now only consider the required reagents
        if reagentType == CraftSim.CONST.REAGENT_TYPE.REQUIRED then

            table.insert(self.requiredReagents, CraftSim.Reagent(reagentSlotSchematic))
        
        elseif reagentType == CraftSim.CONST.REAGENT_TYPE.OPTIONAL then
            table.insert(self.optionalReagentSlots, CraftSim.OptionalReagentSlot(self.recipeData, reagentSlotSchematic))
        elseif reagentType == CraftSim.CONST.REAGENT_TYPE.FINISHING_REAGENT then
            table.insert(self.finishingReagentSlots, CraftSim.OptionalReagentSlot(self.recipeData, reagentSlotSchematic))
        end
    end
end

---Serializes the required reagents list for sending via the addon channel
---@return CraftSim.Reagent.Serialized[]
function CraftSim.ReagentData:SerializeReagents()
    return CraftSim.UTIL:Map(self.requiredReagents, function (reagent)
        return reagent:Serialize()
    end)
end

function CraftSim.ReagentData:SerializeOptionalReagentSlots()
    return CraftSim.UTIL:Map(self.optionalReagentSlots, function (slot)
        return slot:Serialize()
    end)
end

function CraftSim.ReagentData:SerializeFinishingReagentSlots()
    return CraftSim.UTIL:Map(self.finishingReagentSlots, function (slot)
        return slot:Serialize()
    end)
end


function CraftSim.ReagentData:GetProfessionStatsByOptionals()
    local totalStats = CraftSim.ProfessionStats()

    local optionalStats = CraftSim.UTIL:Map(CraftSim.UTIL:Concat({self.optionalReagentSlots, self.finishingReagentSlots}), 
        function (slot)
            if slot.activeReagent then
                return slot.activeReagent.professionStats
            end
        end)

    table.foreach(optionalStats, function (_, stat)
        totalStats:add(stat)
    end)

    return totalStats
end

---@param itemID number
function CraftSim.ReagentData:GetReagentQualityIDByItemID(itemID)
    local qualityID = 0
    for _, reagent in pairs(self.requiredReagents) do
        local reagentItem = CraftSim.UTIL:Find(reagent.items, function (reagentItem)
            return reagentItem.item:GetItemID() == itemID
        end)
        if reagentItem then
            return reagentItem.qualityID
        end
    end
    return qualityID
end

---@return CraftingReagentInfo[]
function CraftSim.ReagentData:GetCraftingReagentInfoTbl()

    local required = self:GetRequiredCraftingReagentInfoTbl()
    local optionals = self:GetOptionalCraftingReagentInfoTbl()

    return CraftSim.UTIL:Concat({required, optionals})
end

function CraftSim.ReagentData:GetOptionalCraftingReagentInfoTbl()
    local craftingReagentInfoTbl = {}

    -- optional/finishing
    for _, slot in pairs(CraftSim.UTIL:Concat({self.optionalReagentSlots, self.finishingReagentSlots})) do
        local craftingReagentInfo = slot:GetCraftingReagentInfo()
        if craftingReagentInfo then
            table.insert(craftingReagentInfoTbl, craftingReagentInfo)
        end
    end

    return craftingReagentInfoTbl
end

function CraftSim.ReagentData:GetRequiredCraftingReagentInfoTbl()
    local craftingReagentInfoTbl = {}

    -- required
    for _, reagent in pairs(self.requiredReagents) do
        local craftingReagentInfos = reagent:GetCraftingReagentInfos()
        craftingReagentInfoTbl = CraftSim.UTIL:Concat({craftingReagentInfoTbl, craftingReagentInfos})
    end

    return craftingReagentInfoTbl
end

---@param itemID number
function CraftSim.ReagentData:SetOptionalReagent(itemID)
    for _, slot in pairs(CraftSim.UTIL:Concat({self.optionalReagentSlots, self.finishingReagentSlots})) do
        local optionalReagent = CraftSim.UTIL:Find(slot.possibleReagents, 
            function (optionalReagent) 
                return optionalReagent.item:GetItemID() == itemID 
            end)

        if optionalReagent then
            slot.activeReagent = optionalReagent
            return
        end
    end

    print("Error: recipe does not support optional reagent: " .. tostring(itemID))
end

function CraftSim.ReagentData:ClearOptionalReagents()
    for _, slot in pairs(CraftSim.UTIL:Concat({self.optionalReagentSlots, self.finishingReagentSlots})) do
        slot.activeReagent = nil
    end
end

function CraftSim.ReagentData:GetMaxSkillFactor()
    local maxQualityReagentsCraftingTbl = CraftSim.UTIL:Map(self.requiredReagents, function(rr) 
        return rr:GetCraftingReagentInfoByQuality(3, true)
    end)

    print("max quality reagents crafting tbl:")
    print(maxQualityReagentsCraftingTbl, true)

    local recipeID = self.recipeData.recipeID
    local baseOperationInfo = C_TradeSkillUI.GetCraftingOperationInfo(recipeID, {}, self.recipeData.allocationItemGUID)
    local operationInfoWithReagents = C_TradeSkillUI.GetCraftingOperationInfo(recipeID, maxQualityReagentsCraftingTbl, self.recipeData.allocationItemGUID)

    if baseOperationInfo and operationInfoWithReagents then
        
        local baseSkill = baseOperationInfo.baseSkill + baseOperationInfo.bonusSkill
        local skillWithReagents = operationInfoWithReagents.baseSkill + operationInfoWithReagents.bonusSkill

        local maxSkill = skillWithReagents - baseSkill

        local maxReagentIncreaseFactor = self.recipeData.baseProfessionStats.recipeDifficulty.value / maxSkill

        print("ReagentData: maxReagentIncreaseFactor: " .. tostring(maxReagentIncreaseFactor))

        local percentFactor = (100 / maxReagentIncreaseFactor) / 100

        print("ReagentData: maxReagentIncreaseFactor % of difficulty: " .. tostring(percentFactor) .. " %")

        return percentFactor
    end

    print("ReagentData: Could not determine max reagent skill factor: operationInfos nil")
end

function CraftSim.ReagentData:GetSkillFromRequiredReagents()
    local requiredTbl = self:GetRequiredCraftingReagentInfoTbl()

    local recipeID = self.recipeData.recipeID

    local baseOperationInfo = C_TradeSkillUI.GetCraftingOperationInfo(recipeID, {}, self.recipeData.allocationItemGUID)
    local operationInfoWithReagents = C_TradeSkillUI.GetCraftingOperationInfo(recipeID, requiredTbl, self.recipeData.allocationItemGUID)

    if baseOperationInfo and operationInfoWithReagents then
        
            local baseSkill = baseOperationInfo.baseSkill + baseOperationInfo.bonusSkill
            local skillWithReagents = operationInfoWithReagents.baseSkill + operationInfoWithReagents.bonusSkill

            return skillWithReagents - baseSkill
    end
    print("ReagentData: Could not determine required reagent skill: operationInfos nil")
    return 0
end

function CraftSim.ReagentData:EqualsQualityReagents(reagents)
    -- order can be different?
    for _, reagent in pairs(self.requiredReagents) do
        if reagent.hasQuality then
            for _, reagentItem in pairs(reagent.items) do
                local foundReagent = nil
                for _, bestReagent in pairs(reagents) do
                    foundReagent = CraftSim.UTIL:Find(bestReagent.items, function(r) return r.item:GetItemID() == reagentItem.item:GetItemID() end)
                    if foundReagent then
                        if reagentItem.quantity ~= foundReagent.quantity then
                            return false
                        end
                    end
                end
            end
        end
    end

    return true
end

---@param qualityID number
function CraftSim.ReagentData:SetReagentsMaxByQuality(qualityID)
    if not qualityID or qualityID < 1 or qualityID > 3 then
        error("CraftSim.ReagentData:SetReagentsMaxByQuality(qualityID) -> qualityID has to be between 1 and 3")
    end
    table.foreach(self.requiredReagents, function (_, reagent)
        if reagent.hasQuality then
            reagent:Clear()
            reagent.items[qualityID].quantity = reagent.requiredQuantity
        end
    end)
end

---@param optimizationResult? CraftSim.ReagentOptimizationResult
function CraftSim.ReagentData:SetReagentsByOptimizationResult(optimizationResult)
    if not optimizationResult then
        return
    end
    local reagentItemList = optimizationResult:GetReagentItemList()
    self.recipeData:SetReagents(reagentItemList)
end

function CraftSim.ReagentData:Debug()
    local debugLines = {}
    for _, reagent in pairs(self.requiredReagents) do
        local q1 = reagent.items[1].quantity
        local q2 = 0
        local q3 = 0
        if reagent.hasQuality then
            q1 = reagent.items[1].quantity
            q2 = reagent.items[2].quantity  
            q3 = reagent.items[3].quantity
            table.insert(debugLines, (reagent.items[1].item:GetItemLink() or reagent.items[1].item:GetItemID()) .. " " .. q1 .. " | " .. q2 .. " | " .. q3 .. " / " .. reagent.requiredQuantity)
        else
            table.insert(debugLines, (reagent.items[1].item:GetItemLink() or reagent.items[1].item:GetItemID()) .. " " .. q1 .. " / " .. reagent.requiredQuantity)
        end
    end

    table.insert(debugLines, "Optional Reagent Slots: " .. tostring(#self.optionalReagentSlots))
    for i, slot in pairs(self.optionalReagentSlots) do
        debugLines = CraftSim.UTIL:Concat({debugLines, slot:Debug()})
    end
    table.insert(debugLines, "Finishing Reagent Slots: ".. tostring(#self.finishingReagentSlots))
    for i, slot in pairs(self.finishingReagentSlots) do
        debugLines = CraftSim.UTIL:Concat({debugLines, slot:Debug()})
    end

    table.insert(debugLines, "Salvage Reagent Slot: " .. tostring(#self.salvageReagentSlot.possibleItems))
    debugLines = CraftSim.UTIL:Concat({debugLines, self.salvageReagentSlot:Debug()})

    return debugLines
end

function CraftSim.ReagentData:Copy(recipeData)
    local copy = CraftSim.ReagentData(recipeData)

    copy.requiredReagents = CraftSim.UTIL:Map(self.requiredReagents, function(r) return r:Copy() end)
    copy.optionalReagentSlots = CraftSim.UTIL:Map(self.optionalReagentSlots, function(r) return r:Copy(recipeData) end)
    copy.finishingReagentSlots = CraftSim.UTIL:Map(self.finishingReagentSlots, function(r) return r:Copy(recipeData) end)

    return copy
end