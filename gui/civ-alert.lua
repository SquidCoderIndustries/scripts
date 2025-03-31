--@ module=true

local gui = require('gui')
local overlay = require('plugins.overlay')
local textures = require('gui.textures')
local utils = require('utils')
local widgets = require('gui.widgets')

local function get_civ_alert()
    local list = df.global.plotinfo.alerts.list
    while #list < 2 do
        local list_item = df.alert_statest:new()
        list_item.id = df.global.plotinfo.alerts.next_id
        df.global.plotinfo.alerts.next_id = df.global.plotinfo.alerts.next_id + 1
        list_item.name = 'civ-alert'
        list:insert('#', list_item)
    end
    return list[1]
end

-- public API section
function can_sound_alarm()
    return df.global.plotinfo.alerts.civ_alert_idx == 0 and
            #get_civ_alert().burrows > 0
end

function sound_alarm()
    if not can_sound_alarm() then return end
    df.global.plotinfo.alerts.civ_alert_idx = 1
end

function can_clear_alarm()
    return df.global.plotinfo.alerts.civ_alert_idx ~= 0
end

function clear_alarm()
    df.global.plotinfo.alerts.civ_alert_idx = 0
end

function add_civalert_burrow(id)
    local burrows = get_civ_alert().burrows
    utils.insert_sorted(burrows, id)
end

function remove_civalert_burrow(id)
    local burrows = get_civ_alert().burrows
    utils.erase_sorted(burrows, id)
    if #burrows == 0 then
        clear_alarm()
    end
end

local function toggle_civalert_burrow(id)
    local burrows = get_civ_alert().burrows
    if utils.binsearch(burrows, id) then
        remove_civalert_burrow(id)
    else
        add_civalert_burrow(id)
    end
end

--
-- BigRedButton
--

local to_pen = dfhack.pen.parse
local BUTTON_TEXT_ON = to_pen{fg=COLOR_BLACK, bg=COLOR_LIGHTRED}
local BUTTON_TEXT_OFF = to_pen{fg=COLOR_WHITE, bg=COLOR_RED}

BigRedButton = defclass(BigRedButton, widgets.Panel)
BigRedButton.ATTRS{
}

function BigRedButton:init()
    self.frame = self.frame or {}
    self.frame.w = 10
    self.frame.h = 3

    self:addviews{
        widgets.Label{
            text=widgets.makeButtonLabelText{
                chars={
                    ' Activate ',
                    ' civilian ',
                    '  alert   ',
                },
                pens=BUTTON_TEXT_ON,
                pens_hover=BUTTON_TEXT_OFF,
            },
            visible=can_sound_alarm,
            on_click=sound_alarm,
        },
        widgets.Label{
            text=widgets.makeButtonLabelText{
                chars={
                    '  Clear   ',
                    ' civilian ',
                    '  alert   ',
                },
                pens=BUTTON_TEXT_OFF,
                pens_hover=BUTTON_TEXT_ON,
            },
            visible=can_clear_alarm,
            on_click=clear_alarm,
        },
    }
end

--
-- CivalertOverlay
--

CivalertOverlay = defclass(CivalertOverlay, overlay.OverlayWidget)
CivalertOverlay.ATTRS{
    desc='Adds a button for activating a civilian alert when the squads panel is open.',
    default_pos={x=-15,y=-1},
    default_enabled=true,
    viewscreens='dwarfmode',
    frame={w=20, h=5},
}

local function is_squads_panel_open()
    return dfhack.gui.matchFocusString('dwarfmode/Squads/Default',
        dfhack.gui.getDFViewscreen(true))
end

local function should_show_alert_button()
    return can_clear_alarm() or (is_squads_panel_open() and can_sound_alarm())
end

local function should_show_configure_button()
    return is_squads_panel_open() and not can_sound_alarm() and not can_clear_alarm()
end

local function launch_config()
    dfhack.run_script('gui/civ-alert')
end

last_tp_start = last_tp_start or 0
CONFIG_BUTTON_PENS = CONFIG_BUTTON_PENS or {}
local function get_button_pen(idx)
    local start = textures.tp_control_panel(1)
    if last_tp_start == start then return CONFIG_BUTTON_PENS[idx] end
    last_tp_start = start

    CONFIG_BUTTON_PENS[1] = to_pen{fg=COLOR_CYAN, tile=curry(textures.tp_control_panel, 7), ch=string.byte('[')}
    CONFIG_BUTTON_PENS[2] = to_pen{tile=curry(textures.tp_control_panel, 10), ch=15} -- gear/masterwork symbol
    CONFIG_BUTTON_PENS[3] = to_pen{fg=COLOR_CYAN, tile=curry(textures.tp_control_panel, 8), ch=string.byte(']')}

    return CONFIG_BUTTON_PENS[idx]
