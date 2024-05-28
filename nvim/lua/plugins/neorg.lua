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
        require("neorg").setup({
            load = {
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
                ["core.integrations.image"] = {},
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
            },
        })
        vim.wo.foldlevel = 99
        vim.wo.conceallevel = 2
    end,
}
