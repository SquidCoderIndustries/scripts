-- Prints the sum of all citizens' needs.

local argparse = require('argparse')

local sorts = {
    id=function(a,b) return a.id < b.id end,
    strength=function(a,b) return a.strength > b.strength end,
    focus=function(a,b) return a.focus < b.focus end,
    freq=function(a,b) return a.freq > b.freq end,
}

local sort = 'focus'

argparse.processArgsGetopt({...}, {
    {'s', 'sort', hasArg=true, handler=function(optarg) sort = optarg end}
})

if not sorts[sort] then
    qerror(('unknown sort: "%s"'):format(sort))
end

local fulfillment_threshold =
    { 300, 200, 100, -999, -9999, -99999 }

local function getFulfillment(focus_level)
    for i = 1, 6 do
        if focus_level >= fulfillment_threshold[i] then
            return i
        end
    end
    return 7
end

local fort_needs = {}

local units = dfhack.gui.getSelectedUnit(true)
if units then
    print(('Summarizing needs for %s:'):format(dfhack.units.getReadableName(units)))
    units = {units}
else
    print('Summarizing needs for all (sane) citizens and residents:')
    units = dfhack.units.getCitizens()
end
print()

for _, unit in ipairs(units) do
    local mind = unit.status.current_soul.personality.needs
    -- sum need_level and focus_level for each need
    for _,need in ipairs(mind) do
        local needs = ensure_key(fort_needs, need.id)
        needs.strength = (needs.strength or 0) + need.need_level
        needs.focus = (needs.focus or 0) + need.focus_level
        needs.freq = (needs.freq or 0) + 1

        local level = getFulfillment(need.focus_level)
        ensure_key(needs, 'fulfillment', {0, 0, 0, 0, 0, 0, 0})
        needs.fulfillment[level] = needs.fulfillment[level] + 1
    end
end

local sorted_fort_needs = {}
for id, need in pairs(fort_needs) do
    table.insert(sorted_fort_needs, {
        id=df.need_type[id],
        strength=need.strength,
        focus=need.focus,
        freq=need.freq,
        fulfillment=need.fulfillment
    })
end

table.sort(sorted_fort_needs, sorts[sort])

-- Print sorted output
local fmt = '%20s  %8s  %12s  %9s  %35s'
print(fmt:format("Need", "Strength", "Focus Impact", "Frequency", "Num. Unfettered -> Badly distracted"))
print(fmt:format("----", "--------", "------------", "---------", "-----------------------------------"))
for _, need in ipairs(sorted_fort_needs) do
    local res = ""
    for i = 1, 7 do
        res = res..(('%5d'):format(need.fulfillment[i]))
    end
    print(fmt:format(need.id, need.strength, need.focus, need.freq, res))
end
