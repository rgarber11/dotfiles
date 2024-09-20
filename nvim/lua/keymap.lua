vim.keymap.set({ "n", "v" }, "<Space>", "<Nop>", { silent = true })
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")
-- Remap for dealing with word wrap
vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
vim.keymap.set("n", "<C-h>", "<C-w><C-h>", { desc = "Move focus to the left window" })
vim.keymap.set("n", "<C-l>", "<C-w><C-l>", { desc = "Move focus to the right window" })
vim.keymap.set("n", "<C-j>", "<C-w><C-j>", { desc = "Move focus to the lower window" })
vim.keymap.set("n", "<C-k>", "<C-w><C-k>", { desc = "Move focus to the upper window" })
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
vim.keymap.set("n", "<leader>?", require("telescope.builtin").oldfiles, { desc = "[?] Find recently opened files" })
vim.keymap.set("n", "<leader><space>", require("telescope.builtin").buffers, { desc = "[ ] Find existing buffers" })
vim.keymap.set("n", "<leader>/", function()
    -- You can pass additional configuration to telescope to change theme, layout, etc.
    require("telescope.builtin").current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
        winblend = 10,
        previewer = false,
    }))
end, { desc = "[/] Fuzzily search in current buffer" })

vim.keymap.set("n", "<leader>gf", require("telescope.builtin").git_files, { desc = "Search [G]it [F]iles" })
vim.keymap.set("n", "<leader>sf", require("telescope.builtin").find_files, { desc = "[S]earch [F]iles" })
vim.keymap.set("n", "<leader>sh", require("telescope.builtin").help_tags, { desc = "[S]earch [H]elp" })
vim.keymap.set("n", "<leader>sw", require("telescope.builtin").grep_string, { desc = "[S]earch current [W]ord" })
vim.keymap.set("n", "<leader>sg", require("telescope.builtin").live_grep, { desc = "[S]earch by [G]rep" })
vim.keymap.set("n", "<leader>sd", require("telescope.builtin").diagnostics, { desc = "[S]earch [D]iagnostics" })
vim.keymap.set("n", "<leader>sr", require("telescope.builtin").resume, { desc = "[S]earch [R]resume" })
vim.keymap.set("n", "<leader>u", function()
    vim.cmd "Telescope undo"
end, { noremap = true, desc = "Undo History" })
-- DAP keybinds
vim.keymap.set("n", "<leader>db", require("dap").toggle_breakpoint, { desc = "Add breakpoint at line" })
vim.keymap.set("n", "<leader>dr", require("dap").continue, { desc = "Run/continue debugger" })
vim.keymap.set("n", "<leader>dc", function()
    require("dap").terminate()
    require("dapui").close()
end, { desc = "Terminate debugger" })
vim.keymap.set("n", "<leader>di", require("dap").step_into, { desc = "Step into function" })
vim.keymap.set("n", "<leader>do", require("dap").step_into, { desc = "Step over function" })

-- Diagnostic keymaps
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Go to previous diagnostic message" })
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Go to next diagnostic message" })
vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "Open floating diagnostic message" })
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostics list" })

vim.keymap.set("n", "<leader>p", require("nabla").popup, { noremap = true, desc = "Open Nabla Popup" })
vim.keymap.set("n", "<leader>nt", function()
    if vim.bo.filetype == "markdown" then
        if require("nabla").is_virt_enabled(0) then
            require("markview").configuration.latex.enable = false
        else
            require("markview").configuration.latex.enable = true
        end
    end
    require("nabla").toggle_virt()
end, { noremap = true, desc = "Toggle Nabla Virt" })
-- Overseer Keymaps
vim.keymap.set("n", "<leader>or", function()
    vim.cmd "OverseerRun"
end, { noremap = true, desc = "Open Task Runner Menu" })
vim.keymap.set("n", "<leader>ot", function()
    vim.cmd "OverseerToggle"
end, { noremap = true, desc = "Toggle Task Results" })
-- Oil Keymaps
vim.keymap.set("n", "<leader>nr", function()
    require("oil").open()
end, { noremap = true, desc = "Open Oil" })
vim.keymap.set("n", "<leader>ns", function()
    vim.cmd "split"
    require("oil").open()
end, { noremap = true, desc = "Split Side Oil" })
vim.keymap.set("n", "<leader>nv", function()
    vim.cmd "vsplit"
    require("oil").open()
end, { noremap = true, desc = "Split Vertical Oil" })
vim.keymap.set("n", "<leader>no", function()
    require("oil").open_float()
end, { noremap = true, desc = "Open Oil in Hover Mode" })
-- Formatting Keybind
vim.keymap.set({ "n", "v" }, "<leader>f", function()
    require("conform").format({
        lsp_fallback = true,
        async = false,
        timeout_ms = 500,
    })
end, { desc = "Format file or range (in visual mode)" })
-- Norg Latex
vim.keymap.set("n", "<leader>mt", function()
    vim.cmd "Neorg render-latex toggle"
end, { desc = "Toggle Neorg Latex Rendering" })
-- LSP Specific Keymaps
local langs = { "English (US)", "Russian", "Spanish" }
local lang_codes = { "en-US", "ru-RU", "es" }
local set_ltex_lang = function(lsp_id, lang_id)
    local client = vim.lsp.get_client_by_id(lsp_id)
    if client == nil then
        return
    end
    local lang = lang_codes[lang_id]
    vim.notify("LTeX language set to " .. langs[lang_id], vim.log.levels.INFO)
    client.config.settings.ltex.language = lang
    vim.lsp.buf_notify(0, "workspace/didChangeConfiguration", { settings = client.config.settings })
    pcall(require("ltex_extra").reload, { lang })
