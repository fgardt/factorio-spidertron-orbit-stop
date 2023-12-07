local const = require("const")
require("util")

---@class SpidertronInfo Storing all necessary details about a locomotive
---@field entity LuaEntity The spidertron entity
---@field last_waypoint MapPosition? The last waypoint of the spidertron
---@field last_dist uint The last distance to the current waypoint
---@field last_check uint The last tick the spidertron was checked
---@field counter uint The numeber of times orbiting on the current waypoint was detected
---@field next_unit uint The unit_number of the next spidertron in the ringbuffer
---@field prev_unit uint The unit_number of the previous spidertron in the ringbuffer

---@class Global
---@field rate 0|10|30|60
---@field threshold uint
---@field spidertrons {[uint]: SpidertronInfo} Ringbuffer of locomotives
---@field count uint
---@field next_check uint? unit_number of the locomotive that gets checked next
---@field ticks_per_check uint
---@field entities_per_check uint

---@return 0|10|30|60
local function parse_rate_setting()
    local rate = settings.global[const.scan_rate_setting].value

    if rate == "Off" then
        return 0
    end

    if rate == "Slow" then
        return 60
    end

    if rate == "Normal" then
        return 30
    end

    if rate == "Fast" then
        return 10
    end

    return 0
end

local function init_globals()
    ---@type Global
    global = global or {}

    global.rate = global.rate or parse_rate_setting()
    global.spidertrons = global.spidertrons or {}
    global.count = global.count or 0 ---@type uint
    global.next_check = global.next_check or nil

    if global.rate == 0 then
        global.threshold = 10
    else
        global.threshold = math.ceil(60 / global.rate) --[[@as uint]]
    end

    global.ticks_per_check = global.ticks_per_check or 1 ---@type uint
    global.entities_per_check = global.entities_per_check or 1 ---@type uint
end

---@param pointA MapPosition
---@param pointB MapPosition
---@return uint
local function square_distance(pointA, pointB)
    if not pointA or not pointB then
        return 0
    end

    local x = pointA.x - pointB.x
    local y = pointA.y - pointB.y

    return x * x + y * y
end

---@param info SpidertronInfo
local function check_spidertron(info)
    local entity = info.entity
    if not entity or not entity.valid then
        -- remove locomotive from ring buffer
        global.count = global.count - 1

        if global.count == 0 then
            global.next_check = nil
        else
            global.spidertrons[info.prev_unit].next_unit = info.next_unit
            global.spidertrons[info.next_unit].prev_unit = info.prev_unit
        end

        info = nil ---@type SpidertronInfo

        return
    end

    -- standing still
    if entity.speed <= 0.025 or not entity.autopilot_destination then
        info.counter = 0
        goto no_orbit
    end

    -- waypoint changed
    if info.last_waypoint and info.last_waypoint.x ~= entity.autopilot_destination.x and info.last_waypoint.y ~= entity.autopilot_destination.y then
        info.counter = 0
        goto no_orbit
    end

    do
        local dist = square_distance(entity.position, entity.autopilot_destination)
        if math.abs(info.last_dist - dist) < (entity.speed * (game.tick - info.last_check) / 4) then
            info.counter = info.counter + 1
        elseif info.counter > 0 then
            info.counter = info.counter - 1
        end
    end

    if info.counter >= global.threshold then
        local destinations = table.deepcopy(entity.autopilot_destinations or {})
        entity.autopilot_destination = nil

        destinations[1] = nil
        for _, dest in pairs(destinations) do
            entity.add_autopilot_destination(dest)
        end

        info.counter = 0
    end

    ::no_orbit::

    info.last_check = game.tick
    info.last_waypoint = entity.autopilot_destination
    info.last_dist = square_distance(entity.position, entity.autopilot_destination)
end

---@param _ NthTickEventData
local function run_checks(_)
    for _ = 1, global.entities_per_check do
        if not global.next_check then
            return
        end

        local info = global.spidertrons[ global.next_check --[[@as uint]] ]
        global.next_check = info.next_unit

        check_spidertron(info)
    end
end

local function update_timings()
    local count = global.count
    local rate = global.rate

    -- check if we can disable locomotive scanning
    if count == 0 or rate == 0 then
        script.on_nth_tick(global.ticks_per_check, nil)
        return
    end

    local ticks_per_check = math.ceil(rate / count) --[[@as uint]]
    local entities_per_check = math.ceil(count / rate) --[[@as uint]]

    -- check if this clashes with the recalculation interval
    if ticks_per_check == 1800 then
        ticks_per_check = 1799
    end

    script.on_nth_tick(global.ticks_per_check, nil)
    script.on_nth_tick(ticks_per_check, run_checks)

    global.ticks_per_check = ticks_per_check
    global.entities_per_check = entities_per_check
    global.recalculate_timings = false
end

script.on_nth_tick(1800, update_timings)

---@param entity LuaEntity?
local function register_spidertron(entity)
    if not entity or not entity.valid or entity.type ~= "spider-vehicle" or not entity.unit_number then
        return
    end

    ---@type uint, uint
    local next_unit, prev_unit
    if not global.next_check then
        global.next_check = entity.unit_number
        next_unit = entity.unit_number ---@type uint
        prev_unit = entity.unit_number ---@type uint
    else
        prev_unit = global.next_check ---@type uint
        next_unit = global.spidertrons[prev_unit].next_unit

        global.spidertrons[prev_unit].next_unit = entity.unit_number
        global.spidertrons[next_unit].prev_unit = entity.unit_number
    end

    ---@type SpidertronInfo
    local info = {
        entity = entity,
        counter = 0,
        last_dist = 0,
        last_waypoint = nil,
        last_check = game.tick,
        next_unit = next_unit,
        prev_unit = prev_unit
    }

    global.count = global.count + 1
    global.spidertrons[entity.unit_number] = info

    update_timings()
end

---@param clear boolean?
local function init(clear)
    if clear then
        global = {}
    end

    init_globals()
    global.rate = parse_rate_setting()
    update_timings()

    if clear or global.count == 0 then
        for _, surface in pairs(game.surfaces) do
            for _, entity in pairs(surface.find_entities_filtered({ type = "spider-vehicle" })) do
                register_spidertron(entity)
            end
        end
    end
end

script.on_init(function() init(true) end)
script.on_configuration_changed(function() init(false) end)

script.on_load(function()
    if not global then return end
    if global.count == 0 or global.rate == 0 then return end
    if not global.ticks_per_check then return end

    script.on_nth_tick(global.ticks_per_check, run_checks)
end)

---@param event
---| EventData.on_robot_built_entity
---| EventData.script_raised_revive
---| EventData.script_raised_built
---| EventData.on_entity_cloned
---| EventData.on_built_entity
local function placed_spidertron(event)
    local entity = event.created_entity or event.entity or event.destination

    register_spidertron(entity)
end

local ev = defines.events
script.on_event(ev.on_runtime_mod_setting_changed, init)

script.on_event(ev.on_robot_built_entity, placed_spidertron, { { filter = "type", type = "spider-vehicle" } })
script.on_event(ev.script_raised_revive, placed_spidertron, { { filter = "type", type = "spider-vehicle" } })
script.on_event(ev.script_raised_built, placed_spidertron, { { filter = "type", type = "spider-vehicle" } })
script.on_event(ev.on_entity_cloned, placed_spidertron, { { filter = "type", type = "spider-vehicle" } })
script.on_event(ev.on_built_entity, placed_spidertron, { { filter = "type", type = "spider-vehicle" } })
