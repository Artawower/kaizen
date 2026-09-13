local command_shell = vim.fn.exepath("dash")
if command_shell == "" then
  command_shell = vim.fn.exepath("sh")
end
vim.opt.shell = command_shell

vim.g.mapleader = " "

vim.opt.clipboard = "unnamedplus"

vim.opt.virtualedit = "onemore"
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.expandtab = true
vim.opt.smartindent = true

vim.opt.signcolumn = "yes"
vim.opt.updatetime = 300

vim.opt.undofile = true

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

vim.pack.add({
  {
    src = "https://github.com/3rd/image.nvim",
    data = {
      cmd = "ImageReport",
      event = {
        {
          event = "BufReadPre",
          pattern = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" },
        },
      },
      after = function()
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
      end,
    },
  },
}, { load = require("lz.n").load })

vim.opt.fillchars:append({
  eob = " ",
})

