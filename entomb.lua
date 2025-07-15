-- Entomb corpse items of any dead unit.
--@module = true

local utils = require('utils')

local unit_id
local unit
local building_id
local tomb
local forceBurial

local args = {...}

-- Get unit from selected corpse or corpse piece item.
local function GetUnitFromCorpse()
    local item = dfhack.gui.getSelectedItem(true)
    if item then
        if df.item_corpsest:is_instance(item) or df.item_corpsepiecest:is_instance(item) then
            unit_id = item.unit_id
            unit = df.unit.find(unit_id)
        else
            qerror('Selected item is not a corpse or body part.')
        end
    else
        qerror('No item selected or unit specified.')
    end
end

-- Validate tomb zone assignment.
local function CheckTombZone(building, id)
    if df.building_civzonest:is_instance(building) then
        if building.type == 97 then
            if building.assigned_unit_id == id then
                return true
            end
        end
    end
end

-- Iterate through all available tomb zones.
local function IterateTombZone(id)
    for _, building in pairs(df.global.world.buildings.all) do
        if CheckTombZone(building, id) then return building end
    end
end

-- Check if any of the unit's corpse items are still not in a coffin.
local function isNotBuried()
    for _, item_id in pairs(unit.corpse_parts) do
        local item = df.item.find(item_id)
        if item then
            local inCoffin = dfhack.items.getGeneralRef(item, df.general_ref_type.BUILDING_HOLDER)
            local coffinBuilding_id = inCoffin and inCoffin.building_id or nil
            local coffin = coffinBuilding_id and df.building.find(coffinBuilding_id) or nil
            local isCoffin = coffin and df.building_coffinst:is_instance(coffin) or nil
            -- Return TRUE if even one item is not interred.
            if not isCoffin then
                return true
            end
        end
    end
end

local function GetEmptyTombZone()
    -- Check if unit is already assigned to a tomb zone.
    local isAlreadyAssigned = IterateTombZone(unit_id)
    if isAlreadyAssigned then
        if isNotBuried() or forceBurial then
            tomb = isAlreadyAssigned
            print('Unit is already assigned to a tomb zone but may still have uninterred corpse or body part(s).')
        else
            qerror('Unit is already interred in a tomb zone.')
        end
    else
        -- Find an unassigned tomb zone.
        tomb = IterateTombZone(-1)
    end
    if not tomb then
        qerror('No unassigned tomb zones are available.')
    end
end

-- Set corpse items to be valid for burial.
local function FlagForBurial(corpseParts)
    -- Undead units have empty corpse_parts vector.
    if unit.enemy.undead then
        for _, item in pairs(df.global.world.items.other.IN_PLAY) do
            if df.item_corpsest:is_instance(item) or df.item_corpsepiecest:is_instance(item) then
                if item.unit_id == unit_id then
                    corpseParts:insert(#corpseParts, item.id)
                end
            end
        end
        utils.sort_vector(corpseParts)
    end
    local burialItemCount = 0
    for _, item_id in pairs(corpseParts) do
        local item = df.item.find(item_id)
        if item then
            item.flags.dead_dwarf = true
            -- Some corpse items may be lost/destroyed before burial.
            burialItemCount = burialItemCount + 1
        end
    end
    if burialItemCount == 0 then
        qerror('Unit has no corpse or body parts available for burial.')
    end
    tomb.assigned_unit_id = unit_id
    return burialItemCount
end

local function PutInCoffin(corpseParts)
    local coffin
    for _, building in pairs(tomb.contained_buildings) do
        if df.building_coffinst:is_instance(building) then coffin = building end
    end
    if coffin then
        -- Set df.building_item_role_type.PERM first before changing
        -- it to TEMP to turn it into an interred corpse item.
        for _, item_id in pairs(corpseParts) do
            local item = df.item.find(item_id)
            if item then
                dfhack.items.moveToBuilding(item, coffin, 2)
            end
        end
        for _, buildingItem in pairs(coffin.contained_items) do
            local item = buildingItem.item
            if not df.item_coffinst:is_instance(item) then
                buildingItem.use_mode = 0
            end
        end
        print('Corpse items have been teleported into a coffin.')
    else
        print('No coffin in the assigned tomb zone.\nCorpse items will not be teleported into the tomb zone.')
    end
end

local function AssignToTomb()
    local corpseParts = unit.corpse_parts
    local strBurial = '%s assigned to a tomb zone for burial.'
    local strCorpseItems = '(%d corpse or body part%s)'
    local strUnitName = unit and dfhack.units.getReadableName(unit)
    local strPlural = ''
    local incident_id = unit.counters.death_id
    if incident_id ~= -1 then
        local incident = df.incident.find(incident_id)
        -- Corpse will not be interred if not yet discovered.
        incident.flags.discovered = true
    end
    local burialItemCount = FlagForBurial(corpseParts)
    print(string.format(strBurial, strUnitName))
    if forceBurial then PutInCoffin(corpseParts) end
    if burialItemCount > 1 then strPlural = 's' end
    print(string.format(strCorpseItems, burialItemCount, strPlural))
end

local function parseArgs()
    local building
    if #args > 0 then
        for i, v in ipairs(args) do
            if v == 'unit' then
                unit_id = tonumber(args[i+1]) or nil
                unit = unit_id and df.unit.find(unit_id)
                if not unit then qerror('Invalid unit ID.') end
            end
            if v == 'tomb' then
                building_id = tonumber(args[i+1]) or nil
                building = building_id and df.building.find(building_id)
                if not building then qerror('Invalid zone ID.') end
                -- Check if tomb zone is unassigned.
                if CheckTombZone(building, -1) then
                    tomb = building
                else
                    qerror('Specified zone ID does not point to an unassigned tomb zone.')
                end
            end
            if v == 'now' then forceBurial = true end
        end
    end
end

local function Main()
    parseArgs()
    if not unit then GetUnitFromCorpse() end
    if unit then
        if not tomb then GetEmptyTombZone() end
        if tomb then AssignToTomb() end
    end
end

if not dfhack_flags.module then
    Main()
end
