return {
    "barreiroleo/ltex_extra.nvim",
    config = function()
        vim.api.nvim_create_autocmd("LspAttach", {
            callback = function(args)
                local client = vim.lsp.get_client_by_id(args.data.client_id)
                if client and client.name == "ltex" then
                    require("ltex_extra").setup()
                end
            end,
        })
    end,
}
