return {
    {
        -- Highlight, edit, and navigate code
        "nvim-treesitter/nvim-treesitter",
        dependencies = {
            "nvim-treesitter/nvim-treesitter-textobjects",
        },
        branch = "master",
        build = ":TSUpdate",
        config = function()
            require("nvim-treesitter.configs").setup({
                -- Add languages to be installed here that you want installed for treesitter
                ensure_installed = {
                    "c",
                    "cmake",
                    "cpp",
                    "csv",
                    "go",
                    "html",
                    "ini",
                    "lua",
                    "python",
                    "rust",
                    "tsx",
                    "latex",
                    "markdown",
                    "toml",
                    "javascript",
                    "typescript",
                    "vimdoc",
                    "vim",
                    "php",
                    "bash",
                    "java",
                    "r",
                    "xml",
                    "yaml",
                },

                -- Autoinstall languages that are not installed. Defaults to false (but you can change for yourself!)
                auto_install = true,

                highlight = { enable = true },
                indent = { enable = true },
                incremental_selection = {
                    enable = true,
                    keymaps = {
                        init_selection = "<c-space>",
                        node_incremental = "<c-space>",
                        scope_incremental = "<c-s>",
                        node_decremental = "<M-space>",
                    },
                },
                textobjects = {
                    select = {
                        enable = true,
                        lookahead = true, -- Automatically jump forward to textobj, similar to targets.vim
                        keymaps = {
                            -- You can use the capture groups defined in textobjects.scm
                            ["aa"] = "@parameter.outer",
                            ["ia"] = "@parameter.inner",
                            ["af"] = "@function.outer",
                            ["if"] = "@function.inner",
                            ["ac"] = "@class.outer",
                            ["ic"] = "@class.inner",
                        },
                    },
                    move = {
                        enable = true,
                        set_jumps = true, -- whether to set jumps in the jumplist
                        goto_next_start = {
                            ["]m"] = "@function.outer",
                            ["]]"] = "@class.outer",
                        },
                        goto_next_end = {
                            ["]M"] = "@function.outer",
                            ["]["] = "@class.outer",
                        },
                        goto_previous_start = {
                            ["[m"] = "@function.outer",
                            ["[["] = "@class.outer",
                        },
                        goto_previous_end = {
                            ["[M"] = "@function.outer",
                            ["[]"] = "@class.outer",
                        },
                    },
                    swap = {
                        enable = true,
                        swap_next = {
                            ["<leader>a"] = "@parameter.inner",
                        },
                        swap_previous = {
                            ["<leader>A"] = "@parameter.inner",
                        },
                    },
                },
            })
            local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
            parser_config.prolog = {
                install_info = {
                    url = "/home/rgarber11/tree-sitter/tree-sitter-prolog",
                    files = { "src/parser.c" },
                    branch = "main",
                },
                filetype = "pl",
            }
        end,
    },
}
