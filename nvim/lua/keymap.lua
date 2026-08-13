-- Keymaps to fix edge cases
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
-- Window Moving Commands
vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })
-- Telescope Search Commands
vim.keymap.set('n', '<leader>?', require('telescope.builtin').oldfiles, { desc = '[?] Find recently opened files' })
vim.keymap.set('n', '<leader><space>', require('telescope.builtin').buffers, { desc = '[ ] Find existing buffers' })
vim.keymap.set('n', '<leader>/', function()
  -- You can pass additional configuration to telescope to change theme, layout, etc.
  require('telescope.builtin').current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
    winblend = 10,
    previewer = false,
  })
end, { desc = '[/] Fuzzily search in current buffer' })

vim.keymap.set('n', '<leader>gf', require('telescope.builtin').git_files, { desc = 'Search [G]it [F]iles' })
vim.keymap.set('n', '<leader>sf', require('telescope.builtin').find_files, { desc = '[S]earch [F]iles' })
vim.keymap.set('n', '<leader>sh', require('telescope.builtin').help_tags, { desc = '[S]earch [H]elp' })
vim.keymap.set('n', '<leader>sw', require('telescope.builtin').grep_string, { desc = '[S]earch current [W]ord' })
vim.keymap.set('n', '<leader>sg', require('telescope.builtin').live_grep, { desc = '[S]earch by [G]rep' })
vim.keymap.set('n', '<leader>sd', require('telescope.builtin').diagnostics, { desc = '[S]earch [D]iagnostics' })
vim.keymap.set('n', '<leader>sR', require('telescope.builtin').resume, { desc = '[S]earch [R]resume' })
vim.keymap.set('n', '<leader>sr', require('telescope.builtin').lsp_references, { desc = '[S]earch [R]eferences' })

-- Telescope Undo
vim.keymap.set('n', '<leader>u', function()
  vim.cmd 'Telescope undo'
end, { noremap = true, desc = 'Undo History' })

-- DAP keybinds
vim.keymap.set('n', '<leader>db', require('dap').toggle_breakpoint, { desc = 'Add breakpoint at line' })
vim.keymap.set('n', '<leader>dr', require('dap').continue, { desc = 'Run/continue debugger' })
vim.keymap.set('n', '<leader>dc', function()
  require('dap').terminate()
  require('dapui').close()
end, { desc = 'Terminate debugger' })
vim.keymap.set('n', '<leader>di', require('dap').step_into, { desc = 'Step into function' })
vim.keymap.set('n', '<leader>do', require('dap').step_into, { desc = 'Step over function' })

-- Diagnostic keymaps
vim.keymap.set('n', '[d', function()
  vim.diagnostic.jump { count = -1, float = true }
end, { desc = 'Go to previous diagnostic message' })
vim.keymap.set('n', ']d', function()
  vim.diagnostic.jump { count = 1, float = true }
end, { desc = 'Go to next diagnostic message' })
vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Open floating diagnostic message' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostics list' })

-- Pretty Math
vim.keymap.set('n', '<leader>po', require('nabla').popup, { noremap = true, desc = 'Open Nabla Popup' })
vim.keymap.set('n', '<leader>nt', function()
  if vim.bo.filetype == 'markdown' then
    if require('nabla').is_virt_enabled(0) then
      require('markview').configuration.latex.enable = false
    else
      require('markview').configuration.latex.enable = true
    end
  end
  require('nabla').toggle_virt()
end, { noremap = true, desc = 'Toggle Nabla Virt' })
if os.getenv 'KITTY_WINDOW_ID' then
  vim.keymap.set('n', '<leader>mt', function()
    vim.cmd 'Neorg render-latex toggle'
  end, { desc = 'Toggle Neorg Latex Rendering' })
end

-- Overseer Keymaps
vim.keymap.set('n', '<leader>or', function()
  vim.cmd 'OverseerRun'
end, { noremap = true, desc = 'Open Task Runner Menu' })
vim.keymap.set('n', '<leader>ot', function()
  vim.cmd 'OverseerToggle'
end, { noremap = true, desc = 'Toggle Task Results' })

