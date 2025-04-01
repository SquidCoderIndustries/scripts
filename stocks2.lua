local gui = require("gui")
local widgets = require("gui.widgets")
local utils = require("utils")

local common = reqscript('internal/caravan/common')

local to_pen = dfhack.pen.parse
SOME_PEN = to_pen{ch=':', fg=COLOR_YELLOW}
ALL_PEN = to_pen{ch=string.char(251), fg=COLOR_LIGHTGREEN}

local current_search_query = ""
local filter_states = {
    in_job = true,
    rotten = true,
    owned = true,
    forbidden = true,
    dump = true,
    on_fire = true,
    melt = true,
    in_inv = true,
    caged = true,
    trade = true,
    no_flags = true,
}

-- -------------------
-- Stocks
--

Stocks = defclass(Stocks, widgets.Window)
Stocks.ATTRS {
    frame_title='Stocks',
    frame={w=86, h=47},
    resizable=true,
    resize_min={w=80, h=40},
}

local function get_entry_icon(data)
    return to_pen{ch=''}
    -- if trade.goodflag[data.list_idx][data.item_idx].selected then
    --     return common.ALL_PEN
    -- end
end

local function sort_noop()
    -- this function is used as a marker and never actually gets called
    error('sort_noop should not be called')
end

local function sort_base(a, b)
    return a.data.desc < b.data.desc
end

local function sort_by_name_desc(a, b)
    if a.search_key == b.search_key then
        return sort_base(a, b)
    end
    return a.search_key < b.search_key
end

local function sort_by_name_asc(a, b)
    if a.search_key == b.search_key then
        return sort_base(a, b)
    end
    return a.search_key > b.search_key
end

local function sort_by_value_desc(a, b)
    if a.data.value == b.data.value then
        return sort_by_name_desc(a, b)
    end
    return a.data.value > b.data.value
end

local function sort_by_value_asc(a, b)
    if a.data.value == b.data.value then
        return sort_by_name_desc(a, b)
    end
    return a.data.value < b.data.value
end

local VALUE_COL_WIDTH = 6
local FILTER_HEIGHT = 18

-- save filters (sans search string) between dialog invocations
local filters = {
    min_quality=0,
    max_quality=6,
    hide_unreachable=true,
    hide_forbidden=false,
    hide_written=false,
    inside_containers=true,
}