end
local create_language_select_menu = function(lsp_id)
    vim.ui.select(langs, {
        format_item = function(e)
            return tostring(e)
        end,
        prompt = "Select LTeX Language...",
        kind = "make_indexed",
    }, function(_, choice_id)
        if choice_id == nil then
            return
        end
        set_ltex_lang(lsp_id, choice_id)
    end)
end
vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
        local nmap = function(keys, func, desc)
            if desc then
                desc = "LSP: " .. desc
            end

            vim.keymap.set("n", keys, func, { buffer = args.buf, desc = desc })
        end

        nmap("<leader>rn", vim.lsp.buf.rename, "[R]e[n]ame")
        nmap("<leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction")

        nmap("gd", vim.lsp.buf.definition, "[G]oto [D]efinition")
        nmap("gr", require("telescope.builtin").lsp_references, "[G]oto [R]eferences")
        nmap("gI", vim.lsp.buf.implementation, "[G]oto [I]mplementation")
        nmap("<leader>D", vim.lsp.buf.type_definition, "Type [D]efinition")
        nmap("<leader>ds", require("telescope.builtin").lsp_document_symbols, "[D]ocument [S]ymbols")
        nmap("<leader>ws", require("telescope.builtin").lsp_dynamic_workspace_symbols, "[W]orkspace [S]ymbols")

        -- See `:help K` for why this keymap
        nmap("K", vim.lsp.buf.hover, "Hover Documentation")
        nmap("<C-k>", vim.lsp.buf.signature_help, "Signature Documentation")

        -- Lesser used LSP functionality'
        nmap("gD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")
        nmap("<leader>wa", vim.lsp.buf.add_workspace_folder, "[W]orkspace [A]dd Folder")
        nmap("<leader>wr", vim.lsp.buf.remove_workspace_folder, "[W]orkspace [R]emove Folder")
        nmap("<leader>wl", function()
            print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
        end, "[W]orkspace [L]ist Folders")
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client == nil then
            return
        end
        if client.supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
            nmap("<leader>th", function()
                vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = args.buf }))
            end, "[T]oggle Inlay [H]ints")
        end
        if client.name == "ltex" then
            vim.keymap.set("n", "<leader>lt", function()
                create_language_select_menu(client.id)
            end, { noremap = true, desc = "Toggle LTeX Language" })
        end
    end,
})
-- Gitsigns Uses OnAttach, so its config is here
require("gitsigns").setup({
    -- See `:help gitsigns.txt`
    signs = {
        add = { text = "+" },
        change = { text = "~" },
        delete = { text = "_" },
        topdelete = { text = "‾" },
        changedelete = { text = "~" },
    },
    on_attach = function(bufnr)
        vim.keymap.set("n", "<leader>hp", require("gitsigns").preview_hunk, { buffer = bufnr, desc = "Preview git hunk" })

        -- don't override the built-in and fugitive keymaps
        local gs = package.loaded.gitsigns
        vim.keymap.set({ "n", "v" }, "]c", function()
            if vim.wo.diff then
                return "]c"
            end
            vim.schedule(function()
                gs.next_hunk()
            end)
            return "<Ignore>"
        end, { expr = true, buffer = bufnr, desc = "Jump to next hunk" })
        vim.keymap.set({ "n", "v" }, "[c", function()
            if vim.wo.diff then
                return "[c"
            end
            vim.schedule(function()
                gs.prev_hunk()
            end)
            return "<Ignore>"
        end, { expr = true, buffer = bufnr, desc = "Jump to previous hunk" })
    end,
})
