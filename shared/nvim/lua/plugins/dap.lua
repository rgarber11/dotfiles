return {
  {
    'jay-babu/mason-nvim-dap.nvim',
    {
      'mxsdev/nvim-dap-vscode-js',
      dependencies = { 'mfussenegger/nvim-dap' },
    },
    event = 'VeryLazy',
    dependencies = {
      'williamboman/mason.nvim',
      { 'mfussenegger/nvim-dap', config = function() end },
    },
    opts = {
      handlers = {},
    },
  },
  {
    'rcarriga/nvim-dap-ui',
    dependencies = {
      'mfussenegger/nvim-dap',
      'nvim-neotest/nvim-nio',
    },
    event = 'VeryLazy',
    config = function()
      local dap, dapui = require 'dap', require 'dapui'
      require('mason-nvim-dap').setup {
        ensure_installed = { 'python', 'js', 'codelldb' },
        automatic_installation = true,
      }
      local adapterDirectory = os.getenv 'HOME' .. '/Projects/vscode-js-debug/'
      require('dap-vscode-js').setup {
        debugger_path = adapterDirectory,
        adapters = { 'pwa-node', 'pwa-chrome', 'pwa-msedge', 'node-terminal', 'pwa-extensionHost' },
      }
      dap.configurations.javascript = {
        {
          type = 'pwa-node',
          request = 'launch',
          name = 'Launch file',
          program = '${file}',
          cwd = '${workspaceFolder}',
        },
        {
          type = 'pwa-node',
          request = 'attach',
          name = 'Attach',
          processId = require('dap.utils').pick_process,
          cwd = '${workspaceFolder}',
        },
      }
      dap.configurations.typescript = {
        {
          type = 'pwa-node',
          request = 'launch',
          name = 'Launch file',
          program = '${file}',
          cwd = '${workspaceFolder}',
        },
        {
          type = 'pwa-node',
          request = 'attach',
          name = 'Attach',
          processId = require('dap.utils').pick_process,
          cwd = '${workspaceFolder}',
        },
      }
      dapui.setup()
      dap.adapters['node'] = function(cb, config, parent)
        config.type = 'pwa-node'
        dap.adapters['pwa-node'](cb, config, parent)
      end
      dap.listeners.before['attach']['dapui_config'] = function()
        dapui.open()
      end
      dap.listeners.before['launch']['dapui_config'] = function()
        dapui.open()
      end
      dap.listeners.before['event_terminated']['dapui_config'] = function()
        dapui.close()
      end
      dap.listeners.before['event_exited']['dapui_config'] = function()
        dapui.close()
      end
    end,
  },
}
