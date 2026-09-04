local map = vim.keymap.set;

local command_shell = vim.fn.exepath("dash")
if command_shell == "" then
  command_shell = vim.fn.exepath("sh")
end
vim.opt.shell = command_shell

vim.g.mapleader = " "


-- Clipboard
vim.opt.clipboard = "unnamedplus"

-- Prevent savind the selected region to the clipboard
map({ "n", "x" }, "c", '"_c')
map("n", "C", '"_C')
map("n", "cc", '"_cc')

map("x", "p", '"_dP', {
  desc = "Paste without yanking replaced text",
})


-- Undo
vim.cmd.packadd("nvim.undotree")
vim.opt.undofile = true


-- Image reading
vim.pack.add({
  { src = "https://github.com/3rd/image.nvim" },
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
