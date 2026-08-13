return {
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    opts = {
      panel = {
        enabled = false,
      },
      suggestion = {
        auto_trigger = true,
        keymap = {
          accept = '<M-l>',
          accept_word = '<M-;>',
          accept_line = false,
          next = '<M-]>',
          prev = '<M-[>',
          dismiss = '<C-]>',
        },
      },
    },
  },
  {
    'folke/sidekick.nvim',
    config = function()
      require('sidekick').setup {
        nes = {
          ---@type boolean|fun(buf:integer):boolean?
          enabled = function(buf)
            return vim.g.sidekick_nes ~= false and vim.b.sidekick_nes ~= false
          end,
          debounce = 100,
          trigger = {
            -- events that trigger sidekick next edit suggestions
            events = { 'ModeChanged i:n', 'TextChanged', 'User SidekickNesDone' },
          },
          clear = {
            -- events that clear the current next edit suggestion
            events = { 'TextChangedI', 'InsertEnter' },
            esc = true, -- clear next edit suggestions when pressing <Esc>
          },
          ---@class sidekick.diff.Opts
          ---@field inline? "words"|"chars"|false Enable inline diffs
          diff = {
            inline = 'words',
          },
        },
      }
    end,
  },
  {
    'olimorris/codecompanion.nvim',
    tag = 'v19.7.0',
    opts = {
      adapters = {
        acp = {
          claude_code = function()
            return require('codecompanion.adapters').extend('claude_code', {
              env = {
                CLAUDE_CODE_OAUTH_TOKEN = os.getenv 'CLAUDE_CODE_OAUTH_TOKEN',
              },
            })
          end,
        },
      },
      display = {
        diff = {
          provider = 'mini_diff',
        },
      },
      strategies = {
        chat = {
          adapter = 'claude_code',
        },
        inline = {
          keymaps = {
            accept_change = {
              modes = { n = '<leader>cc' },
              description = 'Accept Code Change',
            },
            reject_change = {
              modes = { n = '<leader>cr' },
              opts = { nowait = true },
              description = 'Reject the Code Change',
            },
          },
        },
      },
      dependencies = {
        'nvim-lua/plenary.nvim',
      },
    },
  },
}
