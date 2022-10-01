local ffi = require("ffi")
local gamerules_ptr = client.find_signature("client.dll", "\x83\x3D\xCC\xCC\xCC\xCC\xCC\x74\x2A\xA1")
local gamerules = ffi.cast("intptr_t**", ffi.cast("intptr_t", gamerules_ptr) + 2)[0]
client.set_event_callback("setup_command", function(c)
    local is_valve_ds = ffi.cast('bool*', gamerules[0] + 124)
    if is_valve_ds ~= nil then
        is_valve_ds[0] = false
    end

end)