function get_slider_widgets(self, suffix)
    suffix = suffix or ''
    return {
        widgets.Panel{
            frame={t=0, l=0, h=4},
            subviews={
                widgets.CycleHotkeyLabel{
                    view_id='min_condition'..suffix,
                    frame={l=0, t=0, w=18},
                    label='Min condition:',
                    label_below=true,
                    key_back='CUSTOM_SHIFT_C',
                    key='CUSTOM_SHIFT_V',
                    options={
                        {label='XXTatteredXX', value=3, pen=COLOR_BROWN},
                        {label='XFrayedX', value=2, pen=COLOR_LIGHTRED},
                        {label='xWornx', value=1, pen=COLOR_YELLOW},
                        {label='Pristine', value=0, pen=COLOR_GREEN},
                    },
                    initial_option=3,
                    on_change=function(val)
                        if self.subviews['max_condition'..suffix]:getOptionValue() > val then
                            self.subviews['max_condition'..suffix]:setOption(val)
                        end
                        self:refresh_list()
                    end,
                },
                widgets.CycleHotkeyLabel{
                    view_id='max_condition'..suffix,
                    frame={l=20, t=0, w=18},
                    label='Max condition:',
                    label_below=true,
                    key_back='CUSTOM_SHIFT_E',
                    key='CUSTOM_SHIFT_R',
                    options={
                        {label='XXTatteredXX', value=3, pen=COLOR_BROWN},
                        {label='XFrayedX', value=2, pen=COLOR_LIGHTRED},
                        {label='xWornx', value=1, pen=COLOR_YELLOW},
                        {label='Pristine', value=0, pen=COLOR_GREEN},
                    },
                    initial_option=0,
                    on_change=function(val)
                        if self.subviews['min_condition'..suffix]:getOptionValue() < val then
                            self.subviews['min_condition'..suffix]:setOption(val)
                        end
                        self:refresh_list()
                    end,
                },
                widgets.RangeSlider{
                    frame={l=0, w=38, t=3},
                    num_stops=4,
                    get_left_idx_fn=function()
                        return 4 - self.subviews['min_condition'..suffix]:getOptionValue()
                    end,
                    get_right_idx_fn=function()
                        return 4 - self.subviews['max_condition'..suffix]:getOptionValue()
                    end,
                    on_left_change=function(idx) self.subviews['min_condition'..suffix]:setOption(4-idx, true) end,
                    on_right_change=function(idx) self.subviews['max_condition'..suffix]:setOption(4-idx, true) end,
                },
            },
        },
        widgets.Panel{
            frame={t=6, l=0, h=4},
            subviews={
                widgets.CycleHotkeyLabel{
                    view_id='min_quality'..suffix,
                    frame={l=0, t=0, w=18},
                    label='Min quality:',
                    label_below=true,
                    key_back='CUSTOM_SHIFT_Z',
                    key='CUSTOM_SHIFT_X',
                    options={
                        {label='Ordinary', value=0, pen=COLOR_GRAY},
                        {label='-Well Crafted-', value=1, pen=COLOR_LIGHTBLUE},
                        {label='+Fine Crafted+', value=2, pen=COLOR_BLUE},
                        {label='*Superior*', value=3, pen=COLOR_YELLOW},
                        {label=common.CH_EXCEPTIONAL..'Exceptional'..common.CH_EXCEPTIONAL, value=4, pen=COLOR_BROWN},
                        {label=common.CH_MONEY..'Masterful'..common.CH_MONEY, value=5, pen=COLOR_MAGENTA},
                        {label='Artifact', value=6, pen=COLOR_GREEN},
                    },
                    initial_option=0,
                    on_change=function(val)
                        if self.subviews['max_quality'..suffix]:getOptionValue() < val then
                            self.subviews['max_quality'..suffix]:setOption(val)
                        end
                        self:refresh_list()
                    end,
                },
                widgets.CycleHotkeyLabel{
                    view_id='max_quality'..suffix,
                    frame={l=20, t=0, w=18},
                    label='Max quality:',
                    label_below=true,
                    key_back='CUSTOM_SHIFT_Q',
                    key='CUSTOM_SHIFT_W',
                    options={
                        {label='Ordinary', value=0, pen=COLOR_GRAY},
                        {label='-Well Crafted-', value=1, pen=COLOR_LIGHTBLUE},
                        {label='+Fine Crafted+', value=2, pen=COLOR_BLUE},
                        {label='*Superior*', value=3, pen=COLOR_YELLOW},
                        {label=common.CH_EXCEPTIONAL..'Exceptional'..common.CH_EXCEPTIONAL, value=4, pen=COLOR_BROWN},
                        {label=common.CH_MONEY..'Masterful'..common.CH_MONEY, value=5, pen=COLOR_MAGENTA},
                        {label='Artifact', value=6, pen=COLOR_GREEN},
                    },
                    initial_option=6,
                    on_change=function(val)
                        if self.subviews['min_quality'..suffix]:getOptionValue() > val then
                            self.subviews['min_quality'..suffix]:setOption(val)
                        end
                        self:refresh_list()
                    end,
                },
                widgets.RangeSlider{
                    frame={l=0,w=38, t=3},
                    num_stops=7,
                    get_left_idx_fn=function()
                        return self.subviews['min_quality'..suffix]:getOptionValue() + 1
                    end,
                    get_right_idx_fn=function()
                        return self.subviews['max_quality'..suffix]:getOptionValue() + 1
                    end,
                    on_left_change=function(idx) self.subviews['min_quality'..suffix]:setOption(idx-1, true) end,
                    on_right_change=function(idx) self.subviews['max_quality'..suffix]:setOption(idx-1, true) end,
                },
            },
        },
        widgets.Panel{
            frame={t=12, l=0, h=4},
            subviews={
                widgets.CycleHotkeyLabel{
                    view_id='min_value'..suffix,
                    frame={l=0, t=0, w=18},
                    label='Min value:',
                    label_below=true,
                    key_back='CUSTOM_SHIFT_B',
                    key='CUSTOM_SHIFT_N',
                    options={
                        {label='1'..common.CH_MONEY, value={index=1, value=1}, pen=COLOR_BROWN},
                        {label='20'..common.CH_MONEY, value={index=2, value=20}, pen=COLOR_BROWN},
                        {label='50'..common.CH_MONEY, value={index=3, value=50}, pen=COLOR_BROWN},
                        {label='100'..common.CH_MONEY, value={index=4, value=100}, pen=COLOR_BROWN},
                        {label='500'..common.CH_MONEY, value={index=5, value=500}, pen=COLOR_BROWN},
                        {label='1000'..common.CH_MONEY, value={index=6, value=1000}, pen=COLOR_BROWN},
                        -- max "min" value is less than max "max" value since the range of inf - inf is not useful
                        {label='5000'..common.CH_MONEY, value={index=7, value=5000}, pen=COLOR_BROWN},
                    },
                    initial_option=1,
                    on_change=function(val)
                        if self.subviews['max_value'..suffix]:getOptionValue().value < val.value then
                            self.subviews['max_value'..suffix]:setOption(val.index)
                        end
                        self:refresh_list()
                    end,
                },
                widgets.CycleHotkeyLabel{
                    view_id='max_value'..suffix,
                    frame={l=20, t=0, w=18},
                    label='Max value:',
                    label_below=true,
                    key_back='CUSTOM_SHIFT_T',
                    key='CUSTOM_SHIFT_Y',
                    options={
                        {label='1'..common.CH_MONEY, value={index=1, value=1}, pen=COLOR_BROWN},
                        {label='20'..common.CH_MONEY, value={index=2, value=20}, pen=COLOR_BROWN},
                        {label='50'..common.CH_MONEY, value={index=3, value=50}, pen=COLOR_BROWN},
                        {label='100'..common.CH_MONEY, value={index=4, value=100}, pen=COLOR_BROWN},
                        {label='500'..common.CH_MONEY, value={index=5, value=500}, pen=COLOR_BROWN},
                        {label='1000'..common.CH_MONEY, value={index=6, value=1000}, pen=COLOR_BROWN},
                        {label='Max', value={index=7, value=math.huge}, pen=COLOR_GREEN},
                    },
                    initial_option=7,
                    on_change=function(val)
                        if self.subviews['min_value'..suffix]:getOptionValue().value > val.value then
                            self.subviews['min_value'..suffix]:setOption(val.index)
                        end
                        self:refresh_list()
                    end,
                },
                widgets.RangeSlider{
                    frame={l=0,w=38, t=3},
                    num_stops=7,
                    get_left_idx_fn=function()
                        return self.subviews['min_value'..suffix]:getOptionValue().index
                    end,
                    get_right_idx_fn=function()
                        return self.subviews['max_value'..suffix]:getOptionValue().index
                    end,
                    on_left_change=function(idx) self.subviews['min_value'..suffix]:setOption(idx, true) end,
                    on_right_change=function(idx) self.subviews['max_value'..suffix]:setOption(idx, true) end,
                },
            },
        },
        widgets.ToggleHotkeyLabel{
            view_id='hide_unreachable',
            frame={t=0, l=40, w=30},
            label='Hide unreachable items:',
            options={
                {label='Yes', value=true, pen=COLOR_GREEN},
                {label='No', value=false}
            },
            initial_option=filters.hide_unreachable,
            on_change=function(val)
                filters.hide_unreachable = val
                self:refresh_list()
            end,
        },
        widgets.ToggleHotkeyLabel{
            view_id='hide_forbidden',
            frame={t=1, l=40, w=30},
            label='Hide forbidden items:',
            options={
                {label='Yes', value=true, pen=COLOR_GREEN},
                {label='No', value=false}
            },
            option_gap=3,
            initial_option=filters.hide_forbidden,
            on_change=function(val)
                filters.hide_forbidden = val
                self:refresh_list()
            end,
        },
        widgets.ToggleHotkeyLabel{
            view_id='hide_written',
            frame={t=3, l=40, w=30},
            label='Hide written items:',
            options={
                {label='Yes', value=true, pen=COLOR_GREEN},
                {label='No', value=false}
            },
            option_gap=5,
            initial_option=filters.hide_written,
            on_change=function(val)
                filters.hide_written = val
                self:refresh_list()
            end,
        },
    }
