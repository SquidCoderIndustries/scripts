--@module = true
--@enable = true

local argparse = require('argparse')
local repeatutil = require("repeat-util")
local utils = require('utils')

local GLOBAL_KEY = 'timestream'

local SETTINGS = {
    {
        name='fps',
        validate=function(arg)
            local val = argparse.positiveInt(arg, 'fps')
            if val < 10 then qerror('target fps must be at least 10') end
            return val
        end,
        default=function() return df.global.init.fps_cap end,
    },
    {
        name='calendar-rate',
        internal_name='calendar_rate',
        validate=function(arg)
            local val = tonumber(arg)
            if not val or val <= 0 then qerror('calendar-rate must be larger than 0') end
            return val
        end,
        default=1.0,
    },
    {
        name='max-boost',
        internal_name='max_boost',
        validate=function(arg) return argparse.nonnegativeInt(arg, 'max-boost') end,
        default=50,
    },
}

local function get_default_state()
    local settings = {}
    for _, v in ipairs(SETTINGS) do
        settings[v.internal_name or v.name] = utils.getval(v.default)
    end
    return {
        enabled=false,
        settings=settings,
    }
end

state = state or get_default_state()

function isEnabled()
    return state.enabled
end

local function persist_state()
    dfhack.persistent.saveSiteData(GLOBAL_KEY, state)
end

local function event_loop()
    print('doin the stream')
end

local function do_enable()
    state.enabled = true
    repeatutil.scheduleEvery(GLOBAL_KEY, 1, 'ticks', event_loop)
end

local function do_disable()
    state.enabled = false
    repeatutil.cancel(GLOBAL_KEY)
end

dfhack.onStateChange[GLOBAL_KEY] = function(sc)
    if sc == SC_MAP_UNLOADED then
        do_disable()
        return
    end
    if sc ~= SC_MAP_LOADED or not dfhack.world.isFortressMode() then
        return
    end
    state = get_default_state()
    utils.assign(state, dfhack.persistent.getSiteData(GLOBAL_KEY, state))
    if state.enabled then
        do_enable()
    end
end

if dfhack_flags.module then
    return
end

if not dfhack.world.isFortressMode() or not dfhack.isMapLoaded() then
    qerror('needs a loaded fortress map to work')
end

local function print_status()
    print(GLOBAL_KEY .. ' is ' .. (state.enabled and 'enabled' or 'not enabled'))
    print()
    print('settings:')
    for _,v in ipairs(SETTINGS) do
        print(('  %15s: %s'):format(v.name, state.settings[v.internal_name or v.name]))
    end
end

local function do_set(setting_name, arg)
    if not setting_name or not arg then
        qerror('must specify setting and value')
    end
    local _, setting = utils.linear_index(SETTINGS, setting_name, 'name')
    if not setting then
        qerror('setting not found: ' .. setting_name)
    end
    state.settings[setting.internal_name or setting.name] = setting.validate(arg)
    print(('set %s to %s'):format(setting_name, state.settings[setting.internal_name or setting.name]))
end

local function do_reset()
    state = get_default_state()
end

local args = {...}
local command = table.remove(args, 1)

if dfhack_flags and dfhack_flags.enable then
    if dfhack_flags.enable_state then do_enable()
    else do_disable()
    end
elseif command == 'set' then
    do_set(args[1], args[2])
elseif command == 'reset' then
    do_reset()
elseif not command or command == 'status' then
    print_status()
    return
else
    print(dfhack.script_help())
    return
end

persist_state()



-- local TICKS_PER_DAY = 1200
-- local TICKS_PER_MONTH = 28 * TICKS_PER_DAY
-- local TICKS_PER_SEASON = 3 * TICKS_PER_MONTH
-- local TICKS_PER_YEAR = 4 * TICKS_PER_SEASON

-- local MINIMAL_FPS           = 10    -- This ensures you won't get crazy values on pausing/saving, or other artefacts on extremely low FPS.
-- local DEFAULT_MAX_FPS       = 100


-- --- DO NOT CHANGE BELOW UNLESS YOU KNOW WHAT YOU'RE DOING ---

-- local utils = require("utils")
-- args = utils.processArgs({...}, utils.invert({
--     'rate',
--     'fps',
--     'units',
--     'debug',
-- }))
-- local rate = tonumber(args.rate) or -1
-- local desired_fps = tonumber(args.fps)
-- local simulating_units = tonumber(args.units)
-- if args.units == '' then
--     simulating_units = 1
-- end
-- local debug_mode = not not args.debug

