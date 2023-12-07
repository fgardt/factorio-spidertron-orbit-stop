local const = require("const")

data:extend({
    {
        type = "string-setting",
        name = const.scan_rate_setting,
        setting_type = "runtime-global",
        default_value = "Normal",
        allowed_values = { "Off", "Slow", "Normal", "Fast" },
        order = "a"
    }
})
