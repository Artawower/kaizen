vim.pack.add({
  { src = "https://github.com/mfussenegger/nvim-dap" },

  {
    src = "https://github.com/igorlfs/nvim-dap-view",
    version = vim.version.range("1.*"),
  },

  { src = "https://github.com/mfussenegger/nvim-dap-python" },
  { src = "https://github.com/leoluz/nvim-dap-go" },
})

local dap = require("dap")
local map = vim.keymap.set

require("dap-view").setup({
  auto_toggle = true,
})

-- Python
require("dap-python").setup("debugpy-adapter")

-- Go
require("dap-go").setup()

-- Continue / start
map({ "n", "x" }, "<leader>dc", dap.continue, {
  desc = "Debug continue",
})

-- Breakpoint
map({ "n", "x" }, "<leader>db", dap.toggle_breakpoint, {
  desc = "Toggle breakpoint",
})

-- Step over
map({ "n", "x" }, "<leader>dn", dap.step_over, {
  desc = "Step over",
})

-- Step into
map({ "n", "x" }, "<leader>di", dap.step_into, {
  desc = "Step into",
})

-- Step out
map({ "n", "x" }, "<leader>do", dap.step_out, {
  desc = "Step out",
})

-- Terminate
map({ "n", "x" }, "<leader>dq", dap.terminate, {
  desc = "Terminate debug session",
})

-- Debug UI
map({ "n", "x" }, "<leader>dv", "<cmd>DapViewToggle<CR>", {
  desc = "Toggle debug view",
})

-- REPL
map({ "n", "x" }, "<leader>dr", dap.repl.toggle, {
  desc = "Toggle debug REPL",
})