end

function CivalertOverlay:init()
    self:addviews{
        widgets.Panel{
            frame={t=0, r=0, w=16, h=5},
            frame_style=gui.MEDIUM_FRAME,
            frame_background=gui.CLEAR_PEN,
            visible=should_show_alert_button,
            subviews={
                BigRedButton{
                    frame={t=0, l=0},
                },
                widgets.Label{
                    frame={t=1, r=0, w=3},
                    text={
                        {tile=curry(get_button_pen, 1)},
                        {tile=curry(get_button_pen, 2)},
                        {tile=curry(get_button_pen, 3)},
                    },
                    on_click=launch_config,
                },
            },
        },
        widgets.Panel{
            frame={b=0, r=0, w=20, h=4},
            frame_style=gui.MEDIUM_FRAME,
            frame_background=gui.CLEAR_PEN,
            visible=should_show_configure_button,
            subviews={
                widgets.Label{
                    text={
                        'Click to configure', NEWLINE,
                        '  civilian alert  ',
                    },
                    text_pen=to_pen{fg=COLOR_YELLOW, bg=COLOR_BLACK},
                    on_click=launch_config,
                },
            },
        },
    }
end

OVERLAY_WIDGETS = {big_red_button=CivalertOverlay}

--
-- Civalert
--

Civalert = defclass(Civalert, widgets.Window)
Civalert.ATTRS{
    frame_title='Civilian alert',
    frame={w=60, h=20},
    resizable=true,
    resize_min={h=15},
}

function Civalert:init()
    local choices = self:get_burrow_choices()

    self:addviews{
        widgets.Panel{
            frame={t=0, l=0, r=12},
            subviews={
                widgets.WrappedLabel{
                    frame={t=0, r=0, h=2},
                    text_to_wrap='Choose the burrow(s) where you want your civilians to hide during danger.',
                },
                widgets.HotkeyLabel{
                    frame={t=3, l=0},
                    key='CUSTOM_CTRL_N',
                    label='Sound alarm! Citizens run to safety!',
                    on_activate=sound_alarm,
                    enabled=can_sound_alarm,
                },
                widgets.HotkeyLabel{
                    frame={t=4, l=0},
                    key='CUSTOM_CTRL_D',
                    label='All clear! Citizens return to normal',
                    on_activate=clear_alarm,
                    enabled=can_clear_alarm,
                },
            },
        },
        BigRedButton{
            frame={t=0, r=0},
        },
        widgets.FilteredList{
            frame={t=6, l=0, b=0, r=0},
            choices=choices,
            icon_width=2,
            on_submit=self:callback('select_burrow'),
            visible=#choices > 0,
        },
        widgets.WrappedLabel{
            frame={t=7, l=0, r=0},
            text_to_wrap='No burrows defined. Please define one to use for the civalert.',
            text_pen=COLOR_RED,
            visible=#choices == 0,
        },
    }
end

local function get_burrow_name(burrow)
    if #burrow.name > 0 then return burrow.name end
    return ('Burrow %d'):format(burrow.id+1)
end

local SELECTED_ICON = to_pen{ch=string.char(251), fg=COLOR_LIGHTGREEN}

function Civalert:get_burrow_icon(id)
    local burrows = get_civ_alert().burrows
    return utils.binsearch(burrows, id) and SELECTED_ICON or nil
end

function Civalert:get_burrow_choices()
    local choices = {}
    for _,burrow in ipairs(df.global.plotinfo.burrows.list) do
        local choice = {
            text=get_burrow_name(burrow),
            id=burrow.id,
            icon=self:callback('get_burrow_icon', burrow.id),
        }
        table.insert(choices, choice)
    end
    return choices
end

function Civalert:select_burrow(_, choice)
    toggle_civalert_burrow(choice.id)
    self:updateLayout()
end

--
-- CivalertScreen
--

CivalertScreen = defclass(CivalertScreen, gui.ZScreen)
CivalertScreen.ATTRS {
    focus_path='civalert',
}

function CivalertScreen:init()
    self:addviews{Civalert{}}
end

function CivalertScreen:onDismiss()
    view = nil
end

if dfhack_flags.module then
    return
end

if not dfhack.isMapLoaded() then
    qerror('gui/civ-alert requires a map to be loaded')
end

view = view and view:raise() or CivalertScreen{}:show()