-- Oil Keymaps
vim.keymap.set('n', '<leader>nr', function()
  require('oil').open()
end, { noremap = true, desc = 'Open Oil' })
vim.keymap.set('n', '<leader>ns', function()
  vim.cmd 'split'
  require('oil').open()
end, { noremap = true, desc = 'Split Side Oil' })
vim.keymap.set('n', '<leader>nv', function()
  vim.cmd 'vsplit'
  require('oil').open()
end, { noremap = true, desc = 'Split Vertical Oil' })
vim.keymap.set('n', '<leader>no', function()
  require('oil').open_float()
end, { noremap = true, desc = 'Open Oil in Hover Mode' })

-- Formatting Keybind
vim.keymap.set({ 'n', 'v' }, '<leader>f', function()
  require('conform').format {
    lsp_fallback = true,
    async = false,
    timeout_ms = 500,
  }
end, { desc = 'Format file or range (in visual mode)' })

-- LSP Specific Keymaps
local langs = { 'English (US)', 'Russian', 'Spanish' }
local lang_codes = { 'en-US', 'ru-RU', 'es' }
local set_ltex_lang = function(lsp_id, lang_id)
  local client = vim.lsp.get_client_by_id(lsp_id)
  if client == nil then
    return
  end
  if lang_id == 2 then
    pcall(require('hyprland-keymap-picker').set_keymap, 2)
  end
  local lang = lang_codes[lang_id]
  vim.notify('LTeX language set to ' .. langs[lang_id], vim.log.levels.INFO)
  client.config.settings.ltex.language = lang
  vim.lsp.buf_notify(0, 'workspace/didChangeConfiguration', { settings = client.config.settings })
  pcall(require('ltex_extra').reload, { lang })
end
local create_language_select_menu = function(lsp_id)
  vim.ui.select(langs, {
    format_item = function(e)
      return tostring(e)
    end,
    prompt = 'Select Text Language...',
    kind = 'make_indexed',
  }, function(_, choice_id)
    if choice_id == nil then
      return
    end
    set_ltex_lang(lsp_id, choice_id)
  end)
end
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(args)
    local nmap = function(keys, func, desc)
      if desc then
        desc = 'LSP: ' .. desc
      end

      vim.keymap.set('n', keys, func, { buffer = args.buf, desc = desc })
    end

    nmap('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
    nmap('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')

    nmap('gd', vim.lsp.buf.definition, '[G]oto [D]efinition')
    nmap('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
    nmap('gI', vim.lsp.buf.implementation, '[G]oto [I]mplementation')
    nmap('<leader>D', vim.lsp.buf.type_definition, 'Type [D]efinition')
    nmap('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
    nmap('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

    -- See `:help K` for why this keymap
    nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
    nmap('<C-k>', vim.lsp.buf.signature_help, 'Signature Documentation')

    -- Lesser used LSP functionality'
    nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
    nmap('<leader>wa', vim.lsp.buf.add_workspace_folder, '[W]orkspace [A]dd Folder')
    nmap('<leader>wr', vim.lsp.buf.remove_workspace_folder, '[W]orkspace [R]emove Folder')
    nmap('<leader>wl', function()
      print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, '[W]orkspace [L]ist Folders')
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client == nil then
      return
    end
    if client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint, args.buf) then
      nmap('<leader>th', function()
        vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = args.buf })
      end, '[T]oggle Inlay [H]ints')
    end
    if client.name == 'ltex' then
      vim.keymap.set('n', '<leader>lt', function()
        create_language_select_menu(client.id)
      end, { noremap = true, desc = 'Toggle Neovim Language' })
    end
  end,
})

