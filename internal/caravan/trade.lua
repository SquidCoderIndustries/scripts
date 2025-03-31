--@ module = true

-- TODO: the category checkbox that indicates whether all items in the category
-- are selected can be incorrect after the overlay adjusts the container
-- selection. the state is in trade.current_type_a_flag, but figuring out which
-- index to modify is non-trivial.

local common = reqscript('internal/caravan/common')
local gui = require('gui')
local overlay = require('plugins.overlay')
local predicates = reqscript('internal/caravan/predicates')
local utils = require('utils')
local widgets = require('gui.widgets')

trader_selected_state = trader_selected_state or {}
broker_selected_state = broker_selected_state or {}
handle_ctrl_click_on_render = handle_ctrl_click_on_render or false
handle_shift_click_on_render = handle_shift_click_on_render or false

local trade = df.global.game.main_interface.trade

-- -------------------
-- Trade
--

Trade = defclass(Trade, widgets.Window)
Trade.ATTRS {
    frame_title='Select trade goods',
    frame={w=86, h=47},
    resizable=true,
    resize_min={w=48, h=40},
}

local function get_entry_icon(data)
    if trade.goodflag[data.list_idx][data.item_idx].selected then
        return common.ALL_PEN
    end
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

local function sort_by_status_desc(a, b)
    local a_selected = get_entry_icon(a.data)
    local b_selected = get_entry_icon(b.data)
    if a_selected == b_selected then
        return sort_by_value_desc(a, b)
    end
    return a_selected
end

local function sort_by_status_asc(a, b)
    local a_selected = get_entry_icon(a.data)
    local b_selected = get_entry_icon(b.data)
    if a_selected == b_selected then
        return sort_by_value_desc(a, b)
    end
    return b_selected
end

local STATUS_COL_WIDTH = 7
local VALUE_COL_WIDTH = 6
local FILTER_HEIGHT = 18

