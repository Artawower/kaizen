local g = vim.g

require("toggleterm").setup {

    size = function(term)
        if term.direction == "horizontal" then
            return 15
        elseif term.direction == "vertical" then
            return vim.o.columns * 0.4
        end
    end,
    open_mapping = [[<c-\>]],
    hide_numbers = true, 
    shade_filetypes = {},
    shade_terminals = true,

    start_in_insert = true,
    insert_mappings = true, 
    persist_size = true,
    direction = "float",
    close_on_exit = true, 
    shell = vim.o.shell, 

    float_opts = {

        

        
        border = "single",
        width = 120,
        height = 30,
        winblend = 3,
        highlights = {
            border = "Normal",
            background = "Normal"
        }
    }
}

function _G.set_terminal_keymaps()
    local opts = {noremap = true}
    vim.api.nvim_buf_set_keymap(0, "t", "<esc>", [[<C-\><C-n>]], opts)
    vim.api.nvim_buf_set_keymap(0, "t", "jk", [[<C-\><C-n>]], opts)
    vim.api.nvim_buf_set_keymap(0, "t", "<C-w>h", [[<C-\><C-n><C-W>h]], opts)
    vim.api.nvim_buf_set_keymap(0, "t", "<C-w>j", [[<C-\><C-n><C-W>j]], opts)
    vim.api.nvim_buf_set_keymap(0, "t", "<C-w>k", [[<C-\><C-n><C-W>k]], opts)
    vim.api.nvim_buf_set_keymap(0, "t", "<C-w>l", [[<C-\><C-n><C-W>l]], opts)
end

vim.cmd("autocmd! TermOpen term://*toggleterm#* lua set_terminal_keymaps()")

local wk = require("which-key")

wk.add({
    { "<space>o", group = "Terminal" },
    { "<space>ot", ":ToggleTerm size=20 direction=horizontal<CR>", desc = "Open horizontal terminal", remap = false },
    { "<space>oT", ":ToggleTerm size=20 direction=float<CR>", desc = "Float terminal", remap = false },

    { "<leader>", group = "Translate" },
    { "<leader>t", ":TranslateW --target_lang=ru --source_lang=auto<CR>", desc = "Translate line", mode = "v" },
    { "<leader>r", ":TranslateW --target_lang=en --source_lang=ru<CR>", desc = "Translate ru" },
})

