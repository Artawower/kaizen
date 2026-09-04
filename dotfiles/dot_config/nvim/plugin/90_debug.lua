-- Packages
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

-- DAP UI

require("dap-view").setup({
  auto_toggle = true,
})

-- Languages

require("dap-python").setup("debugpy-adapter")
require("dap-go").setup()

-- Keymaps

map({ "n", "x" }, "<leader>dc", dap.continue, {
  desc = "Debug continue",
})

map({ "n", "x" }, "<leader>db", dap.toggle_breakpoint, {
  desc = "Toggle breakpoint",
})

map("n", "<leader>dB", function()
  dap.set_breakpoint(
    vim.fn.input("Breakpoint condition: ")
  )
end, {
  desc = "Conditional breakpoint",
})

map({ "n", "x" }, "<leader>dn", dap.step_over, {
  desc = "Step over",
})

map({ "n", "x" }, "<leader>di", dap.step_into, {
  desc = "Step into",
})

map({ "n", "x" }, "<leader>do", dap.step_out, {
  desc = "Step out",
})

map({ "n", "x" }, "<leader>dq", dap.terminate, {
  desc = "Terminate debug session",
})

map({ "n", "x" }, "<leader>dv", "<cmd>DapViewToggle<CR>", {
  desc = "Toggle debug view",
})

map({ "n", "x" }, "<leader>dr", dap.repl.toggle, {
  desc = "Toggle debug REPL",
})
