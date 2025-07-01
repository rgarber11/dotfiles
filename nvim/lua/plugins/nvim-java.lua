return {
    "nvim-java/nvim-java",
    dependencies = "neovim/nvim-lspconfig",
    ft = "java",
    config = function()
        require("java").setup()
        vim.lsp.enable "jdtls"
        vim.lsp.config("jdtls", {
            settings = {},
        })
    end,
}