-- Gitsigns Uses OnAttach, so its config is here
require('gitsigns').setup {
  -- See `:help gitsigns.txt`
  signs = {
    add = { text = '+' },
    change = { text = '~' },
    delete = { text = '_' },
    topdelete = { text = '‾' },
    changedelete = { text = '~' },
  },
  on_attach = function(bufnr)
    vim.keymap.set('n', '<leader>hp', require('gitsigns').preview_hunk, { buffer = bufnr, desc = 'Preview git hunk' })

    -- don't override the built-in and fugitive keymaps
    local gs = package.loaded.gitsigns
    vim.keymap.set({ 'n', 'v' }, ']c', function()
      if vim.wo.diff then
        return ']c'
      end
      vim.schedule(function()
        gs.next_hunk()
      end)
      return '<Ignore>'
    end, { expr = true, buffer = bufnr, desc = 'Jump to next hunk' })
    vim.keymap.set({ 'n', 'v' }, '[c', function()
      if vim.wo.diff then
        return '[c'
      end
      vim.schedule(function()
        gs.prev_hunk()
      end)
      return '<Ignore>'
    end, { expr = true, buffer = bufnr, desc = 'Jump to previous hunk' })
  end,
}
-- Neorg Keybindings
vim.keymap.set('n', '<leader>nn', '<Plug>(neorg.dirman.new-note)', { noremap = true, desc = '[neorg] Create New Note', buffer = true })
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'norg',
  callback = function()
    vim.keymap.set('i', '<C-t>', '<Plug>(neorg.promo.promote)', { desc = '[neorg] Promote Object (Recursively)', buffer = true, noremap = true })
    vim.keymap.set('i', '<C-d>', '<Plug>(neorg.promo.demote)', { desc = '[neorg] Demote Object (Recursively)', buffer = true, noremap = true })
    vim.keymap.set('i', '<M-CR>', '<Plug>(neorg.itero.next-iteration)', { desc = '[neorg] Continue Object', buffer = true, noremap = true })
    vim.keymap.set('i', '<M-d>', '<Plug>(neorg.tempus.insert-date.insert-mode)', { desc = '[neorg] Insert Date', buffer = true, noremap = true })
    vim.keymap.set('n', '<leader>tu', '<Plug>(neorg.qol.todo-items.todo.task-undone)', { desc = '[neorg] Mark as Undone', buffer = true, noremap = true })
    vim.keymap.set('n', '<leader>tp', '<Plug>(neorg.qol.todo-items.todo.task-pending)', { desc = '[neorg] Mark as Pending', buffer = true, noremap = true })
    vim.keymap.set('n', '<leader>td', '<Plug>(neorg.qol.todo-items.todo.task-done)', { desc = '[neorg] Mark as Done', buffer = true, noremap = true })
    vim.keymap.set('n', '<leader>th', '<Plug>(neorg.qol.todo-items.todo.task-on-hold)', { desc = '[neorg] Mark as On Hold', buffer = true, noremap = true })
    vim.keymap.set('n', '<leader>tc', '<Plug>(neorg.qol.todo-items.todo.task-cancelled)', { desc = '[neorg] Mark as Cancelled', buffer = true, noremap = true })
    vim.keymap.set('n', '<leader>tr', '<Plug>(neorg.qol.todo-items.todo.task-recurring)', { desc = '[neorg] Mark as Recurring', buffer = true, noremap = true })
    vim.keymap.set('n', '<leader>ti', '<Plug>(neorg.qol.todo-items.todo.task-important)', { desc = '[neorg] Mark as Important', buffer = true, noremap = true })
    vim.keymap.set('n', '<leader>ta', '<Plug>(neorg.qol.todo-items.todo.task-ambiguous)', { desc = '[neorg] Mark as Ambigous', buffer = true, noremap = true })
    vim.keymap.set('n', '<C-Space>', '<Plug>(neorg.qol.todo-items.todo.task-cycle)', { desc = '[neorg] Cycle Task', buffer = true, noremap = true })
    vim.keymap.set('n', '<CR>', '<Plug>(neorg.esupports.hop.hop-link)', { desc = '[neorg] Jump to Link', buffer = true, noremap = true })
    vim.keymap.set(
      'n',
      '<M-CR>',
      '<Plug>(neorg.esupports.hop.hop-link.vsplit)',
      { desc = '[neorg] Jump to Link (Vertical Split)', buffer = true, noremap = true }
    )
    vim.keymap.set('n', '>.', '<Plug>(neorg.promo.promote)', { desc = '[neorg] Promote Object (Non-Recursively)', buffer = true, noremap = true })
    vim.keymap.set('n', '<,', '<Plug>(neorg.promo.demote)', { desc = '[neorg] Demote Object (Non-Recursively)', buffer = true, noremap = true })
    vim.keymap.set('n', '>>', '<Plug>(neorg.promo.promote.nested)', { desc = '[neorg] Promote Object (Recursively)', buffer = true, noremap = true })
    vim.keymap.set('n', '<<', '<Plug>(neorg.promo.demote.nested)', { desc = '[neorg] Demote Object (Recursively)', buffer = true, noremap = true })
    vim.keymap.set('n', '<leader>lt', '<Plug>(neorg.pivot.list.toggle)', { desc = '[neorg] Toggle (Un)ordered List', buffer = true, noremap = true })
    vim.keymap.set('n', '<leader>li', '<Plug>(neorg.pivot.list.invert)', { desc = '[neorg] Invert (Un)ordered List', buffer = true, noremap = true })
    vim.keymap.set('n', '<leader>id', '<Plug>(neorg.tempus.insert-date)', { desc = '[neorg] Insert Date', buffer = true, noremap = true })
    vim.keymap.set('n', '<leader>cm', '<Plug>(neorg.looking-glass.magnify-code-block)', { desc = '[neorg] Magnify Code Block', buffer = true, noremap = true })
    vim.keymap.set('v', '>', '<Plug>(neorg.promo.promote.range)', { desc = '[neorg] Promote Objects in Range', buffer = true, noremap = true })
    vim.keymap.set('v', '<', '<Plug>(neorg.promo.demote.range)', { desc = '[neorg] Demote Objects in Range', buffer = true, noremap = true })
  end,
})
-- Hyprland Keyboard Bindings
-- AI Keyboard Bindings
vim.keymap.set('n', '<tab>', function()
  -- if there is a next edit, jump to it, otherwise apply it if any
  if not require('sidekick').nes_jump_or_apply() then
    return '<Tab>' -- fallback to normal tab
  end
end, {
  expr = true,
  desc = 'Goto/Apply Next Edit Suggestion',
})
vim.keymap.set('n', '<M-e>', function()
  -- if there is a next edit, jump to it, otherwise apply it if any
  if not require('sidekick.nes').clear() then
    return '<M-e>' -- fallback to normal tab
  end
end, {
  expr = true,
  desc = 'Goto/Apply Next Edit Suggestion',
})
vim.keymap.set({ 'n', 't', 'i', 'x' }, '<c-.>', function()
  require('sidekick.cli').toggle()
end, { desc = 'Sidekick Toggle' })
vim.keymap.set('n', '<leader>aa', function()
  require('sidekick.cli').toggle()
end, { desc = 'Sidekick Toggle CLI' })
vim.keymap.set(
  'n',
  '<leader>as',
  function()
    require('sidekick.cli').select()
  end,
  -- Or to select only installed tools:
  -- require("sidekick.cli").select({ filter = { installed = true } })
  { desc = 'Select CLI' }
)
vim.keymap.set('n', '<leader>ad', function()
  require('sidekick.cli').close()
end, { desc = 'Detach a CLI Session' })
vim.keymap.set({ 'x', 'n' }, '<leader>at', function()
  require('sidekick.cli').send { msg = '{this}' }
end, { desc = 'Send This' })
vim.keymap.set('n', '<leader>af', function()
  require('sidekick.cli').send { msg = '{file}' }
end, { desc = 'Send File' })
vim.keymap.set('x', '<leader>av', function()
  require('sidekick.cli').send { msg = '{selection}' }
end, { desc = 'Send Visual Selection' })
vim.keymap.set({ 'n', 'x' }, '<leader>ap', function()
  require('sidekick.cli').prompt()
end, { desc = 'Sidekick Select Prompt' })
-- Example of a keybinding to open Claude directly
vim.keymap.set('n', '<leader>ac', function()
  require('sidekick.cli').toggle { name = 'claude', focus = true }
end, { desc = 'Sidekick Toggle Claude' })

