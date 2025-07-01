return {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    opts = {
        panel = {
            enabled = false,
        },
        suggestion = {
            auto_trigger = true,
            keymap = {
                accept = "<M-l>",
                accept_word = "<M-;>",
                accept_line = false,
                next = "<M-]>",
                prev = "<M-[>",
                dismiss = "<C-]>",
            },
        },
    },
}
