return {
    "echasnovski/mini.nvim",
    version = false,
    config = function()
        require("mini.ai").setup({ n_lines = 500 })
        require("mini.surround").setup()
        require("mini.comment").setup()
        require("mini.pairs").setup()
        require("mini.git").setup()
        require("mini.diff").setup()
        require("mini.notify").setup()
        require("mini.starter").setup()
        local statusline = require "mini.statusline"
        -- set use_icons to true if you have a Nerd Font
        statusline.setup({ use_icons = vim.g.have_nerd_font })
    end,
}