-- local current_fps = desired_fps
-- local prev_tick = 0
-- local ticks_left = 0
-- local simulating_desired_fps = false
-- local prev_frames = df.global.world.frame_counter
-- local last_frame = df.global.world.frame_counter
-- local prev_time = df.global.enabler.clock
-- local ui_main = df.global.plotinfo.main
-- local saved_game_frame = -1
-- local frames_until_speeding = 0
-- local speedy_frame_delta = desired_fps or DEFAULT_MAX_FPS

-- local SEASON_LEN = 3360
-- local YEAR_LEN = 403200

-- if not dfhack.world.isFortressMode() then
--     print("timestream: Will start when fortress mode is loaded.")
-- end

-- if rate == nil then
--     rate = 1
-- elseif rate < 0 then
--     rate = 0
-- end

-- simulating_desired_fps = true
-- if desired_fps == nil then
--     desired_fps = DEFAULT_MAX_FPS
--     if simulating_units ~= 1 and simulating_units ~= 2 then
--         simulating_desired_fps = false
--     end
-- elseif desired_fps < MINIMAL_FPS then
--     desired_fps = MINIMAL_FPS
-- end
-- current_fps = desired_fps

-- eventNow = false
-- seasonNow = false
-- timestream = 0
-- counter = 0
-- if df.global.cur_season_tick < SEASON_LEN then
--     month = 1
-- elseif df.global.cur_season_tick < SEASON_LEN * 2 then
--     month = 2
-- else
--     month = 3
-- end

-- dfhack.onStateChange.loadTimestream = function(code)
--     if code==SC_MAP_LOADED then
--         if rate ~= 1 then
--             last_frame = df.global.world.frame_counter
--             --if rate > 0 then            -- Won't behave well with unit simulation
--             if rate > 1 and not simulating_desired_fps then
--                 print('timestream: Time running at x'..rate..".")
--             else
--                 print('timestream: Time running dynamically to simulate '..desired_fps..' FPS.')
--                 if rate ~= 0 then
--                     print('timestream: Rate setting ignored.')
--                 end
--                 reset_frame_count()
--                 rate = 1
--                 if simulating_units == 1 or simulating_units == 2 then
--                     print("timestream: Unit simulation is on.")
--                     if simulating_units ~= 2 then
--                         df.global.debug_turbospeed = false
--                     end
--                 end
--             end
--             ticks_left = rate - 1

--             eventNow = false
--             seasonNow = false
--             timestream = 0
--             if df.global.cur_season_tick < SEASON_LEN then
--                 month = 1
--             elseif df.global.cur_season_tick < SEASON_LEN * 2 then
--                 month = 2
--             else
--                 month = 3
--             end
--             if loaded ~= true then
--                 dfhack.timeout(1,"frames",function() update() end)
--                 loaded = true
--             end
--         else
--             print('timestream: Time set to normal speed.')
--             loaded = false
--             df.global.debug_turbospeed = false
--         end
--         if debug_mode then
--             print("timestream: Debug mode is on.")
--         end
--     end
-- end

-- function update()
--     loaded = false
--     prev_tick = df.global.cur_year_tick
--     local current_frame = df.global.world.frame_counter
--     if (rate ~= 1 or simulating_desired_fps) and dfhack.world.isFortressMode() then
--         if last_frame + 1 == current_frame then
--             timestream = 0

--             --[[if rate < 1 then
--                 if df.global.cur_year_tick - math.floor(df.global.cur_year_tick/10)*10 == 5 then
--                     if counter > 1 then
--                         counter = counter - 1
--                         timestream = -1
--                     else
--                         counter = counter + math.floor(ticks_left)
--                     end
--                 end
--             else
--             --]]
--             --counter = counter + rate-1
--             counter = counter + math.floor(ticks_left)
--             while counter >= 10 do
--                 counter = counter - 10
--                 timestream = timestream + 1
--             end
--             --end
--             eventFound = false
--             for i=0,#df.global.timed_events-1,1 do
--                 event=df.global.timed_events[i]
--                 if event.season == df.global.cur_season and event.season_ticks <= df.global.cur_season_tick then
--                     if eventNow == false then
--                         --df.global.cur_season_tick=event.season_ticks
--                         event.season_ticks = df.global.cur_season_tick
--                         eventNow = true
--                     end
--                     eventFound = true
--                 end
--             end
--             if eventFound == false then eventNow = false end

