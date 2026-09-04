local command_shell = vim.fn.exepath("dash")
if command_shell == "" then
    command_shell = vim.fn.exepath("sh")
end
vim.opt.shell = command_shell

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
    vim.fn.system(
        {
            "git",
            "clone",
            "--filter=blob:none",
            "https://github.com/folke/lazy.nvim.git",
            "--branch=stable",
            lazypath
        }
    )
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins")
require("core")
