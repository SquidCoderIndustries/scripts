-- Changes the personality of units.
--@ module = true

--[[ Notes:
> When using script functions, use numerical IDs for representing personality traits.
]]

local utils = require('utils')

local validArgs = utils.invert({
  "all",
  "trait",
  "set",
  "tier",
  "modify",
  "step",
  "random",
  "average",
  "citizens",
  "unit",
  "help",
  "list",
  "noneed",
  "listunit"
})

-- These ranges represent the bounds at which the description for a personality trait changes
local tierRanges = {{min = 0, max = 9, weight = 4}, {min = 10, max = 24, weight = 20}, {min = 25, max = 39, weight = 85}, {min = 40, max = 60, weight = 780}, {min = 61, max = 75, weight = 85}, {min = 76, max = 90, weight = 20}, {min = 91, max = 100, weight = 4}}

rng = rng or dfhack.random.new(nil, 10)

---------------------
local function clamp(value, low, high)
  return math.min(high, math.max(low, value))
end

local function weightedRoll(weightedTable)
  local maxWeight = 0
  for index, result in ipairs(weightedTable) do
    maxWeight = maxWeight + result.weight
  end

  local roll = rng:random(maxWeight) + 1
  local currentNum = roll
  local result

  for index, currentResult in ipairs(weightedTable) do
    currentNum = currentNum - currentResult.weight
    if currentNum <= 0 then
      result = currentResult.id
      break
    end
  end

  return result
end

local function randomiseWithinBounds(min, max)
  local range = math.abs(min - max)
  local roll = rng:random(range+1)

  return min + roll
end

---------------------
-- Set unit's personality facet to a given value
-- Use this as the main method of changing a unit's personality!
function setUnitTrait(unit, trait, value)
  -- Clamp value
  local value = clamp(value, 0, 100)

  unit.status.current_soul.personality.traits[trait] = value
end

-- Returns the value of the unit's base personality trait (ignoring current modifiers)
function getUnitTraitBase(unit, trait)
  if trait == df.personality_facet_type.NONE then return 0 end
  local value = unit.status.current_soul.personality.traits[trait]

  return value
end

-- Returns the value of the unit's current personality trait (modified by active syndromes and such)
function getUnitTraitCurrent(unit, trait)
  local base = getUnitTraitBase(unit, trait)
  local value = base
  if unit.status.current_soul.personality.temporary_trait_changes ~= nil then
    value = value + unit.status.current_soul.personality.temporary_trait_changes[trait]
  end

  return value
end

-- Gives a list of all the unit's traits and their values.
-- Returns a table where the keys are the traits names and its values are its strength
-- If current is true, the unit's current trait strength is used instead of base.
-- If tiers is true, the value is the tier of the trait instead of the trait's strength
function getUnitTraitList(unit, current, tiers)
  local list = {}

  for index, traitName in ipairs(df.personality_facet_type) do
    if traitName ~= 'NONE' then
      local strength

      if current then
        strength = getUnitTraitCurrent(unit, traitName)
      else
        strength = getUnitTraitBase(unit, traitName)
      end

      if tiers then
        list[traitName] = getTraitTier(strength)
      else
        list[traitName] = strength
      end
    end
  end

  return list
end

-- Sets unit's trait to a random value within the given tier.
function setUnitTraitTier(unit, trait, tier)
  local tier = clamp(tier, 1, 7)
  local currentTier = getTraitTier(getUnitTraitBase(unit, trait))

  -- Randomly generate a strength value which falls between within the new tier, and set that as the unit's trait strength
  local strength = randomiseWithinBounds(tierRanges[tier].min, tierRanges[tier].max)
  setUnitTrait(unit, trait, strength)
end

-- Move the unit's trait in tier increments
function stepUnitTrait(unit, trait, modifier)
  local currentTier = getTraitTier(getUnitTraitBase(unit, trait))
  local newTier = clamp(currentTier + modifier, 1, 7)

  -- Only do so if new tier is different from the current one
  if currentTier ~= newTier then
    setUnitTraitTier(unit, trait, newTier)
  end
end

-- Modify the unit's trait by a given amount
function modifyUnitTrait(unit, trait, modifier)
  local currentStrength = getUnitTraitBase(unit, trait)
  local newStrength = currentStrength + modifier

  setUnitTrait(unit, trait, newStrength)
end

-- Changes unit trait to a new random amount, based on their caste's PERSONALITY token range for the trait
function randomiseUnitTrait(unit, trait)
  local casteRange = getUnitCasteTraitRange(unit, trait)
  local rolledValue = randomTraitRoll(casteRange.min, casteRange.mid, casteRange.max)

  setUnitTrait(unit, trait, rolledValue)
end

-- Sets the unit's trait to their caste average value
function averageUnitTrait(unit, trait)
  local average = getUnitCasteTraitRange(unit, trait).mid

  setUnitTrait(unit, trait, average)
end

-- Gets the range of the unit caste's min, average, and max value for a trait, as defined in the PERSONALITY creature tokens.
function getUnitCasteTraitRange(unit, trait)
  local caste = dfhack.units.getCasteRaw(unit)
  local range = {}

  range.min = caste.personality.a[df.personality_facet_type[trait]]
  range.mid = caste.personality.b[df.personality_facet_type[trait]]
  range.max = caste.personality.c[df.personality_facet_type[trait]]

  return range
end

