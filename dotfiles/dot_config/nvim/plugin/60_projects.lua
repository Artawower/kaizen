vim.pack.add({
  { src = "https://github.com/DrKJeff16/project.nvim" },
  { src = "https://github.com/rmagatti/auto-session" },
  { src = "https://github.com/folke/snacks.nvim" },
})

vim.pack.add({
  {
    src = "https://github.com/chrisgrieser/nvim-early-retirement",
    data = {
      event = "DeferredUIEnter",
      after = function()
        require("early-retirement").setup({
          retirementAgeMins = 30,
          minimumBufferNum = 5,
          ignoreUnsavedChangesBufs = true,
          ignoreVisibleBufs = true,
          ignoreSpecialBuftypes = true,
          notificationOnAutoClose = false,
        })
      end,
    },
  },
}, { load = require("lz.n").load })

require("auto-session").setup({
  cwd_change_handling = true,
  pre_save_cmds = {
    function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local name = vim.api.nvim_buf_get_name(buf)

          if name:match("^guh://") then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
          end
        end
      end
    end,
  },
})

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

vim.keymap.set("n", "<leader>pp", function()
  require("project.extensions.snacks").pick()
end, {
  desc = "Projects",
})