vim.keymap.set('i', '<M-l>', require('copilot.suggestion').accept, { desc = 'Accept Copilot Suggestion' })
vim.keymap.set('i', '<M-;>', require('copilot.suggestion').accept_word, { desc = 'Accept Copilot Suggestion (Single Word)' })
vim.keymap.set('i', '<M-]>', require('copilot.suggestion').next, { desc = 'Next Copilot Suggestion' })
vim.keymap.set('i', '<M-[>', require('copilot.suggestion').next, { desc = 'Previous Copilot Suggestion' })
vim.keymap.set('i', '<C-]>', require('copilot.suggestion').dismiss, { desc = 'Dismiss Copilot Suggestion' })

-- Harpoon Keymaps
local function harpoon_telescope(files)
  local conf = require('telescope.config').values
  local file_paths = {}
  for _, file in ipairs(files.items) do
    table.insert(file_paths, file.value)
  end
  require('telescope.pickers')
    .new({}, {
      prompt_title = 'Harpoon',
      finder = require('telescope.finders').new_table {
        results = file_paths,
      },
      previewer = conf.file_previewer {},
      sorter = conf.generic_sorter {},
    })
    :find()
end
local harpoon = require 'harpoon'
vim.keymap.set('n', '<leader>bb', function()
  harpoon_telescope(harpoon:list())
end, { desc = 'Open harpoon window' })

