-- Shell
local command_shell = vim.fn.exepath("dash")
if command_shell == "" then
  command_shell = vim.fn.exepath("sh")
end
vim.opt.shell = command_shell

-- Leader
vim.g.mapleader = " "

-- Clipboard
vim.opt.clipboard = "unnamedplus"

-- Editing
-- Prevent line break after entire line replacing
vim.opt.virtualedit = "onemore"
-- Tabs
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Diagnostics
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 300

-- Undo
vim.opt.undofile = true

-- Autosave
local function autosave()
  local buf = vim.api.nvim_get_current_buf()

  if vim.bo[buf].buftype ~= "" then
    return
  end

  if not vim.bo[buf].modifiable or vim.bo[buf].readonly then
    return
  end

  local name = vim.api.nvim_buf_get_name(buf)

  if name == "" or vim.fn.filereadable(name) == 0 then
    return
  end

  vim.cmd.update()
end

vim.api.nvim_create_autocmd({
  "InsertLeave",
  "BufLeave",
  "FocusLost",
}, {
  callback = autosave,
})

-- Packages
vim.pack.add({
  { src = "https://github.com/3rd/image.nvim" },
  { src = "https://github.com/nvim-mini/mini.diff" },
})

require("image").setup({
  backend = "kitty",

  hijack_file_patterns = {
    "*.png",
    "*.jpg",
    "*.jpeg",
    "*.gif",
    "*.webp",
    "*.avif",
  },
})


-- Sidebar
vim.opt.fillchars:append({
  eob = " ",
})
