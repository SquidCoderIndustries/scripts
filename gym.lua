--@ enable = true
--@ module = true

local repeatUtil = require 'repeat-util'
local utils=require('utils')

validArgs = utils.invert({
    't',
    'n'
})

local args = utils.processArgs({...}, validArgs)
local GLOBAL_KEY  = "autotraining"
local ignore_flag = df.unit_labor['DISSECT_FISH']
local ignore_count = 0
local need_id = 14

local function get_default_state()
    return {
        enabled=false,
        threshold=-5000,
        squadname='Gym'
    }
end

state = state or get_default_state()

function isEnabled()
    return state.enabled
end

dfhack.onStateChange[GLOBAL_KEY] = function(sc)
    -- the state changed, is a map loaded and is that map in fort mode?
    if sc ~= SC_MAP_LOADED or df.global.gamemode ~= df.game_mode.DWARF then
        -- no its isnt, so bail
        return
    end
    -- yes it was so:
    -- retrieve state saved in game. merge with default state so config
    -- saved from previous versions can pick up newer defaults.
    state = get_default_state()
    utils.assign(state, dfhack.persistent.getSiteData(GLOBAL_KEY, state))
end

-- Save any configurations in the save data
local function persist_state()
    dfhack.persistent.saveSiteData(GLOBAL_KEY, state)
end


--######
--Functions
--######
function getAllCititzen()
    local citizen = {}
    local my_civ = df.global.world.world_data.active_site[0].entity_links[0].entity_id
    for n, unit in ipairs(df.global.world.units.all) do
        if unit.civ_id == my_civ and dfhack.units.isCitizen(unit) then
            if unit.profession ~= df.profession.BABY and unit.profession ~= df.profession.CHILD then
                if ( not unit.status.labors[ignore_flag] ) then
                    table.insert(citizen, unit)
                else
                    ignore_count = ignore_count +1
                end
            end
        end
    end
    return citizen
end

local citizen = getAllCititzen()

function findNeed(unit,need_id)
    local needs =  unit.status.current_soul.personality.needs
    for _, need in ipairs(needs) do
        if need.id == need_id then
            return need
        end
    end
    return nil
end

--######
--Main
--######

function getByID(id)
    for n, unit in ipairs(citizen) do
        if (unit.hist_figure_id == id) then
            return unit
        end
    end

    return nil
end

-- Find all training squads
-- Abort if no squads found
function checkSquads()
    local squads = {}
    local count = 0
    for n, mil in ipairs(df.global.world.squads.all) do
        if (mil.alias == state.squadname) then
            local leader = mil.positions[0].occupant
            if ( leader ~= -1) then
                table.insert(squads,mil)
                count = count +1
            end
        end
    end

    if (count == 0) then
        dfhack.print(GLOBAL_KEY .." | ")
        dfhack.printerr('ERROR: You need a squad with the name ' .. state.squadname)
        dfhack.print(GLOBAL_KEY .." | ")
        dfhack.printerr('That has an active Squad Leader')
        dfhack.color(-1)
        return nil
    end

    return squads
end

function addTraining(squads,unit)
    for n, squad in ipairs(squads) do
        for i=1,9,1   do
            if (unit.hist_figure_id == squad.positions[i].occupant) then
                return true
            end

            if (unit.military.squad_id ~= -1) then
                return false
            end

            if ( squad.positions[i].occupant  == -1 ) then
                squad.positions[i].occupant = unit.hist_figure_id
                unit.military.squad_id = squad.id
                unit.military.squad_position = i
                return true
            end
        end
    end

    return false
end

function removeTraining(squads,unit)
    for n, squad in ipairs(squads) do
        for i=1,9,1   do
            if ( unit.hist_figure_id  == squad.positions[i].occupant ) then
                unit.military.squad_id = -1
                unit.military.squad_position = -1
                squad.positions[i].occupant = -1
                return true
            end
        end
    end
    return false
end

function removeAll(squads)
    if ( squads == nil) then return end
    for n, squad in ipairs(squads) do
        for i=1,9,1 do
            local dwarf = getByID(squad.positions[i].occupant)
            if (dwarf ~= nil) then
                dwarf.military.squad_id = -1
                dwarf.military.squad_position = -1
                squad.positions[i].occupant = -1
            end
        end
    end
end


function check()
    local squads = checkSquads()
    local intraining_count = 0
    local inque_count = 0
    if ( squads == nil)then return end
    for n, unit in ipairs(citizen) do
        local need = findNeed(unit,need_id)
        if ( need  ~= nil ) then
            if ( need.focus_level  < threshold ) then
                local bol = addTraining(squads,unit)
                if ( bol ) then
                    intraining_count = intraining_count +1
                else
                    inque_count = inque_count +1
                end
            else
                removeTraining(squads,unit)
            end
        end
    end

    dfhack.println(GLOBAL_KEY  .. " | IGN: " .. ignore_count .. " TRAIN: " .. intraining_count .. " QUE: " ..inque_count )
end

function start()
    dfhack.println(GLOBAL_KEY  ..  " | START")

    if (args.t) then
        state.threshold = 0-tonumber(args.t)
    end
    if (args.n) then
        state.squadname = args.n
    end

    repeatUtil.scheduleEvery(GLOBAL_KEY, 997, 'ticks', check) -- 997 is the closest prime to 1000
end

function stop()
    repeatUtil.cancel(GLOBAL_KEY)
    local squads = checkSquads()
    removeAll(squads)
    dfhack.println(GLOBAL_KEY  .. " | STOP")
end

if dfhack_flags.enable then
    if dfhack_flags.enable_state then
        start()
        state.enabled = true
        persist_state()
    else
        stop()
        state.enabled = false
        persist_state()
    end
end

if dfhack_flags.module then
    return
end

if ( state.enabled ) then
    dfhack.println(GLOBAL_KEY  .."    | Enabled")
else
    dfhack.println(GLOBAL_KEY  .."    | Disabled")
end
