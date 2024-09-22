return {
    "rgarber11/neorg",
    dependencies = {
        { "nvim-lua/plenary.nvim" },
        {
            "vhyrro/luarocks.nvim",
            priority = 1000,
            config = true,
        },
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
                    engine = "nvim-cmp"
                }
            },
            ["core.latex.renderer"] = {},
            ["core.summary"] = {},
            -- ["core.ui.calendar"] = {},
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
        if vim.fn.has("win32") ~= 1 then
            load_settings["core.integrations.image"] = {}
        end
        require("neorg").setup({
            load = load_settings
        })
    end,
    ft = "norg",
    cmd = "Neorg",
}
