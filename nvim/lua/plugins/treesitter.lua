return {
  {
    -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    event = 'BufRead',
    build = ':TSUpdate',
    config = function()
      local treesitter = require 'nvim-treesitter'
      -- Add languages to be installed here that you want installed for treesitter
      local ensure_installed = {
        'c',
        'cmake',
        'cpp',
        'csv',
        'go',
        'html',
        'ini',
        'lua',
        'python',
        'rust',
        'tsx',
        'latex',
        'markdown',
        'toml',
        'javascript',
        'typescript',
        'vimdoc',
        'vim',
        'php',
        'bash',
        'java',
        'r',
        'xml',
        'yaml',
      }

      if ensure_installed and #ensure_installed > 0 then
        treesitter.install(ensure_installed)
      end
      local langs = treesitter.get_installed 'parsers'
      for _, lang in ipairs(langs) do
        vim.api.nvim_create_autocmd('FileType', {
          pattern = vim.treesitter.language.get_filetypes(lang),
          callback = function(event)
            vim.treesitter.start(event.buf, lang)
            vim.bo[event.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end,
        })
      end
      vim.api.nvim_create_autocmd('BufRead', {
        callback = function(event)
          local filetype = vim.api.nvim_get_option_value('filetype', { buf = event.buf })
          if filetype == '' then
            return
          end
          local lang = vim.treesitter.language.get_lang(filetype)
          if not lang or not vim.tbl_contains(require('nvim-treesitter').get_available(), lang) then
            return
          end
          require('nvim-treesitter').install(lang):wait(30000)
          vim.treesitter.start(event.buf, lang)
        end,
      })
    end,
  },
  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    branch = 'main',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    opts = {
      select = {
        enable = true,
        lookahead = true, -- Automatically jump forward to textobj, similar to targets.vim
      },
      move = {
        set_jumps = true, -- whether to set jumps in the jumplist
      },
    },
  },
  {
    'folke/flash.nvim',
    event = 'VeryLazy',
    ---@type Flash.Config
    opts = {},
  },
}
