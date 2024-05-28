local function harpoon_telescope(files)
    local conf = require("telescope.config").values
    local file_paths = {}
    for _, file in ipairs(files.items) do
        table.insert(file_paths, file.value)
    end
    require("telescope.pickers")
        .new({}, {
            prompt_title = "Harpoon",
            finder = require("telescope.finders").new_table({
                results = file_paths,
            }),
            previewer = conf.file_previewer({}),
            sorter = conf.generic_sorter({}),
        })
        :find()
end
local harpoon = require "harpoon"
vim.keymap.set("n", "<C-e>", function()
    harpoon_telescope(harpoon:list())
end, { desc = "Open harpoon window" })

vim.keymap.set("n", "<C-a>", function()
    harpoon:list():add()
end)
vim.keymap.set("n", "<C-r>", function()
    harpoon:list():remove()
end)

vim.keymap.set("n", "<C-M-P>", function()
    harpoon:list():prev()
end)
vim.keymap.set("n", "<C-M-N>", function()
    harpoon:list():next()
end)
vim.keymap.set("n", "<C-u>", function()
    harpoon:list():select(1)
end)
vim.keymap.set("n", "<C-i>", function()
    harpoon:list():select(2)
end)
vim.keymap.set("n", "<C-o>", function()
    harpoon:list():select(3)
end)
vim.keymap.set("n", "<C-p>", function()
    harpoon:list():select(4)
end)
