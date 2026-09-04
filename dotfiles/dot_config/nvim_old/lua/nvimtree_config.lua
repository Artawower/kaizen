local g = vim.g

require "nvim-tree".setup {
    disable_netrw = true,
    hijack_netrw = true,

    open_on_tab = true,
    hijack_cursor = false,
    update_cwd = false,

    

    

    

    

    
    diagnostics = {
        enable = false,
        icons = {
            hint = "",
            info = "",
            warning = "",
            error = ""
        }
    },
    update_focused_file = {
        enable = true,
        update_cwd = true,
        update_cwd = false,
        ignore_list = {}
    },
    system_open = {
        cmd = nil,
        args = {}
    },
    filters = {
        dotfiles = false,
        custom = {}
    },
    git = {
        enable = true,
        ignore = true,
        timeout = 500
    },
    trash = {
        cmd = "trash",
        require_confirm = true
    },

    sync_root_with_cwd = true,
    respect_buf_cwd = true
}

g.nvim_tree_icons = {
     default = '',
     symlink = '',
     git = {
       unstaged = "✗",
       staged = "✓",
       unmerged = "",
       renamed =  "➜",
       untracked = "★",
       deleted = "",
       ignored = "◌"
       },
     folder =  {
       arrow_open = "",
       arrow_closed = "",
       default = "",
       open = "",
       empty = "",
       empty_open = "",
       symlink = "",
       symlink_open = "",
       }
     }

local wk = require("which-key")

wk.add({
    { "<space>", group = "completion" },
    { "<space>op", ":NvimTreeToggle<CR>", desc = "Toggle file tree" },
    { "<space>oP", ":NvimTreeFindFile<CR>", desc = "Focus current file" },
})

