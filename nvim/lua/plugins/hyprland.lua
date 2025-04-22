return {
    "rgarber11/hyprland-keymap-picker.nvim",
    dependencies = "nvim-lua/plenary.nvim",
    config = function()
        if os.getenv "HYPRLAND_INSTANCE_SIGNATURE" then
            require("hyprland-keymap-picker").setup({
                on_change = function()
                    local Job = require "plenary.job"
                    Job:new({
                        command = "pkill",
                        args = {
                            "-f",
                            "-34",
                            "nwg-panel",
                        },
                    }):start()
                end,
            })
        end
    end,
}