--             if df.global.cur_season_tick >= SEASON_LEN - 1 and df.global.cur_season_tick < SEASON_LEN * 2 - 1 and month == 1 then
--                 seasonNow = true
--                 month = 2
--                 if df.global.cur_season_tick > SEASON_LEN - 1 then
--                     df.global.cur_season_tick = SEASON_LEN
--                 end
--             elseif df.global.cur_season_tick >= SEASON_LEN * 2 - 1 and df.global.cur_season_tick < SEASON_LEN * 3 - 1 and month == 2 then
--                 seasonNow = true
--                 month = 3
--                 if df.global.cur_season_tick > SEASON_LEN * 2 - 1 then
--                     df.global.cur_season_tick = SEASON_LEN * 2
--                 end
--             elseif df.global.cur_season_tick >= SEASON_LEN * 3 - 1 then
--                 seasonNow = true
--                 month = 1
--                 if df.global.cur_season_tick > SEASON_LEN * 3 then
--                     df.global.cur_season_tick = SEASON_LEN * 3 - 1
--                 end
--             else
--                 seasonNow = false
--             end

--             if df.global.cur_year > 0 then
--                 if timestream ~= 0 then
--                     if df.global.cur_season_tick < 0 then
--                         df.global.cur_season_tick = df.global.cur_season_tick + SEASON_LEN * 3
--                         df.global.cur_season = df.global.cur_season-1
--                         eventNow = true
--                     end
--                     if df.global.cur_season < 0 then
--                         df.global.cur_season = df.global.cur_season + 4
--                         df.global.cur_year_tick = df.global.cur_year_tick + YEAR_LEN
--                         df.global.cur_year = df.global.cur_year - 1
--                         eventNow = true
--                     end
--                     if (eventNow == false and seasonNow == false) or timestream < 0 then
--                         if timestream > 0 then
--                             df.global.cur_season_tick=df.global.cur_season_tick + timestream
--                             remainder = df.global.cur_year_tick - math.floor(df.global.cur_year_tick/10)*10
--                             df.global.cur_year_tick=(df.global.cur_season_tick*10)+((df.global.cur_season)*(SEASON_LEN * 3 * 10)) + remainder
--                         elseif timestream < 0 then
--                             df.global.cur_season_tick=df.global.cur_season_tick
--                             df.global.cur_year_tick=(df.global.cur_season_tick*10)+((df.global.cur_season)*(SEASON_LEN * 3 * 10))
--                         end
--                     end
--                 end
--             end

--             if simulating_desired_fps then
--                 if saved_game_frame ~= -1 and saved_game_frame + 2 == current_frame then
--                     if debug_mode then
--                         print("Game was saved two ticks ago (saved_game_frame(".. saved_game_frame .. ") + 2 == current_frame(" .. current_frame ..")")
--                     end
--                     reset_frame_count()
--                     saved_game = -1
--                 end
--                 local counted_frames = current_frame - prev_frames
--                 if counted_frames >= desired_fps then
--                     current_fps = 1000 * desired_fps / (df.global.enabler.clock - prev_time)
--                     if current_fps < desired_fps then
--                         rate = desired_fps/current_fps
--                     else
--                         rate = 1     -- We don't want to slow down the game
--                     end
--                     reset_frame_count()
--                     if current_fps < MINIMAL_FPS then
--                         current_fps = MINIMAL_FPS
--                     end
--                     local missing_frames = desired_fps - current_fps
--                     speedy_frame_delta = desired_fps/missing_frames
--                     if missing_frames == 0 then
--                         speedy_frame_delta = desired_fps
--                     end
--                     if debug_mode then
--                         print("prev_frames: " .. prev_frames .. ", current_fps: ".. current_fps.. ", rate: " .. rate)
--                     end
--                 end