-- Roll a trait value in the same style as the game
-- At least, I think this is how it works (it's how bp appearances work)
-- Note: I'm not sure this is actually how it works
function randomTraitRoll(min, median, max)
  local min = min or 0
  local median = median or 50
  local max = max or 100

  -- Decide whether the result is between min + median, or median + max
  local bucketRoll = randomiseWithinBounds(1, 2)
  local traitValue

  if bucketRoll == 1 then -- Min - Median
    traitValue = randomiseWithinBounds(min, median)
  else --median to max
    traitValue = randomiseWithinBounds(median, max)
  end

  return traitValue
end


function randomTraitValueRespectingTokens(unit, trait)
  --TODO
  return randomTraitValue()
end

-- Gets what tier of trait that the given value falls into
-- 1: Lowest | 2: Very Low | 3: Low | 4: Neutral | 5: High | 6: Very High | 7: Highest
function getTraitTier(value)
  local range = 1
  for index, data in ipairs(tierRanges) do
    if value >= data.min and value <= data.max then
      range = index
      break
    end
  end

  return range
end

-- Returns a trait tier based on the probabilities listed on the wiki
-- Doesn't account for the creature's PERSONALITY weighting!
function randomTraitTier()
  local weightedTable = {} --as:{_type:table,id:number,weight:number}[]

  for rangeIndex, data in ipairs(tierRanges) do
    local addition = {}
    addition.id = rangeIndex
    addition.weight = data.weight
    table.insert(weightedTable, addition)
  end

  -- Determine the range tier
  local result = weightedRoll(weightedTable)

  return result
end

-- Uses above, but then gets a strength value within the tier's bounds
function randomTraitValue()
  local randomTier = randomTraitTier()

  -- Get a random value within that range
  return randomiseWithinBounds(tierRanges[randomTier].min, tierRanges[randomTier].max)
end

function printUnitTraits(unit)
  print("Traits of " .. dfhack.df2console(dfhack.units.getReadableName(unit)) .. ":")
  for id, name in ipairs(df.personality_facet_type) do
    if name ~= 'NONE' then
      local baseValue = getUnitTraitBase(unit, id)
      local currentValue = getUnitTraitCurrent(unit, id)

      print(name .. ": " .. baseValue .. " (" .. currentValue .. ")")
    end
  end
end

function main(...)
  local args = utils.processArgs({...}, validArgs)
  local setneed = dfhack.reqscript("modtools/set-need")

  if args.help then
    print(dfhack.script_help())
    return
  end

  if args.list then
    for index, traitName in ipairs(df.personality_facet_type) do
      if traitName ~= 'NONE' then
        print(index .. " (" .. traitName .. ")")
      end
    end
    return
  end

  -- Valid target check
  local unitsList = {}
  if not args.citizens then
    -- Assume trying to target a unit
    local unit
    if args.unit then
        if tonumber(args.unit) then
            unit = df.unit.find(tonumber(args.unit))
        end
    end

    -- If unit ID wasn't provided / unit couldn't be found,
    -- Try getting selected unit
    if unit == nil then
        unit = dfhack.gui.getSelectedUnit(true)
    end

    if unit == nil then
        qerror("Couldn't find unit. If you don't want to target a specific unit, use -citizens.")
    else
        table.insert(unitsList, unit)
    end
  elseif args.citizens then
    -- Abort if not in Fort mode
    if not dfhack.world.isFortressMode() then
        qerror("--citizens argument only available in Fortress Mode.")
    end

    unitsList = dfhack.units.getCitizens(false, true)
  end

  -- Trait check
  local traitsList = {}
  if not args.trait and not args.all and not args.listunit then
    qerror("Please specify a trait to edit using -trait <ID> or -all.")
  end
  if not args.all then -- One trait provided
    local traitId
    if tonumber(args.trait) then
      traitId = tonumber(args.trait)
    else
      traitId = df.personality_facet_type[args.trait:upper()]
    end

    table.insert(traitsList,traitId)
  else -- To modify: all
    for id, traitName in ipairs(df.personality_facet_type) do
      if traitName ~= 'NONE' then
        table.insert(traitsList, id)
      end
    end
  end

  -- Modifier check
  local modifyStyle
  local value
  if args.set then
    modifyStyle = "set"
    value = tonumber(args.set)
  elseif args.tier then
    modifyStyle = "tier"
    value = tonumber(args.tier)
  elseif args.modify then
    modifyStyle = "modify"
    value = tonumber(args.modify)
  elseif args.step then
    modifyStyle = "step"
    value = tonumber(args.step)
  elseif args.random then
    modifyStyle = "random"
  elseif args.average then
    modifyStyle = "average"
  elseif not args.listunit then
    qerror("Please provide a valid modifier.")
  end

  -- Execute
  for index, unit in ipairs(unitsList) do
    for index, trait in ipairs(traitsList) do
      if modifyStyle == "set" then
        setUnitTrait(unit, trait, value)
      elseif modifyStyle == "tier" then
        setUnitTraitTier(unit, trait, value)
      elseif modifyStyle == "modify" then
        modifyUnitTrait(unit, trait, value)
      elseif modifyStyle == "step" then
        stepUnitTrait(unit, trait, value)
      elseif modifyStyle == "random" then
        randomiseUnitTrait(unit, trait)
      elseif modifyStyle == "average" then
        averageUnitTrait(unit, trait)
      end
    end

    if args.listunit then
      printUnitTraits(unit)
    end

    if not args.noneed and not args.listunit then
      setneed.rebuildNeeds(unit)
    end
  end
end

if not dfhack_flags.module then
  main(...)
end
