-- INIT FILE NEOVIM
vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.g.have_nerd_font = true
vim.o.hlsearch = true

-- Make line numbers default
vim.wo.number = true
vim.wo.relativenumber = true

-- Enable mouse mode
vim.o.mouse = "a"

-- Enable break indent
vim.o.breakindent = true
vim.o.linebreak = true

-- Save undo history
vim.o.undofile = true

-- Case-insensitive searching UNLESS \C or capital in search
vim.o.ignorecase = true
vim.o.smartcase = true

-- Keep signcolumn on by default
vim.wo.signcolumn = "yes"

-- Decrease update time
vim.o.updatetime = 250
vim.o.timeoutlen = 300

-- Set completeopt to have a better completion experience
vim.o.completeopt = "menuone"

-- NOTE: You should make sure your terminal supports this
vim.o.termguicolors = true

vim.opt.expandtab = true
vim.opt.smarttab = true
package.path = package.path .. ";" .. vim.fn.expand "$HOME" .. "/.luarocks/share/lua/5.1/?/init.lua;"
package.path = package.path .. ";" .. vim.fn.expand "$HOME" .. "/.luarocks/share/lua/5.1/?.lua;"
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", -- latest stable release
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)
require("lazy").setup({
    -- Git Helper
    "tpope/vim-fugitive",
    -- Github Helper
    "tpope/vim-rhubarb",
    -- Autoset Some indent/blankline values
    "tpope/vim-sleuth",
    {
        -- Add indentation guides even on blank lines
        "lukas-reineke/indent-blankline.nvim",
        -- Enable `lukas-reineke/indent-blankline.nvim`
        -- See `:help indent_blankline.txt`
        main = "ibl",
        opts = {},
    },

    {
        -- Change Highlighting
        "nvimdev/hlsearch.nvim",
        event = "BufRead",
        config = function()
            require("hlsearch").setup()
        end,
    },
    -- Useful plugin to show you pending keybinds.
    {
        "folke/which-key.nvim",
        event = "VimEnter",
        opts = {
            icons = {
                mappings = vim.g.have_nerd_font,
                keys = {},
            },
        },
    },

    -- Adds git related signs to the gutter, as well as utilities for managing changes
    "lewis6991/gitsigns.nvim",
    {
        "craftzdog/solarized-osaka.nvim",
        lazy = false,
        priority = 1000,
        config = function()
            require("solarized-osaka").setup({
                style = "moon",
                styles = {
                    comments = { italic = true },
                    keywords = { italic = true },
                    sidebars = "transparent",
                    floats = "transparent",
                },
            })
            vim.cmd.colorscheme "solarized-osaka"
        end,
    },

    --    For additional information see: https://github.com/folke/lazy.nvim#-structuring-your-plugins
    { import = "plugins" },
}, {})

-- Set highlight on search

-- [[ Basic Keymaps ]]
require "keymap"

-- [[ Highlight on yank ]]
-- See `:help vim.highlight.on_yank()`
local highlight_group = vim.api.nvim_create_augroup("YankHighlight", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
    callback = function()
        vim.highlight.on_yank()
    end,
    group = highlight_group,
    pattern = "*",
})
-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
