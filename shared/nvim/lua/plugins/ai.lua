return {
  {
    'monkoose/neocodeium',
    event = 'VeryLazy',
    opts = {},
  },
  {
    'folke/sidekick.nvim',
    opts = {
      nes = {
        enabled = false,
      },
      cli = {
        tools = {
          gpt_code = {
            cmd = { 'gpt_code' },
          },
          monet = {
            cmd = { 'monet' },
          },
        },
      },
    },
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
