return {
    "mfussenegger/nvim-lint",
    event = {
        "BufReadPre",
        "BufNewFile",
    },
    config = function()
        local lint = require "lint"
        local cpplint = lint.linters.cpplint
        cpplint.args = { "--filter=-build/c++11,-build/c++14,-build/c++tr1" }
        lint.linters_by_ft = {
            python = { "mypy", "ruff" },
            cpp = { "cpplint" },
        }

        local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

        vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
            group = lint_augroup,
            callback = function()
                lint.try_lint()
            end,
        })
    end,
}