end

function Stocks:init()
    self.cur_page = 1

    self.choices_cache = {}

    self:addviews{
        widgets.CycleHotkeyLabel{
            view_id='sort',
            frame={t=0, l=0, w=21},
            label='Sort by:',
            key='CUSTOM_SHIFT_S',
            options={
                {label='value'..common.CH_DN, value=sort_by_value_desc},
                {label='value'..common.CH_UP, value=sort_by_value_asc},
                {label='name'..common.CH_DN, value=sort_by_name_desc},
                {label='name'..common.CH_UP, value=sort_by_name_asc},
            },
            initial_option=sort_by_status_desc,
            on_change=self:callback('refresh_list', 'sort'),
        },
        -- widgets.ToggleHotkeyLabel{
        --     view_id='trade_bins',
        --     frame={t=0, l=26, w=36},
        --     label='Bins:',
        --     key='CUSTOM_SHIFT_B',
        --     options={
        --         {label='Trade bin with contents', value=true, pen=COLOR_YELLOW},
        --         {label='Trade contents only', value=false, pen=COLOR_GREEN},
        --     },
        --     initial_option=false,
        --     on_change=function() self:refresh_list() end,
        -- },
        widgets.ToggleHotkeyLabel{
            view_id='filters',
            frame={t=3, l=0, w=36},
            label='Show filters:',
            options={
                {label='Yes', value=true, pen=COLOR_GREEN},
                {label='No', value=false}
            },
            initial_option=false,
            on_change=function() self:updateLayout() end,
        },
        widgets.EditField{
            view_id='search',
            frame={t=3, l=40},
            label_text='Search: ',
            on_char=function(ch) return ch:match('[%l -]') end,
        },
        widgets.Panel{
            frame={t=5, l=0, r=0, h=FILTER_HEIGHT},
            frame_style=gui.FRAME_INTERIOR,
            visible=function() return self.subviews.filters:getOptionValue() end,
            on_layout=function()
                local panel_frame = self.subviews.list_panel.frame
                if self.subviews.filters:getOptionValue() then
                    panel_frame.t = 5 + FILTER_HEIGHT + 1
                else
                    panel_frame.t = 5
                end
            end,
            subviews={
                widgets.Panel{
                    frame={t=0, l=0, w=100},
                    visible=true,
                    subviews=get_slider_widgets(self, '1'),
                },
            },
        },
        widgets.Panel{
            view_id='list_panel',
            frame={t=5, l=0, r=0, b=5},
            subviews={
                widgets.CycleHotkeyLabel{
                    view_id='sort_value',
                    frame={t=0, l=2+VALUE_COL_WIDTH+1-6, w=6},
                    options={
                        {label='value', value=sort_noop},
                        {label='value'..common.CH_DN, value=sort_by_value_desc},
                        {label='value'..common.CH_UP, value=sort_by_value_asc},
                    },
                    option_gap=0,
                    on_change=self:callback('refresh_list', 'sort_value'),
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_name',
                    frame={t=0, l=2+VALUE_COL_WIDTH+2, w=5},
                    options={
                        {label='name', value=sort_noop},
                        {label='name'..common.CH_DN, value=sort_by_name_desc},
                        {label='name'..common.CH_UP, value=sort_by_name_asc},
                    },
                    option_gap=0,
                    on_change=self:callback('refresh_list', 'sort_name'),
                },
                widgets.FilteredList{
                    view_id='list',
                    frame={l=0, t=2, r=0, b=0},
                    icon_width=2,
                    -- on_submit=self:callback('toggle_item'),
                    -- on_submit2=self:callback('toggle_range'),
                    -- on_select=self:callback('select_item'),
                },
            }
        },
        widgets.Divider{
            frame={b=4, h=1},
            frame_style=gui.FRAME_INTERIOR,
            frame_style_l=false,
            frame_style_r=false,
        },
        widgets.Label{
            frame={b=2, l=0, r=0},
            text='Click to mark/unmark for trade. Shift click to mark/unmark a range of items.',
        },
        widgets.HotkeyLabel{
            frame={l=0, b=0},
            label='Select all/none',
            key='CUSTOM_CTRL_N',
            on_activate=self:callback('toggle_visible'),
            auto_width=true,
        },
    }

    -- replace the FilteredList's built-in EditField with our own
    self.subviews.list.list.frame.t = 0
    self.subviews.list.edit.visible = false
    self.subviews.list.edit = self.subviews.search
    self.subviews.search.on_change = self.subviews.list:callback('onFilterChange')

    self:reset_cache()
