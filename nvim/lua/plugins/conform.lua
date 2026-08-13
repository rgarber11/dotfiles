return {
  'stevearc/conform.nvim',
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    local conform = require 'conform'

    conform.setup {
      formatters = {
        clang_format = {
          prepend_args = { '--fallback-style=Google' },
        },
        ktfmt = {
          prepend_args = { '--kotlinlang-style' },
        },
      },
      formatters_by_ft = {
        javascript = { 'oxfmt' },
        typescript = { 'oxfmt' },
        javascriptreact = { 'oxfmt' },
        typescriptreact = { 'oxfmt' },
        svelte = { 'oxfmt' },
        css = { 'oxfmt' },
        html = { 'oxfmt' },
        json = { 'oxfmt' },
        yaml = { 'oxfmt' },
        markdown = { 'oxfmt' },
        graphql = { 'oxfmt' },
        lua = { 'stylua' },
        python = { 'isort', 'ruff' },
        cpp = { 'clang_format' },
        c = { 'clang_format' },
        tex = { 'latexindent' },
        sh = { 'shfmt' },
        bash = { 'shfmt' },
        kotlin = { 'ktfmt' },
      },
      format_on_save = {
        lsp_fallback = true,
        async = false,
        timeout_ms = 5000,
      },
    }
  end,
}