function Trade:init()
    self.cur_page = 1
    self.filters = {'', ''}
    self.predicate_contexts = {{name='trade_caravan'}, {name='trade_fort'}}

    self.animal_ethics = common.is_animal_lover_caravan(trade.mer)
    self.wood_ethics = common.is_tree_lover_caravan(trade.mer)
    self.banned_items = common.get_banned_items()
    self.risky_items = common.get_risky_items(self.banned_items)

    self:addviews{
        widgets.CycleHotkeyLabel{
            view_id='sort',
            frame={t=0, l=0, w=21},
            label='Sort by:',
            key='CUSTOM_SHIFT_S',
            options={
                {label='status'..common.CH_DN, value=sort_by_status_desc},
                {label='status'..common.CH_UP, value=sort_by_status_asc},
                {label='value'..common.CH_DN, value=sort_by_value_desc},
                {label='value'..common.CH_UP, value=sort_by_value_asc},
                {label='name'..common.CH_DN, value=sort_by_name_desc},
                {label='name'..common.CH_UP, value=sort_by_name_asc},
            },
            initial_option=sort_by_status_desc,
            on_change=self:callback('refresh_list', 'sort'),
        },
        widgets.ToggleHotkeyLabel{
            view_id='trade_bins',
            frame={t=0, l=26, w=36},
            label='Bins:',
            key='CUSTOM_SHIFT_B',
            options={
                {label='Trade bin with contents', value=true, pen=COLOR_YELLOW},
                {label='Trade contents only', value=false, pen=COLOR_GREEN},
            },
            initial_option=false,
            on_change=function() self:refresh_list() end,
        },
        widgets.TabBar{
            frame={t=2, l=0},
            labels={
                'Caravan goods',
                'Fort goods',
            },
            on_select=function(idx)
                local list = self.subviews.list
                self.filters[self.cur_page] = list:getFilter()
                list:setFilter(self.filters[idx])
                self.cur_page = idx
                self:refresh_list()
            end,
            get_cur_page=function() return self.cur_page end,
        },
        widgets.ToggleHotkeyLabel{
            view_id='filters',
            frame={t=5, l=0, w=36},
            label='Show filters:',
            key='CUSTOM_SHIFT_F',
            options={
                {label='Yes', value=true, pen=COLOR_GREEN},
                {label='No', value=false}
            },
            initial_option=false,
            on_change=function() self:updateLayout() end,
        },
        widgets.EditField{
            view_id='search',
            frame={t=5, l=40},
            label_text='Search: ',
            on_char=function(ch) return ch:match('[%l -]') end,
        },
        widgets.Panel{
            frame={t=7, l=0, r=0, h=FILTER_HEIGHT},
            frame_style=gui.FRAME_INTERIOR,
            visible=function() return self.subviews.filters:getOptionValue() end,
            on_layout=function()
                local panel_frame = self.subviews.list_panel.frame
                if self.subviews.filters:getOptionValue() then
                    panel_frame.t = 7 + FILTER_HEIGHT + 1
                else
                    panel_frame.t = 7
                end
            end,
            subviews={
                widgets.Panel{
                    frame={t=0, l=0, w=38},
                    visible=function() return self.cur_page == 1 end,
                    subviews=common.get_slider_widgets(self, '1'),
                },
                widgets.Panel{
                    frame={t=0, l=0, w=38},
                    visible=function() return self.cur_page == 2 end,
                    subviews=common.get_slider_widgets(self, '2'),
                },
                widgets.Panel{
                    frame={b=0, l=40, r=0, h=2},
                    visible=function() return self.cur_page == 1 end,
                    subviews=common.get_advanced_filter_widgets(self, self.predicate_contexts[1]),
                },
                widgets.Panel{
                    frame={t=1, l=40, r=0},
                    visible=function() return self.cur_page == 2 end,
                    subviews=common.get_info_widgets(self, {trade.mer.buy_prices}, true, self.predicate_contexts[2]),
                },
            },
        },
        widgets.Panel{
            view_id='list_panel',
            frame={t=7, l=0, r=0, b=5},
            subviews={
                widgets.CycleHotkeyLabel{
                    view_id='sort_status',
                    frame={t=0, l=0, w=7},
                    options={
                        {label='status', value=sort_noop},
                        {label='status'..common.CH_DN, value=sort_by_status_desc},
                        {label='status'..common.CH_UP, value=sort_by_status_asc},
                    },
                    initial_option=sort_by_status_desc,
                    option_gap=0,
                    on_change=self:callback('refresh_list', 'sort_status'),
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_value',
                    frame={t=0, l=STATUS_COL_WIDTH+2+VALUE_COL_WIDTH+1-6, w=6},
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
                    frame={t=0, l=STATUS_COL_WIDTH+2+VALUE_COL_WIDTH+2, w=5},
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
                    on_submit=self:callback('toggle_item'),
                    on_submit2=self:callback('toggle_range'),
                    on_select=self:callback('select_item'),
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

function Trade:refresh_list(sort_widget, sort_fn)
    sort_widget = sort_widget or 'sort'
    sort_fn = sort_fn or self.subviews.sort:getOptionValue()
    if sort_fn == sort_noop then
        self.subviews[sort_widget]:cycle()
        return
    end
    for _,widget_name in ipairs{'sort', 'sort_status', 'sort_value', 'sort_name'} do
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

local function is_ethical_product(item, animal_ethics, wood_ethics)
    if not animal_ethics and not wood_ethics then return true end
    -- bin contents are already split out; no need to double-check them
    if item.flags.container and not df.item_binst:is_instance(item) then
        for _, contained_item in ipairs(dfhack.items.getContainedItems(item)) do
            if (animal_ethics and contained_item:isAnimalProduct()) or
                (wood_ethics and common.has_wood(contained_item))
            then
                return false
            end
        end
    end

    return (not animal_ethics or not item:isAnimalProduct()) and
        (not wood_ethics or not common.has_wood(item))
end

local function make_choice_text(value, desc)
    return {
        {width=STATUS_COL_WIDTH+VALUE_COL_WIDTH, rjustify=true, text=common.obfuscate_value(value)},
        {gap=2, text=desc},
    }
end

function Trade:cache_choices(list_idx, trade_bins)
    if self.choices[list_idx][trade_bins] then return self.choices[list_idx][trade_bins] end

    local goodflags = trade.goodflag[list_idx]
    local trade_bins_choices, notrade_bins_choices = {}, {}
    local parent_data
    for item_idx, item in ipairs(trade.good[list_idx]) do
        local goodflag = goodflags[item_idx]
        if not goodflag.contained then
            parent_data = nil
        end
        local is_banned, is_risky = common.scan_banned(item, self.risky_items)
        local is_requested = dfhack.items.isRequestedTradeGood(item, trade.mer)
        local wear_level = item:getWear()
        local desc = dfhack.items.getReadableDescription(item)
        local is_ethical = is_ethical_product(item, self.animal_ethics, self.wood_ethics)
        local data = {
            desc=desc,
            value=common.get_perceived_value(item, trade.mer),
            list_idx=list_idx,
            item=item,
            item_idx=item_idx,
            quality=item.flags.artifact and 6 or item:getQuality(),
            wear=wear_level,
            has_foreign=item.flags.foreign,
            has_banned=is_banned,
            has_risky=is_risky,
            has_requested=is_requested,
            has_ethical=is_ethical,
            ethical_mixed=false,
        }
        if parent_data then
            data.update_container_fn = function(from, to)
                -- TODO
            end
            parent_data.has_banned = parent_data.has_banned or is_banned
            parent_data.has_risky = parent_data.has_risky or is_risky
            parent_data.has_requested = parent_data.has_requested or is_requested
            parent_data.ethical_mixed = parent_data.ethical_mixed or (parent_data.has_ethical ~= is_ethical)
            parent_data.has_ethical = parent_data.has_ethical or is_ethical
        end
        local is_container = df.item_binst:is_instance(item)
        local search_key
        if (trade_bins and is_container) or item:isFoodStorage() then
            search_key = common.make_container_search_key(item, desc)
        else
            search_key = common.make_search_key(desc)
        end
        local choice = {
            search_key=search_key,
            icon=curry(get_entry_icon, data),
            data=data,
            text=make_choice_text(data.value, desc),
        }
        if not data.update_container_fn then
            table.insert(trade_bins_choices, choice)
        end
        if data.update_container_fn or not is_container then
            table.insert(notrade_bins_choices, choice)
        end
        if is_container then parent_data = data end
    end

    self.choices[list_idx][true] = trade_bins_choices
    self.choices[list_idx][false] = notrade_bins_choices
    return self:cache_choices(list_idx, trade_bins)
end

function Trade:get_choices()
    local raw_choices = self:cache_choices(self.cur_page-1, self.subviews.trade_bins:getOptionValue())
    local provenance = self.subviews.provenance:getOptionValue()
    local banned = self.cur_page == 1 and 'ignore' or self.subviews.banned:getOptionValue()
    local only_agreement = self.cur_page == 2 and self.subviews.only_agreement:getOptionValue() or false
    local ethical = self.cur_page == 1 and 'show' or self.subviews.ethical:getOptionValue()
    local strict_ethical_bins = self.subviews.strict_ethical_bins:getOptionValue()
    local min_condition = self.subviews['min_condition'..self.cur_page]:getOptionValue()
    local max_condition = self.subviews['max_condition'..self.cur_page]:getOptionValue()
    local min_quality = self.subviews['min_quality'..self.cur_page]:getOptionValue()
    local max_quality = self.subviews['max_quality'..self.cur_page]:getOptionValue()
    local min_value = self.subviews['min_value'..self.cur_page]:getOptionValue().value
    local max_value = self.subviews['max_value'..self.cur_page]:getOptionValue().value
    local choices = {}
    for _,choice in ipairs(raw_choices) do
        local data = choice.data
        if ethical ~= 'show' then
            if strict_ethical_bins and data.ethical_mixed then goto continue end
            if ethical == 'hide' and data.has_ethical then goto continue end
            if ethical == 'only' and not data.has_ethical then goto continue end
        end
        if provenance ~= 'all' then
            if (provenance == 'local' and data.has_foreign) or
                (provenance == 'foreign' and not data.has_foreign)
            then
                goto continue
            end
        end
        if min_condition < data.wear then goto continue end
        if max_condition > data.wear then goto continue end
        if min_quality > data.quality then goto continue end
        if max_quality < data.quality then goto continue end
        if min_value > data.value then goto continue end
        if max_value < data.value then goto continue end
        if only_agreement and not data.has_requested then goto continue end
        if banned ~= 'ignore' then
            if data.has_banned or (banned ~= 'banned_only' and data.has_risky) then
                goto continue
            end
        end
        if not predicates.pass_predicates(self.predicate_contexts[self.cur_page], data.item) then
            goto continue
        end
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

function Trade:select_item(idx, choice)
    if not dfhack.internal.getModifiers().shift then
        self.prev_list_idx = self.subviews.list.list:getSelected()
    end
end

function Trade:toggle_item(idx, choice)
    toggle_item_base(choice)
end

function Trade:toggle_range(idx, choice)
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

function Trade:toggle_visible()
    local target_value
    for _, choice in ipairs(self.subviews.list:getVisibleChoices()) do
        target_value = toggle_item_base(choice, target_value)
    end
end

function Trade:reset_cache()
    self.choices = {[0]={}, [1]={}}
    self:refresh_list()
end

-- -------------------
-- TradeScreen
--

trade_view = trade_view or nil

TradeScreen = defclass(TradeScreen, gui.ZScreen)
TradeScreen.ATTRS {
    focus_path='caravan/trade',
}

function TradeScreen:init()
    self.trade_window = Trade{}
    self:addviews{self.trade_window}
end

function TradeScreen:onInput(keys)
    if self.reset_pending then return false end
    local handled = TradeScreen.super.onInput(self, keys)
    if keys._MOUSE_L and not self.trade_window:getMouseFramePos() then
        -- "trade" or "offer" buttons may have been clicked and we need to reset the cache
        self.reset_pending = true
    end
    return handled
end

function TradeScreen:onRenderFrame()
    if not df.global.game.main_interface.trade.open then
        if trade_view then trade_view:dismiss() end
    elseif self.reset_pending and
        (dfhack.gui.matchFocusString('dfhack/lua/caravan/trade') or
         dfhack.gui.matchFocusString('dwarfmode/Trade/Default'))
    then
        self.reset_pending = nil
        self.trade_window:reset_cache()
    end
end

function TradeScreen:onDismiss()
    trade_view = nil
end

-- -------------------
-- TradeOverlay
--

local MARGIN_HEIGHT = 26 -- screen height *other* than the list

local function set_height(list_idx, delta)
    trade.i_height[list_idx] = trade.i_height[list_idx] + delta
    if delta >= 0 then return end
    _,screen_height = dfhack.screen.getWindowSize()
    -- list only increments in three tiles at a time
    local page_height = ((screen_height - MARGIN_HEIGHT) // 3) * 3
    trade.scroll_position_item[list_idx] = math.max(0,
            math.min(trade.scroll_position_item[list_idx],
                     trade.i_height[list_idx] - page_height))
end

local function flags_match(goodflag1, goodflag2)
    return goodflag1.selected == goodflag2.selected and
        goodflag1.contained == goodflag2.contained and
        goodflag1.container_collapsed == goodflag2.container_collapsed and
        goodflag1.filtered_off == goodflag2.filtered_off
end

local function select_shift_clicked_container_items(new_state, old_state_fn, list_idx)
    -- if ctrl is also held, collapse the container too
    local also_collapse = dfhack.internal.getModifiers().ctrl
    local collapsed_item_count, collapsing_container, in_target_container = 0, false, false
    for k, goodflag in ipairs(new_state) do
        if in_target_container then
            if not goodflag.contained then break end
            goodflag.selected = true
            if collapsing_container then
                collapsed_item_count = collapsed_item_count + 1
            end
            goto continue
        end

        local old_goodflag = old_state_fn(k)
        if flags_match(goodflag, old_goodflag) then goto continue end
        local is_container = df.item_binst:is_instance(trade.good[list_idx][k])
        if not is_container then goto continue end

        -- deselect the container itself
        goodflag.selected = false

        if also_collapse or old_goodflag.container_collapsed then
            goodflag.container_collapsed = true
            collapsing_container = not old_goodflag.container_collapsed
        end
        in_target_container = true

        ::continue::
    end

    if collapsed_item_count > 0 then
        set_height(list_idx, collapsed_item_count * -3)
    end
end

-- collapses uncollapsed containers and restores the selection state for the container
-- and contained items
local function toggle_ctrl_clicked_containers(new_state, old_state_fn, list_idx)
    local toggled_item_count, in_target_container, is_collapsing = 0, false, false
    for k, goodflag in ipairs(new_state) do
        local old_goodflag = old_state_fn(k)
        if in_target_container then
            if not goodflag.contained then break end
            toggled_item_count = toggled_item_count + 1
            utils.assign(goodflag, old_goodflag)
            goto continue
        end

        if flags_match(goodflag, old_goodflag) or goodflag.contained then goto continue end
        local is_container = df.item_binst:is_instance(trade.good[list_idx][k])
        if not is_container then goto continue end

        goodflag.selected = old_goodflag.selected
        goodflag.container_collapsed = not old_goodflag.container_collapsed
        in_target_container = true
        is_collapsing = goodflag.container_collapsed

        ::continue::
    end

    if toggled_item_count > 0 then
        set_height(list_idx, toggled_item_count * 3 * (is_collapsing and -1 or 1))
    end
end

local function collapseTypes(types_list, list_idx)
    local type_on_count = 0

    for k in ipairs(types_list) do
        local type_on = trade.current_type_a_on[list_idx][k]
        if type_on then
            type_on_count = type_on_count + 1
        end
        types_list[k] = false
    end

    trade.i_height[list_idx] = type_on_count * 3
    trade.scroll_position_item[list_idx] = 0
end

local function collapseAllTypes()
   collapseTypes(trade.current_type_a_expanded[0], 0)
   collapseTypes(trade.current_type_a_expanded[1], 1)
end

local function collapseContainers(item_list, list_idx)
    local num_items_collapsed = 0
    for k, goodflag in ipairs(item_list) do
        if goodflag.contained then goto continue end

        local item = trade.good[list_idx][k]
        local is_container = df.item_binst:is_instance(item)
        if not is_container then goto continue end

        if not goodflag.container_collapsed then
            goodflag.container_collapsed = true
            num_items_collapsed = num_items_collapsed + #dfhack.items.getContainedItems(item)
        end

        ::continue::
    end

    if num_items_collapsed > 0 then
        set_height(list_idx, num_items_collapsed * -3)
    end
end

local function collapseAllContainers()
    collapseContainers(trade.goodflag[0], 0)
    collapseContainers(trade.goodflag[1], 1)
end

local function collapseEverything()
    collapseAllContainers()
    collapseAllTypes()
end

local function copyGoodflagState()
    -- utils.clone will return a lua table, with indices offset by 1
    -- we'll use getSavedGoodflag to map the index back to the original value
    trader_selected_state = utils.clone(trade.goodflag[0], true)
    broker_selected_state = utils.clone(trade.goodflag[1], true)
end

local function getSavedGoodflag(saved_state, k)
    return saved_state[k+1]
end

TradeOverlay = defclass(TradeOverlay, overlay.OverlayWidget)
TradeOverlay.ATTRS{
    desc='Adds convenience functions for working with bins to the trade screen.',
    default_pos={x=-3,y=-12},
    default_enabled=true,
    viewscreens='dwarfmode/Trade/Default',
    frame={w=27, h=13},
    frame_style=gui.MEDIUM_FRAME,
    frame_background=gui.CLEAR_PEN,
}

function TradeOverlay:init()
    self:addviews{
        widgets.Label{
            frame={t=0, l=0},
            text={
                {text='Shift+Click checkbox', pen=COLOR_LIGHTGREEN}, ':',
                NEWLINE,
                '  select items inside bin',
            },
        },
        widgets.Label{
            frame={t=3, l=0},
            text={
                {text='Ctrl+Click checkbox', pen=COLOR_LIGHTGREEN}, ':',
                NEWLINE,
                '  collapse/expand bin',
            },
        },
        widgets.HotkeyLabel{
            frame={t=6, l=0},
            label='collapse bins',
            key='CUSTOM_CTRL_C',
            on_activate=collapseAllContainers,
        },
        widgets.HotkeyLabel{
            frame={t=7, l=0},
            label='collapse all',
            key='CUSTOM_CTRL_X',
            on_activate=collapseEverything,
        },
        widgets.Label{
            frame={t=9, l=0},
            text = 'Shift+Scroll',
            text_pen=COLOR_LIGHTGREEN,
        },
        widgets.Label{
            frame={t=9, l=12},
            text = ': fast scroll',
        },
    }
end

-- do our alterations *after* the vanilla response to the click has registered. otherwise
-- it's very difficult to figure out which item has been clicked
function TradeOverlay:onRenderBody(dc)
    if handle_shift_click_on_render then
        handle_shift_click_on_render = false
        select_shift_clicked_container_items(trade.goodflag[0], curry(getSavedGoodflag, trader_selected_state), 0)
        select_shift_clicked_container_items(trade.goodflag[1], curry(getSavedGoodflag, broker_selected_state), 1)
    elseif handle_ctrl_click_on_render then
        handle_ctrl_click_on_render = false
        toggle_ctrl_clicked_containers(trade.goodflag[0], curry(getSavedGoodflag, trader_selected_state), 0)
        toggle_ctrl_clicked_containers(trade.goodflag[1], curry(getSavedGoodflag, broker_selected_state), 1)
    end
end

function TradeOverlay:onInput(keys)
    if TradeOverlay.super.onInput(self, keys) then return true end

    if keys._MOUSE_L then
        if dfhack.internal.getModifiers().shift then
            handle_shift_click_on_render = true
            copyGoodflagState()
        elseif dfhack.internal.getModifiers().ctrl then
            handle_ctrl_click_on_render = true
            copyGoodflagState()
        end
    end
end

-- -------------------
-- TradeBannerOverlay
--

TradeBannerOverlay = defclass(TradeBannerOverlay, overlay.OverlayWidget)
TradeBannerOverlay.ATTRS{
    desc='Adds link to the trade screen to launch the DFHack trade UI.',
    default_pos={x=-31,y=-7},
    default_enabled=true,
    viewscreens='dwarfmode/Trade/Default',
    frame={w=25, h=1},
    frame_background=gui.CLEAR_PEN,
}

function TradeBannerOverlay:init()
    self:addviews{
        widgets.TextButton{
            frame={t=0, l=0},
            label='DFHack trade UI',
            key='CUSTOM_CTRL_T',
            enabled=function() return trade.stillunloading == 0 and trade.havetalker == 1 end,
            on_activate=function() trade_view = trade_view and trade_view:raise() or TradeScreen{}:show() end,
        },
    }
end

function TradeBannerOverlay:onInput(keys)
    if TradeBannerOverlay.super.onInput(self, keys) then return true end

    if keys._MOUSE_R or keys.LEAVESCREEN then
        if trade_view then
            trade_view:dismiss()
        end
    end
end

-- -------------------
-- Ethics
--

Ethics = defclass(Ethics, widgets.Window)
Ethics.ATTRS {
    frame_title='Ethical transgressions',
    frame={w=45, h=30},
    resizable=true,
}

function Ethics:init()
    self.choices = {}
    self.animal_ethics = common.is_animal_lover_caravan(trade.mer)
    self.wood_ethics = common.is_tree_lover_caravan(trade.mer)

    self:addviews{
        widgets.Label{
            frame={l=0, t=0},
            text={
                'You have ',
                {text=self:callback('get_transgression_count'), pen=self:callback('get_transgression_color')},
                ' item',
                {text=function() return self:get_transgression_count() == 1 and '' or 's' end},
                ' selected for trade', NEWLINE,
                'that would offend the merchants:',
            },
        },
        widgets.List{
            view_id='list',
            frame={l=0, r=0, t=3, b=2},
        },
        widgets.HotkeyLabel{
            frame={l=0, b=0},
            key='CUSTOM_CTRL_N',
            label='Deselect items in trade list',
            auto_width=true,
            on_activate=self:callback('deselect_transgressions'),
        },
    }

    self:rescan()
end

function Ethics:get_transgression_count()
    return #self.choices
end

function Ethics:get_transgression_color()
    return next(self.choices) and COLOR_LIGHTRED or COLOR_LIGHTGREEN
end

-- also used by confirm
function for_selected_item(list_idx, fn)
    local goodflags = trade.goodflag[list_idx]
    local in_selected_container = false
    for item_idx, item in ipairs(trade.good[list_idx]) do
        local goodflag = goodflags[item_idx]
        if not goodflag.contained then
            in_selected_container = goodflag.selected
        end
        if in_selected_container or goodflag.selected then
            if fn(item_idx, item) then
                return
            end
        end
    end
end

local function for_ethics_violation(fn, animal_ethics, wood_ethics)
    if not animal_ethics and not wood_ethics then return end
    for_selected_item(1, function(item_idx, item)
        if not is_ethical_product(item, animal_ethics, wood_ethics) then
            if fn(item_idx, item) then return true end
        end
    end)
end

function Ethics:rescan()
    local choices = {}
    for_ethics_violation(function(item_idx, item)
        local choice = {
            text=dfhack.items.getReadableDescription(item),
            data={item_idx=item_idx},
        }
        table.insert(choices, choice)
    end, self.animal_ethics, self.wood_ethics)

    self.subviews.list:setChoices(choices)
    self.choices = choices
end

function Ethics:deselect_transgressions()
    local goodflags = trade.goodflag[1]
    for _,choice in ipairs(self.choices) do
        goodflags[choice.data.item_idx].selected = false
    end
    self:rescan()
end

-- -------------------
-- EthicsScreen
--

ethics_view = ethics_view or nil

EthicsScreen = defclass(EthicsScreen, gui.ZScreen)
EthicsScreen.ATTRS {
    focus_path='caravan/trade/ethics',
}

function EthicsScreen:init()
    self.ethics_window = Ethics{}
    self:addviews{self.ethics_window}
end

function EthicsScreen:onInput(keys)
    if self.reset_pending then return false end
    local handled = EthicsScreen.super.onInput(self, keys)
    if keys._MOUSE_L and not self.ethics_window:getMouseFramePos() then
        -- check for modified selection
        self.reset_pending = true
    end
    return handled
end

function EthicsScreen:onRenderFrame()
    if not df.global.game.main_interface.trade.open then
        if ethics_view then ethics_view:dismiss() end
    elseif self.reset_pending and
        (dfhack.gui.matchFocusString('dfhack/lua/caravan/trade') or
         dfhack.gui.matchFocusString('dwarfmode/Trade/Default'))
    then
        self.reset_pending = nil
        self.ethics_window:rescan()
    end
end

function EthicsScreen:onDismiss()
    ethics_view = nil
end

-- --------------------------
-- TradeEthicsWarningOverlay
--

-- also called by confirm
function has_ethics_violation()
    local violated = false
    for_ethics_violation(function()
        violated = true
        return true
    end, common.is_animal_lover_caravan(trade.mer), common.is_tree_lover_caravan(trade.mer))
    return violated
end

TradeEthicsWarningOverlay = defclass(TradeEthicsWarningOverlay, overlay.OverlayWidget)
TradeEthicsWarningOverlay.ATTRS{
    desc='Adds warning to the trade screen when you are about to offend the elves.',
    default_pos={x=-54,y=-5},
    default_enabled=true,
    viewscreens='dwarfmode/Trade/Default',
    frame={w=9, h=2},
    visible=has_ethics_violation,
}

function TradeEthicsWarningOverlay:init()
    self:addviews{
        widgets.BannerPanel{
            frame={l=0, w=9},
            subviews={
                widgets.Label{
                    frame={l=1, r=1},
                    text={
                        'Ethics', NEWLINE,
                        'warning',
                    },
                    on_click=function() ethics_view = ethics_view and ethics_view:raise() or EthicsScreen{}:show() end,
                    text_pen=COLOR_LIGHTRED,
                    auto_width=false,
                },
            },
        },
    }
end

function TradeEthicsWarningOverlay:preUpdateLayout(rect)
    self.frame.w = (rect.width - 95) // 2
end

function TradeEthicsWarningOverlay:onInput(keys)
    if TradeEthicsWarningOverlay.super.onInput(self, keys) then return true end

    if keys._MOUSE_R or keys.LEAVESCREEN then
        if ethics_view then
            ethics_view:dismiss()
        end
    end
end
