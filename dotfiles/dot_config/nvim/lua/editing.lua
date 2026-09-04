vim.pack.add({
  "https://github.com/nvim-mini/mini.surround",
})

vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.expandtab = true
vim.opt.smartindent = true

-- surround brackets
require("mini.surround").setup({
  mappings = {
    add = "ms",
    delete = "md",
    replace = "mr",

    find = "mf",
    find_left = "mF",
    highlight = "mh",

    suffix_last = "l",
    suffix_next = "n",
  },
})

-- Autopairs
vim.pack.add({
  "https://github.com/nvim-mini/mini.pairs",
})

require("mini.pairs").setup()


-- Treesiteer
vim.pack.add({
  { src = "https://github.com/nvim-treesitter/nvim-treesitter" },
})

require("nvim-treesitter").install({
  "lua",
  "python",
  "go",
  "rust",
  "javascript",
  "typescript",
  "tsx",
  "json",
  "html",
  "css",
  "bash",
  "markdown",
  "vue"
})

vim.api.nvim_create_autocmd("FileType", {
  callback = function()
    pcall(vim.treesitter.start)
  end,
})
