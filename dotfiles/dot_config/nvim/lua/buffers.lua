vim.pack.add({
  {
    src = "https://github.com/serhez/bento.nvim",
    version = "feat/v2",
  },
})

local map = vim.keymap.set;

require("bento").setup({
  max_open_buffers = nil,

  buffer_deletion_metric = "frecency_access",
  buffer_notify_on_delete = true,

  ordering_metric = "access",
  locked_first = false,

  ui = {
    mode = "floating",

    floating = {
      position = "middle-right",
      offset_x = 0,
      offset_y = 0,
      dash_char = "─",
      border = "none",
      label_padding = 1,
      minimal_menu = nil,
      max_rendered_buffers = nil,
    },
  },
})

local api = require("bento.api")

-- Menu
api.register_expand_key(";")
api.register_last_buffer_key(";")

api.register_collapse_key("<Esc>")

api.register_prev_page_key("[")
api.register_next_page_key("]")

-- Actions
api.register_action("open", {
  key = "<CR>",
  action = api.actions.open,
  hl = "DiagnosticVirtualTextHint",
})

api.register_action("delete", {
  key = "<BS>",
  action = api.actions.delete,
  hl = "DiagnosticVirtualTextError",
})

api.register_action("vsplit", {
  key = "|",
  action = api.actions.vsplit,
  hl = "DiagnosticVirtualTextInfo",
})

api.register_action("split", {
  key = "_",
  action = api.actions.split,
  hl = "DiagnosticVirtualTextInfo",
})

api.register_action("lock", {
  key = "*",
  action = api.actions.lock,
  hl = "DiagnosticVirtualTextWarn",
})

api.set_default_action("open")

local function toggle_maximize()
  if vim.t.maximize_restore then
    vim.cmd(vim.t.maximize_restore)
    vim.t.maximize_restore = nil
    return
  end

  vim.t.maximize_restore = vim.fn.winrestcmd()

  vim.cmd("wincmd _")
  vim.cmd("wincmd |")
end

map("n", "<leader>wf", toggle_maximize, {
  desc = "Toggle window maximize",
})

-------

-- Rotate windows
map("n", "<leader>wr", "<C-w>r", {
  desc = "Rotate windows",
})

-- Window navigation
map("n", "<C-w>h", "<C-w>h", {
  desc = "Window left",
})

map("n", "<C-w>n", "<C-w>j", {
  desc = "Window down",
})

map("n", "<C-w>e", "<C-w>k", {
  desc = "Window up",
})

map("n", "<C-w>i", "<C-w>l", {
  desc = "Window right",
})
