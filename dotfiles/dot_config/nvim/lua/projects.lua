vim.pack.add({
  { src = "https://github.com/DrKJeff16/project.nvim" },
  { src = "https://github.com/rmagatti/auto-session" },
})

local map = vim.keymap.set

-- Sessions
require("auto-session").setup({
  cwd_change_handling = true,
})

-- Projects
require("project").setup({
  patterns = {
    ".git",
    ".jj",
    "go.mod",
    "Cargo.toml",
    "package.json",
    "pyproject.toml",
  },

  lsp = {
    enabled = true,
  },

  scope_chdir = "global",
  silent_chdir = true,

  snacks = {
    enabled = true,

    opts = {
      sort = "newest",
      hidden = false,
      title = "Projects",
      layout = "ivy",
      show = "names",
    },
  },
})

-- Switch project
map("n", "<leader>pp", function()
  require("project.extensions.snacks").pick()
end, {
  desc = "Projects",
})