--                 if simulating_units == 2 then
--                     if frames_until_speeding <= 0 then
--                         frames_until_speeding = frames_until_speeding + speedy_frame_delta
--                         if debug_mode then
--                             print("speedy_frame_delta: "..speedy_frame_delta..", speedy_frame: "..counted_frames.."/"..desired_fps)
--                         end
--                         df.global.debug_turbospeed = true
--                         last_frame_sped_up = current_frame
--                     else
--                         frames_until_speeding = frames_until_speeding - 1
--                         if df.global.debug_turbospeed then
--                             df.global.debug_turbospeed = false
--                         end
--                     end
--                 elseif simulating_units == 1 then
--                     local dec = math.floor(ticks_left) - 1  -- A value used to determine how much more to decrement from the timers per tick.
--                     for k1, unit in pairs(df.global.world.units.active) do
--                         if dfhack.units.isActive(unit) then
--                             if unit.sex == 0 then   -- Check to see if unit is female.
--                                 local ptimer = unit.pregnancy_timer
--                                 if ptimer > 0 then
--                                     ptimer = ptimer - dec
--                                     if ptimer < 1 then
--                                         ptimer = 1
--                                     end
--                                     unit.pregnancy_timer = ptimer
--                                 end
--                             end
--                             for k2, action in pairs(unit.actions) do
--                                 local action_type = action.type
--                                 if action_type == df.unit_action_type.Move then
--                                     local d = action.data.move.timer - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.move.timer = d

--                                 elseif action_type == df.unit_action_type.Attack then
--                                     local d = action.data.attack.timer1 - dec
--                                     if d <= 1 then
--                                         d = 1
--                                         action.data.attack.timer2 = 1   -- I don't know why, but if I don't add this line then there's a bug where people just dogpile each other and don't fight.
--                                     end
--                                     d = action.data.attack.timer2 - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.attack.timer2 = d
--                                 elseif action_type == df.unit_action_type.HoldTerrain then
--                                     local d = action.data.holdterrain.timer - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.holdterrain.timer = d
--                                 elseif action_type == df.unit_action_type.Climb then
--                                     local d = action.data.climb.timer - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.climb.timer = d
--                                 elseif action_type == df.unit_action_type.Job then
--                                     local d = action.data.job.timer - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.job.timer = d
--                                 elseif action_type == df.unit_action_type.Talk then
--                                     local d = action.data.talk.timer - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.talk.timer = d
--                                 elseif action_type == df.unit_action_type.Unsteady then
--                                     local d = action.data.unsteady.timer - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.unsteady.timer = d
--                                 elseif action_type == df.unit_action_type.StandUp then
--                                     local d = action.data.standup.timer - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.standup.timer = d
--                                 elseif action_type == df.unit_action_type.LieDown then
--                                     local d = action.data.liedown.timer - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.liedown.timer = d
--                                 elseif action_type == df.unit_action_type.JobRecover then
--                                     local d = action.data.jobrecover.timer - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.job2.timer = d
--                                 elseif action_type == df.unit_action_type.PushObject then
--                                     local d = action.data.pushobject.timer - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.pushobject.timer = d
--                                 elseif action_type == df.unit_action_type.SuckBlood then
--                                     local d = action.data.suckblood.timer - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.suckblood.timer = d
--                                 elseif action_type == df.unit_action_type.Mount then
--                                     local d = action.data.mount.timer - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.mount.timer = d
--                                 elseif action_type == df.unit_action_type.Dismount then
--                                     local d = action.data.dismount.timer - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.dismount.timer = d
--                                 elseif action_type == df.unit_action_type.HoldItem then
--                                     local d = action.data.holditem.timer - dec
--                                     if d < 1 then
--                                         d = 1
--                                     end
--                                     action.data.holditem.timer = d
--                                 end
--                             end
--                         end
--                     end
--                 end
--             end
--             ticks_left = ticks_left - math.floor(ticks_left) + rate
--             last_frame = current_frame
--         else
--             if debug_mode then
--                 print("last_frame("..last_frame..") + 1 != current_frame("..current_frame..")")
--             end
--             reset_frame_count()
--         end
--         if ui_main.autosave_request then
--             if debug_mode then
--                 print("Save state detected")
--             end
--             saved_game_frame = current_frame
--         end
--         if not loaded then
--             loaded = true
--             dfhack.timeout(1,"frames",function() update() end)
--         end
--     end
-- end

-- function reset_frame_count()
--     if debug_mode then
--         print("Resetting frame count")
--     end
--     prev_time = df.global.enabler.clock
--     prev_frames = df.global.world.frame_counter
-- end

-- --Initial call

-- if dfhack.isMapLoaded() then
--     dfhack.onStateChange.loadTimestream(SC_MAP_LOADED)
-- end
