return {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim" },
    config = function()
        require("harpoon").setup({})
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
        vim.keymap.set("n", "<leader>bb", function()
            harpoon_telescope(harpoon:list())
        end, { desc = "Open harpoon window" })

        vim.keymap.set("n", "<leader>ba", function()
            harpoon:list():add()
        end, { desc = "Add Buffer to Harpoon" })
        vim.keymap.set("n", "<leader>bc", function()
            harpoon:list():clear()
        end, { desc = "Clear Harpoon List" })
        vim.keymap.set("n", "<leader>br", function()
            harpoon:list():remove()
        end, { desc = "Remove buffer from Harpoon" })

        vim.keymap.set("n", "<leader>bp", function()
            harpoon:list():prev()
        end, { desc = "Open Previous Harpoon File" })
        vim.keymap.set("n", "<leader>bn", function()
            harpoon:list():next()
        end, { desc = "Open Next Harpoon File" })
        vim.keymap.set("n", "<leader>bj", function()
            harpoon:list():select(1)
        end, { desc = "Open Harpoon File [1]" })
        vim.keymap.set("n", "<leader>bk", function()
            harpoon:list():select(2)
        end, { desc = "Open Harpoon File [2]" })
        vim.keymap.set("n", "<leader>bl", function()
            harpoon:list():select(3)
        end, { desc = "Open Harpoon File [3]" })
        vim.keymap.set("n", "<leader>b;", function()
            harpoon:list():select(4)
        end, { desc = "Open Harpoon File [4]" })
    end,
}
