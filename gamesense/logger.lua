local ffi = require("ffi")
ffi.cdef [[
typedef void***(__thiscall* FindHudElement_t)(void*, const char*);
typedef void(__cdecl* ChatPrintf_t)(void*, int, int, const char*, ...);
]]

local signature_gHud = "\xB9\xCC\xCC\xCC\xCC\x88\x46\x09"
local signature_FindElement = "\x55\x8B\xEC\x53\x8B\x5D\x08\x56\x57\x8B\xF9\x33\xF6\x39\x77\x28"

local match = client.find_signature("client_panorama.dll", signature_gHud) or error("sig1 not found")
local hud = ffi.cast("void**", ffi.cast("char*", match) + 1)[0] or error("hud is nil")

match = client.find_signature("client_panorama.dll", signature_FindElement) or error("FindHudElement not found")
local find_hud_element = ffi.cast("FindHudElement_t", match)
local hudchat = find_hud_element(hud, "CHudChat") or error("CHudChat not found")

local chudchat_vtbl = hudchat[0] or error("CHudChat instance vtable is nil")
local print_to_chat = ffi.cast("ChatPrintf_t", chudchat_vtbl[27])

local bChat = ui.new_checkbox("LUA", "B", "Log into chat")
local bConsole = ui.new_checkbox("LUA", "B", "Log into console")

local function print_chat(text)
    print_to_chat(hudchat, 0, 0, text)
end

local weapon_data = require("gamesense/csgo_weapons")

local file = "shots.compressed"
local hitgroups = {
    "generic",
    "head",
    "chest",
    "stomach",
    "left arm",
    "right arm",
    "left leg",
    "right leg",
    "neck",
    "?",
    "gear"
}

local dbname = "bob_shotlogging"

local cache = {}
local shot_buffer = {}

local function read()
    return database.read(dbname) or {}
end

local function write(data)
    database.write(dbname, data)
end

local function key_num(tbl)
    local N = 0
    for _ in pairs(tbl) do
        N = N + 1
    end
    return N
end

local function save()
    local data = shot_buffer
    if #shot_buffer == 0 then
        return
    end
    local buffer = read() or {}

    if not (key_num(data) == 0) then
        local buffer_size = key_num(buffer)
        for i = 1, #data do
            buffer[tostring(buffer_size + i)] = data[i]
        end
    end
    write(buffer)
    shot_buffer = {}
end

local function notify(buffer)
    local flags = {
        buffer.teleported and "T" or "",
        buffer.interpolated and "I" or "",
        buffer.extrapolated and "E" or "",
        buffer.boosted and "B" or "",
        buffer.high_priority and "H" or ""
    }
    flags = table.concat(flags)
    local msg =
        string.format(
        "[logger] missed %s due to %s (hc=%d;hb=%s;fl=%s) [th=%s;td=%s]",
        buffer.name,
        buffer.reason,
        buffer.hitchance,
        buffer.hitbox,
        flags,
        buffer.target_hitbox,
        buffer.target_dmg
    )
    if buffer.type == "hit" then
        msg =
            string.format(
            "[logger] hit %s (%d) in %s (hc=%d;fl=%s) [th=%s;td=%s]",
            buffer.name,
            buffer.damage,
            buffer.hitbox,
            buffer.hitchance,
            flags,
            buffer.target_hitbox,
            buffer.target_dmg
        )
    end
    if ui.get(bConsole) then
        client.log(msg)
    end
    if ui.get(bChat) then
        print_chat(msg)
    end
end

local function process(data)
    local hitbox = data.hitgroup and hitgroups[data.hitgroup + 1] or "generic"
    local buffer = {}
    buffer.type = data.reason and "miss" or "hit"

    if data.reason then
        buffer.name = entity.get_player_name(data.target)
        buffer.reason = data.reason == "?" and "resolver" or data.reason
        buffer.hitbox = hitbox
        buffer.hitchance = data.hit_chance
    else
        buffer.name = entity.get_player_name(data.target)
        buffer.damage = data.damage
        buffer.hitbox = hitbox
        buffer.hitchance = data.hit_chance
    end

    buffer.target_dmg = cache.damage
    buffer.target_hitbox = cache.hitgroup and hitgroups[cache.hitgroup + 1] or "generic"
    buffer.boosted = cache.boosted
    buffer.high_priority = cache.high_priority
    buffer.interpolated = cache.interpolated
    buffer.extrapolated = cache.extrapolated
    buffer.teleported = cache.teleported
    buffer.weapon = cache.weapon

    cache = {}
    table.insert(shot_buffer, buffer)

    notify(buffer)
end

local function process_query(tbl, key, query)
    local count = 0
    local table_size = key_num(tbl)
    if table_size == 0 then
        return 0
    end

    for i = 1, table_size do
        for k, v in pairs(tbl[tostring(i)]) do
            if k == key then
                if v == query then
                    count = count + 1
                end
            end
        end
    end

    return count
end

local function display()
    save()
    local buffer = read() or {}

    local total_shots = key_num(buffer)
    local total_misses = process_query(buffer, "type", "miss")
    local total_hits = process_query(buffer, "type", "hit")
    local miss_prediction = process_query(buffer, "reason", "prediction error")
    local miss_unknown = process_query(buffer, "reason", "resolver")
    local miss_spread = process_query(buffer, "reason", "spread")
    local miss_death = process_query(buffer, "reason", "death")
    local miss_unreg = process_query(buffer, "reason", "unregistered shot")

    client.color_log(222, 222, 222, "-| SHOT LOGS |-\n", buffer)
    client.color_log(20, 222, 222, "Total shots: ", key_num(buffer))
    client.color_log(
        10,
        240,
        10,
        string.format("Total hits: %d (%.1f%s)", total_hits, (total_shots - total_misses) / total_shots * 100, "%")
    )
    client.color_log(
        240,
        10,
        10,
        string.format("Total misses: %d (%.1f%s)", total_misses, (total_shots - total_hits) / total_shots * 100, "%")
    )
    client.color_log(
        140,
        140,
        140,
        string.format(
            "Spread: %d; Prediction: %d; Death: %d; Resolver: %d; Unregistered shot: %d",
            miss_spread,
            miss_prediction,
            miss_death,
            miss_unknown,
            miss_unreg
        )
    )
end

local function main()
    client.set_event_callback(
        "aim_fire",
        function(data)
            cache = data
            local wpn = entity.get_player_weapon(entity.get_local_player())
            local wpn_id = entity.get_prop(wpn, "m_iItemDefinitionIndex")
            local m_item = wpn_id and bit.band(wpn_id, 0xFFFF) or 0
            local wpn_name = weapon_data[m_item].console_name or ""
            if wpn_name == "" then
                cache.weapon = "invalid"
            else
                cache.weapon = wpn_name
            end
        end
    )
    client.set_event_callback("aim_hit", process)
    client.set_event_callback("aim_miss", process)
    client.set_event_callback("shutdown", save)
end

main()