vim.keymap.set('n', '<leader>ba', function()
  harpoon:list():add()
end, { desc = 'Add Buffer to Harpoon' })
vim.keymap.set('n', '<leader>bc', function()
  harpoon:list():clear()
end, { desc = 'Clear Harpoon List' })
vim.keymap.set('n', '<leader>br', function()
  harpoon:list():remove()
end, { desc = 'Remove buffer from Harpoon' })

vim.keymap.set('n', '<leader>bp', function()
  harpoon:list():prev()
end, { desc = 'Open Previous Harpoon File' })
vim.keymap.set('n', '<leader>bn', function()
  harpoon:list():next()
end, { desc = 'Open Next Harpoon File' })
vim.keymap.set('n', '<leader>bj', function()
  harpoon:list():select(1)
end, { desc = 'Open Harpoon File [1]' })
vim.keymap.set('n', '<leader>bk', function()
  harpoon:list():select(2)
end, { desc = 'Open Harpoon File [2]' })
vim.keymap.set('n', '<leader>bl', function()
  harpoon:list():select(3)
end, { desc = 'Open Harpoon File [3]' })
vim.keymap.set('n', '<leader>b;', function()
  harpoon:list():select(4)
end, { desc = 'Open Harpoon File [4]' })

-- Textobjects Keymaps
-- NOTE: mini.ai owns bare `a`/`i` in operator/visual mode (brackets, quotes, tags,
-- function-CALL `f`, argument `a`, etc.). To avoid shadowing mini.ai and the
-- `a`/`i` `timeoutlen` stall, treesitter SELECT objects live under the `<leader>v`
-- group. Mnemonic: `a`/`i` = around/inside, `f`/`c`/`p` = function/class/parameter.
vim.keymap.set({ 'x', 'o' }, '<leader>vaf', function()
  require('nvim-treesitter-textobjects.select').select_textobject('@function.outer', 'textobjects')
end, { desc = 'Select around function' })
vim.keymap.set({ 'x', 'o' }, '<leader>vif', function()
  require('nvim-treesitter-textobjects.select').select_textobject('@function.inner', 'textobjects')
end, { desc = 'Select inside function' })
vim.keymap.set({ 'x', 'o' }, '<leader>vac', function()
  require('nvim-treesitter-textobjects.select').select_textobject('@class.outer', 'textobjects')
end, { desc = 'Select around class' })
vim.keymap.set({ 'x', 'o' }, '<leader>vic', function()
  require('nvim-treesitter-textobjects.select').select_textobject('@class.inner', 'textobjects')
end, { desc = 'Select inside class' })
vim.keymap.set({ 'x', 'o' }, '<leader>vap', function()
  require('nvim-treesitter-textobjects.select').select_textobject('@parameter.outer', 'textobjects')
end, { desc = 'Select around parameter' })
vim.keymap.set({ 'x', 'o' }, '<leader>vip', function()
  require('nvim-treesitter-textobjects.select').select_textobject('@parameter.inner', 'textobjects')
end, { desc = 'Select inside parameter' })
vim.keymap.set('n', '<leader>pn', function()
  require('nvim-treesitter-textobjects.swap').swap_next '@parameter.inner'
end, { desc = 'Swap parameter with next' })
vim.keymap.set('n', '<leader>pp', function()
  require('nvim-treesitter-textobjects.swap').swap_previous '@parameter.inner'
end, { desc = 'Swap parameter with previous' })
vim.keymap.set({ 'n', 'x', 'o' }, ']m', function()
  require('nvim-treesitter-textobjects.move').goto_next_start('@function.outer', 'textobjects')
end, { desc = 'Go to next function start' })
vim.keymap.set({ 'n', 'x', 'o' }, ']]', function()
  require('nvim-treesitter-textobjects.move').goto_next_start('@class.outer', 'textobjects')
end, { desc = 'Go to next class start' })
-- You can also pass a list to group multiple queries.
vim.keymap.set({ 'n', 'x', 'o' }, ']M', function()
  require('nvim-treesitter-textobjects.move').goto_next_end('@function.outer', 'textobjects')
end, { desc = 'Go to next function end' })
vim.keymap.set({ 'n', 'x', 'o' }, '][', function()
  require('nvim-treesitter-textobjects.move').goto_next_end('@class.outer', 'textobjects')
end, { desc = 'Go to next class end' })

