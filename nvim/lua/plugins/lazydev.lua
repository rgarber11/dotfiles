return {
    {
        "folke/lazydev.nvim",
        ft = "lua", -- only load on lua files
        dependencies = {
            "hrsh7th/nvim-cmp",
            { "Bilal2453/luvit-meta", lazy = true }, -- optional `vim.uv` typings
        },
        opts = {
            library = {
                "lazy.nvim",
                "~/.config/nvim",
                -- See the configuration section for more details
                -- Load luvit types when the `vim.uv` word is found
                { path = "luvit-meta/library", words = { "vim%.uv" } },
            },
        },
    },
}
