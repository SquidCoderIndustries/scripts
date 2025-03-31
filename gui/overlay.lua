-- overlay plugin gui config
--@ module = true

local gui = require('gui')
local widgets = require('gui.widgets')

local overlay = require('plugins.overlay')

local DIALOG_WIDTH = 59
local LIST_HEIGHT = 14
local HIGHLIGHT_TILE = df.global.init.load_bar_texpos[1]

local SHADOW_FRAME = gui.PANEL_FRAME()
SHADOW_FRAME.signature_pen = false

local to_pen = dfhack.pen.parse

local HIGHLIGHT_FRAME = {
    t_frame_pen = to_pen{tile=df.global.init.texpos_border_n, ch=205, fg=COLOR_GREEN, bg=COLOR_BLACK, tile_fg=COLOR_LIGHTGREEN},
    l_frame_pen = to_pen{tile=df.global.init.texpos_border_w, ch=186, fg=COLOR_GREEN, bg=COLOR_BLACK, tile_fg=COLOR_LIGHTGREEN},
    b_frame_pen = to_pen{tile=df.global.init.texpos_border_s, ch=205, fg=COLOR_GREEN, bg=COLOR_BLACK, tile_fg=COLOR_LIGHTGREEN},
    r_frame_pen = to_pen{tile=df.global.init.texpos_border_e, ch=186, fg=COLOR_GREEN, bg=COLOR_BLACK, tile_fg=COLOR_LIGHTGREEN},
    lt_frame_pen = to_pen{tile=df.global.init.texpos_border_nw, ch=201, fg=COLOR_GREEN, bg=COLOR_BLACK, tile_fg=COLOR_LIGHTGREEN},
    lb_frame_pen = to_pen{tile=df.global.init.texpos_border_sw, ch=200, fg=COLOR_GREEN, bg=COLOR_BLACK, tile_fg=COLOR_LIGHTGREEN},
    rt_frame_pen = to_pen{tile=df.global.init.texpos_border_ne, ch=187, fg=COLOR_GREEN, bg=COLOR_BLACK, tile_fg=COLOR_LIGHTGREEN},
    rb_frame_pen = to_pen{tile=df.global.init.texpos_border_se, ch=188, fg=COLOR_GREEN, bg=COLOR_BLACK, tile_fg=COLOR_LIGHTGREEN},
    signature_pen=false,
}

local function make_highlight_frame_style(frame)
    local frame_style = copyall(HIGHLIGHT_FRAME)
    local fg, bg = COLOR_GREEN, COLOR_LIGHTGREEN
    if frame.t then
        frame_style.t_frame_pen = to_pen{tile=HIGHLIGHT_TILE, ch=205, fg=fg, bg=bg}
    elseif frame.b then
        frame_style.b_frame_pen = to_pen{tile=HIGHLIGHT_TILE, ch=205, fg=fg, bg=bg}
    end
    if frame.l then
        frame_style.l_frame_pen = to_pen{tile=HIGHLIGHT_TILE, ch=186, fg=fg, bg=bg}
    elseif frame.r then
        frame_style.r_frame_pen = to_pen{tile=HIGHLIGHT_TILE, ch=186, fg=fg, bg=bg}
    end
    return frame_style
end

--------------------
-- DraggablePanel --
--------------------

DraggablePanel = defclass(DraggablePanel, widgets.Panel)
DraggablePanel.ATTRS{
    on_click=DEFAULT_NIL,
    name=DEFAULT_NIL,
    draggable=true,
    drag_anchors={frame=true, body=true},
    drag_bound='body',
    widget=DEFAULT_NIL,
}

function DraggablePanel:onInput(keys)
    if keys._MOUSE_L and self:getMousePos() then
        self.on_click()
    end
    return DraggablePanel.super.onInput(self, keys)
end

function DraggablePanel:postUpdateLayout()
    if not self.is_selected then return end
    local frame = self.frame
    local matcher = {t=not not frame.t, b=not not frame.b,
                     l=not not frame.l, r=not not frame.r}
    local parent_rect, frame_rect = self.widget.frame_parent_rect, self.frame_body
    if frame_rect.y1-1 <= parent_rect.y1 then
        frame.t, frame.b = frame_rect.y1-parent_rect.y1-1, nil
    elseif frame_rect.y2+1 >= parent_rect.y2 then
        frame.t, frame.b = nil, parent_rect.y2-frame_rect.y2-1
    end
    if frame_rect.x1-1 <= parent_rect.x1 then
        frame.l, frame.r = frame_rect.x1-parent_rect.x1-1, nil
    elseif frame_rect.x2+1 >= parent_rect.x2 then
        frame.l, frame.r = nil, parent_rect.x2-frame_rect.x2-1
    end
    self.frame_style = make_highlight_frame_style(self.frame)
    if not not frame.t ~= matcher.t or not not frame.b ~= matcher.b
            or not not frame.l ~= matcher.l or not not frame.r ~= matcher.r then
        -- we've changed edge affinity, recalculate our frame
        self:updateLayout()
    end
