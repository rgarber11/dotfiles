return {
    "stevearc/conform.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
        local conform = require "conform"

        conform.setup({
            clang_format = {
                prepend_args = { "--fallback-style=Google" },
            },
            formatters_by_ft = {
                javascript = { "prettier" },
                typescript = { "prettier" },
                javascriptreact = { "prettier" },
                typescriptreact = { "prettier" },
                svelte = { "prettier" },
                css = { "prettier" },
                html = { "prettier" },
                json = { "prettier" },
                yaml = { "prettier" },
                markdown = { "prettier" },
                graphql = { "prettier" },
                lua = { "stylua" },
                python = { "isort", "ruff", "black" },
                cpp = { "clang_format" },
                c = { "clang_format" },
                tex = { "latexindent" },
            },
            format_on_save = {
                lsp_fallback = true,
                async = false,
                timeout_ms = 5000,
            },
        })
    end,
}
