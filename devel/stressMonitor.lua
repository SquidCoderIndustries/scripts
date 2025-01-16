local list = {}
for _, unit in ipairs(dfhack.units.getCitizens(true, false)) do
    local personality = unit.status.current_soul.personality
    if personality.stress > 25000 or personality.longterm_stress > 0 then
        local name = dfhack.units.getReadableName(unit)
        local str = ((' %15d | %7d | %s'):format(
            personality.longterm_stress,
            personality.stress,
            dfhack.df2console(name)
        ))
        table.insert(list, str)
    end
end
local sorted = {}
for _,unit in ipairs(list) do table.insert(sorted, unit)end
table.sort(sorted)
print('Long-term Stress |  Stress | Name')
print('=======================================================')
for _,unit in ipairs(sorted) do print(unit) end