end

function DraggablePanel:onRenderFrame(dc, rect)
    if self:getMousePos() then
        self.frame_background = to_pen{
                ch=32, fg=COLOR_LIGHTGREEN, bg=COLOR_LIGHTGREEN}
    else
        self.frame_background = nil
    end
    DraggablePanel.super.onRenderFrame(self, dc, rect)
end

-------------------
-- OverlayConfig --
-------------------

OverlayConfig = defclass(OverlayConfig, gui.Screen) -- not a ZScreen since we want to freeze the underlying UI

function OverlayConfig:init()
    -- prevent hotspot widgets from reacting
    overlay.register_trigger_lock_screen(self)

    local contexts = dfhack.gui.getFocusStrings(dfhack.gui.getDFViewscreen(true))
    local interface_width_pct = df.global.init.display.max_interface_percentage

    local main_panel = widgets.Window{
        frame={w=DIALOG_WIDTH, h=LIST_HEIGHT+15},
        resizable=true,
        resize_min={h=20},
        frame_title='Reposition overlay widgets',
    }
    main_panel:addviews{
        widgets.Label{
            frame={t=0, l=0},
            text={
                'Current contexts: ',
                {text=table.concat(contexts, ', '), pen=COLOR_CYAN},
            }},
        widgets.Label{
            frame={t=2, l=0},
            text={
                'Interface width percent: ',
                {text=interface_width_pct, pen=COLOR_CYAN},
            }},
        widgets.CycleHotkeyLabel{
            view_id='filter',
            frame={t=4, l=0},
            key='CUSTOM_CTRL_O',
            label='Showing',
            options={{label='overlays for the current contexts', value='cur'},
                     {label='all overlays', value='all'}},
            on_change=self:callback('refresh_list')},
        widgets.FilteredList{
            view_id='list',
            frame={t=6, b=7},
            on_select=self:callback('highlight_selected'),
        },
        widgets.HotkeyLabel{
            frame={b=5, l=0},
            key='SELECT',
            key_sep=' or drag the on-screen widget to reposition ',
            on_activate=function() self:reposition(self.subviews.list:getSelected()) end,
            scroll_keys={},
        },
        widgets.HotkeyLabel{
            frame={b=3, l=0},
            key='CUSTOM_CTRL_D',
            scroll_keys={},
            label='reset selected widget to its default position',
            on_activate=self:callback('reset'),
        },
        widgets.WrappedLabel{
            frame={b=0, l=0},
            scroll_keys={},
            text_to_wrap='When repositioning a widget, touch a boundary edge'..
                ' to anchor the widget to that edge.',
        },
    }

    self:addviews{
        widgets.Divider{
            view_id='left_border',
            frame={l=0, w=1},
            frame_style=gui.FRAME_THIN,
        },
        widgets.Divider{
            view_id='right_border',
            frame={r=0, w=1},
            frame_style=gui.FRAME_THIN,
        },
        main_panel,
    }

    self:refresh_list()
end

local function make_highlight_frame(widget_frame)
    local frame = {h=widget_frame.h+2, w=widget_frame.w+2}
    if widget_frame.l then frame.l = widget_frame.l - 1
    else frame.r = widget_frame.r - 1 end
    if widget_frame.t then frame.t = widget_frame.t - 1
    else frame.b = widget_frame.b - 1 end
    return frame
end

