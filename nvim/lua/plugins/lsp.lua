return {
    -- LSP Configuration & Plugins
    "neovim/nvim-lspconfig",
    dependencies = {
        -- Automatically install LSPs to stdpath for neovim
        { "williamboman/mason.nvim", config = true },
        "williamboman/mason-lspconfig.nvim",
        "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
        vim.diagnostic.config({ virtual_text = true })
        vim.api.nvim_create_autocmd("LspAttach", {
            group = vim.api.nvim_create_augroup("kickstart-lsp-attach", { clear = true }),
            callback = function(event)
                local client = vim.lsp.get_client_by_id(event.data.client_id)
                if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
                    local highlight_augroup = vim.api.nvim_create_augroup("kickstart-lsp-highlight", { clear = false })
                    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
                        buffer = event.buf,
                        group = highlight_augroup,
                        callback = vim.lsp.buf.document_highlight,
                    })

                    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
                        buffer = event.buf,
                        group = highlight_augroup,
                        callback = vim.lsp.buf.clear_references,
                    })

                    vim.api.nvim_create_autocmd("LspDetach", {
                        group = vim.api.nvim_create_augroup("kickstart-lsp-detach", { clear = true }),
                        callback = function(event2)
                            vim.lsp.buf.clear_references()
                            vim.api.nvim_clear_autocmds({ group = "kickstart-lsp-highlight", buffer = event2.buf })
                        end,
                    })
                end

                -- The following code creates a keymap to toggle inlay hints in your
                -- code, if the language server you are using supports them
                --
                -- This may be unwanted, since they displace some of your code
                vim.api.nvim_buf_create_user_command(event.buf, "Format", function(_)
                    vim.lsp.buf.format()
                end, { desc = "Format current buffer with LSP" })
            end,
        })
        local servers = {
            clangd = {
                "--clang-tidy",
                "--completion-style=detailed",
                "--fallback-style=Google",
                "--header-insertions=iwyu",
                "--offset-encoding=utf-8",
            },
            -- gopls = {},
            -- pyright = {},
            rust_analyzer = {},
            -- tsserver = {},
            -- html = { filetypes = { 'html', 'twig', 'hbs'} },

            lua_ls = {
                Lua = {
                    workspace = { checkThirdParty = false },
                    telemetry = { enable = false },
                    diagnostics = { disable = { "missing-fields" } },
                },
            },
            texlab = {},
        }
        for server_name, settings_value in pairs(servers) do
            vim.lsp.enable(server_name)
            vim.lsp.config(server_name, {
                settings = settings_value,
            })
        end

        -- nvim-cmp supports additional completion capabilities, so broadcast that to servers
        local capabilities = vim.lsp.protocol.make_client_capabilities()
        capabilities = vim.tbl_deep_extend("force", capabilities, require("cmp_nvim_lsp").default_capabilities(capabilities))

        -- Ensure the servers above are installed
        local mason = require "mason"
        local mason_lspconfig = require "mason-lspconfig"

        mason_lspconfig.setup({
            ensure_installed = vim.tbl_keys(servers),
        })

        vim.lsp.enable "hls"
        vim.lsp.config("hls", {
            cmd = { "ghcup" },
            settings = { "run", "--hls", "latest", "--ghc", "latest", "--cabal", "latest", "--", "haskell-language-server-wrapper", "--lsp" },
        })
    end,
}