end

function Stocks:refresh_list(sort_widget, sort_fn)
    sort_widget = sort_widget or 'sort'
    sort_fn = sort_fn or self.subviews.sort:getOptionValue()
    if sort_fn == sort_noop then
        self.subviews[sort_widget]:cycle()
        return
    end
    for _,widget_name in ipairs{'sort', 'sort_value', 'sort_name'} do
        self.subviews[widget_name]:setOption(sort_fn)
    end
    local list = self.subviews.list
    local saved_filter = list:getFilter()
    local saved_top = list.list.page_top
    list:setFilter('')
    list:setChoices(self:get_choices(), list:getSelected())
    list:setFilter(saved_filter)
    list.list:on_scrollbar(math.max(0, saved_top - list.list.page_top))
end

local function make_choice_text(value, desc)
    return {
        {width=VALUE_COL_WIDTH, rjustify=true, text=common.obfuscate_value(value)},
        {gap=2, text=desc},
    }
end

local function is_container(item)
    return item and (
        df.item_binst:is_instance(item) or
        item:isFoodStorage()
    )
end

local function contains_non_liquid_powder(container)
    for _, item in ipairs(dfhack.items.getContainedItems(container)) do
        if not item:isLiquidPowder() then return true end
    end
    return false
end

function Stocks:cache_choices(inside_containers, _)
    if self.choices_cache[inside_containers] then return self.choices_cache[inside_containers] end

    local choices = {}
    for _, item in ipairs(df.global.world.items.other.IN_PLAY) do
        if inside_containers and is_container(item) and contains_non_liquid_powder(item) then
            goto continue
        elseif not inside_containers and item.flags.in_inventory then
            goto continue
        end
        local wear_level = item:getWear()
        local desc = dfhack.items.getReadableDescription(item)
        local reachable = false
        for _,depot in ipairs(df.global.world.buildings.other.TRADE_DEPOT) do
            reachable = reachable or dfhack.maps.canWalkBetween(xyz2pos(dfhack.items.getPosition(item)),
                    xyz2pos(depot.centerx, depot.centery, depot.z))
        end
        local data = {
            item=item,
            desc=desc,
            value=common.get_perceived_value(item),
            quality=item.flags.artifact and 6 or item:getQuality(),
            wear=wear_level,
            reachable=reachable,
        }
        local search_key
        if not inside_containers and is_container(item) then
            search_key = make_container_search_key(item, desc)
        else
            search_key = common.make_search_key(desc)
        end
        local entry = {
            search_key=search_key,
            -- icon=curry(get_entry_icon, data),
            data=data,
            text=make_choice_text(data.value, desc),
        }
        table.insert(choices, entry)
        ::continue::
    end

    self.choices_cache[inside_containers] = choices
    return choices
