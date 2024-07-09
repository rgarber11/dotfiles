-- Toggle Latex Rendering
vim.keymap.set("n", "<leader>mt", function()
    vim.cmd "Neorg render-latex toggle"
end, { desc = "Toggle Neorg Latex Rendering" })
