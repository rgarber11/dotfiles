return {
    "rgarber11/neorg",
    dependencies = {
        { "nvim-lua/plenary.nvim" },
    },
    branch = "main",
    config = function()
        local load_settings = {
            ["core.defaults"] = {},
            ["core.concealer"] = {},
            ["core.dirman"] = {
                config = {
                    workspaces = {
                        notes = "~/notes",
                    },
                    default_workspace = "notes",
                },
            },
            ["core.completion"] = {
                config = {
                    engine = "nvim-cmp",
                },
            },
            ["core.keybinds"] = {
                config = {
                    default_keybinds = false,
                },
            },
            ["core.summary"] = {},
            ["core.ui"] = {},
            ["core.neorgcmd"] = {},
            ["core.export"] = {
                config = {
                    export_dir = "<export-dir>/<language>-export",
                },
            },
            ["core.export.markdown"] = {
                config = {
                    extensions = "all",
                },
            },
        }
        if os.getenv "KITTY_WINDOW_ID" ~= nil then
            load_settings["core.latex.renderer"] = {}
        end
        require("neorg").setup({
            load = load_settings,
        })
    end,
}