end

local function is_written_work(item)
    if df.item_bookst:is_instance(item) then return true end
    return df.item_toolst:is_instance(item) and item:hasToolUse(df.tool_uses.CONTAIN_WRITING)
end

function Stocks:get_choices()
    local raw_choices = self:cache_choices(self.cur_page-1, --[[self.subviews.trade_bins:getOptionValue()]]nil)
    local choices = {}

    local include_unreachable = not self.subviews.hide_unreachable:getOptionValue()
    local include_forbidden = not self.subviews.hide_forbidden:getOptionValue()
    local include_written = not self.subviews.hide_written:getOptionValue()
    local min_condition = self.subviews['min_condition'..self.cur_page]:getOptionValue()
    local max_condition = self.subviews['max_condition'..self.cur_page]:getOptionValue()
    local min_quality = self.subviews['min_quality'..self.cur_page]:getOptionValue()
    local max_quality = self.subviews['max_quality'..self.cur_page]:getOptionValue()
    local min_value = self.subviews['min_value'..self.cur_page]:getOptionValue().value
    local max_value = self.subviews['max_value'..self.cur_page]:getOptionValue().value

    for _,choice in ipairs(raw_choices) do
        local data = choice.data
        if not include_unreachable and not data.reachable then goto continue end
        if not include_forbidden and data.item.flags.forbid then goto continue end
        if not include_written and is_written_work(data.item) then goto continue end
        if min_condition < data.wear then goto continue end
        if max_condition > data.wear then goto continue end
        if min_quality > data.quality then goto continue end
        if max_quality < data.quality then goto continue end
        if min_value > data.value then goto continue end
        if max_value < data.value then goto continue end
        table.insert(choices, choice)
        ::continue::
    end
    table.sort(choices, self.subviews.sort:getOptionValue())
    return choices
