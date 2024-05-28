-- Toggle Latex Rendering
local latex_enabled_buffers = {}
function toggle_latex_rendering()
    local buffer = vim.api.nvim_get_current_buf()
    if latex_enabled_buffers[buffer] then
        latex_enabled_buffers[buffer] = false
        vim.cmd "Neorg clear-latex"
    else
        latex_enabled_buffers[buffer] = true
        vim.cmd "Neorg render-latex"
    end
end

vim.keymap.set("n", "<leader>mt", toggle_latex_rendering, { desc = "Toggle Neorg Latex Rendering" })