function OverlayConfig:refresh_list(filter)
    local choices = {}
    local scr = dfhack.gui.getDFViewscreen(true)
    local state = overlay.get_state()
    local list = self.subviews.list
    local make_on_click_fn = function(idx)
        return function() list.list:setSelected(idx) end
    end
    for _,name in ipairs(state.index) do
        local db_entry = state.db[name]
        local widget = db_entry.widget
        if widget.fullscreen or widget.full_interface or
            widget.frame.w == 0 or widget.frame.h == 0
        then
            goto continue
        end
        if (not widget.hotspot or #widget.viewscreens > 0) and filter ~= 'all' then
            for _,vs in ipairs(overlay.normalize_list(widget.viewscreens)) do
                if dfhack.gui.matchFocusString(overlay.simplify_viewscreen_name(vs), scr) then
                    goto matched
                end
            end
            goto continue
        end
        ::matched::
        local panel = DraggablePanel{
            frame=make_highlight_frame(widget.frame),
            frame_style=SHADOW_FRAME,
            on_click=make_on_click_fn(#choices+1),
            name=name,
            widget=widget,
        }
        panel.on_drag_end = function(success)
            if (success) then
                local frame = panel.frame
                local frame_rect = panel.frame_rect
                local frame_parent_rect = panel.frame_parent_rect
                local posx = frame.l and tostring(frame_rect.x1+2)
                        or tostring(frame_rect.x2-frame_parent_rect.width-1)
                local posy = frame.t and tostring(frame_rect.y1+2)
                        or tostring(frame_rect.y2-frame_parent_rect.height-1)
                overlay.overlay_command({'position', name, posx, posy}, true)
            end
            self.reposition_panel = nil
        end
        local cfg = state.config[name]
        local tokens = {}
        table.insert(tokens, name)
        table.insert(tokens, {text=function()
                if self.reposition_panel and self.reposition_panel == panel then
                    return ' (repositioning with keyboard)'
                end
                return ''
            end})
        table.insert(choices,
                {text=tokens, enabled=cfg.enabled, name=name, panel=panel,
                 widget=widget, search_key=name})
        ::continue::
    end
    local old_filter = list:getFilter()
    list:setChoices(choices)
    list:setFilter(old_filter)
    if self.frame_parent_rect then
        self:postUpdateLayout()
    end
end

function OverlayConfig:highlight_selected(_, obj)
    if self.selected_panel then
        self.selected_panel.frame_style = SHADOW_FRAME
        self.selected_panel.is_selected = false
        self.selected_panel = nil
    end
    if self.reposition_panel then
        self.reposition_panel:setKeyboardDragEnabled(false)
        self.reposition_panel = nil
    end
    if not obj or not obj.panel then return end
    local panel = obj.panel
    panel.is_selected = true
    panel.frame_style = make_highlight_frame_style(panel.frame)
    self.selected_panel = panel
end

function OverlayConfig:reposition(_, obj)
    if not obj then return end
    self.reposition_panel = obj.panel
    if self.reposition_panel then
        self.reposition_panel:setKeyboardDragEnabled(true)
    end
end

function OverlayConfig:reset()
    local _,obj = self.subviews.list:getSelected()
    if not obj or not obj.panel then return end
    overlay.overlay_command({'position', obj.panel.name, 'default'}, true)
    self:refresh_list(self.subviews.filter:getOptionValue())
    self:updateLayout()
end

function OverlayConfig:onDismiss()
    view = nil
end

function OverlayConfig:preUpdateLayout(parent_rect)
    local interface_rect = gui.get_interface_rect()
    local left, right = self.subviews.left_border, self.subviews.right_border
    left.frame.l = interface_rect.x1 - 1
    left.visible = left.frame.l >= 0
    right.frame.r = nil
    right.frame.l = interface_rect.x2 + 1
    right.visible = right.frame.l < parent_rect.width
end

function OverlayConfig:postUpdateLayout()
    local rect = gui.ViewRect{rect=gui.get_interface_rect()}
    for _,choice in ipairs(self.subviews.list:getChoices()) do
        choice.panel:updateLayout(rect)
    end
end

function OverlayConfig:onInput(keys)
    if self.reposition_panel then
        if self.reposition_panel:onInput(keys) then
            return true
        end
    end
    if keys.LEAVESCREEN or keys._MOUSE_R then
        self:dismiss()
        return true
    end
    if self.selected_panel then
        if self.selected_panel:onInput(keys) then
            return true
        end
    end
    if self:inputToSubviews(keys) then
        return true
    end
    for _,choice in ipairs(self.subviews.list:getVisibleChoices()) do
        if choice.panel and choice.panel:onInput(keys) then
            return true
        end
    end
end

function OverlayConfig:onRenderFrame()
    self:renderParent()
    local interface_area_painter = gui.Painter.new(gui.ViewRect{rect=gui.get_interface_rect()})
    for _,choice in ipairs(self.subviews.list:getVisibleChoices()) do
        local panel = choice.panel
        if panel and panel ~= self.selected_panel then
            panel:render(interface_area_painter)
        end
    end
    if self.selected_panel then
        self.render_selected_panel = function()
            self.selected_panel:render(interface_area_painter)
        end
    else
        self.render_selected_panel = nil
    end
end

function OverlayConfig:renderSubviews(dc)
    OverlayConfig.super.renderSubviews(self, dc)
    if self.render_selected_panel then
        self.render_selected_panel()
    end
end

if dfhack_flags.module then
    return
end

view = view or OverlayConfig{}:show()