end

local function toggle_item_base(choice, target_value)
    local goodflag = trade.goodflag[choice.data.list_idx][choice.data.item_idx]
    if target_value == nil then
        target_value = not goodflag.selected
    end
    local prev_value = goodflag.selected
    goodflag.selected = target_value
    if choice.data.update_container_fn then
        choice.data.update_container_fn(prev_value, target_value)
    end
    return target_value
end

function Stocks:select_item(idx, choice)
    if not dfhack.internal.getModifiers().shift then
        self.prev_list_idx = self.subviews.list.list:getSelected()
    end
end

function Stocks:toggle_item(idx, choice)
    toggle_item_base(choice)
end

function Stocks:toggle_range(idx, choice)
    if not self.prev_list_idx then
        self:toggle_item(idx, choice)
        return
    end
    local choices = self.subviews.list:getVisibleChoices()
    local list_idx = self.subviews.list.list:getSelected()
    local target_value
    for i = list_idx, self.prev_list_idx, list_idx < self.prev_list_idx and 1 or -1 do
        target_value = toggle_item_base(choices[i], target_value)
    end
    self.prev_list_idx = list_idx
end

function Stocks:toggle_visible()
    local target_value
    for _, choice in ipairs(self.subviews.list:getVisibleChoices()) do
        target_value = toggle_item_base(choice, target_value)
    end
end

function Stocks:reset_cache()
    self.choices = {[0]={}, [1]={}}
    self:refresh_list()
end

StocksScreen = defclass(StocksScreen, gui.ZScreen)
StocksScreen.ATTRS({
    focus_path = "stocks2"
})

function StocksScreen:init()
    self:addviews({Stocks{}})
end

function StocksScreen:onDismiss()
    view = nil
end

if dfhack_flags.module then
    return
end

view = view and view:raise() or StocksScreen{}:show()