vim.keymap.set({ 'n', 'x', 'o' }, '[m', function()
  require('nvim-treesitter-textobjects.move').goto_previous_start('@function.outer', 'textobjects')
end, { desc = 'Go to previous function start' })
vim.keymap.set({ 'n', 'x', 'o' }, '[[', function()
  require('nvim-treesitter-textobjects.move').goto_previous_start('@class.outer', 'textobjects')
end, { desc = 'Go to previous class start' })

vim.keymap.set({ 'n', 'x', 'o' }, '[M', function()
  require('nvim-treesitter-textobjects.move').goto_previous_end('@function.outer', 'textobjects')
end, { desc = 'Go to previous function end' })
vim.keymap.set({ 'n', 'x', 'o' }, '[]', function()
  require('nvim-treesitter-textobjects.move').goto_previous_end('@class.outer', 'textobjects')
end, { desc = 'Go to previous class end' })
vim.keymap.set({ 'n', 'x', 'o' }, '<c-space>', function()
  require('flash').treesitter {
    actions = {
      ['<c-space>'] = 'next',
      ['<M-space>'] = 'prev',
    },
  }
end, { desc = 'Treesitter incremental selection' })
vim.keymap.set({ 'n', 'x', 'o' }, '<C-s>', function()
  require('flash').jump()
end, { desc = 'Flash' })
vim.keymap.set({ 'n', 'x', 'o' }, 'S', function()
  require('flash').treesitter()
end, { desc = 'Flash Treesitter' })
vim.keymap.set('o', 'r', function()
  require('flash').remote()
end, { desc = 'Remote Flash' })
vim.keymap.set({ 'o', 'x' }, 'R', function()
  require('flash').treesitter_search()
end, { desc = 'Treesitter Search' })
vim.keymap.set({ 'c' }, '<c-s>', function()
  require('flash').toggle()
end, { desc = 'Toggle Flash Search' })
vim.api.nvim_create_user_command('DisableAI', function()
  vim.cmd ':Copilot disable'
  vim.cmd ':Sidekick nes disable'
  vim.notify('AI Disabled', vim.log.levels.INFO)
end, { desc = 'Disable all AI integrations' })
