-- Prevents a "loyalty cascade" (intra-fort civil war) when a citizen is killed.

local makeown = reqscript('makeown')

-- Checks if a unit is a former member of a given entity as well as it's
-- current enemy.
local function getUnitRenegade(unit, entity_id)
    local unit_entity_links = df.historical_figure.find(unit.hist_figure_id).entity_links
    local former_index = nil
    local enemy_index = nil

    for index, link in pairs(unit_entity_links) do
        local link_type = link:getType()

        if link.entity_id ~= entity_id then
            goto skipentity
        end

        if link_type == df.histfig_entity_link_type.FORMER_MEMBER then
            former_index = index
        elseif link_type == df.histfig_entity_link_type.ENEMY then
            enemy_index = index
        end

        :: skipentity ::
    end

    return former_index, enemy_index
end

local function convertUnit(unit, entity_id, former_index, enemy_index)
    local unit_entity_links = df.historical_figure.find(unit.hist_figure_id).entity_links

    unit_entity_links:erase(math.max(former_index, enemy_index))
    unit_entity_links:erase(math.min(former_index, enemy_index))

    -- Creates a new entity link to the player's civilization/group.
    unit_entity_links:insert('#', df.histfig_entity_link_memberst{
        entity_id = entity_id,
        link_strength = 100
    })
end

local function fixUnit(unit)
    local fixed = false

    local unit_name = dfhack.units.getReadableName(unit)
    local former_civ_index, enemy_civ_index = getUnitRenegade(unit, df.global.plotinfo.civ_id)
    local former_group_index, enemy_group_index = getUnitRenegade(unit, df.global.plotinfo.group_id)

    -- If the unit is a former member of your civilization, as well as now an
    -- enemy of it, we make it become a member again.
    if former_civ_index and enemy_civ_index then
        local civ_name = dfhack.translation.translateName(df.historical_entity.find(df.global.plotinfo.civ_id).name)

        convertUnit(unit, df.global.plotinfo.civ_id, former_civ_index, enemy_civ_index)

        dfhack.gui.showAnnouncement(
            ('loyaltycascade: %s is now a happy member of %s again'):format(unit_name, civ_name), COLOR_WHITE)

        fixed = true
    end

    if former_group_index and enemy_group_index then
        local group_name = dfhack.translation.translateName(df.historical_entity.find(df.global.plotinfo.group_id).name)

        convertUnit(unit, df.global.plotinfo.group_id, former_group_index, enemy_group_index)

        dfhack.gui.showAnnouncement(
            ('loyaltycascade: %s is now a happy member of %s again'):format(unit_name, group_name), COLOR_WHITE)

        fixed = true
    end

    if fixed then
        makeown.clear_enemy_status(unit)
    end

    return false
end

local count = 0
for _, unit in pairs(dfhack.units.getCitizens()) do
    if fixUnit(unit) then
        count = count + 1
    end
end

if count > 0 then
    print(('Fixed %s units from a loyalty cascade.'):format(count))
else
    print('No loyalty cascade found.')
end
