local gui = require('gui')
local spectate = require('plugins.spectate')
local widgets = require('gui.widgets')

Spectate = defclass(Spectate, widgets.Window)
Spectate.ATTRS {
    frame_title='Spectate',
    frame={w=50, h=45},
    resizable=true,
    resize_min={w=50, h=20},
}

function Spectate:init()
    self:addviews{
    }
end

SpectateScreen = defclass(SpectateScreen, gui.ZScreen)
SpectateScreen.ATTRS {
    focus_path='spectate',
}

function SpectateScreen:init()
    self:addviews{Spectate{}}
end

function SpectateScreen:onDismiss()
    view = nil
end

view = view and view:raise() or SpectateScreen{}:show()
