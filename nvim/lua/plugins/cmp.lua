return {
  {
    'saghen/blink.compat',
    -- use v2.* for blink.cmp v1.*
    version = '2.*',
    -- lazy.nvim will automatically load the plugin when it's required by blink.cmp
    lazy = true,
    -- make sure to set opts so that lazy.nvim calls blink.compat's setup
    opts = {},
  },
  {
    -- Autocompletion
    'saghen/blink.cmp',
    version = '1.x',

    dependencies = {
      {
        'L3MON4D3/LuaSnip',
        dependencies = { 'rafamadriz/friendly-snippets' },
        build = (function()
          if vim.fn.has 'win32' == 1 then
            return
          end
          return 'make install_jsregexp'
        end)(),
        version = 'v2.*',
        config = function()
          require('luasnip.loaders.from_vscode').lazy_load()
          require('luasnip').config.setup {}
        end,
      },
      {
        'folke/lazydev.nvim',
        ft = 'lua', -- only load on lua files
        dependencies = {
          { 'Bilal2453/luvit-meta', lazy = true }, -- optional `vim.uv` typings
        },
        opts = {
          library = {
            'lazy.nvim',
            -- See the configuration section for more details
            -- Load luvit types when the `vim.uv` word is found
            { path = 'luvit-meta/library', words = { 'vim%.uv' } },
          },
          integrations = {
            lspconfig = true,
            cmp = true,
          },
        },
      },
    },
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      keymap = { preset = 'default', ['<Enter>'] = { 'select_and_accept', 'fallback' } },
      signature = { enabled = true },
      snippets = { preset = 'luasnip' },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 300 },
      },
      sources = {
        default = { 'lazydev', 'lsp', 'path', 'snippets', 'buffer' },
        providers = {
          lazydev = {
            name = 'LazyDev',
            module = 'lazydev.integrations.blink',
            -- make lazydev completions top priority (see `:h blink.cmp`)
            score_offset = 100,
          },
          neorg = {
            name = 'neorg',
            module = 'blink.compat.source',
          },
        },
        per_filetype = {
          codecompanion = { 'codecompanion' },
        },
      },
      fuzzy = { implementation = 'prefer_rust_with_warning' },
    },
    opts_extend = { 'sources.default' },
  },
}
