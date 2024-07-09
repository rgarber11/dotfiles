local lspconfig = require "lspconfig"
lspconfig.hls.setup({
    cmd = { "ghcup run hls", "--lsp" },
})
