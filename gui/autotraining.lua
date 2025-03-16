---@diagnostic disable: missing-fields

local gui = require('gui')
local widgets = require('gui.widgets')

local autotraining = reqscript('autotraining')

local training_squads  = autotraining.state.training_squads
local ignored_units = autotraining.state.ignored

AutoTrain = defclass(AutoTrain, widgets.Window)
AutoTrain.ATTRS {
    frame_title='Training Setup',
    frame={w=55, h=45},
    resizable=true, -- if resizing makes sense for your dialog
    resize_min={w=55, h=20}, -- try to allow users to shrink your windows
}

local SELECTED_ICON = dfhack.pen.parse{ch=string.char(251), fg=COLOR_LIGHTGREEN}
function AutoTrain:getSquadIcon(squad_id)
    if training_squads[squad_id] then
        return SELECTED_ICON
    end
    return nil
end

function AutoTrain:getSquads()
    local squads = {}
    for _, squad in ipairs(df.global.world.squads.all) do
        if not (squad.entity_id == df.global.plotinfo.group_id) then
            goto continue
        end
        table.insert(squads, {
            text = dfhack.translation.translateName(squad.name, true)..' ('..squad.alias..')',
            icon = self:callback("getSquadIcon", squad.id ),
            id   = squad.id
        })

        ::continue::
    end
    return squads
end

function AutoTrain:toggleSquad(_, choice)
    training_squads[choice.id] = not training_squads[choice.id]
    autotraining.persist_state()
    self:updateLayout()
end

local IGNORED_ICON = dfhack.pen.parse{ch='x', fg=COLOR_RED}
function AutoTrain:getUnitIcon(unit_id)
    if ignored_units[unit_id] then
        return IGNORED_ICON
    end
    return nil
end

function AutoTrain:getUnits()
    local unit_choices = {}
    for _, unit in ipairs(dfhack.units.getCitizens(true,false)) do
        if not dfhack.units.isAdult(unit) then
            goto continue
        end

        table.insert(unit_choices, {
            text = dfhack.units.getReadableName(unit),
            icon = self:callback("getUnitIcon", unit.id ),
            id   = unit.id
        })
        ::continue::
    end
    return unit_choices
end

function AutoTrain:toggleUnit(_, choice)
    ignored_units[choice.id] = not ignored_units[choice.id]
    autotraining.persist_state()
    self:updateLayout()
end

function AutoTrain:init()

    -- TODO: provide actual values, and write to configuration
    -- (once the base tool actually supports this)
    local position_options = {
        { label = "none", val = nil, pen = COLOR_LIGHTCYAN },
        { label = "manager", val = nil, pen = COLOR_LIGHTCYAN },
        { label = "manager and chief medical dwarf", val = nil, pen = COLOR_LIGHTCYAN },
    }

    self:addviews{
        widgets.Label{
            frame={ t = 0 , h = 1 },
            text = "Select squads for automatic training",
        },
        widgets.List{
            view_id = "squad_list",
            icon_width = 2,
            frame = { t = 2, h = 10 },
            choices = self:getSquads(),
            on_submit=self:callback("toggleSquad")
        },
        widgets.Divider{ frame={t=12, h=1}, frame_style_l = false, frame_style_r = false},
        widgets.Label{
            frame={ t = 13 , h = 1 },
            text = "General options",
        },
        widgets.EditField {
            view_id = "threshold",
            frame={ t = 15 , h = 1 },
            key = "CUSTOM_T",
            label_text = "Need threshold for training: ",
            text = tostring(-autotraining.state.threshold),
            on_char = function (char, _)
                return tonumber(char,10)
            end,
            on_submit = function (text)
                -- still necessary, because on_char does not check pasted text
                local entered_number = tonumber(text,10) or 5000
                autotraining.state.threshold = -entered_number
                autotraining.persist_state()
                -- make sure that the auto correction is reflected in the EditField
                self.subviews.threshold:setText(tostring(entered_number))
            end
        },
        widgets.CycleHotkeyLabel {
            view_id = "ignored_positions",
            frame={ t = 16 , h = 2 },
            key = "CUSTOM_P",
            label = "Positions to keep from training: ",
            label_below = true,
            options = position_options,
            initial_option = 3
        },
        widgets.Divider{ frame={t=19, h=1}, frame_style_l = false, frame_style_r = false},
        widgets.Label{
            frame={ t = 20 , h = 1 },
            text = "Select units to exclude from automatic training"
        },
        widgets.FilteredList{
            frame = { t = 22 },
            view_id = "unit_list",
            edit_key = "CUSTOM_CTRL_F",
            icon_width = 2,
            choices = self:getUnits(),
            on_submit=self:callback("toggleUnit")
        }
    }
    --self.subviews.unit_list:setChoices(unit_choices)
end

function AutoTrain:onDismiss()
    view = nil
end

AutoTrainScreen = defclass(AutoTrainScreen, gui.ZScreen)
AutoTrainScreen.ATTRS {
    focus_path='autotrain',
}

function AutoTrainScreen:init()
    self:addviews{AutoTrain{}}
end

function AutoTrainScreen:onDismiss()
    view = nil
end

if not dfhack.world.isFortressMode() or not dfhack.isMapLoaded() then
    qerror('gui/autotrain requires a fortress map to be loaded')
end

view = view and view:raise() or AutoTrainScreen{}:show()
